import Foundation
import XCTest
@testable import MadarMoney

/// RM6: the owner's real bank messages, kept only on this Mac in Madar/Private/bank-messages (git-ignored).
/// Skipped when the folder is absent. Writes aggregate counts only to Madar/Artifacts/bank-corpus-report.json and redacted layouts to the git-ignored local guide.
final class BankCorpusTests: XCTestCase {
    private struct Line: Decodable { let sender: String; let date: String; let text: String }
    private struct Layout { var count = 0; var kinds: [String: Int] = [:]; var missing = Set<String>() }
    private static let madar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// Owner-confirmed institutions represented as tracked accounts in this parser-only corpus pass.
    private static let trackedOwnerWallets = ["Barq", "STC Pay", "STC Bank", "Tiqmo", "Drahim", "D360", "Tweeq", "urpay", "Alinma Investment", "Sukuk"]

    private static func kindSummary(_ kinds: [String: Int]) -> String {
        kinds.sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
            .map { "\($0.key)×\($0.value)" }
            .joined(separator: "، ")
    }

    /// A message's layout: digits → #, greetings and party/merchant values hidden, lines joined with ⏎.
    static func layout(_ text: String) -> String {
        let lines = text.split(whereSeparator: \.isNewline).map { line -> String in
            var l = String(line).trimmingCharacters(in: .whitespaces).replacing(/[0-9٠-٩]/, with: "#")
            let greetings = ["عميلنا العزيز", "عزيزي العميل", "عزيزنا العميل", "عزيزتي", "عزيزي", "مرحباً", "مرحبًا", "مرحبا", "أهلاً", "اهلا", "Dear customer", "Dear", "Hello", "Hi"]
            if let greeting = greetings.first(where: { l.range(of: $0, options: [.anchored, .caseInsensitive]) != nil }) {
                l = String(l.prefix(greeting.count)) + " ‹…›"
            }
            let partyLabel = #"(?i)(^|[^\p{L}\p{N}])(اسم\s+(?:المستفيد|المرسل|المستلم|الطرف)|المستفيد|المستلم|المرسل|Beneficiary|Counterparty|Recipient|Merchant|Sender|From|To|من|لدى|إلى|الى|At|للحساب)\s*[:：]?\s*.+$"#
            l = l.replacingOccurrences(of: partyLabel, with: "$1$2 ‹…›", options: .regularExpression)
            // Merchant-only «لـName», normalized «لName», and «ل Name» lines may omit a colon.
            l = l.replacingOccurrences(of: #"(?i)(^|\s)(لدى|لـ|ل)\s*[:：]?\s*\S.*$"#, with: "$1$2 ‹…›", options: .regularExpression)
            return l
        }.filter { !$0.isEmpty }
        return String(lines.joined(separator: " ⏎ ").prefix(180))
    }

    // MARK: Accuracy heuristics (independent of the parser's own regexes)

    /// Figures printed beside a currency word, in hundredths (independent of the parser).
    private static func printedFigures(_ t: String) -> Set<Int> {
        var out = Set<Int>()
        let forms = [#"(\d[\d,]*(?:\.\d+)?)\s*(?:SAR|SR|USD|EUR|AED|GBP|ريال|ر\.س|دولار|درهم)(?![A-Za-z])"#, #"(?<![A-Za-z])(?:SAR|SR|USD|EUR|AED|GBP)\s*(\d[\d,]*(?:\.\d+)?)"#]
        for form in forms {
            guard let regex = try? NSRegularExpression(pattern: form) else { continue }
            for m in regex.matches(in: t, range: NSRange(t.startIndex..., in: t)) {
                guard let r = Range(m.range(at: 1), in: t), let d = Double(t[r].replacingOccurrences(of: ",", with: "")) else { continue }
                out.insert(Int((d * 100).rounded()))
            }
        }
        return out
    }

    private static func has(_ text: String, _ pattern: String) -> Bool { text.range(of: pattern, options: [.regularExpression, .caseInsensitive]) != nil }

    /// What the message prints versus what the parser captured. Returns counters to add for one message.
    private static func accuracyMisses(_ raw: String, _ p: ParsedBankMessage, sender: String = "?") -> [String: Int] {
        let t = BankMessageParser.clean(raw)
        let money = #"(بمبلغ\s*\d)|(\d[\d,]*(\.\d+)?\s*(SAR|SR|USD|AED|EUR|ريال|ر\.س|دولار|درهم))|((SAR|SR|USD|AED|EUR)\s*\d)"#
        let moneyPrinted = has(t, money)
        var out: [String: Int] = [:]
        let decision = BankIntake.decision(p.kind)
        if decision == .discard || decision == .discardWithoutText {
            out["financialTotal"] = 1; out["fullyRead"] = 1; out["fullyReadWithSource"] = 1; out["notice"] = 1
            if p.kind == .marketing && moneyPrinted && has(t, #"(شراء|حوالة|تحويل|سحب|إيداع|ايداع|Purchase|Transfer|Debit|Credit)"#) { out["noticeWithMovementWord"] = 1 }
            return out
        }
        if p.kind == .unknown {
            if moneyPrinted { out["financialTotal"] = 1; out["miss.unknown"] = 1; out["strict.total"] = 1; out["strict.miss.unknown"] = 1 } else { out["nonFinancialUnknown"] = 1 }
            return out
        }
        out["financialTotal"] = 1
        var miss: [String] = []
        let amountCaptured = p.amountMinor != nil || p.statementDueMinor != nil
        if moneyPrinted && !amountCaptured { miss.append("miss.amount") }
        // Correctness, not only presence: the parsed amount must equal a figure printed next to a currency word.
        if let parsedMinor = p.amountMinor, p.kind != .statement, !has(t, "بقيمة إجمالية") {
            let printed = Self.printedFigures(t)
            if !printed.isEmpty && !printed.contains(parsedMinor) && !(p.statedHomeMinor.map(printed.contains) ?? false) { miss.append("miss.amountMismatch") }
        }
        if moneyPrinted && amountCaptured && p.currency == nil { miss.append("miss.currency") }
        if has(t, #"\d{1,2}:\d{2}"#) && p.eventAt == nil { miss.append("miss.time") }
        let valued = #"(?m)^\s*%@\s*:?\s*[^\d\s*:]"#
        if [.purchase, .refund, .declined].contains(p.kind), p.merchant == nil,
           (has(t, String(format: valued, "(لدى|من|At|Merchant|على|التاجر)")) || has(t, #"(?m)^\s*(في|ل)\s*:\s*(?!SA\b|السعودية)[^\d\s*:]"#)) { miss.append("miss.merchant") }
        if [.transferIn, .transferOut].contains(p.kind), p.counterparty == nil,
           has(t, #"(?m)^\s*(من|إلى|الى|To|From|المستفيد|اسم المستفيد|إلى المستفيد|اسم المرسل|اسم المستلم|المستلم)(\s*:\s*|\s+)(?!حساب|بنك|البنك|مصرف|IBAN|آيبان|الأيبان|الايبان|لآيبان|بطاقة|رقم)[^\d\s*:]"#) || has(t, #"(?m)^\s*ل\s*:\s*[^\d\s*:]"#) || has(t, #"(?i)(?:تحويل|حوالة|transfer)[^\n]*\s(?:إلى|الى|To)\s+[^\d\s]"#) { miss.append("miss.party") }
        if [.purchase, .withdrawal, .refund, .declined, .reversal].contains(p.kind), p.last4 == nil,
           has(t, #"(\*\s?\d{4}\b|\b\d{4}\s?\*|(بطاقة|ببطاقة|عبر|card)\s*:?\s*\d{4}(?!\d))"#) { miss.append("miss.last4") }
        if miss.isEmpty { out["fullyRead"] = 1 } else { for m in miss { out[m, default: 0] += 1 } }
        // STRICT: notices (marketing/OTP) are outside the count; a recordable message with no amount is an error; the amount must be
        // a figure printed on an operation line (not balance, limit, fee, VAT or rate lines); a printed name needs a counterparty.
        var strictMiss = miss.filter { $0 != "miss.amountMismatch" }
        if p.amountMinor == nil && p.statementDueMinor == nil && !strictMiss.contains("miss.amount") { strictMiss.append("miss.noAmount") }
        if let parsedMinor = p.amountMinor, p.kind != .statement, !has(t, "بقيمة إجمالية") {
            let operationLines = t.split(separator: "\n").map(String.init).filter { !has($0, #"(الرصيد|رصيد|المتاح|المتبقي|رسوم|عمولة|ضريبة|Fee|VAT|Balance|Limit|سعر الصرف|Exchange|Markup|إجمالي|الإجمالي|المستحق)"#) }
            let figures = Self.printedFigures(operationLines.joined(separator: "\n"))
            if !figures.isEmpty && !figures.contains(parsedMinor) && !(p.statedHomeMinor.map(figures.contains) ?? false) { strictMiss.append("miss.amountNotOperation") }
        }
        // Printed card/account tails must be captured (any masked shape), a balance must not repeat the amount when the text prints
        // two different figures, «available» must not become a balance on a credit card, a future-payment reminder is no movement.
        if BankIntake.decision(p.kind) == .record {
            let captured = Set([p.last4, p.accountLast4, p.counterpartyAccountLast4].compactMap { $0 })
            let ignoredLine = #"(IBAN|آيبان|الأيبان|الايبان|لآيبان|مرجع|Reference|Ref\b|المخالفة|الفاتورة|الطلب|الهوية|شيك|رقم الفرصة)"#
            let shapes = [#"(?:بطاقة|ببطاقة|للبطاقة|[Cc]ard|عبر|ائتمانية|إئتمانية)[^\n\d]{0,14}\**\s*(\d{4})(?!\d|\.\d|,\d)"#, #"\*+\s?(\d{3,4})(?!\d)"#, #"(?<!\d)(\d{4})\s?\*"#,
                          #"(?m)^\s*(?:من|الى|إلى|ل|حساب|رقم حساب|A/C|من حساب|الى حساب|إلى حساب)\s*:?\s*\**\s*(\d{3,4})\s*(?:\**|;.*)$"#, #"\d+\*(\d{3})(?!\d)"#]
            var printed = Set<String>()
            for line in t.split(separator: "\n").map(String.init) where !has(line, ignoredLine) {
                for shape in shapes {
                    guard let regex = try? NSRegularExpression(pattern: shape) else { continue }
                    for m in regex.matches(in: line, range: NSRange(line.startIndex..., in: line)) { if let r = Range(m.range(at: 1), in: line) { printed.insert(String(line[r])) } }
                }
            }
            if !printed.isSubset(of: captured) { strictMiss.append("miss.tail") }
            let figures = Self.printedFigures(t)
            if let b = p.balanceMinor, let a = p.amountMinor, b == a, figures.count > 1 { strictMiss.append("miss.balanceEqualsAmount") }
            if p.balanceMinor != nil, has(t, "ائتمانية"), has(t, #"الإجمالي المستحق|إجمالي المبلغ المستحق"#), has(t, #"الرصيد (المتوفر|المتاح)"#) { strictMiss.append("miss.availableAsBalance") }
            if has(t, #"(?:دفعة\s+قادمة|دفعتك)\s+بقيمة|will\s+be\s+charged"#) { strictMiss.append("miss.reminderRecorded") }
            if p.balanceMinor == nil, has(t, #"(?m)^[^\n]*(الرصيد|رصيد|Balance)\s*:?\s*(SAR\s*)?-\d"#) { strictMiss.append("miss.negativeBalanceDropped") }
        }
        out["strict.total"] = 1
        if strictMiss.isEmpty { out["strict.read"] = 1 } else { for m in strictMiss { out["strict." + m, default: 0] += 1 } }
        // Source/destination account and printed balance are counted apart so the transaction-level number stays comparable.
        var extra: [String] = []
        var extra2: [String] = []
        let noneStatement = p.kind != .statement && p.kind != .declined
        let balancePrinted = noneStatement && has(t, #"(?mi)^[^\n]*(الرصيد|رصيد|المتاح|Avl\.?\s*Bal|Available\s+Balance|Balance)\s*[:：]?\s*-?\d[\d,]*(\.\d+)?"#)
            && !has(t, #"(?mi)^[^\n]*(القائم|الحد المتاح|غير كاف|Insufficient|المستحق)[^\n]*$"#)
        if balancePrinted { out["expect.balance"] = 1 }
        if balancePrinted, p.balanceMinor == nil { extra.append("miss.balance") }
        let debit: [BankMessageKind] = [.purchase, .withdrawal, .transferOut, .cardPayment, .billPayment, .fee, .declined, .reversal]
        let sourcePrinted = debit.contains(p.kind) && (has(t, #"(?mi)^\s*(من|من حساب|من الحساب|From|A/C|حساب|رقم حساب|الحساب)\s*:?\s*\**\s*\d{3,4}\s*\**\s*$"#) || has(t, #"من\s+حسابك\s*\*+\d{3,4}"#))
        if sourcePrinted { out["expect.sourceAccount"] = 1 }
        if sourcePrinted, p.accountLast4 == nil { extra.append("miss.sourceAccount") }
        let destPrinted = p.kind == .transferIn && has(t, #"(?mi)^\s*(الى|إلى|To|إلى حساب|الى حساب|حساب|الحساب)\s*:?\s*\**\s*\d{3,4}\s*\**\s*$"#)
        if destPrinted { out["expect.destAccount"] = 1 }
        if destPrinted, p.accountLast4 == nil { extra.append("miss.destAccount") }
        // Fees, FX and limits (owner scope 11 Nov): counted apart as well.
        let feePrinted = p.kind != .fee && has(t, #"(?mi)^[^\n]*(رسوم العملية|الرسوم|رسوم|Fees?|عمولة)\s*[:：]?\s*(SAR|SR|ر\.س)?\s*\d"#) && !has(t, #"(?mi)^[^\n]*رسوم\s*تحويل\s*العملة"#)
        if feePrinted { out["expect.fee"] = 1; if p.feeMinor == nil { extra2.append("miss.fee") } }
        let limitPrinted = has(t, #"(?mi)(الصرف المتبقي|الحد المتبقي)\s*[:：]?\s*(SAR\s*)?\d"#)
        if limitPrinted { out["expect.remainingLimit"] = 1; if p.remainingLimitMinor == nil { extra2.append("miss.remainingLimit") } }
        let fxPrinted = has(t, #"(سعر الصرف|Exchange Rate)\s*[≈~:]*\s*\d"#)
        if fxPrinted { out["expect.fxRate"] = 1; if p.exchangeRate == nil { extra2.append("miss.fxRate") } }
        if p.kind == .declined { out["expect.declineReason"] = 1; if p.declineReason == .other { extra2.append("other.declineReason") } }
        for m in extra2 { out[m, default: 0] += 1 }
        if miss.isEmpty && extra.isEmpty { out["fullyReadWithSource"] = 1 }
        for m in extra { out[m, default: 0] += 1 }
        return out
    }

    func testLayoutMasksGreetingAndNamedCounterparties() {
        let shape = Self.layout("عزيزي اسم عميل تجريبي،\nاسم المرسل: اسم مرسل تجريبي\nBeneficiary: Example Person\nشراء\nلدى: Example Shop")
        XCTAssertFalse(shape.contains("اسم عميل تجريبي"))
        XCTAssertFalse(shape.contains("اسم مرسل تجريبي"))
        XCTAssertFalse(shape.contains("Example"))
        XCTAssertTrue(shape.contains("‹…›"))
    }

    func testLayoutMasksColonAndInlinePartyValues() {
        let shape = Self.layout("حوالة\nمن:اسم تجريبي\nلـمتجر تجريبي\nلExample Store\nTransfer to Example Person")
        XCTAssertFalse(shape.contains("اسم تجريبي"))
        XCTAssertFalse(shape.contains("متجر تجريبي"))
        XCTAssertFalse(shape.contains("Example"))
    }

    func testGuideKeepsEveryKindForAGroupedLayout() {
        XCTAssertEqual(Self.kindSummary(["unknown": 2, "transferOut": 1]), "unknown×2، transferOut×1")
    }

    func testOwnerCorpusReport() throws {
        let folder = Self.madar.appendingPathComponent("Private/bank-messages")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "jsonl" }), !files.isEmpty else {
            throw XCTSkip("No local bank-message corpus on this machine.")
        }
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        var report: [String: [String: Int]] = [:]
        var accuracy: [String: [String: Int]] = [:]
        // The guide groups masked layouts per sender; keep every observed class because hidden party names can affect parsing.
        var guide: [String: [String: Layout]] = [:]
        for file in files {
            let sender = file.deletingPathExtension().lastPathComponent
            var counts: [String: Int] = [:]
            for raw in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                guard let line = try? JSONDecoder().decode(Line.self, from: Data(raw.utf8)) else { continue }
                let fractional = ISO8601DateFormatter(); fractional.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
                let received = fractional.date(from: line.date) ?? ISO8601DateFormatter().date(from: line.date)
                if received == nil { counts["gap.noReceiveTime", default: 0] += 1 }
                let parsed = BankMessageParser.parse(line.text, timeZone: zone, receivedAt: received, sender: line.sender, trackedWallets: Self.trackedOwnerWallets)
                // A printed time more than two days from the receive time is a misread date.
                if let at = parsed.eventAt, let received, abs(at.timeIntervalSince(received)) > 2 * 86_400 { counts["gap.dateFar", default: 0] += 1 }
                counts["total", default: 0] += 1
                let key = Self.layout(line.text)
                var entry = guide[sender, default: [:]][key, default: Layout()]
                entry.count += 1; entry.kinds[parsed.kind.rawValue, default: 0] += 1
                if BankIntake.decision(parsed.kind) == .record {
                    if parsed.amountMinor == nil { entry.missing.insert("المبلغ") }
                    if parsed.eventAt == nil { entry.missing.insert("الوقت") }
                    if [.purchase, .refund, .declined].contains(parsed.kind) && parsed.merchant == nil { entry.missing.insert("التاجر") }
                    if [.purchase, .withdrawal, .refund, .declined].contains(parsed.kind) && parsed.last4 == nil { entry.missing.insert("البطاقة") }
                    if [.transferIn, .transferOut].contains(parsed.kind) && parsed.counterparty == nil { entry.missing.insert("الطرف") }
                }
                guide[sender, default: [:]][key] = entry
                for (name, value) in Self.accuracyMisses(line.text, parsed, sender: sender) { accuracy[sender, default: [:]][name, default: 0] += value }
                counts["kind." + parsed.kind.rawValue, default: 0] += 1
                let recordable = BankIntake.decision(parsed.kind) == .record
                if recordable { counts["recordable", default: 0] += 1 }
                if recordable && parsed.amountMinor == nil { counts["gap.noAmount", default: 0] += 1 }
                if recordable && parsed.last4 == nil && [.purchase, .withdrawal, .refund, .declined, .reversal].contains(parsed.kind) { counts["gap.noLast4", default: 0] += 1 }
                if parsed.kind == .purchase && parsed.merchant == nil { counts["gap.purchaseNoMerchant", default: 0] += 1 }
                if [.transferOut, .transferIn].contains(parsed.kind) && parsed.counterparty == nil { counts["gap.transferNoParty", default: 0] += 1 }
                if recordable && parsed.eventAt == nil { counts["gap.noTime", default: 0] += 1 }
                if parsed.currency != nil && parsed.currency != "SAR" { counts["foreign", default: 0] += 1 }
            }
            report[sender] = counts
        }
        let out = Self.madar.appendingPathComponent("Artifacts/bank-corpus-report.json")
        try FileManager.default.createDirectory(at: out.deletingLastPathComponent(), withIntermediateDirectories: true)
        // Accuracy: financial senders only (any recordable message); percent is over messages that carry money or are recordable.
        var accSection: [String: Any] = [:]
        var overall: [String: Int] = [:]
        for (sender, counts) in report where (counts["recordable"] ?? 0) > 0 {
            var a = accuracy[sender] ?? [:]
            a["percent×100"] = (a["financialTotal"] ?? 0) == 0 ? 0 : (a["fullyRead"] ?? 0) * 10_000 / a["financialTotal"]!
            a["strict.percent×100"] = (a["strict.total"] ?? 0) == 0 ? 0 : (a["strict.read"] ?? 0) * 10_000 / a["strict.total"]!
            accSection[sender] = a
            for (k, v) in accuracy[sender] ?? [:] { overall[k, default: 0] += v }
        }
        overall["strict.percent×100"] = (overall["strict.total"] ?? 0) == 0 ? 0 : (overall["strict.read"] ?? 0) * 10_000 / overall["strict.total"]!
        overall["percent×100"] = (overall["financialTotal"] ?? 0) == 0 ? 0 : (overall["fullyRead"] ?? 0) * 10_000 / overall["financialTotal"]!
        accSection["_overall"] = overall
        var full: [String: Any] = report
        full["_accuracy"] = accSection
        try JSONSerialization.data(withJSONObject: full, options: [.prettyPrinted, .sortedKeys]).write(to: out)
        var md = "# دليل تحليل رسائل البنوك (محلي)\n\nيُولَّد من `BankCorpusTests` عند كل تشغيل. الأرقام مقنّعة بـ#، وما بعد «من/لدى/لـ/إلى/At» مخفي بـ‹…›.\n"
        for (sender, layouts) in guide.sorted(by: { $0.value.values.map(\.count).reduce(0, +) > $1.value.values.map(\.count).reduce(0, +) }) {
            let total = layouts.values.map(\.count).reduce(0, +)
            md += "\n## \(sender) — \(total) رسالة، \(layouts.count) شكل\n\n| العدد | الأنواع حسب العدد | ينقصه | الشكل |\n|---|---|---|---|\n"
            for (shape, l) in layouts.sorted(by: { $0.value.count > $1.value.count }).prefix(25) {
                md += "| \(l.count) | \(Self.kindSummary(l.kinds)) | \(l.missing.sorted().joined(separator: "، ")) | \(shape.replacingOccurrences(of: "|", with: "/")) |\n"
            }
        }
        try md.write(to: folder.appendingPathComponent("GUIDE.md"), atomically: true, encoding: .utf8)
        XCTAssertFalse(report.isEmpty)
    }
}
