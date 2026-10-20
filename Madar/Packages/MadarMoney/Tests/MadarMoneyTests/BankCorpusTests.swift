import Foundation
import XCTest
@testable import MadarMoney

/// RM6: the owner's real bank messages, kept only on this Mac in Madar/Private/bank-messages (git-ignored).
/// Skipped when the folder is absent. Writes aggregate counts only to Madar/Artifacts/bank-corpus-report.json and redacted layouts to the git-ignored local guide.
final class BankCorpusTests: XCTestCase {
    private struct Line: Decodable { let sender: String; let date: String; let text: String }
    private static let madar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    /// Owner-confirmed institutions represented as tracked accounts in this parser-only corpus pass.
    private static let trackedOwnerWallets = ["Barq", "STC Pay", "STC Bank", "Tiqmo", "Drahim", "D360", "Tweeq", "urpay", "Alinma Investment", "Sukuk"]

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

    func testOwnerCorpusReport() throws {
        let folder = Self.madar.appendingPathComponent("Private/bank-messages")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "jsonl" }), !files.isEmpty else {
            throw XCTSkip("No local bank-message corpus on this machine.")
        }
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        var report: [String: [String: Int]] = [:]
        // The analysis guide: every layout per sender, with what Madar reads from it. Local only (Private/ is git-ignored).
        struct Layout { var count = 0; var kind = ""; var missing = Set<String>() }
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
                entry.count += 1; entry.kind = parsed.kind.rawValue
                if BankIntake.decision(parsed.kind) == .record {
                    if parsed.amountMinor == nil { entry.missing.insert("المبلغ") }
                    if parsed.eventAt == nil { entry.missing.insert("الوقت") }
                    if [.purchase, .refund, .declined].contains(parsed.kind) && parsed.merchant == nil { entry.missing.insert("التاجر") }
                    if [.purchase, .withdrawal, .refund, .declined].contains(parsed.kind) && parsed.last4 == nil { entry.missing.insert("البطاقة") }
                    if [.transferIn, .transferOut].contains(parsed.kind) && parsed.counterparty == nil { entry.missing.insert("الطرف") }
                }
                guide[sender, default: [:]][key] = entry
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
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(report).write(to: out)
        var md = "# دليل تحليل رسائل البنوك (محلي)\n\nيُولَّد من `BankCorpusTests` عند كل تشغيل. الأرقام مقنّعة بـ#، وما بعد «من/لدى/لـ/إلى/At» مخفي بـ‹…›.\n"
        for (sender, layouts) in guide.sorted(by: { $0.value.values.map(\.count).reduce(0, +) > $1.value.values.map(\.count).reduce(0, +) }) {
            let total = layouts.values.map(\.count).reduce(0, +)
            md += "\n## \(sender) — \(total) رسالة، \(layouts.count) شكل\n\n| العدد | النوع | ينقصه | الشكل |\n|---|---|---|---|\n"
            for (shape, l) in layouts.sorted(by: { $0.value.count > $1.value.count }).prefix(25) {
                md += "| \(l.count) | \(l.kind) | \(l.missing.sorted().joined(separator: "، ")) | \(shape.replacingOccurrences(of: "|", with: "/")) |\n"
            }
        }
        try md.write(to: folder.appendingPathComponent("GUIDE.md"), atomically: true, encoding: .utf8)
        XCTAssertFalse(report.isEmpty)
    }
}
