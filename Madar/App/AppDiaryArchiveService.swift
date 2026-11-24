import Foundation
import SwiftData
import MadarCore
import MadarData

struct DiaryDaySummary: Identifiable, Sendable {
    var id: String { day.description }
    let day: GregorianDay
    let excerpt: String
    let writings: Int
    let hasSavedContent: Bool
    let photoIDs: [UUID]
    let places: Set<String>
    let projectIDs: Set<UUID>
}
struct DiaryArchiveSnapshot: Sendable {
    let today: GregorianDay
    let days: [DiaryDaySummary]
}
struct DiaryCalendarGrid: Sendable {
    let first: FirstCalendar
    let zone: TimeZone
    let offset: Int
    let weekStart: Int
    var calendar: Calendar { var value = Calendar(identifier: first == .gregorian ? .gregorian : .islamicUmmAlQura); value.timeZone = zone; return value }
    private func shifted(_ day: GregorianDay) -> Date { day.adding(days: first == .hijri ? offset : 0).date(in: zone).addingTimeInterval(12*3600) }
    func parts(_ day: GregorianDay) -> DateComponents { calendar.dateComponents([.year,.month,.day], from: shifted(day)) }
    func days(year: Int, month: Int) -> [GregorianDay] {
        guard let start = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)), let count = calendar.range(of: .day, in: .month, for: start)?.count else { return [] }
        return (0..<count).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }.map { GregorianDay.containing($0, in: zone).adding(days: first == .hijri ? -offset : 0) }
    }
    func leading(_ days: [GregorianDay]) -> Int { guard let day = days.first else { return 0 }; return (calendar.component(.weekday, from: shifted(day)) - weekStart + 7) % 7 }
    func monthName(year: Int, month: Int) -> String {
        guard let date = calendar.date(from: DateComponents(year: year, month: month, day: 1, hour: 12)) else { return "" }
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar_SA"); formatter.calendar = calendar; formatter.timeZone = zone; formatter.dateFormat = "MMMM"; return formatter.string(from: date)
    }
}
extension AppDiaryService {
    var diaryCalendar: DiaryCalendarGrid {
        .init(first: FirstCalendar(rawValue: app.string("notes.calendarFirst")) ?? .gregorian, zone: app.activePlace.timeZone,
            offset: app.string("core.hijriSource") == "sighting" ? min(2,max(-2,Int(app.number("core.hijriOffset")))) : 0, weekStart: app.string("core.weekStart") == "sunday" ? 1 : 7)
    }
    func monthLabels(_ day: GregorianDay) -> MadarDateLabels {
        let grid = diaryCalendar, parts = grid.parts(day)
        guard let year = parts.year, let month = parts.month else { return .init(primary: "", secondary: "") }
        let primary = grid.monthName(year: year, month: month) + " " + digits.string(year)
        return .init(primary: primary, secondary: alternateMonthTitle(year: year, month: month, includeYear: true))
    }
    func alternateMonthTitle(year: Int, month: Int, includeYear: Bool = false) -> String {
        let grid = diaryCalendar, days = grid.days(year: year, month: month)
        guard let first = days.first, let last = days.last else { return "" }
        let a = dateLabels(first, first: grid.first).secondary.split(separator: " ").dropFirst()
        let b = dateLabels(last, first: grid.first).secondary.split(separator: " ").dropFirst()
        guard a.count > 2, b.count > 2 else { return a == b ? a.joined(separator: " ") : a.joined(separator: " ") + " – " + b.joined(separator: " ") }
        let aMonth = a.dropLast(2).joined(separator: " "), bMonth = b.dropLast(2).joined(separator: " ")
        if a.suffix(2) == b.suffix(2) {
            let span = aMonth == bMonth ? aMonth : aMonth + " – " + bMonth
            return includeYear ? span + " " + a.suffix(2).joined(separator: " ") : span
        }
        let start = aMonth + (includeYear ? " " + a.suffix(2).joined(separator: " ") : "")
        let end = bMonth + " " + b.suffix(2).joined(separator: " ")
        return start + " – " + end
    }
    func archive() throws -> DiaryArchiveSnapshot {
        try authorizeRead()
        let days = try Self.archiveDays(context: ModelContext(app.container))
        return try .init(today: currentDay(), days: days)
    }
    /// The same read without holding the main actor: the fetches and grouping use a separate context.
    func archiveOffMain() async throws -> DiaryArchiveSnapshot {
        try authorizeRead()
        let generation = app.storeGeneration, container = app.container
        let today = try await currentDayOffMain()
        let days = try await Self.readArchiveDays(container: container, range: nil)
        try authorizeRead()
        try Task.checkCancellation()
        guard app.storeGeneration == generation, app.container === container else { throw CancellationError() }
        return .init(today: today, days: days)
    }

    func archiveDays(in range: ClosedRange<GregorianDay>) throws -> [DiaryDaySummary] {
        try authorizeRead()
        return try Self.archiveDays(context: ModelContext(app.container), range: range)
    }

    func archiveDaysOffMain(in range: ClosedRange<GregorianDay>) async throws -> [DiaryDaySummary] {
        try authorizeRead()
        let generation = app.storeGeneration, container = app.container
        let days = try await Self.readArchiveDays(container: container, range: range)
        try authorizeRead()
        try Task.checkCancellation()
        guard app.storeGeneration == generation, app.container === container else { throw CancellationError() }
        return days
    }

    @concurrent private static func readArchiveDays(container: ModelContainer, range: ClosedRange<GregorianDay>?) async throws -> [DiaryDaySummary] {
        try archiveDays(context: ModelContext(container), range: range)
    }

