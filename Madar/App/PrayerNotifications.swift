@preconcurrency import ActivityKit
import Foundation
import MadarCore
import MadarCommands
import MadarData
import MadarPrayer
import MadarInbox
import SwiftData
import UIKit
@preconcurrency import UserNotifications
#if DEBUG
import SwiftUI
#endif

struct MadarContextTripFact: Equatable {
    let city: String
    let timeZoneID: String
    let startsAt: Date
    let endsAt: Date?
}

struct MadarContextActivityPlan: Equatable {
    let kind: MadarContextActivityAttributes.Kind
    let activityKey: String
    let eventAt: Date?
    let city: String?
    let timeZoneID: String?
    let staleAt: Date?

    var state: MadarContextActivityAttributes.ContentState {
        .init(eventAt: eventAt, city: city, timeZoneID: timeZoneID)
    }
}

enum MadarContextActivityPlanner {
    static let maximumActiveDuration: TimeInterval = 8 * 60 * 60

    /// Produces only facts that are safe to put on an external surface. Letter text and IDs never enter the plan.
    static func plans(now: Date, eligibleLetterAt: Date?, trip: MadarContextTripFact?, iftarAt: Date?) -> [MadarContextActivityPlan] {
        var result: [MadarContextActivityPlan] = []
        if let eligibleLetterAt, eligibleLetterAt <= now {
            result.append(.init(kind: .letter, activityKey: "notes.letter", eventAt: eligibleLetterAt,
                                city: nil, timeZoneID: nil,
                                staleAt: now.addingTimeInterval(maximumActiveDuration)))
        }
        if let iftarAt, iftarAt > now, iftarAt.timeIntervalSince(now) <= maximumActiveDuration {
            result.append(.init(kind: .iftar, activityKey: "bahw.iftar", eventAt: iftarAt,
                                city: nil, timeZoneID: nil, staleAt: iftarAt))
        }
        if let trip, trip.startsAt <= now, trip.endsAt.map({ now < $0 }) ?? true {
            result.append(.init(kind: .travel, activityKey: "salah.travel", eventAt: trip.startsAt,
                                city: trip.city.isEmpty ? "مدينة السفر" : trip.city,
                                timeZoneID: trip.timeZoneID,
                                staleAt: trip.endsAt ?? now.addingTimeInterval(maximumActiveDuration)))
        }
        return result
    }
}

struct PrayerNotificationSlot: Equatable {
    let reference: PrayerReference
    let prayer: Prayer
    let prayerDay: PrayerDay
    let occurrence: PrayerOccurrence
    let recorded: Bool
}

@MainActor enum PrayerNotificationSchedule {
    static func slots(repository: PrayerRepository, days: [PrayerDay], now: Date) throws -> [PrayerNotificationSlot] {
        var result: [PrayerNotificationSlot] = []
        for day in days {
            for cell in try repository.day(day.day, now: now).cells {
                guard let occurrence = repository.occurrence(cell.reference) else { continue }
                let options = occurrence.tripID == nil ? repository.options : repository.tripOptions
                guard let actualDay = PrayerTimesEngine.calculate(day: cell.reference.day, place: occurrence.place, options: options),
                      abs(actualDay.time(for: cell.reference.prayer).timeIntervalSince(occurrence.time)) < 1 else { continue }
                result.append(.init(reference: cell.reference, prayer: cell.reference.prayer, prayerDay: actualDay,
                                    occurrence: occurrence, recorded: PrayerNotificationCoordinator.isRecorded(cell.status)))
            }
        }
        return result
    }

    static func sanctityWindows(for slots: [PrayerNotificationSlot]) -> [SanctityWindow] {
        slots.compactMap { slot in slot.prayerDay.sanctityWindows.first { $0.prayer == slot.prayer } }
    }

    static func candidates(for slots: [PrayerNotificationSlot], sanctityWindows: [SanctityWindow], askAfterAdhanMinutes: Int) -> [NotificationCandidate] {
        slots.compactMap { slot in
            NotificationArbiter.prayerAsk(day: slot.prayerDay, prayer: slot.prayer,
                                           askAfterAdhanMinutes: askAfterAdhanMinutes, recorded: slot.recorded,
                                           sanctityWindows: sanctityWindows)
        }
    }

    static func timeZone(for reference: PrayerReference, repository: PrayerRepository, fallbackAt: Date) -> TimeZone {
        repository.occurrence(reference)?.place.timeZone ?? repository.place(at: fallbackAt).timeZone
    }
}

@MainActor
final class PrayerNotificationCoordinator {
    static let categoryID = "salah.ask"
    static let snoozeActionID = "salah.snooze"
    static let jamaahActionID = "salah.jamaah"
    static let aloneActionID = "salah.alone"
    private static let requestPrefix = "salah."

