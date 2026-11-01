import SwiftUI
import UIKit
import MadarCore
import MadarData
import MadarDesign

/// «عرض الصفحة»: every choice is saved to `mihbara.readerAr` at once and applied live.
struct MihbaraReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppSession
    let paper: SwiftUI.Color
    let palette: MihbaraReaderPalette
    let english: Bool
    let options: MihbaraReaderOptions
    let undoTokenID: UUID?
    let set: (String, MadarData.JSONValue) -> Void
    let reset: () -> Void
    @State private var more = false

    private var ink: SwiftUI.Color { palette.ink }
    private var accent: SwiftUI.Color { palette.accent }
    private var well: SwiftUI.Color { ink.opacity(0.06) }
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private var hasSettingsUndo: Bool {
        guard app.undoToastVisible, let token = app.undoToken, let undoTokenID else { return false }
        return token.id == undoTokenID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                sizeRow
                fontRow
                modeRow
                themeRow
                if options.mode == "scroll" { autoScrollRow }
                Button { withAnimation(.smooth(duration: 0.25)) { more.toggle() } } label: {
                    Text(more ? "خيارات أقل" : "خيارات أكثر").font(MadarTypography.caption().weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .glassEffect(.regular.interactive(), in: Capsule())
                }
                .buttonStyle(.plain).accessibilityIdentifier("mihbara-reader-more")
                if more { moreOptions }
            }
            .padding(.horizontal, 18).padding(.vertical, 12)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(ink)
        .background(paper.ignoresSafeArea())
        .safeAreaInset(edge: .top) {
            VStack(spacing: 0) {
                if hasSettingsUndo {
                    UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast)
                        .accessibilityIdentifier("mihbara-reader-undo")
                        .padding(.horizontal, 12).padding(.top, 4)
                }
                // Changing a font can preserve a scrolled content offset. The close
                // action stays outside that scrolling content and below the undo toast.
                header.padding(.horizontal, 18).padding(.vertical, 8)
            }.foregroundStyle(ink).background(paper)
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .environment(\.colorScheme, palette.isDark ? .dark : .light)
        .environment(\.roomTheme, RoomTheme(room: "mihbara", dark: palette.isDark))
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("عرض الصفحة").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
            Spacer(minLength: 8)
            Text(english ? "كتاب إنجليزي · إعداداتك للإنجليزي" : "كتاب عربي · إعداداتك للعربي").font(MadarTypography.fine().weight(.semibold))
                .lineLimit(1)
                .padding(.horizontal, 12).padding(.vertical, 6).background(well, in: .capsule)
            Button("تمّ") { dismiss() }.font(MadarTypography.caption()).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("mihbara-reader-settings-close")
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 0) {
            HStack(spacing: 2) {
                Text(english ? "A" : "أ").font(.custom(english ? options.englishFont.previewName : options.font.previewName, size: 15, relativeTo: .body))
                Text("−").font(MadarTypography.caption())
            }
            ForEach(1...7, id: \.self) { value in
                Button { set("size", .number(Double(value))) } label: {
                    Circle().fill(ink.opacity(value == options.size ? 1 : 0.35))
                        .frame(width: value == options.size ? 14 : 6, height: value == options.size ? 14 : 6)
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .contentShape(.rect)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("حجم الخط \(digits.string(value))")
                .accessibilityAddTraits(value == options.size ? .isSelected : [])
                .accessibilityIdentifier("mihbara-reader-size-\(value)")
            }
            HStack(spacing: 2) {
                Text(english ? "A" : "أ").font(.custom(english ? options.englishFont.previewName : options.font.previewName, size: 26, relativeTo: .title))
                Text("+").font(MadarTypography.body())
            }
        }
        .padding(.horizontal, 16).frame(minHeight: 58).background(well, in: .rect(cornerRadius: 16))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 16))
    }

    private var fontRow: some View {
        HStack(spacing: 8) {
            if english {
                GlassEffectContainer(spacing: 8) {
                    HStack(spacing: 8) {
                        ForEach(MihbaraEnglishReaderFont.allCases) { option in
                            let selected = option == options.englishFont
                            Button { set("font", .string(option.rawValue)) } label: {
                                VStack(spacing: 3) {
                                    Text("Book").font(.custom(option.previewName, size: 22, relativeTo: .title3)).lineLimit(1).minimumScaleFactor(0.75)
                                    Text(option.title).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.72)).lineLimit(1)
                                }
                                .frame(maxWidth: .infinity, minHeight: 76)
                                .background(SwiftUI.Color.white.opacity(0.26), in: .rect(cornerRadius: 16))
                                .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                                .overlay { RoundedRectangle(cornerRadius: 16).stroke(ink.opacity(selected ? 0.88 : 0.12), lineWidth: selected ? 2.5 : 1) }
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("الخط \(option.title)")
                            .accessibilityAddTraits(selected ? .isSelected : [])
                            .accessibilityIdentifier("mihbara-reader-font-\(option.rawValue)")
                        }
                    }
                }
            } else {
                ForEach(MihbaraReaderFont.allCases) { option in
                    let selected = option == options.font
                    Button { set("font", .string(option.rawValue)) } label: {
                        VStack(spacing: 2) {
                            Text("كتاب").font(.custom(option.previewName, size: 24, relativeTo: .title3))
                            Text(option.title).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.7))
                        }
                        .frame(maxWidth: .infinity, minHeight: 76)
                        .background(SwiftUI.Color.white.opacity(0.26), in: .rect(cornerRadius: 16))
                        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 16))
                        .overlay { RoundedRectangle(cornerRadius: 16).stroke(ink.opacity(selected ? 0.88 : 0.12), lineWidth: selected ? 2.5 : 1) }
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("الخط \(option.title)")
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("mihbara-reader-font-\(option.rawValue)")
                }
            }
        }
    }

    /// Six palettes (§7.6): each swatch is the page itself, a line of ink on its own paper.
    private var themeRow: some View {
        HStack(spacing: 0) {
            ForEach(MihbaraReaderTheme.allCases) { theme in
                let selected = theme == options.theme
                Button { set("theme", .string(theme.rawValue)) } label: {
                    VStack(spacing: 6) {
                        ZStack {
                            if theme == .auto {
                                Circle().fill(SwiftUI.Color(uiColor: UIColor(madarHex: MihbaraReaderTheme.paper.hex.bg)))
                                Circle().trim(from: 0.25, to: 0.75).fill(SwiftUI.Color(uiColor: UIColor(madarHex: MihbaraReaderTheme.night.hex.bg)))
                            } else {
                                Circle().fill(SwiftUI.Color(uiColor: UIColor(madarHex: theme.hex.bg)))
                            }
                            Text(english ? "A" : "أ").font(.custom(english ? options.englishFont.previewName : "Amiri-Bold", size: 17, relativeTo: .body))
                                .foregroundStyle(SwiftUI.Color(uiColor: UIColor(madarHex: (theme == .auto ? MihbaraReaderTheme.paper : theme).hex.ink)))
                                .opacity(theme == .auto ? 0 : 1)
                            Circle().strokeBorder(selected ? accent : ink.opacity(0.22), lineWidth: selected ? 2.5 : 1)
                        }
                        .frame(width: 44, height: 44)
                        Text(theme.title).font(MadarTypography.fine()).foregroundStyle(selected ? ink : palette.ink2)
                    }
                    .frame(maxWidth: .infinity, minHeight: 64).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel("ثيم " + theme.title)
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("mihbara-reader-theme-\(theme.rawValue)")
            }
        }
    }

    private var modeRow: some View {
        segmented([("صفحات", "pages"), ("تمرير", "scroll"), ("تركيز", "focus")],
                  selected: options.mode, id: "mode") { set("mode", .string($0)) }
    }

    private var autoScrollRow: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("تمرير تلقائي").font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.72))
            segmented(MihbaraAutoScrollSpeed.allCases.map { ($0.title, $0.rawValue) },
                      selected: options.autoScroll.rawValue, id: "autoScroll") {
                set("autoScroll", .string($0))
            }
        }
    }

    private var moreOptions: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 12) {
                iconGroup(title: "تباعد الأسطر", id: "lineSpacing", selected: options.lineSpacing) { level in
                    VStack(spacing: CGFloat(level) * 1.6) { ForEach(0..<3, id: \.self) { _ in Capsule().frame(width: 20, height: 2) } }
                }
                iconGroup(title: "الهوامش", id: "margins", selected: options.margins) { level in
                    RoundedRectangle(cornerRadius: 2).stroke(lineWidth: 1.4).frame(width: 24, height: 18)
                        .overlay { Rectangle().frame(width: max(4, 20 - CGFloat(level) * 4), height: 12) }
                }
            }
            toggle("ضبط الأسطر (محاذاة كاملة)", nil, isOn: options.justify, id: "justify")
            Divider()
            toggle("خط أثقل", "أوضح على الشاشة", isOn: options.heavier, id: "heavier")
            Divider()
            if english {
                toggle("تقسيم الكلمات", "يلائم الكلمات الطويلة داخل السطر", isOn: options.hyphenation, id: "hyphenation")
                Divider()
                toggle("مسافة أوسع بين الكلمات", nil, isOn: options.wordSpacing, id: "wordSpacing")
                Divider()
            }
            VStack(alignment: .leading, spacing: 8) {
                Text("أسفل الصفحة").font(MadarTypography.caption()).foregroundStyle(ink.opacity(0.7))
                if english {
                    segmented(MihbaraEnglishReaderFooter.allCases.map { ($0.title, $0.rawValue) }, selected: options.englishFooter.rawValue, id: "footer") { set("footer", .string($0)) }
                } else {
                    segmented(MihbaraReaderFooter.allCases.map { ($0.title, $0.rawValue) }, selected: options.footer.rawValue, id: "footer") { set("footer", .string($0)) }
                }
            }
            Button("العودة إلى الإعدادات الافتراضية", action: reset)
                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44)
                .glassEffect(.regular.interactive(), in: Capsule())
                .accessibilityIdentifier("mihbara-reader-reset")
        }
    }

    private func segmented(_ items: [(String, String)], selected: String, id: String, choose: @escaping (String) -> Void) -> some View {
        HStack(spacing: 4) {
            ForEach(items, id: \.1) { title, value in
                let isOn = value == selected
                Button { choose(value) } label: {
                    Text(title).font(MadarTypography.caption().weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .foregroundStyle(isOn ? paper : ink.opacity(0.6))
                        .background(isOn ? ink : .clear, in: .rect(cornerRadius: 12))
                }
                .buttonStyle(.madarPlain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("mihbara-reader-\(id)-\(value)")
            }
        }
        .padding(4).background(well, in: .rect(cornerRadius: 15))
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 15))
    }

    private func iconGroup<Icon: View>(title: String, id: String, selected: Int, @ViewBuilder icon: @escaping (Int) -> Icon) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.7))
            HStack(spacing: 4) {
                ForEach(1...4, id: \.self) { level in
                    let isOn = level == selected
                    Button { set(id, .number(Double(level))) } label: {
                        icon(level).foregroundStyle(isOn ? paper : ink.opacity(0.6))
                            .frame(maxWidth: .infinity, minHeight: 44)
                            .background(isOn ? ink : .clear, in: .rect(cornerRadius: 10))
                    }
                    .buttonStyle(.madarPlain)
                    .accessibilityLabel("\(title) \(digits.string(level))")
                    .accessibilityAddTraits(isOn ? .isSelected : [])
                    .accessibilityIdentifier("mihbara-reader-\(id)-\(level)")
                }
            }
            .padding(4).background(well, in: .rect(cornerRadius: 13))
        }
        .frame(maxWidth: .infinity)
    }

    private func toggle(_ title: String, _ detail: String?, isOn: Bool, id: String) -> some View {
        Toggle(isOn: Binding(get: { isOn }, set: { set(id, .bool($0)) })) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MadarTypography.body().weight(.semibold))
                if let detail { Text(detail).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65)) }
            }
        }
        .tint(accent)
        .accessibilityIdentifier("mihbara-reader-\(id)")
    }
}
