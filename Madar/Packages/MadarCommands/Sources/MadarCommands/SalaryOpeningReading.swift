import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarPrayer

/// What «نزل الراتب» reads from the store. The preview and `money.confirmSalary` both build their input here, so the
/// report can never show a figure the command would not write.
public struct SalaryOpeningReading {
    public struct EnvelopeLine: Equatable, Identifiable {
        public var id: UUID
        public var planID: UUID
        public var name: String
        public var amountMinor: Int
        public var balanceMinor: Int
        public var targetMinor: Int?
        public var due: Date?
        public var repay: Bool
        /// A salary saving plan the report may adjust in place (`money.setEnvelopeSaving`).
        public var adjustable: Bool
    }
    public var salaryID: UUID
    public var salaryMinor: Int
    public var salaryAt: Date
    public var startDay: GregorianDay
    public var endDay: GregorianDay
    public var closingCycleID: UUID?
    public var closingStartDay: GregorianDay?
    /// The closing cycle's last «يومك», for «السابقة».
    public var previousDailyMinor: Int?
    public var previousMode: String?
    public var input: SalaryOpeningInput
    public var plan: SalaryOpeningPlan
    public var envelopes: [EnvelopeLine]
    public var surplusBeforeMinor: Int
    public var reserveBeforeMinor: Int
    /// Earlier closed cycles' carried figure («الفائض المرحّل», signed), oldest first.
    public var history: [(start: Date, carriedMinor: Int)]
}

/// Written once into `Cycle.closedReportJSON` at the close; later corrections are adjust rows, never a rewrite.
public struct SalaryCloseReport: Codable, Equatable, Sendable {
    public var v = 1
    public var start: Date
    public var end: Date
    public var carriedMinor: Int
    public var offsetMinor: Int
    public var carryMinor: Int
    public var toSurplusMinor: Int
    public var toReserveMinor: Int
    public var nextIncomeMinor: Int
    public init(start: Date, end: Date, carriedMinor: Int, offsetMinor: Int, carryMinor: Int, toSurplusMinor: Int, toReserveMinor: Int, nextIncomeMinor: Int) {
        self.start = start; self.end = end; self.carriedMinor = carriedMinor; self.offsetMinor = offsetMinor; self.carryMinor = carryMinor
        self.toSurplusMinor = toSurplusMinor; self.toReserveMinor = toReserveMinor; self.nextIncomeMinor = nextIncomeMinor
    }
}