    private let center: UNUserNotificationCenter
    private weak var session: AppSession?
    private var pendingResponses: [UNNotificationResponse] = []
    private var lifecycleOperationInProgress = false
    private var lifecycleOperationWaiters: [CheckedContinuation<Void, Never>] = []

    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func install(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
        let snooze = UNNotificationAction(identifier: Self.snoozeActionID, title: "ذكّرني بعد ساعة", options: [])
        // S10: record from the notification. «فاتتني» is not offered here: before the prayer's window ends it is not allowed (RP2).
        let jamaah = UNNotificationAction(identifier: Self.jamaahActionID, title: "في جماعة", options: [])
        let alone = UNNotificationAction(identifier: Self.aloneActionID, title: "وحدي", options: [])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [jamaah, alone, snooze], intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func attach(to session: AppSession) async {
        self.session = session
        await updateAuthorizationState()
        let queued = pendingResponses
        pendingResponses.removeAll()
        for response in queued { await handle(response) }
        do { try await refresh() }
        catch { session.errorMessage = "تعذّر إعداد تذكيرات الصلاة. \(madarUserMessage(error))" }
    }

    func requestAuthorization() async throws {
        let current = await authorizationStatus()
        if current == .notDetermined {
            _ = try await center.requestAuthorization(options: [.alert, .sound])
        }
        await updateAuthorizationState()
        try await refresh()
    }

    func refresh(now suppliedNow: Date? = nil) async throws {
        guard let session, session.beginNotificationStoreAccess() else { return }
        defer { session.endNotificationStoreAccess() }
        await acquireLifecycleLock()
        defer { releaseLifecycleLock() }
        do { try await refreshLocked(session: session, suppliedNow: suppliedNow) }
        catch {
            guard !isExpectedNoPrayerBoundary(error, session: session) else { return }
            throw error
        }
    }

    func withSerializedMutation<T>(_ operation: @MainActor () async throws -> T) async rethrows -> T {
        await acquireLifecycleLock()
        defer { releaseLifecycleLock() }
        return try await operation()
    }

    func refreshAfterSerializedMutation() async {
        guard let session, session.notificationStoreAccessAvailable else { return }
        do { try await refreshLocked(session: session, suppliedNow: nil) }
        catch {
            guard !isExpectedNoPrayerBoundary(error, session: session) else { return }
            session.errorMessage = "تعذّر تحديث تذكيرات الصلاة. \(madarUserMessage(error))"
        }
    }

    /// Missing prayer boundaries are a normal polar-day state, not a notification failure.
    private func isExpectedNoPrayerBoundary(_ error: Error, session: AppSession) -> Bool {
        guard (error as? CoreError) == .missingPrayerTimes else { return false }
        return (try? session.prayerSnapshot(at: session.prayerNow()).hasTimes) == false
    }

    func resumeAfterStoreMaintenance() async {
        guard session != nil else { return }
        let queued = pendingResponses
        pendingResponses.removeAll()
        for response in queued { await handle(response) }
        do { try await refresh() }
        catch { session?.errorMessage = "تعذّر تحديث تذكيرات الصلاة بعد تحديث البيانات. \(madarUserMessage(error))" }
    }

    private func refreshLocked(session: AppSession, suppliedNow: Date?) async throws {
        try session.reload()
        let now = suppliedNow ?? session.prayerNow()
        try session.publishNotificationBudget(at: now)
        let repository = try PrayerRepository(context: ModelContext(session.container))
        let days = prayerDays(repository: repository, now: now)
        let prayerSlots = try PrayerNotificationSchedule.slots(repository: repository, days: days, now: now)
        let sanctityWindows = PrayerNotificationSchedule.sanctityWindows(for: prayerSlots)
        let currentAuthorization = await authorizationStatus()
        session.updateNotificationAuthorization(Self.authorizationCode(currentAuthorization))

        let requestsEnabled = session.bool("salah.askReminder") && session.bool("notif.thisDeviceReminders") && Self.canSchedule(currentAuthorization)
        let existing = await center.pendingNotificationRequests()
        var candidates: [NotificationCandidate] = []
        if requestsEnabled {
            let askAfter = Int(session.number("salah.askAfterAdhanMin"))
            candidates += PrayerNotificationSchedule.candidates(for: prayerSlots, sanctityWindows: sanctityWindows, askAfterAdhanMinutes: askAfter)
                .filter { $0.dueAt <= now.addingTimeInterval(96 * 60 * 60) }
            candidates += Self.pendingSnoozes(from: existing, prayerDays: days, sanctityWindows: sanctityWindows, repository: repository, now: now)
        }

        let globalEnabled = session.bool("notif.thisDeviceReminders") && Self.canSchedule(currentAuthorization)
        if globalEnabled {
            candidates += try AppQuranService(session: session, clock: { now }).notificationCandidates(prayerDays: days, now: now)
            candidates += try RoomNotificationContent.candidates(session: session, prayerDays: days, now: now)
        }
        let planningDays = RoomNotificationContent.planningPrayerDays(session: session, candidates: candidates, current: days, now: now)
        let externalPendingCount = existing.filter { !Self.manages($0.identifier) }.count
        let ledger = try ModelContext(session.container).fetch(FetchDescriptor<NotificationLedger>()).filter { $0.deletedAt == nil && ["submitted", "observed"].contains($0.state) && $0.requestClass != "prayer" }
        let consumed = ledger.filter { $0.scheduledFor <= now || $0.kind == "activityStart" }
        let sharedConsumed = try session.notificationBudget.reservations().filter { $0.scheduledAt <= now || $0.activity }
        let counts = Dictionary(grouping: sharedConsumed, by: \.dayKey).mapValues { Set($0.map(\.id)).count }
        let quiet = session.string("notif.quietFrom").split(separator: ":").compactMap { Int($0) }
        let quietMinutes = session.bool("notif.quietAfterIsha") ? (quiet.count == 2 ? quiet[0] * 60 + quiet[1] : 0) : nil
        let priority: [Room]
        if case .array(let order)? = session.values["notif.roomPriority"] { priority = order.compactMap { $0.string.flatMap(Room.init(rawValue:)) } }
        else { priority = [.salah, .quran, .mal, .notes, .habits, .mihbara] }
        let plan = NotificationArbiter.plan(
            candidates: candidates,
            prayerDays: planningDays,
            now: now,
            timeZone: repository.place(at: now).timeZone,
            policy: .init(dailyBudget: Int(session.number("notif.dailyBudget")), priority: priority, quietFromMinutes: quietMinutes,
                digestEnabled: session.bool("notif.digestOverflow"), thisDeviceRemindersEnabled: globalEnabled, staleNudgeEnabled: session.bool("notif.staleNudge"),
                notesDailyCap: Int(session.number("notes.dailyCap")),
                dayBoundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr),
            existingPendingCount: externalPendingCount, disabledIDs: Set(consumed.map(\.requestID)), submittedBudgetByDay: counts,
            sanctityWindows: sanctityWindows
        )
        try await reconcile(plan: plan, candidates: candidates,
                            current: existing.filter { $0.identifier.hasPrefix(Self.requestPrefix) },
                            repository: repository)
        try await reconcileRooms(plan: plan, candidates: candidates, current: existing.filter { RoomNotificationContent.isRoomRequest($0.identifier) }, timeZone: repository.place(at: now).timeZone, consumed: Set(consumed.map(\.requestID)), now: now)
        try await reconcilePrayerActivity(prayerSlots: prayerSlots, sanctityWindows: sanctityWindows, repository: repository, now: now, session: session)
        try await reconcileContextActivities(prayerDays: days, prayerSlots: prayerSlots, sanctityWindows: sanctityWindows,
                                            repository: repository, now: now, session: session)
    }

    private func acquireLifecycleLock() async {
        guard lifecycleOperationInProgress else { lifecycleOperationInProgress = true; return }
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            lifecycleOperationWaiters.append(continuation)
        }
    }

    private func releaseLifecycleLock() {
        if lifecycleOperationWaiters.isEmpty { lifecycleOperationInProgress = false }
        else { lifecycleOperationWaiters.removeFirst().resume() }
    }

