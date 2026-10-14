import MadarQuran

@MainActor public enum QuranResources {
    private static var verified: QuranResourceCatalog?
    public static func catalog() throws -> QuranResourceCatalog {
        if let verified { return verified }
        let catalog = try QuranResourceCatalog.bundled()
        verified = catalog
        return catalog
    }
}
