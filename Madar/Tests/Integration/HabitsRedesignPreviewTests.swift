import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 17 Nov). Round 9, after «شف التطبيقات وأبي شي جميل وخورافي»; the owner kept the colours.
// Lessons taken (not copied): Streaks — one big, bold token per habit you read at a glance; Apple Fitness — a month of
// small rings; Gentler Streak — kind, never punishing. Madar's own twist: «سماء يومك», the day's real light from the
// prayer-time engine (dawn to night) with each habit placed at the time it will ask you, and a sun at «now».
// Generic: tokens depend only on measure × frequency. Synthetic data; not wired into the app.

private func ar(_ v: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

private struct H: Identifiable {
    let id = UUID()
    let name: String
    let symbol: String
    let share: Double
    let amount: String
    let askAt: Double     // fraction of the day from Fajr (0) to Isha (1)
    let askLabel: String
}

private let today: [H] = [
    .init(name: "الأذكار", symbol: "sun.horizon", share: 1, amount: "تمّت", askAt: 0.08, askLabel: "٥:٣٠ ص"),
    .init(name: "القراءة", symbol: "book", share: 1, amount: "٢٠ صفحة", askAt: 0.3, askLabel: "٩:٠٠ ص"),
    .init(name: "الماء", symbol: "drop", share: 0.62, amount: "٥ من ٨ أكواب", askAt: 0.55, askLabel: "٢:٠٠ م"),
    .init(name: "المشي", symbol: "figure.walk", share: 0.7, amount: "٣٫٥ من ٥ كم", askAt: 0.7, askLabel: "٦:٠٠ م"),
    .init(name: "الرياضة", symbol: "dumbbell", share: 0.66, amount: "٢ من ٣ هذا الأسبوع", askAt: 0.83, askLabel: "٨:٠٠ م"),
    .init(name: "النوم المبكر", symbol: "moon.stars", share: 0, amount: "قبل ١١ م", askAt: 0.95, askLabel: "١٠:٣٠ م"),
]

/// The day's sky: real light from Fajr (right) to Isha (left), a sun-path arc, habits at their ask times.
private struct DaySky: View {
    let now: Double
    @Environment(\.roomTheme) private var theme
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, h = g.size.height
            let base = h - 48, radiusX = w / 2 - 34, radiusY = h - 96
            let point = { (t: Double) -> CGPoint in
                let a = Double.pi * t          // 0 at right (Fajr), π at left (Isha)
                return CGPoint(x: w / 2 + cos(a) * radiusX, y: base - sin(a) * radiusY)
            }
            ZStack {
                LinearGradient(stops: [
                    .init(color: Color(red: 0.96, green: 0.86, blue: 0.80), location: 0),
                    .init(color: Color(red: 0.98, green: 0.93, blue: 0.82), location: 0.35),
                    .init(color: Color(red: 0.93, green: 0.80, blue: 0.62), location: 0.75),
                    .init(color: Color(red: 0.30, green: 0.22, blue: 0.17), location: 1),
                ], startPoint: .trailing, endPoint: .leading)
                // The arc the sun travels.
                Path { p in
                    p.move(to: point(0))
                    for i in 1...60 { p.addLine(to: point(Double(i) / 60)) }
                }.stroke(.white.opacity(0.7), style: StrokeStyle(lineWidth: 1.2, dash: [3, 4]))
                // Horizon with a soft reflection.
                Rectangle().fill(.white.opacity(0.55)).frame(height: 1).position(x: w / 2, y: base)
                LinearGradient(colors: [.white.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom)
                    .frame(height: 34).position(x: w / 2, y: base + 17)
                // Now: the sun.
                let s = point(now)
                Circle().fill(Color(red: 1, green: 0.85, blue: 0.5).opacity(0.55)).frame(width: 70, height: 70).blur(radius: 14).position(s)
                Circle().fill(Color(red: 1, green: 0.88, blue: 0.6)).frame(width: 20, height: 20).position(s)
                ForEach(today) { item in
                    let p = point(item.askAt)
                    ZStack {
                        Circle().fill(item.share >= 1 ? theme.accent : theme.background.opacity(0.92))
                        Circle().trim(from: 0, to: item.share).stroke(theme.accent, style: StrokeStyle(lineWidth: 2.5, lineCap: .round)).rotationEffect(.degrees(-90))
                        Image(systemName: item.symbol).font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(item.share >= 1 ? theme.background : theme.accent)
                    }
                    .frame(width: 34, height: 34).position(p)
                    Text(item.askLabel).font(PrayerHomeType.small).foregroundStyle(item.askAt > 0.88 ? .white.opacity(0.9) : theme.ink.opacity(0.7))
                        .position(x: p.x, y: item.askAt > 0.65 ? p.y - 28 : p.y + 30)
                }
                HStack { Text("العشاء"); Spacer(); Text("الفجر") }
                    .font(PrayerHomeType.smallBold).foregroundStyle(.white.opacity(0.9))
                    .padding(.horizontal, 16).position(x: w / 2, y: h - 18)
                    .environment(\.layoutDirection, .leftToRight)
            }
            .environment(\.layoutDirection, .leftToRight)
        }
        .frame(height: 290)
        .clipShape(.rect(cornerRadius: 28))
    }
}

