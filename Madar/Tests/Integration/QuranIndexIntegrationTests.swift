import XCTest
import SwiftData
import MadarData
import MadarCommands
@testable import Madar
@MainActor final class QuranIndexIntegrationTests:XCTestCase {
    func testIndexUsesEachVerifiedUnitBoundaryAndNoFabricatedCoverage() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"QuranIndex-\(UUID())"),container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data"))
        let app=try AppSession(container:container,groupDirectory:root),service=AppQuranService(session:app)
        for (unit,count) in [(QuranUIIndexUnit.surah,114),(.ayah,6236),(.juz,30),(.hizb,60),(.page,604)] {
            let items=try await service.index(unit);XCTAssertEqual(items.count,count);XCTAssertTrue(items.allSatisfy {$0.fraction == 0 && !$0.memorized && !$0.reviewed})
        }
        let juz=try await service.index(.juz),hizb=try await service.index(.hizb)
        XCTAssertEqual(juz[3].firstPage,62);XCTAssertEqual(hizb[1].firstPage,11);XCTAssertEqual(hizb[59].firstPage,591)
        XCTAssertEqual(try service.snapshot().sessions.count,0)
    }
}
