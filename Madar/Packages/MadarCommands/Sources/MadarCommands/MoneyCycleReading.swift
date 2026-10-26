import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarPrayer

public struct MoneyCycleReading {
    public var id: UUID
    public var startDay: GregorianDay
    public var today: GregorianDay
    public var expectedEndDay: GregorianDay
    public var incomeMinor: Int
    public var elapsedDays: Int
    public var input: CycleInput
    public var spent: [Int: Int]
    public var headline: Headline
    public var curve: [CurvePoint]
    public var planEnvelopes: [String: UUID]
}

extension MoneyRepository {
    public func pendingDecisionCount() throws -> Int {
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && ["needsLook", "possibleDuplicate"].contains($0.status) }
        let manual = try pendingTransactions().filter { $0.messageID == nil }
        return messages.count + manual.count
    }

    /// Cycle membership uses the salary instant. Stored transaction days and the first policy's
    /// day are authoritative, so later boundary/calendar choices cannot move old spending.
    public func cycle(at now: Date) throws -> MoneyCycleReading? {
        guard let cycle = try context.fetch(FetchDescriptor<Cycle>()).filter({ $0.deletedAt == nil && $0.mergedInto == nil && $0.start <= now && ($0.end == nil || now < $0.end!) }).max(by: { $0.start < $1.start }),
              let expectedEnd = cycle.expectedEnd else { return nil }
        let prayer = try PrayerRepository(context: context), place = prayer.place(at: now)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let policies = try context.fetch(FetchDescriptor<CyclePolicy>()).filter { $0.cycleID == cycle.id && $0.deletedAt == nil && $0.mergedInto == nil }.sorted { $0.effectiveFromDayKey < $1.effectiveFromDayKey }
        let start = try policies.first.map { try GregorianDay($0.effectiveFromDayKey) } ?? GregorianDay.containing(cycle.start, in: prayer.place(at: cycle.start).timeZone)
        let end = GregorianDay.containing(expectedEnd, in: place.timeZone)
        let length = max(1, MadarCalendarDays.distance(from: start, to: end)), elapsed = max(1, MadarCalendarDays.distance(from: start, to: today) + 1)
        let specs: [CyclePolicySpec]
        if policies.isEmpty {
            let mode: AllowanceMode = cycle.mode == "percent" ? .percent(basisPoints: cycle.percentBp ?? 0, incomeMinor: cycle.incomeMinor) : .fixed(allowanceMinor: cycle.dailyAllowanceMinor)
            specs = [.init(mode: mode)]
        } else {
            specs = try policies.map { policy in
                .init(effectiveFromDay: max(1, MadarCalendarDays.distance(from: start, to: try GregorianDay(policy.effectiveFromDayKey)) + 1),
                    mode: policy.mode == "percent" ? .percent(basisPoints: policy.percentBp ?? 0, incomeMinor: cycle.incomeMinor) : .fixed(allowanceMinor: policy.allowanceMinor),
                    frozenRate: .init(dailyRateMinor: policy.dailyRateMinor, lastDayRemainderMinor: policy.lastDayRemainderMinor))
            }
        }
        var planEnvelopes: [String: UUID] = [:]
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.source == "daily" && ($0.untilDate == nil || $0.untilDate! >= cycle.start) }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }
        let allAllocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let allMovements = try confirmedTransactions()
        let goalEnvelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.role == "goal" }
        let planSpecs = plans.compactMap { plan -> DailyPlan? in
            if plan.kind == "repay", let total = plan.repaymentTotalMinor, let count = plan.repaymentPaychecks,
               let purchase = allMovements.first(where: { $0.id == plan.id }) {
                guard purchase.cycleID != cycle.id, purchase.eventAt < cycle.start, let envelope = plan.envelopeID else { return nil }
                let paid = allAllocations.filter { $0.cycleID != cycle.id && $0.targetID == envelope && $0.amountMinor > 0 && $0.kind == "repay" && $0.idempotencyKey.hasPrefix("daily:") && $0.idempotencyKey.contains(":" + plan.id.uuidString + ":") }
                let refunds = Set(allMovements.filter { $0.kind == "refund" && $0.relatedTransactionID == purchase.id }.map(\.id))
                let returned = allAllocations.filter { $0.targetID == envelope && $0.transactionID.map(refunds.contains) == true && $0.kind == "refund" }.reduce(0) { $0 + $1.amountMinor }
                guard let amount = RepaymentEngine.nextPayment(.init(totalMinor: max(0, total - returned), paychecks: count, paidMinor: paid.reduce(0) { $0 + $1.amountMinor }, paidCount: Set(paid.compactMap(\.cycleID)).count)) else { return nil }
                planEnvelopes[plan.id.uuidString] = envelope
                return .init(id: plan.id.uuidString, amountMinor: amount, period: .perCycle)
            }
            guard let envelope = plan.envelopeID else { return nil }; planEnvelopes[plan.id.uuidString] = envelope
            return .init(id: plan.id.uuidString, amountMinor: plan.perPaycheckMinor, period: plan.period == "perDay" ? .perDay : .perCycle,
                startDay: max(1, plan.startDayKey.flatMap { try? GregorianDay($0) }.map { MadarCalendarDays.distance(from: start, to: $0) + 1 } ?? 1),
                endDay: plan.untilDate.map { MadarCalendarDays.distance(from: start, to: .containing($0, in: place.timeZone)) + 1 },
                maximumMinorPerCycle: goalEnvelopes.first(where: { $0.id == plan.id && $0.id == envelope })?.targetMinor.map { target in
                    let alreadyFunded = allAllocations.filter { $0.targetID == envelope && $0.kind == "fund" && $0.amountMinor > 0 && !($0.cycleID == cycle.id && $0.idempotencyKey.hasPrefix("daily:")) }.reduce(0) { $0 + $1.amountMinor }
                    return max(0, target - alreadyFunded)
                })
        }
        var paused: Set<Int> = []
        let settings = try SettingsStore(context: context)
        if try settings.value(for: "mal.travelPausesDaily") == .bool(true) {
            let trips = try context.fetch(FetchDescriptor<Trip>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            let boundary = DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "fajr") ?? .fajr
            for day in 1...max(length, elapsed) {
                let key = start.adding(days: day - 1), nextKey = key.adding(days: 1)
                let dayInstant = key.date(in: place.timeZone).addingTimeInterval(12 * 3600)
                let dayPlace = prayer.place(at: dayInstant), dayOptions = prayer.calculationOptions(at: dayInstant)
                let beginning: Date, ending: Date
                if boundary == .midnight { beginning = key.date(in: dayPlace.timeZone); ending = nextKey.date(in: dayPlace.timeZone) }
                else {
                    guard let first = PrayerTimesEngine.calculate(day: key, place: dayPlace, options: dayOptions),
                          let next = PrayerTimesEngine.calculate(day: nextKey, place: dayPlace, options: dayOptions) else { throw CoreError.missingPrayerTimes }
                    beginning = boundary == .fajr ? first.fajr : first.maghrib
                    ending = boundary == .fajr ? next.fajr : next.maghrib
                }
                if trips.contains(where: { trip in
                    guard !trip.dismissed, let began = trip.start else { return false }
                    // An open trip pauses through now; its unknown return does not erase future forecast dailies.
                    return began < ending && (trip.end ?? now) > beginning
                }) { paused.insert(day) }
            }
        }
        let input = CycleInput(expectedLengthDays: length, policies: specs, plans: planSpecs, carryMinor: cycle.carryAdjustMinor, pausedDays: paused)
        let tx = try confirmedTransactions(), rows = try context.fetch(FetchDescriptor<Allocation>())
        var spent: [Int: Int] = [:]
        for allocation in rows where allocation.deletedAt == nil && allocation.mergedInto == nil && allocation.target == "daily" && allocation.cycleID == cycle.id && ["spend", "refund", "adjust", "offset"].contains(allocation.kind) {
            guard let transaction = tx.first(where: { $0.id == allocation.transactionID }) else { continue }
            let budgetDay: String
            if transaction.kind == "refund", let original = tx.first(where: { $0.id == transaction.relatedTransactionID }) { budgetDay = original.dayKey }
            else { budgetDay = transaction.dayKey }
            let index = MadarCalendarDays.distance(from: start, to: try GregorianDay(budgetDay)) + 1
            spent[index, default: 0] -= allocation.amountMinor
        }
        let headline = CycleEngine.headline(elapsedDays: elapsed, input, dailySpentMinor: spent, pendingDecisions: try pendingDecisionCount())
        return .init(id: cycle.id, startDay: start, today: today, expectedEndDay: end, incomeMinor: cycle.incomeMinor, elapsedDays: elapsed, input: input, spent: spent,
            headline: headline, curve: CycleEngine.curve(through: max(length, elapsed), input, dailySpentMinor: spent), planEnvelopes: planEnvelopes)
    }
}
