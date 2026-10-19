import Foundation
import XCTest
@testable import MadarMoney

/// RM6: the owner's real bank messages, kept only on this Mac in Madar/Private/bank-messages (git-ignored).
/// Skipped when the folder is absent. Writes counts only, never message text, to Madar/Artifacts/bank-corpus-report.json.
final class BankCorpusTests: XCTestCase {
    private struct Line: Decodable { let sender: String; let date: String; let text: String }
    private static let madar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    func testOwnerCorpusReport() throws {
        let folder = Self.madar.appendingPathComponent("Private/bank-messages")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "jsonl" }), !files.isEmpty else {
            throw XCTSkip("No local bank-message corpus on this machine.")
        }
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        var report: [String: [String: Int]] = [:]
        for file in files {
            let sender = file.deletingPathExtension().lastPathComponent
            var counts: [String: Int] = [:]
            for raw in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                guard let line = try? JSONDecoder().decode(Line.self, from: Data(raw.utf8)) else { continue }
                let parsed = BankMessageParser.parse(line.text, timeZone: zone)
                counts["total", default: 0] += 1
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
        XCTAssertFalse(report.isEmpty)
    }
}
