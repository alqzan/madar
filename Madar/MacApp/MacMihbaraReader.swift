import SwiftUI
import AppKit
import WebKit
import SwiftData
import Translation
import MadarCore
import MadarPrayer
import MadarCommands
import MadarData
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
    @Environment(\.colorScheme) private var colorScheme
    @State private var publication: MacEPUB?
    @State private var contentRuleList: WKContentRuleList?
    @State private var failure: String?
    @State private var chapter = 0
    @State private var startProgression = 0.0
    @State private var page = MacEPUBPage()
    @Environment(\.scenePhase) private var scenePhase
    // Reading time, counted the same way as the iPhone reader: active seconds (idle pauses after five minutes), sessions of a
    // minute or more, forward positions of about 1024 characters each (Readium's position size) for the reading wird.
    @State private var clock: ActiveReadingClock?
    @State private var sessionID = UUID()
    @State private var sessionStart: Date?
    @State private var sessionStartChapter = 0
    @State private var sessionStartProgression = 0.0
    @State private var positions = ReadingPositionProgress()
    @State private var sessionDayStamp: String?
    @State private var lastSample: Date?
    @State private var highlights: [MihbaraHighlight] = []
    @State private var paragraph: MacEPUBParagraph?
    @State private var noteDraft: String?
    @State private var footnote: String?
    @State private var scrollRequest = 0
    @State private var selection: MacEPUBSelection?
    @State private var wordCard: MacEPUBSelection?
    @State private var wordCardDestination: MacWordCardDestination?
    @State private var quoteCard: MihbaraQuoteCardContent?
    @State private var settingsOpen = false

    private var marks: [MacEPUBMark] {
        guard let publication else { return [] }
        return highlights.compactMap { h in
            guard let m = publication.mark(fromLocatorJSON: h.locatorJSON), m.chapter == chapter else { return nil }
            return MacEPUBMark(id: h.id, selector: m.selector, color: h.color)
        }
    }
    /// The reader theme shared with iPhone and iPad (`mihbara.readerAr` / `mihbara.readerEn` → `theme`); «تلقائي» is paper by
    /// day and night after dark, the same colours as the iPhone reader.
    private var settingsKey: String { book.language == "en" ? "mihbara.readerEn" : "mihbara.readerAr" }
    private var readerSettings: [String: MadarData.JSONValue] {
        var merged = app.schema.settings.first(where: { $0.key == settingsKey })?.defaultValue.object ?? [:]
        if case .object(let stored)? = app.values[settingsKey] { merged.merge(stored) { _, new in new } }
        return merged
    }
    private var readerTheme: String { readerSettings["theme"]?.string ?? "auto" }
    private var readerColors: (paper: Color, ink: Color) {
        let name = readerTheme == "auto" ? (colorScheme == .dark ? "night" : "paper") : readerTheme
        let hex: (String, String) = switch name {
        case "warm": ("#F3E7CF", "#2E2216")
        case "calm": ("#E5E4DF", "#1F1E1B")
        case "night": ("#1F1C17", "#E9E1D2")
        case "black": ("#000000", "#D9D3C7")
        default: ("#FAF6EA", "#2A2118")
        }
        return (Color(macReaderHex: hex.0), Color(macReaderHex: hex.1))
    }
    /// The shared text size (1…7, the iPhone's 95%…155%), shown a fifth larger on the Mac's reading distance.
    private var readerSize: Int {
        guard case .number(let value)? = readerSettings["size"], value.isFinite else { return 4 }
        return min(7, max(1, Int(value)))
    }
    private var fontScale: Double { Double(95 + (readerSize - 1) * 10) / 100 }
    private var readerFontFamily: String {
        let name = readerSettings["font"]?.string ?? (book.language == "en" ? "literata" : "amiri")
        if book.language == "en" {
            return switch name {
            case "sourceSerif": "Source Serif 4"
            case "atkinsonHyperlegible": "Atkinson Hyperlegible"
            case "ibmPlexSerif": "IBM Plex Serif"
            default: "Literata"
            }
        }
        return switch name {
        case "thmanyahSerif": "Thmanyah Serif Text"
        case "thmanyahSans": "Thmanyah Sans"
        default: "Amiri"
        }
    }
    private var lineHeight: Double {
        let value = (readerSettings["lineSpacing"]?.number ?? 2).rounded()
        return 1.5 + min(max(value, 1), 4) * 0.2
    }
    private var pageMargin: Double {
        let value = (readerSettings["margins"]?.number ?? 2).rounded()
        return 1.0 + min(max(value, 1), 4) * 0.4
    }
    private var readerHeavier: Bool {
        guard case .bool(let value)? = readerSettings["heavier"] else { return false }
        return value
    }
    private var readerJustifies: Bool {
        guard case .bool(let value)? = readerSettings["justify"] else { return true }
        return value
    }
    private func setReaderTheme(_ value: String) { setReader("theme", .string(value)) }
    private func setReader(_ key: String, _ value: MadarData.JSONValue) {
        var settings = readerSettings
        settings[key] = value
        app.set(.object(settings), key: settingsKey)
    }
    private var paragraphMark: MacEPUBMark? {
        paragraph.flatMap { p in p.chapter == chapter ? marks.last { $0.selector == p.selector } : nil }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                Button("إغلاق", action: finish).keyboardShortcut(.cancelAction)
                Spacer()
                Text(book.title).font(MadarTypography.section()).lineLimit(1)
                Spacer()
                if paragraph != nil {
                    // Click a paragraph, then colour it here; the same paragraph highlight as on iPhone (one tap of its colour clears it).
                    Menu {
                        ForEach([("yellow", "أصفر"), ("green", "أخضر"), ("rose", "وردي")], id: \.0) { color, name in
                            Button(paragraphMark?.color == color ? "\(name) ✓" : name) { Task { await highlight(color) } }
                        }
                        if paragraphMark != nil { Divider(); Button("أزل التظليل", role: .destructive) { Task { await removeHighlight() } } }
                        Divider()
                        Button("دوّن حاشية على الفقرة…") { noteDraft = "" }
                    } label: { Label("الفقرة", systemImage: "highlighter") }
                    .fixedSize()
                }
                if let publication, !publication.contents.isEmpty {
                    Menu {
                        ForEach(Array(publication.contents.enumerated()), id: \.offset) { _, entry in
                            Button(entry.title) { jump(to: entry.chapter, fragment: entry.fragment) }
                        }
                    } label: { Image(systemName: "list.bullet") }
                    .menuIndicator(.hidden).fixedSize().accessibilityLabel("الفهرس")
                }
                Menu {
                    ForEach([("auto", "تلقائي"), ("paper", "ورق"), ("warm", "دافئ"), ("calm", "هادئ"), ("night", "ليل"), ("black", "أسود")], id: \.0) { value, title in
                        Button(readerTheme == value ? "\(title) ✓" : title) { setReaderTheme(value) }
                    }
                } label: { Image(systemName: "circle.lefthalf.filled") }
                .menuIndicator(.hidden).fixedSize().accessibilityLabel("لون الصفحة")
                Button { setReader("size", .number(Double(max(1, readerSize - 1)))) } label: { Image(systemName: "textformat.size.smaller") }
                    .keyboardShortcut("-", modifiers: .command).accessibilityLabel("تصغير الخط")
                Button { setReader("size", .number(Double(min(7, readerSize + 1)))) } label: { Image(systemName: "textformat.size.larger") }
                    .keyboardShortcut("=", modifiers: .command).accessibilityLabel("تكبير الخط")
                Button { settingsOpen = true } label: { Image(systemName: "textformat") }
                    .fixedSize().accessibilityLabel("إعدادات عرض الصفحة")
            }
            .buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 12)
            Divider()
            Group {
                if let publication {
                    if let contentRuleList {
                        MacEPUBWebView(publication: publication, chapter: chapter, startProgression: startProgression,
                                       fontScale: fontScale, pageMargin: pageMargin, lineHeight: lineHeight,
                                       readerFontFamily: readerFontFamily, heavier: readerHeavier,
                                       justify: readerJustifies,
                                       writingDirection: book.language == "en" ? "ltr" : "rtl",
                                       paper: readerColors.paper, ink: readerColors.ink, page: page,
                                       contentRuleList: contentRuleList, marks: marks, scrollRequest: scrollRequest)
                    } else {
                        ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
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
                        .font(MadarTypography.caption()).foregroundStyle(readerColors.ink)
                    Spacer()
                    Button { move(by: 1) } label: { Label("الفصل التالي", systemImage: "chevron.left") }
                        .disabled(chapter >= publication.spine.count - 1).keyboardShortcut(.rightArrow, modifiers: .command)
                }
                .buttonStyle(.borderless).padding(.horizontal, 20).padding(.vertical, 10)
            }
        }
        .background(readerColors.paper)
        .foregroundStyle(readerColors.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .task { await open() }
        .sheet(isPresented: Binding(get: { footnote != nil }, set: { if !$0 { footnote = nil } })) {
            VStack(alignment: .leading, spacing: 14) {
                Text("الحاشية").font(MadarTypography.section())
                ScrollView { Text(footnote ?? "").font(MadarTypography.body()).frame(maxWidth: .infinity, alignment: .leading).textSelection(.enabled) }
                    .frame(maxHeight: 320)
                HStack { Spacer(); Button("تمّ") { footnote = nil }.keyboardShortcut(.defaultAction) }
            }
            .padding(24).frame(width: 460).environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: Binding(get: { noteDraft != nil }, set: { if !$0 { noteDraft = nil } })) {
            VStack(alignment: .leading, spacing: 14) {
                Text("حاشية على الفقرة").font(MadarTypography.section())
                if let paragraph { Text(paragraph.text).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(3) }
                TextEditor(text: Binding(get: { noteDraft ?? "" }, set: { noteDraft = $0 }))
                    .font(MadarTypography.body()).frame(minHeight: 140).scrollContentBackground(.hidden)
                    .padding(8).background(theme.surface, in: .rect(cornerRadius: 10))
                HStack {
                    Button("إلغاء") { noteDraft = nil }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("احفظ في دفتر الكتاب") { Task { await savePageNote() } }
                        .keyboardShortcut(.defaultAction)
                        .disabled((noteDraft ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
            .padding(24).frame(width: 460).environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $settingsOpen) {
            MacMihbaraReaderSettingsSheet(bookIsEnglish: book.language == "en", settings: readerSettings,
                                           set: setReader, reset: { app.reset([settingsKey]) })
                .frame(minWidth: 420, minHeight: 310)
        }
        .sheet(item: $wordCard, onDismiss: presentWordCardDestination) { selected in
            MacMihbaraWordCardSheet(app: app, book: book, selection: selected,
                                    locatorJSON: locator(for: selected),
                                    onQuote: { if let card = makeQuoteCard(from: selected) { wordCardDestination = .quote(card) } },
                                    onNote: { wordCardDestination = .note(selected) })
                .frame(minWidth: 460, minHeight: 460)
        }
        .sheet(item: $quoteCard) { card in MacMihbaraQuoteCardSheet(card: card) }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if let selection {
                HStack(spacing: 12) {
                    Text(selection.selectedText).font(MadarTypography.caption()).lineLimit(1)
                    Spacer(minLength: 8)
                    Button("بطاقة الكلمة") { wordCard = selection }
                    Button("بطاقة اقتباس") { quoteCard = makeQuoteCard(from: selection) }
                }
                .buttonStyle(.borderless).padding(.horizontal, 18).padding(.vertical, 10)
                .background(readerColors.paper.opacity(0.96))
                .overlay(alignment: .top) { Divider() }
            }
        }
        .onDisappear { save(); endSession(at: Date()); publication?.discard() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { beginSession(at: Date()) } else { save(); endSession(at: Date()) }
        }
    }

    private func open() async {
        do {
            contentRuleList = try await MacEPUBWebPolicy.blockRemoteContent()
            let data = try await AppMihbaraService(app: app).epubDataOffMain(for: book)
            let opened = try await Task.detached { try MacEPUB(data: data) }.value
            let saved = initialLocatorJSON ?? book.locatorJSON.flatMap { String(data: $0, encoding: .utf8) }
            if let saved, let place = opened.place(fromLocatorJSON: saved) {
                chapter = place.chapter; startProgression = place.progression; page.fragment = place.fragment
            } else if let volume, volume > 0, opened.spine.count > 1 {
                chapter = min(opened.spine.count - 1, Int((Double(volume) / Double(max(volume + 1, 1))) * Double(opened.spine.count)))
            }
            // The session may close or the window may resign before WebKit finishes its first layout.
            // Seed the restored location before the clock can observe or save it.
            page.progression = startProgression
            publication = opened
            page.onChange = { [self] progression in observe(progression) }
            page.onParagraph = { [self] tapped in if tapped.chapter == chapter { paragraph = tapped } }
            page.onSelection = { [self] tapped in if tapped.chapter == chapter { selection = tapped } }
            page.onNote = { [self] text in footnote = text }
            page.onLink = { [self] index, fragment in jump(to: index, fragment: fragment) }
            reloadHighlights()
            beginSession(at: Date())
        } catch {
            failure = "تعذّر فتح الكتاب على الماك. \(madarUserMessage(error))"
        }
    }

    private func move(by delta: Int) {
        guard let publication else { return }
        save()
        paragraph = nil
        selection = nil
        wordCard = nil
        chapter = min(max(chapter + delta, 0), publication.spine.count - 1)
        startProgression = delta < 0 ? 1 : 0
        page.fragment = nil
        page.progression = startProgression
        observe(startProgression, jump: true)
    }

    private func reloadHighlights() { highlights = (try? AppMihbaraService(app: app).highlights(for: book.id)) ?? [] }

    private func highlight(_ color: String) async {
        guard let publication, let paragraph else { return }
        if paragraphMark?.color == color { await removeHighlight(); return }
        guard let locator = publication.locatorJSON(chapter: paragraph.chapter, progression: page.progression,
                                                    selector: paragraph.selector, text: paragraph.text) else { return }
        do {
            try await app.executeBookCommand("highlight.save", payload: [
                "id": .string((paragraphMark?.id ?? UUID()).uuidString), "bookID": .string(book.id.uuidString),
                "locator": .string(locator), "color": .string(color)
            ], undoMessage: "ظُلّلت الفقرة")
            reloadHighlights()
        } catch { app.errorMessage = madarUserMessage(error) }
    }

    /// The same «حاشية الكتاب» record as the iPhone's word card: the note text with the paragraph's locator.
    private func savePageNote() async {
        guard let publication, let paragraph, let text = noteDraft?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty,
              let locator = publication.locatorJSON(chapter: paragraph.chapter, progression: page.progression,
                                                    selector: paragraph.selector, text: paragraph.text) else { return }
        do {
            try await app.executeBookCommand("notebook.savePage", payload: [
                "id": .string(UUID().uuidString), "bookID": .string(book.id.uuidString), "text": .string(text), "locator": .string(locator)
            ], undoMessage: "دُوّنت في حاشية الكتاب")
            noteDraft = nil
        } catch { app.errorMessage = madarUserMessage(error) }
    }

    private func removeHighlight() async {
        guard let id = paragraphMark?.id else { return }
        do {
            try await app.executeBookCommand("highlight.delete", payload: ["id": .string(id.uuidString)], undoMessage: "أُزيل التظليل")
            reloadHighlights()
        } catch { app.errorMessage = madarUserMessage(error) }
    }

    private func jump(to target: Int, fragment: String? = nil) {
        guard let publication, publication.spine.indices.contains(target) else { return }
        save()
        paragraph = nil
        selection = nil
        wordCard = nil
        chapter = target
        startProgression = 0
        page.fragment = fragment
        scrollRequest += 1
        page.progression = 0
        observe(0, jump: true)
    }

    private func beginSession(at now: Date) {
        guard let publication, clock == nil, scenePhase == .active else { return }
        clock = ActiveReadingClock(startedAt: now)
        sessionID = UUID()
        sessionStart = now
        sessionStartChapter = chapter
        sessionStartProgression = page.progression
        positions = ReadingPositionProgress(startingAt: publication.position(chapter: chapter, progression: page.progression), at: now)
        sessionDayStamp = dayStamp(at: now)
        lastSample = now
    }

    /// The reading day a moment belongs to (`core.dayStart`, place and time zone), as the iPhone readers stamp it; a session that
    /// crosses into a new day is saved in two parts so each day's wird counts only its own minutes.
    private func dayStamp(at date: Date) -> String? {
        let context = ModelContext(app.container)
        guard let day = try? DiaryLineRenderer.today(context: context, now: date),
              let prayers = try? PrayerRepository(context: context) else { return nil }
        return day.description + "|" + prayers.place(at: date).timeZoneID + "|" + app.string("core.dayStart")
    }

    private func splitAtDayBoundary(_ now: Date) {
        defer { lastSample = now }
        guard clock != nil, let previous = sessionDayStamp, let last = lastSample, let stamp = dayStamp(at: now), stamp != previous,
              let boundary = ReadingSessionBoundaryFinder.firstTransition(from: previous, after: last, through: now, stampAt: { dayStamp(at: $0) })
        else { return }
        endSession(at: boundary.endsPreviousAt)
        beginSession(at: boundary.startsNextAt)
    }

    private func observe(_ progression: Double, jump: Bool = false) {
        let now = Date()
        splitAtDayBoundary(now)
        guard let publication, var clock else { return }
        clock.advance(to: now)
        clock.interaction(at: now)
        self.clock = clock
        positions.observe(position: publication.position(chapter: chapter, progression: progression), at: now, explicitJump: jump)
    }

    private func endSession(at now: Date) {
        if now.timeIntervalSince(lastSample ?? now) > 0 { splitAtDayBoundary(now) }
        guard let publication, var clock, let sessionStart else { return }
        clock.advance(to: now)
        self.clock = nil
        let active = min(86_400, clock.activeSeconds)
        guard active >= 60,
              let first = publication.locatorJSON(chapter: sessionStartChapter, progression: sessionStartProgression),
              let last = publication.locatorJSON(chapter: chapter, progression: page.progression, fragment: page.fragment) else { return }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let startTotal = publication.totalProgression(chapter: sessionStartChapter, progression: sessionStartProgression)
        let endTotal = max(startTotal, publication.totalProgression(chapter: chapter, progression: page.progression))
        MihbaraReadingSaveCoordinator.forSession(app).enqueue(sessionID: sessionID, payload: [
            "id": .string(sessionID.uuidString), "bookID": .string(book.id.uuidString),
            "start": .string(formatter.string(from: sessionStart)), "end": .string(formatter.string(from: now)),
            "activeSeconds": .number(Double(active)), "fromPage": .number(0), "toPage": .number(0),
            "startLocator": .string(first), "endLocator": .string(last),
            "startProgression": .number(startTotal), "endProgression": .number(endTotal),
            "pagesCounted": .number(Double(positions.pagesCounted))
        ])
    }

    private func save() {
        guard let publication, let json = publication.locatorJSON(chapter: chapter, progression: page.progression, fragment: page.fragment) else { return }
        MihbaraReadingSaveCoordinator.forSession(app).enqueueLocatorJSON(json, bookID: book.id)
    }

    private func locator(for selected: MacEPUBSelection) -> String? {
        publication?.locatorJSON(chapter: selected.chapter, progression: page.progression,
                                 selector: selected.selector, text: selected.paragraphText)
    }

    private func presentWordCardDestination() {
        guard let destination = wordCardDestination else { return }
        wordCardDestination = nil
        switch destination {
        case .quote(let card): quoteCard = card
        case .note(let selected):
            paragraph = .init(chapter: selected.chapter, selector: selected.selector, text: selected.paragraphText)
            noteDraft = ""
        }
    }

    private func makeQuoteCard(from selected: MacEPUBSelection) -> MihbaraQuoteCardContent? {
        let quote = selected.paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return nil }
        return MihbaraQuoteCardContent(quote: quote, bookTitle: book.title, author: book.author,
                                       pageLabel: nil, turathID: book.turathID,
                                       digits: AppMihbaraService(app: app).digits)
    }

    private func finish() { save(); close() }
}

/// The scroll position the web view reports, kept outside SwiftUI state so a scroll does not redraw the reader.
@MainActor final class MacEPUBPage {
    var progression = 0.0
    var fragment: String?
    var onChange: ((Double) -> Void)?
    var onParagraph: ((MacEPUBParagraph) -> Void)?
    var onSelection: ((MacEPUBSelection) -> Void)?
    var onNote: ((String) -> Void)?
    var onLink: ((Int, String?) -> Void)?
    func report(_ value: Double) { progression = value; fragment = nil; onChange?(value) }
}

private enum MacWordCardDestination {
    case quote(MihbaraQuoteCardContent)
    case note(MacEPUBSelection)
}

struct MacEPUBSelection: Identifiable, Equatable {
    let id = UUID()
    let chapter: Int
    let selectedText: String
    let selector: String
    let paragraphText: String
}

/// An unpacked EPUB: the folder it lives in and its reading order (paths relative to the publication root, as Readium writes them).
struct MacEPUB: Sendable {
    let root: URL
    let spine: [String]
    /// Each spine file's size in bytes, used to weigh progress across chapters and to count positions as Readium does.
    let sizes: [Int]
    /// The book's own table of contents (EPUB 3 nav, else the EPUB 2 NCX), each entry pointing at a spine chapter.
    let contents: [MacEPUBContentsEntry]

    init(data: Data) throws {
        let zip = try ZIPReader(data: data)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("mihbara-mac-" + UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var completed = false
        defer { if !completed { try? FileManager.default.removeItem(at: root) } }
        var writtenPaths = Set<String>()
        for member in zip.members where !member.isDirectory && !member.isSymbolicLink && !member.isEncrypted {
            guard let path = Self.safePath(member.path), !path.isEmpty,
                  writtenPaths.insert(path).inserted else { continue }
            let target = root.appending(path: path, directoryHint: .notDirectory)
            try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
            try zip.read(member).write(to: target, options: .atomic)
        }
        let container = try Data(contentsOf: root.appendingPathComponent("META-INF/container.xml"))
        guard let rawOPFPath = MacEPUBXML.attribute("full-path", ofFirst: "rootfile", in: container),
              let opfPath = Self.safePath(rawOPFPath) else { throw MacEPUBError.unreadable }
        let opf = try Data(contentsOf: root.appending(path: opfPath, directoryHint: .notDirectory))
        let parsed = MacEPUBXML.spine(in: opf)
        let spine = parsed.order.compactMap { idref -> String? in
            guard let href = parsed.manifest[idref] else { return nil }
            return Self.resolveReference(href, relativeTo: opfPath)?.path
        }
        guard !spine.isEmpty else { throw MacEPUBError.unreadable }
        self.root = root
        self.spine = spine
        var navPath: String?
        if let nav = parsed.nav { navPath = Self.resolveReference(nav, relativeTo: opfPath)?.path }
        else if let ncx = parsed.ncx { navPath = Self.resolveReference(ncx, relativeTo: opfPath)?.path }
        self.contents = navPath.flatMap { path in
            (try? String(contentsOf: root.appending(path: path, directoryHint: .notDirectory), encoding: .utf8))
                .map { MacEPUB.contents(in: $0, at: path, spine: spine) }
        } ?? []
        self.sizes = spine.map { path in
            ((try? FileManager.default.attributesOfItem(atPath: root.appending(path: path, directoryHint: .notDirectory).path)[.size]) as? Int).map { max($0, 1) } ?? 1
        }
        completed = true
    }

    func url(chapter: Int) -> URL { root.appending(path: spine[chapter], directoryHint: .notDirectory) }

    /// Resolves an EPUB reference inside the extracted root. Percent decoding happens before
    /// normalization so encoded dot segments cannot bypass the root boundary.
    static func safePath(_ rawPath: String, relativeTo base: String = "") -> String? {
        let decoded = rawPath.removingPercentEncoding ?? rawPath
        guard !decoded.hasPrefix("/"), !decoded.contains("\\"), !decoded.contains("\0") else { return nil }
        var parts = base.split(separator: "/").map(String.init)
        for component in decoded.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch component {
            case "", ".": continue
            case "..":
                guard !parts.isEmpty else { return nil }
                parts.removeLast()
            default: parts.append(component)
            }
        }
        return parts.joined(separator: "/")
    }

    /// Resolves a link relative to a publication file while retaining its in-document fragment.
    static func resolveReference(_ rawReference: String, relativeTo baseFile: String) -> (path: String, fragment: String?)? {
        guard let components = URLComponents(string: rawReference), components.scheme == nil, components.host == nil else { return nil }
        let folder = (baseFile as NSString).deletingLastPathComponent
        let referencePath = components.percentEncodedPath.isEmpty ? (baseFile as NSString).lastPathComponent : components.percentEncodedPath
        guard let path = safePath(referencePath, relativeTo: folder == "." ? "" : folder), !path.isEmpty else { return nil }
        return (path, components.percentEncodedFragment?.removingPercentEncoding)
    }

    /// Opens a staged EPUB the way the reader will, then removes the unpacked copy.
    @concurrent static func validate(_ file: URL) async throws {
        let opened = try MacEPUB(data: Data(contentsOf: file, options: .mappedIfSafe))
        opened.discard()
    }

    func discard() { try? FileManager.default.removeItem(at: root) }

    /// Reads the entries of a nav (`<a href>`) or NCX (`<navLabel><text>` + `<content src>`) file and keeps those that land
    /// on a spine chapter, in book order of appearance.
    static func contents(in source: String, at path: String, spine: [String]) -> [MacEPUBContentsEntry] {
        let pattern = path.hasSuffix(".ncx")
            ? "<text>([\\s\\S]*?)</text>[\\s\\S]*?<content[^>]*src=\"([^\"]+)\""
            : "<a[^>]*href=\"([^\"]+)\"[^>]*>([\\s\\S]*?)</a>"
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return [] }
        let ns = source as NSString
        return regex.matches(in: source, range: NSRange(location: 0, length: ns.length)).compactMap { match in
            let first = ns.substring(with: match.range(at: 1)), second = ns.substring(with: match.range(at: 2))
            let (href, label) = path.hasSuffix(".ncx") ? (second, first) : (first, second)
            guard let reference = resolveReference(href, relativeTo: path),
                  let chapter = spine.firstIndex(of: reference.path) else { return nil }
            let title = plainText(label)
            return title.isEmpty ? nil : MacEPUBContentsEntry(title: title, chapter: chapter, fragment: reference.fragment)
        }
    }

    /// A chapter's readable text: markup, scripts and styles removed, entities for spaces and brackets decoded, spaces collapsed.
    static func plainText(_ html: String) -> String {
        var text = html.replacingOccurrences(of: "<(head|script|style)[^>]*>[\\s\\S]*?</\\1>", with: " ", options: .regularExpression)
        text = text.replacingOccurrences(of: "<[^>]+>", with: " ", options: .regularExpression)
        for (entity, value) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
            text = text.replacingOccurrences(of: entity, with: value)
        }
        return text.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespaces)
    }

    /// The chapter and paragraph selector of a saved highlight's locator, when it lands on this book's spine.
    func mark(fromLocatorJSON data: Data) -> (chapter: Int, selector: String)? {
        guard let json = String(data: data, encoding: .utf8), let place = place(fromLocatorJSON: json),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let selector = (object["locations"] as? [String: Any])?["cssSelector"] as? String, !selector.isEmpty else { return nil }
        return (place.chapter, selector)
    }

    func place(fromLocatorJSON json: String) -> (chapter: Int, progression: Double, fragment: String?)? {
        guard let object = try? JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any],
              let href = object["href"] as? String else { return nil }
        guard let components = URLComponents(string: href) else { return nil }
        var locatorPath = components.percentEncodedPath
        if locatorPath.hasPrefix("/") { locatorPath.removeFirst() }
        guard let safe = Self.safePath(locatorPath),
              let index = spine.firstIndex(of: safe) ?? spine.firstIndex(where: { $0.hasSuffix("/" + safe) || safe.hasSuffix("/" + $0) }) else { return nil }
        let locations = object["locations"] as? [String: Any]
        return (index, min(max((locations?["progression"] as? Double) ?? 0, 0), 1), components.percentEncodedFragment?.removingPercentEncoding)
    }

    func totalProgression(chapter: Int, progression: Double) -> Double {
        let all = Double(sizes.reduce(0, +))
        let before = Double(sizes.prefix(chapter).reduce(0, +))
        return min(max((before + min(max(progression, 0), 1) * Double(sizes[chapter])) / max(all, 1), 0), 1)
    }

    func position(chapter: Int, progression: Double) -> Int {
        let before = sizes.prefix(chapter).reduce(0, +)
        return (before + Int(min(max(progression, 0), 1) * Double(sizes[chapter]))) / 1024 + 1
    }

    func locatorJSON(chapter: Int, progression: Double, fragment: String? = nil, selector: String? = nil, text: String? = nil) -> String? {
        let p = min(max(progression, 0), 1)
        let total = totalProgression(chapter: chapter, progression: p)
        var locations: [String: Any] = ["progression": p, "totalProgression": total]
        if let selector { locations["cssSelector"] = selector }
        let encodedFragment = fragment?.addingPercentEncoding(withAllowedCharacters: .urlFragmentAllowed)
        let href = spine[chapter] + (encodedFragment.map { "#" + $0 } ?? "")
        var object: [String: Any] = ["href": href, "type": "application/xhtml+xml", "locations": locations]
        if let text, !text.isEmpty { object["text"] = ["highlight": text] }
        guard let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys, .withoutEscapingSlashes]) else { return nil }
        return String(data: data, encoding: .utf8)
    }
}

