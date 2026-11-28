import Foundation
import MadarQuran

/// B1-5: hashing every bundled Quran file (~116 MB) on each cold start cost battery for no gain, because the files ship inside the
/// signed app. They are verified once per build number; a new build verifies again.
public enum QuranResourceVerification {
    static let key = "quran.resources.verifiedBuild"
    public static func needsVerification(build: String, defaults: UserDefaults = .standard) -> Bool { defaults.string(forKey: key) != build }
    public static func recordVerified(build: String, defaults: UserDefaults = .standard) { defaults.set(build, forKey: key) }
    public static var currentBuild: String {
        let info = Bundle.main.infoDictionary
        return "\(info?["CFBundleShortVersionString"] as? String ?? "0")-\(info?["CFBundleVersion"] as? String ?? "0")"
    }
}

/// The catalog is read once and shared; any thread may ask for it, so habit readings can run off the main thread (FB-38).
///
/// Owner, 28 Nov 2026: «إذا حدثت التطبيق ما يفتح معي… كل تحديث». Hashing the ~116 MB of bundled Quran files used to happen
/// inside `catalog()` on the first start of every new build, under the same lock the lobby's habit tile waits on from the main
/// thread. On the iPhone that took longer than the launch watchdog allows, so every update was killed at launch (0x8BADF00D,
/// crash logs of build 77 on 27 and 28 Nov); the owner had to swipe Madar away and open it again after each update. The catalog
/// now opens without hashing (the files ship inside the signed app); the per-build check runs apart, at background priority,
/// holding no lock any screen can wait on.
public enum QuranResources {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var loaded: QuranResourceCatalog?
    private static let verifyLock = NSLock()
    nonisolated(unsafe) private static var verifying = false

    public static func catalog() throws -> QuranResourceCatalog {
        lock.lock(); defer { lock.unlock() }
        if let loaded { return loaded }
        let catalog = try QuranResourceCatalog.bundled(verifyFiles: false)
        loaded = catalog
        return catalog
    }

    /// Hashes the bundled files once per build number, off every screen's path. Call it from a background task only.
    /// Returns whether the files were checked now (false when this build was already checked or another check is running).
    @discardableResult
    public static func verifyOncePerBuild(build: String = QuranResourceVerification.currentBuild, defaults: UserDefaults = .standard,
                                          verify: () throws -> Void = { try QuranResourceManifest.bundled().verifyFiles() }) -> Bool {
        verifyLock.lock()
        guard !verifying, QuranResourceVerification.needsVerification(build: build, defaults: defaults) else { verifyLock.unlock(); return false }
        verifying = true
        verifyLock.unlock()
        defer { verifyLock.lock(); verifying = false; verifyLock.unlock() }
        guard (try? verify()) != nil else { return false }
        QuranResourceVerification.recordVerified(build: build, defaults: defaults)
        return true
    }
}
