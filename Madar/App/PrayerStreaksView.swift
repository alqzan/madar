import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// The three nested home streaks (owner decision, 13 October 2026), drawn as minbar steps:
/// completion is the base, on time above it, congregation on top. Each step includes the ones under it.
extension PrayerStreakLevel {
    var title: String {
        switch self {
        case .congregation: "الجماعة"
        case .onTime: "في وقتها"
        case .completion: "إتمام الخمس"
        }
    }
    var meaning: String {
        switch self {
        case .congregation: "الخمس كلها في جماعة"
        case .onTime: "الخمس في وقتها، بلا قضاء"
        case .completion: "صليتَ الخمس، ولو قضيتَ منها"
        }
    }
    func count(_ stats: PrayerStatistics) -> Int {
        switch self {
        case .congregation: stats.congregationStreak
        case .onTime: stats.prayerStreak
        case .completion: stats.completionStreak
        }
    }
    /// Top step first.
    static func shown(congregation: Bool) -> [PrayerStreakLevel] {
        congregation ? [.congregation, .onTime, .completion] : [.onTime, .completion]
    }
}

/// The glyph of each level, from the status marks the owner approved in S4.
struct PrayerStreakGlyph: View {
    let level: PrayerStreakLevel
    var size: CGFloat = 16
    @Environment(\.roomTheme) private var theme
    var body: some View {
        switch level {
        case .congregation:
            PrayerStar().fill(theme.accent).frame(width: size, height: size)
        case .onTime:
            PrayerStar().fill(theme.color("goldMid"))
                .overlay { PrayerStar().stroke(theme.accent, lineWidth: 1) }
                .frame(width: size, height: size)
        case .completion:
            PrayerFiveBeads().fill(theme.secondaryInk).frame(width: size * 1.25, height: size)
        }
    }
}

/// Five beads on a small arch: one day's five prayers.
struct PrayerFiveBeads: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let r = min(rect.width, rect.height) * 0.12
        let points: [(CGFloat, CGFloat)] = [(0.12, 0.78), (0.27, 0.35), (0.5, 0.15), (0.73, 0.35), (0.88, 0.78)]
        for (x, y) in points {
            path.addEllipse(in: CGRect(x: rect.minX + rect.width * x - r, y: rect.minY + rect.height * y - r, width: r * 2, height: r * 2))
        }
        return path
    }
}

/// S1 «سلاسلك»: the steps. Tapping the card opens `PrayerStreaksSheet`.
struct PrayerStreakSteps: View {
    let levels: [PrayerStreakLevel]
    let stats: PrayerStatistics
    let digits: MadarNumberFormatter
    @Environment(\.roomTheme) private var theme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(Array(levels.enumerated()), id: \.element) { index, level in
                step(level)
                    .padding(.trailing, CGFloat(levels.count - 1 - index) * 46)
            }
            Capsule().fill(theme.line).frame(height: 3)
        }
    }

    private func step(_ level: PrayerStreakLevel) -> some View {
        HStack(spacing: 8) {
            PrayerStreakGlyph(level: level).accessibilityHidden(true)
            Text(level.title).font(PrayerHomeType.strong).lineLimit(1)
            Spacer(minLength: 6)
            Text(PrayerCopy.days(level.count(stats), digits: digits))
                .font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline))
                .lineLimit(1).minimumScaleFactor(0.8)
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
        .frame(maxWidth: .infinity)
        .background(fill(level), in: UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 14))
        .overlay {
            UnevenRoundedRectangle(topLeadingRadius: 14, bottomLeadingRadius: 6, bottomTrailingRadius: 6, topTrailingRadius: 14)
                .stroke(stroke(level), lineWidth: 1.5)
        }
    }

    private func fill(_ level: PrayerStreakLevel) -> Color {
        switch level {
        case .congregation: theme.accent.opacity(0.12)
        case .onTime: theme.color("goldSoft")
        case .completion: theme.ink.opacity(0.05)
        }
    }
    private func stroke(_ level: PrayerStreakLevel) -> Color {
        switch level {
        case .congregation: theme.accent
        case .onTime: theme.color("goldMid")
        case .completion: theme.ink.opacity(0.4)
        }
    }
}

