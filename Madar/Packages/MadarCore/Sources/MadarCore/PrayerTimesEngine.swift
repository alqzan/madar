import Foundation
import Adhan

public enum Prayer: String, Codable, CaseIterable, Sendable { case fajr, dhuhr, asr, maghrib, isha }
/// The first three are the global `salah.method` options. The rest are offered per trip (RP4) when a trip starts outside Saudi Arabia.
public enum PrayerCalculationMethod: String, Codable, Sendable, CaseIterable { case ummAlQura, mwl, egyptian, turkey, isna, dubai, kuwait, qatar }
public enum PrayerHighLatitudeRule: String, Codable, Sendable { case auto, middleOfTheNight, seventhOfTheNight, twilightAngle }
public struct PrayerCalculationOptions: Codable, Equatable, Sendable {
    public var method: PrayerCalculationMethod
    public var hanafiAsr: Bool
    public var highLatitudeRule: PrayerHighLatitudeRule
    public var offsets: [Prayer: Int]
    public var hijriSource: HijriSource
    public var sightingOffset: Int
    public init(method: PrayerCalculationMethod = .ummAlQura, hanafiAsr: Bool = false, highLatitudeRule: PrayerHighLatitudeRule = .auto, offsets: [Prayer: Int] = [:], hijriSource: HijriSource = .ummAlQura, sightingOffset: Int = 0) {
        self.method = method; self.hanafiAsr = hanafiAsr; self.highLatitudeRule = highLatitudeRule; self.offsets = offsets; self.hijriSource = hijriSource; self.sightingOffset = sightingOffset
    }
}
public struct SanctityWindow: Codable, Equatable, Sendable {
    public let prayer: Prayer
    public let start: Date
    public let end: Date
    public init(prayer: Prayer, adhan: Date, durationMinutes: Int? = nil) {
        self.prayer = prayer; start = adhan
        let minutes = durationMinutes ?? (prayer == .maghrib ? 20 : 30)
        end = adhan.addingTimeInterval(TimeInterval(max(0, minutes)) * 60)
    }
    public func contains(_ instant: Date) -> Bool { instant >= start && instant < end }
}
public struct PrayerDay: Codable, Equatable, Sendable {
    public let day: GregorianDay
    public let place: ActivePlace
    public let fajr: Date
    public let sunrise: Date
    public let dhuhr: Date
    public let asr: Date
    public let maghrib: Date
    public let isha: Date
    /// The calendar date used by the calculation. Nil is supported for older encoded values.
    public let hijriDate: HijriDate?
    public init(day: GregorianDay, place: ActivePlace, fajr: Date, sunrise: Date, dhuhr: Date, asr: Date, maghrib: Date, isha: Date, hijriDate: HijriDate? = nil) {
        self.day = day; self.place = place; self.fajr = fajr; self.sunrise = sunrise
        self.dhuhr = dhuhr; self.asr = asr; self.maghrib = maghrib; self.isha = isha
        self.hijriDate = hijriDate
    }
    public func time(for prayer: Prayer) -> Date { switch prayer { case .fajr: fajr; case .dhuhr: dhuhr; case .asr: asr; case .maghrib: maghrib; case .isha: isha } }
    public var sanctityWindows: [SanctityWindow] {
        return Prayer.allCases.map { prayer in
            let minutes = prayer == .maghrib ? 20 : 30
            return .init(prayer: prayer, adhan: time(for: prayer), durationMinutes: minutes)
        }
    }
}
public enum PrayerTimesEngine {
    /// Pure Umm Al-Qura calculation. Polar days return nil, never fabricated clock times.
    public static func calculate(day: GregorianDay, place: ActivePlace, hanafiAsr: Bool = false) -> PrayerDay? {
        calculate(day: day, place: place, options: .init(hanafiAsr: hanafiAsr))
    }
    public static func calculate(day: GregorianDay, place: ActivePlace, options: PrayerCalculationOptions) -> PrayerDay? {
        guard options.offsets.values.allSatisfy({ (-60...60).contains($0) }), (-2...2).contains(options.sightingOffset) else { return nil }
        let method: CalculationMethod = switch options.method {
        case .ummAlQura: .ummAlQura; case .mwl: .muslimWorldLeague; case .egyptian: .egyptian
        case .turkey: .turkey; case .isna: .northAmerica; case .dubai: .dubai; case .kuwait: .kuwait; case .qatar: .qatar
        }
        var params = method.params; params.madhab = options.hanafiAsr ? .hanafi : .shafi
        params.highLatitudeRule = switch options.highLatitudeRule {
        case .auto: abs(place.latitude) > 48 ? .seventhOfTheNight : .middleOfTheNight
        case .middleOfTheNight: .middleOfTheNight
        case .seventhOfTheNight: .seventhOfTheNight
        case .twilightAngle: .twilightAngle
        }
        guard let result = Adhan.PrayerTimes(coordinates: .init(latitude: place.latitude, longitude: place.longitude), date: day.components, calculationParameters: params) else { return nil }
        let hijri = HijriCalendar.date(for: day.date(in: place.timeZone).addingTimeInterval(12 * 3600), timeZone: place.timeZone, source: options.hijriSource, sightingOffset: options.sightingOffset)
        let isha = options.method == .ummAlQura ? result.maghrib.addingTimeInterval(TimeInterval(hijri.month == 9 ? 120 : 90) * 60) : result.isha
        func shifted(_ time: Date, _ prayer: Prayer) -> Date { time.addingTimeInterval(Double(options.offsets[prayer, default: 0]) * 60) }
        return PrayerDay(day: day, place: place, fajr: shifted(result.fajr, .fajr), sunrise: result.sunrise, dhuhr: shifted(result.dhuhr, .dhuhr), asr: shifted(result.asr, .asr), maghrib: shifted(result.maghrib, .maghrib), isha: shifted(isha, .isha), hijriDate: hijri)
    }
}