/// The paragraph the reader last clicked: its CSS selector (the same kind Readium stores) and its text.
struct MacEPUBParagraph: Equatable { let chapter: Int; let selector: String; let text: String }

/// A saved paragraph highlight on the open chapter, with its tint as CSS.
struct MacEPUBMark: Equatable {
    let id: UUID
    let selector: String
    let color: String
    var tint: String {
        switch color { case "green": "rgba(120,190,130,0.35)"; case "rose": "rgba(235,140,155,0.35)"; default: "rgba(245,205,80,0.40)" }
    }
}

struct MacEPUBContentsEntry: Hashable, Sendable {
    let title: String
    let chapter: Int
    let fragment: String?
}

enum MacEPUBError: LocalizedError {
    case unreadable
    case webContentPolicyUnavailable
    var errorDescription: String? {
        switch self {
        case .unreadable: "ملف الكتاب لا يحوي ترتيب قراءة صالحًا."
        case .webContentPolicyUnavailable: "تعذّر تأمين محتوى الكتاب على الماك."
        }
    }
}

@MainActor private enum MacEPUBWebPolicy {
    private static var cachedRules: WKContentRuleList?

    static func blockRemoteContent() async throws -> WKContentRuleList {
        if let cachedRules { return cachedRules }
        guard let store = WKContentRuleListStore.default() else { throw MacEPUBError.webContentPolicyUnavailable }
        let json = #"[{"trigger":{"url-filter":"^https?://"},"action":{"type":"block"}}]"#
        guard let rules = try await store.compileContentRuleList(forIdentifier: "madar-epub-no-network", encodedContentRuleList: json) else {
            throw MacEPUBError.webContentPolicyUnavailable
        }
        cachedRules = rules
        return rules
    }
}

