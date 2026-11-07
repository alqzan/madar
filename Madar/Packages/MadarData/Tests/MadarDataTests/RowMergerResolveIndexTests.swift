import Foundation
import Testing
@testable import MadarData

/// The launch merge (owner 7 Nov 2026: «أول ما أفتح التطبيق يعلق») now looks rows up through an index. The expected answers are the
/// original linear `resolve`, which these tests keep as the reference, over chains, duplicates of one id, cycles, missing and broken links.
@Suite @MainActor struct RowMergerResolveIndexTests {
    private static let pool = (0..<12).map { UUID(uuidString: String(format: "00000000-0000-4000-8000-%012d", $0))! }

    private static func row(_ model: String, _ id: UUID, mergedInto: JSONValue?) -> DataRecord {
        var fields: [String: JSONValue] = ["id": .string(id.uuidString)]
        if let mergedInto { fields["mergedInto"] = mergedInto }
        return DataRecord(model: model, fields: fields)
    }

    @Test func indexedResolveMatchesTheLinearReferenceOnHandBuiltChains() {
        let p = Self.pool
        let rows = [
            Self.row("Habit", p[0], mergedInto: .string(p[1].uuidString)),   // 0 → 1 → 2
            Self.row("Habit", p[1], mergedInto: .string(p[2].uuidString)),
            Self.row("Habit", p[2], mergedInto: .null),
            Self.row("Habit", p[3], mergedInto: .string(p[4].uuidString)),   // cycle 3 ↔ 4
            Self.row("Habit", p[4], mergedInto: .string(p[3].uuidString)),
            Self.row("Habit", p[5], mergedInto: .string(p[6].uuidString)),   // two versions of 5: the unmerged one wins
            Self.row("Habit", p[5], mergedInto: .null),
            Self.row("Habit", p[7], mergedInto: .string("not-a-uuid")),      // broken link stops
            Self.row("Habit", p[8], mergedInto: nil),                        // no field at all
            Self.row("Account", p[0], mergedInto: .string(p[9].uuidString)), // same id, other model: never mixed
        ]
        let index = RowMerger.ResolveIndex(rows)
        for model in ["Habit", "Account", "Missing"] {
            for id in p {
                #expect(RowMerger.resolve(id: id, model: model, rows: rows, index: index) == RowMerger.resolve(id: id, model: model, rows: rows), "\(model) \(id)")
            }
        }
        #expect(RowMerger.resolve(id: p[0], model: "Habit", rows: rows, index: index) == p[2])
        #expect(RowMerger.resolve(id: p[5], model: "Habit", rows: rows, index: index) == p[5])
    }

    @Test func indexedResolveMatchesTheLinearReferenceOnRandomStores() {
        var generator = SystemRandomNumberGenerator()
        for _ in 0..<300 {
            let count = Int.random(in: 0...40, using: &generator)
            let rows = (0..<count).map { _ -> DataRecord in
                let model = ["Habit", "Entry"].randomElement(using: &generator)!
                let id = Self.pool.randomElement(using: &generator)!
                let link: JSONValue? = switch Int.random(in: 0..<5, using: &generator) {
                case 0: nil
                case 1, 2: .null
                case 3: .string(Self.pool.randomElement(using: &generator)!.uuidString)
                default: .string("broken")
                }
                return Self.row(model, id, mergedInto: link)
            }
            let index = RowMerger.ResolveIndex(rows)
            for model in ["Habit", "Entry"] {
                for id in Self.pool {
                    #expect(RowMerger.resolve(id: id, model: model, rows: rows, index: index) == RowMerger.resolve(id: id, model: model, rows: rows))
                }
            }
        }
    }
}
