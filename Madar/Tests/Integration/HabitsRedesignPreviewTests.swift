import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 16 Nov). Round 8, the owner: «أبي شي أنت تجيبه من ذكاءك».
// Idea: «الوتيرة» (pace). Every habit, whatever its unit or frequency, has a plan to date (what you meant to do by today)
// and an actual to date. The room shows one thing per habit: are you ahead of your own plan or behind, by how much,
// and when you will catch up at your current pace. The gold line is what you did; the dashed line is your plan;
// the space between them is gold when ahead and rose when behind, with the room's soft reflection under it.
// Synthetic data; not wired into the app.

private func ar(_ v: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

private struct Pace {
    let actual: [Double]   // cumulative, one value per step so far
    let steps: Int         // steps in the whole period
    let planTotal: Double
}

private struct PaceChart: View {
    let pace: Pace
    var height: CGFloat = 70
    var reflection = false
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = height
            let maxV = max(pace.planTotal, pace.actual.max() ?? 1)
            let x = { (i: Int) in w * CGFloat(i) / CGFloat(pace.steps - 1) }
            let y = { (v: Double) in h - h * CGFloat(v / maxV) }
            let plan = { (i: Int) in pace.planTotal * Double(i) / Double(pace.steps - 1) }
            let n = pace.actual.count
            let ahead = (pace.actual.last ?? 0) >= plan(n - 1)
            let gap = Path { p in
                p.move(to: CGPoint(x: x(0), y: y(pace.actual[0])))
                for i in 1..<n { p.addLine(to: CGPoint(x: x(i), y: y(pace.actual[i]))) }
                for i in stride(from: n - 1, through: 0, by: -1) { p.addLine(to: CGPoint(x: x(i), y: y(plan(i)))) }
                p.closeSubpath()
            }
            let actualLine = Path { p in
                p.move(to: CGPoint(x: x(0), y: y(pace.actual[0])))
                for i in 1..<n { p.addLine(to: CGPoint(x: x(i), y: y(pace.actual[i]))) }
            }
            let planLine = Path { p in p.move(to: CGPoint(x: x(0), y: y(0))); p.addLine(to: CGPoint(x: x(pace.steps - 1), y: y(pace.planTotal))) }
            ZStack(alignment: .topLeading) {
                Rectangle().fill(theme.line).frame(height: 1).offset(y: h)
                gap.fill((ahead ? theme.color("goldMid") : theme.color("missed")).opacity(0.28))
                planLine.stroke(theme.secondaryInk.opacity(0.6), style: StrokeStyle(lineWidth: 1.2, dash: [4, 4]))
                actualLine.stroke(theme.accent, style: StrokeStyle(lineWidth: 2.4, lineCap: .round, lineJoin: .round))
                Circle().fill(theme.accent).frame(width: 9, height: 9)
                    .position(x: x(n - 1), y: y(pace.actual[n - 1]))
                if reflection {
                    ZStack(alignment: .topLeading) {
                        gap.fill((ahead ? theme.color("goldMid") : theme.color("missed")).opacity(0.28))
                        actualLine.stroke(theme.accent, lineWidth: 2)
                    }
                    .scaleEffect(x: 1, y: -0.35, anchor: .top).offset(y: h * 2 + 2)
                    .opacity(0.35)
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom).offset(y: h))
                }
            }
        }
        .frame(height: height * (reflection ? 1.4 : 1))
        .environment(\.layoutDirection, .leftToRight)
        .scaleEffect(x: -1, y: 1) // time runs right to left, like the page
    }
}

private func ramp(_ perStep: [Double]) -> [Double] { perStep.reduce(into: [Double]()) { $0.append(($0.last ?? 0) + $1) } }

private struct HabitPace: Identifiable {
    let id = UUID()
    let name: String
    let rule: String
    let verdict: String     // ahead / behind in the habit's unit
    let detail: String      // the smart sentence
    let ahead: Bool
    let pace: Pace
}

