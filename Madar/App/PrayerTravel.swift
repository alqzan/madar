import CoreLocation
import MadarCore
import MadarDesign
import MadarPrayer
import SwiftUI

/// RP7 · M1-F02. The device location is read once, only to compare it with the home city. Nothing is stored or sent.
struct TravelFix: Equatable {
    let place: ActivePlace
    let city: String
    let country: String
}

@MainActor @Observable
final class TravelLocator: NSObject, CLLocationManagerDelegate {
    private(set) var fix: TravelFix?
    private let manager = CLLocationManager()
    private let geocoder = CLGeocoder()

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    func refresh() {
        #if DEBUG
        // UI stores use a deterministic place instead of raising an OS permission
        // alert over the app. Travel-specific tests can inject their own place.
        if ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"] != nil {
            let raw = ProcessInfo.processInfo.environment["MADAR_UI_TRAVEL_FIX"]
                ?? "24.7136,46.6753,الرياض,SA,Asia/Riyadh"
            let parts = raw.split(separator: ",").map(String.init)
            if parts.count == 5, let lat = Double(parts[0]), let lon = Double(parts[1]), let place = try? ActivePlace(latitude: lat, longitude: lon, timeZoneID: parts[4]) {
                fix = TravelFix(place: place, city: parts[2], country: parts[3])
            }
            return
        }
        #endif
        switch manager.authorizationStatus {
        case .notDetermined: manager.requestWhenInUseAuthorization()
        case .authorizedWhenInUse, .authorizedAlways: manager.requestLocation()
        default: break
        }
    }

    nonisolated func locationManagerDidChangeAuthorization(_ manager: CLLocationManager) {
        if manager.authorizationStatus == .authorizedWhenInUse || manager.authorizationStatus == .authorizedAlways { manager.requestLocation() }
    }
    nonisolated func locationManager(_ manager: CLLocationManager, didFailWithError error: Error) {}
    nonisolated func locationManager(_ manager: CLLocationManager, didUpdateLocations locations: [CLLocation]) {
        guard let location = locations.last else { return }
        Task { @MainActor in await resolve(location) }
    }

    private func resolve(_ location: CLLocation) async {
        guard let mark = try? await geocoder.reverseGeocodeLocation(location).first,
              let zone = mark.timeZone?.identifier, let country = mark.isoCountryCode,
              let place = try? ActivePlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timeZoneID: zone) else { return }
        fix = TravelFix(place: place, city: mark.locality ?? mark.administrativeArea ?? mark.name ?? country, country: country)
    }
}

enum PrayerTravelCopy {
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
    private static let declinedKey = "prayer.travelDeclinedAt"
    /// «لا، أنا مقيم هنا» is remembered on this device until the owner is more than the threshold away from that place.
    static func declined(near place: ActivePlace, thresholdKm: Double) -> Bool {
        guard let raw = UserDefaults.standard.string(forKey: declinedKey) else { return false }
        let parts = raw.split(separator: ",").compactMap { Double($0) }
        guard parts.count == 2, let other = try? ActivePlace(latitude: parts[0], longitude: parts[1], timeZoneID: place.timeZoneID) else { return false }
        return TravelRule.distanceKm(from: other, to: place) <= thresholdKm
    }
    static func decline(_ place: ActivePlace) { UserDefaults.standard.set("\(place.latitude),\(place.longitude)", forKey: declinedKey) }
    static func clearDecline() { UserDefaults.standard.removeObject(forKey: declinedKey) }
}

/// The pill under the header: «مسافر · جدة · قصرٌ وجمع» on a trip, «خارج مدينتك» until the one question is answered.
struct PrayerTravelPill: View {
    let text: String
    let action: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Image(systemName: "diamond.fill").font(.system(size: 11))
                Text(text).font(PrayerHomeType.strong)
            }
            .foregroundStyle(theme.color("accentText"))
            .padding(.horizontal, 22).frame(minHeight: 44)
            .background(theme.color("goldSoft"), in: .capsule)
            .overlay { Capsule().stroke(theme.line, lineWidth: 1) }
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("prayer-travel-pill")
    }
}

private struct TravelPrimaryButton: View {
    let title: String
    let id: String
    var busy = false
    let action: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: action) {
            Text(title).font(PrayerHomeType.strong).foregroundStyle(theme.background)
                .frame(maxWidth: .infinity, minHeight: 52).background(theme.ink, in: .capsule)
        }
        .buttonStyle(.plain).disabled(busy).accessibilityIdentifier(id)
    }
}
private struct TravelSecondaryButton: View {
    let title: String
    let id: String
    let action: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: action) {
            Text(title).font(PrayerHomeType.strong)
                .frame(maxWidth: .infinity, minHeight: 52).overlay { Capsule().stroke(theme.ink.opacity(0.18), lineWidth: 1) }
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
}

/// The one question at the start of a trip (RP7), with the local method suggested (RP4).
struct PrayerTravelQuestionSheet: View {
    let session: AppSession
    let fix: TravelFix
    let homeKm: Double
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var method: PrayerCalculationMethod

