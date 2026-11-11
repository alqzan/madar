import Foundation

/// A transaction's explicit manual category choice is the only evidence used to learn a merchant preference.
/// The result is a suggestion; the caller keeps every purchase editable.
public enum MerchantCategoryLearning {
    public struct Sample: Equatable, Sendable {
        public let transactionID: UUID
        public let merchant: String?
        public let categoryID: UUID?
        public let categorySource: String?
        public let kind: String
        public let reviewState: String
        public let isDeleted: Bool
        public let isMerged: Bool

        public init(transactionID: UUID, merchant: String?, categoryID: UUID?, categorySource: String?,
                    kind: String, reviewState: String, isDeleted: Bool = false, isMerged: Bool = false) {
            self.transactionID = transactionID
            self.merchant = merchant
            self.categoryID = categoryID
            self.categorySource = categorySource
            self.kind = kind
            self.reviewState = reviewState
            self.isDeleted = isDeleted
            self.isMerged = isMerged
        }
    }

    public struct CategoryCount: Equatable, Sendable {
        public let categoryID: UUID
        public let count: Int
    }

    public struct Result: Equatable, Sendable {
        public let counts: [CategoryCount]
        /// Set only when exactly one live category has reached the requested threshold.
        public let suggestedCategoryID: UUID?
        public var hasMultipleQualifiedCategories: Bool { counts.filter { $0.count >= threshold }.count > 1 }
        fileprivate let threshold: Int
    }

    /// A precomputed, normalized lookup keeps suggestions available for typed merchants too, without rescanning every
    /// historical transaction on each keystroke or limiting learning to the visible recent-merchant chips.
    public struct Index: Sendable {
        private let countsByMerchant: [String: [CategoryCount]]

        fileprivate init(countsByMerchant: [String: [CategoryCount]]) {
            self.countsByMerchant = countsByMerchant
        }

        public func result(for merchant: String, threshold: Int) -> Result {
            let key = MerchantKey.key(merchant)
            guard threshold > 0, !key.isEmpty, let counts = countsByMerchant[key] else {
                return .init(counts: [], suggestedCategoryID: nil, threshold: threshold)
            }
            let qualified = counts.filter { $0.count >= threshold }
            return .init(counts: counts, suggestedCategoryID: qualified.count == 1 ? qualified[0].categoryID : nil,
                         threshold: threshold)
        }

        public static let empty = Index(countsByMerchant: [:])
    }

    public static func makeIndex(samples: [Sample], liveCategoryIDs: Set<UUID>) -> Index {
        var seenByMerchant: [String: Set<UUID>] = [:]
        var countsByMerchant: [String: [UUID: Int]] = [:]

        for sample in samples {
            guard !sample.isDeleted, !sample.isMerged,
                  sample.kind == "expense", sample.reviewState == "ok",
                  sample.categorySource == "manual",
                  let categoryID = sample.categoryID, liveCategoryIDs.contains(categoryID),
                  let merchant = sample.merchant else { continue }
            let key = MerchantKey.key(merchant)
            guard !key.isEmpty, seenByMerchant[key, default: []].insert(sample.transactionID).inserted else { continue }
            countsByMerchant[key, default: [:]][categoryID, default: 0] += 1
        }

        let normalizedCounts = countsByMerchant.mapValues { counts in
            counts.map { CategoryCount(categoryID: $0.key, count: $0.value) }
                .sorted { left, right in
                    if left.count != right.count { return left.count > right.count }
                    return left.categoryID.uuidString < right.categoryID.uuidString
                }
        }
        return Index(countsByMerchant: normalizedCounts)
    }

    public static func evaluate(merchant: String, samples: [Sample], threshold: Int,
                                liveCategoryIDs: Set<UUID>) -> Result {
        makeIndex(samples: samples, liveCategoryIDs: liveCategoryIDs).result(for: merchant, threshold: threshold)
    }
}
