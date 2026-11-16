import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 16 Nov). Round 7: «صمّم كل الواجهات بشكل أوضح وأذكى».
// Every habit screen: room home, habit page, new habit, and the outside surfaces (notification, lobby).
// Clear = one big fact per block, plain sentences, the unit always shown. Smart = each block answers a question
// the logs already answer (when do I usually do it, which day slips, am I better than last month).
// Layouts depend only on measure × frequency, never on a particular habit. Synthetic data; not wired into the app.

private func ar(_ v: Double) -> String {
    let f = NumberFormatter(); f.locale = Locale(identifier: "ar_SA"); f.maximumFractionDigits = 1
    return f.string(from: NSNumber(value: v)) ?? "\(v)"
}

private struct Box<C: View>: View {
    var pad: CGFloat = 16
    @ViewBuilder let content: () -> C
    @Environment(\.roomTheme) private var theme
    var body: some View {
        content().padding(pad).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 20))
    }
}

/// Twelve weeks as small squares: the shared «rhythm» mark for every habit, whatever its kind.
private struct Rhythm: View {
    let seed: Int
    var weeks = 12
    var size: CGFloat = 9
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(spacing: 3) {
            ForEach(0..<weeks, id: \.self) { w in
                VStack(spacing: 3) {
                    ForEach(0..<7, id: \.self) { d in
                        let v = (w * 7 + d + seed * 5) % 9
                        RoundedRectangle(cornerRadius: 2)
                            .fill(w == weeks - 1 && d > 1 ? theme.line.opacity(0.35) : v < 2 ? theme.line.opacity(0.7) : theme.accent.opacity(v < 4 ? 0.35 : v < 7 ? 0.6 : 0.9))
                            .frame(width: size, height: size)
                    }
                }
            }
        }
    }
}

// MARK: 1. Room home — what changed, then each habit as one clear card.

private struct HomeScreen: View {
    let theme: RoomTheme
    private let cards: [(String, String, String, String, Int)] = [
        ("المشي", "كل يوم · ٥ كم", "٦٢ كم", "في نوفمبر، أكثر من أكتوبر بـ١٢", 1),
        ("ورد الأذكار", "كل يوم · مرة", "١٤ من ١٦", "يومًا في نوفمبر", 2),
        ("الرياضة", "٣ مرات أسبوعيًا", "٢ من ٣", "هذا الأسبوع، بقي ٤ أيام", 3),
        ("زيارة الأهل", "مرة كل شهر", "تمّت", "في ٣ نوفمبر", 4),
    ]
    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .firstTextBaseline) {
                Text("العادات").font(PrayerHomeType.hero)
                Spacer()
                Image(systemName: "plus").font(.system(size: 18, weight: .semibold)).foregroundStyle(theme.background)
                    .frame(width: 44, height: 44).background(theme.accent, in: .circle)
            }
            // The one sentence worth reading today.
            Box {
                VStack(alignment: .leading, spacing: 8) {
                    Text("نوفمبر أفضل شهر لك هذا العام").font(PrayerHomeType.cardHead)
                    Text("التزمت ٨٧٪ حتى الآن مقابل ٧٤٪ في أكتوبر. الجمعة وحدها تنقص؛ أغلب ما يفوتك يقع فيها.")
                        .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
            }
            ForEach(cards, id: \.0) { name, rule, big, sub, seed in
                Box {
                    HStack(alignment: .center, spacing: 14) {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(name).font(PrayerHomeType.strong)
                            Text(rule.replacingOccurrences(of: " · ", with: "، ")).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                            Text(big).font(PrayerHomeType.number).padding(.top, 6)
                            Text(sub).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }
                        Spacer(minLength: 0)
                        Rhythm(seed: seed, weeks: 10, size: 8)
                    }
                }
            }
            Text("آخر ١٠ أسابيع: المربع الداكن يوم أتممت فيه العادة.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
}

// MARK: 2. Habit page — the answer to «how am I doing», «when do I do it», «what is my pattern».

