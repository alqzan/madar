import Foundation

/// Phase 3 (owner, 11 Nov 2026): recurring charges and recurring salary, derived on every read from confirmed movements. Nothing is stored.
/// Unlike `SubscriptionSuggestionEngine` (a strict monthly draft for an obligation) this accepts any regular interval, and reports what is
/// expected next, a price change, and a late or missed occurrence.
public enum RecurringCharges {
    public enum Profile: Sendable {
        /// Same amount every time, or one price step (a raise or a cut) inside the pattern.
        case subscription
        /// Credits whose amount may drift (allowances, overtime): largest within 35% of the smallest.
        case salary
    }

    public struct Occurrence: Equatable, Sendable {
        public var id: String
        /// `MerchantKey.key` of the merchant (or the salary source).
        public var key: String
        public var name: String
        public var currency: String
        public var amountMinor: Int
        public var at: Date
        /// The app day stored on the movement («yyyy-MM-dd», `core.dayStart` applied once at write time). When present it is the
        /// occurrence's day, so a charge between midnight and Fajr counts on the same day as everywhere else in the app.
        public var dayKey: String?
        public init(id: String, key: String, name: String, currency: String, amountMinor: Int, at: Date, dayKey: String? = nil) {
            self.id = id; self.key = key; self.name = name; self.currency = currency; self.amountMinor = amountMinor; self.at = at; self.dayKey = dayKey
        }
    }

    public enum Cadence: Equatable, Sendable {
        case weekly, fortnightly, monthly, quarterly, halfYearly, yearly
        /// Any other regular interval, in days.
        case days(Int)
        public var approxDays: Int {
            switch self {
            case .weekly: 7
            case .fortnightly: 14
            case .monthly: 30
            case .quarterly: 91
            case .halfYearly: 182
            case .yearly: 365
            case .days(let n): n
            }
        }
        /// Calendar months between occurrences for the month-based cadences.
        var months: Int? {
            switch self { case .monthly: 1; case .quarterly: 3; case .halfYearly: 6; case .yearly: 12; default: nil }
        }
    }

    public enum Status: Equatable, Sendable {
        /// The expected date is today or still ahead.
        case upcoming
        /// Past the expected date by this many days, still inside the grace period.
        case late(days: Int)
        /// Past the grace period, but within two intervals: probably skipped or cancelled.
        case missed(days: Int)
        /// More than two intervals overdue: the pattern ended. The UI hides it.
        case ended
    }

    public struct PriceChange: Equatable, Sendable {
        public var fromMinor: Int
        public var toMinor: Int
        /// The first occurrence at the new amount.
        public var since: Date
    }

    public struct Series: Equatable, Sendable, Identifiable {
        public var id: String
        public var key: String
        public var name: String
        public var currency: String
        public var cadence: Cadence
        /// The latest amount, which is also the amount expected next.
        public var amountMinor: Int
        /// Set when the latest occurrence differs from the one before it.
        public var priceChange: PriceChange?
        public var occurrences: [Date]
        public var lastAt: Date
        public var nextExpectedAt: Date
        public var status: Status
        public var count: Int { occurrences.count }
    }

    public static let minimumOccurrences = 3

    /// `todayKey` is today's app day («yyyy-MM-dd»); with it «late» counts in app days like the occurrences' stored days.
    public static func detect(_ input: [Occurrence], profile: Profile, now: Date, timeZone: TimeZone, todayKey: String? = nil) -> [Series] {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let today = dayStart(todayKey, calendar) ?? calendar.startOfDay(for: now)
        var groups: [String: [Occurrence]] = [:]
        for item in input where item.amountMinor > 0 && !item.key.isEmpty && !item.currency.isEmpty {
            groups[item.key + "|" + item.currency.uppercased(), default: []].append(item)
        }
        var result: [Series] = []
        for (id, rows) in groups {
            // Two equal charges on one day are one event, never a stronger pattern.
            var seen = Set<String>(), unique: [Occurrence] = []
            for row in rows.sorted(by: { ($0.at, $0.id) < ($1.at, $1.id) }) {
                let day = appDay(row, calendar)
                guard seen.insert("\(day.timeIntervalSince1970):\(row.amountMinor)").inserted else { continue }
                unique.append(row)
            }
            guard unique.count >= minimumOccurrences else { continue }
            let days = unique.map { appDay($0, calendar) }
            // The longest recent run that is regular: an old irregular history never hides a current pattern.
            var found: (start: Int, cadence: Cadence)?
            for start in stride(from: 0, through: unique.count - minimumOccurrences, by: 1) {
                let slice = Array(unique[start...]), sliceDays = Array(days[start...])
                guard amountsAgree(slice.map(\.amountMinor), profile: profile) else { continue }
                if let cadence = cadence(of: gaps(sliceDays, calendar: calendar)) { found = (start, cadence); break }
            }
            guard let found else { continue }
            let run = Array(unique[found.start...]), runDays = Array(days[found.start...])
            guard let latest = run.last, let lastDay = runDays.last else { continue }
            let amount = latest.amountMinor
            var change: PriceChange?
            if run.count >= 2, run[run.count - 2].amountMinor != amount {
                change = .init(fromMinor: run[run.count - 2].amountMinor, toMinor: amount, since: latest.at)
            }
            let next = nextDate(after: lastDay, cadence: found.cadence, runDays: runDays, calendar: calendar)
            let late = calendar.dateComponents([.day], from: next, to: today).day ?? 0
            let grace = max(3, Int((0.15 * Double(found.cadence.approxDays)).rounded()))
            let status: Status = late <= 0 ? .upcoming : late <= grace ? .late(days: late)
                : late <= 2 * found.cadence.approxDays ? .missed(days: late) : .ended
            result.append(.init(id: id, key: latest.key, name: latest.name, currency: latest.currency.uppercased(), cadence: found.cadence,
                                amountMinor: amount, priceChange: change, occurrences: run.map(\.at), lastAt: latest.at,
                                nextExpectedAt: next, status: status))
        }
        return result.sorted { ($0.nextExpectedAt, $0.id) < ($1.nextExpectedAt, $1.id) }
    }

