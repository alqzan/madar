import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData

public struct MoneyGoalReading {
    public struct Paid: Identifiable { public var id: UUID; public var title: String; public var amountMinor: Int; public var dayKey: String }
    public var cycleID: UUID?
    public var today: GregorianDay
    public var dailyMinor: Int
    public var surplusMinor: Int
    public var reserveMinor: Int
    public var signature: String
    public var paid: [Paid]
}
extension MoneyRepository {
    public func goalPreparation(at now: Date) throws -> MoneyGoalReading {
        let cycle = try cycle(at: now), today = try DiaryLineRenderer.today(context: context, now: now)
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        func balance(_ role: String) -> Int {
            let ids = Set(envelopes.filter { $0.role == role }.map(\.id))
            return allocations.filter { ($0.target == role && $0.targetID == nil) || $0.targetID.map(ids.contains) == true }.reduce(0) { $0 + $1.amountMinor }
        }
        let movements = try confirmedTransactions()
        let returnsByTransaction = movements.reduce(into: [UUID: Int]()) { totals, row in
            guard row.kind == "refund", let originalID = row.relatedTransactionID else { return }
            totals[originalID, default: 0] += row.homeAmountMinor
        }
        let paid = movements.filter { $0.kind == "expense" }.sorted { $0.eventAt > $1.eventAt }.compactMap { row -> MoneyGoalReading.Paid? in
            let net = max(0, row.homeAmountMinor - (returnsByTransaction[row.id] ?? 0))
            return net == 0 ? nil : .init(id: row.id, title: row.merchant ?? "مصروف مسجل", amountMinor: net, dayKey: row.dayKey)
        }
        let daily = max(0, cycle?.headline.todayAllowanceMinor ?? 0), surplus = balance("surplus"), reserve = balance("reserve")
        let raw = [cycle?.id.uuidString ?? "none", today.description, String(daily), String(surplus), String(reserve)] + paid.map { "\($0.id):\($0.amountMinor)" }
        let signature = SHA256.hash(data: Data(raw.joined(separator: "|").utf8)).map { String(format: "%02x", $0) }.joined()
        return .init(cycleID: cycle?.id, today: today, dailyMinor: daily, surplusMinor: surplus, reserveMinor: reserve, signature: signature, paid: paid)
    }
}