/// A small OPF/container reader: the rootfile path, the manifest (id → href) and the spine order.
private final class MacEPUBXML: NSObject, XMLParserDelegate {
    private var wanted = ""
    private var attributeName = ""
    private var found: String?
    private(set) var manifest: [String: String] = [:]
    private(set) var nav: String?
    private(set) var ncx: String?
    private var order: [String] = []

    static func attribute(_ name: String, ofFirst element: String, in data: Data) -> String? {
        let reader = MacEPUBXML(); reader.wanted = element; reader.attributeName = name
        let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
        return reader.found
    }

    static func spine(in data: Data) -> (order: [String], manifest: [String: String], nav: String?, ncx: String?) {
        let reader = MacEPUBXML()
        let parser = XMLParser(data: data); parser.delegate = reader; parser.parse()
        return (reader.order, reader.manifest, reader.nav, reader.ncx)
    }

    func parser(_ parser: XMLParser, didStartElement elementName: String, namespaceURI: String?, qualifiedName: String?,
                attributes: [String: String] = [:]) {
        let local = elementName.split(separator: ":").last.map(String.init) ?? elementName
        if !wanted.isEmpty {
            if local == wanted, found == nil { found = attributes[attributeName] }
            return
        }
        if local == "item", let id = attributes["id"], let href = attributes["href"] {
            manifest[id] = href
            if attributes["properties"]?.split(separator: " ").contains("nav") == true { nav = href }
            if attributes["media-type"] == "application/x-dtbncx+xml" { ncx = href }
        }
        if local == "itemref", let idref = attributes["idref"], attributes["linear"] != "no" { order.append(idref) }
    }
}

