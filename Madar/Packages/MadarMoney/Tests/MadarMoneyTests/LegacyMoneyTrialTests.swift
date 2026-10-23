import Foundation
import XCTest
@testable import MadarMoney

/// Owner data trial (22 Oct): the old app's backup stays only on this Mac in Madar/Artifacts/owner-data (git-ignored).
/// Re-parses every stored bank message with today's parser and compares it with what the old app recorded.
/// Skipped when the backup is absent. Writes counts to the same ignored folder; masked layouts of disagreements go
/// to a local-only file next to it. Nothing here enters Git, the board or a helper agent.
final class LegacyMoneyTrialTests: XCTestCase {
    private static let ownerData = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        .deletingLastPathComponent().deletingLastPathComponent().appendingPathComponent("Artifacts/owner-data")

    private struct Backup: Decodable { let transactions: [Row]; let inboxEvents: [Row] }
    private struct Row: Decodable {
        let date: String?; let time: String?; let amount: Double?; let originalAmount: Double?
        let cardLast4: String?; let counterparty: String?; let rawText: String?; let bank: String?; let reviewReason: String?
    }

    static func minor(_ value: Double?) -> Int? {
        guard let value else { return nil }
        // Through Decimal: 12.3 must give 1230, never 1229.
        let scaled = (Decimal(string: String(value)) ?? Decimal(value)) * 100
        return NSDecimalNumber(decimal: scaled).intValue
    }
    static func squash(_ s: String?) -> String? {
        guard let s else { return nil }
        let t = s.split(whereSeparator: \.isWhitespace).joined(separator: " ").lowercased()
        return t.isEmpty ? nil : t
    }

    /// The word that introduces each occurrence of these four digits («بطاقة» or «حساب»), on its own line.
    static func labels(_ last4: String, in text: String) -> Set<String> {
        Set(text.split(separator: "\n").compactMap { line in
            guard line.contains(last4) else { return nil }
            return ["بطاقة", "حساب"].first { line.contains($0) }
        })
    }

    func testMinorUnitsGoThroughDecimal() {
        XCTAssertEqual(Self.minor(12.3), 1230); XCTAssertEqual(Self.minor(0.07), 7); XCTAssertEqual(Self.minor(19.99), 1999); XCTAssertEqual(Self.minor(45), 4500)
    }

    func testOwnerLegacyMoneyReparse() throws {
        guard let file = try? FileManager.default.contentsOfDirectory(at: Self.ownerData, includingPropertiesForKeys: nil)
            .filter({ $0.lastPathComponent.hasPrefix("madar-backup-") && $0.pathExtension == "json" }).sorted(by: { $0.lastPathComponent < $1.lastPathComponent }).last else {
            throw XCTSkip("No owner backup on this machine.")
        }
        let backup = try JSONDecoder().decode(Backup.self, from: Data(contentsOf: file))
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        let stamp = DateFormatter(); stamp.locale = Locale(identifier: "en_US_POSIX"); stamp.timeZone = zone; stamp.dateFormat = "yyyy-MM-dd HH:mm"
        var counts: [String: Int] = [:]
        var diffs: [String: [String]] = [:]
        func note(_ key: String, _ text: String) { counts[key, default: 0] += 1; diffs[key, default: []].append(BankCorpusTests.layout(text)) }

        for row in backup.transactions {
            guard let text = row.rawText, !text.isEmpty else { counts["noText"] = (counts["noText"] ?? 0) + 1; continue }
            counts["messages", default: 0] += 1
            let received = row.date.flatMap { d in stamp.date(from: d + " " + (row.time ?? "12:00")) }
            let p = BankMessageParser.parse(text, timeZone: zone, receivedAt: received, sender: row.bank ?? "", trackedWallets: [])
            counts["kind." + p.kind.rawValue, default: 0] += 1
            if p.kind != .purchase { note("differ.kind", text) }
            // The old app kept the charged amount; a foreign purchase also has its original currency amount.
            let old = Self.minor(row.amount), original = Self.minor(row.originalAmount)
            if p.amountMinor == nil { note("missing.amount", text) }
            else if p.amountMinor == original || p.amountMinor == old || p.statedHomeMinor == old { counts["match.amount", default: 0] += 1 }
            else { note("differ.amount", text) }
            if let want = row.cardLast4, !want.isEmpty {
                if p.last4 == nil { note("missing.last4", text) } else if p.last4 == want { counts["match.last4", default: 0] += 1 }
                else if let got = p.last4, Self.labels(got, in: text).contains("بطاقة"), Self.labels(want, in: text) == ["حساب"] {
                    // The old app took the funding account's digits; a card purchase belongs to the card.
                    counts["differ.last4.madarCardOldAccount", default: 0] += 1
                } else { note("differ.last4", text) }
            } else if p.last4 != nil { counts["extra.last4", default: 0] += 1 }
            if let want = Self.squash(row.counterparty) {
                let got = Self.squash(p.merchant ?? p.counterparty ?? p.biller ?? p.provider)
                if got == nil { note("missing.merchant", text) }
                else if got == want || got!.contains(want) || want.contains(got!) { counts["match.merchant", default: 0] += 1 }
                else { note("differ.merchant", text) }
            }
            if let at = p.eventAt, let d = row.date, let t = row.time {
                let printed = stamp.string(from: at)
                if printed == d + " " + t { counts["match.time", default: 0] += 1 }
                else if printed.hasPrefix(d) { note("differ.timeSameDay", text) }
                else { note("differ.date", text) }
            } else { note("missing.time", text) }
            if BankIntake.decision(p.kind) != .record { note("notRecorded", text) }
        }
        for row in backup.inboxEvents {
            guard let text = row.rawText, !text.isEmpty else { continue }
            let p = BankMessageParser.parse(text, timeZone: zone, receivedAt: nil, sender: row.bank ?? "", trackedWallets: [])
            counts["inbox.kind." + p.kind.rawValue, default: 0] += 1
            counts[p.amountMinor == nil ? "inbox.noAmount" : "inbox.amount", default: 0] += 1
            // The old app flagged some events as having no trusted amount; record what the parser does with those.
            if row.reviewReason != nil { counts["inbox.oldFlagged." + p.kind.rawValue + (p.amountMinor == nil ? ".noAmount" : ".amount"), default: 0] += 1 }
            if p.amountMinor == nil { diffs["inbox.noAmount." + p.kind.rawValue, default: []].append(BankCorpusTests.layout(text)) }
        }

        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(counts).write(to: Self.ownerData.appendingPathComponent("money-trial-report.json"))
        var md = "# فروق إعادة تحليل رسائل المال القديمة (محلي، مقنّع)\n"
        for (key, shapes) in diffs.sorted(by: { $0.key < $1.key }) {
            md += "\n## \(key) — \(shapes.count)\n\n"
            for (shape, n) in Dictionary(shapes.map { ($0, 1) }, uniquingKeysWith: +).sorted(by: { $0.value > $1.value }) { md += "- \(n) × `\(shape.replacingOccurrences(of: "\n", with: " ⏎ "))`\n" }
        }
        try md.write(to: Self.ownerData.appendingPathComponent("money-trial-diffs.md"), atomically: true, encoding: .utf8)
        XCTAssertGreaterThan(counts["messages"] ?? 0, 0)
    }
}
