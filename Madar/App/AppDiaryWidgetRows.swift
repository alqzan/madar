import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarSnapshots

extension AppSession {
    /// RD7 (owner, 16 Oct): diary text reaches a widget only after the owner turns on `notes.widgetContent`, and never
    /// under the whole-app lock (the caller passes no rows then). Each row is shown `.privacySensitive()`.
    func diaryWidgetRows(today: GregorianDay) -> [RoomWidgetSnapshot.Row] {
        let context = ModelContext(container), route = BuiltRoomWidget.diaryWrite.route
        func excerpt(_ text: String) -> String {
            let line = text.split(whereSeparator: \.isNewline).first.map(String.init)?.trimmingCharacters(in: .whitespaces) ?? ""
            return line.count > 140 ? String(line.prefix(139)) + "…" : line
        }
        var rows: [RoomWidgetSnapshot.Row] = []
        let key = today.description
        if let niyya = (try? context.fetch(FetchDescriptor<Niyya>(predicate: #Predicate { $0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.order), SortDescriptor(\.createdAt)])))?.first(where: { !excerpt($0.text).isEmpty }) {
            rows.append(.init(id: "intention", title: "النيّة", value: excerpt(niyya.text), route: "madar://notes/today"))
        }
        let diary = AppDiaryService(app: self)
        if let facts = try? diary.memoryFacts(), let day = diary.memorySelection(facts: facts, today: today).days.first,
           let page = try? diary.day(day), let line = page.lines.first(where: { ["normal", "late", "intention"].contains($0.kind) && !excerpt($0.text).isEmpty }) {
            let labels = dateLabels(day)
            rows.append(.init(id: "thatDay", title: "في مثل هذا اليوم", value: excerpt(line.text), detail: labels.primary, secondDate: labels.secondary, route: "madar://notes"))
        }
        let entries = AppDiaryService.visible((try? context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))) ?? [])
        if let last = entries.filter({ !excerpt($0.text).isEmpty }).max(by: { $0.eventAt < $1.eventAt }), let day = try? GregorianDay(last.dayKey) {
            let labels = dateLabels(day)
            rows.append(.init(id: "lastLine", title: "آخر سطر", value: excerpt(last.text), detail: labels.primary, secondDate: labels.secondary, route: route))
        }
        return rows
    }
}
