import CoreLocation

extension CLAuthorizationStatus {
    /// macOS grants location to the app as a whole; "when in use" there is `authorizedAlways`.
    static var authorizedWhenInUse: CLAuthorizationStatus { .authorizedAlways }
}
