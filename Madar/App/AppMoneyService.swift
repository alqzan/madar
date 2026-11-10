import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyHomeEnvelope: Identifiable, Sendable {
    var id: UUID
    var name: String
    var balanceMinor: Int
    var targetMinor: Int?
    var due: GregorianDay?
    var perSalaryMinor: Int
    var dailyFundingMinor: Int
    var fundingProjection: MoneyGoalFundingProjection? = nil
}
struct MoneyHomeLimit: Identifiable, Sendable {
    var id: UUID
    var title: String
    var spentMinor: Int
    var limitMinor: Int
}
struct MoneyHomeObligation: Identifiable, Equatable, Sendable {
    var id: UUID
    var name: String
    var amountMinor: Int
    var due: GregorianDay
}
struct MoneyHomeReading: Sendable {
    var salaryDates: [GregorianDay] = []
    var cycle: MoneyCycleReading?
    var basis: Basis
    var currency: String
    var hasAccounts: Bool
    var cardCount: Int
    var hawlKey: String?
    var unknownBalanceCount: Int
    var knownBalanceCount: Int
    /// Empty cash is zero; accounts without any bank checkpoint are unknown.
    var hasKnownBalance: Bool { knownBalanceCount > 0 || unknownBalanceCount == 0 }
    var pendingCount: Int
    var reserveMinor: Int
    var surplusMinor: Int
    var reserveRunway: Runway?
    var reserveDailies: Int?
    var obligationsPerCycleMinor: Int
    var surplusHistory: [Int]
    var envelopes: [MoneyHomeEnvelope]
    var limits: [MoneyHomeLimit]
    var obligations: [MoneyHomeObligation]
    /// Foreign accounts left out of the basis because no exchange rate is known.
    var unratedAccountNames: [String] = []
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
    func time(_ at: Date) -> String {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: app.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab")
        formatter.timeZone = app.activePlace.timeZone; formatter.dateFormat = "h:mm a"; return formatter.string(from: at)
    }
    func days(_ count: Int) -> String { count == 0 ? "اليوم" : PrayerCopy.days(count, digits: digits) }
    func dailies(_ count: Int) -> String {
        let formatted = digits.string(count)
        return String(localized: "money.dailies", defaultValue: "\(count) \(formatted)", table: "Money", locale: Locale(identifier: "ar"))
    }
    func coverage(_ count: Int) -> String {
        let formatted = digits.string(count)
        return String(localized: "money.coverage", defaultValue: "\(count) \(formatted)", table: "Money", locale: Locale(identifier: "ar"))
    }
    /// Arabic counting: «رسالة واحدة»، «رسالتان»، «٣ رسائل»، «١١ رسالةً». Forms are (one, two, 3–10, 11+).
    func counted(_ count: Int, _ forms: (String, String, String, String)) -> String {
        switch count { case 1: forms.0; case 2: forms.1; case 0, 3...10: digits.string(count) + " " + forms.2; default: digits.string(count) + " " + forms.3 }
    }
    func pending(_ count: Int) -> String {
        let formatted = digits.string(count)
        return String(localized: "money.pending", defaultValue: "\(count) \(formatted)", table: "Money", locale: Locale(identifier: "ar"))
    }
    func bigExpenseThreshold(cycle: MoneyCycleReading?) -> Int? {
        let rule: ExpenseThreshold.Rule
        switch app.string("mal.bigExpenseRule") {
        case "salaryPercent": rule = .salaryPercent(basisPoints: Int(app.number("mal.bigExpenseSalaryBp")))
        case "amount": rule = .amount(Int(app.number("mal.bigExpenseMinor")))
        default: rule = .dailies(Int(app.number("mal.bigExpenseDays")))
        }
        return ExpenseThreshold.amount(rule, dailyMinor: cycle?.headline.todayAllowanceMinor, salaryMinor: cycle?.incomeMinor)
    }
    /// The store/authentication boundary every money read crosses (the ledger used to build the whole home reading just to pass it).
    func requireReadableStore() throws {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
    }
    func load(at instant: Date? = nil) throws -> MoneyHomeReading {
        try requireReadableStore()
        let now = instant ?? app.prayerNow()
        return try MoneyHomeReadingBuilder.load(context: ModelContext(app.container), now: now,
            currency: app.string("core.currency"), zone: app.activePlace.timeZone)
    }

