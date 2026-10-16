import Foundation
import MadarCore
import MadarMoney

public enum MoneyInboxError: Error, Equatable, Sendable { case invalidPayload }

/// RA2: producers write only value envelopes. OTP/marketing are discarded BEFORE a file or
/// command receipt can contain their text. The app repeats this check for untrusted producers.
public enum MoneyInboxCommandWriter {
    @discardableResult
    public static func ingest(inbox: PendingInbox, text: String, sender: String? = nil, receivedAt: Date? = nil,
                              commandID: UUID = UUID(), issuedAt: Date = .now) throws -> InboxTicket? {
        var p: [String: JSONValue] = ["text": .string(text)]
        if let sender { p["sender"] = .string(sender) }
        // Freeze the device time at receipt, not at a later app drain.
        if let receivedAt { p["receivedAt"] = .string(ISO8601DateFormatter().string(from: receivedAt)) }
        guard MoneyCommandPayload.validate(name: MoneyCommandPayload.intakeName, payload: p) else { throw MoneyInboxError.invalidPayload }
        switch BankIntake.decision(BankMessageParser.classify(text)) {
        case .discard, .discardWithoutText: return nil
        default: break
        }
        return try enqueue(inbox, name: MoneyCommandPayload.intakeName, payload: p, id: commandID, at: issuedAt)
    }

    @discardableResult
    public static func logExpense(inbox: PendingInbox, amountMinor: Int, currency: String, merchant: String? = nil,
                                  method: String? = nil, commandID: UUID = UUID(), issuedAt: Date = .now) throws -> InboxTicket {
        var p: [String: JSONValue] = ["amountMinor": .string(String(amountMinor)), "currency": .string(currency),
            "eventAt": .string(ISO8601DateFormatter().string(from: issuedAt))]
        if let merchant { p["merchant"] = .string(merchant) }
        if let method { p["method"] = .string(method) }
        guard MoneyCommandPayload.validate(name: "money.logExpense", payload: p) else { throw MoneyInboxError.invalidPayload }
        return try enqueue(inbox, name: "money.logExpense", payload: p, id: commandID, at: issuedAt)
    }

    private static func enqueue(_ inbox: PendingInbox, name: String, payload: [String: JSONValue], id: UUID, at: Date) throws -> InboxTicket {
        try inbox.enqueue(.init(expectedGenerationID: inbox.currentGeneration()?.generationID,
            command: .init(commandID: id, name: name, payload: .object(payload), source: .shortcut, issuedAt: at)))
    }
}
