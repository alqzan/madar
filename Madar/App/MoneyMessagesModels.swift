import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// One draft movement read from a bank message, waiting for ✓ or ✕.
struct MoneyMessageDraft: Identifiable, Equatable {
    enum Direction { case out, incoming, neutral }
    var id: UUID
    var sender: String
    var title: String
    var kindLabel: String
    var payment: String?
    var amountMinor: Int
    var currency: String
    var direction: Direction
    var possibleDuplicate: Bool
    /// A fact the data already holds (linked obligation, paired own accounts, card payment), never invented.
    var note: String?
    /// «الواضح»: confirmable as read, with no choice left to the user (§7.5; DECISIONS 16 Oct).
    var clear: Bool
    var at: Date
}

struct MoneyMessageStatement: Identifiable, Equatable {
    var id: UUID
    var sender: String
    var cardName: String?
    var last4: String
    var statementMinor: Int
    var minimumMinor: Int?
    var due: GregorianDay?
    var at: Date
    /// Statement minus the card's recorded purchases since the previous close; nil without a previous close.
    var differenceMinor: Int?
}

struct MoneyMessageLook: Identifiable, Equatable {
    var id: UUID
    var sender: String
    var excerpt: String
    var at: Date
}

struct MoneyMessagesReading: Equatable {
    var today: GregorianDay
    var shortcutToday: Int
    var pending: Int
    var spentCount: Int, spentMinor: Int
    var incomingCount: Int, incomingMinor: Int
    var statements: [MoneyMessageStatement]
    var drafts: [MoneyMessageDraft]
    var looks: [MoneyMessageLook]
    /// money.confirmClear takes at most 100 ids; a longer paste is confirmed in more than one press.
    var clearIDs: [UUID] { Array(drafts.filter(\.clear).map(\.id).prefix(100)) }
}

extension AppMoneyService {
    static let kindLabels = ["expense": "شراء", "fee": "رسوم", "withdrawal": "سحب نقدي", "transfer": "تحويل", "income": "إيداع", "salary": "راتب",
                             "refund": "استرداد", "cardPayment": "سداد بطاقة", "repayment": "قسط", "billPayment": "فاتورة", "cashback": "استرداد نقدي"]

