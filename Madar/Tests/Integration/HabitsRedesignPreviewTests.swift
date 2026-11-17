import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 17 Nov), round 14. The owner pointed at the original W2 habits screen («قصدي ذولي»):
// same look as that picture (bahw paper, Thmanyah serif title and sans text, white cards, the W2 list rows and the
// W2 orbit). Order from the owner: habits on top → tap one for its story → the orbit used better → smart notes
// (when you do it, amount or frequency trend, weekday pattern) → the year (dot fabric, months, best and worst).
// Synthetic data; not wired into the app.

private let missedInk = Color(red: 0.647, green: 0.306, blue: 0.204)
private let orbitPaper = Color(red: 0.969, green: 0.941, blue: 0.886)

private struct H: Identifiable {
    let id = UUID()
    let name: String, symbol: String, band: Int        // band 0 day, 1 week, 2 month, 3 year
    let share: Double, done: Bool
    let line: String, streak: String, streakUnit: String, dots: [Double]
    var warn: String? = nil
}

private let habits: [H] = [
    .init(name: "المشي", symbol: "figure.walk", band: 0, share: 0.7, done: false, line: "٣٫٥ من ٥ كم، يسألك ٦:٠٠ م", streak: "١٢", streakUnit: "يومًا", dots: [1,1,1,1,1,1,0.5], warn: "بقي ١٫٥ كم، وتمشي عادة قبل المغرب"),
    .init(name: "القراءة", symbol: "book", band: 0, share: 1, done: true, line: "٢٠ من ٢٠ صفحة", streak: "١٥", streakUnit: "يومًا", dots: [1,1,1,1,1,1,1]),
    .init(name: "الماء", symbol: "drop", band: 0, share: 1, done: true, line: "٨ من ٨ أكواب", streak: "١٦", streakUnit: "يومًا", dots: [1,1,1,1,1,1,1]),
    .init(name: "أذكار الصباح", symbol: "sun.max", band: 0, share: 1, done: true, line: "تمّت ٧:١٠ ص", streak: "٤٠", streakUnit: "يومًا", dots: [1,1,1,1,1,1,1]),
    .init(name: "الرياضة", symbol: "dumbbell", band: 0, share: 0, done: false, line: "٣٠ دقيقة، يسألك ٨:٠٠ م", streak: "٢", streakUnit: "يومان", dots: [1,0,1,0,0,1,0]),
    .init(name: "النوم المبكر", symbol: "moon", band: 0, share: 0, done: false, line: "قبل ١١:٠٠ م، يسألك صباح الغد", streak: "٣", streakUnit: "ليالٍ", dots: [1,1,0,1,1,1,0]),
    .init(name: "الاتصال بالأهل", symbol: "phone", band: 1, share: 0.5, done: false, line: "١ من ٢ هذا الأسبوع، أي يوم", streak: "٣", streakUnit: "أسابيع", dots: [1,1,1,1,0.5]),
    .init(name: "الأيام البيض", symbol: "moon.stars", band: 2, share: 0.67, done: false, line: "٢ من ٣، الباقي ١٥ جمادى الآخرة", streak: "٨", streakUnit: "أشهر", dots: [1,1,1,1,0.5]),
    .init(name: "العمرة", symbol: "cube", band: 3, share: 0, done: false, line: "مرة في السنة الهجرية، أي وقت", streak: "٢", streakUnit: "سنتان", dots: [1,1,0]),
]

/// What changes when a habit is chosen: the orbit's centre, the period cells, the notes and the year.
private struct Focus {
    let center: String, centerSub: String
    let periods: [(String, String, Double)]
    let peakTitle: String, hours: [Double]
    let trendLabel: String, trendTitle: String, trend: [Double]
    let weekTitle: String, week: [Double]
    let yearNote: String, monthLabel: String, monthly: [Double?], unit: String
}

