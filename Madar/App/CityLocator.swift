import CoreLocation
import Foundation
import MapKit

/// Owner, 30 Oct 2026: «استخدم موقعي» fills the city form once. The position is read one time, turned into a city name,
/// time zone and country by the system geocoder, and thrown away: only the city the reader confirms is saved.
@MainActor final class CityLocator: NSObject, ObservableObject, CLLocationManagerDelegate {
    struct Found { let name: String; let lat: Double; let lon: Double; let tz: String; let country: String; let currency: String }
    @Published var working = false
    @Published var message: String?
    private let manager = CLLocationManager()
    private var onFound: ((Found) -> Void)?
    private var requested = false
    private var timeout: Task<Void, Never>?
    private static let deniedText = "الموقع مغلق لمدار؛ اختر مدينتك من القائمة، أو فعّل الموقع لمدار من إعدادات الآيفون."

    func start(_ onFound: @escaping (Found) -> Void) {
        guard !working else { return }
        self.onFound = onFound; message = nil; working = true; requested = false
        // A position that never comes (indoors, no signal) ends with a sentence, not a button stuck on «أبحث».
        timeout = Task { try? await Task.sleep(nanoseconds: 20_000_000_000); if !Task.isCancelled, self.working { self.fail("لم أصل إلى موقعك؛ اختر مدينتك من القائمة.") } }
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: fail(Self.deniedText)
        default: requested = true; manager.requestLocation()
        }
    }

    private func fail(_ text: String) { working = false; message = text; onFound = nil; timeout?.cancel() }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        let status = manager.authorizationStatus
        Task { @MainActor in
            guard self.working, !self.requested else { return }
            if status == .authorizedWhenInUse || status == .authorizedAlways { self.requested = true; self.manager.requestLocation() }
            else if status == .denied || status == .restricted { self.fail(Self.deniedText) }
        }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        Task { @MainActor in self.fail("تعذّر معرفة موقعك الآن؛ اختر مدينتك من القائمة.") }
    }

    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in
            // One position is enough: a late second fix never geocodes again over a filled form.
            guard self.working else { return }
            self.working = false; self.timeout?.cancel()
            do {
                guard let request = MKReverseGeocodingRequest(location: location) else {
                    self.fail("لم أعرف مدينة هذا الموقع؛ اختر مدينتك من القائمة."); return
                }
                let items = try await request.mapItems
                guard let place = items.first,
                      let code = place.addressRepresentations?.region?.identifier,
                      let zone = place.timeZone else {
                    self.fail("لم أعرف مدينة هذا الموقع؛ اختر مدينتك من القائمة."); return
                }
                let name = place.addressRepresentations?.cityName ?? place.name ?? ""
                let currency = Locale(identifier: "en_" + code).currency?.identifier ?? ""
                let found = Found(name: name, lat: location.coordinate.latitude, lon: location.coordinate.longitude, tz: zone.identifier, country: code, currency: currency)
                self.onFound?(found); self.onFound = nil
            } catch { self.fail("تعذّر معرفة مدينتك الآن؛ اختر من القائمة.") }
        }
    }
}
