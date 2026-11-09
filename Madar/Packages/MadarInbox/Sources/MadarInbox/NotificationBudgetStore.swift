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
    /// `notif.quietUntil`; absent in snapshots written before 29 Oct 2026, which ended quiet at midnight.
    public let quietUntil: String?
    public let dayBoundary: DayBoundary
    public let prayerDays: [PrayerDay]
    public let numerals: String
    public init(generatedAt: Date, validUntil: Date, activityEnabled: Bool, remindersEnabled: Bool,
                dailyBudget: Int, quietFromMinutes: Int?, quietUntil: String? = nil, dayBoundary: DayBoundary, prayerDays: [PrayerDay], numerals: String = "hindi") {
        self.generatedAt = generatedAt; self.validUntil = validUntil; self.activityEnabled = activityEnabled
        self.remindersEnabled = remindersEnabled; self.dailyBudget = dailyBudget; self.quietFromMinutes = quietFromMinutes; self.quietUntil = quietUntil
        self.dayBoundary = dayBoundary; self.prayerDays = prayerDays
        self.numerals = numerals
    }
    public var notificationPolicy: NotificationPolicy {
        .init(dailyBudget: dailyBudget, quietFromMinutes: quietFromMinutes, quietUntil: quietUntil.flatMap(QuietEnd.init(rawValue:)) ?? .midnight, thisDeviceRemindersEnabled: remindersEnabled, dayBoundary: dayBoundary)
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
        // The budget is a rebuildable device cache. Publishing a fresh policy is
        // the recovery boundary: if its JSON was interrupted or became unreadable,
        // keep the original bytes and rebuild from the current policy and ledger seeds.
        try transaction(recoveringUnreadableState: true) { state in
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
            let start = now
            guard NotificationArbiter.liveActivityWindowAllows(start, prayerDays: days, timeZone: zone,
                                                                 policy: policy.notificationPolicy) else {
                throw NotificationBudgetError.disabled
            }
            guard let next = occurrences.first(where: { $0.0 > start }) else { throw NotificationBudgetError.disabled }
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

    /// Reserves a shared device-budget slot before an immediate contextual Live Activity starts.
    /// A repeated underlying event is deduplicated by its stable purpose, even after the activity ends.
    public func reserveContextActivity(id: String, purpose: String, now: Date) throws -> NotificationBudgetReservation {
        try transaction { state in
            let policy = try validPolicy(state, now: now)
            guard policy.activityEnabled && policy.remindersEnabled else { throw NotificationBudgetError.disabled }
            guard !state.reservations.contains(where: { $0.purpose == purpose }) else { throw NotificationBudgetError.duplicate }
            guard let place = policy.prayerDays.first?.place else { throw NotificationBudgetError.unavailable }
            let zone = place.timeZone
            let emptyBudget: [String: Int] = [:]
            guard let candidate = NotificationArbiter.contextActivityStart(id: id, proposedAt: now,
                    prayerDays: policy.prayerDays, timeZone: zone, policy: policy.notificationPolicy,
                    submittedBudgetByDay: emptyBudget) else { throw NotificationBudgetError.disabled }
            let count = state.reservations.filter { $0.dayKey == candidate.dayKey }.count
            guard count < policy.dailyBudget else { throw NotificationBudgetError.full }
            let reservation = NotificationBudgetReservation(id: id, dayKey: candidate.dayKey,
                scheduledAt: candidate.dueAt, activity: true, purpose: purpose)
            guard candidate.dueAt < policy.validUntil else { throw NotificationBudgetError.unavailable }
            try insert(reservation, into: &state, limit: policy.dailyBudget, now: now)
            return reservation
        }
    }
    /// Only an explicit OS request failure may refund a start whose time has passed.
    public func cancel(id: String, now: Date, requestFailed: Bool = false) throws {
        try transaction { state in state.reservations.removeAll { $0.id == id && (requestFailed || $0.scheduledAt > now) } }
    }
    static let publishSkew: TimeInterval = 5 * 60
    private func validPolicy(_ state: State, now: Date) throws -> NotificationBudgetPolicy {
        // A refresh reads its clock before awaiting the notification centre; another write can publish a newer
        // policy meanwhile (owner real-data trial, 24 Oct 2026). A few minutes ahead is that race, not a future policy.
        guard let policy = state.policy, policy.generatedAt <= now.addingTimeInterval(Self.publishSkew), policy.validUntil > now,
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
    private func transaction<T>(recoveringUnreadableState: Bool = false, _ body: (inout State) throws -> T) throws -> T {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let fd = open(directory.appending(path: "budget.lock").path, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard fd >= 0 else { throw NotificationBudgetError.io(errno) }
        defer { close(fd) }
        guard flock(fd, LOCK_EX) == 0 else { throw NotificationBudgetError.io(errno) }
        defer { flock(fd, LOCK_UN) }
        let url = directory.appending(path: "budget.json")
        var state: State
        if FileManager.default.fileExists(atPath: url.path) {
            let data = try Data(contentsOf: url)
            do { state = try JSONDecoder().decode(State.self, from: data) }
            catch {
                guard recoveringUnreadableState else { throw error }
                // Keep damaged operational bytes for diagnosis; never silently erase them.
                let preserved = directory.appending(path: "budget.json.recovery-\(UUID().uuidString)")
                try FileManager.default.moveItem(at: url, to: preserved)
                state = State()
            }
        }
        else { state = State() }
        guard state.version == 1 else { throw NotificationBudgetError.unavailable }
        let result = try body(&state)
        try JSONEncoder().encode(state).write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        return result
    }
}
