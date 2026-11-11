import Foundation
import XCTest
@testable import MadarMoney

/// D3 (owner, 11 Nov 2026): the merchant rule checked against the owner's real messages, locally and read-only. Skipped when the
/// git-ignored corpus is absent. Prints counts only: never a merchant name, an amount or message text. A second word is named only when
/// it is in the fixed candidate list below; any other second word is counted as «other».
final class MerchantKeyCorpusTests: XCTestCase {
    private struct Line: Decodable { let sender: String; let date: String; let text: String }
    private static let madar = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    private static let brands = ["uber", "careem", "amazon", "اوبر", "كريم", "امازون", "أوبر", "أمازون"]
    private static let candidates: Set<String> = ["eats", "food", "pay", "prime", "web", "aws", "trip", "ride", "rides", "mktp", "marketplace",
        "sa", "ksa", "retail", "services", "help", "bv", "eu", "video", "music", "now", "plus", "quik", "box", "ايتس", "فود", "باي", "برايم"]

    func testMerchantRuleAgainstOwnerCorpus() throws {
        let folder = Self.madar.appendingPathComponent("Private/bank-messages")
        guard let files = try? FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil).filter({ $0.pathExtension == "jsonl" }), !files.isEmpty else {
            throw XCTSkip("No local bank-message corpus on this machine.")
        }
        let zone = TimeZone(identifier: "Asia/Riyadh")!
        var second: [String: [String: Int]] = [:]
        var brandKeys: [String: [String: Int]] = [:]   // brand → (key kind → count): «brand» when it kept the brand key, else «split»
        var merchants = Set<String>()
        var instalments: [String: [Int]] = [:]
        for file in files {
            for raw in try String(contentsOf: file, encoding: .utf8).split(separator: "\n") {
                guard let line = try? JSONDecoder().decode(Line.self, from: Data(raw.utf8)) else { continue }
                let parsed = BankMessageParser.parse(line.text, timeZone: zone, receivedAt: nil, sender: line.sender)
                if parsed.provider != nil, let count = parsed.instalmentCount, let amount = parsed.amountMinor ?? parsed.statementDueMinor {
                    instalments[(parsed.provider ?? "") + "|" + MerchantKey.key(parsed.merchant) + "|\(count)", default: []].append(amount)
                }
                guard let name = parsed.merchant ?? parsed.counterparty else { continue }
                merchants.insert(name)
            }
        }
        for name in merchants {
            let words = name.lowercased().split { !$0.isLetter }.map(String.init)
            guard let first = words.first, Self.brands.contains(first) else { continue }
            let next = words.count > 1 ? (Self.candidates.contains(words[1]) ? words[1] : "other") : "(none)"
            second[first, default: [:]][next, default: 0] += 1
            let brandKey = MerchantKey.key(first)
            brandKeys[first, default: [:]][MerchantKey.key(name) == brandKey ? "brand" : "split:" + next, default: 0] += 1
        }
        // Instalment amounts inside one (provider, merchant, printed count): equal, within count-1 minor units, or further apart.
        var spread = ["equal": 0, "rounding": 0, "apart": 0]
        for (key, amounts) in instalments {
            let count = Int(key.split(separator: "|").last ?? "1") ?? 1
            guard let low = amounts.min(), let high = amounts.max() else { continue }
            spread[high == low ? "equal" : high - low < count ? "rounding" : "apart", default: 0] += 1
        }
        print("MERCHANT-CORPUS distinctNames=\(merchants.count) distinctKeys=\(Set(merchants.map(MerchantKey.key)).count)")
        for brand in second.keys.sorted() { print("MERCHANT-CORPUS brand=\(brand) second=\(second[brand]!.sorted { $0.key < $1.key }) keys=\(brandKeys[brand]!.sorted { $0.key < $1.key })") }
        print("MERCHANT-CORPUS instalmentGroups=\(instalments.count) spread=\(spread.sorted { $0.key < $1.key })")
    }
}
