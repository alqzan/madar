import SwiftUI
import AppKit

// The shared room code was written for iPhone and iPad. On the Mac the same names point at AppKit and at layouts that suit a
// window: the Mac is always "wide", a modifier that only exists for a phone is a no-op, and a full-screen cover opens as a sheet.
// Keeping this in the Mac target leaves every shared file byte-for-byte the iOS behaviour.

typealias UIImage = NSImage
typealias UIColor = NSColor
typealias UIFont = NSFont

extension Image { init(uiImage: NSImage) { self.init(nsImage: uiImage) } }
extension Color { init(uiColor: NSColor) { self.init(nsColor: uiColor) } }

/// iOS has compact and regular widths; a Mac window is laid out as the wide (iPad) layout.
enum UserInterfaceSizeClass: Hashable, Sendable { case compact, regular }
extension EnvironmentValues {
    @Entry var horizontalSizeClass: UserInterfaceSizeClass? = .regular
    @Entry var verticalSizeClass: UserInterfaceSizeClass? = .regular
}

/// The Mac always takes the wide layout the iPad uses: sidebar beside the room, two columns where a room has them.
@MainActor func isPadWide(_ sizeClass: UserInterfaceSizeClass?) -> Bool { true }

enum MacTitleDisplayMode { case automatic, inline, large }
enum MacKeyboardType { case `default`, numberPad, decimalPad, phonePad, emailAddress, URL, asciiCapable, numbersAndPunctuation, twitter, webSearch, asciiCapableNumberPad, namePhonePad }

extension View {
    func navigationBarTitleDisplayMode(_ mode: MacTitleDisplayMode) -> some View { self }
    func keyboardType(_ type: MacKeyboardType) -> some View { self }
    func fullScreenCover<Item: Identifiable, Content: View>(item: Binding<Item?>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping (Item) -> Content) -> some View {
        sheet(item: item, onDismiss: onDismiss) { value in MacFullWindow { content(value) } }
    }
    func fullScreenCover<Content: View>(isPresented: Binding<Bool>, onDismiss: (() -> Void)? = nil, @ViewBuilder content: @escaping () -> Content) -> some View {
        sheet(isPresented: isPresented, onDismiss: onDismiss) { MacFullWindow { content() } }
    }
}

extension ToolbarPlacement {
    /// A phone's navigation and tab bars; on the Mac the window toolbar stands in for both.
    static var navigationBar: ToolbarPlacement { .windowToolbar }
    static var tabBar: ToolbarPlacement { .windowToolbar }
}

extension ToolbarItemPlacement {
    /// A phone's top-bar corners; in a Mac window they map to the toolbar's navigation and primary-action slots.
    static var topBarLeading: ToolbarItemPlacement { .navigation }
    static var topBarTrailing: ToolbarItemPlacement { .primaryAction }
}

enum MacAutocapitalization { case never, words, sentences, characters }
enum MacIndexDisplayMode { case automatic, always, never }

extension View {
    func textInputAutocapitalization(_ style: MacAutocapitalization?) -> some View { self }
    func statusBarHidden(_ hidden: Bool = true) -> some View { self }
}

extension TabViewStyle where Self == DefaultTabViewStyle {
    /// A paged strip on iPhone; the Mac shows the same pages with its own tab style.
    static func page(indexDisplayMode: MacIndexDisplayMode) -> DefaultTabViewStyle { .automatic }
}

/// A full-screen flow on iPhone (the Mushaf, a session, the quick expense) opens on the Mac as a sheet as large as the window allows.
private struct MacFullWindow<Content: View>: View {
    @ViewBuilder let content: () -> Content
    var body: some View {
        content().frame(minWidth: 820, idealWidth: 1100, minHeight: 620, idealHeight: 820).presentationSizing(.page)
    }
}
