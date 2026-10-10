import SwiftUI

public struct UndoToast: View {
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    private let message: String
    private let undo: () -> Void
    public init(message: String, undo: @escaping () -> Void) { self.message = message; self.undo = undo }
    public var body: some View {
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(MadarTypography.body())
                    Button("تراجع", action: undo).font(MadarTypography.section()).frame(minWidth: 44, minHeight: 44).accessibilityIdentifier("undo-button")
                }
            } else { HStack(spacing: 16) {
            Text(message).font(MadarTypography.body()).frame(maxWidth: .infinity, alignment: .leading)
            Button("تراجع", action: undo).font(MadarTypography.section()).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("undo-button")
            } }
        }
        .foregroundStyle(theme.ink).padding(.horizontal, 16).padding(.vertical, 4)
        .background(theme.surface, in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.accent, lineWidth: 1) }
        .padding(.horizontal, 16).accessibilityElement(children: .contain)
    }
}

/// Shared editing wrapper. The owner supplies durable reorder/hide commands.
public struct EditModeContainer<Content: View>: View {
    @Binding private var isEditing: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    private let content: Content
    private let reset: () -> Void
    public init(isEditing: Binding<Bool>, reset: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self._isEditing = isEditing; self.reset = reset; self.content = content()
    }
    public var body: some View {
        VStack(spacing: 16) {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(isEditing ? "رتّب واجهتك" : "ترتيب الواجهة").font(MadarTypography.section())
                    Button(isEditing ? "تم" : "رتّب") { isEditing.toggle() }.frame(minWidth: 44, minHeight: 44)
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else { HStack {
                Text(isEditing ? "رتّب واجهتك" : "ترتيب الواجهة").font(MadarTypography.section())
                Spacer()
                Button(isEditing ? "تم" : "رتّب") { isEditing.toggle() }.frame(minWidth: 44, minHeight: 44)
            } }
            content
                .overlay { if isEditing { RoundedRectangle(cornerRadius: 16).stroke(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4])) } }
                #if os(iOS)
                .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                #endif
            if isEditing {
                Button("أعِد الترتيب المتفق عليه", action: reset).frame(minHeight: 44)
            }
        }
        .foregroundStyle(theme.ink)
        .onLongPressGesture(minimumDuration: 0.52) { isEditing = true }
    }
}

public struct CustomizationTemplate<Preview: View, Content: View>: View {
    @Environment(\.roomTheme) private var theme
    private let title: String
    private let subtitle: String
    private let preview: Preview
    private let content: Content
    public init(title: String, subtitle: String = "كل تعديل يُحفظ وحده", @ViewBuilder preview: () -> Preview, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.preview = preview(); self.content = content()
    }
    public var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(MadarTypography.title())
                    Text(subtitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                preview
                content
            }
            .padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink)
    }
}
