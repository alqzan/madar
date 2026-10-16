import Foundation

public enum NotificationKind: String, Codable, Sendable { case reminder, prayerAsk, digest, openApp }
public struct NotificationCandidate: Codable, Equatable, Sendable {
    public let id: String
    public let room: Room
    public let kind: NotificationKind
    public let dueAt: Date
    public let dayKey: String
    public let categoryCycleKey: String?
    public init(id: String, room: Room, kind: NotificationKind = .reminder, dueAt: Date, dayKey: String, categoryCycleKey: String? = nil) { self.id = id; self.room = room; self.kind = kind; self.dueAt = dueAt; self.dayKey = dayKey; self.categoryCycleKey = categoryCycleKey }
}
public struct NotificationPlan: Equatable, Sendable {
    public let scheduled: [NotificationCandidate]
    public let droppedIDs: [String]
    public let digestedIDs: [String]
    /// Which requests each retained digest stands for, so its fixed text can name their kinds (§8 item 8).
    public var digestMembers: [String: [String]] = [:]
}
public struct NotificationPolicy: Sendable {
    public let dailyBudget: Int
    public let priority: [Room]
    public let quietFromMinutes: Int?
    public let digestEnabled: Bool
    public let thisDeviceRemindersEnabled: Bool
    public let staleNudgeEnabled: Bool
    public let notesDailyCap: Int
    public let dayBoundary: DayBoundary
    public init(dailyBudget: Int = 4, priority: [Room] = [.salah, .quran, .mal, .notes, .habits, .mihbara], quietFromMinutes: Int? = nil, digestEnabled: Bool = true, thisDeviceRemindersEnabled: Bool = true, staleNudgeEnabled: Bool = true, notesDailyCap: Int = 2, dayBoundary: DayBoundary = .fajr) {
        self.dailyBudget = min(10, max(1, dailyBudget)); self.priority = priority
        self.quietFromMinutes = quietFromMinutes.map { min(1439, max(0, $0)) }; self.digestEnabled = digestEnabled
        self.thisDeviceRemindersEnabled = thisDeviceRemindersEnabled; self.staleNudgeEnabled = staleNudgeEnabled
        self.notesDailyCap = min(2, max(0, notesDailyCap)); self.dayBoundary = dayBoundary
    }
}
/// The single pure timing gate for every scheduled request. It repeatedly advances a
/// proposal until it is clear of every known window, including a following prayer.
public struct SanctityGuard: Sendable {
    private let windows: [SanctityWindow]
    public init(windows: [SanctityWindow]) { self.windows = windows.sorted { $0.start < $1.start } }
    public init(prayerDays: [PrayerDay]) { self.init(windows: prayerDays.flatMap(\.sanctityWindows)) }
    public func clamp(_ proposed: Date) -> Date {
        var result = proposed
        while let window = windows.first(where: { $0.contains(result) }) { result = window.end }
        return result
    }
}
public enum NotificationArbiter {
    public static let pendingCap = 60
    /// RL5: a scheduled ActivityKit start is an alert and consumes one room-budget slot.
    public static func liveActivityStart(id: String, proposedAt: Date, prayerDays: [PrayerDay], timeZone: TimeZone,
                                         policy: NotificationPolicy, submittedBudgetByDay: [String: Int]) -> NotificationCandidate? {
        guard policy.thisDeviceRemindersEnabled else { return nil }
        let due = SanctityGuard(prayerDays: prayerDays).clamp(proposedAt)
        guard !isQuiet(due, timeZone: timeZone, policy: policy) else { return nil }
        let key = madarKey(at: due, prayerDays: prayerDays, timeZone: timeZone, boundary: policy.dayBoundary)
        guard max(0, submittedBudgetByDay[key, default: 0]) < policy.dailyBudget else { return nil }
        return .init(id: id, room: .salah, dueAt: due, dayKey: key)
    }
    public static func prayerAsk(day: PrayerDay, prayer: Prayer, askAfterAdhanMinutes: Int = 30, recorded: Bool = false) -> NotificationCandidate? {
        guard !recorded else { return nil }
        let adhan = day.time(for: prayer)
        let windows = day.sanctityWindows
        let window = windows.first { $0.prayer == prayer }!
        let proposed = max(window.end, adhan.addingTimeInterval(Double(max(0, askAfterAdhanMinutes)) * 60))
        let due = SanctityGuard(windows: windows).clamp(proposed)
        return .init(id: "salah.\(day.day).\(prayer.rawValue)", room: .salah, kind: .prayerAsk, dueAt: due, dayKey: day.day.description)
    }
    public static func plan(candidates: [NotificationCandidate], prayerDays: [PrayerDay], now: Date, timeZone: TimeZone, policy: NotificationPolicy = .init(), existingPendingCount: Int = 0, deliveredCategoryCycles: Set<String> = [], disabledIDs: Set<String> = [], submittedBudgetByDay: [String: Int] = [:], submittedNotesByDay: [String: Int] = [:]) -> NotificationPlan {
        guard policy.thisDeviceRemindersEnabled else { return .init(scheduled: [], droppedIDs: candidates.map(\.id), digestedIDs: []) }
        let windows = prayerDays.flatMap(\.sanctityWindows).sorted { $0.start < $1.start }
        let sanctityGuard = SanctityGuard(windows: windows)
        let ordinaryEnd = now.addingTimeInterval(48 * 3600), prayerEnd = now.addingTimeInterval(96 * 3600)
        let capacity = max(0, pendingCap - max(0, existingPendingCount))
        var scheduled: [NotificationCandidate] = [], dropped: [String] = [], digested: [String] = []
        var digestMembers: [String: [String]] = [:]
        var ids = Set<String>(), cycles = deliveredCategoryCycles, notesCounts: [String: Int] = submittedNotesByDay, rooms: [String: [NotificationCandidate]] = [:]
        func rank(_ room: Room) -> Int { policy.priority.firstIndex(of: room) ?? policy.priority.count }
        func ordering(_ a: NotificationCandidate, _ b: NotificationCandidate) -> Bool {
            if rank(a.room) != rank(b.room) { return rank(a.room) < rank(b.room) }
            return a.dueAt == b.dueAt ? a.id < b.id : a.dueAt < b.dueAt
        }
        for candidate in candidates.sorted(by: ordering) {
            guard ids.insert(candidate.id).inserted else { continue }
            guard !disabledIDs.contains(candidate.id), candidate.kind == .reminder || candidate.kind == .prayerAsk else { dropped.append(candidate.id); continue }
            let horizon = candidate.kind == .prayerAsk ? prayerEnd : ordinaryEnd
            guard candidate.dueAt >= now, candidate.dueAt <= horizon else { dropped.append(candidate.id); continue }
            let due = sanctityGuard.clamp(candidate.dueAt)
            guard due <= horizon else { dropped.append(candidate.id); continue }
            let shifted = NotificationCandidate(id: candidate.id, room: candidate.room, kind: candidate.kind, dueAt: due, dayKey: candidate.dayKey, categoryCycleKey: candidate.categoryCycleKey)
            if candidate.kind == .prayerAsk { scheduled.append(shifted); continue }
            guard !isQuiet(due, timeZone: timeZone, policy: policy) else { dropped.append(candidate.id); continue }
            let key = madarKey(at: due, prayerDays: prayerDays, timeZone: timeZone, boundary: policy.dayBoundary)
            if let cycle = candidate.categoryCycleKey, cycles.contains(cycle) { dropped.append(candidate.id); continue }
            if candidate.room == .notes && notesCounts[key, default: 0] >= policy.notesDailyCap { dropped.append(candidate.id); continue }
            if candidate.room == .notes { notesCounts[key, default: 0] += 1 }
            if let cycle = candidate.categoryCycleKey { cycles.insert(cycle) }
            rooms[key, default: []].append(shifted)
        }
        if policy.staleNudgeEnabled {
            let finalAt = sanctityGuard.clamp(ordinaryEnd)
            if !isQuiet(finalAt, timeZone: timeZone, policy: policy) {
                let key = madarKey(at: finalAt, prayerDays: prayerDays, timeZone: timeZone, boundary: policy.dayBoundary)
                rooms[key, default: []].append(.init(id: "nudge.\(key)", room: .core, kind: .openApp, dueAt: finalAt, dayKey: key))
            }
        }
        for key in rooms.keys.sorted() {
            let entries = rooms[key]!.sorted(by: ordering)
            let available = max(0, policy.dailyBudget - max(0, submittedBudgetByDay[key, default: 0]))
            guard available > 0 else { dropped += entries.map(\.id); continue }
            if entries.count <= available { scheduled += entries; continue }
            var digestTime: Date?
            if policy.digestEnabled, let prayers = prayerDays.first(where: { $0.day.description == key }) {
                var proposed = prayers.isha.addingTimeInterval(60 * 60) // sanctity end + 30 minutes
                if let quiet = policy.quietFromMinutes {
                    let cutoff = prayers.day.date(in: timeZone).addingTimeInterval(Double(quiet - 15) * 60)
                    proposed = min(proposed, cutoff)
                }
                proposed = sanctityGuard.clamp(proposed)
                if proposed >= now && proposed <= ordinaryEnd && !isQuiet(proposed, timeZone: timeZone, policy: policy) { digestTime = proposed }
            }
            if let digestTime {
                scheduled += entries.prefix(available - 1)
                digested += entries.dropFirst(available - 1).map(\.id)
                let digestID = "digest.\(key)"
                digestMembers[digestID] = entries.dropFirst(available - 1).map(\.id)
                scheduled.append(.init(id: digestID, room: .core, kind: .digest, dueAt: digestTime, dayKey: key))
            } else { scheduled += entries.prefix(available); dropped += entries.dropFirst(available).map(\.id) }
        }
        // A late Isha or a sanctity shift can move a digest into another Madar day.
        // Allocate every final non-prayer request against its actual day, including consumed
        // ledger budget. Room priority wins ties; an unallocated digest drops its members.
        var finalBudget: [String: Int] = [:]
        var retained: [NotificationCandidate] = []
        for request in scheduled.sorted(by: ordering) {
            if request.kind == .prayerAsk { retained.append(request); continue }
            let actualKey = madarKey(at: request.dueAt, prayerDays: prayerDays, timeZone: timeZone, boundary: policy.dayBoundary)
            let available = max(0, policy.dailyBudget - max(0, submittedBudgetByDay[actualKey, default: 0]))
            guard finalBudget[actualKey, default: 0] < available else { dropped.append(request.id); continue }
            finalBudget[actualKey, default: 0] += 1
            retained.append(.init(id: request.id, room: request.room, kind: request.kind, dueAt: request.dueAt, dayKey: actualKey, categoryCycleKey: request.categoryCycleKey))
        }
        scheduled = retained
        // J10 preserves room budget slots and removes the most distant prayer asks first.
        while scheduled.count > capacity {
            let index = scheduled.indices.filter { scheduled[$0].kind == .prayerAsk }.max(by: { scheduled[$0].dueAt < scheduled[$1].dueAt })
                ?? scheduled.indices.max(by: { scheduled[$0].dueAt < scheduled[$1].dueAt })!
            dropped.append(scheduled.remove(at: index).id)
        }
        let retainedDigestIDs = Set(scheduled.filter { $0.kind == .digest }.map(\.id))
        for (id, members) in digestMembers where !retainedDigestIDs.contains(id) {
            let removed = Set(members); digested.removeAll { removed.contains($0) }; dropped += members
        }
        return .init(scheduled: scheduled.sorted { $0.dueAt == $1.dueAt ? $0.id < $1.id : $0.dueAt < $1.dueAt }, droppedIDs: dropped, digestedIDs: digested,
                     digestMembers: digestMembers.filter { retainedDigestIDs.contains($0.key) })
    }
    private static func madarKey(at instant: Date, prayerDays: [PrayerDay], timeZone: TimeZone, boundary: DayBoundary) -> String {
        let civil = GregorianDay.containing(instant, in: timeZone)
        guard boundary != .midnight, let day = prayerDays.first(where: { $0.day == civil }) else { return civil.description }
        let start = boundary == .fajr ? day.fajr : day.maghrib
        return (instant < start ? civil.adding(days: -1) : civil).description
    }
    public static func deferOutsideWindows(_ instant: Date, windows: [SanctityWindow]) -> Date {
        SanctityGuard(windows: windows).clamp(instant)
    }
    private static func isQuiet(_ date: Date, timeZone: TimeZone, policy: NotificationPolicy) -> Bool {
        guard let from = policy.quietFromMinutes else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        let parts = calendar.dateComponents([.hour, .minute], from: date)
        return parts.hour! * 60 + parts.minute! >= from
    }
}
