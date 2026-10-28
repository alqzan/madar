import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// The three nested home streaks (owner decision, 13 October 2026): congregation within on time within completion.
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
    /// The legend line under the name on the home card.
    var short: String {
        switch self {
        case .congregation: "الخمس في جماعة"
        case .onTime: "بلا قضاء"
        case .completion: "ولو بقضاء"
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

/// S1 «سلاسلك»: three nested horseshoe arches in the shape of the home arches (`PrayerHorseshoe`) — congregation inside,
/// on time around it, completion outside (owner decision, 13 October 2026). Each arch is one continuous line that fills
/// right to left with the streak and is complete at a month (30 days). The count keeps growing after that.
struct PrayerStreakArches: View {
    static let monthDays = 30
    let levels: [PrayerStreakLevel]
    let stats: PrayerStatistics
    let digits: MadarNumberFormatter
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        HStack(alignment: .center, spacing: 14) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(levels, id: \.self) { level in
                    HStack(spacing: 8) {
                        Capsule().fill(color(level)).frame(width: 6, height: 30).accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(level.title).font(PrayerHomeType.strong).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                            Text(level.short).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(2).minimumScaleFactor(0.85).fixedSize(horizontal: false, vertical: true)
                        }
                        Spacer(minLength: 4)
                        Text(level.count(stats) == 0 ? "لم تبدأ بعد" : PrayerCopy.days(level.count(stats), digits: digits))
                            .font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline))
                            .lineLimit(1).fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity)
            arch.frame(width: 120, height: 196).accessibilityHidden(true)
        }
        .onAppear {
            if reduceMotion { grown = true } else { withAnimation(.easeOut(duration: 0.9)) { grown = true } }
        }
    }

    private var arch: some View {
        // Outer arch is completion; each inner arch is inset on the sides and the crown, standing on the same floor.
        let ordered = Array(levels.reversed())
        let inset: CGFloat = 17
        return GeometryReader { geometry in
            let full = CGRect(origin: .zero, size: geometry.size).insetBy(dx: 5, dy: 0)
            let rects: [CGRect] = (0..<3).map { (i: Int) -> CGRect in
                let step: CGFloat = CGFloat(i) * inset
                return CGRect(x: full.minX + step, y: full.minY + 5 + step,
                              width: full.width - step * 2, height: full.height - 5 - step - 3)
            }
            let inner = rects[2]
            ZStack {
                PrayerStar().fill(theme.accent).frame(width: 16, height: 16)
                    .position(x: inner.midX, y: inner.minY + inner.width / 2 + 6)
                ForEach(Array(ordered.enumerated()), id: \.element) { index, level in
                    stones(in: rects[index], level: level)
                }
                Capsule().fill(theme.line).frame(width: geometry.size.width, height: 2)
                    .position(x: geometry.size.width / 2, y: geometry.size.height - 1)
            }
        }
    }

    /// One continuous arch line, filled right to left by the streak: up the right leg, over the crown, down to the left foot at a month.
    private func stones(in rect: CGRect, level: PrayerStreakLevel) -> some View {
        let fraction = grown ? min(CGFloat(level.count(stats)), CGFloat(Self.monthDays)) / CGFloat(Self.monthDays) : 0
        let shape = PrayerHorseshoe().path(in: rect)
        let fill = StrokeStyle(lineWidth: 8, lineCap: .round, lineJoin: .round)
        return ZStack {
            shape.stroke(theme.ink.opacity(0.07), style: StrokeStyle(lineWidth: 8, lineCap: .butt, lineJoin: .round))
            if level.count(stats) > 0 {
                // The path starts at the left foot in code; the RTL layout mirrors it, so the fill reads right to left.
                PathShape(path: shape).trim(from: 0, to: fraction).stroke(color(level), style: fill)
            }
        }
    }

    private func color(_ level: PrayerStreakLevel) -> Color {
        switch level {
        case .congregation: theme.accent
        case .onTime: theme.color("goldMid")
        case .completion: theme.secondaryInk
        }
    }

    /// A fixed path as a `Shape`, so its trim animates.
    private struct PathShape: Shape {
        let path: Path
        func path(in rect: CGRect) -> Path { path }
    }
}

/// The details behind the arches: what each streak means, the last seven days, and where and why it broke.
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
                    Text(level.count(snapshot.statistics) == 0 ? "لم تبدأ بعد" : PrayerCopy.days(level.count(snapshot.statistics), digits: digits))
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
