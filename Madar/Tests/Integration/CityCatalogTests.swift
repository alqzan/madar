import CoreLocation
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

@MainActor final class CityLocatorTests: XCTestCase {
    func testCancelledLookupCannotFinishOrInterruptTheNextLookup() async throws {
        let firstManager = StubCityLocationManager()
        let secondManager = StubCityLocationManager()
        var managers = [firstManager, secondManager]
        let locator = CityLocator(makeManager: { managers.removeFirst() }) { location in
            CityLocator.Found(name: String(location.coordinate.latitude), lat: location.coordinate.latitude,
                              lon: location.coordinate.longitude, tz: "Asia/Riyadh", country: "SA", currency: "SAR")
        }
        let firstLocation = CLLocation(latitude: 24, longitude: 46)
        let secondLocation = CLLocation(latitude: 21.4225, longitude: 39.8262)
        var accepted: [Double] = []

        locator.start { accepted += [$0.lat, $0.lon] }
        locator.locationManager(firstManager, didUpdateLocations: [firstLocation])
        let cancelledLookup = try XCTUnwrap(locator.geocodingTask)
        XCTAssertTrue(locator.working)
        locator.cancel()
        XCTAssertFalse(locator.working)

        locator.start { accepted += [$0.lat, $0.lon] }
        locator.locationManager(firstManager, didFailWithError: CLError(.locationUnknown))
        locator.locationManager(firstManager, didUpdateLocations: [firstLocation])
        await cancelledLookup.value
        XCTAssertNil(locator.geocodingTask)
        XCTAssertTrue(locator.working)
        XCTAssertTrue(accepted.isEmpty)

        locator.locationManager(secondManager, didUpdateLocations: [secondLocation])
        let validLookup = try XCTUnwrap(locator.geocodingTask)
        await validLookup.value
        XCTAssertEqual(accepted, [21.42, 39.83])
        XCTAssertFalse(locator.working)
    }
}

private final class StubCityLocationManager: CLLocationManager {
    override var authorizationStatus: CLAuthorizationStatus { .authorizedWhenInUse }
    override func requestLocation() {}
    override func stopUpdatingLocation() {}
}
