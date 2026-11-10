import Foundation
import Testing
import MadarCore
@testable import MadarInbox

/// B2-20: the money Shortcuts write only to the pending inbox; they never open the store (RA2).
struct MoneyInboxCommandWriterTests {
    private func fixture() throws -> PendingInbox {
        let inbox = PendingInbox(directory: FileManager.default.temporaryDirectory.appending(path: "MadarMoneyIntent-\(UUID())"))
        try inbox.publishGeneration(InboxGeneration(generationID: UUID(), acceptsUnstampedDeliveries: false))
        return inbox
    }
    private let instant = Date(timeIntervalSince1970: 1_797_000_000)

    @Test func loggedExpenseIsAStampedShortcutCommandWithItsOwnTime() throws {
        let inbox = try fixture()
        let ticket = try MoneyInboxCommandWriter.logExpense(inbox: inbox, amountMinor: 4250, currency: "SAR", merchant: "قهوة", method: "card", issuedAt: instant)
        let record = try inbox.read(#require(try inbox.claimBatch().first))
        #expect(record.command.commandID == ticket.commandID)
        #expect(record.command.name == "money.logExpense")
        #expect(record.command.source == .shortcut)
        #expect(record.command.issuedAt == instant)
        #expect(record.command.payload == .object([
            "amountMinor": .string("4250"), "currency": .string("SAR"), "merchant": .string("قهوة"), "method": .string("card"),
            "eventAt": .string(ISO8601DateFormatter().string(from: instant))
        ]))
    }

    @Test func anInvalidExpenseIsRefusedBeforeAnythingIsWritten() throws {
        let inbox = try fixture()
        #expect(throws: MoneyInboxError.invalidPayload) { try MoneyInboxCommandWriter.logExpense(inbox: inbox, amountMinor: 0, currency: "SAR") }
        #expect(throws: MoneyInboxError.invalidPayload) { try MoneyInboxCommandWriter.logExpense(inbox: inbox, amountMinor: -5, currency: "SAR") }
        #expect(throws: MoneyInboxError.invalidPayload) { try MoneyInboxCommandWriter.logExpense(inbox: inbox, amountMinor: 100, currency: "SARR") }
        #expect(throws: MoneyInboxError.invalidPayload) { try MoneyInboxCommandWriter.logExpense(inbox: inbox, amountMinor: 100, currency: "SAR", method: "bitcoin") }
        #expect(try inbox.claimBatch().isEmpty)
    }

    @Test func aOneTimeCodeOrAnAdIsNeverStored() throws {
        let inbox = try fixture()
        #expect(try MoneyInboxCommandWriter.ingest(inbox: inbox, text: "رمز التحقق: 482913 لا تشاركه مع أحد") == nil)
        #expect(try MoneyInboxCommandWriter.ingest(inbox: inbox, text: "عرض خاص! خصم حصري على البطاقات. لإلغاء الاشتراك أرسل 1") == nil)
        #expect(try inbox.claimBatch().isEmpty)
    }

    @Test func aMessageWeCannotReadIsKeptForALookWithItsReceiptTime() throws {
        let inbox = try fixture()
        let received = Date(timeIntervalSince1970: 1_796_990_000)
        let ticket = try #require(try MoneyInboxCommandWriter.ingest(inbox: inbox, text: "مرحبًا بك في خدماتنا", sender: "BANK", receivedAt: received, issuedAt: instant))
        let record = try inbox.read(#require(try inbox.claimBatch().first))
        #expect(record.command.commandID == ticket.commandID)
        #expect(record.command.name == "money.ingestBankMessage")
        #expect(record.command.source == .shortcut)
        #expect(record.command.payload == .object([
            "text": .string("مرحبًا بك في خدماتنا"), "sender": .string("BANK"),
            "receivedAt": .string(ISO8601DateFormatter().string(from: received))
        ]))
    }

    @Test func messageLengthIsOneToTwoThousandCharacters() throws {
        let inbox = try fixture()
        #expect(throws: MoneyInboxError.invalidPayload) { try MoneyInboxCommandWriter.ingest(inbox: inbox, text: "") }
        #expect(throws: MoneyInboxError.invalidPayload) { try MoneyInboxCommandWriter.ingest(inbox: inbox, text: String(repeating: "ب", count: 2001)) }
    }
}
