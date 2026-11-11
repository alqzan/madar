import CryptoKit
import Foundation

/// M5-E03: the bank-message parser (§7.5 «رسائل البنك», RM6) and dedupe (F08 as amended by RM8).
/// Formats are learned from synthetic samples written from the spec; the owner's anonymised messages will extend them.
public enum BankMessageKind: String, Sendable, CaseIterable {
    case purchase, withdrawal, transferOut, transferIn, salary, income, cardPayment, statement, refund, cashback
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
    public var statedHomeMinor: Int?
}

/// A small, explicit alias table for bank and wallet identities. The sender remains the authority:
/// message-body merchants are never treated as the sending bank.
public enum BankMessageIdentity {
    private static let groups: [(String, [String])] = [
        ("rajhi", ["الراجحي", "مصرف الراجحي", "بنك الراجحي", "al rajhi", "alrajhibank"]),
        ("fransi", ["الفرنسي", "البنك السعودي الفرنسي", "السعودي الفرنسي", "fransi", "bsf", "saudi fransi bank"]),
        ("snb", ["الاهلي", "الأهلي", "السعودي الاهلي", "السعودي الأهلي", "البنك الأهلي", "البنك الاهلي", "snb", "saudi national bank"]),
        ("inma", ["الانماء", "الإنماء", "inma", "alinma", "alinma bank"]),
        ("sab", ["ساب", "البنك السعودي البريطاني", "sab", "saab", "sabb", "saudi british bank"]),
        ("riyad", ["بنك الرياض", "riyad", "riyad bank"]),
        ("barq", ["برق", "barq"]),
        ("stcbank", ["stc bank", "stcbank", "بنك stc", "stc بنك", "اس تي سي بنك"]),
        ("stcpay", ["stc pay", "stcpay", "اس تي سي باي"]),
        ("drahim", ["دراهم", "drahim"]),
        ("tiqmo", ["تيقمو", "tiqmo"]),
        ("d360", ["دي 360", "دي360", "d360"]),
        ("tweeq", ["تويك", "tweeq"]),
        ("urpay", ["يورباي", "يو ار باي", "urpay"]),
        ("alinma-investment", ["الإنماء للاستثمار", "الانماء للاستثمار", "alinma investment", "alinmainvestment"]),
        ("sukuk", ["صكوك", "sukuk"])
    ]

    private static func compact(_ value: String) -> String {
        String(BankMessageParser.clean(value).lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains))
    }

    private static func group(for key: String) -> String? {
        groups.first { identity, aliases in
            aliases.contains { alias in
                let candidate = compact(alias)
                return key == candidate
            }
        }?.0
    }

    /// Matches an explicitly configured bank/sender or a known Arabic/English alias.
    public static func matches(_ lhs: String, _ rhs: String) -> Bool {
        let left = compact(lhs), right = compact(rhs)
        guard !left.isEmpty, !right.isEmpty else { return false }
        if left == right { return true }
        guard let leftGroup = group(for: left) else { return false }
        return leftGroup == group(for: right)
    }
}

/// A top-up becomes an internal transfer only when its endpoint is an owned, tracked wallet/account.
public enum BankWalletIdentity {
    public static func matches(_ endpoint: String?, trackedWallets: [String]) -> Bool {
        guard let endpoint, !endpoint.isEmpty else { return false }
        return trackedWallets.contains { BankMessageIdentity.matches(endpoint, $0) }
    }
}

