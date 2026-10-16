import CryptoKit
import Foundation

/// M5-E03: the bank-message parser (§7.5 «رسائل البنك», RM6) and dedupe (F08 as amended by RM8).
/// Formats are learned from synthetic samples written from the spec; the owner's anonymised messages will extend them.
public enum BankMessageKind: String, Sendable, CaseIterable {
    case purchase, withdrawal, transferOut, transferIn, salary, income, cardPayment, statement, refund
    case declined, reversal, billPayment, fee, bnplInstalment, otp, marketing, unknown
}

public struct ParsedBankMessage: Equatable, Sendable {
    public enum CardKind: String, Sendable { case debit, credit, prepaid }
    public var kind: BankMessageKind
    public var amountMinor: Int?
    public var currency: String?
    /// The card or account's last four digits, when the message names one.
    public var last4: String?
    public var cardKind: CardKind?
    public var merchant: String?
    public var counterparty: String?
    public var biller: String?
    /// Tamara, Tabby.
    public var provider: String?
    /// RM6: the time printed in the message, when it carries one; nil → the device time is used.
    public var eventAt: Date?
    public var statementDueMinor: Int?
    public var minimumDueMinor: Int?
    public var dueDate: Date?
    public var balanceMinor: Int?
}

public enum BankMessageParser {
    public static let version = 1

