import Foundation
import MadarData
import MadarMoney

/// Merchant rules looked up by `MerchantKey`, built once per command instead of scanning the table per message. Rules stored before
/// the key existed (pattern = the plain normalized name) match too, because their pattern is keyed the same way.
struct MerchantRuleIndex {
    private let byKey: [String: MerchantRule]
    init(rules: [MerchantRule]) {
        var map: [String: MerchantRule] = [:]
        for rule in rules {
            let key = MerchantKey.key(rule.pattern)
            guard !key.isEmpty else { continue }
            if let old = map[key], old.updatedAt >= rule.updatedAt { continue }
            map[key] = rule
        }
        byKey = map
    }
    func rule(for merchant: String?) -> MerchantRule? {
        let key = MerchantKey.key(merchant)
        return key.isEmpty ? nil : byKey[key]
    }
}
