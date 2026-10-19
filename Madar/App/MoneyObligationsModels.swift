import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// One due amount: an unpaid instalment, a bill's or subscription's next occurrence, or a card statement.
struct MoneyObligationDue: Identifiable, Equatable {
    enum Group: String { case loan, installment, bill, subscription, statement }
    var id: String
    var obligationID: UUID?
    var group: Group
    var name: String
    var amountMinor: Int
    var due: GregorianDay
    /// Instalments: paid and total counts, what stays after this one, and the last due day.
    var paidCount: Int? = nil
    var totalCount: Int? = nil
    var remainingMinor: Int? = nil
    var lastDue: GregorianDay? = nil
    var dueDay: Int? = nil
    var minimumMinor: Int? = nil
    var estimated = false
    /// M5-X00: a free schedule in words («كل ٦ أشهر»).
    var schedule: String? = nil
}

struct MoneyLadderMonth: Identifiable, Equatable {
    var id: String
    var label: String
    /// The Hijri month over the middle of that Gregorian month (both calendars on every date).
    var hijri: String
    var loanMinor: Int
    var installmentMinor: Int
    var billMinor: Int
    var subscriptionMinor: Int = 0
    var total: Int { loanMinor + installmentMinor + billMinor + subscriptionMinor }
}

struct MoneyLadderEnding: Identifiable, Equatable {
    var id: String
    var name: String
    var lastDue: GregorianDay
    var returnsMinor: Int
}

struct MoneyObligationsReading: Equatable {
    var today: GregorianDay
    var cycleStart: GregorianDay
    var cycleEnd: GregorianDay
    /// Due inside this cycle, in due order.
    var cycle: [MoneyObligationDue]
    var fromSalaryMinor: Int
    var cardsMinor: Int
    var totalMinor: Int { fromSalaryMinor + cardsMinor }
    var ladder: [MoneyLadderMonth]
    var endings: [MoneyLadderEnding]
    var installments: [MoneyObligationDue]
    var bills: [MoneyObligationDue]
    var subscriptions: [MoneyObligationDue]
    var subscriptionSuggestions: [SubscriptionSuggestionEngine.Suggestion]
    var statements: [MoneyObligationDue]
}

extension AppMoneyService {
    func relative(_ from: GregorianDay, _ to: GregorianDay) -> String {
        let n = MadarCalendarDays.distance(from: from, to: to)
        switch n {
        case ..<0: return "فات موعده"
        case 0: return "اليوم"
        case 1: return "غدًا"
        case 2: return "بعد يومين"
        default: return "بعد " + days(n)
        }
    }