private let allFocus = Focus(
    center: "٤ من ٩", centerSub: "عادات اليوم",
    periods: [("اليوم", "٤ من ٩", 0.44), ("الأسبوع", "٨٥٪", 0.85), ("الشهر", "٨٧٪", 0.87), ("السنة", "٨١٪", 0.81)],
    peakTitle: "صباحك أقوى: ٦٠٪ مما تنجزه قبل الظهر، وعادات المساء هي التي تفوتك.",
    hours: [9,7,4,3,3,2,2,2,2,2,2,3,4,4,3,5,6,4],
    trendLabel: "نسبة التزامك، آخر ٨ أسابيع", trendTitle: "التزامك يرتفع للأسبوع الثامن على التوالي: من ٧٤٪ إلى ٨٨٪.",
    trend: [74,77,80,82,84,86,87,88],
    weekTitle: "الخميس والجمعة أضعف أيامك في كل العادات.", week: [0.9,0.85,0.85,0.88,0.8,0.6,0.65],
    yearNote: "التزام ٨١٪", monthLabel: "التزامك كل شهر",
    monthly: [62,70,74,68,81,77,83,79,85,80,87,nil], unit: "٪")

private let walkFocus = Focus(
    center: "٣٫٥", centerSub: "من ٥ كم اليوم",
    periods: [("اليوم", "٣٫٥ كم", 0.7), ("الأسبوع", "١٨٫٥ كم", 0.92), ("الشهر", "٧٨ كم", 0.92), ("السنة", "٩٩٦ كم", 0.84)],
    peakTitle: "تمشي غالبًا بين ٥:٠٠ و٦:٣٠ م. وإذا تأخرت بعد ٨:٠٠ م يفوتك في الغالب.",
    hours: [0,0,0,0,0,0,0,0,0,0,0,2,6,9,5,2,1,0],
    trendLabel: "معدّل مشيك في اليوم، آخر ٨ أسابيع", trendTitle: "مسافتك تطول: صار معدّلك ٤٫٦ كم في اليوم، وكان ٣٫٦ قبل شهرين.",
    trend: [3.6,3.9,4.1,4,4.4,4.5,4.7,4.6],
    weekTitle: "الخميس أضعف أيامك: تمشي فيه ٥٥٪ فقط. جرّب سؤاله ٧:٠٠ م.", week: [0.9,0.88,0.85,0.9,0.8,0.55,0.75],
    yearNote: "٩٩٦ كم حتى الآن", monthLabel: "كم مشيت كل شهر",
    monthly: [nil,60,95,110,120,98,85,105,130,115,78,nil], unit: "كم")

private func digitsAr(_ v: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

private struct Card<Content: View>: View {
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 0) { content() }
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
    }
}

private struct Ring: View {
    let share: Double; let done: Bool; let symbol: String?; var width: CGFloat = 3.5
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ZStack {
            Circle().fill(done ? theme.accentFill : .clear)
            Circle().stroke(theme.line, lineWidth: width)
            if !done {
                Circle().trim(from: 0, to: share).stroke(theme.accentFill, style: .init(lineWidth: width, lineCap: .round))
                    .rotationEffect(.degrees(-90)).scaleEffect(x: -1)
            }
            if let symbol { Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(done ? theme.onAccent : theme.accent) }
        }.padding(width / 2)
    }
}

private struct HabitRow: View {
    let h: H; let selected: Bool
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(spacing: 12) {
            Ring(share: h.share, done: h.done, symbol: h.symbol).frame(width: 46, height: 46)
            VStack(alignment: .leading, spacing: 4) {
                Text(h.name).font(MadarTypography.section())
                Text(h.line).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if let warn = h.warn {
                    Label(warn, systemImage: "circle.lefthalf.filled").font(MadarTypography.fine()).foregroundStyle(theme.accent)
                }
            }
            Spacer(minLength: 6)
            VStack(alignment: .trailing, spacing: 6) {
                HStack(alignment: .firstTextBaseline, spacing: 4) {
                    Text(h.streak).font(.custom("thmanyahserifdisplay-Bold", size: 22)).foregroundStyle(theme.accent)
                    Text(h.streakUnit).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                HStack(spacing: 3) {
                    ForEach(Array(h.dots.enumerated()), id: \.offset) { _, v in
                        Circle().fill(v >= 1 ? theme.accentFill : v > 0 ? theme.accentFill.opacity(0.45) : .clear)
                            .overlay { if v == 0 { Circle().stroke(theme.secondaryInk, lineWidth: 1) } }
                            .frame(width: 6, height: 6)
                    }
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 13)
        .background(selected ? theme.accentFill.opacity(0.1) : .clear)
        .overlay(alignment: .leading) { if selected { Capsule().fill(theme.accent).frame(width: 3).padding(.vertical, 12) } }
    }
}

private struct PeriodCards: View {
    let focus: Focus
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(spacing: 8) {
            ForEach(focus.periods, id: \.0) { p in
                HStack(spacing: 6) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(p.0).font(.custom("thmanyahsans-Bold", size: 14)).lineLimit(1).fixedSize()
                        Text(p.1).font(.custom("thmanyahsans-Regular", size: 11)).foregroundStyle(theme.secondaryInk).lineLimit(1).fixedSize()
                    }
                    Spacer(minLength: 0)
                    Ring(share: p.2, done: false, symbol: nil, width: 3).frame(width: 22, height: 22)
                }
                .padding(.horizontal, 7).padding(.vertical, 12)
                .background(theme.surface, in: .rect(cornerRadius: 18))
                .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line, lineWidth: 1) }
            }
        }
    }
}

