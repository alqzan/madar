import XCTest
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import CryptoKit
import CoreSpotlight
@testable import Madar

@MainActor private final class SpotlightIndexProbe {
    private(set) var calls: [Bool] = []
    private(set) var indexedBookIDs: [[UUID]] = []
    private(set) var indexed = false
    private var enableStarted = false
    private var disableStarted = false
    private var holdNextEnable = false
    private var holdNextDisable = false
    private var startWaiter: CheckedContinuation<Void, Never>?
    private var disableWaiter: CheckedContinuation<Void, Never>?
    private var enableContinuation: CheckedContinuation<Void, Never>?
    private var disableContinuation: CheckedContinuation<Void, Never>?

    func apply(enabled: Bool, records: [AppSpotlightBookRecord]) async {
        calls.append(enabled)
        indexedBookIDs.append(enabled ? records.map(\.id) : [])
        if enabled {
            enableStarted = true
            startWaiter?.resume()
            startWaiter = nil
            if holdNextEnable {
                holdNextEnable = false
                await withCheckedContinuation { enableContinuation = $0 }
            }
            indexed = true
        } else {
            disableStarted = true
            disableWaiter?.resume()
            disableWaiter = nil
            if holdNextDisable {
                holdNextDisable = false
                await withCheckedContinuation { disableContinuation = $0 }
            }
            indexed = false
        }
    }

    func holdEnable() { holdNextEnable = true }

    func holdDisable() { holdNextDisable = true }

    func waitForEnableStart() async {
        guard !enableStarted else { return }
        await withCheckedContinuation { startWaiter = $0 }
    }

    func waitForDisableStart() async {
        guard !disableStarted else { return }
        await withCheckedContinuation { disableWaiter = $0 }
    }

    func finishEnable() {
        enableContinuation?.resume()
        enableContinuation = nil
    }

    func finishDisable() {
        disableContinuation?.resume()
        disableContinuation = nil
    }
}

@MainActor final class MihbaraHomeIntegrationTests: XCTestCase {
    func testPageFootnotesKeepContinuationLinesAndLongSourceText() throws {
        let note = try XCTUnwrap(MihbaraFootnote(html: "<aside><p>١ الحاشية الأولى.</p><p>سطر مكمل للحاشية.</p><a role=\"doc-backlink\" href=\"#page-ref\">عودة</a></aside>", referrer: "حواشي الصفحة"))
        XCTAssertEqual(note.number, "حواشي الصفحة")
        XCTAssertEqual(note.text, "١ الحاشية الأولى.\nسطر مكمل للحاشية.")
        let long = try XCTUnwrap(MihbaraFootnote(html: "<p>" + String(repeating: "نص حاشية طويل. ", count: 400) + "خاتمة الحاشية المحفوظة.</p>", referrer: "حواشي الصفحة"))
        XCTAssertTrue(long.text.hasSuffix("خاتمة الحاشية المحفوظة."), "The note card must not silently cut off the end of a source note")
    }

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

