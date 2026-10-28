import AppIntents
import Foundation
import MadarCore
import MadarInbox
import MadarSnapshots
import WidgetKit

/// Per-control choices. The person selects both the prayer and its recorded
/// state when adding this Control; it never guesses a state on their behalf.
struct PrayerLogControlConfiguration: ControlConfigurationIntent {
    static let title: LocalizedStringResource = "إعداد تسجيل الصلاة"
    static let description = IntentDescription("اختر الصلاة والحالة التي يسجلها هذا التحكم عند الضغط عليه.")

    @Parameter(title: "الصلاة") var prayer: PrayerIntentPrayer?
    @Parameter(title: "الحالة") var status: PrayerIntentStatus?
    @Parameter(title: "تصنيف ظهر الجمعة") var fridayKind: PrayerIntentFridayKind?

    static var parameterSummary: some ParameterSummary {
        Summary("سجّل \(\.$prayer) \(\.$status) \(\.$fridayKind)")
    }
}

/// Control actions use the same app-group inbox as Shortcuts and never open
/// SwiftData from the widget extension.
struct LogConfiguredPrayerControlIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل الصلاة من التحكم"
    static let description = IntentDescription("يسجّل الصلاة والحالة اللتين اختيرتا لهذا التحكم.")
    static let openAppWhenRun = false

    @Parameter(title: "الصلاة") var prayer: PrayerIntentPrayer?
    @Parameter(title: "الحالة") var status: PrayerIntentStatus?
    @Parameter(title: "تصنيف ظهر الجمعة") var fridayKind: PrayerIntentFridayKind?

    init() {
        prayer = nil
        status = nil
        fridayKind = nil
    }

    init(prayer: PrayerIntentPrayer?, status: PrayerIntentStatus?, fridayKind: PrayerIntentFridayKind?) {
        self.prayer = prayer
        self.status = status
        self.fridayKind = fridayKind
    }

    func perform() async throws -> some IntentResult {
        guard let prayer, let status else { throw PrayerControlIntentError.configureFirst }
        let now = Date()
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else {
            throw PrayerControlIntentError.openMadar
        }
        let snapshotStore = SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
        guard let snapshot = snapshotStore.read("prayerNext", as: PrayerNextSnapshot.self, now: now),
              let timeZone = TimeZone(identifier: snapshot.tzID) else {
            throw PrayerControlIntentError.refreshMadar
        }

        let prayerTimes = snapshot.payload.items.map {
            PrayerInboxCommandWriter.PrayerTime(prayer: $0.prayer, at: $0.at)
        }
        let dayKey: String
        do {
            dayKey = try PrayerInboxCommandWriter.currentPrayerDayKey(
                at: now,
                prayer: prayer.rawValue,
                prayerTimes: prayerTimes,
                timeZone: timeZone
            )
        } catch PrayerInboxCommandError.prayerNotOccurred {
            throw PrayerControlIntentError.prayerNotOccurred
        } catch {
            throw PrayerControlIntentError.refreshMadar
        }

        let day = try GregorianDay(dayKey)
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let fridayKind = prayer == .dhuhr && calendar.component(.weekday, from: day.date(in: timeZone)) == 6
            ? self.fridayKind?.rawValue
            : nil
        let inbox = PendingInbox(directory: group.appending(path: "PendingInbox", directoryHint: .isDirectory))
        do {
            _ = try PrayerInboxCommandWriter.logPrayer(
                inbox: inbox,
                dayKey: dayKey,
                prayer: prayer.rawValue,
                status: status.rawValue,
                fridayKind: fridayKind,
                timeZone: timeZone,
                source: .control,
                issuedAt: now
            )
        } catch PrayerInboxCommandError.fridayKindRequired {
            throw PrayerControlIntentError.fridayKindRequired
        } catch PrayerInboxCommandError.jumuahRequiresCongregation {
            throw PrayerControlIntentError.jumuahRequiresCongregation
        } catch {
            throw PrayerControlIntentError.invalidSelection
        }

        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        return .result(dialog: "حُفظ طلب تسجيل \(prayer.arabicName)، ويُسجَّل في مدار حين تفتحه.")
    }
}

extension PrayerIntentPrayer {
    var arabicName: String {
        switch self {
        case .fajr: "الفجر"
        case .dhuhr: "الظهر"
        case .asr: "العصر"
        case .maghrib: "المغرب"
        case .isha: "العشاء"
        }
    }
}

extension PrayerIntentStatus {
    var arabicName: String {
        switch self {
        case .jamaah: "جماعة"
        case .alone: "وحدي"
        }
    }
}

extension PrayerIntentFridayKind {
    var arabicName: String {
        switch self {
        case .jumuah: "الجمعة"
        case .dhuhr: "الظهر"
        }
    }
}

private enum PrayerControlIntentError: LocalizedError {
    case configureFirst, openMadar, refreshMadar, prayerNotOccurred, fridayKindRequired, jumuahRequiresCongregation, invalidSelection

    var errorDescription: String? {
        switch self {
        case .configureFirst: "أكمل إعداد التحكم واختر الصلاة والحالة."
        case .openMadar: "تعذّر الوصول إلى مدار. افتح التطبيق ثم أعد المحاولة."
        case .refreshMadar: "حدّث مواقيت الصلاة في مدار ثم أعد المحاولة."
        case .prayerNotOccurred: "لم يدخل وقت هذه الصلاة بعد."
        case .fridayKindRequired: "اختر الجمعة أو الظهر في إعدادات هذا التحكم."
        case .jumuahRequiresCongregation: "الجمعة تُسجّل جماعة؛ اختر الظهر إذا صليت منفردًا."
        case .invalidSelection: "راجع اختيارات الصلاة والحالة لهذا التحكم."
        }
    }
}