    func handle(_ response: UNNotificationResponse) async {
        guard let session else { pendingResponses.append(response); return }
        guard session.beginNotificationStoreAccess() else { pendingResponses.append(response); return }
        defer { session.endNotificationStoreAccess() }
        await acquireLifecycleLock()
        defer { releaseLifecycleLock() }
        do {
            try updateLedger(requestID: response.notification.request.identifier, state: "observed")
            if response.actionIdentifier == Self.snoozeActionID {
                try await scheduleSnoozeLocked(for: response.notification.request, tapTime: Date())
            } else if response.actionIdentifier == Self.jamaahActionID || response.actionIdentifier == Self.aloneActionID {
                let info = response.notification.request.content.userInfo
                guard let dayKey = info["dayKey"] as? String, let day = try? GregorianDay(dayKey),
                      let prayer = (info["prayer"] as? String).flatMap(Prayer.init(rawValue:)) else { return }
                let reference = PrayerReference(day: day, prayer: prayer)
                let alone = response.actionIdentifier == Self.aloneActionID
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = session.activePlace.timeZone
                let friday = prayer == .dhuhr && calendar.component(.weekday, from: day.date(in: session.activePlace.timeZone).addingTimeInterval(12 * 3600)) == 6
                if friday && !alone {
                    // RP5: Friday noon in congregation needs an explicit Jumu'ah/Dhuhr choice, so the app opens for it.
                    session.selectedTab = "prayer"
                } else {
                    session.recordPrayer(reference, status: alone ? .alone : .jamaah, fridayKind: friday ? .dhuhr : nil)
                }
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                let request = response.notification.request
                if RoomNotificationContent.isRoomRequest(request.identifier) { RoomNotificationContent.open(request.identifier, userInfo: request.content.userInfo, session: session) }
                else { session.selectedTab = "prayer" }
            }
        } catch { session.errorMessage = "تعذّر تنفيذ تذكير الصلاة. \(madarUserMessage(error))" }
    }

    func foregroundOptions(for notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let session, session.beginNotificationStoreAccess() else { return [] }
        defer { session.endNotificationStoreAccess() }
        await acquireLifecycleLock()
        defer { releaseLifecycleLock() }
        let now = Date()
        do {
            try session.reload()
            let userInfo = notification.request.content.userInfo
            if RoomNotificationContent.isRoomRequest(notification.request.identifier) {
                guard session.bool("notif.thisDeviceReminders") else { return [] }
                let repository = try PrayerRepository(context: ModelContext(session.container)), days = prayerDays(repository: repository, now: now)
                guard SanctityGuard(prayerDays: days).clamp(now) == now,
                      try RoomNotificationContent.stillRelevant(notification.request.identifier, session: session, now: now) else { return [] }
                try updateLedger(requestID: notification.request.identifier, state: "observed")
                return [.banner, .list, .sound]
            }
            guard session.bool("salah.askReminder"), session.bool("notif.thisDeviceReminders"),
                  let dayKey = userInfo["dayKey"] as? String,
                  let prayerRaw = userInfo["prayer"] as? String,
                  let prayer = Prayer(rawValue: prayerRaw) else { return [] }
            let repository = try PrayerRepository(context: ModelContext(session.container))
            let days = prayerDays(repository: repository, now: now)
            let slots = try PrayerNotificationSchedule.slots(repository: repository, days: days, now: now)
            let sanctityWindows = PrayerNotificationSchedule.sanctityWindows(for: slots)
            guard let day = days.first(where: { $0.day.description == dayKey }),
                  let cell = try repository.day(day.day, now: now).cells.first(where: { $0.reference.prayer == prayer }),
                  !Self.isRecorded(cell.status) else { return [] }
            let guarder = SanctityGuard(windows: sanctityWindows)
            if guarder.clamp(now) > now {
                let candidate = NotificationCandidate(id: notification.request.identifier, room: .salah, kind: .prayerAsk,
                                                       dueAt: guarder.clamp(now), dayKey: dayKey)
                let timeZone = PrayerNotificationSchedule.timeZone(for: .init(day: day.day, prayer: prayer), repository: repository, fallbackAt: now)
                try await center.add(Self.makeRequest(candidate: candidate, prayer: prayer, timeZone: timeZone, snooze: candidate.id.hasSuffix(".snooze")))
                try updateLedger(requestID: candidate.id, dayKey: dayKey, prayer: prayer, dueAt: candidate.dueAt,
                                 state: "submitted", kind: candidate.id.hasSuffix(".snooze") ? "snooze" : "ask")
                return []
            }
            try updateLedger(requestID: notification.request.identifier, state: "observed")
            return [.banner, .list, .sound]
        } catch {
            session.errorMessage = "تعذّر التحقق من وقت التذكير. \(madarUserMessage(error))"
            return []
        }
    }

    func scheduleSnooze(for request: UNNotificationRequest, tapTime: Date) async throws {
        guard let session, session.beginNotificationStoreAccess() else { return }
        defer { session.endNotificationStoreAccess() }
        await acquireLifecycleLock()
        defer { releaseLifecycleLock() }
        try await scheduleSnoozeLocked(for: request, tapTime: tapTime)
    }

    private func scheduleSnoozeLocked(for request: UNNotificationRequest, tapTime: Date) async throws {
        guard let session else { return }
        let content = request.content
        guard let dayKey = content.userInfo["dayKey"] as? String,
              let prayerRaw = content.userInfo["prayer"] as? String,
              let prayer = Prayer(rawValue: prayerRaw) else { return }
        let existing = await center.pendingNotificationRequests()
        let authorization = await authorizationStatus()
        try session.reload()
        guard session.bool("salah.askReminder"), session.bool("notif.thisDeviceReminders"),
              Self.canSchedule(authorization) else { return }
        let repository = try PrayerRepository(context: ModelContext(session.container))
        let days = prayerDays(repository: repository, now: tapTime)
        let slots = try PrayerNotificationSchedule.slots(repository: repository, days: days, now: tapTime)
        let sanctityWindows = PrayerNotificationSchedule.sanctityWindows(for: slots)
        guard let day = days.first(where: { $0.day.description == dayKey }),
              let cell = try repository.day(day.day, now: tapTime).cells.first(where: { $0.reference.prayer == prayer }),
              !Self.isRecorded(cell.status) else { return }

        let requestID = request.identifier.hasSuffix(".snooze")
            ? String(request.identifier.dropLast(".snooze".count))
            : request.identifier
        let candidate = NotificationCandidate(id: requestID + ".snooze", room: .salah, kind: .prayerAsk,
                                               dueAt: tapTime.addingTimeInterval(60 * 60), dayKey: dayKey)
        let occupiedCount = existing.count - (existing.contains(where: { $0.identifier == candidate.id }) ? 1 : 0)
        let plan = NotificationArbiter.plan(candidates: [candidate], prayerDays: days, now: tapTime,
                                             timeZone: repository.place(at: tapTime).timeZone,
                                             policy: .init(thisDeviceRemindersEnabled: true, staleNudgeEnabled: false),
                                             existingPendingCount: occupiedCount, sanctityWindows: sanctityWindows)
        guard let scheduled = plan.scheduled.first(where: { $0.id == candidate.id }) else {
            try updateLedger(requestID: candidate.id, dayKey: dayKey, prayer: prayer, dueAt: candidate.dueAt,
                             state: "dropped", reason: "cap", kind: "snooze")
            return
        }
        let timeZone = PrayerNotificationSchedule.timeZone(for: .init(day: day.day, prayer: prayer), repository: repository, fallbackAt: tapTime)
        try await center.add(Self.makeRequest(candidate: scheduled, prayer: prayer, timeZone: timeZone, snooze: true))
        try updateLedger(requestID: scheduled.id, dayKey: scheduled.dayKey, prayer: prayer, dueAt: scheduled.dueAt,
                         state: "submitted", kind: "snooze")
    }

