import CoreLocation
import Foundation
import MapKit

/// Owner, 30 Oct 2026: «استخدم موقعي» fills the city form once. The position is read one time, turned into a city name,
/// time zone and country by the system geocoder, and thrown away: only the city the reader confirms is saved.
// Core Location calls the delegate on the RunLoop that created the manager, here the main RunLoop.
@MainActor final class CityLocator: NSObject, ObservableObject, @preconcurrency CLLocationManagerDelegate {
    struct Found { let name: String; let lat: Double; let lon: Double; let tz: String; let country: String; let currency: String }
    @Published var working = false
    @Published var message: String?
    /// Location permission was refused for Madar and can be changed in device Settings.
    @Published var needsSettings = false
    private let makeManager: () -> CLLocationManager
    private let geocode: @MainActor (CLLocation) async throws -> Found?
    private var manager: CLLocationManager?
    private var onFound: ((Found) -> Void)?
    private var requested = false
    private var timeout: Task<Void, Never>?
    private(set) var geocodingTask: Task<Void, Never>?
    private static let deniedText = "الموقع مغلق لمدار. اختر مدينتك من القائمة، أو فعّل الموقع لمدار من إعدادات الجهاز."

    init(makeManager: @escaping () -> CLLocationManager = CLLocationManager.init,
         geocode: (@MainActor (CLLocation) async throws -> Found?)? = nil) {
        self.makeManager = makeManager
        self.geocode = geocode ?? Self.resolve
        super.init()
    }

    func start(_ onFound: @escaping (Found) -> Void) {
        guard !working else { return }
        self.onFound = onFound; message = nil; needsSettings = false; working = true; requested = false
        let manager = makeManager()
        self.manager = manager
        manager.delegate = self
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .denied, .restricted: fail(Self.deniedText)
        default: requestLocation(using: manager)
        }
    }

    func cancel() {
        manager?.delegate = nil
        manager?.stopUpdatingLocation()
        manager = nil
        onFound = nil
        timeout?.cancel()
        timeout = nil
        geocodingTask?.cancel()
        geocodingTask = nil
        working = false
    }

    /// The timeout covers both the position and the city name. Permission prompts run outside that window.
    private func requestLocation(using manager: CLLocationManager) {
        guard !requested else { return }
        requested = true
        timeout = Task { [weak self] in
            do { try await Task.sleep(for: .seconds(20)) } catch { return }
            guard !Task.isCancelled else { return }
            self?.fail("لم أتمكّن من معرفة مدينتك؛ اخترها من القائمة.")
        }
        manager.requestLocation()
    }

    private func fail(_ text: String) {
        cancel()
        message = text
        needsSettings = text == Self.deniedText
    }

    func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        guard self.manager === manager else { return }
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: requestLocation(using: manager)
        case .denied, .restricted: fail(Self.deniedText)
        default: break
        }
    }

    func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {
        guard self.manager === manager, geocodingTask == nil else { return }
        fail("تعذّر معرفة موقعك الآن؛ اختر مدينتك من القائمة.")
    }

    func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard self.manager === manager, geocodingTask == nil, let location = locations.last else { return }
        geocodingTask = Task { [weak self, geocode] in
            do {
                let found = try await geocode(location)
                guard !Task.isCancelled, let self else { return }
                guard let found else {
                    self.fail("لم أعرف مدينة هذا الموقع؛ اختر مدينتك من القائمة.")
                    return
                }
                let completion = self.onFound
                self.cancel()
                completion?(found)
            } catch {
                guard !Task.isCancelled else { return }
                self?.fail("تعذّر معرفة مدينتك الآن؛ اختر من القائمة.")
            }
        }
    }

    private static func resolve(_ location: CLLocation) async throws -> Found? {
        guard let request = MKReverseGeocodingRequest(location: location),
              let place = try await request.mapItems.first,
              let code = place.addressRepresentations?.region?.identifier,
              let zone = place.timeZone else { return nil }
        let name = place.addressRepresentations?.cityName ?? place.name ?? ""
        let currency = Locale(identifier: "en_" + code).currency?.identifier ?? ""
        return Found(name: name, lat: location.coordinate.latitude, lon: location.coordinate.longitude,
                     tz: zone.identifier, country: code, currency: currency)
    }
}
