import Foundation
import SwiftData
import MadarData

extension AppMihbaraService {
    /// Saved page drawings belong to the book and use the same PencilKit bytes on iPhone, iPad and Mac.
    func pageInkOffMain(bookID: UUID) async throws -> [Int: Data] {
        let container = app.container
        let worker = Task.detached(priority: .userInitiated) {
            try Self.pageInk(container: container, bookID: bookID)
        }
        let result = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return result
    }

    nonisolated private static func pageInk(container: ModelContainer, bookID: UUID) throws -> [Int: Data] {
        let prefix = "pdf-ink:\(bookID.uuidString):"
        var descriptor = FetchDescriptor<Media>(predicate: #Predicate {
            $0.kind == "drawing" && $0.deletedAt == nil && $0.mergedInto == nil && $0.sourceID?.starts(with: prefix) == true
        })
        descriptor.propertiesToFetch = [\.sourceID, \.updatedAt, \.data]
        let context = ModelContext(container)
        let rows = try context.fetch(descriptor)
        var result: [Int: (Date, Data)] = [:]
        for (index, row) in rows.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            guard let key = row.sourceID, key.hasPrefix(prefix), let page = Int(key.dropFirst(prefix.count)), let data = row.data, !data.isEmpty else { continue }
            if (result[page]?.0 ?? .distantPast) < row.updatedAt { result[page] = (row.updatedAt, data) }
        }
        return result.mapValues(\.1)
    }
}
