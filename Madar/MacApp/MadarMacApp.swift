import SwiftUI
import SwiftData
import CoreText
import MadarData
import MadarCore
import MadarDesign
import MadarCommands

/// Madar on the Mac (owner, 15 Nov 2026: «ابي تبدا بناء تطبيق ماك نيتف من مدار»). A native AppKit/SwiftUI app, not the iPad app
/// in a window: one window with the rooms in a sidebar on the leading (right) edge, menu commands with keyboard shortcuts, and the
/// same session, store and room screens the iPhone and iPad use. Local-only like every v1 build (RA1): the Mac keeps its own store.
@main
struct MadarMacApp: App {
    @State private var runtime = MadarRuntime()
    init() { MacFonts.registerBundled() }
    var body: some Scene {
        WindowGroup("مدار", id: "main") {
            MacSceneContent(runtime: runtime)
                .frame(minWidth: 900, minHeight: 620)
        }
        .defaultSize(width: 1240, height: 820)
        .windowToolbarStyle(.unified(showsTitle: false))
        .commands { MadarMacCommands(runtime: runtime) }
    }
}

/// iOS registers the bundled faces through `UIAppFonts`; the Mac registers the same files for this process when the app starts.
enum MacFonts {
    static func registerBundled() {
        let urls = ["otf", "ttf"].flatMap { Bundle.main.urls(forResourcesWithExtension: $0, subdirectory: nil) ?? [] }
        for url in urls { CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil) }
    }
}

private struct MacSceneContent: View {
    let runtime: MadarRuntime
    @Environment(\.scenePhase) private var scenePhase
    var body: some View {
        Group {
            if let session = runtime.session {
                MacRootView(session: session).modelContainer(session.container).environment(session)
            } else if let startupError = runtime.startupError {
                StartupRecoveryView(error: startupError,
                                    groupDirectory: MadarPlatform.dataDirectory,
                                    retry: { Task { await runtime.load() } },
                                    startFresh: { await runtime.startWithFreshStore() })
            } else {
                MadarLaunchPlaceholder()
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar_SA"))
        .task { if runtime.session == nil && runtime.startupError == nil { await runtime.load() } }
        .onOpenURL { url in
            if let session = runtime.session { session.open(url) } else { runtime.pendingURL = url }
        }
    }
}

/// Menu-bar commands. Each room has its own shortcut (⌘1 the lobby, then the rooms in sidebar order) and «خصّص» sits where every
/// Mac app keeps its settings (⌘,). Rooms the Mac does not open yet have no command.
struct MadarMacCommands: Commands {
    let runtime: MadarRuntime
    var body: some Commands {
        CommandGroup(replacing: .appSettings) {
            Button("خصّص مدار…") { runtime.session?.selectedTab = "customize" }
                .keyboardShortcut(",", modifiers: .command)
                .disabled(runtime.session == nil)
        }
        CommandGroup(replacing: .newItem) { }
        CommandMenu("الغرف") {
            ForEach(Array(MacRooms.tabs.enumerated()), id: \.element.id) { index, tab in
                Button(tab.title) { runtime.session?.selectedTab = tab.id }
                    .keyboardShortcut(KeyEquivalent(Character(String(index + 1))), modifiers: .command)
                    .disabled(runtime.session == nil)
            }
            Divider()
            Button("حدّث البيانات") { Task { await runtime.session?.refreshFromPull() } }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(runtime.session == nil)
        }
    }
}

/// The rooms the Mac app opens, in sidebar order. The Mihbara reads EPUBs with the Mac reader and PDFs with PDFKit.
@MainActor enum MacRooms {
    static let macTabs: Set<String> = ["prayer", "quran", "notes", "money", "mihbara"]
    static var tabs: [FoundationTab] {
        [FoundationTab(id: "foundation", title: "البهو", symbol: "MadarOrbit")]
            + AppSession.roomTabs.map(\.tab).filter(macTabs.contains).compactMap { AppSession.tabInfo[$0] }
    }
}