    /// Digits and separators unified (Arabic-Indic → ASCII, «٫» → ".", «٬» → ","), tatweel removed; lines kept.
    public static func clean(_ text: String) -> String {
        var out = ""
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0660...0x0669: out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9: out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0x066B: out.append(".")
            case 0x066C: out.append(",")
            case 0x0640, 0x200E, 0x200F, 0x2066...0x2069, 0x202A...0x202E: continue
            default: out.unicodeScalars.append(scalar)
            }
        }
        return out
    }

    /// Latin keywords match whole words only («fee» is not inside «Coffee»); Arabic ones match as written.
    static func has(_ text: String, _ words: [String]) -> Bool {
        words.contains { word in
            guard word.unicodeScalars.allSatisfy({ $0.isASCII }) else { return text.localizedCaseInsensitiveContains(word) }
            let pattern = "(?<![A-Za-z])" + NSRegularExpression.escapedPattern(for: word) + "(?![A-Za-z])"
            return text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
        }
    }

    public static func classify(_ text: String) -> BankMessageKind {
        let t = clean(text)
        // Order matters: the dangerous and the specific first.
        if has(t, ["رمز التحقق", "رمز التفعيل", "كلمة المرور لمرة", "OTP", "verification code", "لا تشارك الرمز"]) { return .otp }
        if has(t, ["مرفوضة", "رفض العملية", "لم تتم العملية", "declined"]) { return .declined }
        if has(t, ["عكس عملية", "إلغاء عملية", "عكس العملية", "reversal", "reversed"]) { return .reversal }
        if has(t, ["تمارا", "tamara", "تابي", "tabby"]) { return .bnplInstalment }
        if has(t, ["كشف حساب البطاقة", "كشف البطاقة", "statement", "الحد الأدنى للسداد", "المبلغ المستحق"]) { return .statement }
        if has(t, ["سداد بطاقة", "سداد البطاقة", "card payment"]) { return .cardPayment }
        if has(t, ["سداد فاتورة", "سداد", "SADAD", "المفوتر"]) { return .billPayment }
        if has(t, ["استرداد", "refund", "مرتجع"]) { return .refund }
        if has(t, ["راتب", "salary", "payroll"]) { return .salary }
        if has(t, ["سحب صراف", "سحب نقدي", "ATM", "cash withdrawal"]) { return .withdrawal }
        if has(t, ["حوالة صادرة", "تحويل صادر", "تحويل إلى", "outgoing transfer"]) { return .transferOut }
        if has(t, ["حوالة واردة", "تحويل وارد", "incoming transfer"]) { return .transferIn }
        if has(t, ["شراء", "purchase", "Apple Pay", "مدى", "POS"]) { return .purchase }
        // After the movements: a transfer that mentions its fee is still the transfer.
        if has(t, ["رسوم", "عمولة", "fee"]) { return .fee }
        if has(t, ["إيداع", "deposit", "credited"]) { return .income }
        if has(t, ["عرض", "خصم حصري", "اشترك", "offer", "promo", "لإلغاء الاشتراك"]) { return .marketing }
        return .unknown
    }

    public static func parse(_ text: String, timeZone: TimeZone, exponents: CurrencyExponents = .specified) -> ParsedBankMessage {
        let t = clean(text), kind = classify(text)
        var result = ParsedBankMessage(kind: kind)
        // OTP and marketing: nothing is read out of them.
        guard kind != .otp, kind != .marketing else { return result }
        if kind == .statement {
            result.statementDueMinor = labelledAmount(t, ["المبلغ المستحق", "مبلغ الكشف", "Statement balance"], exponents)?.minor
            result.minimumDueMinor = labelledAmount(t, ["الحد الأدنى", "Minimum"], exponents)?.minor
            result.dueDate = labelledDate(t, ["تاريخ الاستحقاق", "Due date"], timeZone)
            result.currency = labelledAmount(t, ["المبلغ المستحق", "مبلغ الكشف", "Statement balance"], exponents)?.currency
        } else if let amount = firstAmount(t, exponents) {
            result.amountMinor = amount.minor; result.currency = amount.currency
        }
        result.balanceMinor = labelledAmount(t, ["الرصيد", "Balance"], exponents)?.minor
        result.last4 = first(#"\*\s?(\d{4})\b|\b(\d{4})\s?\*"#, in: t)
        result.eventAt = eventDate(t, timeZone)
        result.merchant = labelled(t, ["لدى", "من متجر", "at"])
        result.biller = labelled(t, ["المفوتر", "Biller"])
        result.counterparty = kind == .transferIn ? labelled(t, ["من", "From"]) : kind == .transferOut ? labelled(t, ["إلى", "To"]) : nil
        if kind == .refund, result.merchant == nil { result.merchant = labelled(t, ["من"]) }
        if kind == .bnplInstalment { result.provider = has(t, ["تمارا", "tamara"]) ? "Tamara" : "Tabby" }
        if kind == .purchase || kind == .refund {
            result.cardKind = has(t, ["ائتمان", "credit"]) ? .credit : has(t, ["مسبقة الدفع", "prepaid"]) ? .prepaid
                : has(t, ["مدى", "mada", "Apple Pay"]) ? .debit : nil
        }
        return result
    }

    // MARK: Fields

    static let currencyWords: [(String, String)] = [("ر.س", "SAR"), ("ريال", "SAR"), ("SAR", "SAR"), ("USD", "USD"), ("دولار", "USD"),
                                                     ("JPY", "JPY"), ("KWD", "KWD"), ("د.ك", "KWD"), ("BHD", "BHD"), ("OMR", "OMR"),
                                                     ("AED", "AED"), ("EUR", "EUR"), ("GBP", "GBP"), ("EGP", "EGP")]

    /// "42.00 SAR", "SAR 42", "بـ 18.50 ر.س", "15,000.00 ريال" → minor units by the currency's exponent.
    static func amounts(_ text: String, _ exponents: CurrencyExponents) -> [(minor: Int, currency: String, range: Range<String.Index>)] {
        let number = #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#
        let codes = currencyWords.map { NSRegularExpression.escapedPattern(for: $0.0) }.joined(separator: "|")
        let pattern = "(?:\(number)\\s*(\(codes)))|(?:(\(codes))\\s*\(number))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            func group(_ i: Int) -> String? { match.range(at: i).location == NSNotFound ? nil : ns.substring(with: match.range(at: i)) }
            guard let raw = group(1) ?? group(4), let word = group(2) ?? group(3),
                  let code = currencyWords.first(where: { $0.0.caseInsensitiveCompare(word) == .orderedSame })?.1,
                  let exp = exponents.exponent(code), let minor = minorUnits(raw, exponent: exp),
                  let range = Range(match.range, in: text) else { return nil }
            return (minor, code, range)
        }
    }

    /// Decimal text → minor units without floating point.
    static func minorUnits(_ raw: String, exponent: Int) -> Int? {
        let plain = raw.replacingOccurrences(of: ",", with: "")
        let parts = plain.split(separator: ".", omittingEmptySubsequences: false)
        guard let whole = Int(parts[0]) else { return nil }
        var fraction = parts.count > 1 ? String(parts[1]) : ""
        guard fraction.count <= exponent || fraction.dropFirst(exponent).allSatisfy({ $0 == "0" }) else { return nil }
        fraction = String(fraction.prefix(exponent)).padding(toLength: exponent, withPad: "0", startingAt: 0)
        var scale = 1
        for _ in 0..<exponent { scale *= 10 }
        return whole * scale + (Int(fraction) ?? 0)
    }

    static func firstAmount(_ text: String, _ exponents: CurrencyExponents) -> (minor: Int, currency: String)? {
        // The balance is not the movement's amount.
        let balanceLine = text.split(separator: "\n").first { has(String($0), ["الرصيد", "Balance"]) }.map(String.init)
        return amounts(text, exponents).first { balanceLine == nil || !balanceLine!.contains(text[$0.range]) }.map { ($0.minor, $0.currency) }
    }

    static func labelledAmount(_ text: String, _ labels: [String], _ exponents: CurrencyExponents) -> (minor: Int, currency: String)? {
        for line in text.split(separator: "\n").map(String.init) where has(line, labels) {
            if let amount = amounts(line, exponents).first { return (amount.minor, amount.currency) }
        }
        return nil
    }

    /// "label: value" on its own line.
    static func labelled(_ text: String, _ labels: [String]) -> String? {
        for line in text.split(separator: "\n").map(String.init) {
            for label in labels {
                guard let range = line.range(of: label + ":") ?? line.range(of: label + " :") else { continue }
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for i in 1..<match.numberOfRanges where match.range(at: i).location != NSNotFound {
            return Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
        return nil
    }

    /// RM6: eventAt from the text — "2026-10-15 13:05", "15/10/26 13:05" or "15-10-2026 13:05".
    static func eventDate(_ text: String, _ timeZone: TimeZone) -> Date? {
        let patterns = [#"(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})"#, #"(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\s+(\d{1,2}):(\d{2})"#]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let values = (1...5).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            guard values.count == 5 else { continue }
            var parts = DateComponents()
            if index == 0 { parts.year = values[0]; parts.month = values[1]; parts.day = values[2] }
            else { parts.day = values[0]; parts.month = values[1]; parts.year = values[2] < 100 ? 2000 + values[2] : values[2] }
            parts.hour = values[3]; parts.minute = values[4]
            return date(parts, timeZone)
        }
        return nil
    }

    static func labelledDate(_ text: String, _ labels: [String], _ timeZone: TimeZone) -> Date? {
        guard let value = labelled(text, labels) else { return nil }
        let patterns = [#"(\d{4})-(\d{1,2})-(\d{1,2})"#, #"(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})"#]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: value, range: NSRange(value.startIndex..., in: value)) else { continue }
            let v = (1...3).compactMap { Range(match.range(at: $0), in: value).flatMap { Int(value[$0]) } }
            guard v.count == 3 else { continue }
            var parts = DateComponents()
            if index == 0 { parts.year = v[0]; parts.month = v[1]; parts.day = v[2] } else { parts.day = v[0]; parts.month = v[1]; parts.year = v[2] < 100 ? 2000 + v[2] : v[2] }
            parts.hour = 12
            return date(parts, timeZone)
        }
        return nil
    }

    static func date(_ parts: DateComponents, _ timeZone: TimeZone) -> Date? {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == parts.day else { return nil }
        return date
    }
}

/// What intake does with a message (§7.5, RM6).
public enum IngestDecision: Equatable, Sendable {
    /// OTP: never stored, not even its text.
    case discardWithoutText
    /// Marketing: thrown away, no movement.
    case discard
    case needsLook
    case record
}

public enum BankIntake {
    public static func decision(_ kind: BankMessageKind) -> IngestDecision {
        switch kind {
        case .otp: return .discardWithoutText
        case .marketing: return .discard
        case .unknown: return .needsLook
        default: return .record
        }
    }
}

/// F08 as amended by RM8: fingerprint = SHA-256(sender + normalised text), no minute; occurrence counts repeats.
public enum BankDedupe {
    /// Spaces collapsed, digits unified, Latin lowercased.
    public static func normalize(_ text: String) -> String {
        BankMessageParser.clean(text).lowercased().split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    public static func fingerprint(sender: String, text: String) -> String {
        let input = normalize(sender) + "\n" + normalize(text)
        return SHA256.hash(data: Data(input.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    public enum Placement: Equatable, Sendable {
        case insert(occurrence: Int, possibleDuplicate: Bool)
        case alreadyThere
        /// F08: a pasted message without its own time matching one within ±3 days → «قد تكون موجودة», never an automatic skip.
        case mayExist(occurrence: Int)
    }

    public struct Incoming: Equatable, Sendable {
        public var fingerprint: String
        /// The text carries its own time (the parser found eventAt).
        public var hasOwnTime: Bool
        /// That time, or the paste time when the text has none.
        public var at: Date
        public init(fingerprint: String, hasOwnTime: Bool, at: Date) { self.fingerprint = fingerprint; self.hasOwnTime = hasOwnTime; self.at = at }
    }

    public struct Stored: Equatable, Sendable {
        public var key: Key
        public var at: Date
        public init(key: Key, at: Date) { self.key = key; self.at = at }
    }

    /// A pasted file. RM8 took the time out of the fingerprint, so only a text that carries its own time can be
    /// skipped as already stored; copies inside the file count 1, 2, … so the same file twice adds nothing.
    /// A timeless text gets a fresh occurrence and, when the same text is stored within ±3 days, a preview.
    public static func bulk(_ incoming: [Incoming], existing: [Stored]) -> [Placement] {
        var seen: [String: Int] = [:]
        let keys = Set(existing.map(\.key))
        return incoming.map { item in
            seen[item.fingerprint, default: 0] += 1
            let n = seen[item.fingerprint]!
            if item.hasOwnTime {
                return keys.contains(Key(fingerprint: item.fingerprint, occurrence: n)) ? .alreadyThere : .insert(occurrence: n, possibleDuplicate: false)
            }
            let same = existing.filter { $0.key.fingerprint == item.fingerprint }
            let occurrence = (same.map(\.key.occurrence).max() ?? 0) + n
            return same.contains { abs($0.at.timeIntervalSince(item.at)) <= 3 * 86_400 } ? .mayExist(occurrence: occurrence) : .insert(occurrence: occurrence, possibleDuplicate: false)
        }
    }

    /// The live Shortcut: an existing fingerprint arrives as the next occurrence, created and counted; it is flagged
    /// «عمليتان أم تكرار؟» only when the same text came within the near-duplicate window (RM8), so a daily coffee with
    /// a timeless text is not questioned every day. Nothing is dropped blind.
    public static func live(_ fingerprint: String, at: Date, existing: [Stored], window: TimeInterval = 600) -> Placement {
        let same = existing.filter { $0.key.fingerprint == fingerprint }
        let last = same.map(\.key.occurrence).max() ?? 0
        return .insert(occurrence: last + 1, possibleDuplicate: same.contains { abs($0.at.timeIntervalSince(at)) <= window })
    }

    public struct Key: Hashable, Sendable {
        public var fingerprint: String
        public var occurrence: Int
        public init(fingerprint: String, occurrence: Int) { self.fingerprint = fingerprint; self.occurrence = occurrence }
    }

    public struct Movement: Equatable, Sendable {
        public var accountKey: String
        public var amountMinor: Int
        public var merchant: String?
        public var at: Date
        public var fingerprint: String
        public init(accountKey: String, amountMinor: Int, merchant: String?, at: Date, fingerprint: String) {
            self.accountKey = accountKey; self.amountMinor = amountMinor; self.merchant = merchant; self.at = at; self.fingerprint = fingerprint
        }
    }

    /// RM8 near-duplicate: same account, amount and merchant within ±10 minutes but a different text → ask the user.
    public static func nearDuplicate(_ new: Movement, among existing: [Movement], window: TimeInterval = 600) -> Bool {
        existing.contains { old in
            old.fingerprint != new.fingerprint && old.accountKey == new.accountKey && old.amountMinor == new.amountMinor
                && BankDedupe.normalize(old.merchant ?? "") == BankDedupe.normalize(new.merchant ?? "") && abs(old.at.timeIntervalSince(new.at)) <= window
        }
    }
}

/// F07: card identity and statements, honest about uncertainty.
public enum CardStatements {
    public struct KnownCard: Equatable, Sendable {
        public var id: String
        public var bank: String
        public var last4: String
        public var aliases: [String]
        public init(id: String, bank: String, last4: String, aliases: [String] = []) { self.id = id; self.bank = bank; self.last4 = last4; self.aliases = aliases }
    }
    public enum Identity: Equatable, Sendable { case known(String), newCardQuestion }

    /// (bank + last 4) with aliases for sender names; an unknown last 4 → «بطاقة جديدة؟», never created silently.
    public static func identify(sender: String, last4: String, cards: [KnownCard]) -> Identity {
        let s = BankDedupe.normalize(sender)
        let match = cards.first { $0.last4 == last4 && (BankDedupe.normalize($0.bank) == s || $0.aliases.map(BankDedupe.normalize).contains(s)) }
        return match.map { .known($0.id) } ?? .newCardQuestion
    }

    public struct StoredStatement: Equatable, Sendable {
        public var closeDate: Date
        public var statementMinor: Int
        public var estimated: Bool
        public init(closeDate: Date, statementMinor: Int, estimated: Bool) { self.closeDate = closeDate; self.statementMinor = statementMinor; self.estimated = estimated }
    }
    public enum StatementPlacement: Equatable, Sendable { case new, sameStatement(index: Int), needsLook(index: Int) }

    /// A second statement message within 5 days of an estimated close → «نفس الكشف؟» (update) when the amount matches, else review.
    public static func place(closeDate: Date, statementMinor: Int, existing: [StoredStatement]) -> StatementPlacement {
        for (i, old) in existing.enumerated() where old.estimated && abs(old.closeDate.timeIntervalSince(closeDate)) <= 5 * 86_400 {
            return old.statementMinor == statementMinor ? .sameStatement(index: i) : .needsLook(index: i)
        }
        return .new
    }

    /// After two statements the next close is expected on the same day of the month, still «تقديري».
    public static func predictNextClose(_ closes: [Date], calendar: Calendar) -> Date? {
        guard closes.count >= 2 else { return nil }
        let sorted = closes.sorted(), days = sorted.suffix(2).map { calendar.component(.day, from: $0) }
        guard days[0] == days[1], let last = sorted.last else { return nil }
        return calendar.date(byAdding: .month, value: 1, to: last)
    }
}
