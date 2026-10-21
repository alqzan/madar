import Foundation
import CryptoKit
import UniformTypeIdentifiers
import MadarCore
import MadarData

public struct EPUBBookOutlineItem: Codable, Equatable, Sendable {
    public let title: String
    public let href: String
    public let depth: Int
}

public struct EPUBBookInspection: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let sha256: String
    public let sizeBytes: Int
    public let title: String
    public let author: String
    public let languageCode: String?
    public let direction: String?
    public let version: String
    public let outline: [EPUBBookOutlineItem]
    public let hasPageList: Bool
    public let hasCover: Bool
    public let coverData: Data?
    public let hasFootnotes: Bool?

    public var appLanguage: String? {
        guard let languageCode else { return nil }
        let language = languageCode.lowercased().split(separator: "-").first.map(String.init)
        return language == "ar" || language == "en" ? language : nil
    }
}

/// R05/R06: the original EPUB remains unchanged; the staged copy is bounded and re-inspected at commit.
public enum EPUBBookFiles {
    public static let maximumBytes = 500 * 1024 * 1024
    public static let maximumEntries = 10_000
    public static let maximumExpandedBytes = 1024 * 1024 * 1024
    public static let maximumCompressionRatio = 100
    private static let metadataMemberLimit = 2 * 1024 * 1024
    private static let documentScanLimit = 16 * 1024 * 1024
    private static let documentMemberLimit = 1024 * 1024

