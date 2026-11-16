import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 16 Nov: habits take the prayer room's place and identity).
// Synthetic data; renders two PNGs for the owner's review. Not wired into the app.

private struct PreviewHabit: Identifiable {
    let id = UUID()
    let name: String
    let value: Double
    let target: Double
    let unit: String      // the habit's own unit, never summed across habits
    var minimum = false
    var share: Double { min(1, value / max(1, target)) }
    var done: Bool { value >= target }
}

private func digitsAr(_ value: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: value)) ?? "\(value)"
}

/// A habit's arch: the prayer horseshoe, its body rising with the day's share; the lattice closes the dome once done.
private struct HabitArch: View {
    let habit: PreviewHabit
    let isNext: Bool
    var height: CGFloat = 92
    var maxWidth: CGFloat = 58
    var pool = true
    @Environment(\.roomTheme) private var theme
    private var gold: Color { theme.color("goldMid") }

    var body: some View {
        VStack(spacing: 0) {
            arch.frame(height: height)
            if pool {
                arch.frame(height: height)
                    .scaleEffect(x: 1, y: -1).scaleEffect(x: 1, y: 0.5, anchor: .top)
                    .opacity(0.28)
                    .overlay { VStack(spacing: 5) { ForEach(0..<8, id: \.self) { _ in Rectangle().fill(theme.background.opacity(0.7)).frame(height: 1) } } }
                    .mask(LinearGradient(colors: [.black, .clear], startPoint: .top, endPoint: .bottom))
                    .frame(height: height * 0.42, alignment: .top).clipped()
            }
        }
    }

    private var arch: some View {
        GeometryReader { g in
            let width = min(g.size.width - 12, maxWidth)
            let rect = CGRect(x: (g.size.width - width) / 2, y: 0, width: width, height: g.size.height)
            let shape = PrayerHorseshoe().path(in: rect)
            let spring = rect.minY + width / 2 * 1.5
            ZStack {
                ForEach([rect.minX - 5, rect.maxX], id: \.self) { x in
                    Rectangle().fill(gold.opacity(0.1)).frame(width: 5, height: rect.height - spring + 6)
                        .position(x: x + 2.5, y: (spring - 6 + rect.height) / 2)
                }
                shape.fill(theme.background)
                // Water level: the day's share of this habit, in its own unit.
                Rectangle().fill(gold.opacity(habit.minimum ? 0.3 : 0.55))
                    .frame(height: rect.height * habit.share)
                    .frame(maxHeight: .infinity, alignment: .bottom)
                    .clipShape(shape)
                PrayerLatticePattern(spacing: 9)
                    .stroke(theme.accent.opacity(habit.done ? 0.55 : 0.4), lineWidth: 1)
                    .mask {
                        if habit.done { shape.fill().mask(alignment: .top) { Rectangle().frame(height: spring + 2) } }
                        else { shape.stroke(lineWidth: 14).mask(alignment: .top) { Rectangle().frame(height: spring) } }
                    }
                    .clipShape(shape)
                if isNext { shape.stroke(theme.accent, style: StrokeStyle(lineWidth: 4, lineJoin: .round)) }
                else if !habit.done { shape.stroke(theme.accent.opacity(0.35), lineWidth: 1) }
                PrayerStar().fill(habit.done ? theme.accent : isNext ? theme.accent.opacity(0.7) : theme.ink.opacity(0.16))
                    .frame(width: 15, height: 15).position(x: rect.midX, y: spring)
            }
        }
    }
}

private struct PeriodTile: View {
    let period: String
    let met: Double
    let due: Double
    let note: String
    var unit = ""
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(period).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            Text("\(digitsAr(met)) من \(digitsAr(due))" + (unit.isEmpty ? "" : " " + unit)).font(PrayerHomeType.cardHead)
            Capsule().fill(theme.line).frame(height: 4)
                .overlay(alignment: .leading) { GeometryReader { g in Capsule().fill(theme.color("goldMid")).frame(width: g.size.width * met / max(1, due)) } }
            Text(note).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).lineLimit(1)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line) }
    }
}