public enum BankMessageParser {
    public static let version = 2

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
    static func matches(_ text: String, _ pattern: String) -> Bool {
        text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil
    }
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
        // Ported from the owner's earlier My-dream analysis (src/lib/bankParser.ts): notices that move no money.
        if matches(t, #"just\s+a\s+hold|hold\s+on\s+your\s+card|حجز\s+مؤقت|حجز\s+على\s+بطاقتك|pre[\s-]?authoriz"#)
            || matches(t, #"صدور\s+فاتورة|فاتورة\s+جديدة|لم\s+يتم\s+سدادها|تم\s+إصدار\s+فاتورتك|invoice\s+(?:generated|due)|new\s+bill"#)
            || matches(t, #"سداد\s+مبكر|منصة\s+الدين|معرف\s+(?:الفرصة|الاستثمار)|investment\s+opportunity|early\s+repayment"#)
            || matches(t, #"لحمايتك،?\s+حاولنا\s+التواصل|للتحقق\s+من\s+عملية|يرجى\s+مراجعة\s+التفاصيل\s+في\s+التطبيق"#)
            || matches(t, #"تمت\s+اضافة\s+المستفيد|تمت\s+إضافة\s+المستفيد|تم\s+تنشيط\s+المستفيد|تم\s+تسجيل\s+الدخول|تم\s+تسجيلك\s+بنجاح|تسجيل\s+جهاز\s+جديد|نقاط\s+قطاف|نقاط\s+عضوية|رصيد\s+قطاف"#) { return .marketing }
        // Owner, 19 Oct: a charity platform's thank-you receipt is not a movement; the bank's own debit records the gift.
        if has(t, ["وصل تبرعك", "Ehsan.sa"]) { return .marketing }
        if has(t, ["مرفوضة", "رفض العملية", "لم تتم العملية", "declined", "رصيد غير كافي", "رصيد غير كاف", "Insufficient"]) { return .declined }
        if has(t, ["عكس عملية", "إلغاء عملية", "عكس العملية", "reversal", "reversed"]) { return .reversal }
        // Owner special cases: «تأكيد دفعة مقسمة» only confirms a plan (recording it double-counts); a bank purchase
        // «لدى:Tamara» is an ordinary purchase.
        if has(t, ["دفعة مقسمة"]) { return .marketing }
        // Tamara's own texts: «دفعة قادمة بقيمة …» / «دفعتك بقيمة …» (a due notice) and «تأكيد الدفع … بقيمة:» carry no brand word, only a link.
        if matches(t, #"(?:دفعة\s+قادمة|دفعتك)\s+بقيمة|(?m)^\s*تأكيد\s+الدفع[ \t]*[\r\n][\s\S]*?بقيمة\s*:"#) { return .bnplInstalment }
        if has(t, ["تمارا", "tamara", "تابي", "tabby"]) && !has(t, ["شراء"]) { return .bnplInstalment }
        if has(t, ["كشف حساب البطاقة", "كشف البطاقة", "statement", "الحد الأدنى للسداد", "المبلغ المستحق"]) && !has(t, ["شراء"]) { return .statement }
        if has(t, ["سداد بطاقة", "سداد البطاقة", "ائتمانية:سداد", "ائتمانية: سداد", "فيزا:سداد", "ماستركارد:سداد", "تسديد بطاقة", "تسديد البطاقة", "card payment"]) { return .cardPayment }
        // RM6 corpus (19 Oct): a finance instalment is an obligation paid, like a bill.
        if has(t, ["قسط تمويل"]) { return .billPayment }
        if has(t, ["سداد فاتورة", "سداد", "SADAD", "المفوتر"]) { return .billPayment }
        if has(t, ["استرداد نقدي", "استرجاع نقدي", "cashback", "cash back", "cash-back", "مكافأة نقدية"]) { return .cashback }
        if has(t, ["استرداد", "refund", "مرتجع"]) || matches(t, #"رد\s+فائض\s+اكتتاب"#) { return .refund }
        if has(t, ["راتب", "salary", "payroll"]) { return .salary }
        // SNB: «ايداع رواتب» (no hamza, plural) is a salary-like income deposit.
        if matches(t, #"^\s*[اإ]يداع\s+رواتب"#) { return .income }
        // stc pay: a Sawa recharge is a bill-like payment out of the wallet.
        if matches(t, #"شحن\s+رصيد\s+سوا|sawa\s+recharge"#) { return .billPayment }
        // SNB: «تسديد آلي» is the automatic settlement of the credit card.
        if matches(t, #"^\s*تسديد\s+آلي"#) { return .cardPayment }
        // Sukuk: an investment into a project leaves the account; a withdrawal from the investment account too.
        if matches(t, #"^\s*عملية\s+استثمارية"#) { return .transferOut }
        if matches(t, #"^\s*سحب\s+من\s+حساب\s+استثماري"#) { return .withdrawal }
        if has(t, ["سحب صراف", "سحب نقدي", "ATM", "cash withdrawal"]) { return .withdrawal }
        if has(t, ["حوالة صادرة", "تحويل صادر", "تحويل إلى", "outgoing transfer"])
            || matches(t, #"\boutgoing\b[\s\S]{0,80}\btransfer\b"#) { return .transferOut }
        if has(t, ["حوالة واردة", "تحويل وارد", "incoming transfer"]) { return .transferIn }
        // Some banks put the amount between «تحويل» and its explicit destination.
        // A recipient after the amount is enough for an outgoing draft; a source-only «من» stays reviewable.
        if transferOutPartyAfterAmount(t) != nil { return .transferOut }
        // Explicit moves between the owner's accounts are transfers even when a bank omits
        // «صادر» and «وارد». Keep the direction conservative when the message names no endpoint.
        if has(t, ["حوالة بين حساباتك", "حوالة بين حساباتي", "تحويل بين حساباتك", "تحويل بين حساباتي"])
            || matches(t, #"\b(?:transfer\s+between\s+your\s+accounts|debit\s+transfer\s+internal)\b"#) { return .transferOut }
        // RM6 corpus: «حوالة داخلية صادرة», «حوالة محلية واردة», wallet top-ups and own-account moves.
        if has(t, ["حوالة", "تحويل"]) && has(t, ["صادرة", "صادر"]) { return .transferOut }
        if has(t, ["حوالة", "تحويل"]) && has(t, ["واردة", "وارد"]) { return .transferIn }
        // Some internal-transfer templates show only their source account and no direction word.
        if has(t, ["حوالة داخلية", "حوالة محلية"]) && labelled(t, ["من", "From"]) != nil { return .transferIn }
        // «استلام قطة» returns a share of a shared bill: a refund, not income (owner special case).
        if has(t, ["استلام قطة"]) { return .refund }
        if has(t, ["تغذية محفظة", "إضافة أموال", "اضافة اموال", "إضافة باستخدام", "اضافة باستخدام", "إيداع عبر حوالة", "شحن المحفظة", "تعبئة المحفظة"])
            || matches(t, #"\b(?:money\s+added|add(?:ed)?\s+funds|funds\s+added|top[\s-]*up|cash[\s-]*in)\b"#) {
            // Explicit purchase/debit wording is parsed below and only becomes neutral when it matches a tracked wallet.
            if !has(t, ["شراء", "مشتريات", "purchase", "خصم"]) { return .transferIn }
        }
        // «حوالة داخلية … الى:1234 … من:Drahim»: into the owner's own account from a named source.
        if has(t, ["حوالة داخلية", "حوالة محلية"]) && matches(t, #"(?m)^\s*(?:الى|إلى)\s*:\s*\*?\d"#) && matches(t, #"(?m)^\s*من\s*:\s*[^\d\s*]"#) { return .transferIn }
        if has(t, ["خصم عبر حوالة", "بين حساباتي", "بين حساباتك", "للحساب *", "للبطاقة *"]) || (has(t, ["خصم"]) && has(t, ["من حسابك", "من حساب"]) && has(t, ["تحويل"])) { return .transferOut }
        if has(t, ["اضافة", "إضافة"]) && has(t, ["الى حسابك", "إلى حسابك"]) { return .income }
        if has(t, ["شراء", "مشتريات", "purchase", "Apple Pay", "مدى", "POS"]) { return .purchase }
        // STC Bank: «دفع قطة» pays a friend's share of a shared bill (the mirror of «استلام قطة»).
        if matches(t, #"^\s*دفع\s+قطة"#) { return .transferOut }
        // Mobily Pay: «You have received amount».
        if matches(t, #"received\s+amount|تلقيت\s+مبلغ"#) { return .transferIn }
        // Alinma / Al Rajhi: IPO subscription debit; Al Rajhi: «خصم SAR N من حسابك … - <label>» (the label says what it was).
        if matches(t, #"^\s*خصم\s+[\d.,]+\s*(?:ريال|SAR)[^\n]*اكتتاب"#) { return .transferOut }
        if matches(t, #"^\s*خصم\s+[A-Za-z]{3}\s+[\d.,]+\s+من\s+حسابك"#) {
            if has(t, ["الاكتتاب", "اكتتاب"]) { return .transferOut }
            if has(t, ["فواتير", "مدفوعات سوا"]) { return .billPayment }
            return .withdrawal
        }
        // Al Rajhi Capital: «تحويل N ريال من الحساب …» arrives from the named account.
        if transferInPartyAfterAmount(t) != nil { return .transferIn }
        // STC Bank: «عملية انترنت  ب: N SAR  من:<merchant>».
        if matches(t, #"^\s*عملية\s+(?:انترنت|إنترنت)"#) { return .purchase }
        // After the movements: a transfer that mentions its fee is still the transfer.
        if has(t, ["رسوم", "عمولة", "fee"]) { return .fee }
        if has(t, ["إيداع", "deposit", "credited"]) { return .income }
        if has(t, ["عرض", "خصم حصري", "اشترك", "offer", "promo", "لإلغاء الاشتراك"]) { return .marketing }
        // My-dream: greetings and rewards with no movement phrase above are notices.
        if matches(t, #"عزيزي\s+العميل|عميلنا\s+العزيز|مبروك|rewards|خصم\s+خاص|Current\s+balance"#) { return .marketing }
        return .unknown
    }

    /// A transfer recipient can follow its amount without a colon: «تحويل ١٢٠ ريال إلى فلان» or «حوالة ١٢٠ ريال ل فلان».
    /// Only inspect the same line after a parsed amount so ordinary «إلى/ل» prose cannot create a transfer.
    private static func transferOutPartyAfterAmount(_ text: String) -> String? {
        for line in text.split(separator: "\n").map(String.init) where has(line, ["حوالة", "تحويل"]) {
            guard let amount = amounts(line, .specified).first else { continue }
            let tail = line[amount.range.upperBound...].trimmingCharacters(in: .whitespaces)
            for label in ["إلى", "الى", "To"] {
                guard let range = tail.range(of: label, options: [.anchored, .caseInsensitive]) else { continue }
                var value = String(tail[range.upperBound...])
                guard value.first?.isWhitespace == true || value.first == ":" || value.first == "：" else { continue }
                if value.first == ":" || value.first == "：" { value.removeFirst() }
                value = value.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
            if tail.hasPrefix("ل") {
                var value = String(tail.dropFirst())
                guard value.first?.isWhitespace == true || value.first == ":" || value.first == "：" else { continue }
                if value.first == ":" || value.first == "：" { value.removeFirst() }
                value = value.trimmingCharacters(in: .whitespaces)
                if !value.isEmpty { return value }
            }
        }
        return nil
    }

    /// «تحويل ١٢٠ ريال من الحساب …»: a source after the amount and no recipient later on the line.
    private static func transferInPartyAfterAmount(_ text: String) -> String? {
        for line in text.split(separator: "\n").map(String.init) where has(line, ["حوالة", "تحويل"]) {
            guard let amount = amounts(line, .specified).first else { continue }
            let tail = line[amount.range.upperBound...].trimmingCharacters(in: .whitespaces)
            guard tail.hasPrefix("من"), let afterLabel = tail.dropFirst(2).first, afterLabel.isWhitespace else { continue }
            let value = String(tail.dropFirst(2)).trimmingCharacters(in: .whitespaces)
            if !value.isEmpty, !matches(value, #"\s(?:إلى|الى|ل)\s"#) { return value }
        }
        return nil
    }

    /// `receivedAt` (the phone's receive time) settles two-digit dates that read both ways, «25-10-19» vs «19-10-25».
    public static func parse(_ text: String, timeZone: TimeZone, exponents: CurrencyExponents = .specified, homeCurrency: String = "SAR", receivedAt: Date? = nil, sender: String? = nil, trackedWallets: [String] = []) -> ParsedBankMessage {
        let t = clean(text)
        // Owner, 19 Oct: the telecom sender «stc» (not stc pay / STC Bank) sends balance and offers only — ignore it all.
        let kind = ["stc", "stc-ad"].contains(sender?.lowercased().trimmingCharacters(in: .whitespaces) ?? "") ? .marketing : classify(text)
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
        if let stated = labelledAmount(t, ["بما يعادل", "ما يعادل", "equivalent", "المبلغ بالريال"], exponents), stated.currency == homeCurrency, result.currency != homeCurrency {
            result.statedHomeMinor = stated.minor
        }
        result.balanceMinor = labelledAmount(t, ["الرصيد المتوفر", "الرصيد", "رصيد", "Balance"], exponents)?.minor
        result.last4 = first(#"\*\s?(\d{4})\b|\b(\d{4})\s?\*"#, in: t)
            // Al Rajhi: «بطاقة:1234;مدى», «عبر:1234;مدى».
            ?? first(#"(?:بطاقة|ببطاقة|عبر)\s*:?\s*(\d{4})(?!\d)"#, in: t)
        // Sukuk prints its account number as «رقم: 1234».
        if result.last4 == nil { result.last4 = first(#"(?m)^\s*رقم\s*:\s*(\d{4})\s*$"#, in: t) }
        // Sukuk (a Saudi platform) prints «المبلغ: 1,500.00» with no currency word: the home currency is meant.
        if result.amountMinor == nil, kind != .statement, BankMessageIdentity.matches(sender ?? "", "sukuk"),
           let raw = first(#"(?m)^\s*المبلغ\s*:\s*(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*$"#, in: t),
           let exp = exponents.exponent(homeCurrency), let minor = minorUnits(raw, exponent: exp) {
            result.amountMinor = minor; result.currency = homeCurrency
        }
        result.eventAt = eventDate(t, timeZone, near: receivedAt ?? Date())
        result.merchant = labelled(t, ["لدى", "من متجر", "at"])
        result.biller = labelled(t, ["المفوتر", "Biller"])
        result.counterparty = kind == .transferIn ? labelled(t, ["من", "From"]) : kind == .transferOut ? (labelled(t, ["إلى", "To"]) ?? transferOutPartyAfterAmount(t)) : nil
        if kind == .refund, result.merchant == nil { result.merchant = labelled(t, ["من"]) }
        if kind == .refund, result.merchant == nil, matches(t, #"رد\s+فائض\s+اكتتاب"#) { result.merchant = "اكتتاب" }
        // Al Rajhi: «على : <merchant>» names the merchant of a declined card operation.
        if kind == .declined, result.merchant == nil { result.merchant = labelled(t, ["على"]) }
        // BSF, SNB, Alinma, barq: the merchant opens its own line after «من», «لـ», «لدى» or «At», with or without a colon.
        if [.purchase, .refund, .declined, .reversal].contains(kind), result.merchant == nil { result.merchant = lineMerchant(t) }
        // stc pay: «في: <merchant> <city> SA» (the line label «في:» also prints dates elsewhere, so only a non-digit value counts).
        if kind == .purchase, result.merchant == nil, has(t, ["بتاريخ"]),
           let value = first(#"(?m)^\s*في\s*:\s*([^\d\s][^\n]*?)\s*$"#, in: t) { result.merchant = stripCountryAndCity(value) }
        // Alinma: «شراء N ريال (مدى أثير) ببطاقة 1234* من <merchant> 2026-1-5 10:30».
        if kind == .purchase, result.merchant == nil,
           let value = first(#"ببطاقة\s*\d{4}\*?\s+من\s+(.+?)\s+\d{4}-\d{1,2}-\d{1,2}\s+\d{1,2}:\d{2}"#, in: t) { result.merchant = value }
        // STC Bank: «رصيد غير كافي / N ر.س / <merchant> / date»: the merchant is the line after the amount.
        if kind == .declined, result.merchant == nil, matches(t, #"^\s*رصيد\s+غير\s+كاف"#) {
            let lines = t.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
            if let amountLine = lines.firstIndex(where: { !amounts($0, exponents).isEmpty }), lines.indices.contains(amountLine + 1) {
                let candidate = lines[amountLine + 1]
                if let head = candidate.first, !head.isNumber, !has(candidate, ["رصيدك"]) { result.merchant = candidate }
            }
        }
        // Al Rajhi: «تحويل SAR N للحساب *1234 15-10-26 13:05 <name>»: the recipient name follows the time.
        if kind == .transferOut, result.counterparty == nil,
           let name = first(#"للحساب\s*\*?\d{3,4}\s+\d{1,4}[-/]\d{1,2}[-/]\d{1,4}\s+\d{1,2}:\d{2}(?::\d{2})?\s+(\S[^\n]*)$"#, in: t) { result.counterparty = name.trimmingCharacters(in: .whitespaces) }
        if kind == .transferIn, result.counterparty == nil { result.counterparty = transferInPartyAfterAmount(t) }
        // An IPO subscription debit has no recipient line: the subscription itself is the party.
        if kind == .transferOut, result.counterparty == nil, has(t, ["الاكتتاب", "اكتتاب"]) { result.counterparty = "اكتتاب" }
        // Sukuk: the project an investment goes into («في: <project>», the one «في:» line that is not a date).
        if kind == .transferOut, result.counterparty == nil, matches(t, #"^\s*عملية\s+استثمارية"#),
           let project = first(#"(?m)^\s*في\s*:\s*([^\d\s][^\n]*?)\s*$"#, in: t) { result.counterparty = project }
        // The same wallet can be tracked (internal transfer) or untracked (spending); use the owner's existing account choice.
        if kind == .purchase, BankWalletIdentity.matches(result.merchant, trackedWallets: trackedWallets) {
            result.kind = .transferOut
            result.counterparty = result.merchant
        }
        // «مبلغ: 23 USD(86.38 ريال)»: the bank's own riyal figure in brackets is the home amount, not the rate.
        if result.currency != homeCurrency, result.statedHomeMinor == nil,
           let match = t.range(of: #"\(\s*\d[\d.,]*\s*(?:ريال|SAR|SR|ر\.س)\s*\)"#, options: .regularExpression),
           let home = amounts(String(t[match]), exponents).first, home.currency == homeCurrency { result.statedHomeMinor = home.minor }
        if kind == .bnplInstalment {
            result.provider = has(t, ["تمارا", "tamara", "tmra.pe"]) || (sender?.lowercased().contains("tamara") ?? false) ? "Tamara" : "Tabby"
        }
        if kind == .purchase || kind == .refund || kind == .cashback {
            result.cardKind = has(t, ["ائتمان", "إئتمان", "credit"]) ? .credit : has(t, ["مسبقة الدفع", "prepaid"]) ? .prepaid
                : has(t, ["مدى", "mada", "Apple Pay"]) ? .debit : nil
        }
        return result
    }

    // MARK: Fields

    /// «jahez RIYADH SA» → «jahez»: a trailing two-letter country code and a known Saudi city are the card network's, not the shop's name.
    static func stripCountryAndCity(_ value: String) -> String {
        var words = value.split(separator: " ").map(String.init)
        if words.count > 1, let last = words.last, last.count == 2, last == last.uppercased(), last.allSatisfy(\.isLetter) { words.removeLast() }
        let cities: Set<String> = ["RIYADH", "JEDDAH", "DAMMAM", "MAKKAH", "MADINAH", "KHOBAR", "DHAHRAN", "ABHA", "TABUK", "BURAIDAH", "HOFUF", "TAIF", "JUBAIL", "YANBU"]
        if words.count > 1, let last = words.last, cities.contains(last.uppercased()) { words.removeLast() }
        return words.joined(separator: " ")
    }

    /// Longer phrases come first: the pattern takes the first alternative that matches, so «ريال عماني» must be tried before «ريال».
    /// A bare «دينار» is deliberately absent (Kuwaiti, Bahraini, Jordanian, Iraqi…): the message then carries no amount for review instead of a guess.
    static let currencyWords: [(String, String)] = [("ريال سعودي", "SAR"), ("ريال عماني", "OMR"), ("ريال قطري", "QAR"),
                                                     ("دينار كويتي", "KWD"), ("دينار بحريني", "BHD"), ("درهم إماراتي", "AED"), ("درهم مغربي", "MAD"), ("درهم", "AED"),
                                                     ("ريال يمني", "YER"), ("ريال إيراني", "IRR"), ("دينار أردني", "JOD"), ("دينار عراقي", "IQD"),
                                                     ("دينار جزائري", "DZD"), ("دينار تونسي", "TND"), ("دينار ليبي", "LYD"), ("جنيه مصري", "EGP"),
                                                     ("جنيه إسترليني", "GBP"), ("ليرة تركية", "TRY"), ("دولار أمريكي", "USD"),
                                                     ("ر.س", "SAR"), ("ريال", "SAR"), ("SAR", "SAR"), ("SR", "SAR"), ("USD", "USD"), ("دولار", "USD"),
                                                     ("JPY", "JPY"), ("KWD", "KWD"), ("د.ك", "KWD"), ("BHD", "BHD"), ("OMR", "OMR"), ("QAR", "QAR"),
                                                     ("AED", "AED"), ("EUR", "EUR"), ("GBP", "GBP"), ("EGP", "EGP")]

    /// A bare currency noun that a nationality adjective can follow («ريال يمني»).
    static let nationalityNouns: Set<String> = ["ريال", "درهم", "دولار"]
    /// Nationality adjectives (masculine stems; the feminine «…ية» and a leading «ال» are accepted too) that name a currency
    /// the table does not carry. Only these suppress the bare noun's currency: «ريال الراجحي» or «ريال فوري» stay riyals.
    static let nationalityStems: [String] = ["سوداني", "سوري", "لبناني", "مصري", "يمني", "إيراني", "ايراني", "عراقي", "أردني", "اردني", "ليبي",
                                              "تونسي", "جزائري", "مغربي", "كويتي", "بحريني", "عماني", "قطري", "إماراتي", "اماراتي", "تركي",
                                              "كندي", "أسترالي", "استرالي", "نيوزيلندي", "سنغافوري", "برازيلي", "فلسطيني", "صومالي", "موريتاني"]
    static func followedByNationality(_ text: String, after end: String.Index) -> Bool {
        let forms = nationalityStems.flatMap { [$0, String($0.dropLast()) + "ية"] }
        let alternatives = forms.map { "(?:ال)?" + $0 }.joined(separator: "|")
        return text[end...].range(of: "^\\s+(?:\(alternatives))(?![\\u0621-\\u064A])", options: .regularExpression) != nil
    }

    /// "42.00 SAR", "SAR 42", "بـ 18.50 ر.س", "15,000.00 ريال" → minor units by the currency's exponent.
    static func amounts(_ text: String, _ exponents: CurrencyExponents) -> [(minor: Int, currency: String, range: Range<String.Index>)] {
        let number = #"(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#
        let knownWords = Set(currencyWords.map(\.0))
        let words = currencyWords + exponents.exponents.keys.sorted().filter { !knownWords.contains($0) }.map { ($0, $0) }
        // A multi-word name tolerates any run of spaces between its words («ريال  عماني»).
        let codes = words.map { NSRegularExpression.escapedPattern(for: $0.0).replacingOccurrences(of: " ", with: "\\s+") }.joined(separator: "|")
        let pattern = "(?:\(number)\\s*(\(codes)))|(?:(\(codes))\\s*\(number))"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return [] }
        let ns = text as NSString
        return regex.matches(in: text, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            func group(_ i: Int) -> String? { match.range(at: i).location == NSNotFound ? nil : ns.substring(with: match.range(at: i)) }
            guard let raw = group(1) ?? group(4), let rawWord = group(2) ?? group(3),
                  case let word = rawWord.split(whereSeparator: \.isWhitespace).joined(separator: " "),
                  let code = words.first(where: { $0.0.caseInsensitiveCompare(word) == .orderedSame })?.1,
                  let exp = exponents.exponent(code), let minor = minorUnits(raw, exponent: exp),
                  let range = Range(match.range, in: text) else { return nil }
            // «50 ريال سوداني»: an adjective the table does not know must not fall back to the bare word's currency.
            if group(2) != nil, nationalityNouns.contains(word), followedByNationality(text, after: range.upperBound) { return nil }
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
        let product = whole.multipliedReportingOverflow(by: scale)
        let sum = product.partialValue.addingReportingOverflow(Int(fraction) ?? 0)
        guard !product.overflow, !sum.overflow else { return nil }
        return sum.partialValue
    }

    static func firstAmount(_ text: String, _ exponents: CurrencyExponents) -> (minor: Int, currency: String)? {
        // The balance is not the movement's amount. Compare by position: an amount is the balance when it sits in the
        // balance line at or after the «الرصيد»/«Balance» label. Comparing text would drop «50.00 SAR» inside «150.00 SAR».
        let balanceStart = ["الرصيد", "Balance"].compactMap { text.range(of: $0, options: .caseInsensitive)?.lowerBound }.min()
        let balanceEnd = balanceStart.map { start in text[start...].firstIndex(of: "\n") ?? text.endIndex }
        return amounts(text, exponents).first { amount in
            guard let start = balanceStart, let end = balanceEnd else { return true }
            return !(amount.range.lowerBound >= start && amount.range.upperBound <= end)
        }.map { ($0.minor, $0.currency) }
    }

    static func labelledAmount(_ text: String, _ labels: [String], _ exponents: CurrencyExponents) -> (minor: Int, currency: String)? {
        for line in text.split(separator: "\n").map(String.init) where has(line, labels) {
            if let amount = amounts(line, exponents).first { return (amount.minor, amount.currency) }
        }
        return nil
    }

    /// A merchant line: «من Shml», «لـEHSAN», «At: NOON». A value that starts with a digit or «*» is an account, not a merchant.
    static func lineMerchant(_ text: String) -> String? {
        for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            // clean() drops the tatweel, so «لـEHSAN» arrives as «لEHSAN»: «ل» glued to a Latin name.
            if line.hasPrefix("ل"), let next = line.dropFirst().first, next.isASCII, next.isLetter { return String(line.dropFirst()).trimmingCharacters(in: .whitespaces) }
            for label in ["لدى", "من", "At", "at", "Merchant"] where line.hasPrefix(label) {
                var value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                if value.hasPrefix(":") { value = value.dropFirst().trimmingCharacters(in: .whitespaces) }
                guard let head = value.first, !head.isNumber, head != "*", !value.hasPrefix("حساب"), !value.hasPrefix("رصيد") else { continue }
                if label.count == 2, line.dropFirst(label.count).first?.isLetter == true { continue } // «منصة», «atm»: a word, not a label
                return value
            }
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
    static func eventDate(_ text: String, _ timeZone: TimeZone, near reference: Date = Date()) -> Date? {
        let patterns = [#"(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})"#, #"(\d{1,2})[/-](\d{1,2})[/-](\d{2,4})\s+(\d{1,2}):(\d{2})"#]
        for (index, pattern) in patterns.enumerated() {
            guard let regex = try? NSRegularExpression(pattern: pattern),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { continue }
            let values = (1...5).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            guard values.count == 5 else { continue }
            var parts = DateComponents()
            parts.hour = values[3]; parts.minute = values[4]
            if index == 0 { parts.year = values[0]; parts.month = values[1]; parts.day = values[2]; return date(parts, timeZone) }
            // RM6 corpus: Al Rajhi, Alinma and stc pay print «yy-mm-dd», others «dd-mm-yy». With two-digit ends both
            // readings can be valid; the one nearest the receive time wins.
            var dayFirst = parts; dayFirst.day = values[0]; dayFirst.month = values[1]; dayFirst.year = values[2] < 100 ? 2000 + values[2] : values[2]
            var yearFirst = parts; yearFirst.year = 2000 + values[0]; yearFirst.month = values[1]; yearFirst.day = values[2]
            let readings = [date(dayFirst, timeZone), values[2] < 100 ? date(yearFirst, timeZone) : nil].compactMap { $0 }
            return readings.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
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
        guard let date = calendar.date(from: parts), calendar.component(.day, from: date) == parts.day,
              parts.month == nil || calendar.component(.month, from: date) == parts.month else { return nil }
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
    public static let nearDuplicateWindow: TimeInterval = 600
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
    public static func nearDuplicate(_ new: Movement, among existing: [Movement], window: TimeInterval = BankDedupe.nearDuplicateWindow) -> Bool {
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
        let match = cards.first { $0.last4 == last4 && (BankMessageIdentity.matches($0.bank, sender) || $0.aliases.contains { BankMessageIdentity.matches($0, sender) }) }
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
