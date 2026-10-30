import XCTest
@testable import Madar

/// Owner, 30 Oct: the city list fills the five fields «مدينة أخرى» used to ask for, so every entry must be usable as typed.
final class CityCatalogTests: XCTestCase {
    func testEveryCityHasValidFields() {
        let regions = Set(Locale.Region.isoRegions.map(\.identifier)), currencies = Set(Locale.Currency.isoCurrencies.map(\.identifier))
        XCTAssertGreaterThan(CityCatalog.all.count, 40)
        XCTAssertEqual(Set(CityCatalog.all.map(\.id)).count, CityCatalog.all.count, "names are unique")
        for city in CityCatalog.all {
            XCTAssertTrue((-90...90).contains(city.lat) && (-180...180).contains(city.lon), city.name)
            XCTAssertNotNil(TimeZone(identifier: city.tz), city.name)
            XCTAssertTrue(regions.contains(city.country), city.name)
            XCTAssertTrue(currencies.contains(city.currency), city.name)
        }
    }

    func testSearchIgnoresHamzaMarksAndTaMarbuta() {
        XCTAssertEqual(CityCatalog.search("ابها").map(\.name), ["أبها"])
        XCTAssertEqual(CityCatalog.search("القاهره").map(\.name), ["القاهرة"])
        XCTAssertEqual(CityCatalog.search("  دُبي ").map(\.name), ["دبي"])
        XCTAssertEqual(CityCatalog.search("مكه").map(\.name), ["مكة المكرمة"])
        XCTAssertTrue(CityCatalog.search("").isEmpty)
        XCTAssertTrue(CityCatalog.search("zzz").isEmpty)
    }

    func testNamesThatBeginWithTheLettersComeFirst() {
        // «الد» begins «الدمام»، «الدوحة»، «الدار البيضاء» and sits inside none of the others' starts.
        let names = CityCatalog.search("الد").map(\.name)
        XCTAssertEqual(Set(names), ["الدمام", "الدوحة", "الدار البيضاء"])
        // «ان» begins «انقره» ("أنقرة") and sits inside «الاسكندريه»/«الجزائر»? it does not, so only the first matches by prefix.
        XCTAssertEqual(CityCatalog.search("ان").first?.name, "أنقرة")
    }
}
