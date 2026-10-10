import Foundation
import Adhan

public enum Prayer: String, Codable, CaseIterable, Sendable { case fajr, dhuhr, asr, maghrib, isha }
public enum PrayerCalculationMethod: String, Codable, Sendable { case ummAlQura, mwl, egyptian }
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
    public init(prayer: Prayer, adhan: Date) {
        self.prayer = prayer; start = adhan
        end = adhan.addingTimeInterval(TimeInterval(prayer == .maghrib ? 20 : 30) * 60)
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
    public func time(for prayer: Prayer) -> Date { switch prayer { case .fajr: fajr; case .dhuhr: dhuhr; case .asr: asr; case .maghrib: maghrib; case .isha: isha } }
    public var sanctityWindows: [SanctityWindow] { Prayer.allCases.map { .init(prayer: $0, adhan: time(for: $0)) } }
}
public enum PrayerTimesEngine {
    /// Pure Umm Al-Qura calculation. Polar days return nil, never fabricated clock times.
    public static func calculate(day: GregorianDay, place: ActivePlace, hanafiAsr: Bool = false) -> PrayerDay? {
        calculate(day: day, place: place, options: .init(hanafiAsr: hanafiAsr))
    }
    public static func calculate(day: GregorianDay, place: ActivePlace, options: PrayerCalculationOptions) -> PrayerDay? {
        guard options.offsets.values.allSatisfy({ (-60...60).contains($0) }), (-2...2).contains(options.sightingOffset) else { return nil }
        let method: CalculationMethod = switch options.method { case .ummAlQura: .ummAlQura; case .mwl: .muslimWorldLeague; case .egyptian: .egyptian }
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
        return PrayerDay(day: day, place: place, fajr: shifted(result.fajr, .fajr), sunrise: result.sunrise, dhuhr: shifted(result.dhuhr, .dhuhr), asr: shifted(result.asr, .asr), maghrib: shifted(result.maghrib, .maghrib), isha: shifted(isha, .isha))
    }
}
