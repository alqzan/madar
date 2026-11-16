import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 16 Nov). Round 2: the owner rejected arches for habits.
// Two directions in the prayer palette (paper, gold, soft reflection), synthetic data. Not wired into the app.

private struct PH: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let target: Double
    let unit: String
    var share: Double { min(1, value / max(1, target)) }
    var done: Bool { value >= target }
}

private func ar(_ value: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}

private let todayHabits: [PH] = [
    .init(name: "ورد الأذكار", value: 1, target: 1, unit: "مرة"),
    .init(name: "المشي", value: 3.5, target: 5, unit: "كم"),
    .init(name: "الماء", value: 5, target: 8, unit: "أكواب"),
    .init(name: "القراءة", value: 10, target: 20, unit: "صفحة"),
    .init(name: "النوم المبكر", value: 0, target: 1, unit: "مرة"),
]
/// Share of the day's habits met, last 14 days (oldest first). Synthetic.
private let fortnight: [Double] = [1, 0.8, 0.6, 1, 1, 0.4, 0.8, 1, 0.6, 1, 0.8, 1, 0.8, 0.4]

private struct Bead: View {
    let fill: Double
    let size: CGFloat
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ZStack {
            Circle().fill(theme.surface)
            Circle().fill(theme.color("goldMid")).mask(alignment: .bottom) {
                GeometryReader { g in Rectangle().frame(height: g.size.height * fill).frame(maxHeight: .infinity, alignment: .bottom) }
            }
            Circle().fill(LinearGradient(colors: [.white.opacity(fill > 0 ? 0.45 : 0.2), .clear], startPoint: .topLeading, endPoint: .center))
            Circle().stroke(theme.accent.opacity(fill > 0 ? 0.7 : 0.3), lineWidth: 1)
        }.frame(width: size, height: size)
    }
}

private struct Card<C: View>: View {
    @ViewBuilder let content: () -> C
    @Environment(\.roomTheme) private var theme
    var body: some View {
        content().padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line) }
    }
}

private struct Header: View {
    let line: String
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("الاثنين ١٦ نوفمبر").font(PrayerHomeType.strong)
            Text("٢٥ جمادى الأولى ١٤٤٨").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            Text("العادات").font(PrayerHomeType.hero).padding(.top, 6)
            Text(line).font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
        }
    }
}

/// Seven days of the week as soft gold columns: the share of habits met each day.
private struct WeekBars: View {
    @Environment(\.roomTheme) private var theme
    private let days = ["س", "ح", "ن", "ث", "ر", "خ", "ج"]
    var body: some View {
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(0..<7, id: \.self) { i in
                let share = fortnight[7 + i]
                VStack(spacing: 6) {
                    Capsule().fill(theme.line.opacity(0.6)).frame(width: 18, height: 70)
                        .overlay(alignment: .bottom) { Capsule().fill(theme.color("goldMid").opacity(i == 6 ? 1 : 0.7)).frame(width: 18, height: 70 * share) }
                    Text(days[i]).font(PrayerHomeType.small).foregroundStyle(i == 6 ? theme.accent : theme.secondaryInk)
                }.frame(maxWidth: .infinity)
            }
        }
    }
}

private struct Stat: View {
    let value: String
    let title: String
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(PrayerHomeType.number)
            Text(title).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }.frame(maxWidth: .infinity, alignment: .leading)
    }
}

// MARK: Direction A — المسبحة: one bead per unit you set, so the amount is seen, not read.

private struct TasbihHome: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(line: "التالي: المشي، بقي ١٫٥ كم قبل المغرب")
            Card {
                HStack(spacing: 18) {
                    ZStack {
                        Circle().stroke(theme.color("goldMid").opacity(0.5), lineWidth: 1.2).frame(width: 128, height: 128)
                        ForEach(Array(todayHabits.enumerated()), id: \.offset) { i, h in
                            let a = (Double(i) / Double(todayHabits.count)) * 2 * .pi - .pi / 2
                            Bead(fill: h.share, size: 26).offset(x: cos(a) * 64, y: sin(a) * 64)
                        }
                        VStack(spacing: 0) {
                            Text("٢ من ٥").font(PrayerHomeType.cardHead)
                            Text("عادات اليوم").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }
                    }.frame(width: 160, height: 160)
                    VStack(alignment: .leading, spacing: 10) {
                        Stat(value: "٩ أيام", title: "سلسلتك الجارية")
                        Stat(value: "٨٢٪", title: "التزامك في نوفمبر")
                    }
                }
            }
            Text("اليوم").font(PrayerHomeType.cardHead)
            Card {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(todayHabits) { h in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Text(h.name).font(PrayerHomeType.strong)
                                Spacer()
                                Text(h.done ? "تمّت" : "\(ar(h.value)) من \(ar(h.target)) \(h.unit)")
                                    .font(PrayerHomeType.small).foregroundStyle(h.done ? theme.accent : theme.secondaryInk)
                            }
                            let count = Int(min(h.target, 10))
                            let per = h.target / Double(count)
                            ZStack(alignment: .leading) {
                                Rectangle().fill(theme.color("goldMid").opacity(0.45)).frame(height: 1)
                                HStack(spacing: 6) {
                                    ForEach(0..<count, id: \.self) { k in
                                        Bead(fill: max(0, min(1, (h.value - Double(k) * per) / per)), size: count > 6 ? 18 : 22)
                                    }
                                }
                            }
                        }
                    }
                }
            }
            Text("أسبوعك").font(PrayerHomeType.cardHead)
            Card { WeekBars() }
        }
        .padding(20).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
}