/// One bold token per habit: a ring that fills with the period's share, the symbol inside, the amount in its unit.
private struct Token: View {
    let h: H
    var size: CGFloat = 104
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                Circle().fill(h.share >= 1 ? theme.accent : theme.surface)
                Circle().stroke(theme.line, lineWidth: 7).padding(5)
                Circle().trim(from: 0, to: h.share).stroke(h.share >= 1 ? theme.background.opacity(0.35) : theme.accent, style: StrokeStyle(lineWidth: 7, lineCap: .round))
                    .rotationEffect(.degrees(-90)).padding(5)
                Image(systemName: h.symbol).font(.system(size: size * 0.28, weight: .medium))
                    .foregroundStyle(h.share >= 1 ? theme.background : theme.accent)
            }
            .frame(width: size, height: size)
            VStack(spacing: 2) {
                Text(h.name).font(PrayerHomeType.strong)
                Text(h.amount).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(1).minimumScaleFactor(0.8)
            }
        }
    }
}

/// A month of small rings: each day's share of habits met.
private struct MonthRings: View {
    var dim: CGFloat = 26
    let values: [Double?]
    @Environment(\.roomTheme) private var theme
    var body: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 8) {
            ForEach(["س", "ح", "ن", "ث", "ر", "خ", "ج"], id: \.self) { Text($0).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk) }
            Color.clear.frame(width: dim, height: dim) // 1 Nov 2026 is a Sunday
            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                ZStack {
                    Circle().stroke(theme.line, lineWidth: 3)
                    if let v { Circle().trim(from: 0, to: v).stroke(theme.accent.opacity(v >= 1 ? 1 : 0.7), style: StrokeStyle(lineWidth: 3, lineCap: .round)).rotationEffect(.degrees(-90)) }
                    if v == 1 { Circle().fill(theme.accent.opacity(0.18)).padding(4) }
                }
                .frame(width: dim, height: dim)
                .overlay { if i == 15 { Circle().stroke(theme.accent, lineWidth: 1).padding(-4) } }
            }
        }
    }
}

private let november: [Double?] = [1, 0.8, 1, 1, 0.5, 1, 0.8, 1, 1, 1, 0.66, 1, 0.4, 1, 1, 0.66] + Array(repeating: nil, count: 14)

// MARK: Room home

private struct SkyHome: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("العادات").font(PrayerHomeType.hero)
                    Text("الاثنين ١٦ نوفمبر، ٢٥ جمادى الأولى").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
                Spacer()
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.background)
                    .frame(width: 44, height: 44).background(theme.accent, in: .circle)
            }
            DaySky(now: 0.62)
            Text("بقي سؤالان اليوم: المشي ٦:٠٠ م والنوم المبكر ١٠:٣٠ م.").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())], spacing: 22) {
                ForEach(today) { Token(h: $0, size: 92) }
            }
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    Text("نوفمبر").font(PrayerHomeType.cardHead)
                    Spacer()
                    Text("٨٧٪، أفضل من أكتوبر").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                }
                MonthRings(values: november)
            }
            .padding(18).background(theme.surface, in: .rect(cornerRadius: 24))
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
}

// MARK: Habit page

private struct SkyHabit: View {
    let theme: RoomTheme
    var body: some View {
        let walk = today[3]
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 18) {
                Token(h: .init(name: "", symbol: walk.symbol, share: walk.share, amount: "", askAt: 0, askLabel: ""), size: 120)
                    .frame(height: 130).padding(.top, 6)
                VStack(alignment: .leading, spacing: 4) {
                    Text(walk.name).font(PrayerHomeType.hero)
                    Text("٣٫٥ من ٥ كم اليوم").font(PrayerHomeType.cardHead)
                    Text("يسألك ٦:٠٠ م، وآخر تذكير ١٠:٠٠ م").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
            HStack(spacing: 10) {
                stat("١٢ يومًا", "سلسلتك"); stat("٩٨ كم", "نوفمبر"); stat("٨٧٪", "التزامك")
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("نوفمبر").font(PrayerHomeType.cardHead)
                MonthRings(dim: 30, values: [1, 1, 0, 1, 1, 0.8, 0.4, 1, 1, 1, 1, 0, 1, 1, 1, 0.7] + Array(repeating: nil, count: 14))
            }
            .padding(18).background(theme.surface, in: .rect(cornerRadius: 24))
            VStack(alignment: .leading, spacing: 12) {
                Text("ما لاحظه مدار").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                Text("تمشي غالبًا بين ٥ و٦ م، فسؤال ٦:٠٠ م في وقته.").font(PrayerHomeType.body)
                Text("الجمعة أضعف أيامك: مشيت فيها مرتين من خمس.").font(PrayerHomeType.body)
                Text("بهذه الوتيرة تختم نوفمبر عند ١٦٨ كم من ١٥٠.").font(PrayerHomeType.body)
            }
            .padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 24))
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) { Text(v).font(PrayerHomeType.cardHead); Text(t).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk) }
            .padding(12).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 16))
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let theme = RoomTheme(room: "salah", dark: false)
        for (name, view) in [("K1-sky-home", AnyView(SkyHome(theme: theme))), ("K2-sky-habit", AnyView(SkyHabit(theme: theme)))] {
            let renderer = ImageRenderer(content: view.frame(width: 430).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name).png"))
        }
    }
}
