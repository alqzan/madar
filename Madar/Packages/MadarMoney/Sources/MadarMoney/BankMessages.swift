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
    /// The owner's own account tail when the message prints it apart from the card: the debited account of a purchase or
    /// outgoing transfer, the receiving account of an incoming transfer. Never inferred; nil when not printed.
    public var accountLast4: String?
    /// Why a card operation was refused, from the declined layouts.
    public enum DeclineReason: String, Sendable { case insufficientBalance, limitExceeded, wrongPIN, cardBlocked, other }
    public var declineReason: DeclineReason?
    /// Fee, VAT and the foreign-currency fee as printed (never added into `amountMinor`). A «رسوم وضريبة» line is one combined
    /// figure and is kept in `feeMinor` with `vatMinor` left nil.
    public var feeMinor: Int?
    public var vatMinor: Int?
    public var foreignFeeMinor: Int?
    /// The printed exchange rate as the bank wrote it («4.2150»); text so no precision is invented.
    public var exchangeRate: String?
    /// «الصرف المتبقي» / «حد الصرف المتبقي»: what the card may still spend. Not the account balance.
    public var remainingLimitMinor: Int?
    /// «الحد المتاح» / «Avl limit». Not the account balance.
    public var availableLimitMinor: Int?
    /// A message with a printed date but no clock time (the day at 12:00 local); `eventAt` stays nil.
    public var eventDateOnly: Date?
    /// The other side's account tail when the message prints one apart from a name: the destination of an outgoing transfer
    /// («الى حساب:*7788», «إلى: ***2461»), the source of an incoming one («من:*1357»). `accountLast4` stays the owner's side.
    public var counterpartyAccountLast4: String?
    /// Tamara/Tabby «القسط ٢ من ٤» / «payment 2 of 4», and the balance still owed when the message prints one. Never inferred.
    public var instalmentNumber: Int?
    public var instalmentCount: Int?
    public var remainingMinor: Int?
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
        var lastWasCarriageReturn = false
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0660...0x0669: out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x0660 + 0x30)!)
            case 0x06F0...0x06F9: out.unicodeScalars.append(Unicode.Scalar(scalar.value - 0x06F0 + 0x30)!)
            case 0x066B: out.append(".")
            case 0x066C: out.append(",")
            case 0x064B...0x0652, 0x0670, 0x0640, 0x200E, 0x200F, 0x2066...0x2069, 0x202A...0x202E: continue
            case 0x0D: out.append("\n")   // «\r\n» is one Character in Swift and would not split on «\n»
            case 0x0A where out.last == "\n" && lastWasCarriageReturn: continue
            default: out.unicodeScalars.append(scalar)
            }
            lastWasCarriageReturn = scalar.value == 0x0D
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

    /// A bill-issued notice («تم إصدار فاتورتك … المبلغ المطلوب …»): classed as marketing, but it announces an upcoming due, so intake keeps it.
    public static func isDueNotice(_ text: String) -> Bool {
        matches(clean(text), #"صدور\s+فاتورة|فاتورة\s+جديدة|تم\s+إصدار\s+فاتورتك|invoice\s+(?:generated|due)|new\s+bill"#)
    }

    public static func classify(_ text: String) -> BankMessageKind {
        let t = clean(text)
        // Order matters: the dangerous and the specific first.
        if has(t, ["رمز التحقق", "رمز التفعيل", "كلمة المرور لمرة", "OTP", "verification code", "لا تشارك الرمز"]) { return .otp }
        // Ported from the owner's earlier My-dream analysis (src/lib/bankParser.ts): notices that move no money.
        if matches(t, #"just\s+a\s+hold|hold\s+on\s+your\s+card|حجز\s+مؤقت|حجز\s+على\s+بطاقتك|pre[\s-]?authoriz"#)
            || matches(t, #"صدور\s+فاتورة|فاتورة\s+جديدة|لم\s+يتم\s+سدادها|تم\s+إصدار\s+فاتورتك|invoice\s+(?:generated|due)|new\s+bill"#)
            || matches(t, #"سداد\s+مبكر|منصة\s+الدين|معرف\s+(?:الفرصة|الاستثمار)|investment\s+opportunity|early\s+repayment"#)
            || matches(t, #"طلب\s+استرداد|بتوصلك\s+رسالة\s+استرداد|تمت\s+الموافقة\s+على\s+طلب"#)
            || matches(t, #"لحمايتك،?\s+حاولنا\s+التواصل|للتحقق\s+من\s+عملية|يرجى\s+مراجعة\s+التفاصيل\s+في\s+التطبيق"#)
            || matches(t, #"تمت\s+اضافة\s+المستفيد|تمت\s+إضافة\s+المستفيد|تم\s+تنشيط\s+المستفيد|تم\s+تسجيل\s+الدخول|تم\s+تسجيلك\s+بنجاح|تسجيل\s+جهاز\s+جديد|نقاط\s+قطاف|نقاط\s+عضوية|رصيد\s+قطاف"#) { return .marketing }
        // Owner, 19 Oct: a charity platform's thank-you receipt is not a movement; the bank's own debit records the gift.
        if has(t, ["وصل تبرعك", "Ehsan.sa"]) { return .marketing }
        if has(t, ["مرفوضة", "رفض العملية", "لم تتم العملية", "declined", "Rejected transaction", "رصيد غير كافي", "رصيد غير كاف", "Insufficient"]) { return .declined }
        if has(t, ["عكس عملية", "إلغاء عملية", "عكس العملية", "reversal", "reversed"]) || matches(t, #"عكس\s+(?:ال)?عملية|عملية\s+عكسية"#) { return .reversal }
        // Owner special cases: «تأكيد دفعة مقسمة» only confirms a plan (recording it double-counts); a bank purchase
        // «لدى:Tamara» is an ordinary purchase.
        if has(t, ["دفعة مقسمة"]) { return .marketing }
        // Tamara's own texts: «دفعة قادمة بقيمة …» / «دفعتك بقيمة …» (a due notice) and «تأكيد الدفع … بقيمة:» carry no brand word, only a link.
        if matches(t, #"(?:دفعة\s+قادمة|دفعتك)\s+بقيمة|(?m)^\s*تأكيد\s+الدفع[ \t]*\n[\s\S]*?بقيمة\s*:"#) { return .bnplInstalment }
        if has(t, ["تمارا", "tamara", "تابي", "tabby"]) && !has(t, ["شراء"]) { return .bnplInstalment }
        if has(t, ["كشف حساب البطاقة", "كشف البطاقة", "statement", "الحد الأدنى للسداد", "المبلغ المستحق"]) && !has(t, ["شراء"]) { return .statement }
        if has(t, ["سداد بطاقة", "سداد البطاقة", "ائتمانية:سداد", "ائتمانية: سداد", "ائتمانية:تسديد", "ائتمانية: تسديد", "فيزا:سداد", "ماستركارد:سداد", "تسديد بطاقة", "تسديد البطاقة", "card payment"]) { return .cardPayment }
        // RM6 corpus (19 Oct): a finance instalment is an obligation paid, like a bill.
        if has(t, ["قسط تمويل"]) { return .billPayment }
        if has(t, ["سداد فاتورة", "سداد", "SADAD", "المفوتر"]) { return .billPayment }
        // Al Rajhi: «مدفوعات وزارة الداخلية-المخالفات المرورية … رقم الفاتورة: N» is a government bill paid.
        if matches(t, #"^\s*مدفوعات\s+"#) { return .billPayment }
        if has(t, ["استرداد نقدي", "استرجاع نقدي", "cashback", "cash back", "cash-back", "مكافأة نقدية"]) { return .cashback }
        if has(t, ["استرداد", "refund", "مرتجع"]) || matches(t, #"استرجاع\s+عملية|عملية\s+استرجاع|تم\s+اعادة\s+مبلغ"#)
            // Al Rajhi: «تم اضافة مبلغ بقيمة SAR N الى بطاقة *1234 من <merchant>»: a credit from a merchant onto the card.
            || matches(t, #"اضافة\s+مبلغ\s+بقيمة[^\n]*الى\s+بطاقة"#) || matches(t, #"رد\s+فائض\s+اكتتاب"#) { return .refund }
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
        // Al Rajhi: «ايداع:صراف آلي», «ايداع:شيك ورقي» credit the account.
        if matches(t, #"^\s*[اإ]يداع\s*:"#) { return .income }
        if has(t, ["سحب صراف", "سحب نقدي", "ATM", "cash withdrawal"]) { return .withdrawal }
        // Al Rajhi: «بطاقة ائتمانية:تحويل … الى حساب:*1234»: money moved from the credit card to an account.
        if matches(t, #"ائتمانية\s*:\s*تحويل"#) { return .transferOut }
        // stc pay: «Debit via wallet transfer» is money leaving the wallet (owner, 11 Nov); the endpoint is read when printed.
        if matches(t, #"Debit\s+via\s+wallet\s+transfer"#) { return .transferOut }
        if has(t, ["حوالة صادرة", "تحويل صادر", "تحويل إلى", "تحويل الى", "outgoing transfer"])
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
        if has(t, ["تغذية محفظة", "إضافة أموال", "إضافة اموال", "اضافة اموال", "إضافة باستخدام", "اضافة باستخدام", "إيداع عبر حوالة", "شحن المحفظة", "تعبئة المحفظة"])
            || matches(t, #"\b(?:money\s+added|add(?:ed)?\s+funds|funds\s+added|top[\s-]*up|cash[\s-]*in)\b"#) {
            // Explicit purchase/debit wording is parsed below and only becomes neutral when it matches a tracked wallet.
            if !has(t, ["شراء", "مشتريات", "purchase", "خصم"]) { return .transferIn }
        }
        // «حوالة داخلية … الى:1234 … من:Drahim»: into the owner's own account from a named source.
        if has(t, ["حوالة داخلية", "حوالة محلية"]) && matches(t, #"(?m)^\s*(?:الى|إلى)\s*:\s*\*?\d"#) && matches(t, #"(?m)^\s*من\s*:\s*[^\d\s*]"#) { return .transferIn }
        // Al Rajhi: «خصم USD 7.66 من حساب 004*318 للبطاقة *1234 في … والرصيد USD 10.00»: a foreign-currency card debit.
        if matches(t, #"^\s*خصم\s+[A-Za-z]{3}\s+[\d.,]+\s+من\s+حساب\s+\S+\s+للبطاقة\s*\*"#) { return .purchase }
        if has(t, ["خصم عبر حوالة", "بين حساباتي", "بين حساباتك", "للحساب *", "للبطاقة *"]) || (has(t, ["خصم"]) && has(t, ["من حسابك", "من حساب"]) && has(t, ["تحويل"])) { return .transferOut }
        if has(t, ["اضافة", "إضافة"]) && has(t, ["الى حسابك", "إلى حسابك"]) { return .income }
        // Alinma Investment: a share sale pays the portfolio; a share purchase is an ordinary purchase below.
        // Owner, 11 Nov: a sale credits the investment account and a purchase debits it, both as moves to/from the owner's own
        // «Alinma Investment» account (neutral when that wallet is tracked), not income and not spending.
        if matches(t, #"^\s*تنفيذ\s+بيع"#) { return .transferIn }
        if matches(t, #"^\s*تنفيذ\s+شراء"#) { return .transferOut }
        if has(t, ["شراء", "مشتريات", "purchase", "purchases", "Apple Pay", "مدى", "POS"]) { return .purchase }
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
        // Alinma: «حوالة N ريال لحساب **1234 من <name> <date>» lands in the owner's account.
        if matches(t, #"^\s*حوالة\s+[\d.,]+\s*(?:ريال|SAR)\s+لحساب\s*\*+\d+\s+من\s+\S"#) { return .transferIn }
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
    /// `arrivalKnown` is false when `receivedAt` is only the time the owner pasted the message: a relative due day is then left undated.
    public static func parse(_ text: String, timeZone: TimeZone, exponents: CurrencyExponents = .specified, homeCurrency: String = "SAR", receivedAt: Date? = nil, sender: String? = nil, trackedWallets: [String] = [], arrivalKnown: Bool = true) -> ParsedBankMessage {
        let t = clean(text)
        // Owner, 19 Oct: the telecom sender «stc» (not stc pay / STC Bank) sends balance and offers only — ignore it all.
        let kind = ["stc", "stc-ad"].contains(sender?.lowercased().trimmingCharacters(in: .whitespaces) ?? "") ? .marketing : classify(text)
        var result = ParsedBankMessage(kind: kind)
        // Bill-issued notices («تم إصدار فاتورتك … والمبلغ المطلوب N ريال») are not payments, but they become upcoming dues later:
        // the amount and the due date, when printed, are kept in the statement-due fields.
        if kind == .marketing, matches(t, #"صدور\s+فاتورة|فاتورة\s+جديدة|تم\s+إصدار\s+فاتورتك|invoice\s+(?:generated|due)|new\s+bill"#) {
            if let due = labelledAmount(t, ["المبلغ المطلوب", "المبلغ المستحق", "Amount due"], exponents) ?? firstAmount(t, exponents) {
                result.statementDueMinor = due.minor; result.currency = due.currency
            }
            result.dueDate = labelledDate(t, ["تاريخ الاستحقاق", "Due date", "آخر موعد للسداد"], timeZone)
            return result
        }
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
        // The balance is the figure that follows its own label («الرصيد المتوفر: SAR -12.50», «رصيد: 1250.00», «والرصيد USD 10.00»),
        // never another figure on the same line, and the printed sign is kept. A currency word before the number is allowed.
        if let raw = first(#"(?mi)^[^\n]*?(?:الرصيد المتوفر|الرصيد المتاح|رصيد المحفظ[هة]|الرصيد|رصيد|(?<!الحد )المتاح|Avl\.?\s*Bal(?:ance)?|Available\s+Balance|Wallet\s+balance|Balance)\s*[:：]?\s*(?:(?:SAR|SR|USD|EUR|AED|GBP|ر\.س)\s*)?(-?\d{1,3}(?:,\d{3})+(?:\.\d+)?|-?\d+(?:\.\d+)?)"#, in: t),
           let exp = exponents.exponent(result.currency ?? homeCurrency), let minor = minorUnits(raw.replacingOccurrences(of: "-", with: ""), exponent: exp) {
            result.balanceMinor = raw.hasPrefix("-") ? -minor : minor
            // BSF credit card: «الرصيد المتوفر» printed after the «total due» line is the available credit, not a balance.
            if matches(t, #"ائتمانية"#), matches(t, #"(?:المبلغ\s+)?الإجمالي\s+المستحق|إجمالي\s+المبلغ\s+المستحق"#), matches(t, #"الرصيد\s+المتوفر|الرصيد\s+المتاح"#) {
                result.availableLimitMinor = result.balanceMinor; result.balanceMinor = nil
            }
        }
        // A starred number after the word «بطاقة» is the card even when an account tail is printed first («من حساب *1234 / الى بطاقة **5678»).
        result.last4 = first(#"(?:بطاقة|ببطاقة|للبطاقة)\s*:?\s*\*+\s?(\d{4})(?!\d)"#, in: t)
            ?? first(#"\*\s?(\d{4})\b|\b(\d{4})\s?\*"#, in: t)
            // Al Rajhi: «بطاقة:1234;مدى», «عبر:1234;مدى».
            ?? first(#"(?:بطاقة|ببطاقة|عبر)\s*:?\s*(\d{4})(?!\d)"#, in: t)
            ?? first(#"المنتهية\s*ب\s*:?\s*(\d{4})(?!\d)"#, in: t)
            // Al Rajhi card payment: «بطاقة:فيزا 1234» (the network word comes before the tail, no colon after it).
            ?? first(#"بطاقة\s*:\s*(?:فيزا|ماستر\s*كارد|ماستركارد|مدى)[\s-]*(\d{4})(?!\d)"#, in: t)
            // Alinma: «من البطاقة الائتمانية: 1234»; Al Rajhi: «عبر:فيزا;1234».
            ?? first(#"البطاقة\s+الائتمانية\s*:\s*\**(\d{4})(?!\d)"#, in: t)
            ?? first(#"عبر\s*:\s*(?:فيزا|ماستر\s*كارد|مدى)\s*;\s*(\d{4})(?!\d)"#, in: t)
        result.accountLast4 = ownAccountTail(t, kind)
        if kind == .transferOut || kind == .withdrawal {
            result.counterpartyAccountLast4 = first(#"(?mi)^\s*(?:الى حساب|إلى حساب|الى|إلى|To|للحساب|لحساب)\s*:?\s*\**\s*(\d{3,4})\s*\**\s*$"#, in: t)
                ?? first(#"(?m)^\s*ل\s*(\d{3,4})\s*;"#, in: t)
                // SNB «إلى 706*691», D360 «رقم الحساب: ****1234 - <bank>», Al Rajhi «الى حساب:*1234 مبلغ:SAR 1.00».
                ?? first(#"(?m)^\s*(?:إلى|الى)\s+\d+\*(\d{3,4})\s*$"#, in: t)
                ?? first(#"(?m)^\s*رقم\s+الحساب\s*:\s*\**(\d{3,4})(?!\d)"#, in: t)
                ?? first(#"(?m)^\s*الى\s+حساب\s*:\s*\**(\d{3,4})(?=\s+مبلغ)"#, in: t)
                // Al Rajhi Capital: «تحويل N ريال إلى الحساب الإستثماري المنتهي ب ***677 في …».
                ?? first(#"المنتهي\s*ب\s*\*+(\d{3,4})"#, in: t)
        } else if kind == .transferIn {
            result.counterpartyAccountLast4 = first(#"(?mi)^\s*(?:من|من حساب|From)\s*:?\s*\**\s*(\d{3,4})\s*\**\s*$"#, in: t)
                ?? first(#"(?m)^\s*من\s*(\d{3,4})\s*;"#, in: t)
                // Al Rajhi Capital: «… من الحساب الإستثماري المنتهي ب ***677 في 09-06-2021 15:48:47».
                ?? first(#"المنتهي\s*ب\s*\*+(\d{3,4})"#, in: t)
                // Al Rajhi incoming: «من ايبان:*1234».
                ?? first(#"(?m)^\s*من\s+ايبان\s*:\s*\**(\d{3,4})"#, in: t)
        }
        // Sukuk prints its account number as «رقم: 1234».
        if result.last4 == nil { result.last4 = first(#"(?m)^\s*رقم\s*:\s*(\d{4})\s*$"#, in: t) }
        // Sukuk (a Saudi platform) prints «المبلغ: 1,500.00» with no currency word: the home currency is meant.
        if result.amountMinor == nil, kind != .statement, BankMessageIdentity.matches(sender ?? "", "sukuk"),
           let raw = first(#"(?m)^\s*المبلغ\s*:\s*(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)\s*$"#, in: t),
           let exp = exponents.exponent(homeCurrency), let minor = minorUnits(raw, exponent: exp) {
            result.amountMinor = minor; result.currency = homeCurrency
        }
        result.eventAt = eventDate(t, timeZone, near: receivedAt ?? Date(), referenceIsDelivery: receivedAt != nil)
        result.merchant = labelled(t, ["لدى", "من متجر", "at", "التاجر"])
        result.biller = labelled(t, ["المفوتر", "مفوتر", "Biller"])
        result.counterparty = kind == .transferIn ? (partyLabelled(t, ["من", "From", "اسم المرسل", "المرسل"]) ?? partyLine(t, ["من", "From"]))
            : kind == .transferOut ? (partyLabelled(t, ["إلى", "الى", "To", "المستفيد", "اسم المستفيد", "اسم المستلم", "المستلم"]) ?? transferOutPartyAfterAmount(t) ?? partyLine(t, ["إلى", "الى", "To", "مستفيد"])) : nil
        if kind == .refund, result.merchant == nil { result.merchant = labelled(t, ["من"]) }
        // Al Rajhi: «… الى بطاقة *1234 من <merchant> في 25-10-19 10:30 والحد المتبقي …».
        if kind == .refund, result.merchant == nil {
            result.merchant = first(#"الى\s+بطاقة\s*\*?\d{4}\s+من\s+(.+?)\s+في\s+\d"#, in: t)
        }
        if kind == .refund, result.merchant == nil, matches(t, #"رد\s+فائض\s+اكتتاب"#) { result.merchant = "اكتتاب" }
        // Al Rajhi: «على : <merchant>» names the merchant of a declined card operation.
        if kind == .declined, result.merchant == nil { result.merchant = labelled(t, ["على"]) }
        // Al Rajhi «تم رفض العملية: …»: the merchant sits under «الحساب:» (a name, not an account number).
        if kind == .declined, result.merchant == nil { result.merchant = partyLabelled(t, ["الحساب"]) }
        // BSF, SNB, Alinma, barq: the merchant opens its own line after «من», «لـ», «لدى» or «At», with or without a colon.
        if [.purchase, .refund, .declined, .reversal].contains(kind), result.merchant == nil { result.merchant = lineMerchant(t) }
        // stc pay English layout: «At: <merchant> <city> SA» followed by «Date:».
        if kind == .purchase, let m = result.merchant, matches(t, #"(?m)^\s*Date\s*:"#), matches(t, #"(?m)^\s*At\s*:"#) { result.merchant = stripCountryAndCity(m) }
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
        // Al Rajhi new layout: «ل7635;<name>» (recipient tail and name) on an outgoing transfer, «من7524;<name>» on an incoming one.
        if kind == .transferOut, result.counterparty == nil, let m = first(#"(?m)^\s*ل\s*\d{3,4}\s*;\s*(\S.*?)\s*$"#, in: t) { result.counterparty = m }
        if kind == .transferIn, result.counterparty == nil, let m = first(#"(?m)^\s*من\s*\d{3,4}\s*;\s*(\S.*?)\s*$"#, in: t) { result.counterparty = m }
        // «الحساب الإستثماري المنتهي ب ***677 في 09-06-2021 15:48:47»: the name stops before the tail and the date.
        if kind == .transferIn || kind == .transferOut, let party = result.counterparty {
            let cut = party.replacingOccurrences(of: #"\s+في\s+\d.*$"#, with: "", options: .regularExpression)
                .replacingOccurrences(of: #"\s+المنتهي\s*ب\s*\*+\d+$"#, with: "", options: .regularExpression)
            if !cut.isEmpty { result.counterparty = cut }
        }
        // «تم تحويل مبلغ 100 SAR إلى NAME.»: the sentence's full stop is not part of the name.
        if let party = result.counterparty, party.hasSuffix("."), party.count > 1 { result.counterparty = String(party.dropLast()).trimmingCharacters(in: .whitespaces) }
        // Alinma: «حوالة N ريال لحساب **1234 من <name> 2026-01-05 10:30».
        if kind == .transferIn, result.counterparty == nil {
            result.counterparty = first(#"(?m)^\s*حوالة\s+[\d.,]+\s*(?:ريال|SAR)\s+لحساب\s*\*+\d+\s+من\s+(.+?)\s+\d{4}-\d{1,2}-\d{1,2}"#, in: t)
        }
        // SNB English: «Outgoing IPS local transfer from *1234 To <name> Amount 100 SAR By <bank> …».
        if kind == .transferOut, result.counterparty == nil {
            result.counterparty = first(#"\bTo\s+(.+?)\s+Amount\b"#, in: t)
        }
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
        if kind != .fee {
            let home = exponents.exponent(homeCurrency)
            result.feeMinor = labelledMoney(t, #"(?:رسوم وضريبة|رسوم العملية|الرسوم|رسوم(?!\s*تحويل)|(?<![\p{L}\p{N}])Fees?(?=\s*:)|عمولة)"#, home)
            result.vatMinor = labelledMoney(t, #"(?:ضريبة القيمة المضافة|(?<!و)ضريبة|VAT)"#, home)
        }
        result.foreignFeeMinor = labelledMoney(t, #"(?:رسوم تحويل العملة|FX Markup|Currency conversion fee)"#, exponents.exponent(homeCurrency))
        result.exchangeRate = first(#"(?:سعر الصرف|Exchange Rate)\s*[≈~:]*\s*(\d+(?:\.\d+)?)"#, in: t)
        result.remainingLimitMinor = labelledMoney(t, #"(?:حد الصرف المتبقي|الصرف المتبقي|الحد المتبقي)"#, exponents.exponent(homeCurrency))
        result.availableLimitMinor = result.availableLimitMinor ?? labelledMoney(t, #"(?:الحد المتاح|Avl\.?\s*limit|Available limit)"#, exponents.exponent(homeCurrency))
        if kind == .declined {
            result.declineReason = matches(t, #"غير\s+كاف\p{M}*|لعدم\s+وجود\s+رصيد|Insufficient"#) ? .insufficientBalance
                : matches(t, #"limit\s+exceeded|تجاوز[^\n]*الحد|تجاوز\s+الحد"#) ? .limitExceeded
                : matches(t, #"\bPIN\b|الرقم\s+السري"#) ? .wrongPIN
                : matches(t, #"موقوف|محظور|منتهية\s+الصلاحية|\bblocked\b|\binactive\b|غير\s+مفعل"#) ? .cardBlocked : .other
        }
        // Alinma Investment trades: «تنفيذ بيع/شراء <security> لمحفظتك … بسعر P SAR لعدد N سهم بقيمة إجمالية T عمولة F ضريبة V».
        // The amount is the total, not the per-share price that comes first.
        if matches(t, #"^\s*تنفيذ\s+(?:بيع|شراء)"#), let total = first(#"بقيمة\s+إجمالية\s+(\d[\d,]*(?:\.\d+)?)"#, in: t),
           let cur = result.currency, let exp = exponents.exponent(cur), let minor = minorUnits(total, exponent: exp) {
            result.amountMinor = minor
            result.merchant = first(#"^\s*تنفيذ\s+(?:بيع|شراء)\s+(.+?)\s+لمحفظتك"#, in: t)
            result.counterparty = "Alinma Investment"
        }
        // Tamara/Tabby print the due day relatively: «مستحقة اليوم», «خلال يومين», «tomorrow».
        // D5 (owner, 11 Nov 2026): only from a known arrival time. A message pasted days later has none, so the due stays undated.
        if kind == .bnplInstalment, result.dueDate == nil, arrivalKnown, let base = receivedAt {
            let days = matches(t, #"مستحقة\s+اليوم|due\s+today"#) ? 0 : matches(t, #"خلال\s+يومين"#) ? 2 : matches(t, #"\btomorrow\b|غدا"#) ? 1 : nil
            if let days { result.dueDate = base.addingTimeInterval(Double(days) * 86_400) }
        }
        // Date with no clock time: kept apart so a missing time never becomes a guessed one.
        if result.eventAt == nil { result.eventDateOnly = dateOnly(t, timeZone, near: receivedAt ?? Date()) }
        if kind == .bnplInstalment, result.merchant == nil {
            result.merchant = first(#"لطلبك\s+من\s+(.+?)\s+مستحقة"#, in: t) ?? partyLabelled(t, ["من", "المتجر"])
                // Tabby English: «Your SAR 120.00 purchase at <merchant> is confirmed» / «Your <merchant> payment of SAR 45 will be charged …».
                ?? first(#"(?i)purchase\s+at\s+(.+?)\s+is\s+confirmed"#, in: t) ?? first(#"(?i)^\s*Your\s+(.+?)\s+payment\s+of\b"#, in: t)
        }
        // Saudi Electricity «شكرا على سداد فاتورة الحساب N بمبلغ 100.00»: no currency word is printed; the utility is Saudi, so the
        // home currency is meant (sender-scoped, like Sukuk).
        if kind == .billPayment, result.amountMinor == nil, (sender?.lowercased().contains("alkahraba") ?? false),
           let raw = first(#"بمبلغ\s+(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#, in: t),
           let exp = exponents.exponent(homeCurrency), let minor = minorUnits(raw, exponent: exp) {
            result.amountMinor = minor; result.currency = homeCurrency
        }
        if kind == .bnplInstalment {
            result.provider = has(t, ["تمارا", "tamara", "tmra.pe"]) || (sender?.lowercased().contains("tamara") ?? false) ? "Tamara" : "Tabby"
            if let pair = firstTwo(#"(?i)(?:القسط|الدفعة|دفعة|قسط|payment|instalment|installment)\s*(?:رقم\s*)?(\d{1,2})\s*(?:من|of|/)\s*(\d{1,2})"#, in: t),
               let n = Int(pair.0), let m = Int(pair.1), n >= 1, m >= n { result.instalmentNumber = n; result.instalmentCount = m }
            if let rest = labelledAmount(t, ["المبلغ المتبقي", "الرصيد المتبقي", "المتبقي", "Remaining balance", "Remaining"], exponents) { result.remainingMinor = rest.minor }
        }
        if kind == .purchase || kind == .refund || kind == .cashback {
            result.cardKind = has(t, ["ائتمان", "إئتمان", "credit"]) ? .credit : has(t, ["مسبقة الدفع", "prepaid"]) ? .prepaid
                : has(t, ["مدى", "mada", "Apple Pay"]) ? .debit : nil
        }
        // Tamara/Tabby reminders of a payment still to come («دفعة قادمة بقيمة…», «دفعتك … مستحقة اليوم», «will be charged tomorrow»)
        // move no money. They are notices; the figure and due day stay in the statement-due fields.
        if result.kind == .bnplInstalment, matches(t, #"(?:دفعة\s+قادمة|دفعتك)\s+بقيمة|will\s+be\s+charged"#) {
            result.statementDueMinor = result.amountMinor; result.amountMinor = nil; result.kind = .marketing
        }
        // A movement kind with no amount and no statement due is not a movement: an offer, a tariff or terms update, or a
        // cancelled-for-non-payment notice is a notice; anything else is left for review. Never recorded as an amount-less expense.
        if BankIntake.decision(result.kind) == .record, result.amountMinor == nil, result.statementDueMinor == nil {
            let notice = matches(t, #"تحديث|يسري\s+العرض|الشروط\s+والأحكام|لعدم\s+السداد|استمتع|ترشيحك|للاستثمار|بعائد|طرح|مبروك|Congratulations|https?://"#)
            return ParsedBankMessage(kind: notice ? .marketing : .unknown)
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
        let pattern = "(?:\(number)\\s*(\(codes))(?![A-Za-z]))|(?:(?<![A-Za-z])(\(codes))\\s*\(number))"
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
                // Alinma prints a merchant code glued to the name: «من: 1234EXAMPLE SHOP».
                if let head = value.first, head.isNumber, let code = value.range(of: #"^\d+(?=[A-Za-z\u0621-\u064A])"#, options: .regularExpression) { value = String(value[code.upperBound...]) }
                guard let head = value.first, !head.isNumber, head != "*", !value.hasPrefix("حساب"), !value.hasPrefix("رصيد") else { continue }
                if label.count == 2, line.dropFirst(label.count).first?.isLetter == true { continue } // «منصة», «atm»: a word, not a label
                return value
            }
        }
        return nil
    }

    /// «label … 12.50 SAR» or «label: 12.50»: the first number after the label on its line, minor units by the home exponent.
    static func labelledMoney(_ text: String, _ labelPattern: String, _ exponent: Int?) -> Int? {
        guard let exponent, let raw = first(#"(?mi)^[^\n]*?"# + labelPattern + #"\s*[:：]?\s*(?:(?:SAR|SR|ر\.س)\s*)?(\d{1,3}(?:,\d{3})+(?:\.\d+)?|\d+(?:\.\d+)?)"#, in: text) else { return nil }
        return minorUnits(raw, exponent: exponent)
    }

    /// «في: 20/03/2021», «2026-01-05», «25-12-1»: a date with no time, at 12:00 local.
    static func dateOnly(_ text: String, _ timeZone: TimeZone, near reference: Date) -> Date? {
        func noon(_ y: Int, _ m: Int, _ d: Int) -> Date? { var c = DateComponents(); c.year = y; c.month = m; c.day = d; c.hour = 12; return date(c, timeZone) }
        if let m = first(#"(?<![\d/\\-])(\d{4}-\d{1,2}-\d{1,2})(?![\d-])"#, in: text) {
            let v = m.split(separator: "-").compactMap { Int($0) }
            if v.count == 3 { return noon(v[0], v[1], v[2]) }
        }
        guard let regex = try? NSRegularExpression(pattern: #"(?<![\d/\\-])(\d{1,2})[/\\-](\d{1,2})[/\\-](\d{2,4})(?![\d])"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        let v = (1...3).compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } }
        guard v.count == 3, let yearRange = Range(match.range(at: 3), in: text) else { return nil }
        let fullYear = text[yearRange].count == 4
        let candidates = [noon(v[2] < 100 ? 2000 + v[2] : v[2], v[1], v[0]), fullYear ? nil : noon(2000 + v[0], v[1], v[2])].compactMap { $0 }
        return nearest(candidates, reference)
    }

    /// The owner's own account tail: «من:*1234» / «من حساب: **7391» / «حساب 1234*» / «A/C:**1234» on a debit,
    /// «الى:5678» / «إلى **0019» / «حساب *…» on an incoming transfer. The other party's account is never taken.
    static func ownAccountTail(_ text: String, _ kind: BankMessageKind) -> String? {
        let tail = #"\s*:?\s*\**\s*(\d{3,4})\s*\**\s*$"#
        // SNB prints «حساب 706*691»: the digits after the star are the tail.
        let starred = first(#"(?m)^\s*(?:حساب|من)\s*\d+\*(\d{3,4})\s*$"#, in: text)
        let source: String? = first(#"(?mi)^\s*(?:من|من حساب|من الحساب|From|A/C|حساب|رقم حساب|الحساب|ر\.ح|خصمت من حساب)"# + tail, in: text)
            // Al Rajhi: «خصم SAR 23.00 من حسابك *1234 في 20-08-25 09:42 - <label>».
            ?? first(#"من\s+حسابك\s*\*+(\d{3,4})(?!\d)"#, in: text)
            ?? starred
            // Al Rajhi: «من حساب 004*318»: the digits after the star.
            ?? first(#"من\s+حساب\s+\d+\*(\d{3,4})(?!\d)"#, in: text)
        let destination: String? = first(#"(?mi)^\s*(?:الى|إلى|To|إلى حساب|الى حساب|حساب|الحساب)"# + tail, in: text) ?? starred
            // Al Rajhi new layout: «ل7746» (the receiving account, tatweel removed); ATM deposits glue the machine's bank to the tail.
            ?? first(#"(?m)^\s*ل\s*(\d{3,4})\s*$"#, in: text)
            ?? first(#"(?m)^\s*الى\s*:\s*\*+(\d{4})(?=[A-Za-z])"#, in: text)
        if kind == .transferIn || kind == .income || kind == .salary { return destination }
        if kind == .reversal || kind == .refund || kind == .cashback { return destination ?? source }
        guard [.purchase, .withdrawal, .transferOut, .cardPayment, .billPayment, .fee, .declined, .bnplInstalment].contains(kind) else { return nil }
        return source
    }

    /// A person, company or wallet name behind a label: «الى:<name>». A value that starts with a digit or «*» is an account, and one
    /// that starts with an account/bank word is not a name.
    static func isNameValue(_ value: String) -> Bool {
        guard let head = value.first, !head.isNumber, head != "*" else { return false }
        return !matches(value, #"^(?:حساب|الحساب|بنك|البنك|مصرف|IBAN|آيبان|الأيبان|الايبان|لآيبان|بطاقة|البطاقة|رقم)(?![\u0621-\u064A])"#)
    }

    /// «label: name» on its own line, skipping lines whose value is an account.
    static func partyLabelled(_ text: String, _ labels: [String]) -> String? {
        for line in text.split(separator: "\n").map(String.init) {
            for label in labels {
                guard let range = line.range(of: label + ":") ?? line.range(of: label + " :") else { continue }
                // «من:» must open the line or follow a space: «لحساب من:» style tails are not labels of their own.
                let value = line[range.upperBound...].trimmingCharacters(in: .whitespaces)
                if isNameValue(value) { return value }
            }
        }
        return nil
    }

    /// «إلى <name>» or «من <name>» opening its own line with no colon (stc Bank, barq).
    static func partyLine(_ text: String, _ labels: [String]) -> String? {
        for line in text.split(separator: "\n").map({ $0.trimmingCharacters(in: .whitespaces) }) {
            for label in labels {
                guard line.hasPrefix(label), let next = line.dropFirst(label.count).first, next.isWhitespace else { continue }
                let value = line.dropFirst(label.count).trimmingCharacters(in: .whitespaces)
                if isNameValue(value) { return value }
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

    static func firstTwo(_ pattern: String, in text: String) -> (String, String)? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let m = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges >= 3, let a = Range(m.range(at: 1), in: text), let b = Range(m.range(at: 2), in: text) else { return nil }
        return (String(text[a]), String(text[b]))
    }
    static func first(_ pattern: String, in text: String) -> String? {
        guard let regex = try? NSRegularExpression(pattern: pattern), let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)) else { return nil }
        for i in 1..<match.numberOfRanges where match.range(at: i).location != NSNotFound {
            return Range(match.range(at: i), in: text).map { String(text[$0]) }
        }
        return nil
    }

    private static func nearest(_ dates: [Date], _ reference: Date) -> Date? {
        dates.min { abs($0.timeIntervalSince(reference)) < abs($1.timeIntervalSince(reference)) }
    }

    private static let arabicMonths: [String: Int] = ["يناير": 1, "فبراير": 2, "مارس": 3, "ابريل": 4, "أبريل": 4, "إبريل": 4, "مايو": 5, "يونيو": 6, "يوليو": 7,
                                                       "اغسطس": 8, "أغسطس": 8, "سبتمبر": 9, "اكتوبر": 10, "أكتوبر": 10, "نوفمبر": 11, "ديسمبر": 12]

    /// RM6: eventAt from the text — "2026-10-15 13:05", "15/10/26 13:05", "26-1-6 5:36", "10\\1\\26 18:25", "13:05 2026-01-18",
    /// "on 05/09/26 at 06:23", "09/05 09:54" (year from the receive time) or «14 يونيو 2021 10:52:0 ص».
    static func eventDate(_ text: String, _ timeZone: TimeZone, near reference: Date = Date(), referenceIsDelivery: Bool = false) -> Date? {
        /// Month-first readings («2/5/2026 7:25 PM») are never preferred by default: a day-first date stays day first. The swap is
        /// taken only when the reference is the real delivery time and the month-first reading lands within two days of it while
        /// the day-first one does not. Without a delivery time (pasted or imported history) nothing is swapped.
        func preferMonthFirst(_ best: Date, _ alt: Date) -> Bool {
            referenceIsDelivery && abs(alt.timeIntervalSince(reference)) <= 2 * 86_400 && abs(best.timeIntervalSince(reference)) > 2 * 86_400
        }
        func ints(_ match: NSTextCheckingResult, _ range: ClosedRange<Int>) -> [Int] { range.compactMap { Range(match.range(at: $0), in: text).flatMap { Int(text[$0]) } } }
        func find(_ pattern: String) -> NSTextCheckingResult? {
            (try? NSRegularExpression(pattern: pattern))?.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        }
        let sep = #"[/\\-]"#
        // 1. «yyyy-mm-dd hh:mm»
        if let m = find(#"(\d{4})-(\d{1,2})-(\d{1,2})[ T]+(\d{1,2}):(\d{2})"#) {
            let v = ints(m, 1...5)
            if v.count == 5 { var parts = DateComponents(); parts.year = v[0]; parts.month = v[1]; parts.day = v[2]; parts.hour = v[3]; parts.minute = v[4]; return date(parts, timeZone) }
        }
        // 1b. «التاريخ:⏎2026-01-27⏎الوقت:⏎13:38» (traffic violations: value on the line after its label)
        if let m = find(#"(\d{4})-(\d{1,2})-(\d{1,2})\s*\n\s*الوقت\s*:\s*\n?\s*(\d{1,2}):(\d{2})"#) {
            let v = ints(m, 1...5)
            if v.count == 5 { var parts = DateComponents(); parts.year = v[0]; parts.month = v[1]; parts.day = v[2]; parts.hour = v[3]; parts.minute = v[4]; return date(parts, timeZone) }
        }
        // 2. «hh:mm yyyy-mm-dd» (stc pay, D360, Alinma)
        if let m = find(#"(\d{1,2}):(\d{2})(?::\d{1,2})?\s+(\d{4})-(\d{1,2})-(\d{1,2})"#) {
            let v = ints(m, 1...5)
            if v.count == 5 { var parts = DateComponents(); parts.hour = v[0]; parts.minute = v[1]; parts.year = v[2]; parts.month = v[3]; parts.day = v[4]; return date(parts, timeZone) }
        }
        // 3. «a-b-c hh:mm» and «hh:mm a-b-c» with «-», «/» or «\\»: Al Rajhi, Alinma and stc pay print «yy-mm-dd», others «dd-mm-yy».
        // Both readings are tried; the one that is a real date nearest the receive time wins.
        var triple: (a: Int, b: Int, c: Int, cDigits: Int, hour: Int, minute: Int)?
        if let m = find(#"(\d{1,2})\#(sep)(\d{1,2})\#(sep)(\d{1,4})\s+(?:at\s+|الساعة\s+)?(\d{1,2}):(\d{2})(?::\d{1,2})?(?:[^\d\n]{0,2}?([AaPp][Mm])(?![A-Za-z]))?"#) {
            let v = ints(m, 1...5)
            if v.count == 5, let r = Range(m.range(at: 3), in: text) {
                var hour = v[3]
                if let marker = Range(m.range(at: 6), in: text).map({ text[$0].lowercased() }) { hour = marker == "pm" ? v[3] % 12 + 12 : v[3] % 12 }
                triple = (v[0], v[1], v[2], text[r].count, hour, v[4])
            }
        } else if let m = find(#"(\d{1,2}):(\d{2})(?::\d{1,2})?\s+(\d{1,2})\#(sep)(\d{1,2})\#(sep)(\d{1,4})"#) {
            let v = ints(m, 1...5)
            if v.count == 5, let r = Range(m.range(at: 5), in: text) { triple = (v[2], v[3], v[4], text[r].count, v[0], v[1]) }
        }
        if let t = triple {
            var base = DateComponents(); base.hour = t.hour; base.minute = t.minute
            var dayFirst = base; dayFirst.day = t.a; dayFirst.month = t.b; dayFirst.year = t.c < 100 ? 2000 + t.c : t.c
            var yearFirst = base; yearFirst.year = 2000 + t.a; yearFirst.month = t.b; yearFirst.day = t.c
            // «26-1-6»: a one-digit last part cannot be a year; a four-digit one cannot be a day.
            let readings = [t.cDigits >= 2 ? date(dayFirst, timeZone) : nil, t.cDigits <= 2 && t.a < 100 ? date(yearFirst, timeZone) : nil].compactMap { $0 }
            var monthFirst = base; monthFirst.month = t.a; monthFirst.day = t.b; monthFirst.year = t.c < 100 ? 2000 + t.c : t.c
            let alt = t.cDigits >= 2 ? date(monthFirst, timeZone) : nil
            // «02/07/2026»: some senders print month first. Day-first stays the default (see preferMonthFirst); month first is
            // used alone only when day-first is impossible (a month above 12).
            if let best = nearest(readings, reference) {
                if let alt, preferMonthFirst(best, alt) { return alt }
                return best
            }
            if let alt { return alt }
        }
        // 4. «dd/mm hh:mm» or «hh:mm dd/mm» with no year: the year that puts it nearest the receive time.
        if let m = find(#"(?<![\d/\\-])(\d{1,2})/(\d{1,2})\s+(\d{1,2}):(\d{2})(?![\d/-])"#) {
            let v = ints(m, 1...4)
            if v.count == 4 {
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
                let year = calendar.component(.year, from: reference)
                func readings(day: Int, month: Int) -> [Date] {
                    (year - 1...year + 1).compactMap { y -> Date? in var parts = DateComponents(); parts.year = y; parts.month = month; parts.day = day; parts.hour = v[2]; parts.minute = v[3]; return date(parts, timeZone) }
                }
                // «09/05 09:54» can be month first; see preferMonthFirst.
                let best = nearest(readings(day: v[0], month: v[1]), reference), alt = nearest(readings(day: v[1], month: v[0]), reference)
                if let best {
                    if let alt, preferMonthFirst(best, alt) { return alt }
                    return best
                }
                if let alt { return alt }
            }
        }
        // 5. «14 يونيو 2021 10:52:0 ص»
        if let m = find(#"(\d{1,2})\s+([\u0621-\u064A]+)\s+(\d{4})\s+(\d{1,2}):(\d{1,2})(?::\d{1,2})?\s*([صم])?"#),
           let monthRange = Range(m.range(at: 2), in: text), let month = arabicMonths[String(text[monthRange])] {
            let v = [1, 3, 4, 5].compactMap { Range(m.range(at: $0), in: text).flatMap { Int(text[$0]) } }
            if v.count == 4 {
                var parts = DateComponents(); parts.day = v[0]; parts.month = month; parts.year = v[1]; parts.minute = v[3]
                let marker = Range(m.range(at: 6), in: text).map { String(text[$0]) }
                parts.hour = marker == "م" ? (v[2] % 12) + 12 : marker == "ص" ? v[2] % 12 : v[2]
                return date(parts, timeZone)
            }
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
