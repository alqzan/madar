import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyHomeEnvelope: Identifiable {
    var id: UUID
    var name: String
    var balanceMinor: Int
    var targetMinor: Int?
    var due: GregorianDay?
    var perSalaryMinor: Int
}
struct MoneyHomeLimit: Identifiable {
    var id: UUID
    var title: String
    var spentMinor: Int
    var limitMinor: Int
}
struct MoneyHomeObligation: Identifiable {
    var id: UUID
    var name: String
    var amountMinor: Int
    var due: GregorianDay
}
struct MoneyHomeReading {
    var cycle: MoneyCycleReading?
    var basis: Basis
    var currency: String
    var hasAccounts: Bool
    var pendingCount: Int
    var reserveMinor: Int
    var surplusMinor: Int
    var reserveRunway: Runway?
    var surplusHistory: [Int]
    var envelopes: [MoneyHomeEnvelope]
    var limits: [MoneyHomeLimit]
    var obligations: [MoneyHomeObligation]
}

@MainActor struct AppMoneyService {
    unowned let app: AppSession
    var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }
    func amount(_ minor: Int, currency: String? = nil, full: Bool = false) -> String {
        let code = currency ?? app.string("core.currency"), exponent = CurrencyExponents.specified.exponent(code) ?? 2
        var scale = 1; for _ in 0..<exponent { scale *= 10 }
        let showFractions = full || minor % scale != 0
        return digits.amount(minorUnits: Int64(showFractions ? minor : minor / scale), fractionDigits: showFractions ? exponent : 0, signed: false)
    }
    func days(_ count: Int) -> String { count == 0 ? "اليوم" : PrayerCopy.days(count, digits: digits) }
    func pending(_ count: Int) -> String {
        let formatted = digits.string(count)
        return String(localized: "money.pending", defaultValue: "\(count) \(formatted)", table: "Money", locale: Locale(identifier: "ar"))
    }
    func load(at instant: Date? = nil) throws -> MoneyHomeReading {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = instant ?? app.prayerNow()
        let currency = app.string("core.currency"), cycle = try repo.cycle(at: now), basis = try repo.basis(at: now)
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        func envelopeBalance(_ id: UUID) -> Int { allocations.filter { $0.targetID == id }.reduce(0) { $0 + $1.amountMinor } }
        func roleBalance(_ role: String) -> Int {
            let ids = Set(envelopes.filter { $0.role == role }.map(\.id))
            return allocations.filter { ($0.target == role && $0.targetID == nil) || $0.targetID.map(ids.contains) == true }.reduce(0) { $0 + $1.amountMinor }
        }
        let reserve = roleBalance("reserve"), surplus = roleBalance("surplus")
        let zone = app.activePlace.timeZone, today = try DiaryLineRenderer.today(context: context, now: now)
        let goals = envelopes.filter { !["reserve", "surplus"].contains($0.role) }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }.map { envelope in
            MoneyHomeEnvelope(id: envelope.id, name: envelope.name, balanceMinor: envelopeBalance(envelope.id), targetMinor: envelope.targetMinor,
                due: envelope.due.map { GregorianDay.containing($0, in: zone) },
                perSalaryMinor: plans.filter { $0.envelopeID == envelope.id && ($0.untilDate == nil || $0.untilDate! >= now) }.reduce(0) { $0 + $1.perPaycheckMinor })
        }
        var limits: [MoneyHomeLimit] = []
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let movements = try repo.confirmedTransactions().filter { $0.cycleID == cycle?.id }
        let cycleRow = try context.fetch(FetchDescriptor<Cycle>()).first { $0.id == cycle?.id }
        for limit in try context.fetch(FetchDescriptor<CategoryLimit>()) where limit.deletedAt == nil && limit.mergedInto == nil {
            guard let category = categories.first(where: { $0.id == limit.categoryID }), limit.mode != "none" else { continue }
            let mode: CategoryLimitMode = limit.mode == "percent" ? .percent(basisPoints: limit.percentBp ?? 0, base: limit.base == "allowance" ? .allowance : .income) : .fixed(limitMinor: limit.limitMinor)
            guard let actual = LimitEngine.effectiveLimit(mode, cycleIncomeMinor: cycleRow?.incomeMinor ?? 0,
                cycleAllowanceMinor: cycle.map { CycleEngine.accruedDaily(through: $0.input.expectedLengthDays, $0.input) } ?? 0) else { continue }
            let ids = Set(movements.filter { $0.categoryID == category.id }.map(\.id))
            let spent = -allocations.filter { $0.transactionID.map(ids.contains) == true && ["spend", "refund"].contains($0.kind) }.reduce(0) { $0 + $1.amountMinor }
            limits.append(.init(id: category.id, title: category.name, spentMinor: spent, limitMinor: actual))
        }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.paidMinor < $0.amountMinor }
        var due: [MoneyHomeObligation] = []
        for item in items {
            guard let obligation = obligations.first(where: { $0.id == item.obligationID }), obligation.currency == currency else { continue }
            due.append(.init(id: item.id, name: obligation.name, amountMinor: item.amountMinor - item.paidMinor, due: .containing(item.dueDate, in: zone)))
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        for bill in obligations where bill.kind == "bill" && bill.currency == currency {
            guard let day = bill.dueDay else { continue }
            var parts = calendar.dateComponents([.year, .month], from: now)
            let range = calendar.range(of: .day, in: .month, for: now)!
            parts.day = min(day, range.count)
            guard let date = calendar.date(from: parts) else { continue }
            let paid = movements.contains { $0.obligationID == bill.id && calendar.isDate($0.eventAt, equalTo: date, toGranularity: .month) }
            if !paid { due.append(.init(id: bill.id, name: bill.name, amountMinor: bill.amountMinor, due: .containing(date, in: zone))) }
        }
        due.sort { $0.due == $1.due ? $0.id.uuidString < $1.id.uuidString : $0.due < $1.due }
        let daily = cycle?.headline.todayAllowanceMinor ?? 0, length = cycle?.input.expectedLengthDays ?? 30
        let cycleObligations = due.filter { $0.due >= (cycle?.startDay ?? today) && $0.due < (cycle?.expectedEndDay ?? today.adding(days: length)) }.reduce(0) { $0 + $1.amountMinor }
        let history = Dictionary(grouping: allocations.filter { $0.target == "surplus" || $0.targetID.map { id in envelopes.contains { $0.id == id && $0.role == "surplus" } } == true }, by: { $0.cycleID })
            .sorted { ($0.value.map(\.createdAt).min() ?? .distantPast) < ($1.value.map(\.createdAt).min() ?? .distantPast) }.suffix(6).map { $0.value.reduce(0) { $0 + $1.amountMinor } }
        return .init(cycle: cycle, basis: basis, currency: currency, hasAccounts: !accounts.isEmpty, pendingCount: try repo.pendingDecisionCount(),
            reserveMinor: reserve, surplusMinor: surplus, reserveRunway: RunwayEngine.runway(balanceMinor: reserve, dailyMinor: daily, cycleLengthDays: length, obligationsPerCycleMinor: cycleObligations),
            surplusHistory: history, envelopes: goals, limits: limits.sorted { $0.title < $1.title }, obligations: due)
    }
}