/// The W2 orbit, put to better use: four bands, each habit a bead on its band, a «now» mark per band,
/// the band's share as an arc. A chosen habit's bead grows and glows, the rest fade.
private struct Orbit: View {
    let focus: Focus; let selected: String?
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { g in
            let c = CGPoint(x: g.size.width / 2, y: 170)
            let radii: [CGFloat] = [74, 104, 134, 162]
            let labels = ["اليوم ٤٤٪", "الأسبوع ٨٥٪", "الشهر ٨٧٪", "السنة ٨١٪"]
            let shares = [0.44, 0.85, 0.87, 0.81], now = [0.62, 0.57, 0.57, 0.88]
            let point = { (r: CGFloat, f: Double) -> CGPoint in
                let a = f * 2 * .pi
                return CGPoint(x: c.x - r * sin(a), y: c.y - r * cos(a))
            }
            let slots: [[Double]] = [[0.14, 0.3, 0.46, 0.64, 0.8, 0.95], [0.3], [0.72], [0.4]]
            ZStack {
                ForEach(0..<4, id: \.self) { i in
                    Circle().stroke(theme.line, lineWidth: 1).frame(width: radii[i] * 2, height: radii[i] * 2).position(c)
                    Circle().trim(from: 0, to: shares[i])
                        .stroke(theme.accentFill.opacity(selected == nil ? 0.55 : 0.2), style: .init(lineWidth: 4, lineCap: .round))
                        .rotationEffect(.degrees(-90)).scaleEffect(x: -1)
                        .frame(width: radii[i] * 2, height: radii[i] * 2).position(c)
                    Text(labels[i]).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        .padding(.horizontal, 5).background(orbitPaper)
                        .position(x: c.x, y: c.y - radii[i])
                    Circle().fill(theme.ink).frame(width: 6, height: 6).position(point(radii[i], now[i]))
                }
                ForEach(Array(habits.enumerated()), id: \.offset) { index, h in
                    let order = habits.prefix(index).filter { $0.band == h.band }.count
                    let p = point(radii[h.band], slots[h.band][order])
                    let on = selected == h.name
                    ZStack {
                        if on { Circle().fill(theme.accentFill.opacity(0.22)).frame(width: 38, height: 38).blur(radius: 2) }
                        Circle().fill(h.done ? theme.accentFill : h.share > 0 ? theme.accentFill.opacity(0.4) : theme.surface)
                            .overlay { if !h.done { Circle().stroke(theme.accentFill, lineWidth: 2.5) } }
                            .frame(width: on ? 24 : 17, height: on ? 24 : 17)
                    }
                    .opacity(selected == nil || on ? 1 : 0.3)
                    .position(p)
                    if on || (selected == nil && [0, 4, 6].contains(index)) {
                        Text(h.name).font(.custom("thmanyahsans-Bold", size: 11)).foregroundStyle(on ? theme.onAccent : theme.accent)
                            .padding(.horizontal, 6).padding(.vertical, 1)
                            .background(on ? theme.accentFill : orbitPaper, in: .capsule)
                            .position(x: p.x, y: p.y + (on ? -24 : 18))
                    }
                }
                VStack(spacing: 2) {
                    Text(focus.center).font(.custom("thmanyahserifdisplay-Bold", size: 26))
                    Text(focus.centerSub).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                .frame(width: 104, height: 104).background(theme.surface, in: .circle)
                .overlay { Circle().stroke(theme.line) }.position(c)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(height: 350)
        .overlay(alignment: .bottom) {
            HStack(spacing: 12) {
                legend("تمّت") { Circle().fill(theme.accentFill) }
                legend("جزء منها") { Circle().fill(theme.accentFill.opacity(0.4)).overlay { Circle().stroke(theme.accentFill, lineWidth: 1.5) } }
                legend("تنتظر") { Circle().fill(theme.surface).overlay { Circle().stroke(theme.accentFill, lineWidth: 1.5) } }
                legend("الآن") { Circle().fill(theme.ink).padding(2) }
            }
            .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.bottom, 4)
        }
        .padding(.vertical, 14)
        .background(orbitPaper, in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(theme.line) }
    }
    private func legend<S: View>(_ title: String, @ViewBuilder _ mark: () -> S) -> some View {
        Label { Text(title) } icon: { mark().frame(width: 10, height: 10) }
    }
}

private struct Note<Chart: View>: View {
    let label: String, title: String
    @ViewBuilder let chart: () -> Chart
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                Text(label).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                Text(title).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                chart()
            }.padding(16)
        }
    }
}

