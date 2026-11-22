import CoreLocation
import MapKit
import MadarCore
import MadarDesign
import MadarPrayer
import SwiftData
import SwiftUI

/// Travel lives in the lobby since the prayer room left (owner plan, 17 Nov 2026: «يبقى… الموقع والسفر»).
/// RP7: travel is detected, never assumed; the user is asked once. The device location is read only to
/// compare it with the home city; nothing about it is stored until the user starts a trip.
struct TravelFix: Equatable {
    let place: ActivePlace
    let city: String
    let country: String
}

enum TravelRule {
    /// Owner decision, 13 Oct 2026: the distance is counted from the city's edge, approximated as this radius.
    static let homeRadiusKm = 25.0
    static func distanceKm(from a: ActivePlace, to b: ActivePlace) -> Double {
        let r = 6371.0, p1 = a.latitude * .pi / 180, p2 = b.latitude * .pi / 180
        let dp = p2 - p1, dl = (b.longitude - a.longitude) * .pi / 180
        let h = sin(dp / 2) * sin(dp / 2) + cos(p1) * cos(p2) * sin(dl / 2) * sin(dl / 2)
        return 2 * r * asin(min(1, sqrt(h)))
    }
    /// `thresholdKm` is `core.travelKm` (default 80), measured beyond the home city's edge.
    static func isAway(home: ActivePlace, current: ActivePlace, thresholdKm: Double) -> Bool {
        distanceKm(from: home, to: current) - homeRadiusKm > thresholdKm
    }
    /// RP4: the local method suggested when the trip starts.
    static func suggestedMethod(country: String) -> PrayerCalculationMethod {
        switch country.uppercased() {
        case "SA": .ummAlQura
        case "TR": .turkey
        case "US", "CA": .isna
        case "AE": .dubai
        case "KW": .kuwait
        case "QA": .qatar
        case "EG": .egyptian
        default: .mwl
        }
    }
    static func methodName(_ method: PrayerCalculationMethod) -> String {
        switch method {
        case .ummAlQura: "أم القرى"
        case .mwl: "رابطة العالم الإسلامي"
        case .egyptian: "الهيئة المصرية"
        case .turkey: "تركيا (الديانت)"
        case .isna: "أمريكا الشمالية (ISNA)"
        case .dubai: "دبي"
        case .kuwait: "الكويت"
        case .qatar: "قطر"
        }
    }
    private static var declinedKey: String {
        #if DEBUG
        // Each isolated UI-test store keeps its own answer; the device-wide one would leak into the next test.
        if let store = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] { return "prayer.travelDeclinedAt." + store }
        #endif
        return "prayer.travelDeclinedAt"
    }
    /// «لا، أنا مقيم هنا» is remembered on this device until the user is more than the threshold away from that place.
    static func declined(near place: ActivePlace, thresholdKm: Double) -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: declinedKey) else { return false }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, let other = try? ActivePlace(latitude: parts[0], longitude: parts[1], timeZoneID: place.timeZoneID) else { return false }
        return distanceKm(from: other, to: place) <= thresholdKm
    }
    static func decline(_ place: ActivePlace) { UserDefaults.standard.set("\(place.latitude),\(place.longitude)", forKey: declinedKey) }
    static func clearDecline() { UserDefaults.standard.removeObject(forKey: declinedKey) }
}

@MainActor @Observable
final class TravelLocator: NSObject, CLLocationManagerDelegate {
    private(set) var fix: TravelFix?
    private let manager = CLLocationManager()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// Reads the place once. The OS permission question is never raised here: it comes with «استخدم موقعي» in the city form.
    func refresh() {
        #if DEBUG
        if ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil {
            let raw = ProcessInfo.processInfo.environment["MADAR_UI_TRAVEL_FIX"] ?? "24.7136,46.6753,الرياض,SA,Asia/Riyadh"
            let parts = raw.split(separator: ",").map(String.init)
            if parts.count == 5, let lat = Double(parts[0]), let lon = Double(parts[1]), let place = try? ActivePlace(latitude: lat, longitude: lon, timeZoneID: parts[4]) {
                fix = TravelFix(place: place, city: parts[2], country: parts[3])
            }
            return
        }
        #endif
        switch manager.authorizationStatus {
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await resolve(location) }
    }

    private func resolve(_ location: CLLocation) async {
        guard let request = MKReverseGeocodingRequest(location: location),
              let mark = try? await request.mapItems.first,
              let zone = mark.timeZone?.identifier,
              let country = mark.addressRepresentations?.region?.identifier,
              let place = try? ActivePlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timeZoneID: zone) else { return }
        fix = TravelFix(place: place, city: mark.addressRepresentations?.cityName ?? mark.name ?? country, country: country)
    }
}

