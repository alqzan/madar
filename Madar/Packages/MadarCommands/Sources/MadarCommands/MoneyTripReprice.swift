import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData
import MadarMoney

public struct MoneyRepriceLine: Identifiable {
    public var id: UUID
    public var title: String
    public var beforeMinor: Int
    public var afterMinor: Int
    public var isRefund: Bool
}
public struct MoneyTripReprice {
    public var signature: String
    public var lines: [MoneyRepriceLine]
    public var excludedCount: Int
    var allocations: [UUID: Int]
}
extension MoneyRepository {
    /// Preview only. Bank-priced rows, closed reports and adopted repayment plans keep their fixed figures.
    /// Linked refunds travel with their original, even if they arrived after the return.
    @MainActor public func previewTripReprice(id: UUID, rate: String, at now: Date) throws -> MoneyTripReprice {
        _ = try FX.parseRate(rate)
        let trips = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        guard let trip = trips.first(where: { $0.id == id && !$0.dismissed }), let code = trip.currency,
              code != (try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR") else { throw MoneyCommandError.invalidReference }
        let all = try confirmedTransactions()
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cycles = try context.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let statements = try context.fetch(FetchDescriptor<Statement>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let candidates = all.filter { $0.tripID == id && $0.currency == code && $0.kind != "refund" && $0.eventAt <= now }
        var lines: [MoneyRepriceLine] = [], changedAllocations: [UUID: Int] = [:], excluded = 0
        for original in candidates.sorted(by: { $0.id.uuidString < $1.id.uuidString }) {
            let refunds = all.filter { $0.relatedTransactionID == original.id && $0.kind == "refund" }.sorted { $0.eventAt == $1.eventAt ? $0.id.uuidString < $1.id.uuidString : $0.eventAt < $1.eventAt }
            let group = [original] + refunds
            guard original.rateSource == "trip", original.obligationID == nil, ["expense", "fee", "withdrawal", "transfer"].contains(original.kind),
                  !plans.contains(where: { $0.id == original.id }),
                  !group.contains(where: { tx in cycles.contains { $0.id == tx.cycleID && $0.closedAt != nil } }),
                  !statements.contains(where: { $0.cardID != nil && $0.cardID == original.cardID && $0.closeDate >= original.eventAt }),
                  !refunds.contains(where: { $0.rateSource == "message" }) else { excluded += 1; continue }
            let newHome = try FX.homeAmount(amountMinor: original.amountMinor, currency: code, rate: rate, home: original.homeCurrency)
            guard newHome > 0, newHome <= 9_007_199_254_740_991 else { throw MoneyCommandError.invalidAmount }
            let spends = allocations.filter { $0.transactionID == original.id }.sorted { $0.idempotencyKey < $1.idempotencyKey }
            guard spends.allSatisfy({ $0.kind == "spend" && $0.amountMinor <= 0 }), spends.isEmpty || spends.reduce(0, { $0 - $1.amountMinor }) == original.homeAmountMinor else { throw MoneyCommandError.invalidSplit }
            let parts = spends.isEmpty ? [] : AllocationEngine.distribute(newHome, weights: spends.map { -$0.amountMinor })
            for (row, n) in zip(spends, parts) { changedAllocations[row.id] = -n }
            lines.append(.init(id: original.id, title: original.merchant ?? original.counterparty ?? "مصروف", beforeMinor: original.homeAmountMinor, afterMinor: newHome, isRefund: false))
            var priorOriginal = 0, priorHome = 0, previousParts = parts.map { _ in 0 }
            for refund in refunds {
                let home = try FX.refundHomeAmount(refundMinor: refund.amountMinor, original: (original.amountMinor, newHome, code, rate), priorRefundsMinor: priorOriginal, priorRefundsHomeMinor: priorHome, home: original.homeCurrency)
                priorOriginal += refund.amountMinor; priorHome += home
                guard priorOriginal <= original.amountMinor, home >= 0, priorHome <= newHome else { throw MoneyCommandError.invalidAmount }
                let rows = allocations.filter { $0.transactionID == refund.id }.sorted { $0.idempotencyKey < $1.idempotencyKey }
                guard rows.count == spends.count, rows.allSatisfy({ $0.kind == "refund" && $0.amountMinor >= 0 }), zip(rows, spends).allSatisfy({ $0.target == $1.target && $0.targetID == $1.targetID }) else { throw MoneyCommandError.invalidSplit }
                let cumulative = parts.isEmpty ? [] : AllocationEngine.distribute(priorHome, weights: parts)
                for (index, row) in rows.enumerated() { changedAllocations[row.id] = cumulative[index] - previousParts[index] }
                previousParts = cumulative
                lines.append(.init(id: refund.id, title: refund.merchant ?? "مبلغ مسترد", beforeMinor: refund.homeAmountMinor, afterMinor: home, isRefund: true))
            }
        }
        // Hash the complete affected graph, including eligibility, so adding a refund/statement invalidates a stale preview.
        var records = try ([trip.record()] + all.map { try $0.record() } + allocations.map { try $0.record() } + cycles.map { try $0.record() } + plans.map { try $0.record() } + statements.map { try $0.record() })
        records.sort { ($0.model, $0.id.uuidString) < ($1.model, $1.id.uuidString) }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let digest = SHA256.hash(data: try encoder.encode(records)).map { String(format: "%02x", $0) }.joined()
        return .init(signature: digest, lines: lines, excludedCount: excluded, allocations: changedAllocations)
    }
}
