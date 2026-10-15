import XCTest
import SwiftData
import MadarData
@testable import Madar

@MainActor final class QuranAmountIntegrationTests: XCTestCase {
    func testAyahAmountsPreviewLevelsWithoutPersistingChoices() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "QuranAmounts-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root), context = ModelContext(container)
        _ = try SettingsStore(context: context).stage(["core.dayStart": .string("midnight"), "quran.restDay": .string("none")])
        let now = ISO8601DateFormatter().date(from: "2026-10-15T15:00:00+03:00")!
        let plan = HifzPlan(); plan.unit = "ayah"; plan.amount = 2; plan.activeFrom = now; context.insert(plan); try context.save()
        let app = try AppSession(container: container, groupDirectory: root), service = AppQuranService(session: app, clock: { now })
        let state = try await service.load()
        XCTAssertEqual(state.hifzAmounts.mapValues(plain), ["simple": "آية واحدة", "medium": "آيتان", "deep": "٣ آيات", "max": "٤ آيات"])
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<QuranDayState>()), 0)
        XCTAssertEqual(app.string("quran.hifzLevel"), "medium")
        plan.unit = "page"; plan.amount = 1; try context.save()
        let pageState = try await service.load()
        XCTAssertEqual(pageState.hifzAmounts["medium"], "صفحة")
    }
    private func plain(_ text: String) -> String { String(text.unicodeScalars.filter { !(0x2066...0x2069).contains($0.value) }) }
    func testPhysicalAmountsUseArabicPlurals() {
        XCTAssertEqual(QuranMemorizationCopy.pages(2, digits: .init()), "صفحتان")
        XCTAssertEqual(plain(QuranMemorizationCopy.lines(5, digits: .init())), "٥ أسطر")
        XCTAssertEqual(plain(QuranMemorizationCopy.lines(15, digits: .init())), "١٥ سطرًا")
    }
}