private struct Bars: View {
    let values: [Double]; var height: CGFloat = 54; var labels: [String]? = nil; var lowIsBad = false
    @Environment(\.roomTheme) private var theme
    var body: some View {
        let mx = values.max() ?? 1, mn = values.min() ?? 0
        HStack(alignment: .bottom, spacing: labels == nil ? 3 : 10) {
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                VStack(spacing: 5) {
                    RoundedRectangle(cornerRadius: labels == nil ? 3 : 6)
                        .fill(lowIsBad && v == mn ? missedInk : v == mx ? theme.accentFill : theme.accentFill.opacity(v >= mx * 0.5 ? 0.55 : 0.25))
                        .frame(height: max(4, height * v / max(mx, 0.0001)))
                    if let labels { Text(labels[i]).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                }
            }
        }
        .frame(height: height + (labels == nil ? 0 : 20), alignment: .bottom)
    }
}

private struct Trend: View {
    let values: [Double]
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { g in
            let mn = values.min()!, mx = values.max()!, span = max(mx - mn, 0.0001)
            let pts = values.enumerated().map { i, v in
                CGPoint(x: g.size.width - CGFloat(i) / CGFloat(values.count - 1) * g.size.width, y: 8 + (1 - (v - mn) / span) * (g.size.height - 16))
            }
            ZStack {
                Path { p in p.move(to: CGPoint(x: pts[0].x, y: g.size.height)); pts.forEach { p.addLine(to: $0) }; p.addLine(to: CGPoint(x: pts.last!.x, y: g.size.height)) }
                    .fill(theme.accentFill.opacity(0.12))
                Path { p in p.addLines(pts) }.stroke(theme.accentFill, style: .init(lineWidth: 3, lineCap: .round, lineJoin: .round))
                Circle().fill(theme.accentFill).overlay { Circle().stroke(theme.surface, lineWidth: 2) }.frame(width: 11, height: 11).position(pts.last!)
            }
            .environment(\.layoutDirection, .leftToRight)
        }.frame(height: 64)
    }
}