    private func reconcile(plan: NotificationPlan, candidates: [NotificationCandidate], current: [UNNotificationRequest], repository: PrayerRepository) async throws {
        let candidateByID = Dictionary(candidates.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let requested = Dictionary(uniqueKeysWithValues: plan.scheduled.compactMap { item -> (String, NotificationCandidate)? in
            guard Self.prayer(for: item.id) != nil else { return nil }
            return (item.id, item)
        })
        let currentByID = Dictionary(current.map { ($0.identifier, $0) }, uniquingKeysWith: { first, _ in first })
        let obsolete = current.filter { request in
            guard let target = requested[request.identifier] else { return true }
            return !Self.matches(request, dueAt: target.dueAt)
        }.map(\.identifier)
        if !obsolete.isEmpty {
            center.removePendingNotificationRequests(withIdentifiers: obsolete)
            for identifier in obsolete { try updateLedger(requestID: identifier, state: "cancelled") }
        }

        for (identifier, candidate) in requested.sorted(by: { $0.key < $1.key }) {
            guard let prayer = Self.prayer(for: identifier), let day = try? GregorianDay(candidate.dayKey) else { continue }
            let timeZone = PrayerNotificationSchedule.timeZone(for: .init(day: day, prayer: prayer), repository: repository, fallbackAt: candidate.dueAt)
            if let current = currentByID[identifier], Self.matches(current, dueAt: candidate.dueAt) {
                try updateLedger(requestID: identifier, dayKey: candidate.dayKey, prayer: prayer, dueAt: candidate.dueAt,
                                 state: "submitted", kind: identifier.hasSuffix(".snooze") ? "snooze" : "ask")
                continue
            }
            let isSnooze = identifier.hasSuffix(".snooze")
            try await center.add(Self.makeRequest(candidate: candidate, prayer: prayer, timeZone: timeZone, snooze: isSnooze))
            try updateLedger(requestID: identifier, dayKey: candidate.dayKey, prayer: prayer, dueAt: candidate.dueAt,
                             state: "submitted", kind: isSnooze ? "snooze" : "ask")
        }
        for identifier in plan.droppedIDs {
            guard let candidate = candidateByID[identifier], candidate.kind == .prayerAsk else { continue }
            try updateLedger(requestID: identifier, dayKey: candidate.dayKey,
                             prayer: Self.prayer(for: identifier), dueAt: candidate.dueAt,
                             state: "dropped", reason: "cap", kind: "ask")
        }
    }

    private static func manages(_ id: String) -> Bool { id.hasPrefix(requestPrefix) || RoomNotificationContent.isRoomRequest(id) }
    /// Every non-prayer request (Quran, qada, habits, digest, nudge) through one path: a kind turned off
    /// leaves nothing pending and is logged as cancelled; drops and digests are logged for every room.
    private func reconcileRooms(plan: NotificationPlan, candidates: [NotificationCandidate], current: [UNNotificationRequest], timeZone: TimeZone, consumed: Set<String>, now: Date) async throws {
        guard let session else { return }
        let targets = plan.scheduled.filter { $0.kind != .prayerAsk && !consumed.contains($0.id) }
        let ids = Set(targets.map(\.id)), obsolete = current.filter { !ids.contains($0.identifier) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        for id in obsolete where !consumed.contains(id) {
            try session.notificationBudget.cancel(id: id, now: now)
            try updateLedger(requestID: id, state: "cancelled")
        }
        let habitNames = targets.contains { $0.id.hasPrefix("habits.") }
            ? Dictionary(try HabitRepository(context: ModelContext(session.container)).readings(at: now).map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first }) : [:]
        for candidate in targets {
            let content = RoomNotificationContent.content(for: candidate, plan: plan, session: session, habitNames: habitNames)
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
            var date = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate.dueAt); date.timeZone = timeZone
            do {
                try session.notificationBudget.reserve(.init(id: candidate.id, dayKey: candidate.dayKey, scheduledAt: candidate.dueAt), now: now)
            } catch let error as NotificationBudgetError where error == .full || error == .disabled {
                // Owner real-data trial, 24 Oct 2026: with reminders off (or not yet allowed) a room reminder is
                // simply not scheduled; it is not a failure to show the user.
                center.removePendingNotificationRequests(withIdentifiers: [candidate.id])
                try session.notificationBudget.cancel(id: candidate.id, now: now)
                try updateLedger(requestID: candidate.id, dayKey: candidate.dayKey, dueAt: candidate.dueAt, state: "dropped", reason: error == .full ? "budget" : "disabled")
                continue
            }
            if !current.contains(where: { $0.identifier == candidate.id && Self.matches($0, dueAt: candidate.dueAt) && $0.content.title == content.title && $0.content.body == content.body }) {
                do { try await center.add(UNNotificationRequest(identifier: candidate.id, content: content, trigger: UNCalendarNotificationTrigger(dateMatching: date, repeats: false))) }
                catch {
                    try session.notificationBudget.cancel(id: candidate.id, now: now, requestFailed: true)
                    throw error
                }
            }
            try updateLedger(requestID: candidate.id, dayKey: candidate.dayKey, dueAt: candidate.dueAt, state: "submitted", kind: RoomNotificationContent.ledgerKind(candidate.id))
        }
        for id in plan.digestedIDs where RoomNotificationContent.isRoomRequest(id) && !consumed.contains(id) { try updateLedger(requestID: id, state: "digested") }
        for id in plan.droppedIDs where RoomNotificationContent.isRoomRequest(id) && !consumed.contains(id) {
            guard let candidate = candidates.first(where: { $0.id == id }) else { continue }
            let quiet = Self.isQuiet(candidate.dueAt, timeZone: timeZone, quietAfterIsha: session.bool("notif.quietAfterIsha"), quietFrom: session.string("notif.quietFrom"))
            try updateLedger(requestID: id, dayKey: candidate.dayKey, dueAt: candidate.dueAt, state: "dropped", reason: quiet ? "quiet" : "budget", kind: RoomNotificationContent.ledgerKind(id))
        }
    }
    private func prayerDays(repository: PrayerRepository, now: Date) -> [PrayerDay] {
        let place = repository.place(at: now)
        let options = repository.calculationOptions(at: now)
        let firstDay = repository.prayerDay(at: now)
        return (0..<4).compactMap { offset in
            PrayerTimesEngine.calculate(day: firstDay.adding(days: offset), place: place, options: options)
        }
    }