/// One chapter in a WKWebView: right-to-left, the room's paper and ink, the chosen size, and the scroll position reported back.
private struct MacEPUBWebView: NSViewRepresentable {
    let publication: MacEPUB
    let chapter: Int
    let startProgression: Double
    let fontScale: Double
    let pageMargin: Double
    let lineHeight: Double
    let readerFontFamily: String
    let heavier: Bool
    let justify: Bool
    let writingDirection: String
    let paper: Color
    let ink: Color
    let page: MacEPUBPage
    let contentRuleList: WKContentRuleList
    var marks: [MacEPUBMark] = []
    var scrollRequest = 0

    func makeCoordinator() -> Coordinator { Coordinator(page: page) }

    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        configuration.userContentController.add(contentRuleList)
        configuration.defaultWebpagePreferences.allowsContentJavaScript = false
        configuration.userContentController.add(context.coordinator, name: "place")
        configuration.userContentController.add(context.coordinator, name: "paragraph")
        configuration.userContentController.add(context.coordinator, name: "selection")
        configuration.userContentController.add(context.coordinator, name: "note")
        let view = WKWebView(frame: .zero, configuration: configuration)
        view.navigationDelegate = context.coordinator
        view.setValue(false, forKey: "drawsBackground")
        return view
    }

    func updateNSView(_ view: WKWebView, context: Context) {
        let coordinator = context.coordinator
        coordinator.style = style
        coordinator.publication = publication
        coordinator.startProgression = startProgression
        coordinator.startFragment = page.fragment
        let scrollChanged = coordinator.scrollRequest != scrollRequest
        let fragmentChanged = coordinator.fragment != page.fragment
        coordinator.scrollRequest = scrollRequest
        coordinator.fragment = page.fragment
        let marksChanged = coordinator.marks != marks
        coordinator.marks = marks
        if coordinator.loadedChapter != chapter {
            coordinator.loadedChapter = chapter
            view.loadFileURL(publication.url(chapter: chapter), allowingReadAccessTo: publication.root)
        } else {
            let scroll = scrollChanged || fragmentChanged ? Self.scrollScript(progression: startProgression, fragment: page.fragment) : ""
            view.evaluateJavaScript(coordinator.styleScript + (marksChanged ? coordinator.marksScript : "") + scroll)
        }
    }

    static func dismantleNSView(_ view: WKWebView, coordinator: Coordinator) {
        view.configuration.userContentController.removeScriptMessageHandler(forName: "place")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "paragraph")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "selection")
        view.configuration.userContentController.removeScriptMessageHandler(forName: "note")
    }

    private var style: String {
        """
        html:not([dir]){direction:\(writingDirection)}
        html,body{background:\(Self.css(paper))!important;color:\(Self.css(ink))!important}
        body{max-width:44em;margin:0 auto!important;padding:\(pageMargin)em!important;font-size:\(Int(fontScale * 120))%!important;line-height:\(lineHeight)!important;font-family:'\(readerFontFamily)',serif!important;font-weight:\(heavier ? 600 : 400)!important;text-align:\(justify ? "justify" : "start")!important}
        img{max-width:100%;height:auto}
        """
    }

    private static func scrollScript(progression: Double, fragment: String?) -> String {
        let encoded = fragment.flatMap { try? JSONEncoder().encode($0) }.flatMap { String(data: $0, encoding: .utf8) } ?? "null"
        return """
        (function(){var target=\(encoded);var node=target?document.getElementById(target):null;
        if(node){node.scrollIntoView();}else{var e=document.scrollingElement;e.scrollTop=Math.max(e.scrollHeight-innerHeight,0)*\(min(max(progression,0),1));}})();
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
        var startFragment: String?
        var fragment: String?
        var marks: [MacEPUBMark] = []
        var scrollRequest = 0
        var publication: MacEPUB?
        init(page: MacEPUBPage) { self.page = page }

        /// The spine path a link inside the open chapter points to, and its fragment.
        func resolve(_ url: URL) -> (path: String, fragment: String?)? {
            guard let publication, url.isFileURL else { return nil }
            let root = publication.root.standardizedFileURL.path
            let full = url.standardizedFileURL.path
            let prefix = root.hasSuffix("/") ? root : root + "/"
            guard full.hasPrefix(prefix), let path = MacEPUB.safePath(String(full.dropFirst(prefix.count))) else { return nil }
            return (path, url.fragment)
        }

        /// A footnote in another file of the book: the text of the element with that id.
        func noteText(_ href: String) -> String? {
            guard let publication, loadedChapter >= 0,
                  let reference = MacEPUB.resolveReference(href, relativeTo: publication.spine[loadedChapter]), let fragment = reference.fragment,
                  let html = try? String(contentsOf: publication.root.appending(path: reference.path, directoryHint: .notDirectory), encoding: .utf8),
                  let regex = try? NSRegularExpression(pattern: "<(\\w+)[^>]*id=\"\(NSRegularExpression.escapedPattern(for: fragment))\"[^>]*>([\\s\\S]*?)</\\1>")
            else { return nil }
            let ns = html as NSString
            guard let match = regex.firstMatch(in: html, range: NSRange(location: 0, length: ns.length)) else { return nil }
            let text = MacEPUB.plainText(ns.substring(with: match.range(at: 2)))
            return text.isEmpty ? nil : text
        }

        /// Paints each saved paragraph highlight (iPhone or Mac) by its CSS selector, after clearing the previous paint.
        var marksScript: String {
            let items = marks.map { mark -> String in
                let selector = mark.selector.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "'", with: "\\'")
                return "['\(selector)','\(mark.tint)']"
            }.joined(separator: ",")
            return """
            (function(){document.querySelectorAll('[data-madar-mark]').forEach(function(e){e.style.backgroundColor='';e.removeAttribute('data-madar-mark');});
            [\(items)].forEach(function(m){try{var e=document.querySelector(m[0]);if(e){e.style.backgroundColor=m[1];e.style.borderRadius='4px';e.setAttribute('data-madar-mark','1');}}catch(x){}});})();
            """
        }

        var styleScript: String {
            let escaped = style.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "`", with: "\\`")
            return """
            (function(){var s=document.getElementById('madar-style');if(!s){s=document.createElement('style');s.id='madar-style';document.head.appendChild(s);}s.textContent=`\(escaped)`;})();
            """
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            let start = min(max(startProgression, 0), 1)
            webView.evaluateJavaScript("window.__madarChapter=\(loadedChapter);" + styleScript + MacEPUBWebView.scrollScript(progression: start, fragment: startFragment) + """
            (function(){var e=document.scrollingElement;
            var t;addEventListener('scroll',function(){clearTimeout(t);t=setTimeout(function(){var m=Math.max(e.scrollHeight-innerHeight,1);
            window.webkit.messageHandlers.place.postMessage(e.scrollTop/m);},250);});
            function sel(el){var parts=[];while(el&&el!==document.documentElement){var i=1,s=el;while((s=s.previousElementSibling))i++;parts.unshift(':nth-child('+i+')');el=el.parentElement;}return ':root > '+parts.join(' > ');}
            addEventListener('click',function(ev){var a=ev.target.closest('a[href]');if(!a)return;var h=a.getAttribute('href')||'';
            var type=(a.getAttribute('epub:type')||a.getAttributeNS('http://www.idpf.org/2007/ops','type')||'')+' '+(a.getAttribute('role')||'');
            var hash=h.indexOf('#')>=0?decodeURIComponent(h.split('#')[1]):'';var local=h.charAt(0)==='#';var target=local&&hash?document.getElementById(hash):null;
            var isNote=/noteref|doc-noteref/.test(type)||(target&&/aside|footnote|endnote|note/i.test((target.tagName||'')+' '+(target.getAttribute('epub:type')||'')+' '+(target.className||'')));
            if(!isNote)return;ev.preventDefault();ev.stopPropagation();
            window.webkit.messageHandlers.note.postMessage(target?{text:(target.innerText||'').trim()}:{href:h});},true);
            addEventListener('click',function(ev){var el=ev.target.closest('p,li,blockquote,h1,h2,h3,h4,h5,h6,dd,dt,figcaption');if(!el)return;
            window.webkit.messageHandlers.paragraph.postMessage({chapter:window.__madarChapter,selector:sel(el),text:(el.innerText||'').trim().slice(0,4000)});});
            function selected(){var selection=window.getSelection();if(!selection||selection.isCollapsed)return;var text=selection.toString().trim();if(!text)return;
            var node=selection.getRangeAt(0).commonAncestorContainer;if(node.nodeType!==1)node=node.parentElement;var el=node&&node.closest('p,li,blockquote,h1,h2,h3,h4,h5,h6,dd,dt,figcaption,div');
            if(!el||el===document.body||el===document.documentElement)return;
            window.webkit.messageHandlers.selection.postMessage({chapter:window.__madarChapter,selectedText:text.slice(0,300),selector:sel(el),text:(el.innerText||'').trim().slice(0,4000)});}
            addEventListener('mouseup',function(){setTimeout(selected,40);});addEventListener('keyup',function(){setTimeout(selected,40);});})();
            """ + marksScript)
            page.progression = start
        }

        func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
            if message.name == "note", let body = message.body as? [String: Any] {
                let text = body["text"] as? String ?? (body["href"] as? String).flatMap(noteText) ?? ""
                MainActor.assumeIsolated { if !text.isEmpty { page.onNote?(text) } }
                return
            }
            if message.name == "paragraph", let body = message.body as? [String: Any], let selector = body["selector"] as? String {
                let text = body["text"] as? String ?? ""
                let chapter = body["chapter"] as? Int ?? loadedChapter
                MainActor.assumeIsolated { page.onParagraph?(MacEPUBParagraph(chapter: chapter, selector: selector, text: text)) }
                return
            }
            if message.name == "selection", let body = message.body as? [String: Any],
               let selectedText = body["selectedText"] as? String, let selector = body["selector"] as? String {
                let text = body["text"] as? String ?? selectedText
                let chapter = body["chapter"] as? Int ?? loadedChapter
                MainActor.assumeIsolated { page.onSelection?(MacEPUBSelection(chapter: chapter, selectedText: selectedText, selector: selector, paragraphText: text)) }
                return
            }
            if let value = message.body as? Double { MainActor.assumeIsolated { page.report(min(max(value, 0), 1)) } }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction) async -> WKNavigationActionPolicy {
            // Only the book's own files open inside the reader; outside links are not followed. A link to another chapter moves
            // the reader there (so the saved place and reading time follow), a link inside this chapter scrolls in place.
            guard let url = action.request.url, url.isFileURL else { return .cancel }
            guard action.navigationType == .linkActivated else { return .allow }
            guard let target = resolve(url), let publication else { return .cancel }
            let currentPath = loadedChapter >= 0 ? publication.spine[loadedChapter] : ""
            if target.path == currentPath { return .allow }
            if let index = publication.spine.firstIndex(of: target.path) {
                await MainActor.run { page.onLink?(index, target.fragment) }
            }
            return .cancel
        }
    }
}

private extension Color {
    init(macReaderHex hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: Double((value >> 16) & 0xFF) / 255, green: Double((value >> 8) & 0xFF) / 255, blue: Double(value & 0xFF) / 255)
    }
}