private struct HabitsHomePreview: View {
    let theme: RoomTheme
    private let today: [PreviewHabit] = [
        .init(name: "ورد الأذكار", value: 1, target: 1, unit: "مرة"),
        .init(name: "المشي", value: 3.5, target: 5, unit: "كم"),
        .init(name: "الماء", value: 5, target: 8, unit: "أكواب"),
        .init(name: "القراءة", value: 10, target: 20, unit: "صفحة", minimum: true),
        .init(name: "النوم المبكر", value: 0, target: 1, unit: "مرة"),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 2) {
                Text("الاثنين ١٦ نوفمبر").font(PrayerHomeType.strong)
                Text("٢٥ جمادى الأولى ١٤٤٨").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            HStack(alignment: .firstTextBaseline) {
                Text("العادات").font(PrayerHomeType.hero)
                Spacer()
                Text("بقي لك المشي ١٫٥ كم قبل المغرب").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
            }
            // The riwaq: today's habits as arches over the pool.
            PrayerRiwaq(pool: true) {
                ForEach(Array(today.enumerated()), id: \.element.id) { index, habit in
                    VStack(spacing: 3) {
                        HabitArch(habit: habit, isNext: index == 1)
                        Text(habit.name).font(PrayerHomeType.archName).lineLimit(1).minimumScaleFactor(0.6)
                        Text(habit.done ? "تمّت" : "\(digitsAr(habit.value)) من \(digitsAr(habit.target)) \(habit.unit)")
                            .font(index == 1 ? PrayerHomeType.smallBold : PrayerHomeType.small)
                            .foregroundStyle(index == 1 ? theme.accent : theme.secondaryInk)
                            .lineLimit(1).minimumScaleFactor(0.7)
                    }.frame(maxWidth: .infinity)
                }
            }
            Text("تقدّمك").font(PrayerHomeType.cardHead)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    PeriodTile(period: "اليوم", met: 2, due: 5, note: "عادتان تمّتا")
                    PeriodTile(period: "الأسبوع", met: 1, due: 3, note: "بقي يومان")
                }
                GridRow {
                    PeriodTile(period: "الشهر", met: 2, due: 4, note: "حتى ٣٠ نوفمبر")
                    PeriodTile(period: "السنة", met: 0, due: 1, note: "الصيام: ٤ من ٦ أيام")
                }
            }
            Text("هذا الأسبوع").font(PrayerHomeType.cardHead)
            VStack(spacing: 0) {
                row("زيارة الوالدين", "مرة من مرتين", share: 0.5)
                Divider().overlay(theme.line)
                row("الرياضة", "٣ من ٤ حصص", share: 0.75)
                Divider().overlay(theme.line)
                row("ختمة الأسبوع", "٢ من ٧ أجزاء", share: 0.28)
            }
            .padding(.horizontal, 14).background(theme.surface, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
        }
        .padding(20)
        .foregroundStyle(theme.ink)
        .background(theme.background)
        .environment(\.roomTheme, theme)
    }
    private func row(_ name: String, _ amount: String, share: Double) -> some View {
        HStack(spacing: 12) {
            HabitArch(habit: .init(name: name, value: share, target: 1, unit: ""), isNext: false, height: 34, maxWidth: 24, pool: false)
                .frame(width: 30, height: 34)
            Text(name).font(PrayerHomeType.strong)
            Spacer()
            Text(amount).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }.frame(minHeight: 56)
    }
}

private struct HabitDetailPreview: View {
    let theme: RoomTheme
    private let habit = PreviewHabit(name: "المشي", value: 3.5, target: 5, unit: "كم")
    // November so far: true = met, false = missed, nil = rest or future.
    private let month: [Bool?] = [true, true, false, true, true, true, nil, true, true, true, true, false, true, true, true, true, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil, nil]
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .bottom, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("المشي").font(PrayerHomeType.hero)
                    Text("٣٫٥ من ٥ كم اليوم").font(PrayerHomeType.cardHead)
                    Text("بقي ١٫٥ كم؛ المغرب بعد ساعتين").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                    Text("سلسلتك ٩ أيام").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
                Spacer()
                HabitArch(habit: habit, isNext: true, height: 150, maxWidth: 96).frame(width: 120)
            }
            .padding(18).background(theme.color("goldSoft"), in: .rect(cornerRadius: 22))
            .overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line) }
            HStack(spacing: 10) {
                Text("+١ كم").font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 48).background(theme.accent, in: .capsule).foregroundStyle(theme.background)
                Text("سجّل مقدارًا").font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 48).background(theme.surface, in: .capsule)
                    .overlay { Capsule().stroke(theme.line) }
            }
            Text("بالكيلومتر").font(PrayerHomeType.cardHead)
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    PeriodTile(period: "اليوم", met: 3.5, due: 5, note: "بقي ١٫٥", unit: "كم")
                    PeriodTile(period: "الأسبوع", met: 18, due: 35, note: "٤ أيام من ٧", unit: "كم")
                }
                GridRow {
                    PeriodTile(period: "نوفمبر", met: 62, due: 150, note: "١٣ يومًا من ١٦", unit: "كم")
                    PeriodTile(period: "٢٠٢٦", met: 1180, due: 1825, note: "أطول سلسلة ٢١ يومًا", unit: "كم")
                }
            }
            Text("نوفمبر").font(PrayerHomeType.cardHead)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 7), spacing: 8) {
                ForEach(Array(month.enumerated()), id: \.offset) { index, day in
                    VStack(spacing: 2) {
                        PrayerStar()
                            .fill(day == true ? theme.accent : theme.background)
                            .overlay { PrayerStar().stroke(day == false ? theme.color("missed") : theme.accent.opacity(day == nil ? 0.18 : 0.6), lineWidth: 1) }
                            .frame(width: 18, height: 18)
                        Text(digitsAr(Double(index + 1))).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                    }
                }
            }
            .padding(14).background(theme.surface, in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
            HStack(spacing: 10) {
                stat("الالتزام", "٨٧٪")
                stat("متوسط يومك", "٤٫٤ كم")
                stat("أفضل يوم", "٩ كم")
            }
        }
        .padding(20)
        .foregroundStyle(theme.ink)
        .background(theme.background)
        .environment(\.roomTheme, theme)
    }
    private func stat(_ title: String, _ value: String) -> some View {
        VStack(spacing: 4) {
            Text(value).font(PrayerHomeType.cardHead)
            Text(title).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }.frame(maxWidth: .infinity, minHeight: 72).background(theme.surface, in: .rect(cornerRadius: 16))
            .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line) }
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for dark in [false, true] {
            let theme = RoomTheme(room: "salah", dark: dark)
            let views: [(String, AnyView)] = [("home", AnyView(HabitsHomePreview(theme: theme))), ("detail", AnyView(HabitDetailPreview(theme: theme)))]
            for (name, view) in views {
                let renderer = ImageRenderer(content: view.frame(width: 430).environment(\.layoutDirection, .rightToLeft)
                    .environment(\.colorScheme, dark ? .dark : .light))
                renderer.scale = 2
                let image = try XCTUnwrap(renderer.uiImage)
                try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name)-\(dark ? "D" : "L").png"))
            }
        }
    }
}