    func loadObligations() throws -> MoneyObligationsReading {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
        let context = ModelContext(app.container), now = app.prayerNow(), zone = app.activePlace.timeZone, home = app.string("core.currency")
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let cycle = try MoneyRepository(context: context).cycle(at: now)
        let start = cycle?.startDay ?? today, end = cycle?.expectedEndDay ?? today.adding(days: 30)
        func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
        let liveObligations = try context.fetch(FetchDescriptor<Obligation>()).filter(live)
        let obligations = liveObligations.filter { $0.currency == home }
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter(live)
        let confirmed = try MoneyRepository(context: context).confirmedTransactions()
        let paidBills = confirmed.filter { $0.obligationID != nil }
        let subscriptionSuggestions = SubscriptionSuggestionEngine.suggestions(
            charges: confirmed.filter { $0.currency.uppercased() == home.uppercased() }.map {
                .init(id: $0.id.uuidString, kind: $0.kind, reviewState: $0.reviewState, source: $0.source,
                      merchant: $0.merchant, counterparty: $0.counterparty, currency: $0.currency, amountMinor: $0.amountMinor,
                      cardID: $0.cardID?.uuidString, accountID: $0.fromAccountID?.uuidString,
                      obligationID: $0.obligationID?.uuidString, at: $0.eventAt)
            },
            existingObligationNames: liveObligations.filter { $0.kind == "bill" || $0.kind == "subscription" }.map(\.name),
            now: now, timeZone: zone)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone

        // Every unpaid instalment, with its plan's progress.
        var instalments: [MoneyObligationDue] = []
        for obligation in obligations where !obligation.isRecurring {
            let mine = items.filter { $0.obligationID == obligation.id }.sorted { $0.seq == $1.seq ? $0.dueDate < $1.dueDate : $0.seq < $1.seq }
            let unpaid = mine.filter { $0.paidMinor < $0.amountMinor }
            let last = mine.map(\.dueDate).max().map { GregorianDay.containing($0, in: zone) }
            let left = unpaid.reduce(0) { $0 + $1.amountMinor - $1.paidMinor }
            for item in unpaid {
                instalments.append(.init(id: item.id.uuidString, obligationID: obligation.id, group: obligation.kind == "loan" ? .loan : .installment,
                    name: obligation.provider.map { obligation.name.isEmpty ? $0 : $0 + "، " + obligation.name } ?? obligation.name, amountMinor: item.amountMinor - item.paidMinor,
                    due: .containing(item.dueDate, in: zone), paidCount: mine.count - unpaid.count, totalCount: mine.count, remainingMinor: left, lastDue: last))
            }
        }
        // A bill falls once a month on its day (clamped); a month already paid by a linked movement is skipped.
        // M5-X00: a free schedule (bill or subscription) lists every unpaid due day the engine gives over the same months.
        let digits = MadarNumberFormatter(style: app.string("core.numerals") == "western" ? .western : .hindi)
        func occurrences(_ bill: Obligation, months: Int) -> [MoneyObligationDue] {
            if let schedule = bill.recurrence {
                guard let horizon = calendar.date(byAdding: .month, value: months, to: start.date(in: zone)) else { return [] }
                let payments = paidBills.filter { $0.obligationID == bill.id }.map(\.eventAt)
                return ObligationSchedule.unpaid(schedule, from: start, before: .containing(horizon, in: zone), payments: payments, zone: zone).map { day in
                    .init(id: bill.id.uuidString + ":" + day.description, obligationID: bill.id, group: bill.kind == "subscription" ? .subscription : .bill, name: bill.name,
                          amountMinor: bill.amountMinor, due: day, schedule: RecurrencePhrase.every(schedule, digits: digits))
                }
            }
            guard bill.kind == "bill", let day = bill.dueDay else { return [] }
            return (0..<months).compactMap { offset in
                guard let month = calendar.date(byAdding: .month, value: offset, to: start.date(in: zone)), let range = calendar.range(of: .day, in: .month, for: month) else { return nil }
                var parts = calendar.dateComponents([.year, .month], from: month); parts.day = min(day, range.count)
                guard let date = calendar.date(from: parts) else { return nil }
                if paidBills.contains(where: { $0.obligationID == bill.id && calendar.isDate($0.eventAt, equalTo: date, toGranularity: .month) }) { return nil }
                return .init(id: bill.id.uuidString + ":\(offset)", obligationID: bill.id, group: .bill, name: bill.name, amountMinor: bill.amountMinor, due: .containing(date, in: zone), dueDay: day)
            }
        }
        let bills = obligations.filter { $0.kind == "bill" }, subscriptions = obligations.filter { $0.kind == "subscription" }
        let billDues = (bills + subscriptions).flatMap { occurrences($0, months: 13) }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter(live)
        let statements: [MoneyObligationDue] = try context.fetch(FetchDescriptor<Statement>()).filter { live($0) && $0.dueDate != nil && $0.statementMinor > 0 }.compactMap { s in
            let due = GregorianDay.containing(s.dueDate!, in: zone)
            guard due >= today else { return nil }
            return .init(id: s.id.uuidString, group: .statement, name: "كشف " + (cards.first { $0.id == s.cardID }?.name ?? "بطاقة"), amountMinor: s.statementMinor,
                         due: due, minimumMinor: s.minimumDueMinor, estimated: s.closeDateSource == "estimated")
        }

        let inCycle: (MoneyObligationDue) -> Bool = { $0.due >= start && $0.due < end }
        let cycleDues = (instalments.filter(inCycle) + billDues.filter(inCycle) + statements.filter(inCycle)).sorted { $0.due == $1.due ? $0.id < $1.id : $0.due < $1.due }

        // «سلّم الأقساط»: the next twelve months, each a stack of loan, instalments and bills.
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "ar"); formatter.timeZone = zone; formatter.dateFormat = "MMM"
        let hijri = DateFormatter(); hijri.calendar = Calendar(identifier: .islamicUmmAlQura); hijri.locale = Locale(identifier: "ar"); hijri.timeZone = zone; hijri.dateFormat = "MMMM"
        let monthKey: (GregorianDay) -> String = { String($0.description.prefix(7)) }
        let ladder: [MoneyLadderMonth] = (0..<12).compactMap { offset in
            guard let month = calendar.date(byAdding: .month, value: offset, to: today.date(in: zone)) else { return nil }
            let key = monthKey(.containing(month, in: zone))
            let these = instalments.filter { monthKey($0.due) == key }
            var middle = calendar.dateComponents([.year, .month], from: month); middle.day = 15
            return .init(id: key, label: formatter.string(from: month), hijri: hijri.string(from: calendar.date(from: middle) ?? month),
                loanMinor: these.filter { $0.group == .loan }.reduce(0) { $0 + $1.amountMinor },
                installmentMinor: these.filter { $0.group == .installment }.reduce(0) { $0 + $1.amountMinor },
                billMinor: billDues.filter { $0.group == .bill && monthKey($0.due) == key && $0.due >= today }.reduce(0) { $0 + $1.amountMinor },
                subscriptionMinor: billDues.filter { $0.group == .subscription && monthKey($0.due) == key && $0.due >= today }.reduce(0) { $0 + $1.amountMinor })
        }
        let horizon = ladder.last?.id ?? ""
        let endings: [MoneyLadderEnding] = Dictionary(grouping: instalments, by: { $0.obligationID! }).compactMap { _, dues in
            guard let lastDue = dues.map(\.due).max(), monthKey(lastDue) <= horizon, let final = dues.max(by: { $0.due < $1.due }) else { return nil }
            return .init(id: final.id, name: final.name, lastDue: lastDue, returnsMinor: final.amountMinor)
        }.sorted { $0.id < $1.id }

        let nextInstalments = Dictionary(grouping: instalments, by: { $0.obligationID! }).compactMap { $0.value.min { $0.due < $1.due } }.sorted { $0.due < $1.due }
        let next: ([Obligation]) -> [MoneyObligationDue] = { rows in
            rows.compactMap { bill in billDues.filter { $0.obligationID == bill.id && $0.due >= today }.min { $0.due < $1.due } }.sorted { $0.due < $1.due }
        }
        return .init(today: today, cycleStart: start, cycleEnd: end, cycle: cycleDues,
                     fromSalaryMinor: cycleDues.filter { $0.group != .statement }.reduce(0) { $0 + $1.amountMinor },
                     cardsMinor: cycleDues.filter { $0.group == .statement }.reduce(0) { $0 + $1.amountMinor },
                     ladder: ladder, endings: endings, installments: nextInstalments, bills: next(bills), subscriptions: next(subscriptions),
                     subscriptionSuggestions: subscriptionSuggestions, statements: statements.sorted { $0.due < $1.due })
    }
}
