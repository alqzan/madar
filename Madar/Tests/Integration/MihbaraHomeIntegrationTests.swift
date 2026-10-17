import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import CryptoKit
@testable import Madar

@MainActor final class MihbaraHomeIntegrationTests: XCTestCase {
    func testPinnedMatnAndRealFajrGateThenExplicitWirdAndUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraHome-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight")])
        let service = AppMihbaraService(app: app), catalog = try MihbaraCollection.load()
        XCTAssertEqual(catalog.hadiths.count, 42); XCTAssertEqual(catalog.hadiths[12].number, 13)
        XCTAssertTrue(catalog.hadiths[18].text.contains("واعلم أن الأمة")); XCTAssertTrue(catalog.hadiths[26].text.contains("وابصة"))
        let url = try XCTUnwrap(Bundle.main.url(forResource: "nawawi40", withExtension: "json"))
        XCTAssertEqual(SHA256.hash(data: try Data(contentsOf: url)).map { String(format: "%02x", $0) }.joined(), "0927a9cd7c6a567cdef6507b5648e90b372151648add62a00a8122bc78065abe")
        let beforeFajr = ISO8601DateFormatter().date(from: "2026-10-17T03:00:00+03:00")!, afterFajr = ISO8601DateFormatter().date(from: "2026-10-17T12:00:00+03:00")!
        XCTAssertFalse(try service.load(at: beforeFajr).opensAfterFajr); XCTAssertTrue(try service.load(at: afterFajr).opensAfterFajr)
        let today = try service.load().day
        try await app.executeBookCommand("hadith.mark", payload: ["number":.number(1),"edition":.string(catalog.editionID),"understood":.bool(true),"day":.string(today.description)])
        XCTAssertTrue(try service.load().todayHadiths.isEmpty); XCTAssertEqual(try service.load().completedToday, 1)
        let token = try XCTUnwrap(app.undoToken)
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, generationProvider: { try app.pendingInbox.currentGeneration()?.generationID })
        let result = try await CommandBus(adapter: adapter).execute(.init(name: "system.undo", payload: .object(["undoToken":.string(token.id.uuidString)])))
        XCTAssertEqual(result.status, .applied, result.reason ?? ""); XCTAssertEqual(try service.load().todayHadiths.first?.number, 1)
    }
}
