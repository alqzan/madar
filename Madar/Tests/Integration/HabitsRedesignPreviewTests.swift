import XCTest
import SwiftUI
import MadarDesign
@testable import Madar

// Design preview only (owner 16 Nov). Round 6, after the owner explained the flow:
// habits are logged OUTSIDE the room: a question at the time the user sets for each habit, one last call if still open,
// and the lobby for anything missed. The room is opened rarely: add a habit, read long-range statistics and smart notes.
// Synthetic data; generic for every habit kind. Not wired into the app.

private struct Notice: View {
    let title: String
    let message: String
    let actions: [String]
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 6) {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    RoundedRectangle(cornerRadius: 6).fill(theme.accent).frame(width: 22, height: 22)
                        .overlay { PrayerStar().fill(theme.background).frame(width: 12, height: 12) }
                    Text("مدار").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                    Spacer()
                    Text("الآن").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
                Text(title).font(PrayerHomeType.strong)
                Text(message).font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            }
            .padding(14).background(theme.surface, in: .rect(cornerRadius: 20))
            ForEach(actions, id: \.self) { a in
                Text(a).font(PrayerHomeType.strong).frame(maxWidth: .infinity, minHeight: 44)
                    .background(theme.surface.opacity(0.8), in: .rect(cornerRadius: 14))
            }
        }
    }
}

private struct Caption: View {
    let text: String
    @Environment(\.roomTheme) private var theme
    var body: some View { Text(text).font(PrayerHomeType.smallBold).foregroundStyle(theme.accent) }
}

/// Outside the room: the question at the habit's own time, the last call, and the lobby block.
private struct OutsideFlow: View {
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("خارج القسم").font(PrayerHomeType.hero)
            Caption(text: "١. في الوقت الذي تحدده للعادة (عادة بمقدار، ٦:٠٠ م)")
            Notice(title: "مشيت اليوم؟", message: "عادتك ٥ كم. آخر ثلاث مرات مشيت ٥ كم.", actions: ["مشيت ٥ كم كالمعتاد", "سجّل مقدارًا آخر", "ليس الآن"])
            Caption(text: "٢. تذكير أخير واحد إن بقيت مفتوحة (١٠:٠٠ م)")
            Notice(title: "آخر سؤال اليوم", message: "لم تسجّل المشي بعد. هل مشيت؟", actions: ["نعم، ٥ كم", "لم أمشِ اليوم"])
            Caption(text: "عادة مرة واحدة: زرّان فقط، وعادة بالعدد: «+١»")
            Notice(title: "قبل النوم", message: "هل أتممت عادة آخر اليوم؟", actions: ["تمّت", "ليس اليوم"])
            Caption(text: "٣. في البهو: ما فاتك فقط، ويُسجَّل بلمسة")
            VStack(alignment: .leading, spacing: 12) {
                HStack {
                    Text("بقي من عاداتك اليوم").font(PrayerHomeType.cardHead)
                    Spacer()
                    Text("٢").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
                lobbyRow("عادة بالعدد", "٢ من ٣", "+١")
                lobbyRow("عادة بالمدة", "لم تُسجَّل", "٣٠ دقيقة")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 22))
            Text("الأوراد والقراءة المرتبطة بغرفها تُسجَّل تلقائيًا ولا يُسأل عنها. ولا يصل أي سؤال وقت حرمة الأذان؛ يتأخر إلى ما بعدها.")
                .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
        }
        .padding(24).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func lobbyRow(_ name: String, _ state: String, _ action: String) -> some View {
        HStack {
            Text(name).font(PrayerHomeType.strong)
            Text(state).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            Spacer()
            Text(action).font(PrayerHomeType.smallBold).foregroundStyle(theme.accent)
                .padding(.horizontal, 12).frame(minHeight: 36).overlay { Capsule().stroke(theme.line) }
        }
    }
}

