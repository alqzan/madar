import Foundation
import MadarData

/// B2-18 (owner, 10 Nov 2026): the settings a room edits on its own page, found by the central search too.
/// Only keys whose editor was checked in the room's own screens are listed (Money's settings page, the diary's customize
/// page, the Quran plan, the prayer customize page); a search hit opens that place, never an empty result.
enum RoomSettingsIndex {
    enum Place: String, CaseIterable {
        case money, diary, quran, prayer
        var roomName: String {
            switch self { case .money: "المال"; case .diary: "المذكرات"; case .quran: "القرآن"; case .prayer: "الصلاة" }
        }
    }
    struct Hit: Identifiable, Equatable {
        let key: String
        let title: String
        let place: Place
        var id: String { key }
    }
    static let keys: [Place: [String]] = [
        .money: ["core.hideMoneyOutside", "mal.dailyAllowance", "mal.salaryRemainder", "mal.autoOffset", "mal.salaryDay", "mal.cycleCalendar", "mal.bigExpenseDays",
                 "mal.cashWithdrawalAsSpend", "mal.merchantLearnAfter", "mal.travelPausesDaily", "mal.hawlStyle", "mal.figureStyle", "mal.alert80", "mal.cardDue",
                 "mal.zakatReminder", "mal.sinceLastVisit", "mal.offsetCapDailies", "mal.bigExpenseRule", "mal.bigExpenseSalaryBp", "mal.bigExpenseMinor",
                 "mal.salarySchedule", "mal.reconcileEveryDays"],
        .diary: ["notes.homeShape", "notes.memorySize", "notes.match", "notes.noMemory", "notes.yearsBack", "notes.showPhoto", "notes.showPlace", "notes.showAutoSections",
                 "notes.sinceMetrics", "notes.includeDayOne", "notes.dictationFirst", "notes.serverDictationConsent", "notes.secondInk", "notes.ramadanStyle",
                 "notes.fridayStyle", "notes.autoLines", "notes.widgetContent"],
        .quran: ["quran.hifzLevel", "quran.reviewLevel", "quran.restDay", "quran.reviewSchedule", "quran.wirdReminder"],
        .prayer: ["core.travelMode"],
    ]
    static var allKeys: Set<String> { Set(keys.values.flatMap { $0 }) }

    /// Hits for a non-empty query: the title, the room's name or the key contains it. Keys already on the central page are never repeated.
    static func hits(in definitions: [SettingDefinition], query: String, supported: Set<String>) -> [Hit] {
        let needle = normalized(query)
        guard !needle.isEmpty else { return [] }
        let byKey = Dictionary(definitions.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })
        return Place.allCases.flatMap { place in
            (keys[place] ?? []).compactMap { key -> Hit? in
                guard !supported.contains(key), let definition = byKey[key] else { return nil }
                guard normalized(definition.title + " " + place.roomName + " " + key).contains(needle) else { return nil }
                return Hit(key: key, title: definition.title, place: place)
            }
        }
    }
}
