import SwiftUI
import WebKit
import MadarCore
import MadarDesign

/// The Mihbara EPUB reader on the Mac (owner, 15 Nov 2026: «ابي المحبره»). Readium is iOS-only (its shared module imports UIKit),
/// so the Mac opens the same stored EPUB itself: the file is unpacked into a private temporary folder, its spine read from the OPF,
/// and each chapter shown in a WKWebView in the room's paper and type. The place is saved as the same Readium locator JSON
/// (`href`, `type`, `locations.progression`, `locations.totalProgression`) through the shared save coordinator, so the iPhone
/// and the Mac read the same record.
struct MihbaraReaderView: View {
    let app: AppSession
    let book: MihbaraBook
    var volume: Int? = nil
    var initialLocatorJSON: String? = nil
    var originalPDF: ((String) -> UUID?)? = nil
    var openOriginal: ((UUID, Int) -> Void)? = nil
    let close: () -> Void

    @Environment(\.roomTheme) private var theme
    @State private var publication: MacEPUB?
    @State private var failure: String?
    @State private var chapter = 0
    @State private var startProgression = 0.0
    @State private var fontScale = 1.0
    @State private var page = MacEPUBPage()

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button("إغلاق", action: finish).keyboardShortcut(.cancelAction)
                Spacer()
                Text(book.title).font(MadarTypography.section()).lineLimit(1)
                Spacer()
                Button { fontScale = max(0.8, fontScale - 0.1) } label: { Image(systemName: "textformat.size.smaller") }
                    .keyboardShortcut("-", modifiers: .command).accessibilityLabel("تصغير الخط")
                Button { fontScale = min(1.8, fontScale + 0.1) } label: { Image(systemName: "textformat.size.larger") }
                    .keyboardShortcut("=", modifiers: .command).accessibilityLabel("تكبير الخط")
            }
            .buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            Group {
                if let publication {
                    MacEPUBWebView(publication: publication, chapter: chapter, startProgression: startProgression,
                                   fontScale: fontScale, paper: theme.surface, ink: theme.ink, page: page)
                } else if let failure {
                    VStack(spacing: 14) {
                        Text(failure).font(MadarTypography.body()).multilineTextAlignment(.center)
                        Button("العودة إلى المحبرة", action: close).buttonStyle(MadarPrimaryButton())
                    }.padding(40).frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            if let publication {
                Divider()
                HStack {
                    Button { move(by: -1) } label: { Label("الفصل السابق", systemImage: "chevron.right") }
                        .disabled(chapter == 0).keyboardShortcut(.leftArrow, modifiers: .command)
                    Spacer()
                    Text("الفصل \((chapter + 1).formatted()) من \(publication.spine.count.formatted())")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Spacer()
                    Button { move(by: 1) } label: { Label("الفصل التالي", systemImage: "chevron.left") }
                        .disabled(chapter >= publication.spine.count - 1).keyboardShortcut(.rightArrow, modifiers: .command)
                }
                .buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .background(theme.surface)
        .environment(\.layoutDirection, .rightToLeft)
        .task { await open() }
        .onDisappear { save(); publication?.discard() }
    }

    private func open() async {
        do {
            let data = try await AppMihbaraService(app: app).epubDataOffMain(for: book)
            let opened = try await Task.detached { try MacEPUB(data: data) }.value
            let saved = initialLocatorJSON ?? book.locatorJSON.flatMap { String(data: $0, encoding: .utf8) }
            if let saved, let place = opened.place(fromLocatorJSON: saved) {
                chapter = place.chapter; startProgression = place.progression
            } else if let volume, volume > 0, opened.spine.count > 1 {
                chapter = min(opened.spine.count - 1, Int((Double(volume) / Double(max(volume + 1, 1))) * Double(opened.spine.count)))
            }
            publication = opened
        } catch {
            failure = "تعذّر فتح الكتاب على الماك. \(madarUserMessage(error))"
        }
    }

    private func move(by delta: Int) {
        guard let publication else { return }
        save()
        chapter = min(max(chapter + delta, 0), publication.spine.count - 1)
        startProgression = delta < 0 ? 1 : 0
        page.progression = startProgression
    }

    private func save() {
        guard let publication, let json = publication.locatorJSON(chapter: chapter, progression: page.progression) else { return }
        MihbaraReadingSaveCoordinator.forSession(app).enqueueLocatorJSON(json, bookID: book.id)
    }

    private func finish() { save(); close() }
}

/// The scroll position the web view reports, kept outside SwiftUI state so a scroll does not redraw the reader.
final class MacEPUBPage { var progression = 0.0 }

/// An unpacked EPUB: the folder it lives in and its reading order (paths relative to the publication root, as Readium writes them).
struct MacEPUB: Sendable {
    let root: URL
    let spine: [String]

    init(data: Data) throws {
        let zip = try ZIPReader(data: data)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mihbara-mac-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for member in zip.members where !member.isDirectory && !member.isSymbolicLink && !member.isEncrypted {
            let parts = member.path.split(separator: "/").map(String.init)
            guard !parts.isEmpty, !parts.contains(".."), !member.path.hasPrefix("/") else { continue }
            let target = parts.reduce(root) { $0.appendingPathComponent($1) }
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try zip.read(member).write(to: target, options: .atomic)
        }
        let container = try Data(contentsOf: root.appendingPathComponent("META-INF/container.xml"))
        guard let opfPath = MacEPUBXML.attribute("full-path", ofFirst: "rootfile", in: container) else { throw MacEPUBError.unreadable }
        let opf = try Data(contentsOf: root.appendingPathComponent(opfPath))
        let base = (opfPath as NSString).deletingLastPathComponent
        let parsed = MacEPUBXML.spine(in: opf)
        let spine = parsed.order.compactMap { idref -> String? in
            guard let href = parsed.manifest[idref]?.removingPercentEncoding ?? parsed.manifest[idref] else { return nil }
            return base.isEmpty ? href : base + "/" + href
        }
        guard !spine.isEmpty else { throw MacEPUBError.unreadable }
        self.root = root
        self.spine = spine
    }

    func url(chapter: Int) -> URL { root.appendingPathComponent(spine[chapter]) }

    /// Opens a staged EPUB the way the reader will, then removes the unpacked copy.
    @concurrent static func validate(_ file: URL) async throws {
        let opened = try MacEPUB(data: Data(contentsOf: file, options: .mappedIfSafe))
        opened.discard()
    }

    func discard() { try? FileManager.default.removeItem(at: root) }

    func place(fromLocatorJSON json: String) -> (chapter: Int, progression: Double)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              var href = object["href"] as? String else { return nil }
        href = href.split(separator: "#").first.map(String.init) ?? href
        if href.hasPrefix("/") { href.removeFirst() }
        href = href.removingPercentEncoding ?? href
        guard let index = spine.firstIndex(of: href) ?? spine.firstIndex(where: { $0.hasSuffix("/" + href) || href.hasSuffix("/" + $0) }) else { return nil }
        let locations = object["locations"] as? [String: Any]
        return (index, min(max((locations?["progression"] as? Double) ?? 0, 0), 1))
    }

    func locatorJSON(chapter: Int, progression: Double) -> String? {
        let p = min(max(progression, 0), 1)
        let total = (Double(chapter) + p) / Double(max(spine.count, 1))
        let object: [String: Any] = ["href": spine[chapter], "type": "application/xhtml+xml",
                                     "locations": ["progression": p, "totalProgression": total]]
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

enum MacEPUBError: LocalizedError {
    case unreadable
    var errorDescription: String? { "ملف الكتاب لا يحوي ترتيب قراءة صالحًا." }
}

/// A small OPF/container reader: the rootfile path, the manifest (id → href) and the spine order.
private final class MacEPUBXML: NSObject, XMLParserDelegate {
    private var wanted = ""
    private var attributeName = ""
    private var found: String?
    private(set) var manifest: [String: String] = [:]
    private var order: [String] = []

    static func attribute(_ name: String, ofFirst element: String, in data: Data) -> String? {
        let reader = MacEPUBXML(); reader.wanted = element; reader.attributeName = name
        let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
        return reader.found
    }

    static func spine(in data: Data) -> (order: [String], manifest: [String: String]) {
        let reader = MacEPUBXML()
        let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
        return (reader.order, reader.manifest)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if !wanted.isEmpty {
            if local == wanted, found == nil { found = attributes[attributeName] }
            return
        }
        if local == "item", let id = attributes["id"], let href = attributes["href"] { manifest[id] = href }
        if local == "itemref", let idref = attributes["idref"], attributes["linear"] != "no" { order.append(idref) }
    }
}

/// One chapter in a WKWebView: right-to-left, the room's paper and ink, the chosen size, and the scroll position reported back.
private struct MacEPUBWebView: NSViewRepresentable {
    let publication: MacEPUB
    let chapter: Int
    let startProgression: Double
    let fontScale: Double
    let paper: Color
    let ink: Color
    let page: MacEPUBPage

    func makeCoordinator() -> Coordinator { Coordinator(page: page) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(context.coordinator, name: "place")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.style = style
        coordinator.startProgression = startProgression
        if coordinator.loadedChapter != chapter {
            coordinator.loadedChapter = chapter
            view.loadFileURL(publication.url(chapter: chapter), allowingReadAccessTo: publication.root)
        } else {
            view.evaluateJavaScript(coordinator.styleScript)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "place")
    }

    private var style: String {
        """
        html,body{direction:rtl;background:\(Self.css(paper))!important;color:\(Self.css(ink))!important}
        body{max-width:44em;margin:0 auto!important;padding:2.5em 2em 4em!important;font-size:\(Int(fontScale * 120))%!important;line-height:1.9!important}
        img{max-width:100%;height:auto}
        """
    }

    private static func css(_ color: Color) -> String {
        guard let c = NSColor(color).usingColorSpace(.sRGB) else { return "inherit" }
        return String(format: "rgb(%d,%d,%d)", Int(c.redComponent * 255), Int(c.greenComponent * 255), Int(c.blueComponent * 255))
    }

    final class Coordinator: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
        let page: MacEPUBPage
        var loadedChapter = -1
        var style = ""
        var startProgression = 0.0
        init(page: MacEPUBPage) { self.page = page }

        var styleScript: String {
            let escaped = style.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
            return """
            (function(){var s=document.getElementById('madar-style');if(!s){s=document.createElement('style');s.id='madar-style';document.head.appendChild(s);}s.textContent=`\(escaped)`;})();
            """
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let start = min(max(startProgression, 0), 1)
            webView.evaluateJavaScript(styleScript + """
            (function(){var e=document.scrollingElement;var max=Math.max(e.scrollHeight-innerHeight,0);e.scrollTop=max*\(start);
            var t;addEventListener('scroll',function(){clearTimeout(t);t=setTimeout(function(){var m=Math.max(e.scrollHeight-innerHeight,1);
            window.webkit.messageHandlers.place.postMessage(e.scrollTop/m);},250);});})();
            """)
            page.progression = start
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if let value = message.body as? Double { page.progression = min(max(value, 0), 1) }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Only the book's own files open inside the reader; outside links are not followed.
            action.request.url?.isFileURL == true ? .allow : .cancel
        }
    }
}

/// Full-text search across EPUB books uses Readium's search service, which is iOS-only. On the Mac the library search finds books
/// by title and author (the shared list below the field); the in-text hits section stays empty.
struct MihbaraTextSearchSection: View {
    let query: String
    let books: [MihbaraBook]
    let service: AppMihbaraService
    let open: (MihbaraTextHit) -> Void
    var body: some View { EmptyView() }
}

/// The same hit record as the iOS library search, so the shared library sheet compiles unchanged.
struct MihbaraTextHit: Identifiable {
    let id = UUID()
    let bookID: UUID
    let title: String
    let before: String, match: String, after: String
    var locatorJSON: String? = nil
    var pdfPage: Int? = nil
}