    func loadMessages(at instant: Date? = nil) throws -> MoneyMessagesReading {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = instant ?? app.prayerNow()
        let zone = app.activePlace.timeZone, today = try DiaryLineRenderer.today(context: context, now: now)
        func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter(live)
        let rows = try context.fetch(FetchDescriptor<MoneyTransaction>()).filter(live)
        let cards = try context.fetch(FetchDescriptor<Card>()).filter(live)
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter(live)
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter(live)
        let statements = try context.fetch(FetchDescriptor<Statement>()).filter(live)
        let home = app.string("core.currency")
        let open = ["needsLook", "possibleDuplicate"]
        let byMessage = Dictionary(rows.compactMap { row in row.messageID.map { ($0, row) } }, uniquingKeysWith: { first, _ in first })
        // Today follows core.dayStart: a movement by its stored dayKey, a message without one by its civil day.
        let shortcut = messages.filter { message in
            guard message.channel == "shortcut" else { return false }
            if let row = byMessage[message.id], !row.dayKey.isEmpty { return row.dayKey == today.description }
            return GregorianDay.containing(message.receivedAt, in: zone) == today
        }.count
        func direction(_ row: MoneyTransaction) -> MoneyMessageDraft.Direction {
            switch row.kind {
            case "income", "salary", "refund", "cashback": .incoming
            case "transfer": row.fromAccountID != nil && row.toAccountID != nil ? .neutral : row.toAccountID != nil ? .incoming : .out
            case "cardPayment": .neutral
            default: .out
            }
        }
        // «مصروف» and «وارد» count what the user confirmed today from bank messages (nothing is added without them).
        let confirmedToday = rows.filter { $0.reviewState == "ok" && $0.source == "bank" && $0.dayKey == today.description && !$0.ignoredFromBudget }
        let spent = confirmedToday.filter { direction($0) == .out }, incoming = confirmedToday.filter { direction($0) == .incoming }
        // A big expense waits for its own flow (mal.bigExpenseDays × today's allowance), so it is never «واضح».
        let daily = try repo.cycle(at: now)?.headline.todayAllowanceMinor
        let bigFrom = daily.map { $0 * max(2, Int(app.values["mal.bigExpenseDays"].flatMap { if case .number(let n) = $0 { Int(n) } else { nil } } ?? 3)) }
        func cardName(_ id: UUID?) -> String? { cards.first { $0.id == id }?.name }
        func accountName(_ id: UUID?) -> String? { accounts.first { $0.id == id }?.name }
        let confirmable = MoneyMutationHandler.confirmableAsRead(rows.filter { $0.reviewState == "needsLook" && $0.messageID != nil }.map(\.id), container: app.container, now: now)
        var drafts: [MoneyMessageDraft] = []
        for row in rows where open.contains(row.reviewState) && row.messageID != nil {
            let message = messages.first { $0.id == row.messageID }
            let dir = direction(row)
            var note: String?
            if let obligation = obligations.first(where: { $0.id == row.obligationID }) { note = "مرتبطة بـ" + obligation.name }
            else if row.kind == "transfer" && dir == .neutral { note = "تحويل بين حساباتك، لا مصروف" }
            else if row.kind == "cardPayment" { note = "سداد بطاقة، لا مصروف" }
            let resolvable = ["expense", "fee", "withdrawal", "income", "transfer", "cardPayment"].contains(row.kind) && confirmable.contains(row.id)
            let big = dir == .out && bigFrom.map { $0 > 0 && row.homeAmountMinor >= $0 } == true
            let clear = row.reviewState == "needsLook" && resolvable && !big && row.currency == home
            drafts.append(.init(id: row.id, sender: message?.sender ?? "", title: row.merchant ?? row.counterparty ?? Self.kindLabels[row.kind] ?? "حركة",
                kindLabel: Self.kindLabels[row.kind] ?? "حركة", payment: cardName(row.cardID) ?? accountName(row.fromAccountID ?? row.toAccountID),
                amountMinor: row.amountMinor, currency: row.currency, direction: dir, possibleDuplicate: row.reviewState == "possibleDuplicate",
                note: note, clear: clear, at: row.eventAt))
        }
        drafts.sort { $0.clear == $1.clear ? $0.at > $1.at : !$0.clear }
        var statementCards: [MoneyMessageStatement] = []
        var looks: [MoneyMessageLook] = []
        for message in messages where open.contains(message.status) && byMessage[message.id] == nil {
            let parsed = message.parsedJSON.flatMap { try? JSONDecoder().decode(MoneyParsedFields.self, from: $0) }
            if message.kind == BankMessageKind.statement.rawValue, let parsed, let amount = parsed.statementDueMinor, let last4 = parsed.last4 {
                let identity = CardStatements.identify(sender: message.sender, last4: last4, cards: cards.filter { $0.kind == "credit" }.map { .init(id: $0.id.uuidString, bank: $0.bank, last4: $0.last4, aliases: $0.aliases) })
                var card: Card?
                if case .known(let raw) = identity { card = cards.first { $0.id.uuidString == raw } }
                var difference: Int?
                if let card, let previous = statements.filter({ $0.cardID == card.id && $0.closeDate < message.receivedAt }).max(by: { $0.closeDate < $1.closeDate }) {
                    let recorded = rows.filter { $0.cardID == card.id && $0.reviewState == "ok" && $0.eventAt >= previous.closeDate && $0.eventAt < message.receivedAt }
                        .reduce(0) { total, row in ["expense", "fee"].contains(row.kind) ? total + row.homeAmountMinor : row.kind == "refund" ? total - row.homeAmountMinor : total }
                    if recorded != amount { difference = amount - recorded }
                }
                statementCards.append(.init(id: message.id, sender: message.sender, cardName: card?.name, last4: last4, statementMinor: amount,
                    minimumMinor: parsed.minimumDueMinor, due: parsed.dueDate.map { .containing($0, in: zone) }, at: message.receivedAt, differenceMinor: difference))
            } else {
                let first = message.text.split(whereSeparator: \.isNewline).prefix(3).joined(separator: " ")
                looks.append(.init(id: message.id, sender: message.sender, excerpt: String(first.prefix(140)), at: message.receivedAt))
            }
        }
        return .init(today: today, shortcutToday: shortcut, pending: try repo.pendingDecisionCount(),
            spentCount: spent.count, spentMinor: spent.reduce(0) { $0 + $1.homeAmountMinor },
            incomingCount: incoming.count, incomingMinor: incoming.reduce(0) { $0 + $1.homeAmountMinor },
            statements: statementCards.sorted { $0.at > $1.at }, drafts: drafts, looks: looks.sorted { $0.at > $1.at })
    }

    /// Splits pasted text into messages: one per blank-line-separated block (the paste fallback, §7.5 F09).
    static func pastedMessages(_ text: String) -> [String] {
        text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty && $0.count <= 2000 }.prefix(500).map { $0 }
    }
}
