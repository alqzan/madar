import Foundation
import SwiftData
import MadarCore
import MadarData

struct DiaryDaySummary: Identifiable {
    var id: String { day.description }
    let day: GregorianDay
    let excerpt: String
    let writings: Int
    let photoIDs: [UUID]
    let places: Set<String>
    let projectIDs: Set<UUID>
}
struct DiaryArchiveSnapshot {
    let today: GregorianDay
    let days: [DiaryDaySummary]
}
struct DiaryCalendarGrid {
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
        let context = ModelContext(app.container)
        let entries = Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.eventAt)])))
        let pages = try context.fetch(FetchDescriptor<DayPage>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        let margins = try context.fetch(FetchDescriptor<MarginNote>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        var descriptor = FetchDescriptor<Media>(predicate: #Predicate { $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil }); descriptor.propertiesToFetch = [\.id]
        let photos = Set(try context.fetch(descriptor).map(\.id))
        let niyyas=try context.fetch(FetchDescriptor<Niyya>(predicate:#Predicate{$0.deletedAt==nil && $0.mergedInto==nil}))
        let grouped = Dictionary(grouping: entries, by: \.dayKey), keys = Set(entries.map(\.dayKey) + pages.filter { $0.photoMediaID != nil || $0.questionAnswer != nil }.map(\.dayKey) + margins.map(\.writtenDayKey)+niyyas.map(\.dayKey))
        let days = keys.compactMap { key -> DiaryDaySummary? in
            guard let day = try? GregorianDay(key) else { return nil }
            let rows = grouped[key] ?? [], written = rows.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            let ids = Set(rows.flatMap(\.attachmentMediaIDs) + pages.filter { $0.dayKey == key }.compactMap(\.photoMediaID)).intersection(photos)
            let notes = margins.filter { $0.writtenDayKey == key }
            let intentions=niyyas.filter{$0.dayKey==key}
            let fallback=ids.isEmpty ? "صفحة من يومك" : "صورة من هذا اليوم"
            let excerpt:String=written.last.map{ $0.textFormat == "markdown" ? DayOneMarkdown.plain($0.text) : $0.text } ?? intentions.last?.text ?? notes.last?.text ?? fallback
            return DiaryDaySummary(day:day,excerpt:excerpt,writings:written.count+notes.count+intentions.count,photoIDs:ids.sorted{$0.uuidString<$1.uuidString},places:Set(rows.compactMap(\.place)),projectIDs:Set(rows.compactMap(\.projectID)))
        }.sorted { $0.day > $1.day }
        return try .init(today: currentDay(), days: days)
    }
    func archivePhoto(_ id: UUID) throws -> Data? {
        try authorizeRead()
        return try ModelContext(app.container).fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.id == id && $0.kind == "photo" && $0.deletedAt == nil && $0.mergedInto == nil })).first?.data
    }
}