private struct YearCard: View {
    let focus: Focus; let seed: Int
    @Environment(\.roomTheme) private var theme
    private let names = ["يناير","فبراير","مارس","أبريل","مايو","يونيو","يوليو","أغسطس","سبتمبر","أكتوبر","نوفمبر","ديسمبر"]
    private let lengths = [31,28,31,30,31,30,31,31,30,31,30,31]
    private func levels() -> [[Int]] {
        let mx = focus.monthly.compactMap { $0 }.max()!
        var state = UInt64(seed)
        func next() -> Double { state = state &* 6364136223846793005 &+ 1442695040888963407; return Double(state >> 33) / Double(UInt64(1) << 31) }
        return (0..<12).map { m in
            (0..<31).map { d in
                guard d < lengths[m] else { return -2 }
                if m == 11 || (m == 10 && d >= 17) { return -1 }
                guard let v = focus.monthly[m] else { return -1 }
                let r = next() * 0.7 + v / mx * 0.55
                return r > 0.95 ? 3 : r > 0.72 ? 2 : r > 0.5 ? 1 : 0
            }
        }
    }
    var body: some View {
        let complete = focus.monthly.enumerated().compactMap { i, v in v.map { (i, $0) } }.filter { $0.0 < 10 }
        let best = complete.max { $0.1 < $1.1 }!, worst = complete.min { $0.1 < $1.1 }!
        let mx = focus.monthly.compactMap { $0 }.max()!
        let grid = levels()
        let unit = { (v: Double) in digitsAr(v) + (focus.unit == "٪" ? "٪" : " " + focus.unit) }
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("سنة ٢٠٢٦").font(MadarTypography.section()); Spacer(); Text(focus.yearNote).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            Card {
                VStack(alignment: .leading, spacing: 5) {
                    ForEach(0..<12, id: \.self) { m in
                        HStack(spacing: 6) {
                            Text(names[m]).font(MadarTypography.fine())
                                .foregroundStyle(m == best.0 ? theme.accent : m == worst.0 ? missedInk : m == 10 ? theme.ink : theme.secondaryInk)
                                .frame(width: 42, alignment: .leading)
                            HStack(spacing: 2) {
                                ForEach(0..<31, id: \.self) { d in
                                    let l = grid[m][d]
                                    RoundedRectangle(cornerRadius: 2.5)
                                        .fill(l < 0 ? Color.clear : l == 3 ? theme.accentFill : theme.accentFill.opacity([0.14, 0.4, 0.7][l]))
                                        .overlay {
                                            if l == -1 { RoundedRectangle(cornerRadius: 2.5).stroke(theme.line, lineWidth: 1) }
                                            if m == 10 && d == 16 { RoundedRectangle(cornerRadius: 2.5).stroke(theme.ink, lineWidth: 1.5) }
                                        }
                                        .frame(width: 8, height: 8)
                                }
                            }
                        }
                    }
                }.padding(14)
            }
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    Text(focus.monthLabel).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(0..<12, id: \.self) { m in
                            let v = focus.monthly[m]
                            VStack(spacing: 4) {
                                Text(m == best.0 || m == worst.0 ? digitsAr(v ?? 0) : " ").font(MadarTypography.fine())
                                    .foregroundStyle(m == best.0 ? theme.accent : missedInk)
                                RoundedRectangle(cornerRadius: 5)
                                    .fill(v == nil ? theme.line.opacity(0.4) : m == best.0 ? theme.accentFill : m == worst.0 ? missedInk : theme.accentFill.opacity(0.38))
                                    .frame(height: v.map { max(6, 86 * $0 / mx) } ?? 4)
                                Text(String(names[m].prefix(3))).font(.custom("thmanyahsans-Regular", size: 11)).foregroundStyle(theme.secondaryInk)
                            }
                        }
                    }.frame(height: 128, alignment: .bottom)
                    HStack(spacing: 10) {
                        extreme("أحسن شهر", names[best.0], unit(best.1), theme.accent)
                        extreme("أقل شهر", names[worst.0], unit(worst.1), missedInk)
                    }
                }.padding(16)
            }
        }
    }
    private func extreme(_ title: String, _ month: String, _ value: String, _ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(tint)
            Text(month).font(MadarTypography.cardTitle())
            Text(value).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.08), in: .rect(cornerRadius: 16))
    }
}

