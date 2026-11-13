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

enum PrayerIntentHeart: String, AppEnum {
    case distracted, present, khashi

    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "حال القلب")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .distracted: "شارد", .present: "حاضر", .khashi: "خاشع"
    ]
}

/// §9 LogPrayerIntent(prayer, status, heart?): «صلّيت العصر جماعة». The prayer day is the current
/// one (Fajr to the next Fajr) from the app's prayer snapshot; `dayKey` stays only for older Shortcuts.
struct LogPrayerIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل صلاة"
    static let description = IntentDescription("يسجّل صلاة اليوم في جماعة أو منفردًا، دون فتح مدار.")
    static let openAppWhenRun = false

    @Parameter(title: "الصلاة") var prayer: PrayerIntentPrayer
    @Parameter(title: "الحالة") var status: PrayerIntentStatus
    @Parameter(title: "حال القلب") var heart: PrayerIntentHeart?
    @Parameter(title: "قصرًا") var shortened: Bool?
    @Parameter(title: "تصنيف ظهر الجمعة") var fridayKind: PrayerIntentFridayKind?
    @Parameter(title: "يوم الصلاة (السنة-الشهر-اليوم)") var dayKey: String?

    static var parameterSummary: some ParameterSummary {
        Summary("سجّل \(\.$prayer) \(\.$status)") {
            \.$heart
            \.$shortened
            \.$fridayKind
            \.$dayKey
        }
    }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let now = Date()
        guard let group = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: "group.com.alqzan.madar2") else {
            throw LogPrayerIntentError.openMadar
        }
        let snapshotStore = SnapshotStore(directory: group.appending(path: "Snapshots", directoryHint: .isDirectory))
        guard let snapshot = snapshotStore.read("prayerNext", as: PrayerNextSnapshot.self, now: now),
              let timeZone = TimeZone(identifier: snapshot.tzID) else {
            throw LogPrayerIntentError.refreshMadar
        }
        let day: String
        if let dayKey, !dayKey.isEmpty {
            // T07: a prayer whose adhan has not come yet cannot be logged, whichever day is named.
            var civil = Calendar(identifier: .gregorian); civil.timeZone = timeZone
            let parts = civil.dateComponents([.year, .month, .day], from: now)
            let today = String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
            if dayKey > today { throw LogPrayerIntentError.prayerNotOccurred }
            if let item = snapshot.payload.items.first(where: { $0.prayer == prayer.rawValue }), item.at > now,
               civil.isDate(item.at, inSameDayAs: now), dayKey == today { throw LogPrayerIntentError.prayerNotOccurred }
            day = dayKey
        }
        else {
            do {
                day = try PrayerInboxCommandWriter.currentPrayerDayKey(
                    at: now, prayer: prayer.rawValue,
                    prayerTimes: snapshot.payload.items.map { .init(prayer: $0.prayer, at: $0.at) }, timeZone: timeZone)
            } catch PrayerInboxCommandError.prayerNotOccurred {
                throw LogPrayerIntentError.prayerNotOccurred
            } catch { throw LogPrayerIntentError.refreshMadar }
        }
        let inbox = PendingInbox(directory: group.appending(path: "PendingInbox", directoryHint: .isDirectory))
        do {
            _ = try PrayerInboxCommandWriter.logPrayer(
                inbox: inbox,
                dayKey: day,
                prayer: prayer.rawValue,
                status: status.rawValue,
                shortened: shortened,
                fridayKind: fridayKind?.rawValue,
                heart: heart?.rawValue,
                timeZone: timeZone,
                source: .siri,
                issuedAt: now
            )
        } catch PrayerInboxCommandError.fridayKindRequired {
            throw $fridayKind.needsValueError("الجمعة أم الظهر؟")
        } catch PrayerInboxCommandError.jumuahRequiresCongregation {
            throw LogPrayerIntentError.jumuahRequiresCongregation
        } catch PrayerInboxCommandError.invalidDayKey {
            throw LogPrayerIntentError.invalidDayKey
        } catch is PrayerInboxCommandError {
            throw LogPrayerIntentError.invalidSelection
        } catch {
            throw LogPrayerIntentError.refreshMadar
        }
        await MainActor.run { NotificationCenter.default.post(name: Notification.Name("madar.inboxChanged"), object: nil) }
        WidgetCenter.shared.reloadAllTimelines()
        ControlCenter.shared.reloadAllControls()
        // Written to the inbox, not yet to the record: the dialog says so, as the Control does.
        return .result(dialog: "حُفظ طلب تسجيل \(prayer.arabicName)، ويُسجَّل في مدار حين تفتحه.")
    }
}

private enum LogPrayerIntentError: LocalizedError {
    case openMadar, refreshMadar, prayerNotOccurred, jumuahRequiresCongregation, invalidDayKey, invalidSelection

    var errorDescription: String? {
        switch self {
        case .openMadar: "افتح مدار أولًا ثم أعد المحاولة."
        case .refreshMadar: "حدّث مدار ثم أعد المحاولة."
        case .prayerNotOccurred: "لم يدخل وقت هذه الصلاة بعد."
        case .jumuahRequiresCongregation: "الجمعة تُسجّل جماعة؛ اختر الظهر إذا صليت منفردًا."
        case .invalidDayKey: "أدخل يوم الصلاة بصيغة السنة-الشهر-اليوم، مثل 2026-10-28."
        case .invalidSelection: "راجع الصلاة والحالة والقصر وتصنيف الجمعة."
        }
    }
}

