import XCTest
import MadarQuran
import MadarCommands
@testable import Madar

@MainActor
final class QuranTafsirLibraryIntegrationTests: XCTestCase {
    func testTurathIbnKathirDownloadsAndRestoresForOfflineReference() async throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("Madar-QuranTafsir-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let library = QuranTafsirLibrary(directory: directory)
        await library.loadLocal()
        XCTAssertNil(library.localErrorMessage)
        XCTAssertTrue(library.books.contains { $0.id == 42 }, "The bundled Saadi tafsir should always be available.")

        await library.loadCatalogue()
        XCTAssertNil(library.catalogueErrorMessage, library.catalogueErrorMessage ?? "")
        let book = try XCTUnwrap(library.catalogue.first { $0.id == 1_503 && $0.categoryID == 3 })
        await library.download(book)

        XCTAssertNil(library.operationErrorMessage, library.operationFailureDescription ?? library.operationErrorMessage ?? "")
        let downloaded = try XCTUnwrap(library.index(for: book.id))
        XCTAssertFalse(downloaded.passages.isEmpty)
        XCTAssertTrue(downloaded.passages.allSatisfy { !$0.pages.isEmpty }, "Every indexed passage needs a source page reference.")

        let catalog = try QuranResources.catalog()
        let first = try XCTUnwrap(catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 187 })
        XCTAssertFalse(downloaded.passages(forAyahID: first.id).isEmpty, "The downloaded tafsir should map to the exact Baqara ayah used by the reference flow.")

        let restored = QuranTafsirLibrary(directory: directory)
        await restored.loadLocal()
        XCTAssertNil(restored.localErrorMessage)
        let restoredIndex = try XCTUnwrap(restored.index(for: book.id))
        XCTAssertEqual(restoredIndex, downloaded)
        XCTAssertTrue(restored.books.contains { $0.id == book.id && !$0.isBundled })

        restored.remove(bookID: book.id)
        XCTAssertNil(restored.operationErrorMessage)
        XCTAssertNil(restored.index(for: book.id))
        XCTAssertTrue(restored.books.contains { $0.id == 42 }, "Removing a downloaded tafsir must retain the bundled book.")
    }
}
