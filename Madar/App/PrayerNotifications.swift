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
                                    occurrence: occurrence))
            }
        }
        return result
    }

    static func sanctityWindows(for slots: [PrayerNotificationSlot]) -> [SanctityWindow] {
        slots.compactMap { slot in slot.prayerDay.sanctityWindows.first { $0.prayer == slot.prayer } }
    }
}

@MainActor
final class PrayerNotificationCoordinator {
    static let habitCategoryID = "habits.reminder"
    static let habitDoneActionID = "habits.done"
    static let wirdCategoryID = "quran.wird"
    static let wirdDoneActionID = "quran.wirdDone"
    private static let requestPrefix = "salah."

    struct ActionResponse {
        let request: UNNotificationRequest
        let actionIdentifier: String
        let userText: String?
    }

    private let center: UNUserNotificationCenter
    private weak var session: AppSession?
    private var pendingResponses: [ActionResponse] = []
    private var lifecycleOperationInProgress = false
    private var lifecycleOperationWaiters: [CheckedContinuation<Void, Never>] = []

    init(center: UNUserNotificationCenter = .current()) { self.center = center }

    func install(delegate: UNUserNotificationCenterDelegate) {
        center.delegate = delegate
        // T11: a habit reminder can be finished from the notification itself.
        let habitDone = UNNotificationAction(identifier: Self.habitDoneActionID, title: "تمّت", options: [])
        let habit = UNNotificationCategory(identifier: Self.habitCategoryID, actions: [habitDone], intentIdentifiers: [], options: [])
        // 14 Nov owner: finish the whole wird from its reminder. It opens Madar on the grade question; nothing is recorded in the background.
        let wirdDone = UNNotificationAction(identifier: Self.wirdDoneActionID, title: "أتممته", options: [.foreground])
        let wird = UNNotificationCategory(identifier: Self.wirdCategoryID, actions: [wirdDone], intentIdentifiers: [], options: [])
        baseCategories = [habit, wird]
        center.setNotificationCategories(baseCategories)
    }
    private var baseCategories: Set<UNNotificationCategory> = []
    static let habitAmountPrefix = "habits.amount."
    static func habitAmountCategoryID(_ habit: UUID) -> String { habitAmountPrefix + habit.uuidString }
    /// Idea 1 (owner, 17 Nov 2026): a habit counted in an amount (cups, pages, minutes, km) is logged from its reminder:
    /// the whole goal, half of it, or «كمية ثانية» for any number — even below the goal, saved as typed.
    /// Each habit has its own category so the buttons name the real amount («٨ أكواب») instead of a label.
    func registerHabitAmountCategories(_ readings: [HabitReading], digits: MadarNumberFormatter) {
        guard !baseCategories.isEmpty else { return }
        let amounts = readings.compactMap { reading -> UNNotificationCategory? in
            guard reading.source == nil, !reading.archived, let rule = reading.summary.current?.rule,
                  rule.measure == .count || rule.measure == .duration, rule.target > 1 else { return nil }
            let unit = rule.measure == .duration ? (rule.unit ?? "minutes") : rule.unit
            var actions: [UNNotificationAction] = [UNNotificationAction(identifier: Self.habitAmountPrefix + "full", title: habitUnitCount(rule.target, unit, digits), options: [])]
            if rule.target >= 2 { actions.append(UNNotificationAction(identifier: Self.habitAmountPrefix + "half", title: habitUnitCount(rule.target / 2, unit, digits), options: [])) }
            actions.append(UNTextInputNotificationAction(identifier: Self.habitAmountPrefix + "other", title: "كمية ثانية", options: [], textInputButtonTitle: "سجّل", textInputPlaceholder: unit.map { "كم " + habitUnitName($0) + "؟" } ?? "كم؟"))
            return UNNotificationCategory(identifier: Self.habitAmountCategoryID(reading.id), actions: actions, intentIdentifiers: [], options: [])
        }
        center.setNotificationCategories(baseCategories.union(amounts))
    }

