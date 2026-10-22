import Foundation
import Testing
@testable import MadarCommands

/// Spine text is small, so every text colour keeps the 4.5:1 rule for text under 24 pt.
struct BookBindingsTests {
    @Test func twentyDistinctBindings() {
        #expect(BookBindings.all.count == 20)
        #expect(Set(BookBindings.all.map(\.name)).count == 20)
        #expect(Set(BookBindings.all.map(\.base)).count == 20)
    }

    @Test(arguments: BookBindings.all)
    func textIsReadableOnEveryBinding(_ binding: BookBindings.Binding) {
        #expect(BookBindings.contrast(binding.ink, binding.base) >= 4.5, "\(binding.name): ink on base")
        #expect(BookBindings.contrast(binding.ink, binding.shade) >= 4.5, "\(binding.name): ink on shade")
        #expect(BookBindings.contrast(binding.accentInk, binding.accent) >= 4.5, "\(binding.name): ink on accent")
    }

    @Test func contrastMatchesTheWCAGReference() {
        #expect(abs(BookBindings.contrast(0x000000, 0xFFFFFF) - 21) < 0.001)
        #expect(abs(BookBindings.contrast(0x777777, 0xFFFFFF) - 4.48) < 0.01)
    }

    @Test func neighboursNeverShareABinding() {
        let ids = (0..<200).map { _ in UUID() }
        let map = BookBindings.indices(for: ids)
        for (a, b) in zip(ids, ids.dropFirst()) { #expect(map[a] != map[b]) }
    }
}