private let paces: [HabitPace] = [
    .init(name: "المشي", rule: "٥ كم كل يوم", verdict: "متقدّم ١٨ كم", detail: "بهذه الوتيرة تختم نوفمبر عند ١٦٨ كم من ١٥٠.", ahead: true,
          pace: Pace(actual: ramp([7, 6, 0, 8, 7, 6, 5, 7, 9, 6, 10, 0, 7, 6, 7, 7]), steps: 30, planTotal: 150)),
    .init(name: "ورد الأذكار", rule: "مرة كل يوم", verdict: "متأخر يومين", detail: "فاتك الجمعتان؛ تلحق خطتك إن لم يفتك يوم حتى ٢٢ نوفمبر.", ahead: false,
          pace: Pace(actual: ramp([1, 1, 1, 1, 0, 1, 1, 1, 1, 1, 1, 0, 1, 1, 1, 1]), steps: 30, planTotal: 30)),
    .init(name: "الرياضة", rule: "٣ مرات أسبوعيًا", verdict: "على خطتك تمامًا", detail: "٤٢ حصة من ٤٢ حتى هذا الأسبوع.", ahead: true,
          pace: Pace(actual: ramp([3, 3, 2, 4, 3, 3, 3, 3, 2, 4, 3, 3, 3, 3]), steps: 52, planTotal: 156)),
    .init(name: "القراءة", rule: "٢٠ صفحة كل يوم", verdict: "متقدّم ٧٠ صفحة", detail: "قرأت ٣٨٠ صفحة في نوفمبر، أي كتابًا ونصفًا تقريبًا.", ahead: true,
          pace: Pace(actual: ramp([25, 20, 30, 15, 40, 20, 25, 30, 20, 35, 25, 20, 30, 25, 20, 0]), steps: 30, planTotal: 600)),
]

// MARK: Room home

private struct PaceHome: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("العادات").font(PrayerHomeType.hero)
                Spacer()
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.background)
                    .frame(width: 44, height: 44).background(theme.accent, in: .circle)
            }
            VStack(alignment: .leading, spacing: 6) {
                Text("أنت متقدّم على خطتك في ٣ عادات من ٤.").font(.custom("thmanyahserifdisplay-Bold", size: 26))
                    .fixedSize(horizontal: false, vertical: true)
                Text("الخط الذهبي ما فعلته، والمتقطع ما نويته حتى اليوم.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            ForEach(paces) { p in
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(p.name).font(PrayerHomeType.cardHead)
                            Text(p.rule).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer()
                        Text(p.verdict).font(PrayerHomeType.strong).foregroundStyle(p.ahead ? theme.accent : theme.color("missedTextOnSurface"))
                    }
                    PaceChart(pace: p.pace, height: 54)
                    Text(p.detail).font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                .padding(18).background(theme.surface, in: .rect(cornerRadius: 22))
            }
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
}

// MARK: Habit page

private struct PaceHabit: View {
    let theme: RoomTheme
    var body: some View {
        let p = paces[0]
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 4) {
                Text(p.name).font(PrayerHomeType.hero)
                Text("٥ كم كل يوم. يسألك ٦:٠٠ م، وآخر تذكير ١٠:٠٠ م.").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            }
            HStack(spacing: 8) {
                ForEach(["الأسبوع", "نوفمبر", "٢٠٢٦"], id: \.self) { t in
                    Text(t).font(PrayerHomeType.smallBold).padding(.horizontal, 14).frame(minHeight: 36)
                        .background(t == "نوفمبر" ? theme.accent : theme.surface, in: .capsule)
                        .foregroundStyle(t == "نوفمبر" ? theme.background : theme.ink)
                }
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("متقدّم ١٨ كم").font(.custom("thmanyahserifdisplay-Bold", size: 40)).foregroundStyle(theme.accent)
                Text("مشيت ٩٨ كم، وخطتك حتى اليوم ٨٠ كم.").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            }
            PaceChart(pace: p.pace, height: 150)
            VStack(alignment: .leading, spacing: 14) {
                insight("بهذه الوتيرة", "تختم نوفمبر عند ١٦٨ كم من ١٥٠.")
                insight("وقتك المعتاد", "بين ٥ و٦ م؛ سؤال ٦:٠٠ م في وقته.")
                insight("يومك الأضعف", "الجمعة: مشيت فيها مرتين من خمس.")
                insight("أطول سلسلة", "٢١ يومًا في سبتمبر، والحالية ١٢.")
            }
            .padding(18).background(theme.surface, in: .rect(cornerRadius: 22))
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func insight(_ title: String, _ text: String) -> some View {
        HStack(alignment: .firstTextBaseline) {
            Text(title).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).frame(width: 96, alignment: .leading)
            Text(text).font(PrayerHomeType.body).fixedSize(horizontal: false, vertical: true)
        }
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let theme = RoomTheme(room: "salah", dark: false)
        for (name, view) in [("J1-pace-home", AnyView(PaceHome(theme: theme))), ("J2-pace-habit", AnyView(PaceHabit(theme: theme)))] {
            let renderer = ImageRenderer(content: view.frame(width: 430).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name).png"))
        }
    }
}
