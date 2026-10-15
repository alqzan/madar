import Foundation
import Darwin
import MadarCore

/// Device-only operational JSON in the inbox. No room records or SwiftData access.
public struct NotificationBudgetPolicy: Codable, Sendable {
    public let generatedAt: Date
    public let validUntil: Date
    public let activityEnabled: Bool
    public let remindersEnabled: Bool
    public let dailyBudget: Int
    public let quietFromMinutes: Int?
    public let dayBoundary: DayBoundary
    public let prayerDays: [PrayerDay]
    public let numerals: String
    public init(generatedAt: Date, validUntil: Date, activityEnabled: Bool, remindersEnabled: Bool,
                dailyBudget: Int, quietFromMinutes: Int?, dayBoundary: DayBoundary, prayerDays: [PrayerDay], numerals: String = "hindi") {
        self.generatedAt = generatedAt; self.validUntil = validUntil; self.activityEnabled = activityEnabled
        self.remindersEnabled = remindersEnabled; self.dailyBudget = dailyBudget; self.quietFromMinutes = quietFromMinutes
        self.dayBoundary = dayBoundary; self.prayerDays = prayerDays
        self.numerals = numerals
    }
    public var notificationPolicy: NotificationPolicy {
        .init(dailyBudget: dailyBudget, quietFromMinutes: quietFromMinutes, thisDeviceRemindersEnabled: remindersEnabled, dayBoundary: dayBoundary)
    }
}

public struct NotificationBudgetReservation: Codable, Equatable, Sendable {
    public let id: String
    public let dayKey: String
    public let scheduledAt: Date
    public let activity: Bool
    public let purpose: String?
    public init(id: String, dayKey: String, scheduledAt: Date, activity: Bool = false, purpose: String? = nil) {
        self.id = id; self.dayKey = dayKey; self.scheduledAt = scheduledAt; self.activity = activity; self.purpose = purpose
    }
}

public struct ReservedPrayerActivity: Sendable {
    public let reservation: NotificationBudgetReservation
    public let prayer: Prayer
    public let prayerAt: Date
    public let numerals: String
}

public enum NotificationBudgetError: Error, Equatable { case unavailable, disabled, full, duplicate, io(Int32) }

/// Every check-and-reserve holds the same cross-process flock, then atomically replaces JSON.
/// A crash after reservation conservatively spends the slot; no delivery is inferred.
public struct NotificationBudgetStore: Sendable {
    public let directory: URL
    public init(directory: URL) { self.directory = directory }
    private struct State: Codable {
        var version = 1
        var policy: NotificationBudgetPolicy?
        var reservations: [NotificationBudgetReservation] = []
    }
    public func publish(_ policy: NotificationBudgetPolicy, importing seeds: [NotificationBudgetReservation] = []) throws {
        try transaction { state in
            state.policy = policy
            state.reservations.removeAll { $0.scheduledAt < policy.generatedAt.addingTimeInterval(-7 * 86400) }
            for seed in seeds where !state.reservations.contains(where: { $0.id == seed.id }) { state.reservations.append(seed) }
        }
    }
    public func reservations() throws -> [NotificationBudgetReservation] { try transaction { $0.reservations } }

    public func reserve(_ reservation: NotificationBudgetReservation, now: Date) throws {
        try transaction { state in
            let policy = try validPolicy(state, now: now)
            guard policy.remindersEnabled else { throw NotificationBudgetError.disabled }
            try insert(reservation, into: &state, limit: policy.dailyBudget, now: now)
        }
    }

    public func reservePrayerActivity(id: String, now: Date) throws -> ReservedPrayerActivity {
        try transaction { state in
            let policy = try validPolicy(state, now: now)
            guard policy.activityEnabled && policy.remindersEnabled else { throw NotificationBudgetError.disabled }
            let days = policy.prayerDays
            guard let zone = days.first?.place.timeZone else { throw NotificationBudgetError.unavailable }
            let occurrences = days.flatMap { day in Prayer.allCases.map { (day.time(for: $0), $0) } }.sorted { $0.0 < $1.0 }
            let start = SanctityGuard(prayerDays: days).clamp(now.addingTimeInterval(1))
            guard let next = occurrences.first(where: { $0.0 > start }), next.1 != .fajr, next.0.timeIntervalSince(start) <= 8 * 3600,
                  !(occurrences.last(where: { $0.0 <= start })?.1 == .isha && next.1 == .fajr),
                  !occurrences.contains(where: { $0.1 == .isha && $0.0 > start && $0.0 <= start.addingTimeInterval(12 * 3600) }) else {
                throw NotificationBudgetError.disabled
            }
            let purpose = "prayer.next.\(next.0.timeIntervalSince1970)"
            guard !state.reservations.contains(where: { $0.purpose == purpose }) else { throw NotificationBudgetError.duplicate }
            let counts = Dictionary(grouping: state.reservations, by: \.dayKey).mapValues(\.count)
            guard let candidate = NotificationArbiter.liveActivityStart(id: id, proposedAt: start, prayerDays: days,
                    timeZone: zone, policy: policy.notificationPolicy, submittedBudgetByDay: counts) else {
                throw NotificationBudgetError.full
            }
            guard candidate.dueAt < policy.validUntil else { throw NotificationBudgetError.unavailable }
            let reservation = NotificationBudgetReservation(id: id, dayKey: candidate.dayKey, scheduledAt: candidate.dueAt, activity: true, purpose: purpose)
            try insert(reservation, into: &state, limit: policy.dailyBudget, now: now)
            return ReservedPrayerActivity(reservation: reservation, prayer: next.1, prayerAt: next.0, numerals: policy.numerals)
        }
    }
    /// Only an explicit OS request failure may refund a start whose time has passed.
    public func cancel(id: String, now: Date, requestFailed: Bool = false) throws {
        try transaction { state in state.reservations.removeAll { $0.id == id && (requestFailed || $0.scheduledAt > now) } }
    }
    private func validPolicy(_ state: State, now: Date) throws -> NotificationBudgetPolicy {
        guard let policy = state.policy, policy.generatedAt <= now, policy.validUntil > now,
              !policy.prayerDays.isEmpty else { throw NotificationBudgetError.unavailable }
        return policy
    }
    private func insert(_ reservation: NotificationBudgetReservation, into state: inout State, limit: Int, now: Date) throws {
        if state.reservations.contains(reservation) { return }
        guard !state.reservations.contains(where: { $0.id == reservation.id && $0.scheduledAt <= now }) else { throw NotificationBudgetError.duplicate }
        let others = state.reservations.filter { $0.id != reservation.id }
        guard others.filter({ $0.dayKey == reservation.dayKey }).count < min(10, max(1, limit)) else { throw NotificationBudgetError.full }
        state.reservations = others + [reservation]
    }
    private func transaction<T>(_ body: (inout State) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appending(path: "budget.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NotificationBudgetError.io(errno) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw NotificationBudgetError.io(errno) }
        defer { flock(fd, LOCK_UN) }
        let url = directory.appending(path: "budget.json")
        var state: State
        if FileManager.default.fileExists(atPath: url.path) { state = try JSONDecoder().decode(State.self, from: Data(contentsOf: url)) }
        else { state = State() }
        guard state.version == 1 else { throw NotificationBudgetError.unavailable }
        let result = try body(&state)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return result
    }
}
