import Foundation
import CryptoKit
import PDFKit
import UniformTypeIdentifiers
import NaturalLanguage
import MadarData

public struct PDFBookOutlineItem: Codable, Equatable, Sendable {
    public let title: String
    public let page: Int
}

public struct PDFBookInspection: Equatable, Sendable, Identifiable {
    public let id: UUID
    public let fileName: String
    public let sha256: String
    public let sizeBytes: Int
    public let pages: Int
    public let textPages: Int
    public let title: String
    public let author: String
    public let detectedLanguage: String?
    public let outline: [PDFBookOutlineItem]
    public let hasPageLabels: Bool
    public var scanned: Bool { textPages == 0 }
}

/// R05/R06. File bytes stay outside command payloads and receipts.
public enum PDFBookFiles {
    public static let maximumBytes = 500 * 1024 * 1024
    public static let maximumPages = 1000

    /// The PDF's own bookmarks, depth-first; `page` is one-based.
    static func outline(of document: PDFDocument) -> [PDFBookOutlineItem] {
        var outline: [PDFBookOutlineItem] = [], visited = 0
        func visit(_ parent: PDFOutline, depth: Int) {
            guard depth < 20, visited < 2000 else { return }
            for index in 0..<min(parent.numberOfChildren, 2000) {
                guard visited < 2000 else { break }
                visited += 1
                guard let child = parent.child(at: index) else { continue }
                if let title = child.label?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty,
                   let page = child.destination?.page {
                    let pageIndex = document.index(for: page)
                    if pageIndex != NSNotFound { outline.append(.init(title: String(title.prefix(300)), page: pageIndex + 1)) }
                }
                visit(child, depth: depth + 1)
            }
        }
        if let root = document.outlineRoot { visit(root, depth: 0) }
        return outline
    }

    public static func stagedURL(id: UUID, root: URL) -> URL { root.appendingPathComponent(id.uuidString).appendingPathExtension("pdf") }

    public static func stage(source: URL, root: URL, id: UUID = UUID()) throws -> PDFBookInspection {
        let scoped = source.startAccessingSecurityScopedResource()
        defer { if scoped { source.stopAccessingSecurityScopedResource() } }
        let values = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .contentTypeKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true,
              values.contentType?.conforms(to: .pdf) == true else { throw DataError.invalidValue("اختر ملف PDF؛ الصيغ الأخرى لها مسار استيراد مستقل.") }
        if let size = values.fileSize { try checkSize(size) }
        let input = try FileHandle(forReadingFrom: source)
        defer { try? input.close() }
        let length = try input.seekToEnd()
        guard length <= UInt64(maximumBytes) else { throw DataError.invalidValue("الحد الأقصى للملف ٥٠٠ م.ب.") }
        try checkSize(Int(length))
        try input.seek(toOffset: 0)
        guard try input.read(upToCount: 5) == Data("%PDF-".utf8) else { throw DataError.invalidValue("امتداد الملف PDF، لكن محتواه ليس ملف PDF صالحًا.") }
        try input.seek(toOffset: 0)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let destination = stagedURL(id: id, root: root)
        guard !FileManager.default.fileExists(atPath: destination.path) else { throw DataError.invalidValue("هذا الملف قيد المعاينة بالفعل.") }
        guard FileManager.default.createFile(atPath: destination.path, contents: nil) else { throw DataError.invalidValue("تعذّر نسخ الملف إلى مدار.") }
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: destination) } }
        #if os(iOS)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: destination.path)
        #endif
        let output = try FileHandle(forWritingTo: destination)
        defer { try? output.close() }
        var copied = 0
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            copied += chunk.count
            try checkSize(copied)
            try output.write(contentsOf: chunk)
        }
        try output.synchronize()
        guard copied == Int(length) else { throw DataError.invalidValue("تغيّر الملف أثناء نسخه؛ اختره مرة أخرى.") }
        let inspection = try inspect(id: id, root: root, fileName: source.lastPathComponent)
        complete = true
        return inspection
    }

    public static func inspect(id: UUID, root: URL, fileName: String = "كتاب.pdf") throws -> PDFBookInspection {
        let file = stagedURL(id: id, root: root)
        let values = try file.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true, let size = values.fileSize else { throw DataError.invalidValue("ملف المعاينة غير صالح.") }
        try checkSize(size)
        let input = try FileHandle(forReadingFrom: file)
        defer { try? input.close() }
        guard try input.read(upToCount: 5) == Data("%PDF-".utf8) else { throw DataError.invalidValue("ملف PDF تالف.") }
        try input.seek(toOffset: 0)
        var hash = SHA256(), actualSize = 0
        while let chunk = try input.read(upToCount: 1024 * 1024), !chunk.isEmpty {
            actualSize += chunk.count; try checkSize(actualSize); hash.update(data: chunk)
        }
        guard actualSize == size, let document = PDFDocument(url: file) else { throw DataError.invalidValue("تعذّر فتح ملف PDF؛ قد يكون تالفًا.") }
        guard !document.isEncrypted, !document.isLocked else { throw DataError.invalidValue("ملف PDF محمي؛ اختر نسخة غير محمية بكلمة مرور.") }
        guard document.pageCount > 0, document.pageCount <= maximumPages else { throw DataError.invalidValue("الحد الأقصى ١٠٠٠ صفحة؛ لا يُضاف ملف فارغ.") }
        var textPages = 0, sample = ""
        for index in 0..<document.pageCount {
            guard let page = document.page(at: index) else { throw DataError.invalidValue("تعذّر فحص إحدى صفحات الملف.") }
            let text = page.string?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            if !text.isEmpty { textPages += 1; if sample.count < 16_000 { sample += String(text.prefix(16_000 - sample.count)) + " " } }
        }
        let recognizer = NLLanguageRecognizer(); recognizer.processString(sample)
        let dominant = recognizer.languageHypotheses(withMaximum: 1).first
        let language = !sample.isEmpty && (dominant?.value ?? 0) >= 0.75 ? dominant?.key.rawValue : nil
        let outline = Self.outline(of: document)
        var labels: CGPDFDictionaryRef?
        let hasLabels = document.documentRef?.catalog.map { CGPDFDictionaryGetDictionary($0, "PageLabels", &labels) } ?? false
        let attributes = document.documentAttributes ?? [:]
        let metadataTitle = (attributes[PDFDocumentAttribute.titleAttribute] as? String)?.trimmingCharacters(in: .whitespacesAndNewlines)
        let fallback = URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
        return PDFBookInspection(id: id, fileName: fileName, sha256: hash.finalize().map { String(format: "%02x", $0) }.joined(),
            sizeBytes: size, pages: document.pageCount, textPages: textPages,
            title: String((metadataTitle.flatMap { $0.isEmpty ? nil : $0 } ?? fallback).prefix(300)),
            author: String(((attributes[PDFDocumentAttribute.authorAttribute] as? String) ?? "").prefix(300)),
            detectedLanguage: language, outline: outline, hasPageLabels: hasLabels)
    }

    public static func discard(id: UUID, root: URL) { try? FileManager.default.removeItem(at: stagedURL(id: id, root: root)) }
    private static func checkSize(_ size: Int) throws {
        guard size > 0, size <= maximumBytes else { throw DataError.invalidValue("اختر ملفًا غير فارغ لا يتجاوز ٥٠٠ م.ب.") }
    }
}