/// What the lobby knows about travel: the open trip (read once per appearance, not every minute) and the phone's place.
@MainActor @Observable
final class BahwTravelModel {
    let locator = TravelLocator()
    private(set) var trip: PrayerTrip?
    private(set) var legs: [(city: String, country: String, start: Date, end: Date?)] = []
    /// The «مقيم هنا» answer lives in device defaults, which SwiftUI does not observe; each refresh re-reads it.
    private var answerVersion = 0

    func refresh(_ session: AppSession) {
        answerVersion &+= 1
        let repository = try? PrayerRepository(context: ModelContext(session.container))
        trip = repository?.activeTrip(at: session.prayerNow())
        legs = trip.flatMap { repository?.journeyLegs(of: $0.id) } ?? []
        if detects(session) { locator.refresh() }
    }
    private func detects(_ session: AppSession) -> Bool { session.string("core.travelMode") != "manual" }
    func thresholdKm(_ session: AppSession) -> Double {
        if case .number(let km) = session.values["core.travelKm"] { km } else { 80 }
    }
    /// Away from home, not on a trip and not already answered «لا، أنا مقيم هنا» for this place.
    func awayFix(_ session: AppSession) -> TravelFix? {
        _ = answerVersion
        guard detects(session), trip == nil, let fix = locator.fix,
              TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: thresholdKm(session)),
              !TravelRule.declined(near: fix.place, thresholdKm: thresholdKm(session)) else { return nil }
        return fix
    }
    /// The line under the lobby header: «خارج مدينتك؟» until answered, «مسافر في جدة» on a trip, nothing at home.
    func pillText(_ session: AppSession) -> String? {
        if let trip {
            let km = thresholdKm(session)
            if let fix = locator.fix, !TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: km) { return "عدتَ إلى مدينتك؟" }
            if let fix = locator.fix, fix.city != trip.city, TravelRule.distanceKm(from: trip.place, to: fix.place) > km { return "وصلت إلى " + fix.city + "؟" }
            return "مسافر في " + (legs.count > 1 ? legs.map(\.city).joined(separator: " ← ") : trip.city)
        }
        return awayFix(session) != nil ? "خارج مدينتك؟" : nil
    }
}

struct BahwTravelPill: View {
    let text: String
    let onTrip: Bool
    let action: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: onTrip ? "airplane" : "location").font(.system(size: 13, weight: .semibold))
                Text(text).font(MadarTypography.caption().bold())
                Image(systemName: "chevron.backward").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryInk)
            }
            .padding(.horizontal, 18).frame(minHeight: 44)
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.madarPlain)
        .accessibilityIdentifier("bahw-travel-pill")
    }
}

private struct TravelButton: View {
    let title: String
    let id: String
    var primary = true
    var busy = false
    let action: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: action) {
            Text(title).font(MadarTypography.section())
                .frame(maxWidth: .infinity, minHeight: 52)
                .foregroundStyle(primary ? theme.onAccent : theme.ink)
                .background(primary ? theme.accentFill : .clear, in: .capsule)
                .glassEffect(primary ? .identity : .regular.interactive(), in: .capsule)
                .contentShape(Capsule())
        }
        .buttonStyle(.madarPlain).disabled(busy).accessibilityIdentifier(id)
    }
}

/// The one question at the start of a trip (RP7), with the local method suggested (RP4).
struct BahwTravelQuestionSheet: View {
    let session: AppSession
    let fix: TravelFix
    let homeKm: Double
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var method: PrayerCalculationMethod
    @State private var starting = false

