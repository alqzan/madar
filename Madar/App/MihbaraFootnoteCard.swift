import SwiftUI
import MadarDesign

struct MihbaraFootnoteCard: View {
    let note: MihbaraFootnote
    let palette: MihbaraReaderPalette
    let number: String
    let close: () -> Void

    private var ink: SwiftUI.Color { palette.ink }
    private var ink2: SwiftUI.Color { palette.ink2 }
    private var accent: SwiftUI.Color { palette.accent }
    private var onAccent: SwiftUI.Color { palette.onAccent }
    private var surface: SwiftUI.Color { palette.bg }

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            if !number.isEmpty && number != "حواشي الصفحة" {
                Text(number).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline)).foregroundStyle(onAccent)
                    .frame(minWidth: 32, minHeight: 32).background(Circle().fill(accent))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text(number == "حواشي الصفحة" ? "حواشي الصفحة" : "حاشية الكتاب").font(MadarTypography.fine()).foregroundStyle(ink2)
                ScrollView {
                    Text(note.text).font(.custom("Amiri-Regular", size: 19, relativeTo: .body)).foregroundStyle(ink)
                        .lineSpacing(5).frame(maxWidth: .infinity, alignment: .leading)
                        .textSelection(.enabled)
                        .accessibilityIdentifier("mihbara-footnote-text")
                }
                .frame(maxHeight: 220).fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark").font(.system(size: 13, weight: .semibold)).foregroundStyle(ink2)
                    .frame(width: 44, height: 44).background(Circle().fill(ink.opacity(palette.isDark ? 0.10 : 0.05)).padding(4)).contentShape(Circle())
            }
            .accessibilityLabel("إغلاق الحاشية")
            .accessibilityIdentifier("mihbara-footnote-close")
        }
        .padding(.leading, 18).padding(.trailing, 10).padding(.top, 18).padding(.bottom, 16)
        .background(surface)
        .overlay(alignment: .top) { Rectangle().fill(accent).frame(height: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 26, style: .continuous))
        .background(RoundedRectangle(cornerRadius: 26, style: .continuous).fill(surface)
            .shadow(color: .black.opacity(palette.isDark ? 0.45 : 0.14), radius: 20, y: 6))
        .accessibilityElement(children: .contain)
        .accessibilityLabel(number.isEmpty ? "حاشية" : "الحاشية \(number)")
        .accessibilityIdentifier("mihbara-footnote-card")
    }
}