    public static func stagedURL(id: UUID, root: URL) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("epub") }

    public static func stage(source: URL, root: URL, id: UUID = UUID()) throws -> EPUBBookInspection {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.contentType?.conforms(to: UTType("org.idpf.epub-container")!) == true else {
            throw DataError.invalidValue("اختر ملف EPUB غير محمي؛ ملفات Kindle المحمية لا تُفتح.")
        }
        let sourceHandle = try FileHandle(forReadingFrom: source)
        defer { try? sourceHandle.close() }
        let sourceLength = try sourceHandle.seekToEnd()
        guard sourceLength > 0, sourceLength <= UInt64(maximumBytes) else {
            throw DataError.invalidValue("اختر ملف EPUB غير فارغ لا يتجاوز ٥٠٠ م.ب.")
        }
        let sourceSize = Int(sourceLength)

        // Inspect the provider URL first so protected, malformed and oversized archives are rejected before copy.
        let preflight = try inspect(file: source, id: id, fileName: source.lastPathComponent)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = stagedURL(id: id, root: root)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw DataError.invalidValue("هذا الملف قيد المعاينة بالفعل.") }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw DataError.invalidValue("تعذّر نسخ الملف إلى مدار.") }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
        let input = try FileHandle(forReadingFrom: source), output = try FileHandle(forWritingTo: destination)
        defer { try? input.close(); try? output.close() }
        var copied = 0
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            copied += chunk.count
            guard copied <= maximumBytes else { throw DataError.invalidValue("الحد الأقصى للملف ٥٠٠ م.ب.") }
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
        guard copied == sourceSize else { throw DataError.invalidValue("تغيّر الملف أثناء نسخه؛ اختره مرة أخرى.") }
        let staged = try inspect(file: destination, id: id, fileName: source.lastPathComponent)
        guard staged.sha256 == preflight.sha256 else { throw DataError.invalidValue("تغيّر الملف أثناء نسخه؛ اختره مرة أخرى.") }
        complete = true
        return staged
    }

    public static func inspect(id: UUID, root: URL, fileName: String = "كتاب.epub") throws -> EPUBBookInspection {
        try inspect(file: stagedURL(id: id, root: root), id: id, fileName: fileName)
    }

    public static func discard(id: UUID, root: URL) { try? FileManager.default.removeItem(at: stagedURL(id: id, root: root)) }

    private static func inspect(file: URL, id: UUID, fileName: String) throws -> EPUBBookInspection {
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DataError.invalidValue("ملف EPUB غير صالح.") }
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        let fileLength = try input.seekToEnd()
        guard fileLength > 0, fileLength <= UInt64(maximumBytes) else { throw DataError.invalidValue("ملف EPUB غير صالح أو يتجاوز ٥٠٠ م.ب.") }
        let size = Int(fileLength)
        try input.seek(toOffset: 0)
        guard try input.read(upToCount: 4) == Data([0x50, 0x4B, 0x03, 0x04]) else {
            throw DataError.invalidValue("امتداد الملف EPUB، لكن محتواه ليس ملف EPUB صالحًا.")
        }
        try input.seek(toOffset: 0)
        var digest = SHA256(), hashedBytes = 0
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            hashedBytes += chunk.count
            guard hashedBytes <= maximumBytes else { throw DataError.invalidValue("الحد الأقصى للملف ٥٠٠ م.ب.") }
            digest.update(data: chunk)
        }
        guard hashedBytes == size else { throw DataError.invalidValue("تغيّر الملف أثناء فحصه.") }

        let archive: ZIPReader
        do { archive = try ZIPReader(url: file) }
        catch { throw DataError.invalidValue("ملف EPUB تالف أو غير مدعوم.") }
        try validate(archive)
        guard let mimetype = archive.members.first, mimetype.path == "mimetype", mimetype.method == 0,
              try archive.read(mimetype) == Data("application/epub+zip".utf8) else {
            throw DataError.invalidValue("ملف EPUB غير مكتمل؛ لم نجد توقيع EPUB الصحيح.")
        }
        guard let containerMember = archive.member("META-INF/container.xml") else { throw DataError.invalidValue("ملف EPUB ناقص: لا يوجد مسار الحزمة.") }
        let container = try xml(archive, containerMember, maximum: 64 * 1024)
        guard let packagePath = container.descendants(named: "rootfile").first?.attribute("full-path"),
              Self.safeArchivePath(packagePath), let packageMember = archive.member(packagePath) else {
            throw DataError.invalidValue("مسار حزمة EPUB غير صالح.")
        }
        let package = try xml(archive, packageMember, maximum: metadataMemberLimit)
        guard let packageNode = package.name == "package" ? package : package.descendants(named: "package").first,
              let version = packageNode.attribute("version"), ["2", "2.0", "3", "3.0"].contains(version) else {
            throw DataError.invalidValue("يدعم مدار EPUB 2 وEPUB 3 فقط.")
        }
        let metadata = packageNode.first(named: "metadata")
        let title = metadata?.descendants(named: "title").first?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let authors = (metadata?.descendants(named: "creator") ?? []).map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }.filter { !$0.isEmpty }
        let language = metadata?.descendants(named: "language").first?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let direction = packageNode.attribute("dir") ?? packageNode.first(named: "spine")?.attribute("page-progression-direction")

        let packageFolder = (packagePath as NSString).deletingLastPathComponent
        let manifestNodes = packageNode.first(named: "manifest")?.children.filter { $0.name == "item" } ?? []
        var manifest: [String: (path: String, mediaType: String, properties: Set<String>)] = [:]
        var ids = Set<String>(), manifestPaths = Set<String>()
        for item in manifestNodes {
            guard let itemID = item.attribute("id"), !itemID.isEmpty, ids.insert(itemID).inserted,
                  let href = item.attribute("href"), let path = archivePath(for: href, base: packageFolder),
                  archive.member(path) != nil else { throw DataError.invalidValue("مرجع داخل EPUB مفقود أو غير صالح.") }
            guard manifestPaths.insert(path).inserted else { throw DataError.invalidValue("مرجع مكرر داخل EPUB.") }
            manifest[itemID] = (path, item.attribute("media-type") ?? "", Set((item.attribute("properties") ?? "").split(whereSeparator: \.isWhitespace).map(String.init)))
        }
        let spine = packageNode.first(named: "spine")
        let spineRefs = spine?.children.filter { $0.name == "itemref" }.compactMap { $0.attribute("idref") } ?? []
        guard !spineRefs.isEmpty, spineRefs.allSatisfy({ manifest[$0] != nil }) else { throw DataError.invalidValue("ملف EPUB بلا ترتيب قراءة صالح.") }
        let coverID = metadata?.descendants(named: "meta").first(where: { $0.attribute("name") == "cover" })?.attribute("content")
        let coverItem = manifest.values.first(where: { $0.properties.contains("cover-image") }) ?? coverID.flatMap { manifest[$0] }
        let hasCover = coverItem != nil
        let coverData: Data?
        if let coverItem, coverItem.mediaType.hasPrefix("image/"),
           let member = archive.member(coverItem.path), member.size <= 4 * 1024 * 1024,
           let bytes = try? archive.read(member), Self.isSupportedCover(bytes, mediaType: coverItem.mediaType) {
            coverData = bytes
        } else { coverData = nil }

        try validateEncryption(archive)
        let navigationItem = manifest.values.first(where: { $0.properties.contains("nav") })
        let ncxID = spine?.attribute("toc")
        let ncxItem = ncxID.flatMap { manifest[$0] }
        var outline: [EPUBBookOutlineItem] = []
        var hasPageList = false
        if let navigationItem {
            let nav = try xml(archive, path: navigationItem.path, maximum: metadataMemberLimit)
            if let toc = nav.descendants(named: "nav").first(where: { $0.attribute("type")?.split(whereSeparator: { $0.isWhitespace }).contains("toc") == true }) {
                outline = anchors(in: toc, depth: 0)
            }
            hasPageList = nav.descendants(named: "nav").contains { $0.attribute("type")?.split(whereSeparator: { $0.isWhitespace }).contains("page-list") == true }
        } else if let ncxItem {
            let ncx = try xml(archive, path: ncxItem.path, maximum: metadataMemberLimit)
            if let navMap = ncx.descendants(named: "navMap").first { outline = ncxItems(navMap, depth: 0) }
            hasPageList = !ncx.descendants(named: "pageTarget").isEmpty
        }

        let hasFootnotes = scanFootnotes(archive, spineRefs: spineRefs, manifest: manifest)
        let fallbackTitle = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return EPUBBookInspection(id: id, fileName: fileName, sha256: digest.finalize().map { String(format: "%02x", $0) }.joined(),
                                  sizeBytes: size, title: String((title.flatMap { $0.isEmpty ? nil : $0 } ?? fallbackTitle).prefix(300)),
                                  author: String(authors.joined(separator: "، ").prefix(300)), languageCode: language.flatMap { $0.isEmpty ? nil : String($0.prefix(80)) },
                                  direction: ["rtl", "ltr"].contains(direction?.lowercased() ?? "") ? direction?.lowercased() : nil,
                                  version: version.hasPrefix("3") ? "3" : "2", outline: Array(outline.prefix(2000)), hasPageList: hasPageList,
                                  hasCover: hasCover, coverData: coverData, hasFootnotes: hasFootnotes)
    }

    /// The printed size of a book from its EPUB page list: how many printed pages, and how many volumes
    /// (Turath labels a multi-volume page «ج/ص»). Nil when the file has no page list.
    public static func printedShape(file: URL) throws -> (pages: Int, volumes: Int)? {
        let archive = try ZIPReader(url: file)
        guard let containerMember = archive.member("META-INF/container.xml") else { return nil }
        let container = try xml(archive, containerMember, maximum: 64 * 1024)
        guard let packagePath = container.descendants(named: "rootfile").first?.attribute("full-path"),
              Self.safeArchivePath(packagePath), let packageMember = archive.member(packagePath) else { return nil }
        let package = try xml(archive, packageMember, maximum: metadataMemberLimit)
        guard let packageNode = package.name == "package" ? package : package.descendants(named: "package").first else { return nil }
        let folder = (packagePath as NSString).deletingLastPathComponent
        let items = packageNode.first(named: "manifest")?.children.filter { $0.name == "item" } ?? []
        var labels: [String] = []
        if let nav = items.first(where: { ($0.attribute("properties") ?? "").split(whereSeparator: \.isWhitespace).contains("nav") }),
           let href = nav.attribute("href"), let path = archivePath(for: href, base: folder) {
            let node = try xml(archive, path: path, maximum: metadataMemberLimit)
            if let list = node.descendants(named: "nav").first(where: { $0.attribute("type")?.split(whereSeparator: { $0.isWhitespace }).contains("page-list") == true }) {
                labels = list.descendants(named: "a").map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
            }
        }
        if labels.isEmpty, let tocID = packageNode.first(named: "spine")?.attribute("toc"),
           let ncx = items.first(where: { $0.attribute("id") == tocID }), let href = ncx.attribute("href"), let path = archivePath(for: href, base: folder) {
            labels = try xml(archive, path: path, maximum: metadataMemberLimit).descendants(named: "pageTarget").map { $0.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) }
        }
        guard !labels.isEmpty else { return nil }
        let volumes = Set(labels.compactMap { label -> String? in
            let parts = label.split(separator: "/"); return parts.count == 2 ? String(parts[0]) : nil
        })
        return (labels.count, max(1, volumes.count))
    }

    private static func validate(_ archive: ZIPReader) throws {
        guard archive.members.count <= maximumEntries else { throw DataError.invalidValue("ملف EPUB يحتوي عددًا كبيرًا من الملفات.") }
        var expanded = 0
        for member in archive.members {
            guard !member.isSymbolicLink else { throw DataError.invalidValue("ملف EPUB يحتوي رابطًا رمزيًا غير آمن.") }
            guard !member.isEncrypted else { throw DataError.invalidValue("ملف EPUB محمي؛ اختر نسخة بلا DRM.") }
            guard member.size >= 0, member.compressedSize > 0 || member.size == 0 else { throw DataError.invalidValue("بنية ZIP غير صالحة.") }
            let (sum, overflow) = expanded.addingReportingOverflow(member.size)
            guard !overflow, sum <= maximumExpandedBytes else { throw DataError.invalidValue("يتجاوز EPUB حدّ الحجم بعد فك الضغط (١ غ.ب.).") }
            expanded = sum
            guard Double(member.size) <= Double(member.compressedSize) * Double(maximumCompressionRatio) || member.size == 0 else {
                throw DataError.invalidValue("نسبة ضغط EPUB أعلى من الحد الآمن (١٠٠:١).")
            }
            guard member.method == 0 || member.method == 8 else { throw DataError.invalidValue("طريقة ضغط EPUB غير مدعومة.") }
        }
    }

    private static func validateEncryption(_ archive: ZIPReader) throws {
        guard let member = archive.member("META-INF/encryption.xml") else { return }
        let document = try xml(archive, member, maximum: metadataMemberLimit)
        let encrypted = document.descendants(named: "EncryptedData")
        guard !encrypted.isEmpty else { throw DataError.invalidValue("بيانات حماية EPUB غير مكتملة.") }
        for item in encrypted {
            let algorithm = item.descendants(named: "EncryptionMethod").first?.attribute("Algorithm")
            let uri = item.descendants(named: "CipherReference").first?.attribute("URI")
            let normalized = uri.flatMap { archivePath(for: $0, base: "") }
            let path = normalized?.lowercased() ?? ""
            let font = [".otf", ".ttf", ".woff", ".woff2"].contains(where: { path.hasSuffix($0) })
                && normalized.flatMap(archive.member) != nil
            let knownFontObfuscation = algorithm == "http://www.idpf.org/2008/embedding" || algorithm == "http://ns.adobe.com/pdf/enc#RC"
            guard knownFontObfuscation, font else { throw DataError.invalidValue("ملف EPUB محمي؛ اختر نسخة بلا DRM.") }
        }
    }

    private static func xml(_ archive: ZIPReader, _ member: ZIPReader.Member, maximum: Int) throws -> EPUBXMLNode {
        guard member.size <= maximum else { throw DataError.invalidValue("أحد فهارس EPUB يتجاوز الحد الآمن.") }
        do {
            let data = try archive.read(member)
            let parser = XMLParser(data: data)
            parser.shouldProcessNamespaces = false
            parser.shouldResolveExternalEntities = false
            let builder = EPUBXMLTreeBuilder(); parser.delegate = builder
            guard parser.parse(), !builder.hasInternalEntities, let root = builder.root else { throw DataError.invalidValue("بنية XML داخل EPUB تالفة أو تحتوي كيانات غير آمنة.") }
            return root
        } catch let error as DataError { throw error }
        catch { throw DataError.invalidValue("تعذّر قراءة فهرس EPUB بأمان.") }
    }

    private static func xml(_ archive: ZIPReader, path: String, maximum: Int) throws -> EPUBXMLNode {
        guard let member = archive.member(path) else { throw DataError.invalidValue("مرجع XML داخل EPUB غير موجود.") }
        return try xml(archive, member, maximum: maximum)
    }

    private static func scanFootnotes(_ archive: ZIPReader, spineRefs: [String], manifest: [String: (path: String, mediaType: String, properties: Set<String>)]) -> Bool? {
        var scannedBytes = 0
        for ref in spineRefs {
            guard let item = manifest[ref], item.mediaType == "application/xhtml+xml" || item.mediaType == "text/html",
                  let member = archive.member(item.path), member.size <= documentMemberLimit else { return nil }
            let (sum, overflow) = scannedBytes.addingReportingOverflow(member.size)
            guard !overflow, sum <= documentScanLimit else { return nil }
            scannedBytes = sum
            guard let node = try? xml(archive, member, maximum: documentMemberLimit) else { return nil }
            if node.descendants(named: "*", matching: { candidate in
                let types = candidate.attribute("type")?.split(whereSeparator: \.isWhitespace).map(String.init) ?? []
                let role = candidate.attribute("role") ?? ""
                return types.contains(where: { ["footnote", "footnotes", "endnote", "endnotes"].contains($0) }) || role == "doc-footnote" || role == "doc-endnote"
            }).isEmpty == false { return true }
        }
        return false
    }

    private static func anchors(in node: EPUBXMLNode, depth: Int) -> [EPUBBookOutlineItem] {
        var result: [EPUBBookOutlineItem] = []
        for child in node.children {
            if child.name == "a", let href = child.attribute("href"), !href.isEmpty {
                let title = child.stringValue.trimmingCharacters(in: .whitespacesAndNewlines)
                if !title.isEmpty { result.append(.init(title: String(title.prefix(300)), href: String(href.prefix(1024)), depth: min(depth, 20))) }
            }
            result.append(contentsOf: anchors(in: child, depth: child.name == "ol" ? depth + 1 : depth))
        }
        return result
    }

    private static func ncxItems(_ node: EPUBXMLNode, depth: Int) -> [EPUBBookOutlineItem] {
        var result: [EPUBBookOutlineItem] = []
        for child in node.children where child.name == "navPoint" {
            let title = child.descendants(named: "text").first?.stringValue.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            let href = child.descendants(named: "content").first?.attribute("src") ?? ""
            if !title.isEmpty, !href.isEmpty { result.append(.init(title: String(title.prefix(300)), href: String(href.prefix(1024)), depth: min(depth, 20))) }
            result.append(contentsOf: ncxItems(child, depth: depth + 1))
        }
        return result
    }

    private static func archivePath(for reference: String, base: String) -> String? {
        let path = String(reference.split(separator: "#", maxSplits: 1, omittingEmptySubsequences: false).first ?? "")
            .split(separator: "?", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        guard let decoded = path.removingPercentEncoding, !decoded.isEmpty, !decoded.hasPrefix("/"),
              !decoded.contains("\\"), !decoded.contains(":"), !decoded.contains("\0") else { return nil }
        var parts = base.isEmpty ? [] : base.split(separator: "/").map(String.init)
        for part in decoded.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            if part.isEmpty || part == "." { continue }
            if part == ".." { guard !parts.isEmpty else { return nil }; parts.removeLast() }
            else { parts.append(part) }
        }
        let result = parts.joined(separator: "/")
        return safeArchivePath(result) ? result : nil
    }

    private static func safeArchivePath(_ path: String) -> Bool {
        !path.isEmpty && !path.hasPrefix("/") && !path.contains("\\") && !path.contains("\0") && !path.contains(":")
            && !path.split(separator: "/", omittingEmptySubsequences: false).contains("..")
    }

    private static func isSupportedCover(_ data: Data, mediaType: String) -> Bool {
        switch mediaType.lowercased() {
        case "image/png": return data.starts(with: [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        case "image/jpeg", "image/jpg": return data.starts(with: [0xFF, 0xD8, 0xFF])
        case "image/gif": return data.starts(with: Data("GIF8".utf8))
        case "image/webp": return data.count >= 12 && data.starts(with: Data("RIFF".utf8)) && data[8..<12] == Data("WEBP".utf8)
        case "image/tiff": return data.starts(with: [0x49, 0x49, 0x2A, 0x00]) || data.starts(with: [0x4D, 0x4D, 0x00, 0x2A])
        default: return false
        }
    }
}

private final class EPUBXMLNode {
    let name: String
    let attributes: [String: String]
    var text = ""
    var children: [EPUBXMLNode] = []
    init(name: String, attributes: [String: String]) { self.name = name; self.attributes = attributes }
    var stringValue: String { text + children.map(\.stringValue).joined() }
    func attribute(_ name: String) -> String? { attributes.first(where: { $0.key == name || $0.key.hasSuffix(":" + name) })?.value }
    func first(named name: String) -> EPUBXMLNode? { children.first(where: { $0.name == name }) }
    func descendants(named name: String, matching predicate: ((EPUBXMLNode) -> Bool)? = nil) -> [EPUBXMLNode] {
        var result: [EPUBXMLNode] = []
        for child in children {
            if (name == "*" || child.name == name), predicate?(child) ?? true { result.append(child) }
            result.append(contentsOf: child.descendants(named: name, matching: predicate))
        }
        return result
    }
}

private final class EPUBXMLTreeBuilder: NSObject, XMLParserDelegate {
    var root: EPUBXMLNode?
    var hasInternalEntities = false
    private var stack: [EPUBXMLNode] = []
    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName qName: String?, attributes attributeDict: [String: String] = [:]) {
        let node = EPUBXMLNode(name: elementName.split(separator: ":").last.map(String.init) ?? elementName, attributes: attributeDict)
        if let parent = stack.last { parent.children.append(node) } else { root = node }
        stack.append(node)
    }
    func parser(_ parser: XMLParser, didEndElement elementName: String, namespaceURI: String?, qualifiedName qName: String?) { if !stack.isEmpty { stack.removeLast() } }
    func parser(_ parser: XMLParser, foundCharacters string: String) { stack.last?.text += string }
    func parser(_ parser: XMLParser, foundCDATA CDATABlock: Data) { if let value = String(data: CDATABlock, encoding: .utf8) { stack.last?.text += value } }
    func parser(_ parser: XMLParser, foundInternalEntityDeclarationWithName name: String, value: String?) {
        hasInternalEntities = true
        parser.abortParsing()
    }
}
