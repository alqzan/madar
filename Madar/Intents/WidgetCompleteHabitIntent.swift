import AppIntents
import Foundation
import WidgetKit
import MadarCore
import MadarInbox
import MadarSnapshots

/// A widget may queue the existing blind-write habit command only while its period is current.
struct WidgetCompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل خطوة من العادة"
    static let supportedModes: IntentModes = .background
    @Parameter(title: "العادة") var habitID: String
    init() {}
    init(habitID: UUID) { self.habitID = habitID.uuidString }
    func perform() async throws -> some IntentResult {
        guard let root = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2"), let id = UUID(uuidString: habitID) else { throw WidgetHabitError.openApp }
        let now = Date(), store = SnapshotStore(directory: root.appending(path: "Snapshots", directoryHint: .isDirectory))
        guard let envelope = store.read(HabitShortcutSnapshot.name, as: HabitShortcutSnapshot.self, now: now),
              let day = try? GregorianDay(envelope.dayKey),
              envelope.payload.periodsValidUntil > now, let item = envelope.payload.items.first(where: { $0.id == id }) else { throw WidgetHabitError.openApp }
        let inbox = PendingInbox(directory: root.appending(path: "PendingInbox", directoryHint: .isDirectory))
        try HabitInboxCommandWriter.complete(inbox: inbox, habitID: id, delta: item.step, periodKey: item.periodKey, source: .widget, issuedAt: now, day: day)
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }
}
private enum WidgetHabitError: LocalizedError {
    case openApp
    var errorDescription: String? { "افتح مدار لتحديث يوم العادة ثم أعد المحاولة." }
}