    func loadOffMain(at instant: Date? = nil) async throws -> MoneyHomeReading {
        let session = app
        try requireReadableStore()
        guard !session.settingsWriteInProgress else { throw BackupOperationError.busy }
        let revision = session.prayerRevision, generation = session.storeGeneration, container = session.container
        let request = MoneyHomeReadRequest(now: instant ?? session.prayerNow(), currency: session.string("core.currency"),
            timeZoneIdentifier: session.activePlace.timeZone.identifier)
        let readTask = Task.detached(priority: .userInitiated) {
            let worker = MoneyHomeReadActor(modelContainer: container)
            return try await worker.read(request)
        }
        let reading = try await withTaskCancellationHandler { try await readTask.value } onCancel: { readTask.cancel() }
        try Task.checkCancellation()
        try requireReadableStore()
        guard !session.settingsWriteInProgress, session.prayerRevision == revision,
              session.storeGeneration == generation, session.container === container else { throw CancellationError() }
        return reading
    }

}


struct MoneyHomeReadRequest: Sendable {
    let now: Date
    let currency: String
    let timeZoneIdentifier: String
}

@ModelActor private actor MoneyHomeReadActor {
    func read(_ request: MoneyHomeReadRequest) throws -> MoneyHomeReading {
        try Task.checkCancellation()
        let zone = TimeZone(identifier: request.timeZoneIdentifier) ?? .current
        let reading = try MoneyHomeReadingBuilder.load(context: modelContext, now: request.now, currency: request.currency, zone: zone)
        try Task.checkCancellation()
        return reading
    }

}