/// Inside the room: statistics and smart notes first; adding a habit is one clear action.
private struct RoomStats: View {
    let theme: RoomTheme
    private let habits: [(String, String, [Double])] = [
        ("عادة يومية بمقدار", "٨٧٪ هذا العام", [0.6, 0.7, 0.8, 0.9, 0.85, 0.9, 0.95, 0.8, 0.9, 1, 0.92, 0]),
        ("عادة يومية مرة", "٧٤٪ هذا العام", [0.4, 0.5, 0.7, 0.8, 0.6, 0.7, 0.9, 0.85, 0.8, 0.75, 0.8, 0]),
        ("عادة أسبوعية", "٣٨ من ٤٦ أسبوعًا", [1, 0.75, 1, 1, 0.5, 1, 0.75, 1, 1, 0.75, 1, 0]),
        ("عادة شهرية", "١٠ من ١١ شهرًا", [1, 1, 0, 1, 1, 1, 1, 1, 1, 1, 1, 0]),
    ]
    private let months = ["ي", "ف", "م", "أ", "م", "ي", "ي", "أ", "س", "أ", "ن", "د"]
    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack(alignment: .firstTextBaseline) {
                Text("العادات").font(PrayerHomeType.hero)
                Spacer()
                Text("+ عادة جديدة").font(PrayerHomeType.strong).foregroundStyle(theme.background)
                    .padding(.horizontal, 16).frame(minHeight: 44).background(theme.accent, in: .capsule)
            }
            // Smart notes, from the habits' own logs: patterns the user would not see alone.
            VStack(alignment: .leading, spacing: 12) {
                Caption(text: "ما لاحظه مدار")
                note("أثبت أيامك الأحد والاثنين، وأضعفها الجمعة.")
                note("العادة اليومية مرة تتعثّر حين تُسأل بعد ١١ م؛ جرّب وقتًا أبكر.")
                note("العادة الشهرية بقي لها ١٤ يومًا هذا الشهر.")
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 22))
            // The year: one quiet strip of twelve months per habit, whatever its kind.
            VStack(alignment: .leading, spacing: 18) {
                Text("سنتك ٢٠٢٦").font(PrayerHomeType.cardHead)
                ForEach(habits, id: \.0) { name, summary, values in
                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text(name).font(PrayerHomeType.strong)
                            Spacer()
                            Text(summary).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                        }
                        HStack(alignment: .bottom, spacing: 5) {
                            ForEach(Array(values.enumerated()), id: \.offset) { i, v in
                                VStack(spacing: 4) {
                                    RoundedRectangle(cornerRadius: 3).fill(i == 10 ? theme.accent : theme.accent.opacity(0.25 + 0.5 * v))
                                        .frame(height: max(3, 34 * v))
                                    Text(months[i]).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk.opacity(0.7))
                                }.frame(maxWidth: .infinity)
                            }
                        }.frame(height: 56, alignment: .bottom)
                    }
                }
            }
            HStack(spacing: 10) {
                stat("٢١ يومًا", "أطول سلسلة")
                stat("٨١٪", "التزام نوفمبر")
                stat("٣ عادات", "تحسّنت عن أكتوبر")
            }
        }
        .padding(24).foregroundStyle(theme.ink).background(theme.background).environment(\.roomTheme, theme)
    }
    private func note(_ t: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            PrayerStar().fill(theme.accent.opacity(0.6)).frame(width: 9, height: 9)
            Text(t).font(PrayerHomeType.body).fixedSize(horizontal: false, vertical: true)
        }
    }
    private func stat(_ v: String, _ t: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(v).font(PrayerHomeType.strong)
            Text(t).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 16))
    }
}

@MainActor
final class HabitsRedesignPreviewTests: XCTestCase {
    func testRenderHabitsRedesignPreviews() throws {
        let out = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("Artifacts/habits-redesign-preview")
        try FileManager.default.createDirectory(at: out, withIntermediateDirectories: true)
        let theme = RoomTheme(room: "salah", dark: false)
        for (name, view) in [("H-outside", AnyView(OutsideFlow(theme: theme))), ("H-room", AnyView(RoomStats(theme: theme)))] {
            let renderer = ImageRenderer(content: view.frame(width: 430).environment(\.layoutDirection, .rightToLeft))
            renderer.scale = 2
            let image = try XCTUnwrap(renderer.uiImage)
            try XCTUnwrap(image.pngData()).write(to: out.appendingPathComponent("habits-\(name)-L.png"))
        }
    }
}
