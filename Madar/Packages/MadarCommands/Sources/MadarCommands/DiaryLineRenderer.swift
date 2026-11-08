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
    /// A stored event zone keeps the event's own clock; nil asks the room to infer its place from the event date.
    public var tzID: String? = nil
    /// Text is Markdown (Day One import) and is rendered formatted.
    public var markdown: Bool? = nil
    public init(id: String, at: Date, text: String, kind: String, tzID: String? = nil, markdown: Bool? = nil) { self.id = id; self.at = at; self.text = text; self.kind = kind; self.tzID = tzID; self.markdown = markdown }
}
public struct DiaryAutoLineVisibility: Sendable {
    fileprivate let hiddenKeys: Set<String>
    fileprivate let pinnedKeys: Set<String>
}
@MainActor public enum DiaryLineRenderer {
    nonisolated public static func today(context: ModelContext, now: Date) throws -> GregorianDay {
        let repo = try PrayerRepository(context: context), place = repo.place(at: now), civil = GregorianDay.containing(now, in: place.timeZone)
        let options = repo.calculationOptions(at: now)
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: options) }
        let settings = try SettingsStore(context: context)
        return try MadarDay.resolve(instant: now, place: place, boundary: DayBoundary(rawValue: settings.value(for: "core.dayStart").string ?? "") ?? .fajr, prayerDays: days).date
    }
    public static func live(day: GregorianDay, context: ModelContext) throws -> [DiaryAutoLine] {
        try live(days: [day.description], context: context)[day.description] ?? []
    }
    /// The auto lines of many days from one read of each table (owner trial, 22 Oct 2026: 2,263 imported days froze the
    /// app when every day re-read every table). Each day's lines are exactly those `live(day:)` gives.
    public static func live(days: Set<String>, context: ModelContext) throws -> [String: [DiaryAutoLine]] {
        guard !days.isEmpty else { return [:] }
        let visibility = try visibility(context: context)
        var lines = try liveWithoutMoney(days: days, visibility: visibility, context: context)
        let moneyLines = try liveMoneyLines(days: days, visibility: visibility, context: context)
        for (key, rows) in moneyLines { lines[key, default: []].append(contentsOf: rows) }
        return lines.mapValues { $0.sorted { $0.at == $1.at ? $0.id < $1.id : $0.at < $1.at } }
    }
    nonisolated public static func visibility(context: ModelContext) throws -> DiaryAutoLineVisibility {
        let hiddenKeys = Set(try context.fetch(FetchDescriptor<HiddenAutoLine>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map { "\($0.eventKind)|\($0.eventID?.uuidString ?? "")" })
        let pinnedKeys = Set(try context.fetch(FetchDescriptor<Entry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.source == "autoPinned" }.map { "\($0.pinnedEventKind ?? "")|\($0.pinnedEventID?.uuidString ?? "")" })
        return DiaryAutoLineVisibility(hiddenKeys: hiddenKeys, pinnedKeys: pinnedKeys)
    }
    /// Room reads safe to run away from the main actor. Money stays on its repository's required actor.
    nonisolated public static func liveWithoutMoney(days: Set<String>, visibility: DiaryAutoLineVisibility, context: ModelContext) throws -> [String: [DiaryAutoLine]] {
        guard !days.isEmpty else { return [:] }
        func visible(_ kind: String, _ id: UUID) -> Bool { let key = kind + "|" + id.uuidString; return !visibility.hiddenKeys.contains(key) && !visibility.pinnedKeys.contains(key) }
        var lines: [String: [DiaryAutoLine]] = [:]
        let names = ["fajr": "الفجر", "dhuhr": "الظهر", "asr": "العصر", "maghrib": "المغرب", "isha": "العشاء"]
        for row in try context.fetch(FetchDescriptor<PrayerLog>()) where days.contains(row.dayKey) && row.deletedAt == nil && row.mergedInto == nil && visible("salah", row.id) {
            guard ["jamaah", "alone", "qada"].contains(row.status) else { continue }
            lines[row.dayKey, default: []].append(.init(id: "salah." + row.id.uuidString, at: row.eventAt,
                text: "صلّيت " + (names[row.prayer] ?? "الصلاة") + (row.status == "jamaah" ? " جماعة" : row.status == "qada" ? " قضاءً" : " وحدي"), kind: "salah",
                tzID: row.tzID.isEmpty ? nil : row.tzID))
        }
        let settings = try SettingsStore(context: context)
        let digits = MadarNumberFormatter(style: try settings.value(for: "core.numerals") == .string("western") ? .western : .hindi)
        /// Accusative after the verb: «وجهًا واحدًا»، «وجهين»، «٣ أوجه»، «١١ وجهًا».
        func counted(_ n: Int, _ forms: [String]) -> String {
            let r = n % 100
            return n == 1 ? forms[0] : n == 2 ? forms[1] : (3...10).contains(r) ? digits.string(n) + " " + forms[2] : digits.string(n) + " " + forms[3]
        }
        let catalog = try? QuranResources.catalog()
        for row in try context.fetch(FetchDescriptor<HifzSession>()) where days.contains(row.dayKey) && row.deletedAt == nil && row.mergedInto == nil && visible("quran", row.id) {
            guard row.kind != "drill" else { continue }
            // OR-11: the line names what was read, as in N3 («راجعت ٣ أوجه من الأنعام»); without the catalog it keeps the plain wording.
            var text = row.kind == "hifz" ? "حفظت من القرآن" : row.kind == "qiyam" ? "راجعت من محفوظي في القيام" : "راجعت من محفوظي"
            if let catalog, let first = catalog.ayah(id: min(row.fromAyah, row.toAyah)), let last = catalog.ayah(id: max(row.fromAyah, row.toAyah)) {
                func plain(_ name: String) -> String { String(String.UnicodeScalarView(name.unicodeScalars.filter { $0.properties.generalCategory != .nonspacingMark })) }
                let surah = first.surahID == last.surahID ? plain(first.surahNameArabic) : plain(first.surahNameArabic) + " إلى " + plain(last.surahNameArabic)
                if row.kind == "hifz" {
                    text = "حفظت " + counted(abs(row.toAyah - row.fromAyah) + 1, ["آية واحدة", "آيتين", "آيات", "آية"]) + " من " + surah
                } else {
                    text = "راجعت " + counted(last.page - first.page + 1, ["وجهًا واحدًا", "وجهين", "أوجه", "وجهًا"]) + " من " + surah + (row.kind == "qiyam" ? " في القيام" : "")
                }
            }
            lines[row.dayKey, default: []].append(.init(id: "quran." + row.id.uuidString, at: row.endedAt, text: text, kind: "quran",
                                                        tzID: row.tzID.isEmpty ? nil : row.tzID))
        }
        let books=try context.fetch(FetchDescriptor<Book>()).sorted{$0.updatedAt>$1.updatedAt}
        var bookTitles:[UUID:String]=[:]
        for book in books where bookTitles[book.id] == nil {
            let title=book.title.trimmingCharacters(in:.whitespacesAndNewlines)
            if !title.isEmpty {bookTitles[book.id]=title}
        }
        let readingSessions=try context.fetch(FetchDescriptor<ReadingSession>())
        for row in readingSessions where days.contains(row.dayKey) && row.activeSeconds >= 60 && row.deletedAt == nil && row.mergedInto == nil && visible("mihbara",row.id) {
            let title=row.bookID.flatMap{bookTitles[$0]} ?? "كتابك"
            let text:String
            if row.pagesCounted > 0 {
                let count=row.pagesCounted,remainder=count%100
                let unit=count == 1 ? "صفحة واحدة" : count == 2 ? "صفحتين" : (3...10).contains(remainder) ? digits.string(count)+" صفحات" : digits.string(count)+" صفحة"
                text="قرأت "+unit+" من "+title
            } else {
                let minutes=max(1,row.activeSeconds / 60 + (row.activeSeconds % 60 == 0 ? 0 : 1)),remainder=minutes%100
                let unit=minutes == 1 ? "دقيقة واحدة" : minutes == 2 ? "دقيقتين" : (3...10).contains(remainder) ? digits.string(minutes)+" دقائق" : digits.string(minutes)+" دقيقة"
                text="قرأت "+unit+" من "+title
            }
            lines[row.dayKey, default: []].append(.init(id:"mihbara."+row.id.uuidString,at:row.end ?? row.updatedAt,text:text,kind:"mihbara",
                                                        tzID: row.tzID.isEmpty ? nil : row.tzID))
        }
        // OR-11: habits write their day too. A habit linked to another room (prayer, Quran) is already told by that room's line.
        let habitRows = Dictionary(try context.fetch(FetchDescriptor<Habit>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.linkedSource == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let events = try context.fetch(FetchDescriptor<HabitEvent>()).filter { days.contains($0.dayKey) && $0.deletedAt == nil && $0.mergedInto == nil }
        for (group, rows) in Dictionary(grouping: events.filter { $0.habitID.map { habitRows[$0] != nil } == true }, by: { $0.dayKey + "|" + $0.habitID!.uuidString }) {
            guard let habit = habitRows[rows[0].habitID!], let latest = rows.max(by: { $0.eventAt == $1.eventAt ? $0.id.uuidString < $1.id.uuidString : $0.eventAt < $1.eventAt }), visible("habits", latest.id) else { continue }
            let total = rows.reduce(0) { $0 + $1.delta }
            guard total > 0 else { continue }
            let name = habit.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? "عادتك" : habit.name.trimmingCharacters(in: .whitespacesAndNewlines)
            let unit = (latest.unit ?? "").trimmingCharacters(in: .whitespaces)
            let forms: [String: [String]] = ["minutes": ["دقيقة واحدة", "دقيقتين", "دقائق", "دقيقة"], "دقيقة": ["دقيقة واحدة", "دقيقتين", "دقائق", "دقيقة"],
                "steps": ["خطوة واحدة", "خطوتين", "خطوات", "خطوة"], "pages": ["صفحة واحدة", "صفحتين", "صفحات", "صفحة"], "chapters": ["فصلًا واحدًا", "فصلين", "فصول", "فصلًا"], "صفحة": ["صفحة واحدة", "صفحتين", "صفحات", "صفحة"],
                "كوب": ["كوبًا واحدًا", "كوبين", "أكواب", "كوبًا"], "مرة": ["مرة واحدة", "مرتين", "مرات", "مرة"]]
            let amount = rows.contains { ($0.unit ?? "").isEmpty } && total == 1 ? nil : unit.isEmpty ? (total > 1 ? counted(total, forms["مرة"]!) : nil) : forms[unit].map { counted(total, $0) } ?? digits.string(total) + " " + unit
            let text = MadarInlineText.joined([name, amount].compactMap { $0 })
            lines[String(group.split(separator: "|")[0]), default: []].append(.init(id: "habits." + latest.id.uuidString, at: latest.eventAt, text: text, kind: "habits",
                                                        tzID: latest.tzID.isEmpty ? nil : latest.tzID))
        }
        return lines
    }
    public static func liveMoneyLines(days: Set<String>, visibility: DiaryAutoLineVisibility, context: ModelContext) throws -> [String: [DiaryAutoLine]] {
        guard !days.isEmpty else { return [:] }
        func visible(_ id: UUID) -> Bool { let key = "mal|" + id.uuidString; return !visibility.hiddenKeys.contains(key) && !visibility.pinnedKeys.contains(key) }
        var lines: [String: [DiaryAutoLine]] = [:]
        let settings = try SettingsStore(context: context)
        let digits = MadarNumberFormatter(style: try settings.value(for: "core.numerals") == .string("western") ? .western : .hindi)
        let money = MoneyRepository(context: context)
        let effects = try money.effectContext()
        for row in try money.confirmedTransactions() where days.contains(row.dayKey) && row.showInDiary && visible(row.id) {
            let charge = try money.effect(of: row, includingExcluded: true, in: effects).budgetChargeMinor
            guard charge != 0, let exponent = CurrencyExponents.specified.exponent(row.homeCurrency) else { continue }
            // A whole amount reads «١٤٠ ر.س», not «١٤٠٫٠٠ ر.س»: the zero halalas say nothing on a diary page.
            let scale = (0..<exponent).reduce(1) { acc, _ in acc * 10 }
            let whole = abs(charge) % scale == 0
            let amount = digits.amount(minorUnits: Int64(whole ? abs(charge) / scale : abs(charge)), fractionDigits: whole ? 0 : exponent, signed: false)
            let currency = row.homeCurrency == "SAR" ? "ر.س" : row.homeCurrency
            lines[row.dayKey, default: []].append(.init(id: "mal." + row.id.uuidString, at: row.eventAt,
                                                        text: (charge > 0 ? "صرفت " : "استعدت ") + amount + " " + currency, kind: "mal",
                                                        tzID: row.tzID.isEmpty ? nil : row.tzID))
        }
        return lines
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
        let open = Set(keys.filter { key in !frozen.contains("sys.diaryAutoLines." + key) && ((try? GregorianDay(key)).map { $0 < current } ?? false) })
        guard !open.isEmpty else { return }
        // One read of each table for all the days, then the same snapshot `freeze` keeps for each.
        let all = try live(days: open, context: context)
        let encoder = JSONEncoder()
        for key in open.sorted() {
            let row = DeviceSetting(); row.key = "sys.diaryAutoLines." + key; row.valueJSON = try encoder.encode(all[key] ?? [])
            row.createdAt = now; row.updatedAt = now; row.writerID = writer; context.insert(row)
        }
    }
}
