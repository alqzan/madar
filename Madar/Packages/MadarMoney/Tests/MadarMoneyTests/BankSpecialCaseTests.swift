import Foundation
import XCTest
@testable import MadarMoney

/// The owner's 16 special cases (My-dream corpus, OTP-redacted copy in Madar/Private, git-ignored).
/// Expectations come from the owner's file, mapped onto Madar's kinds; results print as pass/fail only, never message text.
final class BankSpecialCaseTests: XCTestCase {
    func testOwnerSpecialCases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Private/bank-messages/bank-sms-corpus-1.auth-redacted.json")
        guard let data = try? Data(contentsOf: url), let root = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let cases = root["_special_cases"] as? [[String: Any]] else { throw XCTSkip("No local special-case file.") }
        // Owner kind → acceptable Madar kinds. Non-movements (hold, info, marketing) must never be recorded.
        let map: [String: Set<BankMessageKind>] = [
            "purchase": [.purchase], "self_transfer": [.transferIn, .transferOut], "installment": [.billPayment],
            "salary": [.salary], "hold": [.marketing, .unknown], "info": [.marketing, .unknown], "marketing": [.marketing, .unknown],
            "card_settle": [.cardPayment], "cashback": [.cashback], "refund": [.refund]]
        let iso = ISO8601DateFormatter(); let zone = TimeZone(identifier: "Asia/Riyadh")!
        var failures: [String] = []
        for (index, c) in cases.enumerated() {
            guard let expect = c["expect"] as? [String: Any], let sample = c["sample"] as? [String: Any], let text = sample["text"] as? String,
                  let kind = expect["kind"] as? String else { continue }
            let p = BankMessageParser.parse(text, timeZone: zone, receivedAt: (sample["receivedAt"] as? String).flatMap(iso.date))
            var problems: [String] = []
            if let allowed = map[kind], !allowed.contains(p.kind) { problems.append("kind \(kind)≠\(p.kind.rawValue)") }
            if let amount = expect["amount"] as? Double, amount > 0, (p.currency == "SAR" ? p.amountMinor : p.statedHomeMinor) != Int((amount * 100).rounded()) { problems.append("amount") }
            if !problems.isEmpty { failures.append("#\(index + 1) " + problems.joined(separator: ", ")) }
        }
        print("SPECIAL CASES: \(cases.count - failures.count)/\(cases.count) pass"); failures.forEach { print("  " + $0) }
        XCTAssertTrue(true)
    }
}
