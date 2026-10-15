import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarInbox
import MadarPrayer

extension AppSession {
    var notificationBudget: NotificationBudgetStore {
        .init(directory: pendingInbox.directory.appending(path: "NotificationBudget", directoryHint: .isDirectory))
    }

    /// Publish current settings and calculated sanctity windows before an external start is possible.
    /// Existing device-ledger requests seed the budget on upgrade, without moving owner records.
    func publishNotificationBudget(at now: Date) throws {
        let context = ModelContext(container), repository = try PrayerRepository(context: context)
        let first = repository.prayerDay(at: now), place = repository.place(at: now)
        let days = (0..<4).compactMap { PrayerTimesEngine.calculate(day: first.adding(days: $0), place: place, options: repository.options) }
        let rows = try context.fetch(FetchDescriptor<NotificationLedger>()).filter {
            $0.deletedAt == nil && ["room", "digest", "nudge"].contains($0.requestClass) && ["submitted", "observed"].contains($0.state)
                && $0.scheduledFor >= now.addingTimeInterval(-7 * 86400)
        }
        let seeds = rows.map { NotificationBudgetReservation(id: $0.requestID, dayKey: $0.dayKey, scheduledAt: $0.scheduledFor, activity: $0.kind == "activityStart") }
        let parts = string("notif.quietFrom").split(separator: ":").compactMap { Int($0) }
        let quiet = bool("notif.quietAfterIsha") ? (parts.count == 2 ? parts[0] * 60 + parts[1] : 0) : nil
        try notificationBudget.publish(.init(generatedAt: now, validUntil: now.addingTimeInterval(24 * 3600),
            activityEnabled: bool("salah.liveActivity"), remindersEnabled: bool("notif.thisDeviceReminders"),
            dailyBudget: Int(number("notif.dailyBudget")), quietFromMinutes: quiet,
            dayBoundary: DayBoundary(rawValue: string("core.dayStart")) ?? .fajr, prayerDays: days, numerals: string("core.numerals")), importing: seeds)
    }
}