private struct HabitScreen: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 4) {
                Text("المشي").font(PrayerHomeType.hero)
                Text("٥ كم كل يوم. يسألك ٦:٠٠ م، وآخر تذكير ١٠:٠٠ م.").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            }
            HStack(spacing: 10) {
                big("٦٢ كم", "نوفمبر"); big("١٢ يومًا", "سلسلتك"); big("٨٧٪", "التزامك")
            }
            Box {
                VStack(alignment: .leading, spacing: 12) {
                    Text("سنتك").font(PrayerHomeType.cardHead)
                    Rhythm(seed: 1, weeks: 26, size: 10)
                    Text("أطول سلسلة ٢١ يومًا في سبتمبر. مجموع السنة ١١٨٠ كم.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
            }
            Box {
                VStack(alignment: .leading, spacing: 12) {
                    Text("متى تمشي عادة؟").font(PrayerHomeType.cardHead)
                    HStack(alignment: .bottom, spacing: 4) {
                        ForEach(Array([0, 0, 1, 2, 1, 0, 0, 1, 3, 9, 6, 2, 1].enumerated()), id: \.offset) { i, v in
                            RoundedRectangle(cornerRadius: 3).fill(theme.accent.opacity(v == 9 ? 0.9 : 0.35)).frame(height: max(3, CGFloat(v) * 8)).frame(maxWidth: .infinity)
                        }
                    }.frame(height: 76, alignment: .bottom)
                    HStack { Text("الفجر"); Spacer(); Text("الظهر"); Spacer(); Text("العصر"); Spacer(); Text("العشاء") }
                        .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                    Text("أغلب مشيك بين ٥ و٦ م، فسؤال ٦:٠٠ م في وقته.").font(PrayerHomeType.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            Box {
                VStack(alignment: .leading, spacing: 12) {
                    Text("أيام الأسبوع").font(PrayerHomeType.cardHead)
                    HStack(spacing: 8) {
                        ForEach(Array(zip(["س", "ح", "ن", "ث", "ر", "خ", "ج"], [0.9, 0.95, 0.9, 0.85, 0.9, 0.8, 0.4])), id: \.0) { d, v in
                            VStack(spacing: 6) {
                                Text(ar((v * 100).rounded())).font(PrayerHomeType.smallBold).foregroundStyle(v < 0.5 ? theme.color("missed") : theme.ink)
                                Text(d).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                            }.frame(maxWidth: .infinity)
                        }
                    }
                    Text("الجمعة تنقص كثيرًا. هل تجعل هدفها ٣ كم؟").font(PrayerHomeType.body)
                }
            }
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func big(_ v: String, _ t: String) -> some View {
        Box(pad: 12) {
            VStack(alignment: .leading, spacing: 2) { Text(v).font(PrayerHomeType.cardHead); Text(t).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk) }
        }
    }
}

// MARK: 3. New habit — one sentence you complete; every blank is a choice.

private struct NewHabitScreen: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("عادة جديدة").font(PrayerHomeType.hero)
            VStack(alignment: .leading, spacing: 14) {
                line(["أريد أن", "[أمشي]"])
                line(["مقدار", "[٥]", "[كم]"])
                line(["", "[كل يوم]"])
                line(["اسألني", "[٦:٠٠ م]"])
                line(["وذكّرني آخر مرة", "[١٠:٠٠ م]"])
            }
            Box {
                VStack(alignment: .leading, spacing: 6) {
                    Text("هكذا ستصلك").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                    Text("«مشيت اليوم؟» الساعة ٦:٠٠ م، بأزرار: ٥ كم، مقدار آخر، ليس الآن.").font(PrayerHomeType.body).fixedSize(horizontal: false, vertical: true)
                }
            }
            Text("أمثلة سريعة").font(PrayerHomeType.cardHead)
            FlowChips(items: ["أقرأ ١٠ صفحات يوميًا", "أصوم الاثنين والخميس", "أزور أهلي كل شهر", "أنام قبل ١١"])
            Text("أنشئ العادة").font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 50)
                .background(theme.accent, in: .capsule).foregroundStyle(theme.background)
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func line(_ parts: [String]) -> some View {
        HStack(spacing: 8) {
            ForEach(parts.filter { !$0.isEmpty }, id: \.self) { p in
                if p.hasPrefix("[") {
                    Text(p.dropFirst().dropLast()).font(.custom("thmanyahserifdisplay-Bold", size: 28)).foregroundStyle(theme.accent)
                        .padding(.horizontal, 10).padding(.vertical, 2)
                        .overlay(alignment: .bottom) { Rectangle().fill(theme.accent.opacity(0.4)).frame(height: 2) }
                } else {
                    Text(p).font(.custom("thmanyahserifdisplay-Bold", size: 28))
                }
            }
        }
    }
}

private struct FlowChips: View {
    let items: [String]
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(stride(from: 0, to: items.count, by: 2)), id: \.self) { i in
                HStack(spacing: 8) {
                    ForEach(items[i..<min(i + 2, items.count)], id: \.self) { t in
                        Text(t).font(PrayerHomeType.small).padding(.horizontal, 12).frame(minHeight: 36).overlay { Capsule().stroke(theme.line) }
                    }
                }
            }
        }
    }
}

// MARK: 4. Outside — the notification and the lobby line.

private struct OutsideScreen: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("من خارج القسم").font(PrayerHomeType.hero)
            Text("الإشعار، ٦:٠٠ م").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
            Box {
                VStack(alignment: .leading, spacing: 10) {
                    HStack { Text("مدار").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk); Spacer(); Text("الآن").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk) }
                    Text("مشيت اليوم؟").font(PrayerHomeType.cardHead)
                    Text("سلسلتك ١٢ يومًا.").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    HStack(spacing: 8) {
                        ForEach(["٥ كم", "مقدار آخر", "ليس الآن"], id: \.self) { a in
                            Text(a).font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 44)
                                .background(a == "٥ كم" ? theme.accent : theme.background, in: .rect(cornerRadius: 12))
                                .foregroundStyle(a == "٥ كم" ? theme.background : theme.ink)
                        }
                    }
                }
            }
            Text("البهو: سطر واحد لما بقي").font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
            Box {
                VStack(alignment: .leading, spacing: 12) {
                    Text("بقي اليوم: الرياضة والقراءة").font(PrayerHomeType.strong)
                    HStack(spacing: 8) {
                        chip("الرياضة: تمّت"); chip("القراءة: ١٠ صفحات")
                    }
                }
            }
        }
        .padding(22).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func chip(_ t: String) -> some View {
        Text(t).font(PrayerHomeType.smallBold).foregroundStyle(theme.accent).padding(.horizontal, 12).frame(minHeight: 40)
            .background(theme.background, in: .capsule)
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let theme = RoomTheme(room: "salah", dark: false)
        let screens: [(String, AnyView)] = [
            ("I1-home", AnyView(HomeScreen(theme: theme))), ("I2-habit", AnyView(HabitScreen(theme: theme))),
            ("I3-new", AnyView(NewHabitScreen(theme: theme))), ("I4-outside", AnyView(OutsideScreen(theme: theme))),
        ]
        for (name, view) in screens {
            let renderer = ImageRenderer(content: view.frame(width: 430).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name).png"))
        }
    }
}
