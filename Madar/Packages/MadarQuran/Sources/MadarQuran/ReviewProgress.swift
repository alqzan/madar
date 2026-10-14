import Foundation

public struct QuranReviewSection: Codable, Equatable, Sendable {
    public enum Kind: String, Codable, Sendable { case recent, due, mixed, test }
    public var kind: Kind
    public var pages: [Int]
    public var title: String { switch kind { case .recent: "القريب"; case .due: "المستحق"; case .mixed: "القريب والمستحق"; case .test: "اختبار القديم" } }
    public init(kind: Kind, pages: [Int]) { self.kind = kind; self.pages = pages }
    /// Preserve the engine's risk order; adjacent regular pages merge, while the final test stays separate.
    public static func make(regular: [Int], recent: Set<Int>, partialRecent: [Int], tests: [Int]) -> [Self] {
        let testSet = Set(tests)
        var seen = Set<Int>(), result: [Self] = []
        let ordered = (regular.filter { recent.contains($0) } + partialRecent).sorted().map { ($0, Kind.recent) }
            + regular.filter { !recent.contains($0) }.map { ($0, Kind.due) }
            + tests.map { ($0, Kind.test) }
        for (page, kind) in ordered where (kind == .test || !testSet.contains(page)) && seen.insert(page).inserted {
            if let last = result.last, (last.kind == kind || (last.kind != .test && kind != .test)), last.pages.last == page - 1 {
                result[result.count - 1].pages.append(page)
                if last.kind != kind { result[result.count - 1].kind = .mixed }
            } else { result.append(Self(kind: kind, pages: [page])) }
        }
        return result
    }
}
