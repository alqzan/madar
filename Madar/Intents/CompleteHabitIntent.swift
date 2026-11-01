import AppIntents
import Foundation
import MadarCore
import MadarInbox
import MadarSnapshots
import WidgetKit

extension Notification.Name {
    /// Posted in the app process after a Shortcut queued a blind write, so a live session drains it at once.
    static let madarInboxChanged = Notification.Name("madar.inboxChanged")
}

/// A custom habit Siri may complete (never a linked or Health habit; RL4 keeps one fact in its owning room).
struct HabitShortcutEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "عادة")
    static let defaultQuery = HabitShortcutQuery()
    let id: UUID
    let title: String
    let stepTitle: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)", subtitle: "\(stepTitle)") }

    static func envelope(now: Date = .now) -> SnapshotEnvelope<HabitShortcutSnapshot>? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { return nil }
        return SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
            .read(HabitShortcutSnapshot.name, as: HabitShortcutSnapshot.self, now: now)
    }
    static func snapshot(now: Date = .now) -> HabitShortcutSnapshot? { envelope(now: now)?.payload }
}

struct HabitShortcutQuery: EntityStringQuery {
    private func all() -> [HabitShortcutEntity] {
        (HabitShortcutEntity.snapshot()?.items ?? []).map { .init(id: $0.id, title: $0.title, stepTitle: $0.stepTitle) }
    }
    func entities(for identifiers: [UUID]) async throws -> [HabitShortcutEntity] { all().filter { identifiers.contains($0.id) } }
    func suggestedEntities() async throws -> [HabitShortcutEntity] { all() }
    func entities(matching string: String) async throws -> [HabitShortcutEntity] {
        let query = CaptureRouter.fold(string)
        return all().filter { CaptureRouter.fold($0.title).localizedStandardContains(query) }
    }
}

/// §9 CompleteHabitIntent, §16 blindWrite: answers only «سُجّلت», never a count or streak.
/// While today's period is known it goes through the inbox without opening Madar; once the day
/// has turned, Madar opens and records it so the completion is never credited to a closed period.
struct CompleteHabitIntent: AppIntent {
    static let title: LocalizedStringResource = "أتمّ عادة"
    static let description = IntentDescription("يسجّل خطوة واحدة من عادة، كما يفعل زرّها في مدار.")
    static let supportedModes: IntentModes = [.background, .foreground(.dynamic)]

    @Parameter(title: "العادة") var habit: HabitShortcutEntity

    init() {}
    init(habit: HabitShortcutEntity) { self.habit = habit }

    static var parameterSummary: some ParameterSummary { Summary("أتمّ \(\.$habit)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard let envelope = HabitShortcutEntity.envelope(now: now), let day = try? GregorianDay(envelope.dayKey),
              case let snapshot = envelope.payload,
              let item = snapshot.items.first(where: { $0.id == habit.id }) else { throw CompleteHabitIntentError.notAvailable }
        if snapshot.periodsValidUntil <= now {
            try await continueInForeground("افتح مدار ليسجّلها في يومها الجديد.", alwaysConfirm: false)
            let request = MadarIntentRequest.completeHabit(habitID: item.id, id: UUID())
            let applied = await MadarIntentHandoff.shared.submit(request)
            // A held request (locked or still loading) is not yet recorded, and a failed one says why.
            if let failure = await MadarIntentHandoff.shared.takeFailure(request) { return .result(dialog: "\(failure)") }
            return .result(dialog: applied ? "سُجّلت." : "افتح مدار ليكتمل التسجيل.")
        }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else {
            throw CompleteHabitIntentError.openMadar
        }
        do { try Self.enqueue(item: item, day: day, root: group, now: now) }
        catch { throw CompleteHabitIntentError.openMadar }
        await MainActor.run { NotificationCenter.default.post(name: .madarInboxChanged, object: nil) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "حُفظت، وتُسجَّل في مدار حين تفتحه.")
    }

    static func enqueue(item: HabitShortcutSnapshot.Item, day: GregorianDay, root: URL, now: Date) throws {
        let store = SnapshotStore(directory: root.appending(path: "Snapshots", directoryHint: .isDirectory))
        let inbox = PendingInbox(directory: root.appending(path: "PendingInbox", directoryHint: .isDirectory))
        try store.withExclusiveAccess(for: WidgetCatalogSnapshot.valuesName) {
            let previous = store.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: now)
            if let previous {
                var claimed = previous
                claimed.payload.hideHabitActions(for: [item.id])
                do { try store.write(claimed) }
                catch { try? store.write(previous); throw error }
            }
            do {
                try HabitInboxCommandWriter.complete(inbox: inbox, habitID: item.id, delta: item.step,
                                                     periodKey: item.periodKey, source: .siri,
                                                     issuedAt: now, day: day)
            } catch {
                // The inbox can report a directory sync failure after publishing the record.
                do {
                    let pendingIDs = try inbox.unacknowledgedHabitIDs()
                    if !pendingIDs.contains(item.id), let previous { try store.write(previous) }
                } catch { /* An unreadable inbox is uncertain; keep the action claimed. */ }
                throw error
            }
        }
    }
}

private enum CompleteHabitIntentError: LocalizedError {
    case notAvailable, openMadar
    var errorDescription: String? {
        switch self {
        case .notAvailable: "هذه العادة غير متاحة الآن؛ افتح العادات في مدار."
        case .openMadar: "افتح مدار أولًا ثم أعد المحاولة."
        }
    }
}