// MARK: Direction B — النسيج: each habit is a thread; every day weaves one knot, so a fortnight reads as a pattern.

private struct LoomHome: View {
    let theme: RoomTheme
    private func knots(_ h: PH, _ seed: Int) -> [Double] {
        (0..<14).map { d in d == 13 ? h.share : ((d * 7 + seed * 3) % 5 == 0 ? 0 : (d + seed) % 4 == 0 ? 0.5 : 1) }
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Header(line: "نسيجك متصل منذ ٩ أيام")
            Card {
                VStack(alignment: .leading, spacing: 12) {
                    HStack {
                        Text("آخر أسبوعين").font(PrayerHomeType.cardHead)
                        Spacer()
                        Text("اليوم ←").font(PrayerHomeType.small).foregroundStyle(theme.accent)
                    }
                    ForEach(Array(todayHabits.enumerated()), id: \.offset) { i, h in
                        HStack(spacing: 10) {
                            Text(h.name).font(PrayerHomeType.small).frame(width: 78, alignment: .leading).lineLimit(1).minimumScaleFactor(0.7)
                            ZStack {
                                Rectangle().fill(theme.color("goldMid").opacity(0.35)).frame(height: 1)
                                HStack(spacing: 4) {
                                    ForEach(Array(knots(h, i).enumerated()), id: \.offset) { d, v in
                                        Rectangle()
                                            .fill(v == 0 ? theme.background : theme.color("goldMid").opacity(0.3 + 0.7 * v))
                                            .overlay { Rectangle().stroke(d == 13 ? theme.accent : theme.accent.opacity(0.25), lineWidth: d == 13 ? 1.5 : 0.8) }
                                            .frame(width: 11, height: 11).rotationEffect(.degrees(45))
                                            .frame(maxWidth: .infinity)
                                    }
                                }
                            }
                        }
                    }
                    Text("الممتلئ: تمّت؛ النصف: أقلّ القليل؛ الفارغ: فاتت")
                        .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    Card { Stat(value: "٢ من ٥", title: "اليوم") }
                    Card { Stat(value: "١ من ٣", title: "عادات الأسبوع") }
                }
                GridRow {
                    Card { Stat(value: "٨٢٪", title: "التزام نوفمبر") }
                    Card { Stat(value: "٢١ يومًا", title: "أطول سلسلة في ٢٠٢٦") }
                }
            }
            Text("المشي في نوفمبر").font(PrayerHomeType.cardHead)
            Card {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text("٦٢").font(PrayerHomeType.hero)
                        Text("كم من ١٥٠").font(PrayerHomeType.lead).foregroundStyle(theme.secondaryInk)
                    }
                    let km: [Double] = [4, 5, 0, 6, 5, 4.5, 0, 5, 7, 5, 9, 0, 5, 4, 5, 3.5]
                    HStack(alignment: .bottom, spacing: 5) {
                        ForEach(Array(km.enumerated()), id: \.offset) { d, v in
                            VStack(spacing: 1) {
                                Capsule().fill(theme.color("goldMid").opacity(d == km.count - 1 ? 1 : 0.75)).frame(height: max(3, v * 8))
                                Capsule().fill(theme.color("goldMid").opacity(0.18)).frame(height: max(2, v * 3))
                            }.frame(maxWidth: .infinity)
                        }
                    }.frame(height: 110, alignment: .bottom)
                    Text("أفضل يوم ٩ كم، ومتوسط يومك ٤٫٤ كم").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
        }
        .padding(20).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let theme = RoomTheme(room: "salah", dark: false)
        for (name, view) in [("A-tasbih", AnyView(TasbihHome(theme: theme))), ("B-loom", AnyView(LoomHome(theme: theme)))] {
            let renderer = ImageRenderer(content: view.frame(width: 430).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name)-L.png"))
        }
    }
}
