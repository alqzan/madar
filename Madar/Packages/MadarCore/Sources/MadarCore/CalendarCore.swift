import Foundation

public enum CoreError: Error, Equatable { case invalidDate, invalidPlace, missingPrayerTimes, invalidRoute, unavailableFeature, invalidCommand }

public struct GregorianDay: Codable, Hashable, Comparable, Sendable, CustomStringConvertible {
    public let year: Int
    public let month: Int
    public let day: Int
    public init(year: Int, month: Int, day: Int) throws {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = .gmt
        let parts = DateComponents(year: year, month: month, day: day)
        guard (1...9999).contains(year), let date = calendar.date(from: parts), calendar.dateComponents([.year, .month, .day], from: date) == parts else { throw CoreError.invalidDate }
        self.year = year; self.month = month; self.day = day
    }
    public init(_ key: String) throws {
        let parts = key.split(separator: "-", omittingEmptySubsequences: false)
        guard parts.count == 3, parts[0].count == 4, parts[1].count == 2, parts[2].count == 2,
              key.unicodeScalars.allSatisfy({ (48...57).contains($0.value) || $0 == "-" }),
              let y = Int(parts[0]), let m = Int(parts[1]), let d = Int(parts[2]) else { throw CoreError.invalidDate }
        try self.init(year: y, month: m, day: d)
    }
    private enum CodingKeys: String, CodingKey { case year, month, day }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(year: c.decode(Int.self, forKey: .year), month: c.decode(Int.self, forKey: .month), day: c.decode(Int.self, forKey: .day))
    }
    public var description: String { String(format: "%04d-%02d-%02d", year, month, day) }
    public var components: DateComponents { DateComponents(year: year, month: month, day: day) }
    public func date(in zone: TimeZone) -> Date { var cal = Calendar(identifier: .gregorian); cal.timeZone = zone; return cal.date(from: components)! }
    public static func containing(_ date: Date, in zone: TimeZone) -> Self {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = zone
        let p = cal.dateComponents([.year, .month, .day], from: date)
        return try! Self(year: p.year!, month: p.month!, day: p.day!)
    }
    public func adding(days: Int) -> Self {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .gmt
        // A corrupt or absurd offset (from an imported row) clamps to about ±5,000 years rather than trapping on a nil date.
        let bounded = min(max(days, -1_800_000), 1_800_000)
        guard let moved = cal.date(byAdding: .day, value: bounded, to: date(in: .gmt)), let result = try? Self.containingSafely(moved) else { return self }
        return result
    }
    private static func containingSafely(_ date: Date) throws -> Self {
        var cal = Calendar(identifier: .gregorian); cal.timeZone = .gmt
        let p = cal.dateComponents([.year, .month, .day], from: date)
        return try Self(year: p.year ?? 0, month: p.month ?? 0, day: p.day ?? 0)
    }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.description < rhs.description }
}

public struct ActivePlace: Codable, Hashable, Sendable {
    public let latitude: Double
    public let longitude: Double
    public let timeZoneID: String
    public init(latitude: Double, longitude: Double, timeZoneID: String) throws {
        guard latitude.isFinite, longitude.isFinite, (-90...90).contains(latitude), (-180...180).contains(longitude), TimeZone(identifier: timeZoneID) != nil else { throw CoreError.invalidPlace }
        self.latitude = latitude; self.longitude = longitude; self.timeZoneID = timeZoneID
    }
    private enum CodingKeys: String, CodingKey { case latitude, longitude, timeZoneID }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(latitude: c.decode(Double.self, forKey: .latitude), longitude: c.decode(Double.self, forKey: .longitude), timeZoneID: c.decode(String.self, forKey: .timeZoneID))
    }
    public var timeZone: TimeZone { TimeZone(identifier: timeZoneID)! }
    public static let riyadh = try! Self(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
}