    func testHadithGateUsesTheActiveTripFajr() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraTripFajr-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        try await app.applySettingsAndWait(["core.dayStart": .string("midnight"), "salah.method": .string("mwl"),
                                            "salah.tripMethod": .string("egyptian"), "salah.highLatitudeRule": .string("twilightAngle")])
        let context = ModelContext(container), trip = Trip()
        trip.city = "لندن"; trip.lat = 51.5074; trip.lon = -0.1278; trip.tzID = "Europe/London"
        trip.mode = "manual"; trip.start = ISO8601DateFormatter().date(from: "2026-03-20T02:00:00Z")
        context.insert(trip); try context.save()
        let service = AppMihbaraService(app: app)
        let beforeTripFajr = ISO8601DateFormatter().date(from: "2026-03-20T03:00:00Z")!
        let afterTripFajr = ISO8601DateFormatter().date(from: "2026-03-20T04:08:00Z")!
        // Both instants are inside the trip. London MWL is 04:10 ±3 min; the selected Egyptian method opens earlier.
        XCTAssertFalse(try service.load(at: beforeTripFajr).opensAfterFajr)
        XCTAssertTrue(try service.load(at: afterTripFajr).opensAfterFajr)
    }

    func testReadingSavesRetryAfterStoreMaintenanceEnds() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraMaintenanceRetry-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let bytes = Data("synthetic EPUB".utf8)
        let media = Media(); media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = bytes
        media.sizeBytes = bytes.count; media.sha256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let bookID = UUID(), mediaID = media.id
        let book = Book(); book.id = bookID; book.title = "كتاب اختباري"; book.kind = "file"; book.format = "epub"
        book.mediaID = mediaID; book.fileHash = media.sha256; book.shelf = "reading"
        let context = ModelContext(container); context.insert(media); context.insert(book); try context.save()

        let app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData()
        let coordinator = MihbaraReadingSaveCoordinator.forSession(app)
        let start = ISO8601DateFormatter().date(from: "2026-10-26T12:00:00Z")!
        let end = start.addingTimeInterval(120)
        let startText = ISO8601DateFormatter().string(from: start), endText = ISO8601DateFormatter().string(from: end)
        let locator = "{\"href\":\"Text/chapter.xhtml\",\"type\":\"application/xhtml+xml\",\"locations\":{\"position\":2,\"progression\":0.2,\"totalProgression\":0.2}}"
        let sessionID = UUID()
        let sessionPayload: [String:MadarCore.JSONValue] = [
            "id": .string(sessionID.uuidString), "bookID": .string(bookID.uuidString),
            "start": .string(startText), "end": .string(endText), "activeSeconds": .number(61),
            "fromPage": .number(2), "toPage": .number(3), "startLocator": .string(locator), "endLocator": .string(locator),
            "startProgression": .number(0.2), "endProgression": .number(0.3), "pagesCounted": .number(1)
        ]

        try await app.quiesceWriters()
        coordinator.enqueue(sessionID: sessionID, payload: sessionPayload)
        coordinator.enqueueLocatorJSON(locator, bookID: bookID)
        await coordinator.waitForCurrentAttempt()
        XCTAssertTrue(coordinator.hasPending, "The busy store must leave both reading writes queued.")

        app.resumeWriters()
        await coordinator.waitForCurrentAttempt()
        XCTAssertFalse(coordinator.hasPending, "Ending maintenance must retry pending reading writes.")
        XCTAssertNil(app.errorMessage, "A recovered maintenance failure must not leave a stale error on screen.")
        let savedContext = ModelContext(container)
        XCTAssertEqual(try savedContext.fetch(FetchDescriptor<Book>()).first?.locatorJSON, Data(locator.utf8))
        let sessions = try savedContext.fetch(FetchDescriptor<ReadingSession>())
        XCTAssertEqual(sessions.count, 1)
        XCTAssertEqual(sessions.first?.id, sessionID)
        XCTAssertEqual(sessions.first?.activeSeconds, 61)
    }

    func testSpotlightBookRecordsContainOnlyLiveTitles() throws {
        let live = Book(); live.id = UUID(); live.title = "كتاب في المحبرة"; live.author = "اسم لا يُفهرس"
        let deleted = Book(); deleted.deletedAt = Date(); deleted.title = "كتاب محذوف"
        let merged = Book(); merged.mergedInto = UUID(); merged.title = "كتاب مدموج"
        let untitled = Book(); untitled.title = "  \n"

        let records = AppSpotlightIndexing.records(from: [live, deleted, merged, untitled])
        XCTAssertEqual(records.map(\.id), [live.id])
        let item = AppSpotlightIndexing.searchableItem(for: try XCTUnwrap(records.first))
        XCTAssertEqual(item.domainIdentifier, AppSpotlightIndexing.bookDomain)
        XCTAssertEqual(item.uniqueIdentifier, live.id.uuidString)
        XCTAssertEqual(item.attributeSet.title, live.title)
        XCTAssertNil(item.attributeSet.contentDescription)
        XCTAssertNil(item.attributeSet.authorNames)
        XCTAssertNil(item.attributeSet.keywords)
        XCTAssertNil(item.attributeSet.textContent)
    }

    func testSpotlightSelectionTargetsTheBookRoomWithoutLosingTheRequestedBook() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraSpotlight-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), app = try AppSession(container: container, groupDirectory: root)
        XCTAssertFalse(app.bool("core.spotlightIndex"))
        XCTAssertTrue(AppSession.supportedKeys.contains("core.spotlightIndex"))
        XCTAssertEqual(sectionFor("core.spotlightIndex"), "البحث")
        let id = UUID(); app.openSpotlightBook(id)
        XCTAssertEqual(app.selectedTab, "mihbara")
        XCTAssertEqual(app.mihbaraBookToOpen, id)
    }

    func testSpotlightIndexIsOptInAndClearsItsDomainWhenDisabled() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraSpotlightIndex-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let app = try AppSession(container: MadarContainerFactory.makeLocal(at: root), groupDirectory: root)
        XCTAssertFalse(app.bool("core.spotlightIndex"))
        try await app.applySettingsAndWait(["core.spotlightIndex": .bool(true)])
        XCTAssertTrue(app.bool("core.spotlightIndex")); XCTAssertNil(app.errorMessage)
        try await app.applySettingsAndWait(["core.spotlightIndex": .bool(false)])
        XCTAssertFalse(app.bool("core.spotlightIndex")); XCTAssertNil(app.errorMessage)
    }

    func testDeletingBookReconcilesOptedInSpotlightIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraSpotlightDelete-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let book = Book(); book.title = "كتاب قابل للحذف"; context.insert(book); try context.save()
        let probe = SpotlightIndexProbe()
        let app = try AppSession(
            container: container,
            groupDirectory: root,
            spotlightIndexOperation: { enabled, records in await probe.apply(enabled: enabled, records: records) }
        )
        app.authorizeProtectedData()
        try await app.applySettingsAndWait(["core.spotlightIndex": .bool(true)])
        XCTAssertEqual(probe.indexedBookIDs.last, [book.id])

        try await app.executeBookCommand("book.delete", payload: ["id": .string(book.id.uuidString)])

        XCTAssertEqual(probe.indexedBookIDs.last, [])
        XCTAssertEqual(probe.calls.filter { $0 }.count, 2)
        XCTAssertNil(app.errorMessage)
    }

    func testNonUndoableFileRemovalClearsAnOlderBookUndo() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraFileRemoval-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let bytes = Data("local PDF fixture".utf8), hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
        let media = Media(); media.kind = "doc"; media.contentType = "com.adobe.pdf"
        media.data = bytes; media.sizeBytes = bytes.count; media.sha256 = hash; context.insert(media)
        let book = Book(); book.title = "كتاب قابل لإزالة ملفه"; book.kind = "file"; book.format = "pdf"
        book.mediaID = media.id; book.fileHash = hash; context.insert(book); try context.save()
        let app = try AppSession(container: container, groupDirectory: root); app.authorizeProtectedData()

        try await app.executeBookCommand("book.moveShelf", payload: ["id": .string(book.id.uuidString), "shelf": .string("finished")])
        XCTAssertNotNil(app.undoToken)
        XCTAssertTrue(app.undoToastVisible)

        try await app.executeBookCommand("book.removeFile", payload: ["id": .string(book.id.uuidString)])

        XCTAssertNil(app.undoToken, "A prior undo must not appear to reverse this final file removal.")
        XCTAssertFalse(app.undoToastVisible)
        let refreshed = try XCTUnwrap(try ModelContext(container).fetch(FetchDescriptor<Media>()).first { $0.id == media.id })
        XCTAssertNil(refreshed.data)
        XCTAssertEqual(refreshed.state, "missing")
        XCTAssertNil(app.errorMessage)
    }

    func testDisablingSpotlightDuringPendingIndexFinishesWithDeletion() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraSpotlightRace-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let probe = SpotlightIndexProbe()
        probe.holdEnable()
        let app = try AppSession(
            container: MadarContainerFactory.makeLocal(at: root),
            groupDirectory: root,
            spotlightIndexOperation: { enabled, records in await probe.apply(enabled: enabled, records: records) }
        )

        let enableTask = Task { try await app.applySettingsAndWait(["core.spotlightIndex": .bool(true)]) }
        await probe.waitForEnableStart()
        let disableTask = Task { try await app.applySettingsAndWait(["core.spotlightIndex": .bool(false)]) }
        for _ in 0..<100 where app.bool("core.spotlightIndex") { await Task.yield() }
        XCTAssertFalse(app.bool("core.spotlightIndex"))
        XCTAssertEqual(probe.calls, [true])

        probe.finishEnable()
        try await enableTask.value
        try await disableTask.value
        XCTAssertEqual(probe.calls, [true, false])
        XCTAssertFalse(probe.indexed)
    }

    func testReenablingSpotlightDuringPendingDeletionRebuildsTheIndex() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "MihbaraSpotlightReverseRace-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let book = Book(); book.title = "كتاب محفوظ"
        let context = ModelContext(container); context.insert(book); try context.save()
        let probe = SpotlightIndexProbe()
        let app = try AppSession(
            container: container,
            groupDirectory: root,
            spotlightIndexOperation: { enabled, records in await probe.apply(enabled: enabled, records: records) }
        )
        try await app.applySettingsAndWait(["core.spotlightIndex": .bool(true)])
        XCTAssertTrue(probe.indexed)

        probe.holdDisable()
        let disableTask = Task { try await app.applySettingsAndWait(["core.spotlightIndex": .bool(false)]) }
        await probe.waitForDisableStart()
        let enableTask = Task { try await app.applySettingsAndWait(["core.spotlightIndex": .bool(true)]) }
        for _ in 0..<100 where !app.bool("core.spotlightIndex") { await Task.yield() }
        XCTAssertTrue(app.bool("core.spotlightIndex"))
        XCTAssertEqual(probe.calls, [true, false])

        probe.finishDisable()
        try await disableTask.value
        try await enableTask.value
        XCTAssertEqual(probe.calls, [true, false, true])
        XCTAssertTrue(probe.indexed)
    }
}