    init(session: AppSession, fix: TravelFix, homeKm: Double, finished: @escaping () -> Void) {
        self.session = session; self.fix = fix; self.homeKm = homeKm; self.finished = finished
        _method = State(initialValue: TravelRule.suggestedMethod(country: fix.country))
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("هل أنت مسافر؟").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text("أنت الآن في \(fix.city)، بعيدًا عن مدينتك. إن كنت مسافرًا حسبنا المواقيت هنا، وفتحنا لك القصر والجمع.")
                    .font(PrayerHomeType.lead).foregroundStyle(theme.secondaryInk)
                PrayerPaperCard {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("طريقة الحساب في \(fix.city)").font(PrayerHomeType.strong)
                        Text("اقترحنا طريقة البلد. تُطبَّق على هذه الرحلة فقط، وتعود مدينتك إلى طريقتها بعدها.")
                            .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        Picker("الطريقة", selection: $method) {
                            ForEach(PrayerCalculationMethod.allCases, id: \.self) { Text(PrayerTravelCopy.methodName($0)).tag($0) }
                        }
                        .pickerStyle(.menu).accessibilityIdentifier("prayer-travel-method")
                    }
                }
                TravelPrimaryButton(title: "نعم، أنا مسافر", id: "prayer-travel-yes", busy: session.prayerWriteInProgress) {
                    session.startPrayerTrip(city: fix.city, country: fix.country, place: fix.place, homeKm: homeKm, method: method) { if $0 { finished() } }
                }
                TravelSecondaryButton(title: "لا، أنا مقيم هنا", id: "prayer-travel-no") {
                    PrayerTravelCopy.decline(fix.place); finished()
                }
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
    }
}

/// The active trip: its method, place and the way to end it.
struct PrayerTripSheet: View {
    let session: AppSession
    let trip: PrayerTrip
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("رحلتك إلى \(trip.city)").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text("المواقيت محسوبة بطريقة \(PrayerTravelCopy.methodName(PrayerCalculationMethod(rawValue: session.string("salah.tripMethod")) ?? .ummAlQura)). تبقى الصلوات التي سجّلتها كما هي، ويعود الحساب لمدينتك من الفرض التالي.")
                    .font(PrayerHomeType.lead).foregroundStyle(theme.secondaryInk)
                TravelPrimaryButton(title: "أنهِ الرحلة", id: "prayer-end-trip-confirm", busy: session.prayerWriteInProgress) {
                    session.endPrayerTrip(trip.id) { if $0 { PrayerTravelCopy.clearDecline(); finished() } }
                }
                TravelSecondaryButton(title: "أبقِ الرحلة", id: "prayer-trip-keep", action: finished)
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium])
    }
}

/// Shorten and combine (RP7): the owner says what they prayed; nothing is paired before that.
struct PrayerTravelPairSheet: View {
    let session: AppSession
    let day: GregorianDay
    let pair: PrayerPair
    let alone: () -> Void
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var status: PrayerStoredStatus = .jamaah
    @State private var mode: PrayerPairMode = .takhir
    @State private var shortened = true

    private var title: String { pair == .dhuhrAsr ? "الظهر والعصر" : "المغرب والعشاء" }
    private func chip(_ label: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(PrayerHomeType.strong)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background(on ? theme.color("goldSoft") : .clear, in: .capsule)
                .overlay { Capsule().stroke(on ? theme.line : theme.ink.opacity(0.14), lineWidth: 1) }
        }
        .buttonStyle(.plain).accessibilityIdentifier(id)
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("سجّل \(title) معًا").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                Text("يُسجَّل الفرضان في يوم الصلاة نفسه. اختيارك يصف ما صلّيته.").font(PrayerHomeType.lead).foregroundStyle(theme.secondaryInk)
                HStack(spacing: 10) {
                    chip("في جماعة", on: status == .jamaah, id: "prayer-pair-jamaah") { status = .jamaah }
                    chip("وحدي", on: status == .alone, id: "prayer-pair-alone") { status = .alone }
                }
                HStack(spacing: 10) {
                    chip("جمع تقديم", on: mode == .taqdim, id: "prayer-pair-taqdim") { mode = .taqdim }
                    chip("جمع تأخير", on: mode == .takhir, id: "prayer-pair-takhir") { mode = .takhir }
                }
                Toggle(pair == .dhuhrAsr ? "قصر الظهر والعصر" : "قصر العشاء وحدها", isOn: $shortened)
                    .font(PrayerHomeType.body).tint(theme.accent).accessibilityIdentifier("prayer-pair-shorten")
                TravelPrimaryButton(title: "احفظ الصلاتين", id: "prayer-pair-save", busy: session.prayerWriteInProgress) {
                    session.logPrayerPair(day: day, pair: pair, status: status, shortened: shortened, mode: mode) { if $0 { finished() } }
                }
                TravelSecondaryButton(title: "سجّلها وحدها", id: "prayer-pair-single", action: alone)
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
    }
}
