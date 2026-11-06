import Foundation
import MadarQuran

/// The verified catalog is read once and shared; any thread may ask for it, so habit readings can run off the main thread (FB-38).
public enum QuranResources {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var verified: QuranResourceCatalog?
    public static func catalog() throws -> QuranResourceCatalog {
        lock.lock(); defer { lock.unlock() }
        if let verified { return verified }
        let catalog = try QuranResourceCatalog.bundled()
        verified = catalog
        return catalog
    }
}
