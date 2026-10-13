import AppIntents
import Foundation
import MadarCore
import MadarInbox
import MadarSnapshots
import WidgetKit

enum PrayerIntentPrayer: String, AppEnum {
    case fajr, dhuhr, asr, maghrib, isha

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "الصلاة")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .fajr: "الفجر", .dhuhr: "الظهر", .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء"
    ]
}

enum PrayerIntentStatus: String, AppEnum {
    case jamaah, alone

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "الحالة")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .jamaah: "في جماعة", .alone: "وحدي"
    ]
}

enum PrayerIntentFridayKind: String, AppEnum {
    case jumuah, dhuhr

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "تصنيف ظهر الجمعة")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .jumuah: "الجمعة", .dhuhr: "الظهر"
    ]
}

struct LogPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل صلاة"
    static let description = IntentDescription("يسجّل صلاة الجماعة أو الصلاة منفردًا عبر صندوق أوامر مدار.")
    static let openAppWhenRun = false

    @Parameter(title: "يوم الصلاة بصيغة YYYY-MM-DD") var dayKey: String
    @Parameter(title: "الصلاة") var prayer: PrayerIntentPrayer
    @Parameter(title: "الحالة") var status: PrayerIntentStatus
    @Parameter(title: "قصراً") var shortened: Bool?
    @Parameter(title: "تصنيف ظهر الجمعة") var fridayKind: PrayerIntentFridayKind?

    func perform() async throws -> some IntentResult {
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else {
            throw LogPrayerIntentError.openMadar
        }
        let snapshotStore = SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
        guard let snapshot = snapshotStore.read("prayerNext", as: PrayerNextSnapshot.self),
              let timeZone = TimeZone(identifier: snapshot.tzID) else {
            throw LogPrayerIntentError.refreshMadar
        }
        let inbox = PendingInbox(directory: group.appending(path: "PendingInbox", directoryHint: .isDirectory))
        do {
            _ = try PrayerInboxCommandWriter.logPrayer(
                inbox: inbox,
                dayKey: dayKey,
                prayer: prayer.rawValue,
                status: status.rawValue,
                shortened: shortened,
                fridayKind: fridayKind?.rawValue,
                timeZone: timeZone,
                source: .shortcut
            )
        } catch PrayerInboxCommandError.fridayKindRequired {
            throw LogPrayerIntentError.fridayKindRequired
        } catch PrayerInboxCommandError.jumuahRequiresCongregation {
            throw LogPrayerIntentError.jumuahRequiresCongregation
        } catch PrayerInboxCommandError.invalidDayKey {
            throw LogPrayerIntentError.invalidDayKey
        } catch is PrayerInboxCommandError {
            throw LogPrayerIntentError.invalidSelection
        } catch {
            throw LogPrayerIntentError.refreshMadar
        }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result(dialog: "أُضيف طلب تسجيل الصلاة إلى الوارد؛ يطبّقه مدار عند فتح التطبيق.")
    }
}

private enum LogPrayerIntentError: LocalizedError {
    case openMadar, refreshMadar, fridayKindRequired, jumuahRequiresCongregation, invalidDayKey, invalidSelection

    var errorDescription: String? {
        switch self {
        case .openMadar: "افتح مدار أولًا ثم أعد المحاولة."
        case .refreshMadar: "حدّث مدار ثم أعد المحاولة."
        case .fridayKindRequired: "اختر الجمعة أو الظهر تصنيفًا للصلاة."
        case .jumuahRequiresCongregation: "الجمعة تُسجّل جماعة؛ اختر الظهر إذا صليت منفردًا."
        case .invalidDayKey: "أدخل يوم الصلاة بصيغة YYYY-MM-DD."
        case .invalidSelection: "راجع الصلاة والحالة والقصر وتصنيف الجمعة."
        }
    }
}

