import SwiftUI

/// Room identities are vector templates; utility/action symbols retain their system meaning.
struct MadarGlyph: View {
    let name: String
    var size: CGFloat = 18
    init(_ name: String, size: CGFloat = 18) { self.name = name; self.size = size }
    var body: some View {
        Group {
            if name.hasPrefix("Madar") { Image(name).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size) }
            else { Image(systemName: name).font(.system(size: size)) }
        }.accessibilityHidden(true)
    }
}

/// One display-only name map shared by app rooms and JSON-only widget views.
enum HabitNameGlyph {
    static func symbol(for name: String) -> String? {
        let table: [([String], String)] = [(["ماء", "مياه", "شرب"], "drop"), (["أذكار المساء", "المساء", "وتر", "قيام"], "moon"), (["أذكار الصباح", "الصباح", "ضحى"], "sun.max"),
            (["أذكار", "ذكر", "استغفار", "تسبيح"], "sparkle"), (["قراءة", "اقرأ", "كتاب", "مذاكرة", "دراسة", "حفظ", "مراجعة"], "book"), (["مشي", "خطوات"], "figure.walk"),
            (["رياضة", "جري", "تمرين"], "figure.run"), (["صدقة", "تبرع"], "heart"), (["صيام", "صوم"], "moon.stars"), (["الوالدين", "زيارة", "الأخوال", "اتصال", "الاتصال", "صلة", "الأرحام"], "person.2"),
            (["نوم", "النوم"], "bed.double"), (["قهوة"], "cup.and.saucer"), (["كتابة", "تدوين"], "pencil")]
        return table.first { $0.0.contains { name.contains($0) } }?.1
    }
}