    private static func pendingSnoozes(from requests: [UNNotificationRequest], prayerDays: [PrayerDay], sanctityWindows: [SanctityWindow], repository: PrayerRepository, now: Date) -> [NotificationCandidate] {
        let guarder = SanctityGuard(windows: sanctityWindows)
        return requests.compactMap { request in
            guard request.identifier.hasPrefix(Self.requestPrefix), request.identifier.hasSuffix(".snooze"),
                  let dayKey = request.content.userInfo["dayKey"] as? String,
                  let prayer = Prayer(rawValue: request.content.userInfo["prayer"] as? String ?? ""),
                  let day = prayerDays.first(where: { $0.day.description == dayKey }),
                  let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let dueAt = trigger.nextTriggerDate(),
                  let cell = try? repository.day(day.day, now: now).cells.first(where: { $0.reference.prayer == prayer }),
                  !isRecorded(cell.status) else { return nil }
            let guarded = guarder.clamp(dueAt)
            return .init(id: request.identifier, room: .salah, kind: .prayerAsk, dueAt: guarded, dayKey: dayKey)
        }
    }

    static func isRecorded(_ status: PrayerDisplayStatus) -> Bool {
        switch status {
        case .jamaah, .alone, .qada, .missed, .excused: true
        case .unrecordedHistory, .unconfirmed, .pending, .future: false
        }
    }

    private static func prayer(for requestID: String) -> Prayer? {
        let parts = requestID.split(separator: ".")
        guard parts.count >= 3 else { return nil }
        return Prayer(rawValue: String(parts[2]))
    }

