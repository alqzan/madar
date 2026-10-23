import Foundation

/// Owner money trial (item 17, dev-only): turns the old Madar backup's money part into the shipped commands, in order.
/// Pure: the caller supplies the store's live categories and the stable-identity function, and runs the steps through
/// the command bus. Every step carries a command id derived from the old row, so a second run is answered by the
/// command receipts and adds nothing.
public enum LegacyMoneyImport {
    public struct Category: Equatable, Sendable {
        public let id: UUID; public let name: String; public let order: Int
        public init(id: UUID, name: String, order: Int) { self.id = id; self.name = name; self.order = order }
    }

    public enum Step: Equatable, Sendable {
        /// An account the old app never kept: one holding account for its rows without a message (owner, 22 Oct: they came
        /// from an earlier automatic source, never typed by hand, and which card paid is unknown), and the bank accounts
        /// its messages name.
        /// The opening balance is unknown, so it is zero on the first day it is used (an owner decision, listed).
        case saveAccount(command: UUID, id: UUID, kind: String, bank: String?, last4: String?, balanceAt: Date)
        case saveCard(command: UUID, id: UUID, last4: String, bank: String, kind: String, accountID: UUID?)
        case saveRule(command: UUID, merchant: String, categoryID: UUID)
        /// A stored bank message re-enters through the real intake; `transactionID` is the movement it makes.
        case ingest(command: UUID, text: String, sender: String, receivedAt: Date, transactionID: UUID, categoryID: UUID?)
        /// A row the old app kept without a message: an expense on its own stored day, paid from the holding account.
        case logExpense(command: UUID, amountMinor: Int, merchant: String?, categoryID: UUID?, eventAt: Date, accountID: UUID)
    }

    public struct Plan: Equatable, Sendable {
        public var createCategories: [Category] = []
        public var steps: [Step] = []
        public var counts: [String: Int] = [:]
    }

    /// Spelling-level sameness only («بنزين» = « بنزين »، «مقاضى» = «مقاضي»); «مطاعم» is never «مطاعم وقهوة».
    public static func normalize(_ name: String) -> String {
        var s = name.split(whereSeparator: \.isWhitespace).joined(separator: " ").replacingOccurrences(of: "ـ", with: "")
        for (a, b) in [("أ", "ا"), ("إ", "ا"), ("آ", "ا"), ("ى", "ي"), ("ة", "ه")] { s = s.replacingOccurrences(of: a, with: b) }
        return s.lowercased()
    }

    /// Old amounts are JSON numbers in riyals; minor units go through their decimal spelling (12.3 → 1230, never 1229).
    public static func minor(_ value: Double) -> Int? {
        guard value.isFinite, value > 0 else { return nil }
        let scaled = (Decimal(string: String(value)) ?? Decimal(value)) * 100
        var rounded = Decimal(), copy = scaled
        NSDecimalRound(&rounded, &copy, 0, .plain)
        return NSDecimalNumber(decimal: rounded).intValue
    }

    private struct Backup: Decodable {
        let transactions: [Row]?; let categories: [OldCategory]?; let accounts: [OldAccount]?
        let merchantRules: [String: String]?; let deleted: [String: AnyDecodable]?
    }
    private struct Row: Decodable {
        let id: String; let date: String?; let time: String?; let amount: Double?; let category: String?
        let note: String?; let rawText: String?; let bank: String?
    }
    private struct OldCategory: Decodable { let id: String; let label: String? }
    private struct OldAccount: Decodable { let id: String; let kind: String?; let last4: String?; let bank: String?; let fundingKind: String? }
    private struct AnyDecodable: Decodable { init(from decoder: Decoder) throws {} }

