import Foundation
import MadarCore
import MadarQuran
import MadarCommands

struct QuranUIJourneyPoint: Identifiable, Sendable { var id: String; var day: GregorianDay; var remaining: Int }
struct QuranUIJourneyStat: Identifiable, Sendable { var id: String; var title: String; var value: String; var detail: String }
struct QuranUIJourneyMapRow: Identifiable, Sendable { var id: Int; var label: String; var summary: String; var pages: [QuranUIIndexItem] }
struct QuranUIJourney: Sendable {
    var points: [QuranUIJourneyPoint]
    var stats: [QuranUIJourneyStat]
    var pages: [QuranUIIndexItem]
    var mapRows: [QuranUIJourneyMapRow]
    var pageDates: [Int: String]
    var shades: [Int: Double]
    var oldestPageDate: String?
    var newestPageDate: String?
    var planned: String
    var actual: String
    var explanation: String
    var first: String
    var today: String
    var remaining: Int
    var forecastDay: GregorianDay?
}

extension AppQuranService {
    func journeyLog() async throws -> QuranUIJourney {
        let value = try snapshot(), today = value.day.date
        let first = value.sessions.filter { $0.kind == .hifz && $0.dayKey <= today }.map(\.dayKey).min()
        let completed = value.coverage.completedPages.count
        let pace = QuranProgressEngine.pace(activities: value.activities, completedOn: value.completedOn, through: today, restDay: value.restDay)
        let start = value.sessions.contains { $0.kind == .hifz && $0.dayKey == today } ? today.adding(days: 1) : today
        var forecastDay: GregorianDay?
        let actual: String
        if value.coverage.isKhatm { actual = "ختمت القرآن" }
        else if let rate = pace.pagesPerHifzDay {
            if case .estimated(let day) = QuranProgressEngine.forecast(remainingPages: Double(604 - completed), dailyPages: rate, startingOn: start, restDay: value.restDay) {
                actual = displayDate(day); forecastDay = day
            } else { actual = "لم تتضح الوتيرة بعد" }
        } else { actual = "تتضح بعد خمسة أيام حفظ وخمسين آية في " + numerals.string(28) + " يومًا" }

        var planned = ""
        if let plan = value.plan {
            let forecast = try forecast(QuranUIPlanInput(startAyah: plan.plan.startAyah, unit: QuranUIUnit(rawValue: plan.plan.unit.rawValue)!, amount: plan.plan.amount, rhythm: QuranUIRhythm(rawValue: plan.plan.intensity.rawValue)!, restDay: value.restDay.rawValue, missPolicy: plan.missPolicy), snapshot: value)
            planned = forecast.title
            if let other = forecast.secondaryDate { planned += "، " + other }
        }

        let groups = Dictionary(grouping: value.completedOn.values.filter { $0 <= today }, by: { $0 }).sorted { $0.key < $1.key }
        var total = completed - groups.reduce(0) { $0 + $1.value.count }
        var points: [QuranUIJourneyPoint] = []
        // Pages held without a completion day (imported or marked as already memorised) are held from the start,
        // and the line starts on the earliest day anything happened, so it never jumps vertically.
        // A day-one bulk (memorisation marked when the plan began) is where the line starts, not a cliff.
        if let start = [first, groups.first?.key].compactMap({ $0 }).min(), groups.first?.key != start {
            points.append(QuranUIJourneyPoint(id: "start", day: start, remaining: 604 - max(0, total)))
        }
        for group in groups {
            total += group.value.count
            points.append(QuranUIJourneyPoint(id: group.key.description, day: group.key, remaining: 604 - total))
        }
        if points.last?.day != today { points.append(QuranUIJourneyPoint(id: "today", day: today, remaining: 604 - completed)) }

        let activeDays = Set(value.activities.filter { $0.countsForStreak && $0.dayKey <= today }.map(\.dayKey)).sorted()
        let longest = activeDays.map { QuranProgressEngine.streak(activities: value.activities, through: $0, restDay: value.restDay).days }.max() ?? 0
        let current = QuranProgressEngine.streak(activities: value.activities, through: today, restDay: value.restDay).days

        let workingDays = Set(value.activities.filter { activity in
            activity.countsForStreak && activity.dayKey <= today && first.map { activity.dayKey >= $0 } == true && !value.restDay.contains(activity.dayKey)
        }.map(\.dayKey)).count
        let scheduledDays: Int
        if let first {
            scheduledDays = (0...max(0, first.quranDistance(to: today))).reduce(0) { count, offset in
                count + (value.restDay.contains(first.adding(days: offset)) ? 0 : 1)
            }
        } else {
            scheduledDays = 0
        }
        let workPercent = scheduledDays > 0 ? numerals.percent(Int((Double(workingDays) * 100 / Double(scheduledDays)).rounded())) : nil

        // A recorded grade is the source fact that a face was recited and assessed in a Quran session.
        // Count each face once per session, while allowing it to be counted again in a later session.
        let recited = value.sessions.filter { [.hifz, .review, .free, .qiyam].contains($0.kind) }
            .reduce(0) { $0 + Set($1.grades.map(\.page)).count }
        let mushafEquivalentValue = Double(recited) / 604
        let mushafEquivalent = numerals.localized(String(format: "%.1f", mushafEquivalentValue).replacingOccurrences(of: ".", with: "٫"))
        let coveragePercent = numerals.percent(value.coverage.percent)
        let recitedDetail: String
        if recited == 0 { recitedDetail = "لا تسميع مسجّل بعد" }
        else if (mushafEquivalentValue * 10).rounded() == 0 { recitedDetail = "أوجه سُجّل لها تقييم في جلساتك؛ وقد يتكرر الوجه" }
        else { recitedDetail = "أوجه سُجّل لها تقييم؛ كأنك سمّعت المصحف " + mushafEquivalent + " مرات" }
        let stats = [
            QuranUIJourneyStat(id: "days", title: "منذ البداية", value: dayCount(first.map { max(1, $0.quranDistance(to: today) + 1) } ?? 0), detail: first.map { displayDate($0) } ?? "لا حفظ مسجّل"),
            QuranUIJourneyStat(id: "work", title: "أيام العمل", value: dayCount(workingDays), detail: workPercent.map { $0 + " من أيام الحفظ المتاحة" } ?? "لا توجد أيام حفظ متاحة"),
            QuranUIJourneyStat(id: "hifz", title: "في صدرك", value: faceCount(completed), detail: coveragePercent + " من القرآن"),
            QuranUIJourneyStat(id: "recited", title: "مجموع ما سمّعت", value: faceCount(recited), detail: recitedDetail),
            QuranUIJourneyStat(id: "streak", title: "أطول سلسلة", value: dayCount(longest), detail: "والحالية " + dayCount(current)),
            QuranUIJourneyStat(id: "pace", title: "معدل الحفظ", value: pace.pagesPerHifzDay.map { numerals.localized(String(format: "%.2f", $0).replacingOccurrences(of: ".", with: "٫")) + " وجه" } ?? "—", detail: pace.pagesPerHifzDay == nil ? "يتضح بعد خمسة أيام حفظ وخمسين آية" : "لكل يوم حفظ في آخر ٢٨ يومًا")
        ]

        let pages = try await index(.page)
        let catalog = try QuranResources.catalog()
        let firstJuzByPage = Dictionary(grouping: catalog.ayahs, by: \.page).compactMapValues { ayahs in
            ayahs.min(by: { $0.id < $1.id })?.juz
        }
        let mapRows = (1...30).map { juz in
            let rowPages = pages.filter { firstJuzByPage[$0.firstPage] == juz }
            let saved = numerals.string(rowPages.filter(\.memorized).count)
            let total = numerals.string(rowPages.count)
            let due = numerals.string(rowPages.filter(\.due).count)
            return QuranUIJourneyMapRow(id: juz, label: numerals.string(juz),
                summary: "الجزء " + numerals.string(juz) + "، محفوظ " + saved + " من " + total + " وجهًا، " + due + " مستحقة للمراجعة",
                pages: rowPages)
        }
        let completedDays = value.completedOn.filter { $0.value <= today }
        let oldestDay = completedDays.values.min()
        let newestDay = completedDays.values.max()
        let span = Double(max(1, oldestDay?.quranDistance(to: today) ?? 1))
        let pageDates = completedDays.mapValues { displayDate($0) }
        let shades = completedDays.mapValues { 0.4 + 0.6 * Double(max(0, $0.quranDistance(to: today))) / span }
        let explanation = "تقدير الوتيرة الفعلية لكل القرآن من آخر ٢٨ يومًا؛ نفترض إتمام أيام الحفظ بالدرجة المعتادة بلا فوت أو تثبيت. حُسب في " + displayDate(today)
        return QuranUIJourney(points: points, stats: stats, pages: pages, mapRows: mapRows,
            pageDates: pageDates, shades: shades, oldestPageDate: oldestDay.map { displayDate($0) }, newestPageDate: newestDay.map { displayDate($0) },
            planned: planned, actual: actual, explanation: explanation,
            first: first.map { displayDate($0) } ?? "بداية الطريق", today: displayDate(today), remaining: 604 - completed, forecastDay: forecastDay)
    }
}

extension GregorianDay {
    func quranDistance(to day: GregorianDay) -> Int { Int(day.date(in: .gmt).timeIntervalSince(date(in: .gmt)) / 86400) }
}
