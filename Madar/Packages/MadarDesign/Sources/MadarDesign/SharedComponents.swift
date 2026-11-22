import SwiftUI

public struct UndoToast: View {
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let message: String
    private let undo: () -> Void
    private let dismiss: (() -> Void)?
    private let seconds: Double
    private let tokenID: UUID?
    private let earlier: String?
    /// Owner, 30 Oct 2026: the toast glides in from the bottom edge and a swipe down puts it away early.
    /// Owner, 22 Nov 2026 (mockup «أ», approved): a small pill sized to its words, a thin line along its foot that drains
    /// as the seconds pass, and the removal just before it peeking behind, dimmed (only the latest can be undone).
    public init(message: String, undo: @escaping () -> Void, dismiss: (() -> Void)? = nil,
                seconds: Double = 4, tokenID: UUID? = nil, earlier: String? = nil) {
        self.message = message; self.undo = undo; self.dismiss = dismiss
        self.seconds = seconds; self.tokenID = tokenID; self.earlier = earlier
    }
    public var body: some View {
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    Text(message).font(MadarTypography.body())
                    Button("تراجع", action: undo).font(MadarTypography.section()).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("undo-button")
                }
                .padding(.horizontal, 16).padding(.vertical, 4)
                .glassEffect(.regular.interactive(), in: .rect(cornerRadius: 16))
            } else {
                HStack(spacing: 14) {
                    Text(message).font(MadarTypography.caption()).lineLimit(1)
                    Button("تراجع", action: undo).font(MadarTypography.caption().bold()).foregroundStyle(theme.accent)
                        .frame(minWidth: 44, minHeight: 40).contentShape(Rectangle())
                        .accessibilityIdentifier("undo-button")
                }
                .padding(.horizontal, 18)
                .overlay(alignment: .bottom) { UndoTimeLine(seconds: seconds, id: tokenID, tint: theme.accent).padding(.horizontal, 18) }
                .glassEffect(.regular.interactive(), in: .capsule)
                .overlay { Capsule().stroke(theme.accent.opacity(0.5), lineWidth: 0.8) }
                .background(alignment: .top) { UndoEarlierPill(message: earlier) }
            }
        }
        .foregroundStyle(theme.ink)
        .padding(.horizontal, 16).accessibilityElement(children: .contain)
        .gesture(DragGesture(minimumDistance: 12).onEnded { value in
            if value.translation.height > 24 { dismiss?() }
        })
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
        .accessibilityAction(named: "أخفِ") { dismiss?() }
    }
}

/// The removal before the current one, peeking above the pill (Sonner's stack), without an undo of its own.
public struct UndoEarlierPill: View {
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let message: String?
    public init(message: String?) { self.message = message }
    public var body: some View {
        ZStack {
            if let message {
                Text(message).font(MadarTypography.fine()).lineLimit(1).foregroundStyle(theme.secondaryInk)
                    .padding(.horizontal, 14).padding(.top, 5).padding(.bottom, 16)
                    .background(theme.surface.opacity(0.92), in: .capsule)
                    .overlay { Capsule().stroke(theme.line, lineWidth: 0.6) }
                    .scaleEffect(0.92).offset(y: -18)
                    .transition(reduceMotion ? .opacity : .offset(y: 8).combined(with: .opacity))
                    .accessibilityHidden(true)
            }
        }
        .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: message)
    }
}

/// A hairline that drains from full to empty over the seconds the undo pill stays, restarting for each new removal.
public struct UndoTimeLine: View {
    let seconds: Double
    let id: UUID?
    let tint: Color
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var remaining: CGFloat = 1
    public init(seconds: Double, id: UUID?, tint: Color) { self.seconds = seconds; self.id = id; self.tint = tint }
    public var body: some View {
        Capsule().fill(tint.opacity(0.7)).frame(height: 1.5)
            .scaleEffect(x: remaining, anchor: .leading)
            .opacity(reduceMotion ? 0 : 1)
            .task(id: id) {
                var reset = Transaction(); reset.disablesAnimations = true
                withTransaction(reset) { remaining = 1 }
                guard !reduceMotion, seconds > 0, seconds < 60 else { return }
                try? await Task.sleep(for: .milliseconds(30))
                withAnimation(.linear(duration: seconds)) { remaining = 0 }
            }
            .allowsHitTesting(false).accessibilityHidden(true)
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
                    Button(isEditing ? "تم" : "رتّب") { isEditing.toggle() }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
                }.frame(maxWidth: .infinity, alignment: .leading)
            } else { HStack {
                Text(isEditing ? "رتّب واجهتك" : "ترتيب الواجهة").font(MadarTypography.section())
                Spacer()
                Button(isEditing ? "تم" : "رتّب") { isEditing.toggle() }.frame(minWidth: 44, minHeight: 44).contentShape(Rectangle())
            } }
            content
                .overlay { if isEditing { RoundedRectangle(cornerRadius: 16).stroke(theme.accent, style: StrokeStyle(lineWidth: 1, dash: [4])) } }
                #if os(iOS)
                .environment(\.editMode, .constant(isEditing ? .active : .inactive))
                #endif
            if isEditing {
                Button("أعِد الترتيب المتفق عليه", action: reset).frame(minHeight: 44).contentShape(Rectangle())
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
    /// The column width; a page that lays itself out in two columns on iPad passes a wider one.
    private let maxWidth: CGFloat
    public init(title: String, subtitle: String = "كل تعديل يُحفظ وحده", maxWidth: CGFloat = 620, @ViewBuilder preview: () -> Preview, @ViewBuilder content: () -> Content) {
        self.title = title; self.subtitle = subtitle; self.maxWidth = maxWidth; self.preview = preview(); self.content = content()
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
            .padding(16).frame(maxWidth: maxWidth).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink)
    }
}
