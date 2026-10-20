import Testing
@testable import MadarMoney

struct SalarySourceMatcherTests {
    @Test func sourceMatchingIsExactNormalizedAndRequiresAName() {
        let learned: Set<String> = ["شركة المدار"]
        #expect(SalarySourceMatcher.key("  شركة   المدار ") == "شركة المدار")
        #expect(SalarySourceMatcher.matches("شركة المدار", learnedKeys: learned))
        #expect(!SalarySourceMatcher.matches("شركة مدار", learnedKeys: learned))
        #expect(!SalarySourceMatcher.matches("5512", learnedKeys: learned))
        #expect(!SalarySourceMatcher.matches(nil, learnedKeys: learned))
    }
}
