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
    var photoID: UUID? = nil
    var media: [DiaryDisplayMedia] = []
    var marginDays: [String: GregorianDay] = [:]
    /// RD1: line id → the text it was first written with, for lines edited after the freeze.
    var originals: [String: String] = [:]
    /// Written lines the owner may edit (text entries; voice keeps its own transcript editor).
    var editable: Set<String> = []
    /// Current text-only diary lines whose full revision family can be deleted and restored safely.
    var deletable: Set<String> = []
    /// The first line with words: an imported photo-only entry has an empty text and must not hide the next line.
    var excerpt: String {
        let written = lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return written.first(where: { $0.kind == "normal" || $0.kind == "late" })?.text ?? written.first?.text ?? "صفحة بلا كتابة"
    }
    /// Photos an import referenced but did not contain (N01: shown as missing, never invented).
    var missingPhotos: Int { media.filter { $0.kind == "missing" && $0.contentType == "photo" }.count }
}
struct DiaryHomeSnapshot {
    let today: GregorianDay
    let selection: DiaryMemorySelection
    let days: [DiaryDisplayDay]
    let echoes: [DiaryEcho]
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
    func hasWelcomed() throws -> Bool {
        try authorizeRead()
        let key = "sys.diaryWelcomeSeen"
        let context = ModelContext(app.container)
        if try context.fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key && $0.deletedAt == nil && $0.mergedInto == nil })).first?.valueJSON == Data("true".utf8) { return true }
        // An imported/restored diary already belongs to its writer. Open it without
        // an introduction or changing the saved source choices and calendar match.
        var existing = FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })
        existing.fetchLimit = 1
        existing.propertiesToFetch = [\.id]
        return try !context.fetch(existing).isEmpty
    }
    func currentDay() throws -> GregorianDay {
        try authorizeRead()
        return try diaryDay()
    }
    /// V12: the diary's day without a read authorization; reminder scheduling runs while the notes are locked.
    func diaryDay() throws -> GregorianDay {
        let repository = try PrayerRepository(context: ModelContext(app.container)), now = clock(), place = repository.place(at: now), options = repository.calculationOptions(at: now)
        let civil = GregorianDay.containing(now, in: place.timeZone)
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: options) }
        return try MadarDay.resolve(instant: now, place: place, boundary: DayBoundary(rawValue: app.string("core.dayStart")) ?? .fajr, prayerDays: days).date
    }
    func home(match: FirstCalendar? = nil) throws -> DiaryHomeSnapshot {
        try authorizeRead()
        let today = try currentDay(), facts = try memoryFacts()
        let selection = memorySelection(facts: facts, today: today, match: match)
        let recent = facts.map(\.day).filter { $0 < today }.sorted(by: >).prefix(5)
        let echoes = DiaryMemories.echoes(days: facts, today: today, includeDayOne: app.bool("notes.includeDayOne"), zone: app.activePlace.timeZone)
        let visible = Set(selection.days + Array(recent) + echoes.compactMap(\.day))
        return try .init(today: today, selection: selection, days: visible.sorted(by: >).map { try self.day($0) }, echoes: echoes, todayPage: day(today))
    }
    /// Memory facts are day keys and booleans only (written, photo, Day One, hidden); no text leaves this function.
    func memoryFacts() throws -> [DiaryMemoryDay] {
        let context = ModelContext(app.container)
        let pages = try context.fetch(FetchDescriptor<DayPage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let entries = Self.visible(try context.fetch(FetchDescriptor<Entry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil })
        var photoDescriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })
        photoDescriptor.propertiesToFetch = [\.id]
        let photos = Set(try context.fetch(photoDescriptor).map(\.id))
        let niyyas=try context.fetch(FetchDescriptor<Niyya>(predicate:#Predicate{$0.deletedAt==nil && $0.mergedInto==nil}))
        let keys = Set(pages.map(\.dayKey) + entries.map(\.dayKey)+niyyas.map(\.dayKey))
        return keys.compactMap { key -> DiaryMemoryDay? in
            guard let day = try? GregorianDay(key) else { return nil }
            let page = pages.filter { $0.dayKey == key }.max { $0.updatedAt < $1.updatedAt }
            let written = entries.filter { $0.dayKey == key }
            return .init(day: day, hasWriting: niyyas.contains{$0.dayKey==key} || written.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty },
                hasPhoto: page?.photoMediaID.map { photos.contains($0) } == true || written.contains { !photos.isDisjoint(with: $0.attachmentMediaIDs) }, dayOne: page?.origin == "dayOne", hidden: page?.hiddenFromMemories ?? false)
        }
    }
    func memorySelection(facts: [DiaryMemoryDay], today: GregorianDay, match: FirstCalendar? = nil) -> DiaryMemorySelection {
        DiaryMemories.select(days: facts, today: today,
            match: match ?? preferredMatch,
            includeDayOne: app.bool("notes.includeDayOne"), yearsBack: app.values["notes.yearsBack"]?.number.map(Int.init),
            noMemory: app.string("notes.noMemory"), zone: app.activePlace.timeZone,
            hijriSource: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura, sightingOffset: Int(app.number("core.hijriOffset")))
    }
    func day(_ day: GregorianDay) throws -> DiaryDisplayDay {
        try authorizeRead()
        let context = ModelContext(app.container), key = day.description
        let eventPlaces = try PrayerRepository(context: context)
        func eventTimeZoneID(_ stored: String?, at instant: Date) -> String {
            if let stored, TimeZone(identifier: stored) != nil { return stored }
            return eventPlaces.place(at: instant).timeZoneID
        }
        let all = try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.eventAt)]))
        let chains = Self.revisionChains(all), entries = all.filter { chains.heads.contains($0.id) }
        let deletable = Set(entries.filter { head in
            guard head.source != "autoPinned", ["normal", "late", "ghad"].contains(head.ink) else { return false }
            var family: Set<UUID> = [head.id]
            var changed = true
            while changed {
                changed = false
                for row in all {
                    let parent = row.source == "revision" ? row.sourceID.flatMap(UUID.init(uuidString:)) : nil
                    if family.contains(row.id) || parent.map(family.contains) == true {
                        if family.insert(row.id).inserted { changed = true }
                        if let parent, all.contains(where: { $0.id == parent }), family.insert(parent).inserted { changed = true }
                    }
                }
            }
            return all.filter { family.contains($0.id) }.allSatisfy { $0.source != "autoPinned" }
        }.map(\.id.uuidString))
        let page = try context.fetch(FetchDescriptor<DayPage>(predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil })).max { $0.updatedAt < $1.updatedAt }
        var lines = entries.map { row in
            let markdown = row.textFormat == "markdown"
            return DiaryDisplayLine(id: row.id.uuidString, at: row.eventAt, text: markdown ? DayOneMarkdown.readable(row.text) : row.text, kind: row.ink,
                                    tzID: eventTimeZoneID(row.tzID, at: row.eventAt), markdown: markdown ? true : nil)
        }
        for niyya in try context.fetch(FetchDescriptor<Niyya>(predicate:#Predicate{$0.dayKey==key && $0.deletedAt==nil && $0.mergedInto==nil})) {lines.append(.init(id:niyya.id.uuidString,at:niyya.createdAt,text:niyya.text,kind:"intention",tzID:eventTimeZoneID(nil,at:niyya.createdAt)))}
        let margins = try context.fetch(FetchDescriptor<MarginNote>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        for margin in margins where margin.targetDayKey == key || margin.writtenDayKey == key {
            let text = margin.targetDayKey == key ? margin.text : "كتبت في هامش " + dateTitle(try GregorianDay(margin.targetDayKey), calendar: .gregorian) + ": " + margin.text
            lines.append(.init(id: "margin." + margin.id.uuidString, at: margin.writtenAt, text: text, kind: "margin",
                               tzID: eventTimeZoneID(margin.tzID, at: margin.writtenAt)))
        }
        let frozen = try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.diaryAutoLines." + key && $0.deletedAt == nil && $0.mergedInto == nil }
        do {
            let auto: [DiaryDisplayLine]
            if let frozen { auto = try JSONDecoder().decode([DiaryDisplayLine].self, from: frozen.valueJSON) }
            else { auto = try DiaryLineRenderer.live(day: day, context: context) }
            let enabled = app.values["notes.autoLines"]?.object ?? [:]
            lines += auto.filter { enabled[$0.kind] == .bool(true) }.map { line in
                var dated = line
                dated.tzID = eventTimeZoneID(line.tzID, at: line.at)
                return dated
            }
        }
        let mediaLinks = entries.flatMap { entry in (entry.attachmentMediaIDs + (entry.mediaID.map { [$0] } ?? [])).map { (entry.id.uuidString, $0) } }
        var attachments: [DiaryDisplayMedia] = []
        for (entry, id) in mediaLinks {
            if let row = try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil })).first {
                if let data = row.data { attachments.append(.init(id: row.id, entryID: entry, kind: row.kind, contentType: row.contentType, data: data, duration: row.durationS, assetID: DiaryPhotoLink.assetID(sourceID: row.sourceID))) }
                // N01: an attachment the export did not contain is shown as missing, never invented.
                else if row.state == "missing" { attachments.append(.init(id: row.id, entryID: entry, kind: "missing", contentType: row.kind, data: Data(), duration: nil)) }
            }
        }
        var photo: Data?
        var photoID: UUID?
        if app.bool("notes.showPhoto") {
            for id in (page?.photoMediaID.map { [$0] } ?? []) + entries.flatMap(\.attachmentMediaIDs) {
                if let item = try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id && $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })).first, item.data != nil {
                    photo = item.data; photoID = id; break
                }
            }
        }
        return .init(day: day, lines: lines.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }, photo: photo,
            place: app.bool("notes.showPlace") ? entries.compactMap(\.place).first : nil, dayOne: page?.origin == "dayOne", photoID: photoID, media: attachments, marginDays: Dictionary(uniqueKeysWithValues: margins.compactMap { margin in
                guard let day = try? GregorianDay(margin.writtenDayKey) else { return nil }; return ("margin." + margin.id.uuidString, day)
            }), originals: Dictionary(uniqueKeysWithValues: chains.originals.compactMap { head, root in all.first { $0.id == root }.map { (head.uuidString, $0.text) } }),
            editable: Set(entries.filter { $0.mediaID == nil && $0.source != "autoPinned" && ["normal", "late", "ghad"].contains($0.ink) }.map(\.id.uuidString)),
            deletable: deletable)
    }
    func dateTitle(_ day: GregorianDay, calendar: FirstCalendar) -> String {
        let labels = dateLabels(day, first: calendar)
        let suffix = calendar == .hijri ? " هـ" : " م"
        return String(labels.primary.dropLast(suffix.count))
    }

    func prepareClosedDay(_ day: GregorianDay) async throws {
        try authorizeRead()
        guard day < (try currentDay()) else { return }
        let key = "sys.diaryAutoLines." + day.description
        let exists = try ModelContext(app.container).fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key && $0.deletedAt == nil && $0.mergedInto == nil })).first != nil
        if !exists { try await app.executeDiaryCommand("diary.freezeDay", payload: ["dayKey": .string(day.description)]) }
    }
    func time(_ at: Date, zone: String? = nil) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: app.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = zone.flatMap(TimeZone.init(identifier:)) ?? app.activePlace.timeZone; formatter.dateFormat = "h:mm a"; return formatter.string(from: at)
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
            let logs = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.prayer == "fajr" && ["jamaah", "alone", "qada", "missed"].contains($0.status) }
            func ratio(through end: GregorianDay) -> String {
                guard end >= first else { return "لم يكن مدار يسجّل هذا بعد" }
                let start = max(first, end.adding(days: -29))
                let window = logs.filter { $0.dayKey >= start.description && $0.dayKey <= end.description }
                let recorded = Set(window.map(\.dayKey)), jamaah = Set(window.filter { $0.status == "jamaah" }.map(\.dayKey))
                guard !recorded.isEmpty else { return "لا تسجيل للفجر في هذه الفترة" }
                return digits.string(jamaah.count) + " من " + digits.string(recorded.count) + " يومًا مسجّلًا"
            }
            result.append(("الفجر جماعة", ratio(through: day) + " ← " + ratio(through: today)))
        }
        return result
    }
    func distance(_ day: GregorianDay, _ today: GregorianDay) -> String {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: day.date(in: app.activePlace.timeZone), to: today.date(in: app.activePlace.timeZone))
        func unit(_ count: Int, _ one: String, _ two: String, _ few: String, _ many: String) -> String? {
            guard count > 0 else { return nil }
            if count == 1 { return one }; if count == 2 { return two }
            return digits.string(count) + " " + ((3...10).contains(count % 100) ? few : many)
        }
        let values = [unit(parts.year ?? 0, "سنة", "سنتين", "سنوات", "سنة"), unit(parts.month ?? 0, "شهر", "شهرين", "أشهر", "شهر"), unit(parts.day ?? 0, "يوم", "يومين", "أيام", "يوم")].compactMap { $0 }
        return values.isEmpty ? "اليوم" : "قبل " + values.joined(separator: " و")
    }

}

extension AppDiaryService {
    /// RD1 single choke point: every diary reader shows only the newest row of an edited line.
    static func revisionChains(_ entries: [Entry]) -> DiaryRevisionChains {
        DiaryRevisionChains(entries.map { .init(id: $0.id, replaces: $0.source == "revision" ? $0.sourceID.flatMap(UUID.init(uuidString:)) : nil) })
    }
    static func visible(_ entries: [Entry]) -> [Entry] { let chains = revisionChains(entries); return entries.filter { chains.heads.contains($0.id) } }
    func edit(_ line: String, text: String) async throws {
        try await app.executeDiaryCommand("diary.editEntry", payload: ["entryID": .string(line), "revisionID": .string(UUID().uuidString), "text": .string(text)])
    }
}
