import Foundation
import Testing
@testable import MadarCommands

/// Serialized: the in-flight flag is shared by the whole process, so these checks must not overlap each other.
@Suite(.serialized) struct QuranResourceVerificationTests {
    @Test func bundledFilesAreHashedOncePerBuildNumber() throws {
        let suite = "QuranVerify-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(QuranResourceVerification.needsVerification(build: "0.1.0-26", defaults: defaults), "A first start verifies")
        QuranResourceVerification.recordVerified(build: "0.1.0-26", defaults: defaults)
        #expect(!QuranResourceVerification.needsVerification(build: "0.1.0-26", defaults: defaults), "The second start of the same build does not hash again")
        #expect(QuranResourceVerification.needsVerification(build: "0.1.0-27", defaults: defaults), "A new build verifies again")
    }

    /// Owner, 28 Nov 2026: every update was killed at launch while the catalog hashed 116 MB under the lobby's lock.
    @Test func catalogNeverWaitsOnTheFileCheck() throws {
        let suite = "QuranVerify-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let started = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0), finished = DispatchSemaphore(value: 0)
        let checking = Thread {
            QuranResources.verifyOncePerBuild(build: "0.1.0-78", defaults: defaults) { started.signal(); release.wait() }
            finished.signal()
        }
        checking.start()
        try #require(started.wait(timeout: .now() + 10) == .success, "the check must start")
        // The check is running and blocked: the catalog still opens, and a second check does not start.
        let clock = ContinuousClock(), begin = clock.now
        _ = try QuranResources.catalog()
        #expect(clock.now - begin < .seconds(5))
        #expect(!QuranResources.verifyOncePerBuild(build: "0.1.0-78", defaults: defaults) { Issue.record("a second check ran") })
        release.signal()
        try #require(finished.wait(timeout: .now() + 10) == .success, "the check must finish")
        #expect(!QuranResourceVerification.needsVerification(build: "0.1.0-78", defaults: defaults))
        #expect(!QuranResources.verifyOncePerBuild(build: "0.1.0-78", defaults: defaults) { Issue.record("checked twice for one build") })
    }

    @Test func aFailedCheckIsTriedAgainNextStart() throws {
        let suite = "QuranVerify-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        struct Broken: Error {}
        #expect(!QuranResources.verifyOncePerBuild(build: "0.1.0-78", defaults: defaults) { throw Broken() })
        #expect(QuranResourceVerification.needsVerification(build: "0.1.0-78", defaults: defaults))
    }
}