enum MoneyHomeReadingBuilder {
    static func load(context: ModelContext, now: Date, currency: String, zone: TimeZone) throws -> MoneyHomeReading {
        let repo = MoneyRepository(context: context)
        let cycle = try repo.cycle(at: now), basis = try repo.basis(at: now)
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let cardCount = try context.fetch(FetchDescriptor<Card>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.count
        let hawlKey = try context.fetch(FetchDescriptor<ZakatProfile>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .sorted { $0.id.uuidString < $1.id.uuidString }.first?.hawlStartHijri
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        // One pass over the allocations instead of one per envelope, goal and role.
        var balanceByTarget: [UUID: Int] = [:]
        for allocation in allocations { if let id = allocation.targetID { balanceByTarget[id, default: 0] += allocation.amountMinor } }
        func envelopeBalance(_ id: UUID) -> Int { balanceByTarget[id] ?? 0 }
        var rolesByEnvelopeID: [UUID: Set<String>] = [:]
        for envelope in envelopes where ["reserve", "surplus"].contains(envelope.role) {
            rolesByEnvelopeID[envelope.id, default: []].insert(envelope.role)
        }
        var reserve = 0, surplus = 0
        for allocation in allocations {
            if let id = allocation.targetID {
                let roles = rolesByEnvelopeID[id, default: []]
                if roles.contains("reserve") { reserve += allocation.amountMinor }
                if roles.contains("surplus") { surplus += allocation.amountMinor }
            } else if allocation.target == "reserve" {
                reserve += allocation.amountMinor
            } else if allocation.target == "surplus" {
                surplus += allocation.amountMinor
            }
        }
        let activePlansByEnvelope = Dictionary(grouping: plans.filter {
            $0.source != "daily" && ($0.untilDate == nil || $0.untilDate! >= now)
        }, by: \.envelopeID)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let balances = Dictionary(uniqueKeysWithValues: envelopes.map { ($0.id, envelopeBalance($0.id)) })
        let projections = try MoneyHomeProjectionBuilder.fundingProjections(context: context, cycle: cycle, today: today, now: now, zone: zone, envelopes: envelopes,
                                                plans: plans, allocations: allocations, balances: balances, surplus: surplus, reserve: reserve)
        let goals = envelopes.filter { !["reserve", "surplus"].contains($0.role) }.sorted { $0.createdAt == $1.createdAt ? $0.id.uuidString < $1.id.uuidString : $0.createdAt < $1.createdAt }.map { envelope in
            MoneyHomeEnvelope(id: envelope.id, name: envelope.name, balanceMinor: envelopeBalance(envelope.id), targetMinor: envelope.targetMinor,
                due: envelope.due.map { GregorianDay.containing($0, in: zone) },
                perSalaryMinor: (activePlansByEnvelope[envelope.id] ?? []).reduce(0) { $0 + $1.perPaycheckMinor },
                dailyFundingMinor: cycle.map { reading in
                    CycleEngine.day(reading.elapsedDays, reading.input).dripsMinor.filter { reading.planEnvelopes[$0.key] == envelope.id }.values.reduce(0, +)
                } ?? 0, fundingProjection: projections[envelope.id])
        }
        var limits: [MoneyHomeLimit] = []
        let categories = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let categoriesByID = Dictionary(categories.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let confirmed = try repo.confirmedTransactions()
        let movements = confirmed.filter { $0.cycleID == cycle?.id }
        var categoryIDsByMovementID: [UUID: Set<UUID>] = [:]
        for movement in movements {
            if let categoryID = movement.categoryID { categoryIDsByMovementID[movement.id, default: []].insert(categoryID) }
        }
        var spentByCategory: [UUID: Int] = [:]
        for allocation in allocations where ["spend", "refund"].contains(allocation.kind) {
            guard let transactionID = allocation.transactionID,
                  let categoryIDs = categoryIDsByMovementID[transactionID] else { continue }
            for categoryID in categoryIDs { spentByCategory[categoryID, default: 0] -= allocation.amountMinor }
        }
        let cycleRow = try context.fetch(FetchDescriptor<Cycle>()).first { $0.id == cycle?.id }
        for limit in try context.fetch(FetchDescriptor<CategoryLimit>()) where limit.deletedAt == nil && limit.mergedInto == nil {
            guard let categoryID = limit.categoryID,
                  let category = categoriesByID[categoryID], limit.mode != "none" else { continue }
            let mode: CategoryLimitMode = limit.mode == "percent" ? .percent(basisPoints: limit.percentBp ?? 0, base: limit.base == "allowance" ? .allowance : .income) : .fixed(limitMinor: limit.limitMinor)
            guard let actual = LimitEngine.effectiveLimit(mode, cycleIncomeMinor: cycleRow?.incomeMinor ?? 0,
                cycleAllowanceMinor: cycle.map { CycleEngine.accruedDaily(through: $0.input.expectedLengthDays, $0.input) } ?? 0) else { continue }
            let spent = spentByCategory[category.id] ?? 0
            limits.append(.init(id: category.id, title: category.name, spentMinor: spent, limitMinor: actual))
        }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let obligationsByID = Dictionary(obligations.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.paidMinor < $0.amountMinor }
        var due: [MoneyHomeObligation] = []
        for item in items {
            guard let obligationID = item.obligationID,
                  let obligation = obligationsByID[obligationID], obligation.currency == currency else { continue }
            due.append(.init(id: item.id, name: obligation.name, amountMinor: item.amountMinor - item.paidMinor, due: .containing(item.dueDate, in: zone)))
        }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        var paymentDatesByObligation: [UUID: [Date]] = [:]
        for transaction in confirmed {
            guard let obligationID = transaction.obligationID else { continue }
            paymentDatesByObligation[obligationID, default: []].append(transaction.eventAt)
        }
        var flexibleExtraMinor = 0
        for bill in obligations where bill.isRecurring && bill.currency == currency {
            let payments = paymentDatesByObligation[bill.id] ?? []
            // M5-X00: a free schedule shows its next unpaid due day (from this cycle's start), the same rule as the obligations room.
            // The list shows the next one; a schedule due several times this cycle (weekly) adds the others to the cycle total.
            if let schedule = bill.recurrence {
                let from = cycle?.startDay ?? today, cycleEnd = max(cycle?.expectedEndDay ?? today.adding(days: cycle?.input.expectedLengthDays ?? 30), today.adding(days: 1))
                let unpaid = try repo.unpaidRecurring(schedule, from: from, before: max(today, from).adding(days: 400), payments: payments, zone: zone)
                if let next = unpaid.first {
                    due.append(.init(id: bill.id, name: bill.name, amountMinor: bill.amountMinor, due: next))
                    flexibleExtraMinor += bill.amountMinor * unpaid.dropFirst().filter { $0 < cycleEnd }.count
                }
                continue
            }
            guard bill.kind == "bill", let day = bill.dueDay else { continue }
            var parts = calendar.dateComponents([.year, .month], from: now)
            let range = calendar.range(of: .day, in: .month, for: now)!
            parts.day = min(day, range.count)
            guard let date = calendar.date(from: parts) else { continue }
            // A bill paid early (rent due the 1st, paid the 30th, maybe in the last cycle) counts for that due date.
            let earliest = calendar.date(byAdding: .day, value: -15, to: date) ?? date
            let paid = payments.contains { calendar.isDate($0, equalTo: date, toGranularity: .month) || ($0 >= earliest && $0 < date) }
            if !paid { due.append(.init(id: bill.id, name: bill.name, amountMinor: bill.amountMinor, due: .containing(date, in: zone))) }
        }
        due.sort { $0.due == $1.due ? $0.id.uuidString < $1.id.uuidString : $0.due < $1.due }
        let length = cycle?.input.expectedLengthDays ?? 30
        let cycleObligations = due.filter { $0.due < max(cycle?.expectedEndDay ?? today.adding(days: length), today.adding(days: 1)) }.reduce(0) { $0 + $1.amountMinor } + flexibleExtraMinor
        let surplusEnvelopeIDs = Set(envelopes.filter { $0.role == "surplus" }.map(\.id))
        let history = Dictionary(grouping: allocations.filter {
            !$0.idempotencyKey.hasPrefix("move:") && ($0.target == "surplus" || $0.targetID.map(surplusEnvelopeIDs.contains) == true)
        }, by: { $0.cycleID })
            .sorted { ($0.value.map(\.createdAt).min() ?? .distantPast) < ($1.value.map(\.createdAt).min() ?? .distantPast) }.suffix(6).map { $0.value.reduce(0) { $0 + $1.amountMinor } }
        let reserveReading = ReserveEngine.read(balanceMinor: reserve, dailyMinor: cycle?.headline.todayAllowanceMinor, cycleLengthDays: length, obligationsPerCycleMinor: cycleObligations)
        return .init(salaryDates: try MoneyHomeProjectionBuilder.salaryForecastDays(context: context, cycle: cycle, today: today, zone: zone), cycle: cycle, basis: basis, currency: currency, hasAccounts: !accounts.isEmpty,
            cardCount: cardCount, hawlKey: hawlKey,
            unknownBalanceCount: accounts.filter { $0.ownership == "mine" && $0.tracked && $0.balanceAt == nil }.count,
            knownBalanceCount: accounts.filter { $0.ownership == "mine" && $0.tracked && $0.balanceAt != nil }.count,
            pendingCount: try repo.pendingDecisionCount(), reserveMinor: reserve, surplusMinor: surplus, reserveRunway: reserveReading.runway, reserveDailies: reserveReading.wholeDailies, obligationsPerCycleMinor: cycleObligations,
            surplusHistory: history, envelopes: goals, limits: limits.sorted { $0.title < $1.title }, obligations: due,
            unratedAccountNames: try repo.unratedAccountNames(at: now))
    }
}
