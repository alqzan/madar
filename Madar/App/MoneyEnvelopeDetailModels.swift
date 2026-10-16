import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarMoney

struct MoneyEnvelopeEntry: Identifiable {
    var id: UUID
    var at: Date
    var amountMinor: Int
    var balanceMinor: Int
    var title: String
    /// A real spend (a confirmed transaction), not an internal allocation.
    var isSpend = false
}
struct MoneyEnvelopeDetailReading {
    var home: MoneyHomeReading
    var envelope: MoneyHomeEnvelope
    var entries: [MoneyEnvelopeEntry]
    var savingMinor: Int
    var savingPlanID: UUID?
    /// The adopted salary repayment (schema V6), progress counted from its own repay allocations.
    var repayment: MoneyRepaymentReading?
}
struct MoneyRepaymentReading {
    var id: UUID
    var state: RepaymentPlanState
    var nextMinor: Int? { RepaymentEngine.nextPayment(state) }
    /// What each remaining salary pays: the even share, the last one total − paid.
    var remainingMinor: [Int] {
        var state = state, out: [Int] = []
        while let next = RepaymentEngine.nextPayment(state), out.count < MoneyCommandPayload.maxRepaySalaries { out.append(next); state.paidMinor += next; state.paidCount += 1 }
        return out
    }
}
extension AppMoneyService {
    func loadEnvelope(_ id: UUID) throws -> MoneyEnvelopeDetailReading? {
        let home = try load(), context = ModelContext(app.container)
        guard let envelope = home.envelopes.first(where: { $0.id == id }) else { return nil }
        let rows = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.targetID == id }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        let transactions = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.envelopeID == id && $0.kind == "fund" && $0.source == "salary" && ($0.untilDate == nil || $0.untilDate! >= app.prayerNow()) }
        // Adoption tombstones any earlier repayment; the newest live one wins if a merge ever left two.
        let repayPlan = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.envelopeID == id && $0.kind == "repay" && $0.repaymentTotalMinor != nil }.max { $0.createdAt < $1.createdAt }
        let repayment = repayPlan.flatMap { plan -> MoneyRepaymentReading? in
            guard let total = plan.repaymentTotalMinor, let count = plan.repaymentPaychecks else { return nil }
            let paid = rows.filter { $0.kind == "repay" && $0.idempotencyKey.hasPrefix("fund:") && $0.idempotencyKey.hasSuffix(":" + plan.id.uuidString) }
            return .init(id: plan.id, state: .init(totalMinor: total, paychecks: count, paidMinor: paid.reduce(0) { $0 + $1.amountMinor }, paidCount: Set(paid.map(\.idempotencyKey)).count))
        }
        var balance = 0
        let entries = rows.map { row in
            balance += row.amountMinor
            let transaction = transactions.first { $0.id == row.transactionID }
            let title = transaction?.merchant ?? (row.kind == "repay" ? "سداد دين المظروف" : row.kind == "fund" ? "تخصيص للمظروف" : row.kind == "refund" ? "ردّ إلى المظروف" : row.amountMinor < 0 ? "صرف من المظروف" : "رصيد المظروف")
            return MoneyEnvelopeEntry(id: row.id, at: transaction?.eventAt ?? row.createdAt, amountMinor: row.amountMinor, balanceMinor: balance, title: title, isSpend: transaction != nil && row.amountMinor < 0)
        }
        return .init(home: home, envelope: envelope, entries: entries.reversed(), savingMinor: plans.reduce(0) { $0 + $1.perPaycheckMinor }, savingPlanID: plans.count == 1 ? plans.first?.id : nil, repayment: repayment)
    }
    func salaryForecast(_ index: Int, home: MoneyHomeReading) -> GregorianDay? {
        guard let first = home.cycle?.expectedEndDay else { return nil }
        var calendar = Calendar(identifier: app.string("mal.cycleCalendar") == "hijri" ? .islamicUmmAlQura : .gregorian)
        calendar.timeZone = app.activePlace.timeZone
        return calendar.date(byAdding: .month, value: index, to: first.date(in: calendar.timeZone)).map { .containing($0, in: calendar.timeZone) }
    }
}
