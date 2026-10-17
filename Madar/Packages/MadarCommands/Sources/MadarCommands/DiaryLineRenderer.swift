import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarPrayer
import MadarMoney

public struct DiaryAutoLine: Identifiable, Codable, Equatable, Sendable {
    public let id: String
    public let at: Date
    public let text: String
    public let kind: String
    /// Imported Day One lines show their time in the entry's own zone (N01/RD8); nil = the day's place.
    public var tzID: String? = nil
    /// Text is Markdown (Day One import) and is rendered formatted.
    public var markdown: Bool? = nil
    public init(id: String, at: Date, text: String, kind: String, tzID: String? = nil, markdown: Bool? = nil) { self.id = id; self.at = at; self.text = text; self.kind = kind; self.tzID = tzID; self.markdown = markdown }
}
@MainActor public enum DiaryLineRenderer {
    public static func today(context: ModelContext, now: Date) throws -> GregorianDay {
        let repo = try PrayerRepository(context: context), place = repo.place(at: now), civil = GregorianDay.containing(now, in: place.timeZone)
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: repo.options) }
        let settings = try SettingsStore(context: context)
        return try MadarDay.resolve(instant: now, place: place, boundary: DayBoundary(rawValue: settings.value(for: "core.dayStart").string ?? "") ?? .fajr, prayerDays: days).date
    }
    public static func live(day: GregorianDay, context: ModelContext) throws -> [DiaryAutoLine] {
        let hidden = try context.fetch(FetchDescriptor<HiddenAutoLine>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let pinned = try context.fetch(FetchDescriptor<Entry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.source == "autoPinned" }
        func visible(_ kind: String, _ id: UUID) -> Bool {
            !hidden.contains { $0.eventKind == kind && $0.eventID == id } && !pinned.contains { $0.pinnedEventKind == kind && $0.pinnedEventID == id }
        }
        var lines: [DiaryAutoLine] = []
        let names = ["fajr": "الفجر", "dhuhr": "الظهر", "asr": "العصر", "maghrib": "المغرب", "isha": "العشاء"]
        for row in try context.fetch(FetchDescriptor<PrayerLog>()) where row.dayKey == day.description && row.deletedAt == nil && row.mergedInto == nil && visible("salah", row.id) {
            guard ["jamaah", "alone", "qada"].contains(row.status) else { continue }
            lines.append(.init(id: "salah." + row.id.uuidString, at: row.eventAt,
                text: "صلّيت " + (names[row.prayer] ?? "الصلاة") + (row.status == "jamaah" ? " جماعة" : row.status == "qada" ? " قضاءً" : " وحدي"), kind: "salah"))
        }
        for row in try context.fetch(FetchDescriptor<HifzSession>()) where row.dayKey == day.description && row.deletedAt == nil && row.mergedInto == nil && visible("quran", row.id) {
            guard row.kind != "drill" else { continue }
            let text = row.kind == "hifz" ? "حفظت من القرآن" : row.kind == "qiyam" ? "راجعت من محفوظي في القيام" : "راجعت من محفوظي"
            lines.append(.init(id: "quran." + row.id.uuidString, at: row.endedAt, text: text, kind: "quran"))
        }
        let money = MoneyRepository(context: context)
        let settings = try SettingsStore(context: context)
        let digits = MadarNumberFormatter(style: try settings.value(for: "core.numerals") == .string("western") ? .western : .hindi)
        for row in try money.confirmedTransactions() where row.dayKey == day.description && row.showInDiary && visible("mal", row.id) {
            let charge = try money.effect(of: row, includingExcluded: true).budgetChargeMinor
            guard charge != 0, let exponent = CurrencyExponents.specified.exponent(row.homeCurrency) else { continue }
            let amount = digits.amount(minorUnits: Int64(abs(charge)), fractionDigits: exponent, signed: false)
            let currency = row.homeCurrency == "SAR" ? "ر.س" : row.homeCurrency
            lines.append(.init(id: "mal." + row.id.uuidString, at: row.eventAt, text: (charge > 0 ? "صرفت " : "استعدت ") + amount + " " + currency, kind: "mal"))
        }
        return lines.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at }
    }
    /// RD1: keep the first closed-day snapshot. Initial historical pages get a baseline on first observation.
    public static func freeze(_ day: GregorianDay, context: ModelContext, now: Date, writer: String) throws {
        guard day < (try today(context: context, now: now)) else { return }
        let key = "sys.diaryAutoLines." + day.description
        guard !(try context.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == key && $0.deletedAt == nil && $0.mergedInto == nil }) else { return }
        let row = DeviceSetting(); row.key = key; row.valueJSON = try JSONEncoder().encode(live(day: day, context: context))
        row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
    }
    static func freezeBeforeSourceChange(context: ModelContext, now: Date, writer: String) throws {
        let keys = Set(try context.fetch(FetchDescriptor<DayPage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map(\.dayKey))
        guard !keys.isEmpty else { return }
        let frozen = Set(try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map(\.key))
        let current = try today(context: context, now: now)
        for key in keys where !frozen.contains("sys.diaryAutoLines." + key) {
            if let day = try? GregorianDay(key), day < current { try freeze(day, context: context, now: now, writer: writer) }
        }
    }
}
