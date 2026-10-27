import Foundation
import MadarCore

public enum HabitInboxCommandError: Error, Equatable, Sendable { case invalidDelta, missingPeriod }

/// Builds a §16 blindWrite habit completion for Shortcuts and widgets without opening the store.
/// New producers freeze the snapshot's day too: a weekly/monthly period alone cannot identify the tap day.
/// Legacy period-only producers retain their existing rejection behavior when a period closes.
public enum HabitInboxCommandWriter {
    @discardableResult
    public static func complete(inbox: PendingInbox, habitID: UUID, delta: Int, periodKey: String,
                                source: CommandSource, issuedAt: Date = .now, day: GregorianDay? = nil) throws -> InboxTicket {
        guard delta > 0, delta <= 100_000 else { throw HabitInboxCommandError.invalidDelta }
        guard !periodKey.isEmpty else { throw HabitInboxCommandError.missingPeriod }
        var fields: [String: JSONValue] = ["id": .string(habitID.uuidString), "delta": .number(Double(delta))]
        if let day { fields["day"] = .string(day.description) } else { fields["periodKey"] = .string(periodKey) }
        let payload: JSONValue = .object(fields)
        let command = CommandEnvelope(name: "habit.complete", payload: payload, source: source, issuedAt: issuedAt)
        return try inbox.enqueue(.init(expectedGenerationID: try inbox.currentGeneration()?.generationID, command: command))
    }
}
