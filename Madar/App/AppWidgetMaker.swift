import Foundation
import SwiftUI
import MadarDesign
import SwiftData
import WidgetKit
import MadarCore
import MadarData
import MadarCommands
import MadarSnapshots

struct WidgetMakerDraft: Identifiable, Hashable {
    var id = UUID()
    var name = ""
    var familyID = "medium"
    var items: [String] = []
    var style = WidgetMakerStyle()
}

extension AppSession {
    func widgetMakerDrafts() throws -> [WidgetMakerDraft] {
        try ModelContext(container).fetch(FetchDescriptor<WidgetConfig>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]))
            .map { row in
                .init(id: row.id, name: row.name, familyID: row.familyID ?? "medium", items: row.items,
                      style: (try? JSONDecoder().decode(WidgetMakerStyle.self, from: row.styleJSON)) ?? .init())
            }
    }
    func saveWidget(_ draft: WidgetMakerDraft) async throws {
        let style = try JSONDecoder().decode(MadarCore.JSONValue.self, from: JSONEncoder().encode(draft.style))
        try await executeDiaryCommand("widget.save", payload: ["id": .string(draft.id.uuidString), "name": .string(draft.name),
                                                             "familyID": .string(draft.familyID), "items": .array(draft.items.map(MadarCore.JSONValue.string)), "style": style])
    }
    func publishWidgetCatalog(at now: Date) throws {
        let service = AppBahwService(session: self, evaluationDate: now), day = service.today, dates = dateLabels(day)
        let locked = MadarLockScope(rawValue: string("core.faceIDLock"))?.effective == .app
        let configs = try widgetMakerDrafts().map { draft in
            WidgetCatalogSnapshot.Config(id: draft.id, name: locked ? "ودجة مدار" : draft.name, familyID: draft.familyID,
                                         styleJSON: try JSONEncoder().encode(draft.style), rows: locked ? [] : widgetMakerRows(draft, at: now))
        }
        let location = service.prayerLocation(), nextDay = day.adding(days: 1)
        let end: Date?
        switch DayBoundary(rawValue: string("core.dayStart")) ?? .fajr {
        case .midnight: end = nextDay.date(in: location.place.timeZone)
        case .fajr: end = PrayerTimesEngine.calculate(day: nextDay, place: location.place, options: location.options)?.fajr
        case .maghrib: end = PrayerTimesEngine.calculate(day: nextDay, place: location.place, options: location.options)?.maghrib
        }
        let expiry = min(now.addingTimeInterval(3600), end ?? now.addingTimeInterval(900))
        try snapshotStore.write(SnapshotEnvelope(name: WidgetCatalogSnapshot.valuesName, generatedAt: now, validUntil: expiry, dayKey: day.description, tzID: service.prayerLocation().place.timeZoneID,
                                                 privacy: SnapshotPrivacy(moneyHidden: bool("core.hideMoneyOutside"), notesLocked: locked),
                                                 payload: WidgetCatalogSnapshot(datePrimary: dates.primary, dateSecondary: dates.secondary, configs: configs, locked: locked)))
        let metadata = configs.map { WidgetCatalogSnapshot.Config(id: $0.id, name: $0.name, familyID: $0.familyID, styleJSON: $0.styleJSON, rows: []) }
        try snapshotStore.write(SnapshotEnvelope(name: WidgetCatalogSnapshot.name, generatedAt: now, validUntil: now.addingTimeInterval(30 * 86400), dayKey: day.description, tzID: service.prayerLocation().place.timeZoneID,
                                                 privacy: SnapshotPrivacy(moneyHidden: true, notesLocked: locked),
                                                 payload: WidgetCatalogSnapshot(datePrimary: dates.primary, dateSecondary: dates.secondary, configs: metadata, locked: locked)))
        WidgetCenter.shared.reloadTimelines(ofKind: "MadarMaker")
    }
    func widgetMakerRows(_ draft: WidgetMakerDraft, at now: Date, outside: Bool = true) -> [WidgetCatalogSnapshot.Row] {
        let service = AppBahwService(session: self, evaluationDate: now), digits = service.digits, day = service.today
        let dates = dateLabels(day)
        let quran = try? AppQuranService(session: self, clock: { now }).widgetSnapshot().payload
        var roomValues = roomWidgetPayloads(locked: false, at: now)
        if !outside {
            roomValues[.diaryWrite]?.rows = diaryWidgetRows(today: day)
            roomValues[.money] = moneyWidgetPayload(hidden: bool("core.hideMoneyUntilTouch"), at: now)
        }
        let readings = (try? HabitRepository(context: ModelContext(container)).readings(at: now)) ?? []
        let book = mihbaraWidgetSnapshot(locked: false, at: now)
        let prayer = snapshotStore.read("prayerNext", as: PrayerNextSnapshot.self, now: now)?.payload
        var result: [WidgetCatalogSnapshot.Row] = []
        func from(_ row: RoomWidgetSnapshot.Row, id: String, glyph: String, money: Bool = false) -> WidgetCatalogSnapshot.Row {
            .init(id: id, title: row.title, value: row.value, detail: row.detail, secondDate: row.secondDate, glyph: glyph, route: row.route, share: money && ["•••", "—"].contains(row.value) ? nil : row.share, money: money)
        }
        for item in draft.items {
            switch item {
            case "prayerNext":
                if let next = prayer?.state(at: now)?.item {
                    result.append(.init(id: item, title: next.name, value: "", detail: "الصلاة القادمة", glyph: "MadarPrayer", route: "madar://salah", targetDate: next.at))
                }
            case "habitsToday":
                let due = readings.filter { !$0.paused && ($0.summary.current?.target ?? 0) > 0 && $0.summary.current?.dueDays.contains(day) == true }
                let share = due.isEmpty ? nil : Double(due.filter { $0.summary.current?.met == true }.count) / Double(due.count)
                if let value = roomValues[.habits], !value.rows.isEmpty {
                    result.append(.init(id: item, title: "عادات اليوم", value: value.heading, detail: value.rows.first?.title ?? "", glyph: "MadarHabits", route: "madar://bahw/habits", share: share))
                }
            case "moneyNow":
                if let row = roomValues[.money]?.rows.first { result.append(from(row, id: item, glyph: "MadarMoney", money: true)) }
            case "quranCoverage":
                if let quran { result.append(.init(id: item, title: "في صدرك", value: quran.coverage, detail: quran.nextTitle, glyph: "MadarQuran", route: "madar://quran", share: quran.fraction)) }
            case "quranReview":
                if let quran, quran.total > quran.done { result.append(.init(id: item, title: "من القرآن اليوم", value: quran.nextTitle, detail: quran.nextDetail, glyph: "MadarQuran", route: "madar://quran")) }
            case "year":
                if let value = roomValues[.year], let row = value.rows.first {
                    // Both year labels travel together even in the smallest preview.
                    result.append(.init(id: item, title: "سنتك", value: row.value, detail: value.rows.map(\.title).joined(separator: "، "), glyph: "MadarYear", route: row.route, share: row.share))
                }
            case "upcoming":
                if let row = roomValues[.upcoming]?.rows.first { result.append(from(row, id: item, glyph: "MadarUpcoming")) }
            case "book":
                if let current = book.currentBook {
                    let page = current.currentPage.map { "ص " + digits.string($0) } ?? "ابدأ القراءة"
                    let total = current.pages.map { " من " + digits.string($0) } ?? ""
                    result.append(.init(id: item, title: current.title, value: page + total, glyph: "books.vertical", route: "madar://mihbara", share: current.pages.flatMap { $0 > 0 ? Double(current.currentPage ?? 0) / Double($0) : nil }))
                }
            case "hadith":
                if let hadith = book.hadithToday { result.append(.init(id: item, title: "حديث اليوم", value: hadith.title, glyph: "books.vertical", route: "madar://mihbara")) }
            case "diaryLine":
                if let row = roomValues[.diaryWrite]?.rows.first(where: { $0.id == "lastLine" }) { result.append(from(row, id: item, glyph: "MadarDiary")) }
                else { result.append(.init(id: item, title: "سطر اليوم", value: "اكتب", detail: "فكرة صغيرة تستحق أن تبقى", glyph: "MadarDiary", route: "madar://notes/write")) }
            case "ramadan":
                if service.calendarDays.hijri(day).month == 9 { result.append(.init(id: item, title: "رمضان", value: "شهر القرآن", glyph: "moon", route: "madar://quran")) }
                else if let left = service.year().ramadanIn { result.append(.init(id: item, title: "رمضان", value: WidgetCopy.daysLeft(left, digits: digits, dayCount: service.dayCount), glyph: "moon", route: "madar://bahw/year")) }
            case "hijriClock":
                var calendar = Calendar(identifier: .gregorian); calendar.timeZone = service.prayerLocation().place.timeZone
                let parts = calendar.dateComponents([.hour, .minute], from: now)
                let clock = digits.localized(String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0))
                result.append(.init(id: item, title: "الآن", value: clock, detail: dates.primary, secondDate: dates.secondary, glyph: "clock", route: "madar://bahw"))
            default:
                if item.hasPrefix("habit:"), let id = UUID(uuidString: String(item.dropFirst(6))), let habit = readings.first(where: { $0.id == id }), let period = habit.summary.current {
                    result.append(.init(id: item, title: habit.name, value: habit.statusTitle,
                                        detail: WidgetCopy.habitProgress(value: period.value, target: period.target, measure: period.rule.measure, unit: period.rule.unit, digits: digits),
                                        glyph: "MadarHabits", route: "madar://bahw/habits/" + id.uuidString, share: Double(period.value) / Double(max(1, period.target)),
                                        habitID: habit.source == nil && !habit.paused && !period.met && period.target > 0 ? id : nil))
                } else if item.hasPrefix("day:"), let id = UUID(uuidString: String(item.dropFirst(4))), let row = service.upcoming(limit: Int.max).first(where: { $0.id == id.uuidString }) {
                    let date = dateLabels(row.day)
                    result.append(.init(id: item, title: row.title, value: row.elapsedDays.map(service.sincePhrase) ?? WidgetCopy.daysLeft(row.daysLeft, digits: digits, dayCount: service.dayCount), detail: date.primary, secondDate: date.secondary, glyph: "MadarUpcoming", route: "madar://bahw/year", share: row.closed))
                }
            }
        }
        if draft.style.iftarCountdown, service.calendarDays.hijri(day).month == 9,
           let maghrib = prayer?.items.first(where: { $0.prayer == "maghrib" && $0.at > now }) {
            result.insert(.init(id: "iftar", title: "إلى الإفطار", value: "", detail: "بتوقيت مدينتك", glyph: "moon", route: "madar://salah", targetDate: maghrib.at), at: 0)
        }
        let location = service.prayerLocation(), civil = GregorianDay.containing(now, in: location.place.timeZone)
        let todayPrayers = PrayerTimesEngine.calculate(day: civil, place: location.place, options: location.options)
        let tomorrowPrayers = PrayerTimesEngine.calculate(day: civil.adding(days: 1), place: location.place, options: location.options)
        for i in result.indices {
            if ["quranCoverage", "quranReview"].contains(result[i].id) {
                result[i].preferredFrom = todayPrayers?.fajr; result[i].preferredUntil = todayPrayers?.dhuhr
            } else if result[i].id == "diaryLine" {
                result[i].preferredFrom = todayPrayers?.maghrib; result[i].preferredUntil = tomorrowPrayers?.fajr
            } else if result[i].id == "habitsToday" || result[i].id.hasPrefix("habit:") {
                let relevant = readings.first { row in row.isNow && (result[i].id == "habitsToday" || result[i].habitID == row.id) }
                if let rule = relevant?.summary.current?.rule {
                    let windows = [civil.adding(days: -1), civil].compactMap { day in
                        HabitEngine.window(rule: rule, civilDay: day, place: location.place, prayer: PrayerTimesEngine.calculate(day: day, place: location.place, options: location.options))
                    }
                    if let window = windows.first(where: { now >= $0.start && now < $0.end }) {
                        result[i].preferredFrom = window.start; result[i].preferredUntil = window.end
                    }
                }
            }
        }
        return result
    }
}