public enum DayBoundary: String, Codable, Sendable { case fajr, maghrib, midnight }
public struct StoredDayKey: Codable, Hashable, Sendable {
    public let date: GregorianDay
    public let timeZoneID: String
    public let boundary: DayBoundary
    public let hijri: HijriDate
    public var dayKey: String { date.description }
}
public enum HijriSource: String, Codable, Sendable { case ummAlQura, sighting }
public struct HijriDate: Codable, Hashable, Sendable { public let year: Int; public let month: Int; public let day: Int }
public enum HijriCalendar {
    public static func date(for instant: Date, timeZone: TimeZone, source: HijriSource = .ummAlQura, sightingOffset: Int = 0) -> HijriDate {
        var calendar = Calendar(identifier: .islamicUmmAlQura); calendar.timeZone = timeZone
        let offset = source == .sighting ? min(2, max(-2, sightingOffset)) : 0
        let adjusted = calendar.date(byAdding: .day, value: offset, to: instant)!
        let parts = calendar.dateComponents([.year, .month, .day], from: adjusted)
        return HijriDate(year: parts.year!, month: parts.month!, day: parts.day!)
    }
}
public enum MadarDay {
    /// Returns a value to persist once; changing settings must never rewrite this stored key.
    public static func resolve(instant: Date, place: ActivePlace, boundary: DayBoundary = .fajr, prayerDays: [PrayerDay], hijriSource: HijriSource = .ummAlQura, sightingOffset: Int = 0) throws -> StoredDayKey {
        let civil = GregorianDay.containing(instant, in: place.timeZone)
        let key: GregorianDay
        if boundary == .midnight { key = civil }
        else {
            guard let prayers = prayerDays.first(where: { $0.day == civil && $0.place == place }) else { throw CoreError.missingPrayerTimes }
            let start = boundary == .fajr ? prayers.fajr : prayers.maghrib
            key = instant < start ? civil.adding(days: -1) : civil
        }
        // Noon avoids calendar transitions at local midnight in display conversions.
        let hijri = HijriCalendar.date(for: key.date(in: place.timeZone).addingTimeInterval(12 * 3600), timeZone: place.timeZone, source: hijriSource, sightingOffset: sightingOffset)
        return StoredDayKey(date: key, timeZoneID: place.timeZoneID, boundary: boundary, hijri: hijri)
    }
    public static func prayerDay(instant: Date, place: ActivePlace, prayerDays: [PrayerDay]) throws -> StoredDayKey { try resolve(instant: instant, place: place, boundary: .fajr, prayerDays: prayerDays) }
}

public enum NumeralStyle: String, Codable, Sendable { case hindi, western }
public struct MadarNumberFormatter: Sendable {
    public let style: NumeralStyle
    public init(style: NumeralStyle = .hindi) { self.style = style }
    public func string(_ number: Int) -> String { localized(String(number)) }
    public func localized(_ text: String) -> String {
        guard style == .hindi else { return text }
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return String(text.map { ch in if let n = ch.wholeNumberValue, ch.isASCII { return digits[n] }; return ch })
    }
    /// Integer minor units avoid floating point rounding; sign + value stay isolated in RTL prose.
    public func amount(minorUnits: Int64, fractionDigits: Int = 2, signed: Bool = true) -> String {
        let count = min(6, max(0, fractionDigits)); var digits = String(minorUnits.magnitude)
        while digits.count <= count { digits = "0" + digits }
        let split = digits.index(digits.endIndex, offsetBy: -count)
        let whole = String(digits[..<split]); let fraction = String(digits[split...])
        let reversed = Array(whole.reversed())
        let grouped = reversed.enumerated().map { i, ch in (i > 0 && i % 3 == 0 ? "٬" : "") + String(ch) }.joined()
        let sign = minorUnits < 0 ? "−" : (signed ? "+" : "")
        let value = sign + String(grouped.reversed()) + (count == 0 ? "" : "٫" + fraction)
        return "\u{2068}" + localized(value) + "\u{2069}"
    }
    public func percent(_ integer: Int) -> String { string(integer) + "٪" }
}

public enum FirstCalendar: String, Codable, Sendable { case hijri, gregorian }
public struct DualDate: Equatable, Sendable {
    public let gregorian: GregorianDay
    public let hijri: HijriDate
    public init(instant: Date, timeZone: TimeZone, source: HijriSource = .ummAlQura, sightingOffset: Int = 0) {
        gregorian = .containing(instant, in: timeZone)
        hijri = HijriCalendar.date(for: instant, timeZone: timeZone, source: source, sightingOffset: sightingOffset)
    }
    public func text(firstCalendar: FirstCalendar = .hijri, numerals: NumeralStyle = .hindi) -> String {
        let f = MadarNumberFormatter(style: numerals)
        let months = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
        let h = "\(f.string(hijri.day)) \(months[hijri.month - 1]) \(f.string(hijri.year))"
        let g = f.localized(gregorian.description)
        return firstCalendar == .hijri ? h + "، " + g : g + "، " + h
    }
    /// Diary-only night display; does not mutate the persisted Madar day key.
    public static func diaryNightHijri(instant: Date, prayers: PrayerDay, source: HijriSource = .ummAlQura, sightingOffset: Int = 0) -> HijriDate {
        let day = prayers.day.adding(days: instant >= prayers.maghrib ? 1 : 0)
        return HijriCalendar.date(for: day.date(in: prayers.place.timeZone).addingTimeInterval(12 * 3600), timeZone: prayers.place.timeZone, source: source, sightingOffset: sightingOffset)
    }
}
