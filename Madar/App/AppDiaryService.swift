import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarPrayer
import MadarQuran

typealias DiaryDisplayLine = DiaryAutoLine
struct DiaryDisplayDay: Identifiable {
    var id: String { day.description }
    let day: GregorianDay
    let lines: [DiaryDisplayLine]
    let photo: Data?
    let place: String?
    let dayOne: Bool
    var excerpt: String { lines.first(where: { $0.kind == "normal" || $0.kind == "late" })?.text ?? lines.first?.text ?? "صفحة بلا كتابة" }
}
struct DiaryHomeSnapshot {
    let today: GregorianDay
    let selection: DiaryMemorySelection
    let days: [DiaryDisplayDay]
    let todayPage: DiaryDisplayDay
}

@MainActor final class AppDiaryService {
    unowned let app: AppSession
    let clock: @MainActor () -> Date
    init(app: AppSession, clock: @escaping @MainActor () -> Date = { prayerUITestClock(.now) }) { self.app = app; self.clock = clock }
    func authorizeRead() throws {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.notes) ?? app.protectedDataAuthorized else { throw DataError.invalidValue("المذكرات مقفلة") }
    }
    var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }
    var preferredMatch: FirstCalendar {
        if app.string("notes.match") != "auto" { return FirstCalendar(rawValue: app.string("notes.match")) ?? .gregorian }
        let h = HijriCalendar.date(for: clock(), timeZone: app.activePlace.timeZone,
            source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        return h.month == 9 || h.month == 12 || h.month == 10 && h.day <= 3 ? .hijri : .gregorian
    }
    func currentDay() throws -> GregorianDay {
        try authorizeRead()
        let repository = try PrayerRepository(context: ModelContext(app.container)), now = clock(), place = repository.place(at: now)
        let civil = GregorianDay.containing(now, in: place.timeZone)
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: repository.options) }
        return try MadarDay.resolve(instant: now, place: place, boundary: DayBoundary(rawValue: app.string("core.dayStart")) ?? .fajr, prayerDays: days).date
    }
    func home(match: FirstCalendar? = nil) throws -> DiaryHomeSnapshot {
        try authorizeRead()
        let today = try currentDay(), context = ModelContext(app.container)
        let pages = try context.fetch(FetchDescriptor<DayPage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let entries = try context.fetch(FetchDescriptor<Entry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        var photoDescriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })
        photoDescriptor.propertiesToFetch = [\.id]
        let photos = Set(try context.fetch(photoDescriptor).map(\.id))
        let keys = Set(pages.map(\.dayKey) + entries.map(\.dayKey))
        let facts = keys.compactMap { key -> DiaryMemoryDay? in
            guard let day = try? GregorianDay(key) else { return nil }
            let page = pages.filter { $0.dayKey == key }.max { $0.updatedAt < $1.updatedAt }
            let written = entries.filter { $0.dayKey == key }
            return .init(day: day, hasWriting: written.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                hasPhoto: page?.photoMediaID.map { photos.contains($0) } == true || written.contains { !photos.isDisjoint(with: $0.attachmentMediaIDs) }, dayOne: page?.origin == "dayOne", hidden: page?.hiddenFromMemories ?? false)
        }
        let selection = DiaryMemories.select(days: facts, today: today,
            match: match ?? preferredMatch,
            includeDayOne: app.bool("notes.includeDayOne"), yearsBack: app.values["notes.yearsBack"]?.number.map(Int.init),
            noMemory: app.string("notes.noMemory"), zone: app.activePlace.timeZone,
            hijriSource: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
        let recent = facts.map(\.day).filter { $0 < today }.sorted(by: >).prefix(5)
        let visible = Set(selection.days + Array(recent))
        return try .init(today: today, selection: selection, days: visible.sorted(by: >).map { try self.day($0) }, todayPage: day(today))
    }
    func day(_ day: GregorianDay) throws -> DiaryDisplayDay {
        try authorizeRead()
        let context = ModelContext(app.container), key = day.description
        let entries = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.eventAt)]))
        let page = try context.fetch(FetchDescriptor<DayPage>(predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil })).max { $0.updatedAt < $1.updatedAt }
        var lines = entries.map { DiaryDisplayLine(id: $0.id.uuidString, at: $0.eventAt, text: $0.text, kind: $0.ink) }
        let margins = try context.fetch(FetchDescriptor<MarginNote>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        for margin in margins where margin.targetDayKey == key || margin.writtenDayKey == key {
            let text = margin.targetDayKey == key ? margin.text : "كتبت في هامش " + dateTitle(try GregorianDay(margin.targetDayKey), calendar: .gregorian) + ": " + margin.text
            lines.append(.init(id: "margin." + margin.id.uuidString, at: margin.writtenAt, text: text, kind: "margin"))
        }
        let frozen = try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.diaryAutoLines." + key && $0.deletedAt == nil && $0.mergedInto == nil }
        do {
            let auto: [DiaryDisplayLine]
            if let frozen { auto = try JSONDecoder().decode([DiaryDisplayLine].self, from: frozen.valueJSON) }
            else { auto = try DiaryLineRenderer.live(day: day, context: context) }
            let enabled = app.values["notes.autoLines"]?.object ?? [:]
            lines += auto.filter { enabled[$0.kind] == .bool(true) }
        }
        var photo: Data?
        if app.bool("notes.showPhoto") {
            for id in (page?.photoMediaID.map { [$0] } ?? []) + entries.flatMap(\.attachmentMediaIDs) {
                if let item = try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id && $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })).first {
                    photo = item.data; break
                }
            }
        }
        return .init(day: day, lines: lines.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }, photo: photo,
            place: app.bool("notes.showPlace") ? entries.compactMap(\.place).first : nil, dayOne: page?.origin == "dayOne")
    }
    func dateTitle(_ day: GregorianDay, calendar: FirstCalendar) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA@numbers=" + (app.string("core.numerals") == "western" ? "latn" : "arab"))
        formatter.calendar = Calendar(identifier: calendar == .gregorian ? .gregorian : .islamicUmmAlQura)
        formatter.timeZone = app.activePlace.timeZone; formatter.dateFormat = "d MMMM yyyy"
        let offset = calendar == .hijri && app.string("core.hijriSource") == "sighting" ? Int(app.number("core.hijriOffset")) : 0
        return formatter.string(from: day.adding(days: offset).date(in: app.activePlace.timeZone).addingTimeInterval(12*3600))
    }
    func prepareClosedDay(_ day: GregorianDay) async throws {
        try authorizeRead()
        guard day < (try currentDay()) else { return }
        let key = "sys.diaryAutoLines." + day.description
        let exists = try ModelContext(app.container).fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key && $0.deletedAt == nil && $0.mergedInto == nil })).first != nil
        if !exists { try await app.executeDiaryCommand("diary.freezeDay", payload: ["dayKey": .string(day.description)]) }
    }
    func time(_ at: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: app.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = app.activePlace.timeZone; formatter.dateFormat = "h:mm a"; return formatter.string(from: at)
    }
    func monthTitle(_ day: GregorianDay) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: app.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        f.calendar = Calendar(identifier: .gregorian); f.timeZone = app.activePlace.timeZone; f.dateFormat = "MMMM yyyy"
        return f.string(from: day.date(in: app.activePlace.timeZone))
    }
    func weekday(_ day: GregorianDay) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "ar_SA"); f.calendar = Calendar(identifier: .gregorian)
        f.timeZone = app.activePlace.timeZone; f.dateFormat = "EEEE"; return f.string(from: day.date(in: app.activePlace.timeZone))
    }
    func comparisons(since day: GregorianDay) throws -> [(String, String)] {
        try authorizeRead()
        let context = ModelContext(app.container), today = try currentDay()
        let metrics = app.values["notes.sinceMetrics"]?.array?.compactMap(\.string) ?? []
        var result: [(String, String)] = []
        if metrics.contains("sadr") {
            let rows = try context.fetch(FetchDescriptor<HifzSession>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.kind == "hifz" && $0.dayKey <= today.description }
            if let first = rows.map(\.dayKey).min(), first <= day.description {
                let catalog = try QuranResources.catalog()
                func count(through key: String) throws -> Int {
                    let facts = try rows.filter { $0.dayKey <= key }.map { row in QuranCoverageSession(id: row.id.uuidString, kind: .hifz, ayahs: try QuranAyahRange(first: row.fromAyah, last: row.toAyah), endedAt: row.endedAt) }
                    return try QuranCoverageEngine.summarize(sessions: facts, catalog: catalog).completedPages.count
                }
                result.append(("في صدرك", digits.string(try count(through: day.description)) + " ← " + digits.string(try count(through: today.description)) + " وجهًا"))
            } else { result.append(("في صدرك", "لم يكن مدار يسجّل هذا بعد")) }
        }
        if metrics.contains("fajrJamaah") {
            let first = try PrayerRepository(context: context).tracking(at: clock()).day
            let logs = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.prayer == "fajr" && $0.status == "jamaah" }
            func ratio(through end: GregorianDay) -> String {
                guard end >= first else { return "لم يكن مدار يسجّل هذا بعد" }
                let start = max(first, end.adding(days: -29)), keys = Set(logs.filter { $0.dayKey >= start.description && $0.dayKey <= end.description }.map(\.dayKey))
                var count = 0, date = start
                while date <= end { count += 1; date = date.adding(days: 1) }
                return digits.string(keys.count) + " من " + digits.string(count) + " يومًا مسجّلًا"
            }
            result.append(("الفجر جماعة", ratio(through: day) + " ← " + ratio(through: today)))
        }
        return result
    }
}
