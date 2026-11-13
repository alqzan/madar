import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyGoalFundingProjection: Sendable {
    var today: GregorianDay
    var through: GregorianDay
    var points: [FundingProjectionPoint]
    func balance(on day: GregorianDay) -> Int? {
        guard day >= today && day <= through else { return nil }
        let offset = MadarCalendarDays.distance(from: today, to: day)
        return points.last(where: { $0.day <= offset })?.balanceMinor
    }
}

enum MoneyHomeProjectionBuilder {
    static func salaryForecastDays(context: ModelContext, cycle: MoneyCycleReading?, today: GregorianDay, zone: TimeZone) throws -> [GregorianDay] {
        guard let cycle else { return [] }
        let settings = try SettingsStore(context: context)
        let schedule = try settings.value(for: "mal.salarySchedule").object ?? [:]
        let hijri = try settings.value(for: "mal.cycleCalendar").string == "hijri"
        let recurrence: SalaryRecurrence? = {
            guard schedule["enabled"] == .bool(true), let every = schedule["every"]?.number,
                  let unit = schedule["unit"]?.string.flatMap(RecurrenceUnit.init(rawValue:)),
                  let first = schedule["firstDayKey"]?.string.flatMap({ try? GregorianDay($0) }) else { return nil }
            return SalaryRecurrence(every: Int(every), unit: unit, first: first, hijri: hijri)
        }()
        let salaryDay = Int(try settings.value(for: "mal.salaryDay").number ?? 0)
        var dates: [GregorianDay] = []
        var next = cycle.expectedEndDay > today ? cycle.expectedEndDay
            : recurrence?.preview(from: today.adding(days: 1), count: 1).first
                ?? MoneyRepository.expectedEnd(after: today, salaryDay: salaryDay, hijri: hijri, zone: zone)
        for _ in 0..<9 {
            guard next > today, MadarCalendarDays.distance(from: today, to: next) <= 3660 else { break }
            dates.append(next)
            let following = recurrence?.preview(from: next.adding(days: 1), count: 1).first
                ?? MoneyRepository.expectedEnd(after: next, salaryDay: salaryDay, hijri: hijri, zone: zone)
            guard following > next else { break }; next = following
        }
        return dates
    }

