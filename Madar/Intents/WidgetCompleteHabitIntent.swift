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
        try Self.enqueue(habitID: id, root: root, now: Date())
        WidgetCenter.shared.reloadAllTimelines()
        return .result()
    }

    static func enqueue(habitID id: UUID, root: URL, now: Date) throws {
        let store = SnapshotStore(directory: root.appending(path: "Snapshots", directoryHint: .isDirectory))
        let inbox = PendingInbox(directory: root.appending(path: "PendingInbox", directoryHint: .isDirectory))
        try store.withExclusiveAccess(for: WidgetCatalogSnapshot.valuesName) {
            guard let values = store.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: now),
                  !values.payload.locked,
                  let day = try? GregorianDay(values.dayKey),
                  let shortcut = store.read(HabitShortcutSnapshot.name, as: HabitShortcutSnapshot.self, now: now),
                  shortcut.dayKey == values.dayKey,
                  shortcut.payload.periodsValidUntil > now,
                  let item = shortcut.payload.items.first(where: { $0.id == id }), !item.done,
                  values.payload.configs.contains(where: { config in config.rows.contains(where: { $0.habitID == id }) }) else {
                throw WidgetHabitError.openApp
            }

            var claimed = values
            claimed.payload.hideHabitActions(for: [id])
            do { try store.write(claimed) }
            catch { try? store.write(values); throw error }
            do {
                try HabitInboxCommandWriter.complete(inbox: inbox, habitID: id, delta: item.step,
                                                     periodKey: item.periodKey, source: .widget,
                                                     issuedAt: now, day: day)
            } catch {
                // enqueue can fail after atomic publication (for example, a directory fsync
                // failure). Keep the action claimed whenever its command is visible in the inbox.
                do {
                    let pendingIDs = try inbox.unacknowledgedHabitIDs()
                    if !pendingIDs.contains(id) { try store.write(values) }
                }
                catch { /* An unreadable inbox is uncertain; keep the action claimed. */ }
                throw error
            }
        }
    }
}
private enum WidgetHabitError: LocalizedError {
    case openApp
    var errorDescription: String? { "افتح مدار لتحديث يوم العادة ثم أعد المحاولة." }
}