/// The details behind the steps: what each streak means, the last seven days, and where and why it broke.
struct PrayerStreaksSheet: View {
    let snapshot: PrayerSnapshot
    let levels: [PrayerStreakLevel]
    let digits: MadarNumberFormatter
    let timeZone: TimeZone
    let openHali: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                Text("سلاسلك").font(.custom("thmanyahserifdisplay-Bold", size: 30, relativeTo: .title))
                    .accessibilityAddTraits(.isHeader).accessibilityIdentifier("prayer-streaks-title")
                Text("تُحسب حتى أمس، واليوم لا يكسر سلسلة. كل سلسلة أعلى تشمل ما تحتها.")
                    .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
                ForEach(levels, id: \.self) { section($0) }
                Button(action: openHali) {
                    HStack {
                        Text("حالي: سجلّ الشهر").font(PrayerHomeType.strong)
                        Spacer()
                        Image(systemName: "chevron.forward").font(.footnote.weight(.semibold)).accessibilityHidden(true)
                    }
                    .foregroundStyle(theme.color("accentText"))
                    .padding(.horizontal, 20).frame(minHeight: 52)
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
                    .contentShape(.rect(cornerRadius: 18))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("prayer-history")
            }
            .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 20)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.large])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
    }

    private func section(_ level: PrayerStreakLevel) -> some View {
        let marks = Array(PrayerStreaks.marks(snapshot.history, level: level, qada: snapshot.qada, before: snapshot.today.day).prefix(7))
        let week = Array(marks.reversed()) // oldest first: oldest on the right, yesterday on the left, as the Mizan beads.
        return PrayerPaperCard {
            VStack(alignment: .leading, spacing: 12) {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    PrayerStreakGlyph(level: level, size: 18).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(level.title).font(PrayerHomeType.strong)
                        Text(level.meaning).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 6)
                    Text(PrayerCopy.days(level.count(snapshot.statistics), digits: digits))
                        .font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title3))
                }
                HStack(spacing: 6) {
                    ForEach(week, id: \.day) { item in
                        VStack(spacing: 4) {
                            cell(item.mark, level: level)
                            Text(item.day == week.last?.day ? "أمس" : initial(item.day))
                                .font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2))
                                .foregroundStyle(theme.secondaryInk)
                        }
                        .frame(maxWidth: .infinity)
                    }
                }
                .accessibilityHidden(true)
                if let reason = breakLine(marks) {
                    Text(reason).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier("prayer-streak-\(level.rawValue)")
    }

    @ViewBuilder private func cell(_ mark: PrayerStreakMark, level: PrayerStreakLevel) -> some View {
        let shape = RoundedRectangle(cornerRadius: 8)
        ZStack {
            switch mark {
            case .counted:
                shape.fill(solid(level))
            case .open:
                shape.stroke(theme.ink.opacity(0.25), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
            case .outside:
                shape.fill(theme.ink.opacity(0.06))
            case .brokeAlone, .brokeQada, .brokeMissed:
                shape.stroke(theme.ink.opacity(0.35), style: StrokeStyle(lineWidth: 1, dash: [3, 3]))
                reasonGlyph(mark)
            }
        }
        .frame(height: 28)
    }

    @ViewBuilder private func reasonGlyph(_ mark: PrayerStreakMark) -> some View {
        switch mark {
        case .brokeAlone:
            PrayerStar().fill(theme.color("goldMid")).overlay { PrayerStar().stroke(theme.accent, lineWidth: 1) }.frame(width: 13, height: 13)
        case .brokeQada:
            Image(systemName: "hourglass").font(.system(size: 13)).foregroundStyle(theme.secondaryInk)
        default:
            PrayerHorseshoe().stroke(theme.color("missed"), lineWidth: 1.2).frame(width: 12, height: 13)
        }
    }

    private func solid(_ level: PrayerStreakLevel) -> Color {
        switch level {
        case .congregation: theme.accent
        case .onTime: theme.color("goldMid")
        case .completion: theme.ink.opacity(0.45)
        }
    }

    private func weekday(_ day: GregorianDay) -> Int {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = timeZone
        return calendar.component(.weekday, from: day.date(in: timeZone))
    }
    private func initial(_ day: GregorianDay) -> String {
        ["ح", "ن", "ث", "ر", "خ", "ج", "س"][weekday(day) - 1]
    }
    private func breakLine(_ marks: [(day: GregorianDay, mark: PrayerStreakMark)]) -> String? {
        guard let hit = marks.first(where: { $0.mark.breaks }) else { return nil }
        let name = ["الأحد", "الإثنين", "الثلاثاء", "الأربعاء", "الخميس", "الجمعة", "السبت"][weekday(hit.day) - 1]
        let when = hit.day == marks.first?.day ? "أمس" : "يوم " + name
        switch hit.mark {
        case .brokeAlone: return "انقطعت \(when): صليتَ فرضًا وحدك."
        case .brokeQada: return "انقطعت \(when): قضيتَ فرضًا."
        default: return "انقطعت \(when): فاتك فرض لم يُقضَ بعد."
        }
    }
}
