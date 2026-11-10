import Foundation
import CoreSpotlight
import MadarData

struct AppSpotlightBookRecord: Equatable {
    let id: UUID
    let title: String
}

typealias AppSpotlightIndexOperation = @MainActor (Bool, [AppSpotlightBookRecord]) async throws -> Void

enum AppSpotlightIndexing {
    static let bookDomain = "madar.books"
    static let appDomains = [bookDomain, "madar.notes", "madar.privateNotes"]

    static func records(from books: [Book]) -> [AppSpotlightBookRecord] {
        books
            .filter { $0.deletedAt == nil && $0.mergedInto == nil && !$0.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .map { .init(id: $0.id, title: $0.title) }
            .sorted { $0.id.uuidString < $1.id.uuidString }
    }

    static func searchableItem(for record: AppSpotlightBookRecord) -> CSSearchableItem {
        let attributes = CSSearchableItemAttributeSet(contentType: .item)
        attributes.title = record.title
        return CSSearchableItem(uniqueIdentifier: record.id.uuidString, domainIdentifier: bookDomain, attributeSet: attributes)
    }

    static func removeAppItems(from index: CSSearchableIndex = .default()) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: appDomains)
    }

    static func replaceBookItems(_ records: [AppSpotlightBookRecord], in index: CSSearchableIndex = .default()) async throws {
        try await index.deleteSearchableItems(withDomainIdentifiers: [bookDomain])
        guard !records.isEmpty else { return }
        try await index.indexSearchableItems(records.map(searchableItem(for:)))
    }
}
