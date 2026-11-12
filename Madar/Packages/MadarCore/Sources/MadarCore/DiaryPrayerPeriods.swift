import Foundation

/// The quiet section headings of a diary day: the day is divided by the prayers, nothing is stored.
public enum DiaryPrayerPeriod: Int, CaseIterable, Sendable, Comparable {
    case beforeFajr, afterFajr, duha, afterDhuhr, afterAsr, afterMaghrib, afterIsha
    public static func < (a: Self, b: Self) -> Bool { a.rawValue < b.rawValue }
    public var title: String {
        switch self {
        case .beforeFajr: "قبل الفجر"
        case .afterFajr: "بعد الفجر"
        case .duha: "الضحى"
        case .afterDhuhr: "بعد الظهر"
        case .afterAsr: "بعد العصر"
        case .afterMaghrib: "بعد المغرب"
        case .afterIsha: "بعد العشاء"
        }
    }
    /// The time that opens the period (nil for «قبل الفجر», which opens with the day).
    public func opening(in times: PrayerDay) -> Date? {
        switch self {
        case .beforeFajr: nil
        case .afterFajr: times.fajr
        case .duha: times.sunrise
        case .afterDhuhr: times.dhuhr
        case .afterAsr: times.asr
        case .afterMaghrib: times.maghrib
        case .afterIsha: times.isha
        }
    }
}

public struct DiaryPeriodHeading: Equatable, Sendable {
    /// Index (in the instants given) of the first entry under this heading.
    public let index: Int
    public let period: DiaryPrayerPeriod
    public let time: Date?
}

public enum DiaryPrayerPeriods {
    /// A boundary instant belongs to the period it opens. `preFajrExists` is false when the day itself starts at Fajr:
    /// anything earlier (an import) folds into «بعد الفجر» instead of inventing a period the day does not have.
    public static func period(at instant: Date, times: PrayerDay, preFajrExists: Bool) -> DiaryPrayerPeriod {
        if instant < times.fajr { return preFajrExists ? .beforeFajr : .afterFajr }
        if instant < times.sunrise { return .afterFajr }
        if instant < times.dhuhr { return .duha }
        if instant < times.asr { return .afterDhuhr }
        if instant < times.maghrib { return .afterAsr }
        if instant < times.isha { return .afterMaghrib }
        return .afterIsha
    }

    /// Headings for entries already in the order they were written. A heading appears only where the period changes,
    /// so periods with no entries have none. Entries out of time order never repeat a heading.
    public static func headings(for instants: [Date], times: PrayerDay, preFajrExists: Bool) -> [DiaryPeriodHeading] {
        var result: [DiaryPeriodHeading] = []
        var seen: Set<DiaryPrayerPeriod> = []
        for (index, instant) in instants.enumerated() {
            let p = period(at: instant, times: times, preFajrExists: preFajrExists)
            guard seen.insert(p).inserted else { continue }
            result.append(.init(index: index, period: p, time: p.opening(in: times)))
        }
        return result
    }
}