    /// Conditional, read-only projection for the small goal rails. An unsupported daily repayment leaves its rail
    /// without a forecast rather than silently treating the stored first payment as a permanent saving rate.
    static func fundingProjections(context: ModelContext, cycle: MoneyCycleReading?, today: GregorianDay, now: Date, zone: TimeZone,
                                   envelopes: [Envelope], plans: [EnvelopePlan], allocations: [Allocation],
                                   balances: [UUID: Int], surplus: Int, reserve: Int) throws -> [UUID: MoneyGoalFundingProjection] {
        guard let cycle else { return [:] }
        let settings = try SettingsStore(context: context)
        let dates = try salaryForecastDays(context: context, cycle: cycle, today: today, zone: zone)
        guard let last = dates.last else { return [:] }
        let currentLast = MadarCalendarDays.distance(from: cycle.startDay, to: dates[0])
        // The actual salary closes the old cycle before funding plans. A known remaining deficit may consume
        // today's surplus through auto-offset; do not promise that same surplus to goals as well.
        if try settings.value(for: "mal.autoOffset") != .bool(false),
           CycleEngine.availableNow(elapsedDays: currentLast, cycle.input, dailySpentMinor: cycle.spent) < 0 { return [:] }
        let horizon = MadarCalendarDays.distance(from: today, to: last)
        let sorted = plans.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        let unsupported = Set(sorted.filter { $0.source == "daily" && $0.kind == "repay" && $0.repaymentTotalMinor != nil }.compactMap(\.envelopeID))
        // A repayment competes for the same daily allowance as every saving plan. Until its future installments
        // can be replayed exactly, do not expose a forecast for the other goals either.
        guard unsupported.isEmpty else { return [:] }
        var salaryPlans: [FundingProjectionPlan] = []
        for plan in sorted where plan.source != "daily" {
            guard let id = plan.envelopeID, balances[id] != nil, let source = EnvelopePlanSpec.Source(rawValue: plan.source) else { continue }
            let state: RepaymentPlanState?
            if plan.kind == "repay", let total = plan.repaymentTotalMinor, let count = plan.repaymentPaychecks {
                let paid = allocations.filter { $0.kind == "repay" && $0.idempotencyKey.hasPrefix("fund:") && $0.idempotencyKey.hasSuffix(":" + plan.id.uuidString) }
                state = .init(totalMinor: total, paychecks: count, paidMinor: paid.reduce(0) { $0 + $1.amountMinor }, paidCount: Set(paid.map(\.idempotencyKey)).count)
            } else { state = nil }
            salaryPlans.append(.init(spec: .init(id: plan.id.uuidString, target: .envelope(id.uuidString), kind: plan.kind == "repay" ? .repay : .fund,
                                                source: source, perPaycheckMinor: plan.perPaycheckMinor),
                                     until: plan.untilDate.map { MadarCalendarDays.distance(from: today, to: .containing($0, in: zone)) }, repayment: state))
        }
        let targets = Dictionary(uniqueKeysWithValues: sorted.filter { $0.source == "daily" }.compactMap { plan -> (String, String)? in
            guard let id = plan.envelopeID else { return nil }; return (plan.id.uuidString, id.uuidString)
        })
        var caps: [String: Int] = [:]
        for plan in sorted where plan.source == "daily" {
            guard let envelope = envelopes.first(where: { $0.id == plan.envelopeID && $0.role == "goal" }), let target = envelope.targetMinor else { continue }
            let funded = allocations.filter { $0.targetID == envelope.id && $0.kind == "fund" && $0.amountMinor > 0 }.reduce(0) { $0 + $1.amountMinor }
            caps[plan.id.uuidString] = max(0, target - funded)
        }
        let startOffset = MadarCalendarDays.distance(from: today, to: cycle.startDay)
        var windows: [FundingProjectionCycle] = [.init(start: startOffset, firstDay: cycle.elapsedDays + 1,
                                                       lastDay: currentLast, input: cycle.input, targets: cycle.planEnvelopes.mapValues(\.uuidString))]
        let allowanceSetting = try settings.value(for: "mal.dailyAllowance").object ?? [:]
        let allowance: AllowanceMode
        if allowanceSetting["mode"]?.string == "percent", let bp = allowanceSetting["percentBp"]?.number {
            allowance = .percent(basisPoints: Int(bp), incomeMinor: cycle.incomeMinor)
        } else if let amount = allowanceSetting["amountMinor"]?.number { allowance = .fixed(allowanceMinor: Int(amount)) }
        else { allowance = cycle.input.policies.last?.mode ?? .fixed(allowanceMinor: 0) }
        for (first, end) in zip(dates, dates.dropFirst()) {
            let length = MadarCalendarDays.distance(from: first, to: end)
            let daily = sorted.filter { $0.source == "daily" && ($0.untilDate == nil || GregorianDay.containing($0.untilDate!, in: zone) >= first) }.map { plan in
                DailyPlan(id: plan.id.uuidString, amountMinor: plan.perPaycheckMinor, period: plan.period == "perDay" ? .perDay : .perCycle,
                          startDay: max(1, plan.startDayKey.flatMap { try? GregorianDay($0) }.map { MadarCalendarDays.distance(from: first, to: $0) + 1 } ?? 1),
                          endDay: plan.untilDate.map { MadarCalendarDays.distance(from: first, to: .containing($0, in: zone)) + 1 })
            }
            let paused = try MoneyRepository(context: context).moneyPausedDays(from: first, count: length, knownAt: now)
            windows.append(.init(start: MadarCalendarDays.distance(from: today, to: first), firstDay: 1, lastDay: length,
                                 input: .init(expectedLengthDays: length, policies: [.init(mode: allowance)], plans: daily, pausedDays: paused), targets: targets))
        }
        let result = FundingProjectionEngine.project(balances: Dictionary(uniqueKeysWithValues: balances.map { ($0.key.uuidString, $0.value) }),
            cycles: windows, salaryDays: dates.map { MadarCalendarDays.distance(from: today, to: $0) }, plans: salaryPlans,
            surplusMinor: surplus, reserveMinor: reserve, dailyCaps: caps, through: horizon)
        return Dictionary(uniqueKeysWithValues: envelopes.compactMap { envelope in
            guard !unsupported.contains(envelope.id), let points = result.points[envelope.id.uuidString] else { return nil }
            return (envelope.id, MoneyGoalFundingProjection(today: today, through: last, points: points))
        })
    }
}

extension AppMoneyService {
    func salaryForecastDays(cycle: MoneyCycleReading?, today: GregorianDay, zone: TimeZone) throws -> [GregorianDay] {
        try MoneyHomeProjectionBuilder.salaryForecastDays(context: ModelContext(app.container), cycle: cycle, today: today, zone: zone)
    }

    func fundingProjections(cycle: MoneyCycleReading?, today: GregorianDay, now: Date, zone: TimeZone,
                            envelopes: [Envelope], plans: [EnvelopePlan], allocations: [Allocation],
                            balances: [UUID: Int], surplus: Int, reserve: Int) throws -> [UUID: MoneyGoalFundingProjection] {
        try MoneyHomeProjectionBuilder.fundingProjections(context: ModelContext(app.container), cycle: cycle, today: today, now: now, zone: zone,
            envelopes: envelopes, plans: plans, allocations: allocations, balances: balances, surplus: surplus, reserve: reserve)
    }
}