private struct StoryCard: View {
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("قصة العادة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Text("المشي").font(MadarTypography.title())
                    Text("٥ كم كل يوم، يسألك ٦:٠٠ م، وآخر تذكير ١٠:٠٠ م").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                Spacer()
                Text("كل العادات").font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 40)
                    .overlay { Capsule().stroke(theme.line) }
            }
            HStack(alignment: .top, spacing: 10) {
                fact("بدأتها", "٣ فبراير ٢٠٢٦", "١٥ شعبان ١٤٤٧")
                fact("منذ بدأت", "٩٩٦ كم", "في ٢٨٨ يومًا")
                fact("أطول سلسلة", "١٩ يومًا", "في سبتمبر")
            }
        }
        .padding(18)
        .background(theme.surface, in: .rect(cornerRadius: 22))
        .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.accent.opacity(0.5), lineWidth: 1.5) }
    }
    private func fact(_ title: String, _ value: String, _ sub: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(value).font(MadarTypography.section())
            Text(sub).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct HabitsHome: View {
    let selected: String?
    private var theme: RoomTheme { .init(room: "bahw", dark: false) }
    var body: some View {
        let focus = selected == nil ? allFocus : walkFocus
        VStack(alignment: .leading, spacing: 16) {
            ZStack {
                VStack(spacing: 2) {
                    Text("العادات").font(.custom("thmanyahserifdisplay-Bold", size: 26))
                    Text("الثلاثاء ١٧ نوفمبر ٢٠٢٦").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    Text("٧ جمادى الآخرة ١٤٤٨").font(.custom("thmanyahsans-Regular", size: 11)).foregroundStyle(theme.secondaryInk)
                }
                HStack {
                    Label("البهو", systemImage: "chevron.right").font(MadarTypography.section()).padding(.horizontal, 14).frame(height: 46)
                        .background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line) }
                    Spacer()
                    Image(systemName: "plus").font(.system(size: 18, weight: .medium)).frame(width: 46, height: 46)
                        .background(theme.surface, in: .circle).overlay { Circle().stroke(theme.line) }
                }
            }
            PeriodCards(focus: focus)
            HStack(alignment: .firstTextBaseline) {
                Text("يومية").font(MadarTypography.section())
                Text("٤ من ٦").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Spacer()
                Text("اضغط أي عادة لقصتها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            Card { ForEach(Array(habits.filter { $0.band == 0 }.enumerated()), id: \.offset) { i, h in
                if i > 0 { Divider().overlay(theme.line) }
                HabitRow(h: h, selected: selected == h.name)
            } }
            HStack(alignment: .firstTextBaseline) {
                Text("أسبوعية وشهرية وسنوية").font(MadarTypography.section())
                Spacer()
            }
            Card { ForEach(Array(habits.filter { $0.band > 0 }.enumerated()), id: \.offset) { i, h in
                if i > 0 { Divider().overlay(theme.line) }
                HabitRow(h: h, selected: false)
            } }
            if selected != nil { StoryCard() }
            Orbit(focus: focus, selected: selected)
            HStack(spacing: 6) { Image(systemName: "sparkle").foregroundStyle(theme.accent); Text("ما لاحظه مدار").font(MadarTypography.section()) }
            Note(label: "متى تسويها", title: focus.peakTitle) {
                Bars(values: focus.hours)
                HStack { Text("٦ ص"); Spacer(); Text("١٢ م"); Spacer(); Text("٦ م"); Spacer(); Text("١١ م") }
                    .font(.custom("thmanyahsans-Regular", size: 11)).foregroundStyle(theme.secondaryInk)
            }
            Note(label: focus.trendLabel, title: focus.trendTitle) { Trend(values: focus.trend) }
            Note(label: "أيام الأسبوع", title: focus.weekTitle) {
                Bars(values: focus.week, height: 64, labels: ["س","ح","ن","ث","ر","خ","ج"], lowIsBad: true)
            }
            YearCard(focus: focus, seed: selected == nil ? 7 : 19)
            VStack(spacing: 4) {
                Text("«أحبّ الأعمال إلى الله أدومها وإن قلّ»").font(MadarTypography.body())
                Text("متفق عليه، من حديث عائشة رضي الله عنها").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.frame(maxWidth: .infinity).padding(.vertical, 10)
        }
        .padding(.horizontal, 16).padding(.vertical, 22)
        .foregroundStyle(theme.ink)
        .background(theme.background)
        .environment(\.roomTheme, theme)
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for (name, view) in [("L1-w2-all", AnyView(HabitsHome(selected: nil))), ("L2-w2-walk", AnyView(HabitsHome(selected: "المشي")))] {
            let renderer = ImageRenderer(content: view.frame(width: 393).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name).png"))
        }
    }
}
