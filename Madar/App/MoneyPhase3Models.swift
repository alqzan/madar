import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

// Owner decisions, 11 Nov 2026, phase 3: a refund names the purchase it undoes, and a movement shows the fees and the foreign figures
// its bank message printed. Read-only; every read here is a bounded store read, never a write and never a notification.

/// A purchase a refund draft could undo.
struct MoneyRefundOriginal: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var amountMinor: Int
    var currency: String
    var day: GregorianDay
}

/// The purchase a refund draft is linked to (`linked`) and the others it could be (`originals`, best first).
struct MoneyRefundLink: Equatable, Sendable {
    var linked: UUID?
    var originals: [MoneyRefundOriginal]
    var linkedOriginal: MoneyRefundOriginal? { originals.first { $0.id == linked } }
}

enum MoneyPhase3Reader {
    /// nil when the refund has no candidate purchase (nothing is drawn). A failed read also draws nothing.
    static func refundLink(for row: MoneyTransaction, repo: MoneyRepository, zone: TimeZone) -> MoneyRefundLink? {
        guard row.kind == "refund", let found = try? repo.refundOriginals(forRefund: row.id) else { return nil }
        var ids = found.candidates
        if let stored = row.relatedTransactionID, !ids.contains(stored) { ids.insert(stored, at: 0) }
        guard !ids.isEmpty, let rows = try? repo.liveTransactions(ids) else { return nil }
        let originals: [MoneyRefundOriginal] = ids.compactMap { id in
            guard let purchase = rows[id] else { return nil }
            return .init(id: id, name: purchase.merchant ?? purchase.counterparty ?? "مشتريات", amountMinor: purchase.amountMinor, currency: purchase.currency,
                         day: GregorianDay.containing(purchase.eventAt, in: zone))
        }
        guard !originals.isEmpty else { return nil }
        let linked = row.relatedTransactionID ?? found.suggested
        return .init(linked: originals.contains { $0.id == linked } ? linked : nil, originals: originals)
    }

    /// The payload of `money.confirmTransaction` for a draft: a refund carries the purchase it undoes.
    static func confirmPayload(_ draft: MoneyMessageDraft, choice: UUID?) -> [String: MadarCore.JSONValue] {
        var payload: [String: MadarCore.JSONValue] = ["id": .string(draft.id.uuidString)]
        if let target = choice ?? draft.refund?.linked { payload["relatedTransactionID"] = .string(target.uuidString) }
        return payload
    }
}

/// Fees, VAT and foreign figures of one confirmed movement, as printed by its bank message. Empty lines are never drawn.
struct MoneyChargeLines: Equatable, Sendable {
    var feeMinor = 0, vatMinor = 0, foreignFeeMinor = 0
    var chargeCurrency = ""
    var isForeign = false
    var originalAmountMinor = 0, originalCurrency = ""
    var rate: String?
    var hasCharges: Bool { feeMinor > 0 || vatMinor > 0 || foreignFeeMinor > 0 }
    var isEmpty: Bool { !hasCharges && !isForeign }
}

@ModelActor private actor MoneyChargesReadActor {
    func read(_ id: UUID) throws -> MoneyChargeLines? {
        try Task.checkCancellation()
        guard let item = try MoneyRepository(context: modelContext).charges(forTransactions: [id])[id] else { return nil }
        return .init(feeMinor: item.charges.feeMinor, vatMinor: item.charges.vatMinor, foreignFeeMinor: item.charges.foreignFeeMinor,
                     chargeCurrency: item.chargeCurrency, isForeign: item.isForeign, originalAmountMinor: item.originalAmountMinor,
                     originalCurrency: item.originalCurrency, rate: item.printedRate ?? item.rateAtTime)
    }
}

extension AppMoneyService {
    /// Off the main actor; nil for a non-movement id or a movement with nothing printed.
    func loadChargeLines(transactionID: UUID) async -> MoneyChargeLines? {
        guard (try? requireReadableStore()) != nil else { return nil }
        let container = app.container
        let task = Task.detached(priority: .userInitiated) { try await MoneyChargesReadActor(modelContainer: container).read(transactionID) }
        let value = await withTaskCancellationHandler { try? await task.value } onCancel: { task.cancel() }
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
