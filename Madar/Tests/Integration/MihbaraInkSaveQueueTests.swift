import XCTest
@testable import Madar

@MainActor final class MihbaraInkSaveQueueTests: XCTestCase {
    private enum Failure: Error { case transient }

    func testFailedDrawingRemainsPendingUntilRetrySucceeds() async {
        var writes: [Data] = []
        var fail = true
        let queue = MihbaraInkSaveQueue { _, data in
            writes.append(data)
            if fail { fail = false; throw Failure.transient }
        }
        let drawing = Data([1, 2, 3])
        queue.enqueue(page: 0, data: drawing)
        let first = await queue.waitForCurrentAttempt()
        XCTAssertFalse(first)
        XCTAssertTrue(queue.hasPending)
        let retry = await queue.retryAndWait()
        XCTAssertTrue(retry)
        XCTAssertEqual(writes, [drawing, drawing])
        XCTAssertFalse(queue.hasPending)
    }

    func testAnOlderFailureCannotDiscardANewerDrawing() async {
        var releaseFirst: CheckedContinuation<Void, Never>?
        var writes: [Data] = []
        let old = Data([1]), latest = Data([2, 3])
        let queue = MihbaraInkSaveQueue { _, data in
            writes.append(data)
            if data == old {
                await withCheckedContinuation { releaseFirst = $0 }
                throw Failure.transient
            }
        }
        queue.enqueue(page: 0, data: old)
        while releaseFirst == nil { await Task.yield() }
        queue.enqueue(page: 0, data: latest)
        releaseFirst?.resume()
        let saved = await queue.waitForCurrentAttempt()
        XCTAssertTrue(saved)
        XCTAssertEqual(writes, [old, latest])
        XCTAssertFalse(queue.hasPending)
    }

    func testClearRetriesAsEmptyDataAndKeepsOtherPages() async {
        var saved: [Int: Data] = [:]
        var failClear = true
        let queue = MihbaraInkSaveQueue { page, data in
            if page == 0 && failClear { failClear = false; throw Failure.transient }
            saved[page] = data
        }
        queue.enqueue(page: 0, data: Data())
        queue.enqueue(page: 1, data: Data([4]))
        let first = await queue.waitForCurrentAttempt()
        XCTAssertFalse(first)
        XCTAssertEqual(saved[1], Data([4]))
        let retried = await queue.retryAndWait()
        XCTAssertTrue(retried)
        XCTAssertEqual(saved[0], Data())
        XCTAssertEqual(saved[1], Data([4]))
    }

    func testQueuedEditsCoalesceToTheLatestPageBytes() async {
        var writes: [Data] = []
        let queue = MihbaraInkSaveQueue { _, data in writes.append(data) }
        queue.enqueue(page: 0, data: Data([1]))
        queue.enqueue(page: 0, data: Data([2]))
        let saved = await queue.waitForCurrentAttempt()
        XCTAssertTrue(saved)
        XCTAssertEqual(writes, [Data([2])])
    }
}