    /// The stored app day when the movement carries one, else the civil day of its time.
    private static func appDay(_ row: Occurrence, _ calendar: Calendar) -> Date {
        dayStart(row.dayKey, calendar) ?? calendar.startOfDay(for: row.at)
    }

    /// Midnight of a «yyyy-MM-dd» day; nil for a malformed or impossible day («2026-02-31» is not rolled into March).
    private static func dayStart(_ key: String?, _ calendar: Calendar) -> Date? {
        guard let key else { return nil }
        let parts = key.split(separator: "-").compactMap { Int($0) }
        guard parts.count == 3, let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])) else { return nil }
        let back = calendar.dateComponents([.year, .month, .day], from: date)
        return back.year == parts[0] && back.month == parts[1] && back.day == parts[2] ? date : nil
    }

    private static func amountsAgree(_ amounts: [Int], profile: Profile) -> Bool {
        guard let low = amounts.min(), let high = amounts.max(), low > 0 else { return false }
        switch profile {
        case .salary:
            return Double(high) <= Double(low) * 1.35
        case .subscription:
            let distinct = Set(amounts)
            if distinct.count == 1 { return true }
            guard distinct.count == 2 else { return false }
            // One step only: every earlier charge at the old price, every later one at the new price.
            let first = amounts[0]
            var switched = false
            for amount in amounts {
                if amount != first { switched = true } else if switched { return false }
            }
            return Double(high - low) <= 0.5 * Double(low)
        }
    }

    private static func gaps(_ days: [Date], calendar: Calendar) -> [Int] {
        zip(days, days.dropFirst()).map { calendar.dateComponents([.day], from: $0, to: $1).day ?? 0 }
    }

    private static func cadence(of gaps: [Int]) -> Cadence? {
        guard gaps.count >= minimumOccurrences - 1, gaps.allSatisfy({ $0 > 0 }) else { return nil }
        let sorted = gaps.sorted(), median = sorted[sorted.count / 2]
        func all(_ range: ClosedRange<Int>) -> Bool { gaps.allSatisfy(range.contains) }
        if (6...8).contains(median) { return all(6...8) ? .weekly : nil }
        if (13...15).contains(median) { return all(13...15) ? .fortnightly : nil }
        if (26...35).contains(median) { return all(26...35) ? .monthly : nil }
        if (85...97).contains(median) { return all(85...97) ? .quarterly : nil }
        if (175...192).contains(median) { return all(175...192) ? .halfYearly : nil }
        if (355...375).contains(median) { return all(355...375) ? .yearly : nil }
        guard median >= 5 else { return nil }
        let tolerance = max(1, Int((0.1 * Double(median)).rounded()))
        return gaps.allSatisfy({ abs($0 - median) <= tolerance }) ? .days(median) : nil
    }

    private static func nextDate(after last: Date, cadence: Cadence, runDays: [Date], calendar: Calendar) -> Date {
        if let months = cadence.months {
            // The billing day is the median day of the month; a weekend-shifted payment does not move it.
            let dayNumbers = runDays.compactMap { calendar.dateComponents([.day], from: $0).day }.sorted()
            let typical = dayNumbers[dayNumbers.count / 2]
            let firstOfLast = calendar.date(from: calendar.dateComponents([.year, .month], from: last)) ?? last
            let target = calendar.date(byAdding: .month, value: months, to: firstOfLast) ?? last
            let length = calendar.range(of: .day, in: .month, for: target)?.count ?? 28
            var parts = calendar.dateComponents([.year, .month], from: target); parts.day = min(typical, length)
            return calendar.date(from: parts) ?? target
        }
        return calendar.date(byAdding: .day, value: cadence.approxDays, to: last) ?? last
    }
}