    nonisolated private static func archiveDays(context: ModelContext, range: ClosedRange<GregorianDay>? = nil) throws -> [DiaryDaySummary] {
        try Task.checkCancellation()
        let first = range?.lowerBound.description ?? "", last = range?.upperBound.description ?? "9999-99-99"
        let entries = Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate {
            $0.deletedAt == nil && $0.mergedInto == nil && $0.dayKey >= first && $0.dayKey <= last
        }, sortBy: [SortDescriptor(\.eventAt)])))
        let pages = try context.fetch(FetchDescriptor<DayPage>(predicate: #Predicate {
            $0.deletedAt == nil && $0.mergedInto == nil && $0.dayKey >= first && $0.dayKey <= last
        }))
        let margins = try context.fetch(FetchDescriptor<MarginNote>(predicate: #Predicate {
            $0.deletedAt == nil && $0.mergedInto == nil && $0.writtenDayKey >= first && $0.writtenDayKey <= last
        }))
        let niyyas = try context.fetch(FetchDescriptor<Niyya>(predicate: #Predicate {
            $0.deletedAt == nil && $0.mergedInto == nil && $0.dayKey >= first && $0.dayKey <= last
        }))
        let mediaKinds: [UUID: String]
        if range != nil {
            let referenced = Set(entries.compactMap(\.mediaID) + entries.flatMap(\.attachmentMediaIDs) + pages.compactMap(\.photoMediaID))
            mediaKinds = try archiveMediaKinds(context: context, referenced: Array(referenced))
        } else {
            mediaKinds = try archiveMediaKinds(context: context, referenced: nil)
        }
        let entriesByDay = Dictionary(grouping: entries, by: \.dayKey)
        let pagesByDay = Dictionary(grouping: pages, by: \.dayKey)
        let marginsByDay = Dictionary(grouping: margins, by: \.writtenDayKey)
        let intentionsByDay = Dictionary(grouping: niyyas, by: \.dayKey)
        let pagesWithContent = pages.filter {
            $0.photoMediaID != nil || !($0.questionAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
        let keys = Set(entries.map(\.dayKey) + pagesWithContent.map(\.dayKey) + margins.map(\.writtenDayKey) + niyyas.map(\.dayKey))
        let days = try keys.compactMap { key -> DiaryDaySummary? in
            try Task.checkCancellation()
            guard let day = try? GregorianDay(key) else { return nil }
            let rows = entriesByDay[key] ?? []
            let pageRows = pagesByDay[key] ?? []
            let written = rows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let linkedMediaIDs = Set(rows.compactMap(\.mediaID) + rows.flatMap(\.attachmentMediaIDs) + pageRows.compactMap(\.photoMediaID))
                .filter { mediaKinds[$0] != nil }
            let photoIDs = linkedMediaIDs.filter { mediaKinds[$0] == "photo" }
            let notes = marginsByDay[key] ?? []
            let intentions = intentionsByDay[key] ?? []
            let answerExists = pageRows.contains {
                !($0.questionAnswer ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
            let writings = written.count + notes.count + intentions.count
            let hasSavedContent = writings > 0 || !linkedMediaIDs.isEmpty || answerExists
            let fallback: String
            if !photoIDs.isEmpty { fallback = "صورة من هذا اليوم" }
            else if linkedMediaIDs.contains(where: { mediaKinds[$0] == "audio" }) { fallback = "تسجيل صوتي محفوظ من هذا اليوم" }
            else if !linkedMediaIDs.isEmpty { fallback = "مرفق محفوظ من هذا اليوم" }
            else if answerExists { fallback = "إجابة محفوظة من هذا اليوم" }
            else { fallback = "صفحة من يومك" }
            // The newest line written (by when it was written, not by the moment it describes: a line added «بعد» an earlier one sits in the middle of the day); the user's own lines come before the app's.
            let newest=(written.filter{["normal","late","ghad"].contains($0.ink)}.max{$0.createdAt<$1.createdAt}) ?? written.max{$0.createdAt<$1.createdAt}
            let excerpt:String=newest.map{ $0.textFormat == "markdown" ? DayOneMarkdown.plain($0.text) : $0.text } ?? intentions.last?.text ?? notes.last?.text ?? fallback
            return DiaryDaySummary(day: day, excerpt: excerpt, writings: writings, hasSavedContent: hasSavedContent,
                photoIDs: photoIDs.sorted { $0.uuidString < $1.uuidString }, places: Set(rows.compactMap(\.place)),
                projectIDs: Set(rows.compactMap(\.projectID)))
        }.sorted { $0.day > $1.day }
        return days
    }

    nonisolated private static func archiveMediaKinds(context: ModelContext, referenced: [UUID]?) throws -> [UUID: String] {
        var kinds: [UUID: String] = [:]
        func read(_ predicate: Predicate<Media>) throws {
            try Task.checkCancellation()
            var descriptor = FetchDescriptor<Media>(predicate: predicate, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
            descriptor.propertiesToFetch = [\.id, \.kind, \.updatedAt]
            for media in try context.fetch(descriptor) where kinds[media.id] == nil { kinds[media.id] = media.kind }
        }
        if let referenced {
            for start in stride(from: 0, to: referenced.count, by: 400) {
                let batch = Array(referenced[start..<min(start + 400, referenced.count)])
                try read(#Predicate { batch.contains($0.id) && $0.state != "missing" && $0.deletedAt == nil && $0.mergedInto == nil })
            }
        } else {
            try read(#Predicate { $0.state != "missing" && $0.deletedAt == nil && $0.mergedInto == nil })
        }
        return kinds
    }
    func archivePhoto(_ id: UUID) throws -> Data? {
        try authorizeRead()
        return try ModelContext(app.container).fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id && $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })).first?.data
    }
}