    private static func makeRequest(candidate: NotificationCandidate, prayer: Prayer, timeZone: TimeZone, snooze: Bool) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = title(prayer)
        content.body = snooze ? "صلّيتها؟" : "مرّ وقت على الأذان. صلّيتها؟"
        content.categoryIdentifier = Self.categoryID
        content.threadIdentifier = "salah.\(candidate.dayKey)"
        content.sound = .default
        content.userInfo = ["requestID": candidate.id, "dayKey": candidate.dayKey, "prayer": prayer.rawValue, "snooze": snooze]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: candidate.dueAt)
        components.timeZone = timeZone
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: candidate.id, content: content, trigger: trigger)
    }

    private static func matches(_ request: UNNotificationRequest, dueAt: Date) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
              let date = trigger.nextTriggerDate() else { return false }
        return abs(date.timeIntervalSince(dueAt)) < 1
    }

    private func reconcilePrayerActivity(prayerSlots: [PrayerNotificationSlot], sanctityWindows: [SanctityWindow], repository: PrayerRepository,
                                         now: Date, session: AppSession) async throws {
        guard #available(iOS 26.0, *) else { return }
        let activities = Activity<PrayerCountdownAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .pending || $0.activityState == .stale
        }
        let stale = activities.filter { $0.activityState == .stale }
        let active = activities.filter { $0.activityState == .active || $0.activityState == .pending }
        for activity in stale { try await endPrayerActivity(activity, now: now) }
        guard session.bool("salah.liveActivity"), session.bool("notif.thisDeviceReminders"),
              ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in active { try await endPrayerActivity(activity, now: now) }
            return
        }
        let occurrences = prayerSlots.map { ($0.occurrence.time, $0.prayer) }.sorted { $0.0 < $1.0 }
        let guarder = SanctityGuard(windows: sanctityWindows)
        let startAt = now
        guard guarder.clamp(startAt) == startAt else {
            for activity in active { try await endPrayerActivity(activity, now: now) }
            return
        }
        let timeZone = repository.place(at: now).timeZone
        guard !Self.isQuiet(startAt, timeZone: timeZone,
                            quietAfterIsha: session.bool("notif.quietAfterIsha"),
                            quietFrom: session.string("notif.quietFrom")) else {
            for activity in active { try await endPrayerActivity(activity, now: now) }
            return
        }
        // ActivityKit may retain the Lock Screen presentation for four hours
        // after its eight-hour active lifetime ends.
        let maximumDisplayedLifetimeEnd = startAt.addingTimeInterval(NotificationArbiter.liveActivityMaximumDisplayedDuration)
        guard let nextIsha = occurrences.first(where: { $0.1 == .isha && $0.0 > startAt }),
              nextIsha.0 > maximumDisplayedLifetimeEnd else {
            for activity in active { try await endPrayerActivity(activity, now: now) }
            return
        }
        guard let next = occurrences.first(where: { $0.0 > startAt }),
              next.0.timeIntervalSince(startAt) <= 8 * 60 * 60 else {
            for activity in active { try await endPrayerActivity(activity, now: now) }
            return
        }
        let previous = occurrences.last(where: { $0.0 <= startAt })
        if previous?.1 == .isha && next.1 == .fajr {
            for activity in active { try await endPrayerActivity(activity, now: now) }
            return
        }
        if active.contains(where: {
            $0.attributes.activityKey == "prayer.next" && abs($0.content.state.prayerAt.timeIntervalSince(next.0)) < 1
        }) { return }
        // Only foreground requests are authorized by RL5. A refresh caused by an
        // inbox/background notification must never try to start an activity.
        guard UIApplication.shared.applicationState == .active else { return }
        let requestID = "activity." + UUID().uuidString
        let reservation: ReservedPrayerActivity
        do { reservation = try session.notificationBudget.reservePrayerActivity(id: requestID, now: now) }
        catch NotificationBudgetError.full { return }
        catch NotificationBudgetError.disabled { return }
        catch NotificationBudgetError.duplicate { return }
        for activity in active { try await endPrayerActivity(activity, now: now) }
        let attributes = PrayerCountdownAttributes(activityKey: "prayer.next", scheduledStartAt: startAt, budgetRequestID: requestID, numerals: reservation.numerals)
        let state = PrayerCountdownAttributes.ContentState(prayerName: Self.title(next.1), prayerAt: next.0)
        let content = ActivityContent(state: state, staleDate: next.0, relevanceScore: 1)
        // Persist the reservation before asking the OS, so a failed save can never
        // leave a scheduled alert outside the device ledger.
        try updateLedger(requestID: requestID, dayKey: reservation.reservation.dayKey, dueAt: reservation.reservation.scheduledAt,
                         state: "submitted", kind: "activityStart")
        do {
            _ = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard)
        } catch {
            try session.notificationBudget.cancel(id: requestID, now: now, requestFailed: true)
            try updateLedger(requestID: requestID, state: "cancelled")
            throw error
        }
    }

    private func endPrayerActivity(_ activity: Activity<PrayerCountdownAttributes>, now: Date) async throws {
        await activity.end(nil, dismissalPolicy: .immediate)
        // A submitted start keeps consuming its slot once its scheduled time has
        // passed; we do not infer whether the system delivered the alert.
        if activity.attributes.scheduledStartAt > now, let id = activity.attributes.budgetRequestID {
            try session?.notificationBudget.cancel(id: id, now: now)
            try updateLedger(requestID: id, state: "cancelled")
        }
    }

    /// Context surfaces have no alert configuration, but RL5 still budgets every start and gates its window.
    private func reconcileContextActivities(prayerDays: [PrayerDay], prayerSlots: [PrayerNotificationSlot], sanctityWindows: [SanctityWindow],
                                            repository: PrayerRepository, now: Date, session: AppSession) async throws {
        guard #available(iOS 26.0, *), UIApplication.shared.applicationState == .active else { return }

        let eligibleLetterAt: Date?
        if session.lockController?.canPresent(.notes) ?? session.protectedDataAuthorized {
            let context = ModelContext(session.container)
            let eligibleDescriptor = FetchDescriptor<Letter>(predicate: #Predicate<Letter> { $0.state == "eligible" })
            let eligibleRows: [Letter] = try context.fetch(eligibleDescriptor)
            let eligibleLetters = eligibleRows.filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.openedAt == nil }
            eligibleLetterAt = eligibleLetters.compactMap(\.eligibleAt).min() ?? (eligibleLetters.isEmpty ? nil : now)
        } else {
            // The whole-app Face ID gate also protects diary rows. Do not fault
            // private Letter models into memory until that gate has opened.
            eligibleLetterAt = nil
        }
        let trip = repository.activeTrip(at: now).map {
            MadarContextTripFact(city: $0.city, timeZoneID: $0.place.timeZoneID, startsAt: $0.start, endsAt: $0.end)
        }
        let iftarAt = prayerSlots
            .filter { $0.prayer == .maghrib && $0.prayerDay.hijriDate?.month == 9 && $0.occurrence.time > now
                && $0.occurrence.time.timeIntervalSince(now) <= MadarContextActivityPlanner.maximumActiveDuration }
            .min { $0.occurrence.time < $1.occurrence.time }?.occurrence.time
        let plans = MadarContextActivityPlanner.plans(now: now, eligibleLetterAt: eligibleLetterAt, trip: trip, iftarAt: iftarAt)
        let activities = Activity<MadarContextActivityAttributes>.activities.filter {
            $0.activityState == .active || $0.activityState == .pending || $0.activityState == .stale
        }

        guard ActivityAuthorizationInfo().areActivitiesEnabled else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let zone = repository.place(at: now).timeZone
        let occurrences = prayerSlots.map { ($0.occurrence.time, $0.prayer) }
        let quietParts = session.string("notif.quietFrom").split(separator: ":").compactMap { Int($0) }
        let quietFrom = session.bool("notif.quietAfterIsha")
            ? (quietParts.count == 2 ? quietParts[0] * 60 + quietParts[1] : 0) : nil
        let policy = NotificationPolicy(dailyBudget: Int(session.number("notif.dailyBudget")), quietFromMinutes: quietFrom,
                                        thisDeviceRemindersEnabled: session.bool("notif.thisDeviceReminders"),
                                        dayBoundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr)
        guard session.bool("salah.liveActivity"),
              NotificationArbiter.contextActivityWindowAllows(now, prayerDays: prayerDays, timeZone: zone, policy: policy,
                                                               occurrences: occurrences, sanctityWindows: sanctityWindows) else {
            for activity in activities { await activity.end(nil, dismissalPolicy: .immediate) }
            return
        }

        let numerals = session.string("core.numerals") == "western" ? "western" : "hindi"
        var represented = Set<String>()
        for activity in activities {
            guard activity.activityState != .stale,
                  let plan = plans.first(where: { $0.activityKey == activity.attributes.activityKey }),
                  activity.attributes.kind == plan.kind,
                  activity.attributes.numerals == numerals,
                  represented.insert(plan.activityKey).inserted else {
                await activity.end(nil, dismissalPolicy: .immediate)
                continue
            }
            let staleAt = Self.contextActivityStaleDate(plan: plan, startedAt: activity.attributes.startedAt,
                                                        prayerSlots: prayerSlots, timeZone: zone, quietFromMinutes: quietFrom)
            let content = ActivityContent(state: plan.state, staleDate: staleAt, relevanceScore: 0.7)
            if activity.content.state != plan.state || activity.content.staleDate != staleAt {
                await activity.update(content)
            }
        }

        for plan in plans where !represented.contains(plan.activityKey) {
            let requestID = "activity.context.\(plan.activityKey).\(UUID().uuidString)"
            let eventSecond = Int((plan.eventAt ?? now).timeIntervalSince1970)
            let purpose = "context.\(plan.activityKey).\(eventSecond)"
            let reservation: NotificationBudgetReservation
            do {
                reservation = try session.notificationBudget.reserveContextActivity(id: requestID, purpose: purpose, now: now)
            } catch {
                continue
            }
            let attributes = MadarContextActivityAttributes(activityKey: plan.activityKey, kind: plan.kind,
                                                             startedAt: now, numerals: numerals)
            let staleAt = Self.contextActivityStaleDate(plan: plan, startedAt: now, prayerSlots: prayerSlots,
                                                        timeZone: zone, quietFromMinutes: quietFrom)
            let content = ActivityContent(state: plan.state, staleDate: staleAt, relevanceScore: 0.7)
            do {
                try updateLedger(requestID: requestID, dayKey: reservation.dayKey, dueAt: reservation.scheduledAt,
                                 state: "submitted", kind: "activityStart")
            } catch {
                try? session.notificationBudget.cancel(id: requestID, now: now, requestFailed: true)
                throw error
            }
            do {
                _ = try Activity.request(attributes: attributes, content: content, pushType: nil, style: .standard)
            } catch {
                try? session.notificationBudget.cancel(id: requestID, now: now, requestFailed: true)
                try? updateLedger(requestID: requestID, state: "cancelled")
            }
        }
    }

    private static func contextActivityStaleDate(plan: MadarContextActivityPlan, startedAt: Date,
                                                 prayerSlots: [PrayerNotificationSlot], timeZone: TimeZone,
                                                 quietFromMinutes: Int?) -> Date {
        let maximumEnd = startedAt.addingTimeInterval(MadarContextActivityPlanner.maximumActiveDuration)
        var end = min(plan.staleAt ?? maximumEnd, maximumEnd)
        if let nextIsha = prayerSlots.filter({ $0.prayer == .isha }).map(\.occurrence.time).filter({ $0 > startedAt }).min() {
            end = min(end, nextIsha)
        }
        if let quietFromMinutes, let quietAt = nextQuietBoundary(after: startedAt, timeZone: timeZone,
                                                                 quietFromMinutes: quietFromMinutes) {
            end = min(end, quietAt)
        }
        return end
    }

    private static func nextQuietBoundary(after instant: Date, timeZone: TimeZone, quietFromMinutes: Int) -> Date? {
        guard (0..<1440).contains(quietFromMinutes) else { return nil }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let today = calendar.dateComponents([.year, .month, .day], from: instant)
        var cutoff = DateComponents()
        cutoff.year = today.year; cutoff.month = today.month; cutoff.day = today.day
        cutoff.hour = quietFromMinutes / 60; cutoff.minute = quietFromMinutes % 60
        guard let first = calendar.date(from: cutoff) else { return nil }
        if first > instant { return first }
        return calendar.date(byAdding: .day, value: 1, to: first)
    }

    func activityBudgetCounts() throws -> [String: Int] {
        guard let session else { return [:] }
        let container = try session.managedStore?.containerForTransaction() ?? session.container
        let rows = try ModelContext(container).fetch(FetchDescriptor<NotificationLedger>())
        return Self.activityBudgetCounts(rows: rows)
    }

    static func activityBudgetCounts(rows: [NotificationLedger]) -> [String: Int] {
        var counts: [String: Set<String>] = [:]
        for row in rows where row.deletedAt == nil && ["room", "digest", "nudge"].contains(row.requestClass)
            && ["submitted", "observed"].contains(row.state) {
            // Natural request identity avoids counting duplicate ledger rows.
            counts[row.dayKey, default: []].insert(row.requestID)
        }
        return counts.mapValues(\.count)
    }

    private static func isQuiet(_ date: Date, timeZone: TimeZone, quietAfterIsha: Bool, quietFrom: String) -> Bool {
        guard quietAfterIsha else { return false }
        let parts = quietFrom.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return true }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let current = calendar.dateComponents([.hour, .minute], from: date)
        guard let currentHour = current.hour, let currentMinute = current.minute else { return true }
        return currentHour * 60 + currentMinute >= hour * 60 + minute
    }

    private func updateLedger(requestID: String, dayKey: String? = nil, prayer: Prayer? = nil, dueAt: Date? = nil,
                              state: String, reason: String? = nil, kind: String? = nil) throws {
        guard let session else { return }
        let container: ModelContainer
        if let store = session.managedStore { container = try store.containerForTransaction() }
        else { container = session.container }
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<NotificationLedger>()).filter { $0.deletedAt == nil && $0.requestID == requestID }
        if state == "submitted", let dueAt,
           let current = rows.first(where: { $0.state == "submitted" && abs($0.scheduledFor.timeIntervalSince(dueAt)) < 1 }) {
            for duplicate in rows where duplicate.state == "submitted" && duplicate.id != current.id {
                duplicate.state = "cancelled"; duplicate.updatedAt = Date()
            }
            if !context.hasChanges { return }
            try context.save(); return
        }
        if state == "submitted" {
            for row in rows where row.state == "submitted" { row.state = "cancelled"; row.updatedAt = Date() }
            let row = NotificationLedger()
            row.dayKey = dayKey ?? rows.last?.dayKey ?? ""
            row.requestID = requestID
            row.room = requestID.hasPrefix("quran.") ? "quran" : requestID.hasPrefix("digest.") ? "core" : requestID.hasPrefix("mal.") ? "mal" : "salah"
            row.kind = kind ?? (requestID.hasSuffix(".snooze") ? "snooze" : "ask")
            row.requestClass = requestID.hasPrefix("digest.") ? "digest" : requestID.hasPrefix("quran.") || requestID.hasPrefix("mal.") || kind == "activityStart" ? "room" : "prayer"
            row.scheduledFor = dueAt ?? Date()
            row.state = state
            row.reason = reason
            row.writerID = "madar.app.notifications"
            context.insert(row)
        } else {
            for row in rows where row.state == "submitted" {
                row.state = state; row.reason = reason; row.updatedAt = Date()
            }
            if state == "dropped", let dueAt,
               !rows.contains(where: { $0.state == "dropped" && $0.scheduledFor == dueAt && $0.reason == reason }) {
                let row = NotificationLedger()
                row.dayKey = dayKey ?? ""; row.requestID = requestID; row.room = requestID.hasPrefix("quran.") ? "quran" : "salah"
                row.kind = kind ?? "ask"; row.requestClass = requestID.hasPrefix("quran.") || requestID.hasPrefix("mal.") ? "room" : "prayer"; row.scheduledFor = dueAt
                row.state = state; row.reason = reason; row.writerID = "madar.app.notifications"
                context.insert(row)
            }
        }
        try context.save()
        _ = prayer
    }

    private func updateAuthorizationState() async {
        guard let session else { return }
        let status = await authorizationStatus()
        session.updateNotificationAuthorization(Self.authorizationCode(status))
    }

    private func authorizationStatus() async -> UNAuthorizationStatus {
        return await center.notificationSettings().authorizationStatus
    }

    private static func authorizationCode(_ status: UNAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: "notDetermined"
        case .denied: "denied"
        case .authorized: "authorized"
        case .provisional: "provisional"
        case .ephemeral: "ephemeral"
        @unknown default: "unknown"
        }
    }

    private static func canSchedule(_ status: UNAuthorizationStatus) -> Bool {
        status == .authorized || status == .provisional || status == .ephemeral
    }

    private static func title(_ prayer: Prayer) -> String {
        switch prayer {
        case .fajr: "الفجر"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }
}