    public static func plan(backup data: Data, existing: [Category], timeZone: TimeZone, uuid: (String) -> UUID) throws -> Plan {
        let backup = try JSONDecoder().decode(Backup.self, from: data)
        let deleted = Set((backup.deleted ?? [:]).keys)
        var plan = Plan()
        func count(_ key: String) { plan.counts[key, default: 0] += 1 }

        // Categories: an existing row of the same name is reused, the rest are created with ids from the old ids.
        var byName = Dictionary(existing.map { (normalize($0.name), $0.id) }, uniquingKeysWith: { first, _ in first })
        var map: [String: UUID] = [:]
        var order = (existing.map(\.order).max() ?? -1) + 1
        for old in backup.categories ?? [] where !deleted.contains(old.id) {
            let name = (old.label ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { count("category.unnamed"); continue }
            if let id = byName[normalize(name)] { map[old.id] = id; count("category.matched"); continue }
            let row = Category(id: uuid("LegacyCategory:" + old.id), name: name, order: order)
            order += 1; plan.createCategories.append(row); byName[normalize(name)] = row.id; map[old.id] = row.id; count("category.created")
        }

        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.timeZone = timeZone; stamp.dateFormat = "yyyy-MM-dd HH:mm"
        let rows = (backup.transactions ?? []).sorted { ($0.date ?? "", $0.time ?? "", $0.id) < ($1.date ?? "", $1.time ?? "", $1.id) }
            .filter { row in if deleted.contains(row.id) { count("row.deleted"); return false } else { return true } }

        // Most stored messages lost their sender. When every account the old app knew is at one bank, that bank is
        // the sender; otherwise the message keeps no sender and waits for the owner.
        let banks = Set((backup.accounts ?? []).compactMap { $0.bank?.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty })
        func sender(_ row: Row) -> String {
            if let bank = row.bank?.trimmingCharacters(in: .whitespaces), !bank.isEmpty { return bank }
            if banks.count == 1 { return banks.first! }
            return ""
        }

        // Cards and accounts come from what the messages themselves name (sender + last four + card kind), so the
        // shipped intake recognises each movement; the old app's own card list only adds cards no message names.
        var cards: [String: (bank: String, kind: String)] = [:], accounts: [String: (bank: String, last4: String)] = [:]
        for row in rows {
            guard let text = row.rawText, !text.isEmpty, let date = row.date, let at = stamp.date(from: date + " " + (row.time ?? "12:00")) else { continue }
            let sender = sender(row)
            guard !sender.isEmpty else { continue }
            let parsed = BankMessageParser.parse(text, timeZone: timeZone, receivedAt: at, sender: sender, trackedWallets: [])
            guard let last4 = parsed.last4 else { continue }
            if let kind = parsed.cardKind { if cards[sender + "|" + last4] == nil { cards[sender + "|" + last4] = (sender, kind.rawValue) } }
            else if accounts[sender + "|" + last4] == nil { accounts[sender + "|" + last4] = (sender, last4) }
        }
        for old in backup.accounts ?? [] where !deleted.contains(old.id) && old.kind == "card" {
            // The old app sometimes stored an account's digits as a card; those stay accounts.
            let bank = old.bank ?? ""
            guard let last4 = old.last4, last4.count == 4, last4.allSatisfy(\.isNumber),
                  !cards.keys.contains(where: { $0.hasSuffix("|" + last4) && BankMessageIdentity.matches(bank, String($0.prefix { $0 != "|" })) }),
                  !accounts.values.contains(where: { $0.last4 == last4 }) else { count("account.skipped"); continue }
            cards[bank + "|" + last4] = (bank, old.fundingKind == "credit" ? "credit" : "debit")
        }
        // Every opening balance sits at the start of the first day the old app recorded anything.
        let opening = rows.compactMap(\.date).min().flatMap { stamp.date(from: $0 + " 00:00") } ?? Date(timeIntervalSince1970: 0)
        if rows.contains(where: { ($0.rawText ?? "").isEmpty }) {
            plan.steps.append(.saveAccount(command: uuid("LegacyAccountCommand:earlier"), id: uuid("LegacyAccount:earlier"), kind: "earlier", bank: nil, last4: nil, balanceAt: opening))
            count("account.earlier")
        }
        var funding: [String: [UUID]] = [:]
        for (key, item) in accounts.sorted(by: { $0.key < $1.key }) {
            let id = uuid("LegacyAccount:" + key)
            plan.steps.append(.saveAccount(command: uuid("LegacyAccountCommand:" + key), id: id, kind: "current", bank: item.bank, last4: item.last4, balanceAt: opening))
            funding[item.bank, default: []].append(id); count("account.bank")
        }
        for (key, item) in cards.sorted(by: { $0.key < $1.key }) {
            let last4 = String(key.split(separator: "|").last ?? "")
            var account: UUID? = nil
            if item.kind != "credit" {
                // A debit card draws on its bank's only account; with none named, one account for that bank is opened.
                // With two or more, which one it draws on is unknown: the card stays unlinked and the owner decides.
                if let known = funding[item.bank], known.count > 1 { count("card.unlinked") }
                else if let known = funding[item.bank]?.first { account = known } else {
                    let id = uuid("LegacyAccount:" + item.bank)
                    plan.steps.append(.saveAccount(command: uuid("LegacyAccountCommand:" + item.bank), id: id, kind: "current", bank: item.bank, last4: nil,
                                                   balanceAt: opening))
                    funding[item.bank] = [id]; account = id; count("account.bank")
                }
            }
            plan.steps.append(.saveCard(command: uuid("LegacyCardCommand:" + key), id: uuid("LegacyCard:" + key), last4: last4, bank: item.bank, kind: item.kind, accountID: account))
            count("card." + item.kind)
        }
        for (merchant, category) in (backup.merchantRules ?? [:]).sorted(by: { $0.key < $1.key }) {
            guard let id = map[category], !merchant.trimmingCharacters(in: .whitespaces).isEmpty, merchant.count <= 80 else { count("rule.skipped"); continue }
            plan.steps.append(.saveRule(command: uuid("LegacyRule:" + merchant), merchant: merchant, categoryID: id)); count("rule")
        }

        for row in rows {
            let category = row.category.flatMap { map[$0] }
            if row.category != nil && category == nil { count("row.unknownCategory") }
            if let text = row.rawText, !text.isEmpty {
                guard let date = row.date, let at = stamp.date(from: date + " " + (row.time ?? "12:00")) else { count("row.badDate"); continue }
                if (row.bank ?? "").trimmingCharacters(in: .whitespaces).isEmpty { count(banks.count == 1 ? "row.senderFromAccounts" : "row.noSender") }
                let command = uuid("LegacyMessage:" + row.id)
                let message = uuid("BankMessage:\(command.uuidString):0")
                plan.steps.append(.ingest(command: command, text: text, sender: sender(row), receivedAt: at,
                                          transactionID: uuid("BankMovement:\(message.uuidString)"), categoryID: category))
                count("row.message")
            } else {
                // Noon of the stored day: whatever core.dayStart is, the expense stays on the day the owner wrote it on.
                guard let date = row.date, let at = stamp.date(from: date + " 12:00") else { count("row.badDate"); continue }
                guard let amount = row.amount.flatMap(minor) else { count("row.badAmount"); continue }
                let note = row.note?.trimmingCharacters(in: .whitespacesAndNewlines)
                plan.steps.append(.logExpense(command: uuid("LegacyExpense:" + row.id), amountMinor: amount,
                                              merchant: note?.isEmpty == false ? String(note!.prefix(80)) : nil, categoryID: category, eventAt: at,
                                              accountID: uuid("LegacyAccount:earlier")))
                count("row.manual")
            }
        }
        return plan
    }
}
