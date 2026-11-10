import Foundation
import Testing
@testable import MadarCommands

struct QuranResourceVerificationTests {
    @Test func bundledFilesAreHashedOncePerBuildNumber() throws {
        let suite = "QuranVerify-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(QuranResourceVerification.needsVerification(build: "0.1.0-26", defaults: defaults), "A first start verifies")
        QuranResourceVerification.recordVerified(build: "0.1.0-26", defaults: defaults)
        #expect(!QuranResourceVerification.needsVerification(build: "0.1.0-26", defaults: defaults), "The second start of the same build does not hash again")
        #expect(QuranResourceVerification.needsVerification(build: "0.1.0-27", defaults: defaults), "A new build verifies again")
    }
}