    func attach(to session: AppSession) async {
        self.session = session
        await updateAuthorizationState()
        let queued = pendingResponses
        pendingResponses.removeAll()
        for response in queued { await handle(response) }
        // Owner 7 Nov 2026 («أول ما أفتح التطبيق يعلق»): planning every reminder took about two seconds on the main thread and ran
        // before the first screen. In the foreground the plan follows the first frame (the lobby's launch task asks for it);
        // a background launch (a notification answered while Madar was closed) still plans now, before it can be suspended.
        if UIApplication.shared.applicationState == .background {
            do { try await refresh() }
            catch { session.errorMessage = "تعذّر إعداد التذكيرات. \(madarUserMessage(error))" }
        } else {
            requestRefresh()
        }
    }

    /// One plan for a burst of asks (launch, return to the app, unlock, several saves in a row), run once they settle.
    /// In the background, where the app may be suspended at any moment, the plan runs at once.
    private var pendingRefresh: Task<Void, Never>?
    func requestRefresh(after delay: Duration = .milliseconds(1200)) {
        guard UIApplication.shared.applicationState != .background else {
            pendingRefresh?.cancel(); pendingRefresh = nil
            Task { [weak self] in await self?.refreshReportingFailure() }
            return
        }
        pendingRefresh?.cancel()
        pendingRefresh = Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            guard let self, !Task.isCancelled else { return }
            self.pendingRefresh = nil
            await self.refreshReportingFailure()
        }
    }
    /// Leaving the app: a waiting plan runs now, inside the scene's background grant.
    func flushPendingRefresh() async {
        guard let task = pendingRefresh else { return }
        task.cancel(); pendingRefresh = nil
        await refreshReportingFailure()
    }
    private func refreshReportingFailure() async {
        do { try await refresh() }
        catch { session?.errorMessage = "تعذّر تحديث التذكيرات. \(madarUserMessage(error))" }
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
        pendingRefresh?.cancel(); pendingRefresh = nil
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
        // In the foreground a save no longer waits about two seconds for the whole plan (owner 7 Nov: taps froze); the plan follows
        // once the saves settle. In the background (logging from a notification) it still runs under the lock before suspension.
        if UIApplication.shared.applicationState != .background && !AppSession.publishesSnapshotsImmediately { requestRefresh(); return }
        do { try await refreshLocked(session: session, suppliedNow: nil) }
        catch {
            guard !isExpectedNoPrayerBoundary(error, session: session) else { return }
            session.errorMessage = "تعذّر تحديث التذكيرات. \(madarUserMessage(error))"
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
        catch { session?.errorMessage = "تعذّر تحديث التذكيرات بعد تحديث البيانات. \(madarUserMessage(error))" }
    }

    private func refreshLocked(session: AppSession, suppliedNow: Date?) async throws {
        // A read for the re-plan: every writer reloads its own rooms, so this one does not reload every page again.
        try session.reload(domains: [])
        let now = suppliedNow ?? session.prayerNow()
        try session.publishNotificationBudget(at: now)
        pruneLedgerOncePerDay(now: now)
        let repository = try PrayerRepository(context: ModelContext(session.container))
        let days = prayerDays(repository: repository, now: now)
        let prayerSlots = try PrayerNotificationSchedule.slots(repository: repository, days: days, now: now)
        let sanctityWindows = PrayerNotificationSchedule.sanctityWindows(for: prayerSlots)
        let currentAuthorization = await authorizationStatus()
        session.updateNotificationAuthorization(Self.authorizationCode(currentAuthorization))

        // Owner 17 Nov 2026: no prayer logging, so no «صلّيتها؟» ask and no before-adhan alert; the times only anchor other reminders.
        let existing = await center.pendingNotificationRequests()
        var candidates: [NotificationCandidate] = []

        let globalEnabled = session.bool("notif.thisDeviceReminders") && Self.canSchedule(currentAuthorization)
        if globalEnabled {
            // Each stage reads a different room on the main thread: let pending touches through between them.
            await Task.yield()
            candidates += try AppQuranService(session: session, clock: { now }).notificationCandidates(prayerDays: days, now: now)
            await Task.yield()
            candidates += try await RoomNotificationContent.candidates(session: session, prayerDays: days, now: now)
            await Task.yield()
        }
        let planningDays = RoomNotificationContent.planningPrayerDays(session: session, candidates: candidates, current: days, now: now)
        let externalPendingCount = existing.filter { !Self.manages($0.identifier) }.count
        let ledger = try ModelContext(session.container).fetch(FetchDescriptor<NotificationLedger>()).filter { RoomNotificationContent.tracksReminderBudget($0) }
        let consumed = ledger.filter { $0.scheduledFor <= now || $0.kind == "activityStart" }
        let sharedConsumed = try session.notificationBudget.reservations().filter { $0.scheduledAt <= now || $0.activity }
        let counts = Dictionary(grouping: sharedConsumed, by: \.dayKey).mapValues { Set($0.map(\.id)).count }
        let quiet = session.string("notif.quietFrom").split(separator: ":").compactMap { Int($0) }
        let quietMinutes = session.bool("notif.quietAfterIsha") ? (quiet.count == 2 ? quiet[0] * 60 + quiet[1] : 0) : nil
        let priority: [Room]
        if case .array(let order)? = session.values["notif.roomPriority"] { priority = order.compactMap { $0.string.flatMap(Room.init(rawValue:)) } }
        else { priority = [.quran, .habits, .notes, .salah, .mal, .mihbara] }
        let plan = NotificationArbiter.plan(
            candidates: candidates,
            prayerDays: planningDays,
            now: now,
            timeZone: repository.place(at: now).timeZone,
            policy: .init(dailyBudget: Int(session.number("notif.dailyBudget")), priority: priority, quietFromMinutes: quietMinutes, quietUntil: quietEnd,
                digestEnabled: session.bool("notif.digestOverflow"), thisDeviceRemindersEnabled: globalEnabled, staleNudgeEnabled: session.bool("notif.staleNudge"),
                notesDailyCap: Int(session.number("notes.dailyCap")),
                dayBoundary: DayBoundary(rawValue: session.string("core.dayStart")) ?? .fajr),
            existingPendingCount: externalPendingCount, disabledIDs: Set(consumed.map(\.requestID)), submittedBudgetByDay: counts,
            // The arbiter uses only the windows it is given, so the extension days planned for room reminders (zakat, annual) carry their own windows too.
            sanctityWindows: sanctityWindows + planningDays.flatMap(\.sanctityWindows)
        )
        try cancelRetiredPrayerRequests(existing.filter { $0.identifier.hasPrefix(Self.requestPrefix) })
        try await reconcileRooms(plan: plan, candidates: candidates, current: existing.filter { RoomNotificationContent.isRoomRequest($0.identifier) }, timeZone: repository.place(at: now).timeZone, consumed: Set(consumed.map(\.requestID)), prayerDays: planningDays, now: now)
        try await endRetiredPrayerCountdowns(now: now)
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
        await handle(ActionResponse(request: response.notification.request,
                                    actionIdentifier: response.actionIdentifier,
                                    userText: (response as? UNTextInputNotificationResponse)?.userText))
    }

    func handle(_ response: ActionResponse) async {
        guard let session else { pendingResponses.append(response); return }
        guard session.beginNotificationStoreAccess() else { pendingResponses.append(response); return }
        defer { session.endNotificationStoreAccess() }
        let request = response.request
        do {
            // Habit completion drains the inbox under this same lock. Release it after recording the response.
            try await withSerializedMutation { try updateLedger(requestID: request.identifier, state: "observed") }
            if response.actionIdentifier == Self.habitDoneActionID {
                let info = request.content.userInfo
                guard let dayKey = info["dayKey"] as? String, let habit = (info["habit"] as? String).flatMap(UUID.init(uuidString:)) else { return }
                try await session.completeHabitFromNotification(habitID: habit, dayKey: dayKey, requestID: request.identifier)
            } else if response.actionIdentifier.hasPrefix(Self.habitAmountPrefix) {
                let info = request.content.userInfo
                guard let dayKey = info["dayKey"] as? String, let habit = (info["habit"] as? String).flatMap(UUID.init(uuidString:)) else { return }
                let reading = try HabitRepository(context: ModelContext(session.container)).readings(at: Date()).first { $0.id == habit }
                let target = (info["amount"] as? Int) ?? reading?.summary.current?.target ?? 1
                let action = String(response.actionIdentifier.dropFirst(Self.habitAmountPrefix.count))
                let amount: Int?
                switch action {
                case "full": amount = target
                case "half": amount = target / 2
                default: amount = response.userText.flatMap(Self.typedAmount)
                }
                guard let amount, amount > 0 else { session.errorMessage = "لم أفهم الكمية؛ اكتبها رقمًا."; return }
                try await session.completeHabitFromNotification(habitID: habit, dayKey: dayKey, requestID: request.identifier, delta: amount, action: action)
            } else if response.actionIdentifier == Self.wirdDoneActionID {
                // A reminder left in the centre from an earlier day never finishes today's wird: it only opens the room.
                let sent = request.content.userInfo["dayKey"] as? String
                let today = try? AppDiaryService(app: session).currentDay().description
                session.open(URL(string: sent != nil && sent == today ? "madar://quran/finish-whole" : "madar://quran")!)
            } else if response.actionIdentifier == UNNotificationDefaultActionIdentifier {
                if RoomNotificationContent.isRoomRequest(request.identifier) { RoomNotificationContent.open(request.identifier, userInfo: request.content.userInfo, session: session) }
                else { session.selectedTab = "habits" }
            }
        } catch { session.errorMessage = "تعذّر تنفيذ التذكير. \(madarUserMessage(error))" }
    }

    /// «٣»، «3»، «٢٫٥» → a whole amount (a fraction rounds to the nearest; below one half is not an amount).
    nonisolated static func typedAmount(_ text: String) -> Int? {
        let map: [Character: Character] = ["٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9","٫":".","،":".",",":"."]
        var digits = String(text.trimmingCharacters(in: .whitespacesAndNewlines).map { c in c.wholeNumberValue.map { Character(String($0)) } ?? c })
        // «١٬٠٠٠» and «1,000» are thousands, not a fraction: «٬» always groups, «,» only in whole groups of three.
        digits.removeAll { $0 == "٬" }
        if digits.contains(","), digits.wholeMatch(of: /[0-9]{1,3}(,[0-9]{3})+/) != nil { digits.removeAll { $0 == "," } }
        let latin = String(digits.map { map[$0] ?? $0 })
        guard latin.allSatisfy({ ($0.isASCII && $0.isNumber) || $0 == "." }),
              let value = Double(latin), value >= 0.5, value <= 100_000 else { return nil }
        return Int(value.rounded())
    }

    func foregroundOptions(for notification: UNNotification) async -> UNNotificationPresentationOptions {
        guard let session, session.beginNotificationStoreAccess() else { return [] }
        defer { session.endNotificationStoreAccess() }
        await acquireLifecycleLock()
        defer { releaseLifecycleLock() }
        let now = Date()
        do {
            try session.reload(domains: [])
            if RoomNotificationContent.isRoomRequest(notification.request.identifier) {
                guard session.bool("notif.thisDeviceReminders") else { return [] }
                let repository = try PrayerRepository(context: ModelContext(session.container)), days = prayerDays(repository: repository, now: now)
                guard SanctityGuard(prayerDays: days).clamp(now) == now,
                      try RoomNotificationContent.stillRelevant(notification.request.identifier, session: session, now: now) else { return [] }
                try updateLedger(requestID: notification.request.identifier, state: "observed")
                return [.banner, .list, .sound]
            }
            // Anything else is a leftover of the retired prayer ask: it never shows.
            return []
        } catch {
            session.errorMessage = "تعذّر التحقق من وقت التذكير. \(madarUserMessage(error))"
            return []
        }
    }

    private static func manages(_ id: String) -> Bool { id.hasPrefix(requestPrefix) || RoomNotificationContent.isRoomRequest(id) }
    /// Every non-prayer request (Quran, qada, habits, digest, nudge) through one path: a kind turned off
    /// leaves nothing pending and is logged as cancelled; drops and digests are logged for every room.
    private func reconcileRooms(plan: NotificationPlan, candidates: [NotificationCandidate], current: [UNNotificationRequest], timeZone: TimeZone, consumed: Set<String>, prayerDays: [PrayerDay], now: Date) async throws {
        guard let session else { return }
        let targets = plan.scheduled.filter { !$0.kind.isPrayerLane && !consumed.contains($0.id) }
        let ids = Set(targets.map(\.id)), obsolete = current.filter { !ids.contains($0.identifier) }.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: obsolete)
        for id in obsolete where !consumed.contains(id) {
            try session.notificationBudget.cancel(id: id, now: now)
            try updateLedger(requestID: id, state: "cancelled")
        }
        let habitReadings = targets.contains { $0.id.hasPrefix("habits.") } ? try HabitRepository(context: ModelContext(session.container)).readings(at: now) : []
        let habitNames = Dictionary(habitReadings.map { ($0.id.uuidString, $0.name) }, uniquingKeysWith: { first, _ in first })
        if !habitReadings.isEmpty { registerHabitAmountCategories(habitReadings, digits: MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)) }
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
                try updateLedger(requestID: candidate.id, dayKey: candidate.dayKey, dueAt: candidate.dueAt, state: "dropped",
                                 reason: error == .full ? "budget" : "disabled", kind: RoomNotificationContent.ledgerKind(candidate.id))
                continue
            }
            if !current.contains(where: { $0.identifier == candidate.id && Self.matches($0, dueAt: candidate.dueAt) && $0.content.title == content.title && $0.content.body == content.body && $0.content.categoryIdentifier == content.categoryIdentifier }) {
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
            let quiet = Self.isQuiet(candidate.dueAt, timeZone: timeZone, quietAfterIsha: session.bool("notif.quietAfterIsha"), quietFrom: session.string("notif.quietFrom"), until: quietEnd, prayerDays: prayerDays)
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

    private static func matches(_ request: UNNotificationRequest, dueAt: Date) -> Bool {
        guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
              let date = trigger.nextTriggerDate() else { return false }
        return abs(date.timeIntervalSince(dueAt)) < 1
    }

    /// The prayer countdown Live Activity is retired with the prayer room: any one still running (an old install) ends now.
    private func endRetiredPrayerCountdowns(now: Date) async throws {
        for activity in Activity<PrayerCountdownAttributes>.activities {
            await activity.end(nil, dismissalPolicy: .immediate)
            // A submitted start keeps consuming its slot once its scheduled time has passed; only a future one is refunded.
            if activity.attributes.scheduledStartAt > now, let id = activity.attributes.budgetRequestID {
                try session?.notificationBudget.cancel(id: id, now: now)
                try updateLedger(requestID: id, state: "cancelled")
            }
        }
    }

    /// Old installs may still hold pending «صلّيتها؟» requests: cancel them all and say so in the ledger.
    private func cancelRetiredPrayerRequests(_ current: [UNNotificationRequest]) throws {
        guard !current.isEmpty else { return }
        let ids = current.map(\.identifier)
        center.removePendingNotificationRequests(withIdentifiers: ids)
        for id in ids { try updateLedger(requestID: id, state: "cancelled") }
    }

    /// Context surfaces have no alert configuration, but RL5 still budgets every start and gates its window.
    private func reconcileContextActivities(prayerDays: [PrayerDay], prayerSlots: [PrayerNotificationSlot], sanctityWindows: [SanctityWindow],
                                            repository: PrayerRepository, now: Date, session: AppSession) async throws {
        guard UIApplication.shared.applicationState == .active else { return }

        let eligibleLetterAt: Date?
        if session.protectedDataAuthorized {
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
        let policy = NotificationPolicy(dailyBudget: Int(session.number("notif.dailyBudget")), quietFromMinutes: quietFrom, quietUntil: quietEnd,
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
                                                        prayerSlots: prayerSlots, timeZone: zone, quietFromMinutes: quietFrom, sanctityWindows: sanctityWindows)
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
                                                        timeZone: zone, quietFromMinutes: quietFrom, sanctityWindows: sanctityWindows)
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
                                                 quietFromMinutes: Int?, sanctityWindows: [SanctityWindow] = []) -> Date {
        let maximumEnd = startedAt.addingTimeInterval(MadarContextActivityPlanner.maximumActiveDuration)
        var end = min(plan.staleAt ?? maximumEnd, maximumEnd)
        // T01: a stale activity still draws until the app reopens, so it must go stale
        // at the start of the nearest sanctity window of any prayer, not only Isha.
        if let nextWindow = sanctityWindows.map(\.start).filter({ $0 > startedAt }).min() {
            end = min(end, nextWindow)
        }
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
        for row in rows where RoomNotificationContent.tracksReminderBudget(row) {
            // Natural request identity avoids counting duplicate ledger rows.
            counts[row.dayKey, default: []].insert(row.requestID)
        }
        return counts.mapValues(\.count)
    }

    /// «ينتهي الصمت» (`notif.quietUntil`, owner 29 Oct 2026): Fajr by default, sunrise, or midnight as before.
    private var quietEnd: QuietEnd { QuietEnd(rawValue: session?.string("notif.quietUntil") ?? "") ?? .fajr }

    private static func isQuiet(_ date: Date, timeZone: TimeZone, quietAfterIsha: Bool, quietFrom: String, until: QuietEnd, prayerDays: [PrayerDay]) -> Bool {
        guard quietAfterIsha else { return false }
        let parts = quietFrom.split(separator: ":", omittingEmptySubsequences: false)
        guard parts.count == 2, let hour = Int(parts[0]), let minute = Int(parts[1]),
              (0...23).contains(hour), (0...59).contains(minute) else { return true }
        return NotificationArbiter.quietWindowContains(date, timeZone: timeZone, fromMinutes: hour * 60 + minute, until: until, prayerDays: prayerDays)
    }

    /// The ledger only needs today's budget and recent history; rows older than 45 days that are no longer pending are tombstoned (once a day).
    private func pruneLedgerOncePerDay(now: Date) {
        guard let session else { return }
        let key = "Madar.ledgerPrunedOn"
        let today = Int(now.timeIntervalSince1970 / 86_400)
        guard UserDefaults.standard.integer(forKey: key) != today else { return }
        do {
            let container = try session.managedStore?.containerForTransaction() ?? session.container
            let context = ModelContext(container)
            let cutoff = now.addingTimeInterval(-45 * 86_400)
            let old = try context.fetch(FetchDescriptor<NotificationLedger>(predicate: #Predicate { $0.scheduledFor < cutoff }))
            for row in old where row.deletedAt == nil && row.state != "submitted" { row.deletedAt = now; row.updatedAt = now }
            if context.hasChanges { try context.save() }
            UserDefaults.standard.set(today, forKey: key)
        } catch { }
    }

    private func updateLedger(requestID: String, dayKey: String? = nil, dueAt: Date? = nil,
                              state: String, reason: String? = nil, kind: String? = nil) throws {
        guard let session else { return }
        let container: ModelContainer
        if let store = session.managedStore { container = try store.containerForTransaction() }
        else { container = session.container }
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<NotificationLedger>(predicate: #Predicate { $0.requestID == requestID })).filter { $0.deletedAt == nil }
        let classification = RoomNotificationContent.ledgerClassification(for: requestID, kind: kind)
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
            row.room = classification.room
            row.kind = kind ?? (requestID.hasSuffix(".snooze") ? "snooze" : "ask")
            row.requestClass = classification.requestClass
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
                row.dayKey = dayKey ?? ""; row.requestID = requestID; row.room = classification.room
                row.kind = kind ?? "ask"; row.requestClass = classification.requestClass; row.scheduledFor = dueAt
                row.state = state; row.reason = reason; row.writerID = "madar.app.notifications"
                context.insert(row)
            }
        }
        try context.save()
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
