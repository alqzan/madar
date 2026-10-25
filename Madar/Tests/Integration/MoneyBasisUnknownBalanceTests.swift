import XCTest
import SwiftData
import MadarData
import MadarCore
@testable import Madar

@MainActor final class MoneyBasisUnknownBalanceTests: XCTestCase {
    func testUnknownCheckpointIsListedWithoutBecomingCashOrChangingRecords() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("UnknownBasis-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        let missing = Account(); missing.name = "رصيد غير معروف"; missing.balanceMinor = 999_999; missing.balanceAt = nil
        let excluded = Account(); excluded.name = "غير مملوك"; excluded.ownership = "notMine"
        let untracked = Account(); untracked.name = "غير متتبّع"; untracked.tracked = false
        let deleted = Account(); deleted.deletedAt = .now
        let alias = Account(); alias.mergedInto = missing.id; alias.deletedAt = .now
        context.insert(missing); context.insert(excluded); context.insert(untracked); context.insert(deleted); context.insert(alias); try context.save()
        let app = try AppSession(container: container, groupDirectory: root), service = AppMoneyService(app: app)
        app.authorizeProtectedData()
        let before = try RecordBridge.all(ModelContext(container))
        let reading = try service.loadBasis()
        XCTAssertEqual(reading.home.unknownBalanceCount, 1); XCTAssertEqual(reading.home.knownBalanceCount, 0)
        XCTAssertFalse(reading.home.hasKnownBalance)
        XCTAssertEqual(reading.accounts.count, 1); XCTAssertEqual(reading.accounts.first?.valueText, "لم يُعرف رصيدها بعد")
        XCTAssertEqual(reading.home.basis.inAccountMinor, 0, "unknown source metadata never enters cash")
        XCTAssertEqual(try RecordBridge.all(ModelContext(container)), before)
        let known = Account(); known.name = "رصيد مؤكد"; known.balanceMinor = 100_000; known.balanceAt = .now
        context.insert(known); try context.save()
        let mixed = try service.loadBasis()
        XCTAssertTrue(mixed.home.hasKnownBalance); XCTAssertEqual(mixed.home.unknownBalanceCount, 1)
        XCTAssertEqual(mixed.home.basis.inAccountMinor, 100_000, "cash contains only the hand-authored known checkpoint")
        XCTAssertEqual(mixed.accounts.count, 2)
        XCTAssertNil(mixed.accounts.first { $0.title == "رصيد مؤكد" }?.valueText)
    }
}
