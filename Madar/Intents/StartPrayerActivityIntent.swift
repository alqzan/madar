import AppIntents
@preconcurrency import ActivityKit
import Foundation
import MadarInbox

/// The same immediate-start transaction is used by Shortcuts and the Control; neither opens the app store.
@MainActor enum PrayerActivityStarter {
    static func start(budget: NotificationBudgetStore, now: Date,
                      request: (ReservedPrayerActivity) async throws -> Void) async throws {
        let reserved = try budget.reservePrayerActivity(id: "activity." + UUID().uuidString, now: now)
        do { try await request(reserved) }
        catch {
            try budget.cancel(id: reserved.reservation.id, now: now, requestFailed: true)
            throw error
        }
    }

    static func requestSystem(_ reserved: ReservedPrayerActivity, budget: NotificationBudgetStore, now: Date) async throws {
        for old in Activity<PrayerCountdownAttributes>.activities {
            await old.end(nil, dismissalPolicy: .immediate)
            if let id = old.attributes.budgetRequestID { try budget.cancel(id: id, now: now) }
        }
        let names = ["fajr": "الفجر", "dhuhr": "الظهر", "asr": "العصر", "maghrib": "المغرب", "isha": "العشاء"]
        let attributes = PrayerCountdownAttributes(activityKey: "prayer.next", scheduledStartAt: reserved.reservation.scheduledAt,
                                                   budgetRequestID: reserved.reservation.id, numerals: reserved.numerals)
        let state = PrayerCountdownAttributes.ContentState(prayerName: names[reserved.prayer.rawValue] ?? "الصلاة القادمة", prayerAt: reserved.prayerAt)
        _ = try Activity.request(attributes: attributes, content: ActivityContent(state: state, staleDate: reserved.prayerAt, relevanceScore: 1),
            pushType: nil, style: .standard)
    }
}

struct StartPrayerActivityIntent: LiveActivityIntent {
    static let title: LocalizedStringResource = "ابدأ عدّاد الصلاة"
    static let description = IntentDescription("يضع عدّاد الصلاة القادمة على شاشة القفل، إلا وقت الصلاة نفسها وساعات الهدوء.")
    static let openAppWhenRun = false

    @MainActor func perform() async throws -> some IntentResult {
        guard ActivityAuthorizationInfo().areActivitiesEnabled,
              let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else {
            throw PrayerActivityIntentError.unavailable
        }
        let budget = NotificationBudgetStore(directory: group.appending(path: "PendingInbox/NotificationBudget", directoryHint: .isDirectory))
        let now = Date()
        do {
            try await PrayerActivityStarter.start(budget: budget, now: now) { reserved in
                try await PrayerActivityStarter.requestSystem(reserved, budget: budget, now: now)
            }
        } catch NotificationBudgetError.duplicate {
            return .result(dialog: "سبق طلب عدّاد هذه الصلاة.")
        } catch NotificationBudgetError.disabled { throw PrayerActivityIntentError.disabled }
        catch NotificationBudgetError.full { throw PrayerActivityIntentError.budget }
        catch NotificationBudgetError.unavailable { throw PrayerActivityIntentError.refresh }
        return .result(dialog: "بدأت متابعة الصلاة القادمة.")
    }
}

private enum PrayerActivityIntentError: LocalizedError {
    case unavailable, disabled, budget, refresh
    var errorDescription: String? {
        switch self {
        case .unavailable: "اسمح بالأنشطة الحيّة لمدار في إعدادات الجهاز."
        case .disabled: "فعّل عدّاد الصلاة والتذكيرات من إعدادات مدار. لا يبدأ العدّاد وقت الصلاة ولا في ساعات الهدوء أو الليل، فجرّب بعد انتهائها."
        case .budget: "بلغت تنبيهات اليوم حدّها أو هذه ساعات الهدوء؛ جرّب بعد قليل."
        case .refresh: "افتح مدار لتحديث المواقيت والإعدادات ثم أعد المحاولة."
        }
    }
}
