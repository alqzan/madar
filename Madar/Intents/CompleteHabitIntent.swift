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

    static func snapshot(now: Date = .now) -> HabitShortcutSnapshot? {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else { return nil }
        return SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
            .read(HabitShortcutSnapshot.name, as: HabitShortcutSnapshot.self, now: now)?.payload
    }
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
        guard let snapshot = HabitShortcutEntity.snapshot(now: now),
              let item = snapshot.items.first(where: { $0.id == habit.id }) else { throw CompleteHabitIntentError.notAvailable }
        if snapshot.periodsValidUntil <= now {
            try await continueInForeground("افتح مدار ليسجّلها في يومها الجديد.", alwaysConfirm: false)
            await MadarIntentHandoff.shared.submit(.completeHabit(habitID: item.id, id: UUID()))
            return .result(dialog: "سُجّلت.")
        }
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else {
            throw CompleteHabitIntentError.openMadar
        }
        let inbox = PendingInbox(directory: group.appending(path: "PendingInbox", directoryHint: .isDirectory))
        do { try HabitInboxCommandWriter.complete(inbox: inbox, habitID: item.id, delta: item.step, periodKey: item.periodKey, source: .siri, issuedAt: now) }
        catch { throw CompleteHabitIntentError.openMadar }
        await MainActor.run { NotificationCenter.default.post(name: .madarInboxChanged, object: nil) }
        WidgetCenter.shared.reloadAllTimelines()
        return .result(dialog: "سُجّلت.")
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
