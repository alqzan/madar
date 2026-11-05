import CoreLocation
import MapKit
import MadarCore
import MadarDesign
import MadarPrayer
import SwiftData
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

    override init() {
        super.init()
        manager.delegate = self
        manager.desiredAccuracy = kCLLocationAccuracyKilometer
    }

    /// True until the user has answered the OS question once; the prayer screen never raises it by itself.
    var canAskForLocation: Bool { manager.authorizationStatus == .notDetermined }
    func askForLocation() { manager.requestWhenInUseAuthorization() }

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
        // The OS question is never raised from the prayer screen itself: it comes with «استخدم موقعي» in the city form, where its reason is clear.
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
        guard let request = MKReverseGeocodingRequest(location: location),
              let mark = try? await request.mapItems.first,
              let zone = mark.timeZone?.identifier,
              let country = mark.addressRepresentations?.region?.identifier,
              let place = try? ActivePlace(latitude: location.coordinate.latitude, longitude: location.coordinate.longitude, timeZoneID: zone) else { return }
        fix = TravelFix(place: place, city: mark.addressRepresentations?.cityName ?? mark.name ?? country, country: country)
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
            .glassEffect(.regular.interactive(), in: .capsule)
            .contentShape(Capsule())
        }
        .buttonStyle(.madarPlain)
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
        .buttonStyle(.madarPlain).disabled(busy).accessibilityIdentifier(id)
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
                .frame(maxWidth: .infinity, minHeight: 52).glassEffect(.regular.interactive(), in: .capsule)
        }
        .buttonStyle(.madarPlain).accessibilityIdentifier(id)
    }
}

/// The one question at the start of a trip (RP7), with the local method suggested (RP4).
struct PrayerTravelQuestionSheet: View {
    let session: AppSession
    let fix: TravelFix
    let homeKm: Double
    let finished: () -> Void
    let rootDraftChanged: (UUID, Bool) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var method: PrayerCalculationMethod
    @State private var rootBlockerID = UUID()
    @State private var startingTrip = false
    private let initialMethod: PrayerCalculationMethod
    private var hasUnsavedInput: Bool { method != initialMethod }
    private var blocksRootRoute: Bool { hasUnsavedInput || startingTrip }

    init(session: AppSession, fix: TravelFix, homeKm: Double, finished: @escaping () -> Void,
         rootDraftChanged: @escaping (UUID, Bool) -> Void) {
        self.session = session; self.fix = fix; self.homeKm = homeKm; self.finished = finished
        self.rootDraftChanged = rootDraftChanged
        let suggested = TravelRule.suggestedMethod(country: fix.country)
        self.initialMethod = suggested
        _method = State(initialValue: suggested)
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
                        .pickerStyle(.menu).disabled(startingTrip).accessibilityIdentifier("prayer-travel-method")
                    }
                }
                TravelPrimaryButton(title: "نعم، أنا مسافر", id: "prayer-travel-yes", busy: startingTrip || session.prayerWriteInProgress) {
                    guard !startingTrip else { return }
                    startingTrip = true
                    rootDraftChanged(rootBlockerID, true)
                    session.startPrayerTrip(city: fix.city, country: fix.country, place: fix.place, homeKm: homeKm, method: method) { succeeded in
                        startingTrip = false
                        rootDraftChanged(rootBlockerID, hasUnsavedInput)
                        if succeeded { finished() }
                    }
                }
                TravelSecondaryButton(title: "لا، أنا مقيم هنا", id: "prayer-travel-no") {
                    PrayerTravelCopy.decline(fix.place); finished()
                }.disabled(startingTrip)
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
        .onChange(of: blocksRootRoute, initial: true) { _, blocked in rootDraftChanged(rootBlockerID, blocked) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }
}

