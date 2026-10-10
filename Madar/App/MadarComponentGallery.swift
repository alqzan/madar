#if DEBUG
import SwiftUI
import MadarDesign

/// UI-test-only rendering surface; it has no entry in the shipping application.
struct MadarComponentGallery: View {
    @State private var editing = true
    private var dark: Bool { ProcessInfo.processInfo.environment["MADAR_UI_THEME"] == "dark" }
    private var size: DynamicTypeSize {
        switch ProcessInfo.processInfo.environment["MADAR_UI_SIZE"] {
        case "AX3": .accessibility3
        case "AX5": .accessibility5
        default: .large
        }
    }
    var body: some View {
        let theme = RoomTheme(dark: dark, calmPaper: false)
        CustomizationTemplate(title: "مكونات مدار", subtitle: "معاينة اختبار الواجهة") {
            MadarCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("مساحة هادئة ليومك").font(MadarTypography.cardTitle())
                    Text("تتسع الكتابة مع حجم النص الذي اخترته.").font(MadarTypography.body())
                    Button("ابدأ يومك") {}.buttonStyle(MadarPrimaryButton())
                }
            }
        } content: {
            VStack(spacing: 16) {
                EditModeContainer(isEditing: $editing, reset: {}) {
                    MadarCard { Text("الترتيب").font(MadarTypography.section()) }
                }
                UndoToast(message: "حُفظ التعديل", undo: {})
            }.accessibilityIdentifier("component-gallery")
        }
        .environment(\.roomTheme, theme)
        .environment(\.layoutDirection, .rightToLeft)
        .dynamicTypeSize(size)
        .preferredColorScheme(dark ? .dark : .light)
    }
}
#endif
