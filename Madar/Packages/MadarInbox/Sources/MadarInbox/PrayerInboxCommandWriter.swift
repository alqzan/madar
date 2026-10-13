import Foundation
import MadarCore

public enum PrayerInboxCommandError: Error, Equatable, Sendable {
    case invalidDayKey
    case invalidPrayer
    case unsupportedStatus
    case invalidShortening
    case fridayKindRequired
    case unexpectedFridayKind
    case missingTodayFajr
    case missingPrayerOccurrence
    case prayerNotOccurred
    case jumuahRequiresCongregation
}

/// Builds and publishes prayer-log commands without opening the app's data store.
public enum PrayerInboxCommandWriter {
    public struct PrayerTime: Sendable, Equatable {
        public let prayer: String
        public let at: Date

        public init(prayer: String, at: Date) {
            self.prayer = prayer
            self.at = at
        }
    }

    /// Resolve the current prayer day for a Control action using only its fresh,
    /// app-produced prayer-time snapshot. Before today's Fajr, the active prayer
    /// day is yesterday. For today's prayer day, don't let a Control log a prayer
    /// before its adhan time.
    public static func currentPrayerDayKey(
        at now: Date,
        prayer rawPrayer: String,
        prayerTimes: [PrayerTime],
        timeZone: TimeZone
    ) throws -> String {
        guard Prayer(rawValue: rawPrayer) != nil else { throw PrayerInboxCommandError.invalidPrayer }
        let today = GregorianDay.containing(now, in: timeZone)
        guard let todayFajr = prayerTimes.first(where: {
            $0.prayer == Prayer.fajr.rawValue && GregorianDay.containing($0.at, in: timeZone) == today
        }) else { throw PrayerInboxCommandError.missingTodayFajr }

        let prayerDay = now < todayFajr.at ? today.adding(days: -1) : today
        guard prayerDay == today else { return prayerDay.description }

        guard let occurrence = prayerTimes.first(where: {
            $0.prayer == rawPrayer && GregorianDay.containing($0.at, in: timeZone) == prayerDay
        }) else { throw PrayerInboxCommandError.missingPrayerOccurrence }
        guard occurrence.at <= now else { throw PrayerInboxCommandError.prayerNotOccurred }
        return prayerDay.description
    }

    @discardableResult
    public static func logPrayer(
        inbox: PendingInbox,
        dayKey: String,
        prayer rawPrayer: String,
        status: String,
        shortened: Bool? = nil,
        fridayKind: String? = nil,
        timeZone: TimeZone,
        source: CommandSource,
        issuedAt: Date = .now
    ) throws -> InboxTicket {
        guard let day = try? GregorianDay(dayKey) else { throw PrayerInboxCommandError.invalidDayKey }
        guard let prayer = Prayer(rawValue: rawPrayer) else { throw PrayerInboxCommandError.invalidPrayer }
        guard status == "jamaah" || status == "alone" else { throw PrayerInboxCommandError.unsupportedStatus }
        guard shortened != true || (prayer != .fajr && prayer != .maghrib) else {
            throw PrayerInboxCommandError.invalidShortening
        }

        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let isFriday = calendar.component(.weekday, from: day.date(in: timeZone)) == 6
        if prayer == .dhuhr && isFriday {
            guard fridayKind == "jumuah" || fridayKind == "dhuhr" else {
                throw PrayerInboxCommandError.fridayKindRequired
            }
            guard fridayKind != "jumuah" || status == "jamaah" else {
                throw PrayerInboxCommandError.jumuahRequiresCongregation
            }
            guard fridayKind != "jumuah" || shortened != true else {
                throw PrayerInboxCommandError.invalidShortening
            }
        } else if fridayKind != nil {
            throw PrayerInboxCommandError.unexpectedFridayKind
        }

        var payload: [String: JSONValue] = [
            "dayKey": .string(day.description),
            "prayer": .string(prayer.rawValue),
            "status": .string(status)
        ]
        if let shortened { payload["shortened"] = .bool(shortened) }
        if let fridayKind { payload["fridayKind"] = .string(fridayKind) }

        let command = CommandEnvelope(name: "prayer.log", payload: .object(payload), source: source, issuedAt: issuedAt)
        let generation = try inbox.currentGeneration()
        return try inbox.enqueue(.init(expectedGenerationID: generation?.generationID, command: command))
    }
}