extension MoneyRepository {
    /// Throws `missingRow` when the movement is not an unconfirmed salary, `salaryNeedsCycleConfirmation` when it falls on
    /// the open cycle's first day (the salary-or-extra-income question), `invalidAmount` while «يومك» was never set.
    public func salaryOpening(salaryID: UUID, newCycleID: UUID, remainderOverride: SalaryRemainder? = nil) throws -> SalaryOpeningReading {
        func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
        func whole(_ value: Double?) -> Int? { value.flatMap { $0.isFinite && abs($0) <= 9_007_199_254_740_991 ? Int($0) : nil } }
        guard let salary = try context.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == salaryID && live($0) }),
              salary.kind == "salary", salary.reviewState != "ok" else { throw MoneyCommandError.missingRow }
        guard salary.currency == salary.homeCurrency || salary.rateAtTime != nil else { throw MoneyCommandError.missingRate }
        let salaryMinor = try FX.homeAmount(amountMinor: salary.amountMinor, currency: salary.currency, rate: salary.rateAtTime ?? "1", home: salary.homeCurrency)
        guard salaryMinor > 0 else { throw MoneyCommandError.invalidAmount }
        let settings = try SettingsStore(context: context), prayer = try PrayerRepository(context: context)
        let zone = prayer.place(at: salary.eventAt).timeZone
        let startDay = try GregorianDay(salary.dayKey)

        // The cycle being closed: the open one the salary falls in.
        let openCycles = try context.fetch(FetchDescriptor<Cycle>()).filter { live($0) && $0.closedAt == nil && $0.end == nil }
        // A salary older than the open cycle, or one flagged as a possible duplicate, never opens a cycle (no second funding).
        guard !openCycles.contains(where: { $0.start > salary.eventAt }) else { throw MoneyCommandError.salaryNeedsCycleConfirmation }
        if let messageID = salary.messageID, try context.fetch(FetchDescriptor<BankMessage>()).contains(where: { $0.id == messageID && $0.status == "possibleDuplicate" }) {
            throw MoneyCommandError.salaryNeedsCycleConfirmation
        }
        let open = openCycles.filter { $0.start <= salary.eventAt }.max { $0.start < $1.start }
        var closing: SalaryOpeningInput.Closing?, closingStart: GregorianDay?, previousDaily: Int?, previousMode: String?
        if let open, let reading = try cycle(at: salary.eventAt), reading.id == open.id {
            // The salary day opens the new cycle; the old one is read through the day before it (no day counted twice).
            let through = MadarCalendarDays.distance(from: reading.startDay, to: startDay)
            guard through >= 1 else { throw MoneyCommandError.salaryNeedsCycleConfirmation }
            let daily = CycleEngine.day(through, reading.input).dailyMinor
            let offsetSoFar = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) && $0.cycleID == open.id && $0.kind == "offset" && $0.target == "daily" && $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
            closing = .init(cycleID: open.id.uuidString, availableNowMinor: CycleEngine.availableNow(elapsedDays: through, reading.input, dailySpentMinor: reading.spent),
                            dailyMinor: daily, offsetThisCycleMinor: offsetSoFar)
            closingStart = reading.startDay
            previousDaily = CycleEngine.day(through, reading.input).allowanceMinor
            previousMode = open.mode
        }
        // An open cycle that cannot be read is never left open beside a new one.
        if open != nil && closing == nil { throw MoneyCommandError.salaryNeedsCycleConfirmation }

        let salaryDay = whole(try settings.value(for: "mal.salaryDay").number) ?? 0, hijri = try settings.value(for: "mal.cycleCalendar").string == "hijri"
        let endDay = Self.expectedEnd(after: startDay, salaryDay: salaryDay, hijri: hijri, zone: zone)
        let length = max(1, MadarCalendarDays.distance(from: startDay, to: endDay))

        // «يومك» for the new cycle: the setting, else the closing cycle's mode; never an invented 0 (schema: null = not set).
        let allowanceSetting = try settings.value(for: "mal.dailyAllowance").object ?? [:]
        let allowance: AllowanceMode
        if allowanceSetting["mode"]?.string == "percent", let bp = whole(allowanceSetting["percentBp"]?.number) { allowance = .percent(basisPoints: bp, incomeMinor: salaryMinor) }
        else if allowanceSetting["mode"]?.string != "percent", let amount = whole(allowanceSetting["amountMinor"]?.number) { allowance = .fixed(allowanceMinor: amount) }
        else if let open { allowance = open.mode == "percent" ? .percent(basisPoints: open.percentBp ?? 0, incomeMinor: salaryMinor) : .fixed(allowanceMinor: open.dailyAllowanceMinor) }
        else { throw MoneyCommandError.invalidAmount }

        // Balances as the home reads them: role rows and the role envelopes' rows.
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter(live)
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter(live)
        func roleBalance(_ role: String) -> Int {
            let ids = Set(envelopes.filter { $0.role == role }.map(\.id))
            return allocations.filter { ($0.target == role && $0.targetID == nil) || $0.targetID.map(ids.contains) == true }.reduce(0) { $0 + $1.amountMinor }
        }
        let surplus = roleBalance("surplus"), reserve = roleBalance("reserve")

        // Obligations due inside the new cycle, in the home currency: unpaid instalments and each bill once per month.
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { live($0) && $0.currency == salary.homeCurrency }
        let window = startDay.date(in: zone)..<endDay.date(in: zone)
        var due = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { item in
            live(item) && item.paidMinor < item.amountMinor && window.contains(item.dueDate) && obligations.contains { $0.id == item.obligationID }
        }.reduce(0) { $0 + $1.amountMinor - $1.paidMinor }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        for bill in obligations where bill.kind == "bill" {
            guard let day = bill.dueDay else { continue }
            for offset in 0...2 {
                guard let month = calendar.date(byAdding: .month, value: offset, to: window.lowerBound), let range = calendar.range(of: .day, in: .month, for: month) else { continue }
                var parts = calendar.dateComponents([.year, .month], from: month); parts.day = min(day, range.count)
                if let date = calendar.date(from: parts), window.contains(date) { due += bill.amountMinor }
            }
        }

        // Salary-funded plans: savings as they stand, adopted repayments from what they already paid (V6).
        var specs: [EnvelopePlanSpec] = [], lines: [SalaryOpeningReading.EnvelopeLine] = []
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { live($0) && $0.source != "daily" && ($0.untilDate == nil || $0.untilDate! >= salary.eventAt) }
            .sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        for plan in plans {
            guard let envelopeID = plan.envelopeID, let envelope = envelopes.first(where: { $0.id == envelopeID }),
                  let source = EnvelopePlanSpec.Source(rawValue: plan.source) else { continue }
            let target: AllocationTarget = .envelope(envelopeID.uuidString)
            let spec: EnvelopePlanSpec?
            if plan.kind == "repay", let total = plan.repaymentTotalMinor, let count = plan.repaymentPaychecks {
                let paid = allocations.filter { $0.kind == "repay" && $0.idempotencyKey.hasPrefix("fund:") && $0.idempotencyKey.hasSuffix(":" + plan.id.uuidString) }
                spec = .repayment(id: plan.id.uuidString, target: target, source: source,
                                  .init(totalMinor: total, paychecks: count, paidMinor: paid.reduce(0) { $0 + $1.amountMinor }, paidCount: Set(paid.map(\.idempotencyKey)).count))
            } else {
                spec = .init(id: plan.id.uuidString, target: target, kind: plan.kind == "repay" ? .repay : .fund, source: source, perPaycheckMinor: plan.perPaycheckMinor)
            }
            guard let spec, spec.perPaycheckMinor > 0 else { continue }
            specs.append(spec)
            lines.append(.init(id: envelopeID, planID: plan.id, name: envelope.name, amountMinor: spec.perPaycheckMinor,
                balanceMinor: allocations.filter { $0.targetID == envelopeID }.reduce(0) { $0 + $1.amountMinor }, targetMinor: envelope.targetMinor, due: envelope.due,
                repay: spec.kind == .repay, adjustable: plan.kind == "fund" && plan.source == "salary" && plan.period == "perCycle"))
        }

        let storedRemainder = try settings.value(for: "mal.salaryRemainder").string ?? ""
        let remainder = remainderOverride ?? SalaryRemainder(rawValue: storedRemainder) ?? .surplusThenReserve
        let cap = whole(try settings.value(for: "mal.surplusCap").number) ?? 1_000_000, autoOffset = try settings.value(for: "mal.autoOffset") != .bool(false)
        let input = SalaryOpeningInput(newCycleID: newCycleID.uuidString, salaryTransactionID: salary.id.uuidString, salaryMinor: salaryMinor,
            expectedLengthDays: length, allowance: allowance, closing: closing, surplusMinor: surplus, reserveMinor: reserve,
            surplusCapMinor: cap, autoOffset: autoOffset,
            remainder: remainder, obligationsMinor: due, plans: specs)
        let history: [(start: Date, carriedMinor: Int)] = try context.fetch(FetchDescriptor<Cycle>()).filter { live($0) && $0.closedAt != nil }.sorted { $0.start < $1.start }.compactMap { cycle in
            guard let data = cycle.closedReportJSON, let report = try? JSONDecoder().decode(SalaryCloseReport.self, from: data) else { return nil }
            return (cycle.start, report.carriedMinor)
        }
        return .init(salaryID: salary.id, salaryMinor: salaryMinor, salaryAt: salary.eventAt, startDay: startDay, endDay: endDay,
                     closingCycleID: open?.id, closingStartDay: closingStart, previousDailyMinor: previousDaily, previousMode: previousMode,
                     input: input, plan: SalaryOpening.plan(input), envelopes: lines, surplusBeforeMinor: surplus, reserveBeforeMinor: reserve, history: history)
    }

    /// RM9: `mal.salaryDay` 0 = a month after this salary; 1–31 = that day of the month (clamped), the occurrence nearest a
    /// month after this salary, so an early or late salary does not stretch or shrink the next cycle by a month.
    public static func expectedEnd(after start: GregorianDay, salaryDay: Int, hijri: Bool, zone: TimeZone) -> GregorianDay {
        var calendar = Calendar(identifier: hijri ? .islamicUmmAlQura : .gregorian); calendar.timeZone = zone
        let base = start.date(in: zone)
        guard let target = calendar.date(byAdding: .month, value: 1, to: base) else { return start.adding(days: 30) }
        guard (1...31).contains(salaryDay) else { return .containing(target, in: zone) }
        let candidates: [Date] = (0...2).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: base), let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
            var parts = calendar.dateComponents([.era, .year, .month], from: month); parts.day = min(salaryDay, range.count)
            return calendar.date(from: parts)
        }.filter { $0 > base }
        let best = candidates.min { abs($0.timeIntervalSince(target)) < abs($1.timeIntervalSince(target)) } ?? target
        return .containing(best, in: zone)
    }
}
