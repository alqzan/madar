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
        /// Bank accounts identified in messages, plus one explicitly unknown source for textless bank movements.
        /// The trial clears provisional checkpoints unless confirmed bank balance evidence establishes one.
        case saveAccount(command: UUID, id: UUID, kind: String, bank: String?, last4: String?, balanceAt: Date)
        case saveCard(command: UUID, id: UUID, last4: String, bank: String, kind: String, accountID: UUID?)
        case saveRule(command: UUID, merchant: String, categoryID: UUID)
        /// A stored bank message re-enters through the real intake; `transactionID` is the movement it makes.
        case ingest(command: UUID, text: String, sender: String, receivedAt: Date, transactionID: UUID, categoryID: UUID?)
        /// A textless bank expense on its stored day; `earlierCards` may resolve its provisional unknown source.
        case logExpense(command: UUID, amountMinor: Int, merchant: String?, categoryID: UUID?, eventAt: Date, accountID: UUID)
    }

    public struct Plan: Equatable, Sendable {
        public var createCategories: [Category] = []
        public var steps: [Step] = []
        public var counts: [String: Int] = [:]
        public var earlierCards: [UUID: UUID] = [:]
        public var balanceEvidence: [UUID: BalanceEvidence] = [:]
    }

    public struct BalanceEvidence: Equatable, Sendable {
        public var amountMinor: Int
        public var at: Date
        public var transactionID: UUID
    }

    /// Only a labelled account line, never the card's first four digits or a counterparty's account.
    public static func fundingLast4(in text: String) -> String? {
        let pattern = #"(?im)^\s*(?:حساب|من حساب|الحساب|account)\s*:?\s*\*?(\d{4})\*?\s*$"#
        let clean = BankMessageParser.clean(text)
        guard let r = try? NSRegularExpression(pattern: pattern),
              let match = r.firstMatch(in: clean, range: NSRange(clean.startIndex..., in: clean)),
              let range = Range(match.range(at: 1), in: clean) else { return nil }
        return String(clean[range])
    }

    /// Balance printed after a movement = opening + signed movements through that movement.
    public static func openingBalance(printed: Int, signedMovements: [Int]) -> Int? {
        var value = printed
        for delta in signedMovements {
            let next = value.subtractingReportingOverflow(delta)
            guard !next.overflow else { return nil }; value = next.partialValue
        }
        return value
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
        let counterparty: String?; let balanceKind: String?
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
        var explicitFunding: [String: Set<String>] = [:]
        var merchantCards: [String: Set<String>] = [:]
        var parsedRows: [(Row, ParsedBankMessage, Date, String)] = []
        for row in rows {
            guard let text = row.rawText, !text.isEmpty, let date = row.date, let at = stamp.date(from: date + " " + (row.time ?? "12:00")) else { continue }
            let sender = sender(row)
            guard !sender.isEmpty else { continue }
            let parsed = BankMessageParser.parse(text, timeZone: timeZone, receivedAt: at, sender: sender, trackedWallets: [])
            parsedRows.append((row, parsed, parsed.eventAt ?? at, sender))
            guard let last4 = parsed.last4 else { continue }
            if let kind = parsed.cardKind {
                let key = sender + "|" + last4
                if cards[key] == nil { cards[key] = (sender, kind.rawValue) }
                if let merchant = parsed.merchant ?? row.counterparty, !normalize(merchant).isEmpty {
                    merchantCards[normalize(merchant), default: []].insert(key)
                }
                if kind == .debit, let account = fundingLast4(in: text) {
                    let accountKey = sender + "|" + account
                    accounts[accountKey] = (sender, account)
                    explicitFunding[key, default: []].insert(accountKey)
                }
            }
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
        var cardAccounts: [String: UUID] = [:]
        var unidentifiedAccounts: Set<UUID> = []
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
                if let named = explicitFunding[key], named.count == 1, let accountKey = named.first {
                    account = uuid("LegacyAccount:" + accountKey)
                } else if explicitFunding[key] != nil { count("card.unlinked") }
                else if let known = funding[item.bank], known.count > 1 {
                    // Mada proves a funding account exists, but never which of several named accounts it is.
                    // Keep a card-specific, explicitly unidentified account with no balance evidence; do not guess
                    // an existing account or leave an otherwise complete purchase blocked on that choice.
                    let identity = "LegacyAccount:unidentified:" + key
                    let id = uuid(identity); account = id
                    unidentifiedAccounts.insert(id)
                    plan.steps.append(.saveAccount(command: uuid("LegacyAccountCommand:unidentified:" + key), id: id,
                                                   kind: "unidentified", bank: item.bank, last4: nil, balanceAt: opening))
                    count("account.unidentifiedFunding")
                }
                else if let known = funding[item.bank]?.first { account = known } else {
                    let id = uuid("LegacyAccount:" + item.bank)
                    plan.steps.append(.saveAccount(command: uuid("LegacyAccountCommand:" + item.bank), id: id, kind: "current", bank: item.bank, last4: nil,
                                                   balanceAt: opening))
                    funding[item.bank] = [id]; account = id; count("account.bank")
                }
            }
            cardAccounts[key] = account
            plan.steps.append(.saveCard(command: uuid("LegacyCardCommand:" + key), id: uuid("LegacyCard:" + key), last4: last4, bank: item.bank, kind: item.kind, accountID: account))
            count("card." + item.kind)
        }
        // Available credit never establishes cash. A debit/account balance must identify its own account.
        for (row, parsed, at, sender) in parsedRows {
            guard row.balanceKind != "credit_available", parsed.cardKind != .credit, parsed.cardKind != .prepaid,
                  let balance = parsed.balanceMinor, parsed.currency == "SAR", let last4 = parsed.last4 else { continue }
            // A masked number on an unclassified Visa/card message is not account-balance evidence.
            if parsed.cardKind == nil {
                guard let text = row.rawText, fundingLast4(in: text) == last4,
                      !BankMessageParser.clean(text).localizedCaseInsensitiveContains("بطاقة"),
                      !BankMessageParser.clean(text).localizedCaseInsensitiveContains("card") else { continue }
            }
            let key = sender + "|" + last4
            let account = parsed.cardKind == .debit ? cardAccounts[key]
                : accounts[key].map { _ in uuid("LegacyAccount:" + key) }
            // Until identity is resolved this could be one of the named accounts, so never count its cash twice.
            guard let account, !unidentifiedAccounts.contains(account), plan.balanceEvidence[account].map({ at < $0.at }) ?? true else { continue }
            let command = uuid("LegacyMessage:" + row.id)
            let message = uuid("BankMessage:\(command.uuidString):0")
            plan.balanceEvidence[account] = .init(amountMinor: balance, at: at, transactionID: uuid("BankMovement:\(message.uuidString)"))
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
                // Exact merchant identity with only one observed card is evidence; an amount alone isn't.
                // Ambiguous and unseen merchants retain the explicit unknown source.
                if let note, let candidates = merchantCards[normalize(note)], candidates.count == 1, let card = candidates.first {
                    plan.earlierCards[uuid("LegacyExpense:" + row.id)] = uuid("LegacyCard:" + card)
                    count("earlier.cardMatched")
                } else { count("earlier.cardUnknown") }
                count("row.manual")
            }
        }
        return plan
    }
}