/// The active trip: its method, place and the way to end it.
struct PrayerTripSheet: View {
    let session: AppSession
    let trip: PrayerTrip
    var fix: TravelFix? = nil
    var thresholdKm: Double = 80
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    /// OR-09: the journey's legs; a trip through several countries reads «إسطنبول ← القاهرة».
    private var legs: [(city: String, country: String, start: Date, end: Date?)] {
        (try? PrayerRepository(context: ModelContext(session.container)))?.journeyLegs(of: trip.id) ?? []
    }
    private var hasRepeatedCityNames: Bool {
        let cities = legs.map(\.city)
        return Set(cities).count != cities.count
    }
    private func locationLabel(_ city: String, country: String, disambiguate: Bool) -> String {
        guard disambiguate, !country.isEmpty else { return city }
        let name = Locale(identifier: "ar").localizedString(forRegionCode: country) ?? country
        return "\(city)، \(name)"
    }
    /// The phone is in another city than this leg and far from it: offer to add it to the same journey.
    private var nextStop: TravelFix? {
        guard let fix, let currentLeg = legs.last,
              (fix.city != currentLeg.city || fix.country != currentLeg.country), TravelRule.distanceKm(from: trip.place, to: fix.place) > thresholdKm,
              TravelRule.isAway(home: session.activePlace, current: fix.place, thresholdKm: thresholdKm) else { return nil }
        return fix
    }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(legs.count > 1 ? "رحلتك" : "رحلتك إلى \(trip.city)").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                if legs.count > 1 {
                    // One line of stops, the current one last and in the accent.
                    HStack(spacing: 6) {
                        ForEach(Array(legs.enumerated()), id: \.offset) { index, leg in
                            if index > 0 { Image(systemName: "arrow.left").font(.system(size: 12, weight: .semibold)).foregroundStyle(theme.secondaryInk) }
                            Text(locationLabel(leg.city, country: leg.country, disambiguate: hasRepeatedCityNames))
                                .font(PrayerHomeType.strong).foregroundStyle(leg.end == nil ? theme.color("accentText") : theme.ink)
                        }
                    }
                    .accessibilityElement(children: .combine).accessibilityIdentifier("prayer-trip-legs")
                }
                if let stop = nextStop {
                    let currentCountry = legs.last?.country ?? ""
                    let stopName = locationLabel(stop.city, country: stop.country, disambiguate: stop.city == trip.city && stop.country != currentCountry)
                    PrayerPaperCard {
                        VStack(alignment: .leading, spacing: 10) {
                            Text("أنت الآن في \(stopName)").font(PrayerHomeType.strong)
                            Text("أضفها محطةً في رحلتك نفسها: تُحسب المواقيت هنا، ويبقى القصر والجمع، وتجمع ميزانية الرحلة مصروف البلدين.")
                                .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                            TravelPrimaryButton(title: "أضف \(stopName) إلى رحلتك", id: "prayer-trip-continue", busy: session.prayerWriteInProgress) {
                                session.continuePrayerTrip(city: stop.city, country: stop.country, place: stop.place, homeKm: max(0, TravelRule.distanceKm(from: session.activePlace, to: stop.place) - TravelRule.homeRadiusKm)) { if $0 { finished() } }
                            }
                        }
                    }
                }
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
    let rootDraftChanged: (UUID, Bool) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var status: PrayerStoredStatus = .jamaah
    @State private var mode: PrayerPairMode = .takhir
    @State private var shortened = true
    @State private var rootBlockerID = UUID()
    private var hasUnsavedInput: Bool { status != .jamaah || mode != .takhir || !shortened }

    private var title: String { pair == .dhuhrAsr ? "الظهر والعصر" : "المغرب والعشاء" }
    private func chip(_ label: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label).font(PrayerHomeType.strong)
                .frame(maxWidth: .infinity, minHeight: 48)
                .background { if on { Capsule().fill(theme.color("goldSoft").opacity(0.7)).glassEffect(.regular.interactive(), in: .capsule) } }
                .overlay { Capsule().stroke(on ? theme.line : theme.ink.opacity(0.14), lineWidth: 1) }
        }
        .buttonStyle(.madarPlain).accessibilityIdentifier(id)
            .accessibilityAddTraits(on ? .isSelected : [])
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
                TravelSecondaryButton(title: "ليس الآن", id: "prayer-pair-close") { dismiss() }
            }
            .padding(24)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(hasUnsavedInput)
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }
}
