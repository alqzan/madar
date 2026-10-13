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

/// One archivolt of the «سلاسلك» arch: a horseshoe arc (240°, springing 30° below the centre line), foot to foot.
struct PrayerStreakArc: Shape {
    /// Radius as a fraction of the drawing width.
    let radius: CGFloat
    /// The shared centre, as a fraction of the drawing height.
    var centerY: CGFloat = 0.6
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(center: CGPoint(x: rect.midX, y: rect.minY + rect.height * centerY), radius: rect.width * radius,
                    startAngle: .degrees(150), endAngle: .degrees(390), clockwise: false)
        return path
    }
}

/// S1 «سلاسلك»: one arch of three archivolts, congregation inside, on time around it, completion outside
/// (owner decision, 13 October 2026). Each archivolt has 30 stones, one per streak day, laid from both feet
/// towards the keystone; at a month the arch closes. The count keeps growing after that.
struct PrayerStreakArches: View {
    static let monthDays = 30
    let levels: [PrayerStreakLevel]
    let stats: PrayerStatistics
    let digits: MadarNumberFormatter
    @Environment(\.roomTheme) private var theme

    var body: some View {
        VStack(spacing: 14) {
            arch.frame(height: 176).frame(maxWidth: 300).accessibilityHidden(true)
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(levels.enumerated()), id: \.element) { index, level in
                    if index > 0 { Rectangle().fill(theme.line).frame(width: 1, height: 58) }
                    VStack(spacing: 3) {
                        HStack(spacing: 5) {
                            Capsule().fill(color(level)).frame(width: 12, height: 5)
                            Text(level.title).font(PrayerHomeType.smallBold).lineLimit(1)
                        }
                        Text(PrayerCopy.days(level.count(stats), digits: digits))
                            .font(.custom("thmanyahserifdisplay-Bold", size: 19, relativeTo: .headline))
                            .lineLimit(1).minimumScaleFactor(0.75)
                        Text(level.short).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(1)
                    }
                    .frame(maxWidth: .infinity)
                }
            }
        }
    }

    private var arch: some View {
        // Outer archivolt is completion; widths step inwards.
        let radii: [CGFloat] = [0.40, 0.315, 0.23]
        let ordered = Array(levels.reversed())
        return ZStack {
            // Pillars and the floor line, as under the home arches.
            GeometryReader { geometry in
                let w = geometry.size.width, h = geometry.size.height
                let foot = radii[0] * w * 0.5 // sin 30°
                Path { path in
                    for x in [w / 2 - radii[0] * w * 0.866, w / 2 + radii[0] * w * 0.866] {
                        path.move(to: CGPoint(x: x, y: h * 0.6 + foot)); path.addLine(to: CGPoint(x: x, y: h))
                    }
                }
                .stroke(theme.line, lineWidth: 1)
                Capsule().fill(theme.line).frame(width: w * 0.92, height: 2).position(x: w / 2, y: h - 1)
                PrayerLatticePattern(spacing: 9).stroke(theme.color("goldMid").opacity(0.35), lineWidth: 0.6)
                    .clipShape(InnerArch(radius: radii[radii.count - 1] - 0.045))
                PrayerStar().fill(theme.accent).frame(width: 18, height: 18).position(x: w / 2, y: h * 0.6)
            }
            ForEach(Array(ordered.enumerated()), id: \.element) { index, level in
                stones(PrayerStreakArc(radius: radii[index]), level: level)
            }
        }
    }

    /// Thirty stones; the n-th streak day lays the next stone, alternating feet, so the keystone is the 30th.
    private func stones(_ arc: PrayerStreakArc, level: PrayerStreakLevel) -> some View {
        let days = min(level.count(stats), Self.monthDays), n = Self.monthDays
        let laid = Set((0..<days).map { day in day % 2 == 0 ? day / 2 : n - 1 - day / 2 })
        return ZStack {
            ForEach(0..<n, id: \.self) { stone in
                let gap = 0.12 / CGFloat(n)
                arc.trim(from: CGFloat(stone) / CGFloat(n) + gap, to: CGFloat(stone + 1) / CGFloat(n) - gap)
                    .stroke(laid.contains(stone) ? color(level) : theme.ink.opacity(0.07), style: StrokeStyle(lineWidth: 9, lineCap: .butt))
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

    /// The opening of the innermost arch, closed down to the floor, for the lattice.
    private struct InnerArch: Shape {
        let radius: CGFloat
        func path(in rect: CGRect) -> Path {
            var path = PrayerStreakArc(radius: radius).path(in: rect)
            let r = rect.width * radius
            path.addLine(to: CGPoint(x: rect.midX + r * 0.866, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.midX - r * 0.866, y: rect.maxY))
            path.closeSubpath()
            return path
        }
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
