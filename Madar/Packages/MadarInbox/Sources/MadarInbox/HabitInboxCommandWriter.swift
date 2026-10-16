import Foundation
import MadarCore

public enum HabitInboxCommandError: Error, Equatable, Sendable { case invalidDelta, missingPeriod }

/// Builds a §16 blindWrite habit completion for Shortcuts and widgets without opening the store.
/// The period comes from the app-published snapshot, so a late drain is refused rather than misdated.
public enum HabitInboxCommandWriter {
    @discardableResult
    public static func complete(inbox: PendingInbox, habitID: UUID, delta: Int, periodKey: String,
                                source: CommandSource, issuedAt: Date = .now) throws -> InboxTicket {
        guard delta > 0, delta <= 100_000 else { throw HabitInboxCommandError.invalidDelta }
        guard !periodKey.isEmpty else { throw HabitInboxCommandError.missingPeriod }
        let payload: JSONValue = .object(["id": .string(habitID.uuidString), "delta": .number(Double(delta)), "periodKey": .string(periodKey)])
        let command = CommandEnvelope(name: "habit.complete", payload: payload, source: source, issuedAt: issuedAt)
        return try inbox.enqueue(.init(expectedGenerationID: try inbox.currentGeneration()?.generationID, command: command))
    }
}
