import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneySinceDay: Identifiable, Equatable {
    var day: GregorianDay
    var id: String { day.description }
    var spentMinor: Int
    /// «يومك» that day (after envelope drips), nil outside the current cycle.
    var allowanceMinor: Int?
    var salaryMinor: Int
    var messages: Int
    var statements: Int
    var pending: Int
    var envelopesMinor: Int
    var over: Bool { allowanceMinor.map { spentMinor > $0 } ?? false }
}

struct MoneySinceStatement: Identifiable, Equatable {
    var id: UUID
    var title: String
    var amountMinor: Int
    var due: GregorianDay?
}

struct MoneySinceReading: Equatable {
    var today: GregorianDay
    var days: [MoneySinceDay]
    var availableNowMinor: Int?
    var nextObligation: MoneyHomeObligation?
    var shortcutCount: Int
    var silentDays: Int?
    var salaryMinor: Int
    var salaryDay: GregorianDay?
    var envelopesMinor: Int
    var spentMinor: Int
    var allowanceMinor: Int
    var statements: [MoneySinceStatement]
    var pending: Int
}

extension AppMoneyService {
    static let lastVisitKey = "sys.moneyLastVisit"

    func lastVisit() -> Date? {
        let key = Self.lastVisitKey
        guard let row = try? ModelContext(app.container).fetch(FetchDescriptor<DeviceSetting>(predicate: #Predicate { $0.key == key && $0.deletedAt == nil })).first,
              let raw = try? JSONDecoder().decode(String.self, from: row.valueJSON) else { return nil }
        return ISO8601DateFormatter().date(from: raw)
    }

    /// §7.5 «بعد غياب»: opens first when the last visit was on an earlier day (and the setting is on).
    func sinceDue(today: GregorianDay) -> Bool {
        guard app.bool("mal.sinceLastVisit"), let last = lastVisit(),
              let day = try? DiaryLineRenderer.today(context: ModelContext(app.container), now: last) else { return false }
        return day < today
    }

    func loadSince(home: MoneyHomeReading, at instant: Date? = nil) throws -> MoneySinceReading {
        guard app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let context = ModelContext(app.container), now = instant ?? app.prayerNow(), zone = app.activePlace.timeZone
        let today = try DiaryLineRenderer.today(context: context, now: now)
        // Every instant becomes a day by core.dayStart, as the home and the stored dayKeys do.
        func budgetDay(_ instant: Date) -> GregorianDay { (try? DiaryLineRenderer.today(context: context, now: instant)) ?? GregorianDay.containing(instant, in: zone) }
        let lastDay = lastVisit().map(budgetDay) ?? today
        // The days since the last visit, the visit day included, at most a week (the newest seven).
        let first = max(lastDay, today.adding(days: -6))
        let span = (0...max(0, MadarCalendarDays.distance(from: first, to: today))).map { first.adding(days: $0) }
        func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
        let rows = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter(live)
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter(live)
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter(live)
        let cards = try context.fetch(FetchDescriptor<Card>()).filter(live)
        let byMessage = Dictionary(rows.compactMap { row in row.messageID.map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
        // Resolved once per message (prayer times per instant), then read by every column.
        let messageDays: [UUID: GregorianDay] = Dictionary(messages.map { m in
            if let row = byMessage[m.id], let day = try? GregorianDay(row.dayKey) { return (m.id, day) }
            return (m.id, budgetDay(m.receivedAt))
        }, uniquingKeysWith: { first, _ in first })
        func messageDay(_ m: BankMessage) -> GregorianDay { messageDays[m.id] ?? today }
        let fundDays: [UUID: GregorianDay] = Dictionary(allocations.filter { $0.kind == "fund" && $0.target == "envelope" }.map { ($0.id, budgetDay($0.createdAt)) }, uniquingKeysWith: { first, _ in first })
        let cycle = home.cycle
        let days = span.map { day -> MoneySinceDay in
            let key = day.description
            let index = cycle.map { MadarCalendarDays.distance(from: $0.startDay, to: day) + 1 }
            let inCycle = cycle != nil && (index ?? 0) >= 1 && (index ?? 0) <= max(cycle!.elapsedDays, 1)
            let dayRows = rows.filter { $0.dayKey == key }
            let salary = dayRows.filter { $0.kind == "salary" && $0.reviewState == "ok" }.reduce(0) { $0 + $1.homeAmountMinor }
            let ids = Set(dayRows.map(\.id))
            let funded = allocations.filter { $0.kind == "fund" && $0.target == "envelope" && fundDays[$0.id] == day }.reduce(0) { $0 + $1.amountMinor }
            let dayMessages = messages.filter { messageDay($0) == day }
            return .init(day: day, spentMinor: inCycle ? cycle!.spent[index!] ?? 0 : -allocations.filter { $0.target == "daily" && $0.kind == "spend" && $0.transactionID.map(ids.contains) == true }.reduce(0) { $0 + $1.amountMinor },
                allowanceMinor: inCycle ? CycleEngine.day(index!, cycle!.input).dailyMinor : nil,
                salaryMinor: salary, messages: dayMessages.count, statements: dayMessages.filter { $0.kind == BankMessageKind.statement.rawValue }.count,
                pending: dayMessages.filter { ["needsLook", "possibleDuplicate"].contains($0.status) }.count, envelopesMinor: max(0, funded))
        }
        let shortcut = messages.filter { $0.channel == "shortcut" }
        let lastShortcut = shortcut.map(\.receivedAt).max()
        let silent = lastShortcut.map { MadarCalendarDays.distance(from: budgetDay($0), to: today) }.flatMap { $0 >= 3 ? $0 : nil }
        let statements: [MoneySinceStatement] = messages.filter { $0.kind == BankMessageKind.statement.rawValue && span.contains(messageDay($0)) }.compactMap { m in
            guard let parsed = m.parsedJSON.flatMap({ try? JSONDecoder().decode(MoneyParsedFields.self, from: $0) }), let amount = parsed.statementDueMinor else { return nil }
            let card = cards.first { $0.last4 == parsed.last4 && $0.kind == "credit" }
            return .init(id: m.id, title: card?.name ?? "بطاقة " + (parsed.last4 ?? ""), amountMinor: amount, due: parsed.dueDate.map { .containing($0, in: zone) })
        }
        let salaryDay = days.last(where: { $0.salaryMinor > 0 })?.day
        return .init(today: today, days: days, availableNowMinor: cycle?.headline.availableNowMinor, nextObligation: home.obligations.first { $0.due >= today },
            shortcutCount: shortcut.filter { span.contains(messageDay($0)) }.count, silentDays: silent,
            salaryMinor: days.reduce(0) { $0 + $1.salaryMinor }, salaryDay: salaryDay, envelopesMinor: days.reduce(0) { $0 + $1.envelopesMinor },
            // Totals compare like with like: only days inside the current cycle carry «يومك».
            spentMinor: days.filter { $0.allowanceMinor != nil }.reduce(0) { $0 + $1.spentMinor }, allowanceMinor: days.reduce(0) { $0 + ($1.allowanceMinor ?? 0) },
            statements: statements, pending: home.pendingCount)
    }
}
