import Foundation
import MadarCore

/// Content shared by the iPhone quote card and the native Mac reader.
struct MihbaraQuoteCardContent: Identifiable {
    let id = UUID()
    let quote: String
    let bookTitle: String
    let author: String
    let location: String?
    let sourceURL: URL?
    let sourceName: String

    /// «ج ٣، ص ٤٥» for a Turath volume/page label, «ص ٤٥» otherwise.
    static func location(_ pageLabel: String?, turathID: Int?, digits: MadarNumberFormatter) -> String? {
        guard let pageLabel, !pageLabel.isEmpty else { return nil }
        let parts = pageLabel.split(separator: "/", omittingEmptySubsequences: false)
        if turathID != nil, parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
            return "ج \(digits.localized(String(parts[0])))، ص \(digits.localized(String(parts[1])))"
        }
        return "ص \(digits.localized(pageLabel))"
    }

    init(quote: String, bookTitle: String, author: String, pageLabel: String?, turathID: Int?, digits: MadarNumberFormatter) {
        self.quote = quote
        self.bookTitle = bookTitle
        self.author = author
        location = Self.location(pageLabel, turathID: turathID, digits: digits)
        sourceURL = turathID.flatMap { URL(string: "https://shamela.ws/book/\($0)") }
        sourceName = sourceURL == nil ? "من مكتبتك" : "المكتبة الشاملة"
    }

    var sourceAddress: String? {
        guard let sourceURL else { return nil }
        return sourceURL.host.map { $0 + sourceURL.path }
    }
}

/// Owner 27 Oct (OR-29): the quote alone by default; every extra is optional.
enum MihbaraQuoteExtra: String, CaseIterable, Identifiable {
    case book, author, location, source, signature
    var id: String { rawValue }
    var title: String {
        switch self {
        case .book: "الكتاب"
        case .author: "المؤلف"
        case .location: "الموضع"
        case .source: "المصدر"
        case .signature: "توقيع مِحبرة"
        }
    }
}
