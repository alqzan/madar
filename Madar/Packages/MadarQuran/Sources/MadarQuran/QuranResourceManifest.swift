import CryptoKit
import Foundation

public struct QuranResourceManifest: Decodable, Sendable {
    public struct File: Decodable, Sendable {
        public let path: String
        public let sha256: String
        public let edition: Int
        public let role: String
    }

    public let version: Int
    public let files: [File]

    public static func bundled() throws -> Self {
        guard let url = Bundle.module.url(forResource: "QuranResourceManifest", withExtension: "json") else {
            throw QuranResourceCatalogError.missingResource("QuranResourceManifest.json")
        }
        let manifest = try JSONDecoder().decode(Self.self, from: Data(contentsOf: url))
        guard manifest.version == 1, !manifest.files.isEmpty,
              Set(manifest.files.map(\.path)).count == manifest.files.count,
              manifest.files.allSatisfy({ file in
                  !file.path.hasPrefix("/") && !file.path.split(separator: "/").contains("..") &&
                  file.sha256.count == 64 && file.sha256.allSatisfy(\.isHexDigit) &&
                  ((file.role == "quranData" && file.edition == 1439) ||
                   (file.role == "visualOnly" && file.edition == 1405))
              }) else { throw QuranResourceCatalogError.invalidManifest }
        return manifest
    }

    public func verifiedData(at path: String) throws -> Data {
        guard let file = files.first(where: { $0.path == path }),
              let root = Bundle.module.resourceURL else { throw QuranResourceCatalogError.missingResource(path) }
        let data: Data
        do { data = try Data(contentsOf: root.appendingPathComponent(path)) }
        catch { throw QuranResourceCatalogError.missingResource(path) }
        guard SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == file.sha256 else {
            throw QuranResourceCatalogError.checksumMismatch(path)
        }
        return data
    }

    public func verifyFiles() throws {
        for file in files { _ = try verifiedData(at: file.path) }
    }

    /// Artwork is kept outside the Quran data namespace and contains no ayah text.
    public func ornament(named name: String) throws -> Data {
        guard name == "surah-opening" else {
            throw QuranResourceCatalogError.missingResource(name)
        }
        return try verifiedData(at: "Mushaf1405/\(name).svg")
    }
}