@MainActor
final class MadarApplicationDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    let runtime = MadarRuntime()
    var prayerNotifications: PrayerNotificationCoordinator { runtime.prayerNotifications }
    private lazy var backgroundBackups = AppBackupBackgroundTasks { [weak self] in
        guard let self else { throw DataError.invalidValue("session unavailable") }
        await runtime.load()
        guard let service = runtime.session?.backupService as? AppBackupService else {
            throw DataError.invalidValue("session unavailable")
        }
        return service
    }

    func application(_ application: UIApplication, willFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        runtime.backgroundBackups = backgroundBackups
        backgroundBackups.register()
        prayerNotifications.install(delegate: self)
        return true
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification,
                                            withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        let completion = PresentationCompletion(completionHandler)
        Task { @MainActor [weak self, completion] in
            completion.call(await self?.prayerNotifications.foregroundOptions(for: notification) ?? [])
        }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse,
                                            withCompletionHandler completionHandler: @escaping () -> Void) {
        let completion = ResponseCompletion(completionHandler)
        Task { @MainActor [weak self, completion] in
            await self?.prayerNotifications.handle(response)
            completion.call()
        }
    }
}

#if DEBUG
private struct NotificationScenarioFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

extension PrayerNotificationCoordinator {
    func runSimulatorAcceptanceScenarioForTesting() async throws -> String {
        guard let session else { throw NotificationScenarioFailure(message: "Notification test session is unavailable") }
        guard session.bool("salah.askReminder"), session.bool("notif.thisDeviceReminders") else {
            throw NotificationScenarioFailure(message: "Prayer reminders are disabled in the test store")
        }
        guard Self.canSchedule(await authorizationStatus()) else {
            throw NotificationScenarioFailure(message: "The app process does not have notification authorization")
        }

        let alreadyPending = await center.pendingNotificationRequests()
        let priorPrayerIDs = alreadyPending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) }
        var cleanupIDs = Set(priorPrayerIDs)
        center.removePendingNotificationRequests(withIdentifiers: priorPrayerIDs)
        defer {
            center.removePendingNotificationRequests(withIdentifiers: Array(cleanupIDs))
        }

        let now = Date()
        let repository = try PrayerRepository(context: ModelContext(session.container))
        let days = prayerDays(repository: repository, now: now)
        guard let target = days.first(where: { $0.fajr > now.addingTimeInterval(2 * 60 * 60) }) else {
            throw NotificationScenarioFailure(message: "No upcoming Fajr found inside the test horizon")
        }
        let fajrID = "salah.\(target.day.description).fajr"
        let snoozeID = "salah.\(target.day.description).maghrib.snooze"

        try await refresh(now: now)
        var pending = await center.pendingNotificationRequests()
        cleanupIDs.formUnion(pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) })
        guard let fajrRequest = pending.first(where: { $0.identifier == fajrID }),
              let fajrAt = (fajrRequest.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
              abs(fajrAt.timeIntervalSince(target.fajr.addingTimeInterval(30 * 60))) < 1 else {
            throw NotificationScenarioFailure(message: "The app process did not schedule the expected Fajr request")
        }

        guard let ishaWindow = target.sanctityWindows.first(where: { $0.prayer == .isha }) else {
            throw NotificationScenarioFailure(message: "The Isha sanctity fixture is unavailable")
        }
        let content = UNMutableNotificationContent()
        content.userInfo = ["dayKey": target.day.description, "prayer": Prayer.maghrib.rawValue]
        let source = UNNotificationRequest(identifier: "salah.\(target.day.description).maghrib", content: content, trigger: nil)
        try await scheduleSnooze(for: source, tapTime: target.isha.addingTimeInterval(-50 * 60))

        pending = await center.pendingNotificationRequests()
        cleanupIDs.formUnion(pending.map(\.identifier).filter { $0.hasPrefix(Self.requestPrefix) })
        guard let snoozeRequest = pending.first(where: { $0.identifier == snoozeID }),
              let snoozeAt = (snoozeRequest.trigger as? UNCalendarNotificationTrigger)?.nextTriggerDate(),
              abs(snoozeAt.timeIntervalSince(ishaWindow.end)) < 1,
              !ishaWindow.contains(snoozeAt) else {
            throw NotificationScenarioFailure(message: "The Maghrib snooze was not clamped past Isha sanctity")
        }

        let cancellationDay = target.day.adding(days: -1)
        let cancellationID = "salah.\(cancellationDay.description).fajr"
        guard repository.prayerDay(at: now) == cancellationDay,
              let cancellationPrayerAt = repository.occurrence(.init(day: cancellationDay, prayer: .fajr))?.time,
              cancellationPrayerAt <= now else {
            throw NotificationScenarioFailure(message: "No completed Fajr is available for the logging cancellation check")
        }
        let cancellationDueAt = now.addingTimeInterval(6 * 60 * 60)
        let cancellationCandidate = NotificationCandidate(id: cancellationID, room: .salah, kind: .prayerAsk,
                                                            dueAt: cancellationDueAt, dayKey: cancellationDay.description)
        try await center.add(Self.makeRequest(candidate: cancellationCandidate, prayer: .fajr,
                                              timeZone: target.place.timeZone, snooze: false))
        try updateLedger(requestID: cancellationID, dayKey: cancellationDay.description, prayer: .fajr,
                         dueAt: cancellationDueAt, state: "submitted", kind: "ask")
        cleanupIDs.insert(cancellationID)

        let logged = await withCheckedContinuation { continuation in
            session.recordPrayer(.init(day: cancellationDay, prayer: .fajr), status: .jamaah) {
                continuation.resume(returning: $0)
            }
        }
        guard logged else { throw NotificationScenarioFailure(message: session.errorMessage ?? "Fajr log did not commit") }

        pending = await center.pendingNotificationRequests()
        guard !pending.contains(where: { $0.identifier == cancellationID }),
              pending.contains(where: { $0.identifier == snoozeID }) else {
            throw NotificationScenarioFailure(message: "Prayer logging did not cancel only the matching Fajr request")
        }
        let ledgerRows = try ModelContext(session.container).fetch(FetchDescriptor<NotificationLedger>())
            .filter { $0.deletedAt == nil && $0.requestID == cancellationID }
        guard ledgerRows.max(by: { $0.updatedAt < $1.updatedAt })?.state == "cancelled" else {
            throw NotificationScenarioFailure(message: "The Fajr cancellation was not recorded in NotificationLedger")
        }

        for identifier in cleanupIDs { try updateLedger(requestID: identifier, state: "cancelled") }
        return "PASS — scheduled Fajr, clamped Maghrib snooze past Isha, and cancelled Fajr after logging"
    }
}

