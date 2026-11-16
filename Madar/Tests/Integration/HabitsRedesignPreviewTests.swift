import XCTest
import SwiftUI
import MadarCore
import MadarDesign
@testable import Madar

// Design preview only (owner 16 Nov). Round 5. Owner: «تصميم هادئ ذكي جميل واضح» and
// «ابيها طريقة تستطيع أي عادة تكون فِت معها»: nothing is drawn for a particular habit.
// Every row comes from one rule over the engine's own fields (measure, frequency, value, target, unit),
// so any habit the user creates fits. Synthetic data; not wired into the app.

private struct AnyHabit: Identifiable {
    let id = UUID()
    let name: String
    let measure: HabitMeasure
    let frequency: HabitFrequency
    let value: Double
    let target: Double
    var unit: String? = nil
    var left = ""              // time left in the period, from the period's end date
    var share: Double { min(1, value / max(1, target)) }
    var done: Bool { value >= target }
}

private func ar(_ v: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

/// The one rule: what a row says, how its line is drawn and what its button does, from the habit's kind alone.
private enum HabitLine {
    static func amount(_ h: AnyHabit) -> String {
        if h.done { return "تمّت" }
        switch h.measure {
        case .once: return "لم تتمّ بعد"
        case .count: return "\(ar(h.value)) من \(ar(h.target)) \(h.unit ?? "مرات")"
        case .duration: return "\(ar(h.value)) من \(ar(h.target)) \(h.unit ?? "دقيقة")"
        case .health: return "\(ar(h.value)) من \(ar(h.target)) \(h.unit ?? "")"
        }
    }
    /// Discrete targets of ten or fewer show their steps; amounts and durations show one continuous line.
    static func steps(_ h: AnyHabit) -> Int? {
        switch h.measure { case .once: 1; case .count: h.target <= 10 ? Int(h.target) : nil; default: nil }
    }
    static func action(_ h: AnyHabit) -> String {
        switch h.measure {
        case .once: "تمّت"
        case .count: "+١"
        case .duration: "+١٠ دقائق"
        case .health: "سجّل"
        }
    }
}

private struct StepLine: View {
    let h: AnyHabit
    @Environment(\.roomTheme) private var theme
    var body: some View {
        let fill = theme.accent.opacity(0.75), empty = theme.line.opacity(0.7)
        if let n = HabitLine.steps(h) {
            HStack(spacing: 4) { ForEach(0..<n, id: \.self) { i in Capsule().fill(Double(i) < h.value ? fill : empty).frame(height: 3) } }
        } else {
            GeometryReader { g in
                HStack(spacing: 0) { Capsule().fill(fill).frame(width: g.size.width * h.share); Capsule().fill(empty) }
            }.frame(height: 3)
        }
    }
}

private struct Row: View {
    let h: AnyHabit
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(h.name).font(PrayerHomeType.strong).foregroundStyle(h.done ? theme.secondaryInk : theme.ink)
                    if !h.left.isEmpty && !h.done { Text(h.left).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk) }
                }
                Spacer()
                Text(HabitLine.amount(h)).font(PrayerHomeType.body).foregroundStyle(h.done ? theme.accent : theme.secondaryInk)
                if !h.done {
                    Text(HabitLine.action(h)).font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                        .padding(.horizontal, 12).frame(minHeight: 34).overlay { Capsule().stroke(theme.line) }
                }
            }
            StepLine(h: h)
        }
    }
}

private struct Group: View {
    let title: String
    let rows: [AnyHabit]
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text(title).font(PrayerHomeType.cardHead)
                Spacer()
                Text("\(ar(Double(rows.filter(\.done).count))) من \(ar(Double(rows.count)))").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            ForEach(rows) { Row(h: $0) }
        }
    }
}

private struct UniversalHome: View {
    let theme: RoomTheme
    // Every measure and every frequency the engine knows, named by kind, so the preview proves the rule, not a sample.
    private let all: [AnyHabit] = [
        .init(name: "عادة مرة في اليوم", measure: .once, frequency: .daily, value: 1, target: 1),
        .init(name: "عادة بالعدد", measure: .count, frequency: .daily, value: 2, target: 3, unit: "مرات"),
        .init(name: "عادة بالمدة", measure: .duration, frequency: .daily, value: 20, target: 30, unit: "دقيقة"),
        .init(name: "عادة بمقدار ووحدة", measure: .health, frequency: .daily, value: 3.5, target: 5, unit: "كم"),
        .init(name: "عادة أسبوعية", measure: .count, frequency: .weekly, value: 1, target: 3, unit: "مرات", left: "بقي ٤ أيام"),
        .init(name: "عادة شهرية", measure: .once, frequency: .monthly, value: 0, target: 1, left: "حتى ٣٠ نوفمبر"),
        .init(name: "عادة كل ٣ أيام", measure: .once, frequency: .interval, value: 0, target: 1, left: "موعدها غدًا"),
        .init(name: "عادة سنوية", measure: .count, frequency: .yearly, value: 4, target: 6, unit: "أيام", left: "حتى ٣١ ديسمبر"),
    ]
    var body: some View {
        let daily = all.filter { $0.frequency == .daily }
        // The card picks, by rule, the due habit closest to done. No habit is special.
        let next = daily.filter { !$0.done }.max { $0.share < $1.share }!
        VStack(alignment: .leading, spacing: 26) {
            VStack(alignment: .leading, spacing: 2) {
                Text("الاثنين ١٦ نوفمبر").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                Text("٢٥ جمادى الأولى ١٤٤٨").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk.opacity(0.8))
            }
            VStack(alignment: .leading, spacing: 14) {
                Text("أتممت \(ar(Double(daily.filter(\.done).count))) من \(ar(Double(daily.count))) اليوم.")
                    .font(.custom("thmanyahserifdisplay-Bold", size: 30))
                HStack(spacing: 6) { ForEach(daily) { h in Capsule().fill(h.done ? theme.accent.opacity(0.75) : theme.line.opacity(0.7)).frame(height: 4) } }
            }
            VStack(alignment: .leading, spacing: 12) {
                Text("الأقرب للتمام").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                HStack(alignment: .firstTextBaseline) {
                    Text(next.name).font(PrayerHomeType.cardHead)
                    Spacer()
                    Text("بقي \(ar(next.target - next.value)) \(next.unit ?? "")").font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
                StepLine(h: next)
                Text(HabitLine.action(next)).font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 46)
                    .background(theme.accent, in: .capsule).foregroundStyle(theme.background)
            }
            .padding(18).background(theme.surface, in: .rect(cornerRadius: 22))
            Group(title: "اليوم", rows: daily)
            Rectangle().fill(theme.line).frame(height: 1)
            Group(title: "مواعيد أبعد", rows: all.filter { $0.frequency != .daily })
        }
        .padding(.horizontal, 24).padding(.vertical, 28)
        .foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        for dark in [false, true] {
            let renderer = ImageRenderer(content: UniversalHome(theme: RoomTheme(room: "salah", dark: dark)).frame(width: 430).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-G-universal-\(dark ? "D" : "L").png"))
        }
    }
}
