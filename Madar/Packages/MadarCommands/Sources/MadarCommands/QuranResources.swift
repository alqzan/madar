import Foundation
import MadarQuran

/// B1-5: hashing every bundled Quran file (~116 MB) on each cold start cost battery for no gain, because the files ship inside the
/// signed app. They are verified once per build number; a new build verifies again.
public enum QuranResourceVerification {
    static let key = "quran.resources.verifiedBuild"
    public static func needsVerification(build: String, defaults: UserDefaults = .standard) -> Bool { defaults.string(forKey: key) != build }
    public static func recordVerified(build: String, defaults: UserDefaults = .standard) { defaults.set(build, forKey: key) }
    static var currentBuild: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "0")-\(info?["CFBundleVersion"] as? String ?? "0")"
    }
}

/// The verified catalog is read once and shared; any thread may ask for it, so habit readings can run off the main thread (FB-38).
public enum QuranResources {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var verified: QuranResourceCatalog?
    public static func catalog() throws -> QuranResourceCatalog {
        lock.lock(); defer { lock.unlock() }
        if let verified { return verified }
        let build = QuranResourceVerification.currentBuild
        let verify = QuranResourceVerification.needsVerification(build: build)
        let catalog = try QuranResourceCatalog.bundled(verifyFiles: verify)
        if verify { QuranResourceVerification.recordVerified(build: build) }
        verified = catalog
        return catalog
    }
}