    init(session: AppSession, fix: TravelFix, homeKm: Double, finished: @escaping () -> Void) {
        self.session = session; self.fix = fix; self.homeKm = homeKm; self.finished = finished
        _method = State(initialValue: TravelRule.suggestedMethod(country: fix.country))
    }
    /// What a trip changes, in the user's terms; home-only habits are named only when that setting is on.
    private var effects: String {
        var parts = ["نحسب المواقيت هنا", "ونجمع مصروفك في ميزانية الرحلة"]
        if session.bool("bahw.travelFreezesHome") { parts.insert("وتتوقف عادات البيت حتى تعود", at: 1) }
        return "إن كنت مسافرًا " + parts.joined(separator: "، ") + "."
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("هل أنت مسافر؟").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text("أنت الآن في \(fix.city)، على بعد \(AppBahwService(session: session).digits.string(Int(homeKm.rounded()))) كم من مدينتك. " + effects)
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                VStack(alignment: .leading, spacing: 8) {
                    Text("طريقة حساب المواقيت في \(fix.city)").font(MadarTypography.section())
                    Text("اقترحنا طريقة البلد، وتعود مدينتك إلى طريقتها بعد الرحلة.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    Picker("الطريقة", selection: $method) {
                        ForEach(PrayerCalculationMethod.allCases, id: \.self) { Text(TravelRule.methodName($0)).tag($0) }
                    }
                    .pickerStyle(.menu).disabled(starting).accessibilityIdentifier("bahw-travel-method")
                }
                .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 20))
                TravelButton(title: "نعم، أنا مسافر", id: "bahw-travel-yes", busy: starting || session.tripWriteInProgress) {
                    guard !starting else { return }
                    starting = true
                    session.startTrip(city: fix.city, country: fix.country, place: fix.place, homeKm: homeKm, method: method) { succeeded in
                        starting = false
                        if succeeded { finished() }
                    }
                }
                TravelButton(title: "لا، أنا مقيم هنا", id: "bahw-travel-no", primary: false) {
                    TravelRule.decline(fix.place); finished()
                }.disabled(starting)
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
        .madarSheetLock(saving: starting)
    }
}

/// The open trip: where it goes, the next stop when the phone is elsewhere, and the way to end it.
struct BahwTripSheet: View {
    let session: AppSession
    let trip: PrayerTrip
    let legs: [(city: String, country: String, start: Date, end: Date?)]
    var fix: TravelFix?
    var thresholdKm: Double = 80
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme

    private var nextStop: TravelFix? {
        guard let fix, let current = legs.last ?? .some((trip.city, "", trip.start, nil)),
              fix.city != current.city || fix.country != current.country,
              TravelRule.distanceKm(from: trip.place, to: fix.place) > thresholdKm,
              TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: thresholdKm) else { return nil }
        return fix
    }
    private var backHome: Bool {
        guard let fix else { return false }
        return !TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: thresholdKm)
    }
    private var since: GregorianDay { GregorianDay.containing(legs.first?.start ?? trip.start, in: trip.place.timeZone) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(legs.count > 1 ? "رحلتك" : "رحلتك إلى \(trip.city)").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                if legs.count > 1 {
                    Text(legs.map(\.city).joined(separator: " ← ")).font(MadarTypography.section()).foregroundStyle(theme.accent)
                        .accessibilityIdentifier("bahw-trip-legs")
                }
                HStack(spacing: 6) {
                    Text("منذ").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    MadarDateLabel(session.dateLabels(since)).foregroundStyle(theme.secondaryInk)
                }
                if let stop = nextStop {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("أنت الآن في \(stop.city)").font(MadarTypography.section())
                        Text("أضفها محطةً في رحلتك نفسها: تُحسب المواقيت هنا، وتجمع ميزانية الرحلة مصروف المدينتين.")
                            .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                        TravelButton(title: "أضف \(stop.city) إلى رحلتك", id: "bahw-trip-continue", busy: session.tripWriteInProgress) {
                            session.continueTrip(city: stop.city, country: stop.country, place: stop.place,
                                                 homeKm: max(0, TravelRule.distanceKm(from: session.activePlace, to: stop.place) - TravelRule.homeRadiusKm)) { if $0 { finished() } }
                        }
                    }
                    .padding(16).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: .rect(cornerRadius: 20))
                }
                Text("المواقيت محسوبة بطريقة \(TravelRule.methodName(PrayerCalculationMethod(rawValue: session.string("salah.tripMethod")) ?? .ummAlQura))، ويعود الحساب لمدينتك حين تنهي الرحلة.")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                TravelButton(title: backHome ? "عدتُ، أنهِ الرحلة" : "أنهِ الرحلة", id: "bahw-trip-end", busy: session.tripWriteInProgress) {
                    // Ending the trip while still far away means «I live here now»: the question does not come straight back.
                    session.endTrip(trip.id) { ended in
                        guard ended else { return }
                        if let fix, !backHome { TravelRule.decline(fix.place) } else { TravelRule.clearDecline() }
                        finished()
                    }
                }
                TravelButton(title: "أبقِ الرحلة", id: "bahw-trip-keep", primary: false, action: finished)
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
        .madarSheetLock(saving: session.tripWriteInProgress)
    }
}