struct PrayerNotificationAcceptanceHarness: View {
    let session: AppSession

    var body: some View {
        VStack(spacing: 16) {
            Text("اختبار إشعارات الصلاة")
                .font(.title2.bold())
            Text("الإذن: \(session.notificationAuthorization)")
                .accessibilityIdentifier("notification-test-authorization")
            if session.canRequestNotificationPermission {
                Button("السماح بالإشعارات") { session.requestPrayerNotificationPermission() }
                    .accessibilityIdentifier("notification-test-authorize")
            }
            if session.shouldOpenNotificationSettings {
                Button("فتح إعدادات الإشعارات") { session.openPrayerNotificationSettings() }
                    .accessibilityIdentifier("notification-test-settings")
            }
            Button("تشغيل سيناريو التحقق") { session.runNotificationScenarioForTesting() }
                .disabled(!session.notificationsAuthorized)
                .accessibilityIdentifier("notification-test-run")
            Text(session.notificationTestResult.isEmpty ? "بانتظار التشغيل" : session.notificationTestResult)
                .accessibilityIdentifier("notification-test-result")
                .accessibilityLabel(session.notificationTestResult.isEmpty ? "بانتظار التشغيل" : session.notificationTestResult)
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(uiColor: .systemBackground))
        .environment(\.layoutDirection, .rightToLeft)
    }
}
#endif

private final class PresentationCompletion: @unchecked Sendable {
    private let handler: (UNNotificationPresentationOptions) -> Void
    init(_ handler: @escaping (UNNotificationPresentationOptions) -> Void) { self.handler = handler }
    @MainActor func call(_ options: UNNotificationPresentationOptions) { handler(options) }
}

private final class ResponseCompletion: @unchecked Sendable {
    private let handler: () -> Void
    init(_ handler: @escaping () -> Void) { self.handler = handler }
    @MainActor func call() { handler() }
}
