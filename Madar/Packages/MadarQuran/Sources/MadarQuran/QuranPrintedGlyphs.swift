import Foundation

public struct QuranPrintedGlyphs: Decodable, Sendable {
    public struct Entry: Decodable, Sendable {
        public let ayahID: Int
        public let wordIndex: Int?
        public let line: Int
        public let glyphs: String
    }
    public struct Page: Decodable, Sendable {
        public let page: Int
        public let fontName: String
        public let entries: [Entry]
    }
    public let version: Int
    public let edition: Int
    public let pages: [Page]
    public static func bundled() throws -> Self {
        let manifest = try QuranResourceManifest.bundled()
        let value = try JSONDecoder().decode(Self.self, from: manifest.verifiedData(at: "Quran1439/printed-glyphs.json"))
        guard value.version == 1, value.edition == 1439, value.pages.map(\.page) == Array(1...604) else { throw QuranResourceCatalogError.invalidManifest }
        return value
    }
    public static func fontURL(page: Int) throws -> URL {
        let path = "Quran1439/Fonts/\(page).woff2"
        _ = try QuranResourceManifest.bundled().verifiedData(at: path)
        guard let root = Bundle.module.resourceURL else { throw QuranResourceCatalogError.missingResource(path) }
        return root.appendingPathComponent(path)
    }
}
