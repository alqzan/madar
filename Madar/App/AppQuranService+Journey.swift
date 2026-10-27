import Foundation
import MadarCore
import MadarQuran

struct QuranUIJourneyPoint: Identifiable, Sendable { var id: String; var day: GregorianDay; var remaining: Int }
struct QuranUIJourneyStat: Identifiable, Sendable { var id: String; var title: String; var value: String; var detail: String }
struct QuranUIJourney: Sendable {
    var points: [QuranUIJourneyPoint]; var stats: [QuranUIJourneyStat]; var pages: [QuranUIIndexItem]
    var pageDates: [Int: String]; var shades: [Int: Double]; var planned: String; var actual: String; var explanation: String
    var first: String; var today: String; var remaining: Int; var forecastDay: GregorianDay?
}
extension AppQuranService {
    func journeyLog() async throws -> QuranUIJourney {
        let value = try snapshot(), today = value.day.date
        let first = value.sessions.filter { $0.kind == .hifz }.map(\.dayKey).min()
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
        var planned = "ابدأ خطة الحفظ لتقدير الموعد"
        if let p = value.plan {
            let forecast = try forecast(QuranUIPlanInput(startAyah: p.plan.startAyah, unit: QuranUIUnit(rawValue: p.plan.unit.rawValue)!, amount: p.plan.amount, rhythm: QuranUIRhythm(rawValue: p.plan.intensity.rawValue)!, restDay: value.restDay.rawValue, missPolicy: p.missPolicy), snapshot: value)
            planned = forecast.title
            if let other = forecast.secondaryDate { planned += "، " + other }
        }
        let groups = Dictionary(grouping: value.completedOn.values.filter { $0 <= today }, by: { $0 }).sorted { $0.key < $1.key }
        var total = 0
        var points: [QuranUIJourneyPoint] = []
        // Pages held without a completion day (imported or marked as already memorised) are held from the start,
        // and the line starts on the earliest day anything happened, so it never jumps vertically.
        total = completed - groups.reduce(0) { $0 + $1.value.count }
        // A day-one bulk (memorisation marked when the plan began) is where the line starts, not a cliff.
        if let start = [first, groups.first?.key].compactMap({ $0 }).min(), groups.first?.key != start { points.append(QuranUIJourneyPoint(id: "start", day: start, remaining: 604 - max(0, total))) }
        for group in groups { total += group.value.count; points.append(QuranUIJourneyPoint(id: group.key.description, day: group.key, remaining: 604 - total)) }
        if points.last?.day != today { points.append(QuranUIJourneyPoint(id: "today", day: today, remaining: 604 - completed)) }
        let activeDays = Set(value.activities.filter { $0.countsForStreak && $0.dayKey <= today }.map(\.dayKey)).sorted()
        let longest = activeDays.map { QuranProgressEngine.streak(activities: value.activities, through: $0, restDay: value.restDay).days }.max() ?? 0
        let review = Dictionary(grouping: value.sessions.filter { [.review, .free, .qiyam].contains($0.kind) }, by: \.dayKey).values.reduce(0) { $0 + Set($1.flatMap { $0.grades.map(\.page) }).count }
        let stats = [
            QuranUIJourneyStat(id: "days", title: "منذ البداية", value: dayCount(first.map { max(1, $0.quranDistance(to: today) + 1) } ?? 0), detail: first.map { displayDate($0) } ?? "لا حفظ مسجّل"),
            QuranUIJourneyStat(id: "hifz", title: "في صدرك", value: faceCount(completed), detail: "من جميع الأوجه، مع الفجوات"),
            QuranUIJourneyStat(id: "review", title: "المراجعة", value: faceCount(review), detail: "الوجه مرة واحدة في اليوم"),
            QuranUIJourneyStat(id: "juz", title: "أجزاء مكتملة", value: numerals.string(value.coverage.completedJuz.count), detail: "الجزء كله محفوظ"),
            QuranUIJourneyStat(id: "streak", title: "أطول سلسلة", value: dayCount(longest), detail: "يوم الراحة خارج المقام"),
            QuranUIJourneyStat(id: "pace", title: "وتيرتك الفعلية", value: pace.pagesPerHifzDay.map { numerals.localized(String(format: "%.2f", $0).replacingOccurrences(of: ".", with: "٫")) + " وجه" } ?? "—", detail: "لكل يوم حفظ في آخر ٢٨ يومًا")
        ]
        return QuranUIJourney(points: points, stats: stats, pages: try await index(.page), pageDates: value.completedOn.mapValues { displayDate($0) }, shades: value.completedOn.mapValues { 0.4 + 0.6 * Double(max(0, $0.quranDistance(to: today))) / Double(max(1, first?.quranDistance(to: today) ?? 1)) }, planned: planned, actual: actual,
            explanation: "تقدير الوتيرة الفعلية لكل القرآن من آخر ٢٨ يومًا. موعد الخطة يخص نطاقها. بافتراض استمرار الوتيرة بلا فوت أو تثبيت؛ حُسب في " + displayDate(today),
            first: first.map { displayDate($0) } ?? "بداية الطريق", today: displayDate(today), remaining: 604 - completed, forecastDay: forecastDay)
    }
}

extension GregorianDay {
    func quranDistance(to day: GregorianDay) -> Int { Int(day.date(in: .gmt).timeIntervalSince(date(in: .gmt)) / 86400) }
}