struct SavedLobbyWidgets: View {
    @Bindable var session: AppSession
    @State private var configs: [WidgetCatalogSnapshot.Config] = []
    @Environment(\.colorScheme) private var colorScheme
    private var key: String { "\(session.prayerRevision)-\(session.protectedDataAuthorized)-\(Int(session.prayerNow().timeIntervalSince1970 / 60))" }
    var body: some View {
        WidgetMakerGlassGroup {
        BahwGridLayout(placements: BahwGrid.pack(configs.map { ($0.id.uuidString, size($0)) })) {
            ForEach(configs) { config in
                let style = (try? JSONDecoder().decode(WidgetMakerStyle.self, from: config.styleJSON)) ?? .init()
                WidgetMakerContent(config: config, family: size(config) == .small ? .systemSmall : size(config) == .large ? .systemLarge : .systemMedium,
                                   date: session.prayerNow(), timeZoneID: AppBahwService(session: session).prayerLocation().place.timeZoneID)
                    .padding(12).modifier(WidgetMakerAppSurface(style: style, dark: colorScheme == .dark))
                    .accessibilityElement(children: .contain).accessibilityIdentifier("maker-lobby-" + config.id.uuidString)
            }
        }
        }
        .task(id: key) {
            guard session.lockController?.canPresent(.app) ?? session.protectedDataAuthorized else { configs = []; return }
            let drafts = (try? session.widgetMakerDrafts()) ?? []
            configs = drafts.filter { $0.style.surface == "lobby" }.compactMap { draft in
                let rows = session.widgetMakerRows(draft, at: session.prayerNow(), outside: false)
                if draft.style.hideWhenEmpty && rows.isEmpty { return nil }
                return .init(id: draft.id, name: draft.name, familyID: draft.familyID, styleJSON: (try? JSONEncoder().encode(draft.style)) ?? Data(), rows: rows)
            }
        }
    }
    private func size(_ config: WidgetCatalogSnapshot.Config) -> BahwBlockSize {
        switch config.familyID { case "small": .small; case "large", "extraLargePortrait": .large; default: .wide }
    }
}
