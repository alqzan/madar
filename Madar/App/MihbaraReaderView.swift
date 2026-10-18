import SwiftUI
import Observation
import UIKit
import WebKit
import SwiftData
import AVFoundation
import ReadiumShared
import ReadiumStreamer
import ReadiumNavigator
import MadarCore
import MadarDesign
import MadarData
import MadarCommands
import MadarPrayer

/// Retained by the app session, rather than a reader subtree that an app lock can remove.
@MainActor final class MihbaraReadingSaveCoordinator {
    private static let owners = NSMapTable<AppSession, MihbaraReadingSaveCoordinator>.weakToStrongObjects()
    private weak var app: AppSession?
    private var sessions = PendingReadingSessionQueue()
    private struct LocatorWrite {
        let bookID: UUID
        let commandID: UUID
        let payload: [String: MadarCore.JSONValue]
    }
    private var pendingLocators: [UUID: LocatorWrite] = [:]
    private var failedLocatorEpoch: Int?
    private var writing: Task<Void, Never>?
    private var wasAuthorized = false

    static func forSession(_ app: AppSession) -> MihbaraReadingSaveCoordinator {
        if let existing = owners.object(forKey: app) { return existing }
        let coordinator = MihbaraReadingSaveCoordinator(app: app)
        owners.setObject(coordinator, forKey: app)
        return coordinator
    }

    private init(app: AppSession) {
        self.app = app
        observeAuthorization()
    }

    var canWrite: Bool {
        guard let app else { return false }
        return app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized
    }
    var hasPending: Bool { !sessions.isEmpty || !pendingLocators.isEmpty }
    private var canAttempt: Bool {
        sessions.canAttempt || (sessions.isEmpty && !pendingLocators.isEmpty && failedLocatorEpoch != sessions.authorizationEpoch)
    }

    private func observeAuthorization() {
        let authorized = withObservationTracking {
            canWrite
        } onChange: { [weak self] in
            Task { @MainActor in self?.observeAuthorization() }
        }
        if authorized && !wasAuthorized {
            sessions.authorizedForegroundReturned()
        }
        wasAuthorized = authorized
        if authorized { flush() }
    }

    func enqueue(sessionID: UUID, payload: [String: MadarCore.JSONValue]) {
        sessions.enqueue(sessionID: sessionID, payload: payload)
        flush()
    }

    func enqueueLocator(_ locator: Locator, bookID: UUID) {
        do {
            let json = try locator.jsonString()
            enqueueLocatorJSON(json, bookID: bookID)
        } catch { app?.errorMessage = error.localizedDescription }
    }

    func enqueueLocatorJSON(_ json: String, bookID: UUID) {
        pendingLocators[bookID] = LocatorWrite(bookID: bookID, commandID: UUID(), payload: ["id": .string(bookID.uuidString), "locator": .string(json)])
        flush()
    }

    func waitForCurrentAttempt() async { await writing?.value }

    func flush() {
        guard writing == nil, canWrite, canAttempt, let app else { return }
        writing = Task { @MainActor [self] in
            defer {
                writing = nil
                // An authorization return during an in-flight failure grants a fresh attempt.
                if canWrite && canAttempt { flush() }
            }
            while canWrite {
                if let write = sessions.beginNext() {
                    do {
                        try await app.executeBookCommand("reading.saveSession", payload: write.payload, id: write.commandID)
                        sessions.finish(commandID: write.commandID, acknowledged: true)
                    } catch {
                        sessions.finish(commandID: write.commandID, acknowledged: false)
                        app.errorMessage = error.localizedDescription
                        break
                    }
                } else if !sessions.isEmpty {
                    break
                } else if let locator = pendingLocators.values.first, failedLocatorEpoch != sessions.authorizationEpoch {
                    let epoch = sessions.authorizationEpoch
                    do {
                        try await app.executeBookCommand("book.setLocator", payload: locator.payload, id: locator.commandID)
                        if pendingLocators[locator.bookID]?.commandID == locator.commandID {
                            pendingLocators[locator.bookID] = nil
                        }
                        failedLocatorEpoch = nil
                    } catch {
                        failedLocatorEpoch = epoch
                        app.errorMessage = error.localizedDescription
                        break
                    }
                } else { break }
            }
        }
    }
}

private struct MihbaraPrintPage: Identifiable, Equatable {
    var id: String { "\(href.string)#\(fragment ?? "")-\(label)" }
    let href: AnyURL
    let fragment: String?
    let label: String
}

struct MihbaraReaderView: View {
    let app: AppSession
    let book: MihbaraBook
    let close: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var publication: Publication?
    @State private var localURL: URL?
    @State private var initialLocator: Locator?
    @State private var currentLocator: Locator?
    @State private var navigatorController: EPUBNavigatorViewController?
    @State private var printPages: [MihbaraPrintPage] = []
    @State private var printMarkedLocator: Locator?
    @State private var positionCount = 0
    @State private var showingContents = false
    @State private var showingReaderSettings = false
    @State private var speechSynthesizer = AVSpeechSynthesizer()
    @State private var isSpeaking = false
    @State private var readingClock: ActiveReadingClock?
    @State private var positionProgress = ReadingPositionProgress()
    @State private var sessionStart: Date?
    @State private var sessionStartLocator: Locator?
    @State private var sessionID = UUID()
    @State private var pendingLocatorSave: Task<Void, Never>?
    @State private var readerIsRunning = false
    @State private var sessionDayStamp: String?
    @State private var lastClockSample: Date?
    @State private var isClosing = false
    @State private var message: String?
    @State private var readerAlert: String?
    @State private var highlights: [MihbaraHighlight] = []
    @State private var wordCard: MihbaraWordCardState?
    @State private var noteDraft: MihbaraWordCardState?
    @State private var lookupTerm: MihbaraLookupTerm?
    @State private var lastDecorationTap = Date.distantPast
    @State private var readerUndoID: UUID?
    @State private var copiedAt: Date?

    private var paper: SwiftUI.Color {
        colorScheme == .dark
            ? SwiftUI.Color(red: 31 / 255, green: 28 / 255, blue: 23 / 255)
            : SwiftUI.Color(red: 250 / 255, green: 246 / 255, blue: 234 / 255)
    }
    private var saveCoordinator: MihbaraReadingSaveCoordinator { .forSession(app) }
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private var readerTheme: ReadiumNavigator.Theme { colorScheme == .dark ? .dark : .sepia }
    private var readerProgress: Double? {
        if let progression = currentLocator?.locations.totalProgression {
            return min(1, max(0, progression))
        }
        if let position = currentLocator?.locations.position, positionCount > 1 {
            return min(1, max(0, Double(position - 1) / Double(positionCount - 1)))
        }
        return nil
    }
    /// `mihbara.readerAr` merged over its schema default, so values saved before a field existed read as its default.
    private var readerSettings: [String: MadarData.JSONValue] {
        var merged = app.schema.settings.first(where: { $0.key == "mihbara.readerAr" })?.defaultValue.object ?? [:]
        if case .object(let stored)? = app.values["mihbara.readerAr"] { merged.merge(stored) { _, new in new } }
        return merged
    }
    private func readerInt(_ key: String, _ range: ClosedRange<Int>, _ fallback: Int) -> Int {
        guard case .number(let value)? = readerSettings[key], value.isFinite else { return fallback }
        return min(range.upperBound, max(range.lowerBound, Int(value)))
    }
    private func readerBool(_ key: String, _ fallback: Bool) -> Bool {
        guard case .bool(let value)? = readerSettings[key] else { return fallback }
        return value
    }
    private var readerSize: Int { readerInt("size", 1...7, 4) }
    private var readerLineSpacing: Int { readerInt("lineSpacing", 1...4, 2) }
    private var readerMargins: Int { readerInt("margins", 1...4, 2) }
    private var readerJustify: Bool { readerBool("justify", true) }
    private var readerHeavier: Bool { readerBool("heavier", false) }
    private var readerScroll: Bool { readerSettings["mode"]?.string == "scroll" }
    private var readerFooter: MihbaraReaderFooter { readerSettings["footer"]?.string.flatMap(MihbaraReaderFooter.init(rawValue:)) ?? .full }
    private var readerFont: MihbaraReaderFont {
        guard case .string(let id)? = readerSettings["font"] else { return .amiri }
        return MihbaraReaderFont(rawValue: id) ?? .amiri
    }
    private var readerFontPercent: Double { Double(95 + (readerSize - 1) * 10) }
    private var readerPreferences: EPUBPreferences {
        EPUBPreferences(
            fontFamily: readerFont.family,
            // Readium's fontSize is a multiplier: 1.0 is the publisher's 100%.
            fontSize: readerFontPercent / 100,
            // A multiplier of the regular 400 weight, landing on a face the font really has.
            fontWeight: readerHeavier ? readerFont.heavierWeight : nil,
            ligatures: true,
            lineHeight: [1.6, 1.95, 2.25, 2.6][readerLineSpacing - 1],
            pageMargins: [0.6, 1.0, 1.5, 2.0][readerMargins - 1],
            // Line height, alignment and weight apply only over the publisher's own styles.
            publisherStyles: false,
            readingProgression: .rtl,
            scroll: readerScroll,
            textAlign: readerJustify ? .justify : .start,
            theme: readerTheme
        )
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { tick in
            VStack(spacing: 0) {
                header
                Rectangle().fill(SwiftUI.Color.black.opacity(0.08)).frame(height: 1)
                if let publication {
                    MihbaraEPUBNavigator(
                        publication: publication,
                        initialLocation: initialLocator,
                        preferences: readerPreferences,
                        onLocation: locationChanged,
                        onInteraction: readerTapped,
                        onSelection: selectionChanged,
                        onReady: { navigator in
                            navigatorController = navigator
                            if let currentLocator { resolvePrintPageMarker(for: currentLocator) }
                            navigator.observeDecorationInteractions(inGroup: MihbaraHighlight.group) { event in
                                highlightTapped(event.decoration.id)
                            }
                            reloadHighlights()
                        },
                        onError: {
                            switch $0 {
                            case .copyForbidden: readerAlert = "حقوق هذا الكتاب لا تسمح بنسخ نصه."
                            }
                        }
                    )
                    .id(book.id)
                    .accessibilityIdentifier("mihbara-epub-content")
                } else {
                    VStack(spacing: 16) {
                        if message == nil { ProgressView("يفتح الكتاب من جهازك…") }
                        else {
                            Image(systemName: "book.closed").font(.largeTitle)
                            Text(message!).font(MadarTypography.body()).multilineTextAlignment(.center)
                            Button("العودة إلى المحبرة", action: close).buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("mihbara-reader-close")
                        }
                    }.frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
                }
                footer
            }
            .overlay(alignment: .bottom) { readerOverlay }
            .background(paper.ignoresSafeArea())
        .foregroundStyle(colorScheme == .dark ? SwiftUI.Color(red: 233 / 255, green: 225 / 255, blue: 210 / 255) : SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255))
            .environment(\.layoutDirection, .rightToLeft)
            .onChange(of: tick.date) { _, date in
                advanceClock(to: date)
                isSpeaking = speechSynthesizer.isSpeaking
            }
        }
        .task { await openPublication() }
        .onChange(of: app.values["mihbara.readerAr"]) { navigatorController?.submitPreferences(readerPreferences) }
        // An undo from the toast, or anywhere else, repaints the page from the store.
        .onChange(of: app.undoToken?.id) { reloadHighlights() }
        .onChange(of: colorScheme) { applyHighlights() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumeReader(at: Date())
            } else {
                pauseReader(at: Date())
            }
        }
        .onChange(of: saveCoordinator.canWrite) { _, authorized in
            if authorized, scenePhase == .active { resumeReader(at: Date()) }
            else if !authorized { pauseReader(at: Date()) }
        }
        .onChange(of: showingContents || showingReaderSettings) { _, covered in
            if covered { pauseReader(at: Date()) }
            else if scenePhase == .active { resumeReader(at: Date()) }
        }
        .onDisappear {
            pauseReader(at: Date())
            speechSynthesizer.stopSpeaking(at: .immediate)
            pendingLocatorSave?.cancel()
            if let localURL { try? FileManager.default.removeItem(at: localURL) }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .sheet(isPresented: $showingContents) {
            MihbaraContentsSheet(publication: publication, paper: paper) { link in
                showingContents = false
                Task { @MainActor in
                    _ = await navigatorController?.go(to: link, options: .animated)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showingReaderSettings) {
            MihbaraReaderSettingsSheet(
                app: app, paper: paper,
                options: .init(size: readerSize, font: readerFont, scroll: readerScroll, lineSpacing: readerLineSpacing,
                               margins: readerMargins, justify: readerJustify, heavier: readerHeavier, footer: readerFooter),
                set: updateReaderSetting,
                reset: { app.reset(["mihbara.readerAr"]) }
            )
            .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(item: $noteDraft) { draft in
            MihbaraPageNoteSheet(draft: draft, paper: paper, pageText: draft.pageText) { text in
                await savePageNote(text, for: draft)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(item: $lookupTerm) { term in
            MihbaraDictionaryView(term: term.word).ignoresSafeArea()
        }
        .alert("القارئ", isPresented: Binding(get: { readerAlert != nil }, set: { if !$0 { readerAlert = nil } })) {
            Button("حسنًا", role: .cancel) { readerAlert = nil }
        } message: { Text(readerAlert ?? "") }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(book.title).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline)).lineLimit(1)
                Text(currentLocator?.title ?? book.author)
                    .font(MadarTypography.fine())
                    .foregroundStyle(colorScheme == .dark ? SwiftUI.Color.white.opacity(0.68) : SwiftUI.Color(red: 106 / 255, green: 96 / 255, blue: 82 / 255))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            HStack(spacing: 12) {
                Button(action: finishAndClose) {
                    HStack(spacing: 5) {
                        Text("المحبرة").font(MadarTypography.caption())
                        Image(systemName: "chevron.right").font(.system(size: 15, weight: .medium))
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }
                .accessibilityLabel("العودة إلى المحبرة")
                .accessibilityIdentifier("mihbara-reader-close")
                Spacer(minLength: 0)
                HStack(spacing: 12) {
                    Button(action: toggleNarration) {
                        Image(systemName: isSpeaking ? "pause.fill" : "headphones").font(.system(size: 18, weight: .regular))
                            .frame(width: 32, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(isSpeaking ? "إيقاف القراءة الصوتية" : "استمع إلى هذا الفصل")
                    .accessibilityIdentifier("mihbara-reader-listen")
                    Button { showingContents = true } label: {
                        Image(systemName: "list.bullet").font(.system(size: 18, weight: .regular))
                            .frame(width: 32, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("فهرس الكتاب")
                    .accessibilityIdentifier("mihbara-reader-contents")
                    Button {
                        showingReaderSettings = true
                    } label: {
                        Text("Aa").font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline))
                            .frame(width: 36, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel("إعدادات القراءة")
                    .accessibilityIdentifier("mihbara-reader-settings")
                }
            }
        }
        .padding(.horizontal, 16).padding(.top, 4).padding(.bottom, 8)
        .background(paper)
    }

    @ViewBuilder private var footer: some View {
        if readerFooter != .none { footerContent }
    }

    private var footerContent: some View {
        VStack(spacing: 7) {
            if let readerProgress {
                ProgressView(value: readerProgress)
                    .tint(SwiftUI.Color(red: 158 / 255, green: 47 / 255, blue: 37 / 255))
                    .accessibilityLabel("تقدّم الكتاب")
                    .accessibilityValue(digits.string(Int((readerProgress * 100).rounded())) + "٪")
                    .accessibilityIdentifier("mihbara-reader-progress")
            } else {
                Rectangle().fill(SwiftUI.Color.black.opacity(0.10)).frame(height: 3)
            }
            if readerFooter != .bar {
            HStack(alignment: .center, spacing: 12) {
                Text(printPageLabel)
                    .font(MadarTypography.caption()).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("mihbara-reader-print-page")
                Spacer(minLength: 4)
                if readerFooter == .full || isSpeaking {
                    Text(isSpeaking ? "تُقرأ الصفحة بصوت عربي" : "تُسجَّل الجلسة بعد دقيقة نشاط")
                        .font(MadarTypography.fine()).foregroundStyle(.secondary)
                }
            }
            }
        }
        .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 11)
        .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08)).frame(height: 1) }
        .background(paper)
    }

    /// The current locator, with its printed-page anchor when the visible document supplied one.
    private var printLocator: Locator? {
        guard let current = currentLocator, let marked = printMarkedLocator,
              marked.href.isEquivalentTo(current.href),
              marked.locations.totalProgression == current.locations.totalProgression else { return currentLocator }
        return marked
    }

    private var printPageLabel: String {
        guard let last = printPages.last else { return "موضع من الكتاب" }
        guard let ordinal = pageCoordinate(printLocator), printPages.indices.contains(ordinal - 1) else {
            return "موضع من الكتاب؛ صفحة المطبوع غير معروفة هنا"
        }
        let current = printPages[ordinal - 1]
        return "ص \(digits.localized(current.label)) من \(digits.localized(last.label)) في المطبوع"
    }

    @MainActor private func openPublication() async {
        guard publication == nil, localURL == nil, message == nil else { return }
        do {
            let data = try AppMihbaraService(app: app).epubData(for: book)
            let directory = FileManager.default.temporaryDirectory.appendingPathComponent("MadarReader", isDirectory: true)
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            let file = directory.appendingPathComponent(UUID().uuidString).appendingPathExtension("epub")
            try data.write(to: file, options: .atomic)
            try FileManager.default.setAttributes([.protectionKey: FileProtectionType.completeUntilFirstUserAuthentication], ofItemAtPath: file.path)
            localURL = file

            let opened = try await MihbaraEPUBLoader.open(at: file)

            let saved = readiumLocator(book.locatorJSON)
            let now = Date()
            let (readyPublication, firstLocator, readyPages, readyPositionCount) = await prepareReader(from: opened)
            let startLocator = saved ?? firstLocator
            initialLocator = startLocator
            currentLocator = startLocator
            sessionStartLocator = startLocator
            sessionStart = now
            readerIsRunning = saveCoordinator.canWrite && scenePhase == .active
            readingClock = ActiveReadingClock(startedAt: now, foreground: readerIsRunning)
            sessionDayStamp = dayStamp(at: now)
            lastClockSample = now
            publication = readyPublication
            printPages = readyPages
            positionCount = readyPositionCount
            positionProgress = ReadingPositionProgress(startingAt: pageCoordinate(startLocator), at: now)
        } catch {
            message = error.localizedDescription
        }
    }

    nonisolated private func prepareReader(from publication: sending Publication) async -> (Publication, Locator?, [MihbaraPrintPage], Int) {
        let firstLocator = await publication.locate(progression: 0)
        let positions = await publication.positionsByReadingOrder().getOrNil() ?? []
        let positionCount = positions.reduce(0) { $0 + $1.count }
        var result: [MihbaraPrintPage] = []
        for link in publication.pageList {
            guard let label = link.title, !label.isEmpty else { continue }
            let target = link.url(relativeTo: publication.baseURL)
            result.append(.init(href: target.removingFragment(), fragment: target.fragment, label: label))
        }
        return (publication, firstLocator, result, positionCount)
    }

    @MainActor private func locationChanged(_ locator: Locator, explicitJump: Bool) {
        let now = Date()
        recordInteraction(at: now)
        if let position = pageCoordinate(locator) {
            positionProgress.observe(position: position, at: now, explicitJump: explicitJump)
        }
        currentLocator = locator
        // The reader's undo toast belongs to the page it was made on; the undo itself stays available.
        if !explicitJump, wordCard == nil { readerUndoID = nil }
        scheduleLocatorSave(locator)
        resolvePrintPageMarker(for: locator)
    }

    /// Readium's reflowable locators carry a progression, not the page-break anchor, so a
    /// resource with several printed-page markers would otherwise show an unknown page.
    /// Ask the visible document for the page in effect at the top of the screen.
    @MainActor private func resolvePrintPageMarker(for locator: Locator) {
        guard locator.locations.fragments.isEmpty, let navigatorController else { return }
        let ids = printPages.filter { $0.href.isEquivalentTo(locator.href.removingFragment()) }.compactMap(\.fragment)
        guard !ids.isEmpty, let idsJSON = try? JSONEncoder().encode(ids), let idsList = String(data: idsJSON, encoding: .utf8) else { return }
        let script = """
        (() => {
          const rtl = getComputedStyle(document.documentElement).direction === 'rtl';
          let before = null, firstVisible = null;
          for (const id of \(idsList)) {
            const element = document.getElementById(id);
            if (!element) continue;
            const r = element.getBoundingClientRect();
            const earlier = r.bottom <= 0 || (rtl ? r.left >= window.innerWidth : r.right <= 0);
            const later = r.top >= window.innerHeight || (rtl ? r.right <= 0 : r.left >= window.innerWidth);
            if (earlier) before = id;
            else if (!later && firstVisible === null) firstVisible = id;
          }
          return before ?? firstVisible;
        })()
        """
        Task { @MainActor in
            guard case .success(let value) = await navigatorController.evaluateJavaScript(script),
                  let id = value as? String, !id.isEmpty,
                  let current = currentLocator, current.href.isEquivalentTo(locator.href),
                  current.locations.fragments.isEmpty,
                  current.locations.totalProgression == locator.locations.totalProgression else { return }
            // Kept beside the saved locator, which stays Readium's own so reopening returns to
            // the exact spot rather than the start of the printed page.
            printMarkedLocator = current.copy(locations: { $0.fragments = [id] })
        }
    }

    // MARK: - M6-V08 word card, paragraph highlights and page notes

    @ViewBuilder private var readerOverlay: some View {
        if let wordCard {
            MihbaraWordCard(
                state: wordCard, dark: colorScheme == .dark, copied: copiedAt != nil,
                lookUp: { lookupTerm = .init(word: wordCard.word) },
                choose: { color in Task { await chooseHighlight(color, for: wordCard) } },
                note: { noteDraft = wordCard },
                copy: { Task { await copyWithCitation(wordCard) } },
                close: closeWordCard
            )
            .padding(.horizontal, 12).padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let token = app.undoToken, token.id == readerUndoID, !showingReaderSettings {
            UndoToast(message: app.undoMessage, undo: app.undo)
                .accessibilityIdentifier("mihbara-reader-toast")
                .padding(.bottom, 64)
        }
    }

    @MainActor private func readerTapped() {
        recordInteraction()
        guard wordCard != nil else { return }
        let tapped = Date()
        Task { @MainActor in
            // A tap on a highlight reports both the tap and the decoration; the decoration wins.
            try? await Task.sleep(for: .milliseconds(300))
            if lastDecorationTap < tapped.addingTimeInterval(-0.05) { closeWordCard() }
        }
    }

    @MainActor private func closeWordCard() {
        withAnimation(.easeOut(duration: 0.2)) { wordCard = nil }
        copiedAt = nil
        navigatorController?.clearSelection()
    }

    @MainActor private func selectionChanged(_ selection: Selection) {
        recordInteraction()
        let text = (selection.locator.text.highlight ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, wordCard?.selection != selection.locator else { return }
        openWordCard(href: selection.locator.href, base: selection.locator, selector: nil, selectionText: text)
    }

    @MainActor private func highlightTapped(_ id: Decoration.Id) {
        lastDecorationTap = Date()
        guard let highlight = highlights.first(where: { $0.id.uuidString == id }),
              let locator = readiumLocator(highlight.locatorJSON),
              case .string(let selector)? = locator.locations.otherLocations["cssSelector"] else { return }
        openWordCard(href: locator.href, base: locator, selector: selector, selectionText: nil)
    }

    /// Finds the block that holds the selection (or the given selector) and the printed page it starts on.
    @MainActor private func openWordCard(href: AnyURL, base: Locator, selector: String?, selectionText: String?) {
        guard let navigatorController else { return }
        let ids = printPages.filter { $0.href.isEquivalentTo(href.removingFragment()) }.compactMap(\.fragment)
        guard let idsJSON = try? JSONEncoder().encode(ids), let idsList = String(data: idsJSON, encoding: .utf8),
              let selectorJSON = try? JSONEncoder().encode(selector), let selectorValue = String(data: selectorJSON, encoding: .utf8) else { return }
        let script = """
        (() => {
          const blocks = 'p, li, blockquote, h1, h2, h3, h4, h5, h6, dd, dt, figcaption, td, pre';
          let block = null;
          const wanted = \(selectorValue);
          if (wanted) { block = document.querySelector(wanted); }
          else {
            const selection = window.getSelection();
            if (!selection || selection.rangeCount === 0) return null;
            let node = selection.getRangeAt(0).startContainer;
            if (node.nodeType !== 1) node = node.parentElement;
            block = node ? (node.closest(blocks) || node.closest('div')) : null;
          }
          if (!block || block === document.body || block === document.documentElement) return null;
          const path = (element) => {
            const parts = [];
            while (element && element !== document.body) {
              if (element.id) { parts.unshift('#' + CSS.escape(element.id)); return parts.join(' > '); }
              const index = Array.prototype.indexOf.call(element.parentElement.children, element) + 1;
              parts.unshift(element.tagName.toLowerCase() + ':nth-child(' + index + ')');
              element = element.parentElement;
            }
            parts.unshift('body');
            return parts.join(' > ');
          };
          let page = null;
          for (const id of \(idsList)) {
            const marker = document.getElementById(id);
            if (marker && (marker.compareDocumentPosition(block) & Node.DOCUMENT_POSITION_FOLLOWING) && !block.contains(marker)) page = id;
          }
          const text = (block.innerText || '').replace(/\\s+/g, ' ').trim();
          return JSON.stringify({ selector: wanted || path(block), text: text, page: page });
        })()
        """
        Task { @MainActor in
            guard case .success(let value) = await navigatorController.evaluateJavaScript(script),
                  let json = (value as? String)?.data(using: .utf8),
                  let found = try? JSONDecoder().decode(MihbaraParagraphProbe.self, from: json),
                  !found.text.isEmpty else { return }
            let paragraph = base.copy(
                locations: { $0.fragments = []; $0.otherLocations = ["cssSelector": .string(found.selector)] },
                text: { $0 = .init() }
            )
            let page = printPage(href: href, markerID: found.page)
            let existing = matchingHighlight(paragraph)
            let preview = found.text.split(separator: " ").prefix(4).joined(separator: " ")
            var state = MihbaraWordCardState(
                word: selectionText ?? preview + (found.text.split(separator: " ").count > 4 ? "…" : ""),
                isWord: selectionText != nil, selection: selectionText == nil ? nil : base,
                paragraph: paragraph, paragraphText: found.text, quote: selectionText ?? found.text,
                page: page.number, pageLabel: page.label, pageText: page.label.map { "ص " + digits.localized($0) })
            state.highlightID = existing?.id; state.color = existing?.color
            copiedAt = nil
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { wordCard = state }
        }
    }

    /// The printed page in effect at a block: its own marker, else the last page that began before its resource.
    private func printPage(href: AnyURL, markerID: String?) -> (label: String?, number: Int?) {
        let resource = href.removingFragment()
        var index: Int?
        if let markerID { index = printPages.firstIndex { $0.href.isEquivalentTo(resource) && $0.fragment == markerID } }
        if index == nil, let first = printPages.firstIndex(where: { $0.href.isEquivalentTo(resource) }) {
            index = printPages[first].fragment == nil ? first : (first > 0 ? first - 1 : nil)
        }
        guard let index else { return (nil, nil) }
        let label = printPages[index].label
        let number = label.allSatisfy({ $0.wholeNumberValue != nil }) ? Int(label.compactMap { $0.wholeNumberValue.map(String.init) }.joined()) : nil
        return (label, number.flatMap { $0 > 0 ? $0 : nil })
    }

    private func matchingHighlight(_ paragraph: Locator) -> MihbaraHighlight? {
        guard let selector = paragraph.locations.otherLocations["cssSelector"] else { return nil }
        return highlights.last { highlight in
            guard let locator = readiumLocator(highlight.locatorJSON) else { return false }
            return locator.href.isEquivalentTo(paragraph.href) && locator.locations.otherLocations["cssSelector"] == selector
        }
    }

    @MainActor private func reloadHighlights() {
        highlights = (try? AppMihbaraService(app: app).highlights(for: book.id)) ?? []
        if var card = wordCard {
            let existing = matchingHighlight(card.paragraph)
            card.highlightID = existing?.id; card.color = existing?.color
            wordCard = card
        }
        applyHighlights()
    }

    @MainActor private func applyHighlights() {
        guard let navigatorController else { return }
        let palette = colorScheme == .dark ? MihbaraHighlight.night : MihbaraHighlight.paper
        let decorations = highlights.compactMap { highlight -> Decoration? in
            guard let locator = readiumLocator(highlight.locatorJSON),
                  let index = MihbaraHighlight.colors.firstIndex(of: highlight.color) else { return nil }
            return Decoration(id: highlight.id.uuidString, locator: locator, style: .highlight(tint: UIColor(madarHex: palette[index])))
        }
        navigatorController.apply(decorations: decorations, in: MihbaraHighlight.group)
    }

    /// One tap colours the paragraph; tapping its colour again clears it. Both are undoable.
    @MainActor private func chooseHighlight(_ color: String, for card: MihbaraWordCardState) async {
        recordInteraction()
        do {
            let commandID = UUID()
            if card.color == color, let id = card.highlightID {
                try await app.executeBookCommand("highlight.delete", payload: ["id": .string(id.uuidString)], id: commandID,
                                                 undoMessage: "أُزيل التظليل · التراجع متاح لعشر دقائق")
            } else {
                guard let locator = try? card.paragraph.jsonString() else { return }
                var payload: [String: MadarCore.JSONValue] = [
                    "id": .string((card.highlightID ?? UUID()).uuidString), "bookID": .string(book.id.uuidString),
                    "locator": .string(locator), "color": .string(color)
                ]
                if let label = card.pageLabel { payload["pageLabel"] = .string(label) }
                try await app.executeBookCommand("highlight.save", payload: payload, id: commandID,
                                                 undoMessage: "ظُلّلت الفقرة · التراجع متاح لعشر دقائق")
            }
            readerUndoID = app.undoToken?.id
            reloadHighlights()
        } catch { readerAlert = error.localizedDescription }
    }

    @MainActor private func savePageNote(_ text: String, for card: MihbaraWordCardState) async -> Bool {
        guard let locator = try? card.paragraph.jsonString() else { return false }
        var payload: [String: MadarCore.JSONValue] = [
            "id": .string(UUID().uuidString), "bookID": .string(book.id.uuidString),
            "text": .string(text), "locator": .string(locator)
        ]
        if let page = card.page { payload["page"] = .number(Double(page)) }
        do {
            try await app.executeBookCommand("notebook.savePage", payload: payload, undoMessage: "دُوّنت الملاحظة في دفتر الكتاب · التراجع متاح لعشر دقائق")
            readerUndoID = app.undoToken?.id
            noteDraft = nil
            closeWordCard()
            return true
        } catch {
            readerAlert = error.localizedDescription
            return false
        }
    }

    /// «النص» then «— الكتاب، المؤلف، ص ٤٥٣»; a single word copies its whole paragraph.
    /// Import refuses DRM-protected EPUBs (M6-V19), so every readable book may be quoted.
    @MainActor private func copyWithCitation(_ card: MihbaraWordCardState) async {
        let quote = card.isWord && card.quote.split(separator: " ").count > 1 ? card.quote : card.paragraphText
        var source = [book.title]
        if !book.author.trimmingCharacters(in: .whitespaces).isEmpty { source.append(book.author) }
        if let label = card.pageLabel { source.append("ص " + digits.localized(label)) }
        UIPasteboard.general.string = "«\(quote)»\n— " + source.joined(separator: "، ")
        let stamp = Date()
        copiedAt = stamp
        UIAccessibility.post(notification: .announcement, argument: "نُسخت الفقرة مع توثيقها")
        Task { @MainActor in
            try? await Task.sleep(for: .seconds(1.6))
            if copiedAt == stamp { copiedAt = nil }
        }
    }

    @MainActor private func recordInteraction() { recordInteraction(at: Date()) }

    @MainActor private func recordInteraction(at date: Date) {
        advanceClock(to: date)
        guard var readingClock else { return }
        readingClock.interaction(at: date)
        self.readingClock = readingClock
    }

    /// Printed-page ordinals count transitions without assuming that page labels are numeric.
    /// If a multi-page resource supplies no matching marker, its printed position is unknown.
    private func pageCoordinate(_ locator: Locator?) -> Int? {
        guard let locator else { return nil }
        if printPages.isEmpty {
            return ReadingPageEstimate.page(progression: locator.locations.totalProgression, totalPages: book.pages)
        }
        let matches = printPages.enumerated().filter { $0.element.href.isEquivalentTo(locator.href.removingFragment()) }
        if let exact = matches.last(where: { $0.element.fragment.map { locator.locations.fragments.contains($0) } ?? false }) {
            return exact.offset + 1
        }
        if matches.count == 1, matches[0].element.fragment == nil { return matches[0].offset + 1 }
        return nil
    }

    private func printedPageNumber(_ locator: Locator?) -> Int {
        guard !printPages.isEmpty, let ordinal = pageCoordinate(locator), printPages.indices.contains(ordinal - 1) else { return 0 }
        let label = printPages[ordinal - 1].label
        guard !label.isEmpty, label.allSatisfy({ $0.wholeNumberValue != nil }) else { return 0 }
        return Int(label.compactMap { $0.wholeNumberValue.map(String.init) }.joined()) ?? 0
    }

    @MainActor private func dayStamp(at date: Date) -> String? {
        let context = ModelContext(app.container)
        guard let day = try? DiaryLineRenderer.today(context: context, now: date),
              let prayers = try? PrayerRepository(context: context) else { return nil }
        return day.description + "|" + prayers.place(at: date).timeZoneID + "|" + app.string("core.dayStart")
    }

    @MainActor private func advanceClock(to date: Date) {
        guard var clock = readingClock else { return }
        let stamp = dayStamp(at: date)
        if let oldStamp = sessionDayStamp, let stamp, stamp != oldStamp, let lastClockSample, date > lastClockSample {
            // Find the day/trip transition between ticks, so the old session ends on its own day.
            var lower = lastClockSample, upper = date
            if dayStamp(at: lower) == oldStamp {
                while upper.timeIntervalSince(lower) > 0.002 {
                    let middle = lower.addingTimeInterval(upper.timeIntervalSince(lower) / 2)
                    if dayStamp(at: middle) == oldStamp { lower = middle } else { upper = middle }
                }
            } else { lower = date; upper = date }
            clock.advance(to: lower)
            readingClock = clock
            queueSessionSave(at: lower)
            clock.startSegment(at: upper)
            beginSegment(at: upper)
        }
        clock.advance(to: date)
        readingClock = clock
        sessionDayStamp = stamp
        lastClockSample = date
    }

    @MainActor private func beginSegment(at date: Date) {
        sessionID = UUID()
        sessionStart = date
        sessionStartLocator = currentLocator
        positionProgress = ReadingPositionProgress(startingAt: pageCoordinate(currentLocator), at: date)
        sessionDayStamp = dayStamp(at: date)
        lastClockSample = date
    }

    @MainActor private func resumeReader(at date: Date) {
        saveCoordinator.flush()
        guard !readerIsRunning, !showingContents, !showingReaderSettings, !isClosing,
              publication != nil, saveCoordinator.canWrite else { return }
        readerIsRunning = true
        beginSegment(at: date)
        readingClock = ActiveReadingClock(startedAt: date)
    }

    @MainActor private func scheduleLocatorSave(_ locator: Locator) {
        pendingLocatorSave?.cancel()
        pendingLocatorSave = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(650))
            guard !Task.isCancelled else { return }
            saveCoordinator.enqueueLocator(locator, bookID: book.id)
        }
    }

    @MainActor private func pauseReader(at date: Date) {
        guard readerIsRunning else { return }
        readerIsRunning = false
        advanceClock(to: date)
        guard var clock = readingClock else { return }
        clock.setForeground(false, at: date)
        readingClock = clock
        queueSessionSave(at: date)
        beginSegment(at: date)
        readingClock = ActiveReadingClock(startedAt: date, foreground: false)
    }

    @MainActor private func finishAndClose() {
        guard !isClosing else { return }
        isClosing = true
        pauseReader(at: Date())
        Task { @MainActor in
            await saveCoordinator.waitForCurrentAttempt()
            if saveCoordinator.hasPending {
                isClosing = false
                readerAlert = "لم يكتمل حفظ قراءتك. تبقى الجلسة معلّقة وتُعاد المحاولة بعد عودة مدار للمقدمة وفتح القفل."
            } else { close() }
        }
    }

    /// The coordinator owns this immutable snapshot before the reader starts another segment.
    @MainActor private func queueSessionSave(at date: Date) {
        pendingLocatorSave?.cancel()
        if let payload = sessionPayload(at: date) {
            saveCoordinator.enqueue(sessionID: sessionID, payload: payload)
        }
        if let currentLocator { saveCoordinator.enqueueLocator(currentLocator, bookID: book.id) }
    }

    @MainActor private func sessionPayload(at date: Date) -> [String: MadarCore.JSONValue]? {
        guard let readingClock, let sessionStart, let startLocator = sessionStartLocator,
              let endLocator = currentLocator else { return nil }
        let activeSeconds = min(86_400, readingClock.activeSeconds)
        guard activeSeconds >= 60,
              let startJSON = try? startLocator.jsonString(), let endJSON = try? endLocator.jsonString() else { return nil }
        let fromPage = printedPageNumber(startLocator)
        let toPage = max(fromPage, printedPageNumber(endLocator))
        let startProgression = min(1, max(0, startLocator.locations.totalProgression ?? 0))
        let endProgression = min(1, max(0, endLocator.locations.totalProgression ?? startProgression))
        return [
            "id": .string(sessionID.uuidString), "bookID": .string(book.id.uuidString),
            "start": .string(Self.timestamp(sessionStart)), "end": .string(Self.timestamp(date)),
            "activeSeconds": .number(Double(activeSeconds)), "fromPage": .number(Double(fromPage)), "toPage": .number(Double(toPage)),
            "startLocator": .string(startJSON), "endLocator": .string(endJSON),
            "startProgression": .number(startProgression), "endProgression": .number(endProgression),
            "pagesCounted": .number(Double(positionProgress.pagesCounted))
        ]
    }

    private static func timestamp(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    private func readiumLocator(_ data: Data?) -> Locator? {
        guard let data, let string = String(data: data, encoding: .utf8),
              let json = try? ReadiumShared.JSONValue(jsonString: string),
              let locator = try? Locator(json: json, warnings: nil) else { return nil }
        return locator
    }

    @MainActor private func updateReaderSetting(_ key: String, _ value: MadarData.JSONValue) {
        var settings = readerSettings
        settings[key] = value
        app.set(.object(settings), key: "mihbara.readerAr")
    }

    @MainActor private func toggleNarration() {
        if speechSynthesizer.isSpeaking {
            speechSynthesizer.stopSpeaking(at: .immediate)
            isSpeaking = false
            return
        }
        guard let navigatorController else {
            readerAlert = "لم يجهز القارئ للصوت بعد."
            return
        }
        recordInteraction()
        Task { @MainActor in
            let result = await navigatorController.evaluateJavaScript("document.body.innerText")
            guard case .success(let value) = result, let rawText = value as? String else {
                readerAlert = "تعذّر قراءة نص هذا الفصل."
                return
            }
            let text = rawText.components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }.joined(separator: " ")
            guard !text.isEmpty else {
                readerAlert = "لا يوجد نص قابل للقراءة في هذا الموضع."
                return
            }
            guard let voice = AVSpeechSynthesisVoice.speechVoices().first(where: { $0.language.hasPrefix("ar") }) else {
                readerAlert = "لا يتوفر صوت عربي على هذا الجهاز."
                return
            }
            let utterance = AVSpeechUtterance(string: text)
            utterance.voice = voice
            utterance.rate = 0.48
            speechSynthesizer.speak(utterance)
            isSpeaking = true
        }
    }
}

private struct MihbaraContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let publication: Publication?
    let paper: SwiftUI.Color
    let select: (ReadiumShared.Link) -> Void

    private var items: [MihbaraTOCItem] { Self.flatten(publication?.manifest.tableOfContents ?? []) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("فهرس الكتاب").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
                Spacer()
                Button("تمّ") { dismiss() }.font(MadarTypography.caption()).accessibilityIdentifier("mihbara-reader-contents-close")
            }
            if items.isEmpty {
                Text("لا يتضمن هذا الكتاب فهرسًا").font(MadarTypography.body()).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(spacing: 0) {
                        ForEach(items) { item in
                            Button { select(item.link) } label: {
                                HStack {
                                    Text(item.link.title ?? "موضع في الكتاب").font(MadarTypography.body()).lineLimit(2)
                                    Spacer(minLength: 12)
                                    Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
                                }
                                .padding(.leading, CGFloat(item.depth) * 18)
                                .padding(.vertical, 12)
                                .contentShape(Rectangle())
                            }
                            .buttonStyle(.plain)
                            .accessibilityIdentifier("mihbara-reader-toc-" + item.id)
                            Rectangle().fill(SwiftUI.Color.black.opacity(0.08)).frame(height: 1)
                        }
                    }
                }
            }
        }
        .padding(20)
        .foregroundStyle(SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255))
        .background(paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private static func flatten(_ links: [ReadiumShared.Link], depth: Int = 0) -> [MihbaraTOCItem] {
        links.flatMap { link in
            [MihbaraTOCItem(link: link, depth: depth)] + flatten(link.children, depth: depth + 1)
        }
    }
}

private struct MihbaraTOCItem: Identifiable {
    let link: ReadiumShared.Link
    let depth: Int
    var id: String { "\(depth)-\(link.href)" }
}

/// `mihbara.readerAr.font` ids. Amiri (OFL) is the schema default; the Thmanyah faces are the
/// owner's request (18 Oct) and are embedded in the app under their licence.
enum MihbaraReaderFont: String, CaseIterable, Identifiable {
    case amiri, thmanyahSerif, thmanyahSans
    var id: String { rawValue }
    var title: String {
        switch self { case .amiri: "أميري"; case .thmanyahSerif: "ثمانية نسخ"; case .thmanyahSans: "ثمانية حديث" }
    }
    var family: FontFamily {
        switch self { case .amiri: FontFamily(rawValue: "Amiri"); case .thmanyahSerif: FontFamily(rawValue: "Thmanyah Serif Text"); case .thmanyahSans: FontFamily(rawValue: "Thmanyah Sans") }
    }
    /// PostScript name used to preview the face in the sheet.
    var previewName: String {
        switch self { case .amiri: "Amiri-Regular"; case .thmanyahSerif: "thmanyahseriftext-Regular"; case .thmanyahSans: "thmanyahsans-Regular" }
    }
    var files: [(name: String, ext: String, weight: CSSStandardFontWeight)] {
        switch self {
        case .amiri: [("Amiri-Regular", "ttf", .normal), ("Amiri-Bold", "ttf", .bold)]
        case .thmanyahSerif: [("thmanyahseriftext-Regular", "otf", .normal), ("thmanyahseriftext-Bold", "otf", .bold)]
        case .thmanyahSans: [("thmanyahsans-Regular", "otf", .normal), ("thmanyahsans-Medium", "otf", .medium), ("thmanyahsans-Bold", "otf", .bold)]
        }
    }
    /// «خط أثقل»: Medium where the family has it, otherwise its Bold.
    var heavierWeight: Double { self == .thmanyahSans ? 500.0 / 400 : 700.0 / 400 }
}

/// `mihbara.readerAr.footer`: what the bottom of the page shows.
enum MihbaraReaderFooter: String, CaseIterable, Identifiable {
    case full, page, bar, none
    var id: String { rawValue }
    var title: String {
        switch self { case .full: "الكل"; case .page: "الصفحة"; case .bar: "الشريط"; case .none: "لا شيء" }
    }
}

struct MihbaraReaderOptions: Equatable {
    var size: Int, font: MihbaraReaderFont, scroll: Bool, lineSpacing: Int, margins: Int, justify: Bool, heavier: Bool, footer: MihbaraReaderFooter
}

/// «عرض الصفحة»: every choice is saved to `mihbara.readerAr` at once and applied live.
private struct MihbaraReaderSettingsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let app: AppSession
    let paper: SwiftUI.Color
    let options: MihbaraReaderOptions
    let set: (String, MadarData.JSONValue) -> Void
    let reset: () -> Void
    @State private var more = false

    private let ink = SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255)
    private let accent = SwiftUI.Color(red: 158 / 255, green: 47 / 255, blue: 37 / 255)
    private var well: SwiftUI.Color { ink.opacity(0.06) }
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                header
                sizeRow
                fontRow
                modeRow
                Button { withAnimation(.smooth(duration: 0.25)) { more.toggle() } } label: {
                    Text(more ? "خيارات أقل" : "خيارات أكثر").font(MadarTypography.caption().weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32).background(well, in: .capsule)
                }
                .buttonStyle(.plain).accessibilityIdentifier("mihbara-reader-more")
                if more { moreOptions }
            }
            .padding(22)
        }
        .scrollBounceBehavior(.basedOnSize)
        .foregroundStyle(ink)
        .background(paper.ignoresSafeArea())
        .safeAreaInset(edge: .bottom) {
            if app.undoToken != nil { UndoToast(message: app.undoMessage, undo: app.undo).accessibilityIdentifier("mihbara-reader-undo") }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("عرض الصفحة").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
            Spacer(minLength: 8)
            Text("كتاب عربي · إعداداتك للعربي").font(MadarTypography.fine().weight(.semibold))
                .padding(.horizontal, 12).padding(.vertical, 6).background(well, in: .capsule)
            Button("تمّ") { dismiss() }.font(MadarTypography.caption()).frame(minWidth: 44, minHeight: 44)
                .accessibilityIdentifier("mihbara-reader-settings-close")
        }
    }

    private var sizeRow: some View {
        HStack(spacing: 0) {
            Text("أ").font(.custom(options.font.previewName, size: 15, relativeTo: .body)) + Text("−").font(MadarTypography.caption())
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
            Text("أ").font(.custom(options.font.previewName, size: 26, relativeTo: .title)) + Text("+").font(MadarTypography.body())
        }
        .padding(.horizontal, 16).frame(minHeight: 64).background(well, in: .rect(cornerRadius: 16))
    }

    private var fontRow: some View {
        HStack(spacing: 8) {
            ForEach(MihbaraReaderFont.allCases) { option in
                let selected = option == options.font
                Button { set("font", .string(option.rawValue)) } label: {
                    VStack(spacing: 2) {
                        Text("كتاب").font(.custom(option.previewName, size: 24, relativeTo: .title3))
                        Text(option.title).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.7))
                    }
                    .frame(maxWidth: .infinity, minHeight: 84)
                    .background(SwiftUI.Color.white.opacity(0.55), in: .rect(cornerRadius: 16))
                    .overlay { RoundedRectangle(cornerRadius: 16).stroke(ink.opacity(selected ? 1 : 0.15), lineWidth: selected ? 2.5 : 1) }
                }
                .buttonStyle(.plain)
                .accessibilityLabel("الخط \(option.title)")
                .accessibilityAddTraits(selected ? .isSelected : [])
                .accessibilityIdentifier("mihbara-reader-font-\(option.rawValue)")
            }
        }
    }

    private var modeRow: some View {
        // Focus mode is a later task (RMI2), so only pages and scroll are offered.
        segmented([("صفحات", "pages"), ("تمرير", "scroll")],
                  selected: options.scroll ? "scroll" : "pages", id: "mode") { set("mode", .string($0)) }
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
            VStack(alignment: .leading, spacing: 8) {
                Text("أسفل الصفحة").font(MadarTypography.caption()).foregroundStyle(ink.opacity(0.7))
                segmented(MihbaraReaderFooter.allCases.map { ($0.title, $0.rawValue) }, selected: options.footer.rawValue, id: "footer") { set("footer", .string($0)) }
            }
            Button("العودة إلى الإعدادات الافتراضية", action: reset)
                .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44)
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
                .buttonStyle(.plain)
                .accessibilityAddTraits(isOn ? .isSelected : [])
                .accessibilityIdentifier("mihbara-reader-\(id)-\(value)")
            }
        }
        .padding(4).background(well, in: .rect(cornerRadius: 15))
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
                    .buttonStyle(.plain)
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

private struct MihbaraEPUBNavigator: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocation: Locator?
    let preferences: EPUBPreferences
    let onLocation: (Locator, Bool) -> Void
    let onInteraction: () -> Void
    let onSelection: (Selection) -> Void
    let onReady: (EPUBNavigatorViewController) -> Void
    let onError: (NavigatorError) -> Void

    /// One opaque band behind the whole paragraph, across the page width (design tokens: never alpha over ink).
    private static var highlightTemplates: [Decoration.Style.Id: HTMLDecorationTemplate] {
        [.highlight: HTMLDecorationTemplate(
            layout: .bounds, width: .viewport,
            element: { decoration in
                let tint = (decoration.style.config as? Decoration.Style.HighlightConfig)?.tint ?? .yellow
                return "<div class=\"madar-highlight\" style=\"background-color: \(tint.madarCSS) !important;\"/>"
            },
            stylesheet: ".madar-highlight { z-index: -1; margin: -0.3em 0 0 0; padding: 0 0 0.6em 0; box-sizing: content-box; }"
        )]
    }

    /// Every bundled reader font is declared once, so switching in the Aa sheet applies live.
    private static var fontDeclarations: [AnyHTMLFontFamilyDeclaration] {
        MihbaraReaderFont.allCases.compactMap { font in
            let faces = font.files.compactMap { file -> CSSFontFace? in
                guard let url = Bundle.main.url(forResource: file.name, withExtension: file.ext).flatMap(FileURL.init(url:)) else { return nil }
                return CSSFontFace(file: url, preload: font == .amiri && file.weight == .normal, style: .normal, weight: .standard(file.weight))
            }
            guard !faces.isEmpty else { return nil }
            return CSSFontFamilyDeclaration(fontFamily: font.family, fontFaces: faces).eraseToAnyHTMLFontFamilyDeclaration()
        }
    }

    func makeCoordinator() -> Coordinator { Coordinator(onLocation: onLocation, onInteraction: onInteraction, onSelection: onSelection, onReady: onReady, onError: onError) }

    func makeUIViewController(context: Context) -> UIViewController {
        let configuration = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            contentInset: [.compact: (top: 25, bottom: 22), .regular: (top: 38, bottom: 34)],
            decorationTemplates: Self.highlightTemplates,
            fontFamilyDeclarations: Self.fontDeclarations
        )
        do {
            let navigator = try EPUBNavigatorViewController(publication: publication, initialLocation: initialLocation, config: configuration)
            navigator.delegate = context.coordinator
            navigator.view.backgroundColor = UIColor(red: 250 / 255, green: 246 / 255, blue: 234 / 255, alpha: 1)
            let coordinator = context.coordinator
            Task { @MainActor in
                await Task.yield()
                coordinator.onReady(navigator)
            }
            return navigator
        } catch {
            let unavailable = UIViewController()
            unavailable.view.backgroundColor = UIColor(red: 250 / 255, green: 246 / 255, blue: 234 / 255, alpha: 1)
            let label = UILabel()
            label.text = "تعذّر عرض هذا الكتاب"
            label.font = .preferredFont(forTextStyle: .body)
            label.textColor = .secondaryLabel
            label.textAlignment = .center
            label.translatesAutoresizingMaskIntoConstraints = false
            unavailable.view.addSubview(label)
            NSLayoutConstraint.activate([
                label.centerXAnchor.constraint(equalTo: unavailable.view.centerXAnchor),
                label.centerYAnchor.constraint(equalTo: unavailable.view.centerYAnchor),
                label.leadingAnchor.constraint(greaterThanOrEqualTo: unavailable.view.leadingAnchor, constant: 24),
                label.trailingAnchor.constraint(lessThanOrEqualTo: unavailable.view.trailingAnchor, constant: -24)
            ])
            return unavailable
        }
    }

    func updateUIViewController(_ controller: UIViewController, context: Context) {
        context.coordinator.onLocation = onLocation
        context.coordinator.onInteraction = onInteraction
        context.coordinator.onSelection = onSelection
        context.coordinator.onReady = onReady
        context.coordinator.onError = onError
        (controller as? EPUBNavigatorViewController)?.delegate = context.coordinator
    }

    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        var onLocation: (Locator, Bool) -> Void
        var onInteraction: () -> Void
        var onSelection: (Selection) -> Void
        var onReady: (EPUBNavigatorViewController) -> Void
        var onError: (NavigatorError) -> Void

        init(onLocation: @escaping (Locator, Bool) -> Void, onInteraction: @escaping () -> Void, onSelection: @escaping (Selection) -> Void, onReady: @escaping (EPUBNavigatorViewController) -> Void, onError: @escaping (NavigatorError) -> Void) {
            self.onLocation = onLocation
            self.onInteraction = onInteraction
            self.onSelection = onSelection
            self.onReady = onReady
            self.onError = onError
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) { onLocation(locator, false) }
        func navigator(_ navigator: Navigator, didJumpTo locator: Locator) { onLocation(locator, true) }
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) { onError(error) }
        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) { onInteraction() }
        func navigator(_ navigator: Navigator, presentExternalURL url: URL) { onInteraction() }
        /// Madar's word card replaces the system edit menu (RMI1: meaning through the system Look Up only).
        func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
            onSelection(selection)
            return false
        }
        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            let source = """
            (() => {
              const apply = () => {
                const root = document.documentElement;
                if (!root) return false;
                const head = document.head;
                if (!head) return false;
                if (!head.querySelector('#madar-reader-style')) {
                  const style = document.createElement('style');
                  style.id = 'madar-reader-style';
                  style.textContent = `
                    h1 { font-family: var(--USER__fontFamily) !important; font-weight: 700 !important; font-size: 1.45em !important; line-height: 1.35 !important; margin-block: .35em .55em !important; text-align: center !important; }
                    h1::before { content: 'فصل'; display: block; color: #6A6052; font-size: .56em; font-weight: 400; margin-bottom: .32em; }
                    h1::after { content: ''; display: block; width: 3.8em; border-top: 1px solid #B7AA95; margin: .58em auto 0; }
                    p { margin-block: .7em !important; }
                    a[role~='doc-noteref'] { display: inline-block; min-width: 1.25em; padding: .02em .18em; border-radius: 50%; background: #9E2F25 !important; color: #FAF6EA !important; font-size: .74em; font-weight: 600; line-height: 1.25; text-align: center; text-decoration: none !important; }
                  `;
                  head.appendChild(style);
                }
                return true;
              };
              if (!apply()) new MutationObserver((_, observer) => { if (apply()) observer.disconnect(); }).observe(document, {childList:true, subtree:true});
            })();
            """
            userContentController.addUserScript(WKUserScript(source: source, injectionTime: .atDocumentStart, forMainFrameOnly: true))
        }
    }
}

// MARK: - M6-V08 word card

struct MihbaraWordCardState: Identifiable, Equatable {
    let id = UUID()
    var word: String
    var isWord: Bool
    var selection: Locator?
    var paragraph: Locator
    var paragraphText: String
    var quote: String
    var page: Int?
    var pageLabel: String?
    var pageText: String?
    var highlightID: UUID?
    var color: String?
}

struct MihbaraLookupTerm: Identifiable { var word: String; var id: String { word } }
private struct MihbaraParagraphProbe: Decodable { var selector: String; var text: String; var page: String? }

extension MihbaraHighlight {
    static let group: DecorationGroup = "highlights"
    /// `rooms.mihbara.readerThemes.{paper,night}.highlight`, in `highlightNames` order.
    static let paper = ["#F3E3A0", "#D5E5C3", "#F1D0C8"]
    static let night = ["#5A4A1F", "#2F4A2C", "#5A2F2A"]
    static func title(_ color: String) -> String {
        switch color { case "yellow": "أصفر"; case "green": "أخضر"; default: "وردي" }
    }
}

extension UIColor {
    convenience init(madarHex hex: String) {
        let value = UInt32(hex.dropFirst(), radix: 16) ?? 0
        self.init(red: CGFloat((value >> 16) & 0xFF) / 255, green: CGFloat((value >> 8) & 0xFF) / 255, blue: CGFloat(value & 0xFF) / 255, alpha: 1)
    }
    var madarCSS: String {
        var r: CGFloat = 0, g: CGFloat = 0, b: CGFloat = 0, a: CGFloat = 0
        getRed(&r, green: &g, blue: &b, alpha: &a)
        return "rgb(\(Int((r * 255).rounded())), \(Int((g * 255).rounded())), \(Int((b * 255).rounded())))"
    }
}

private struct MihbaraWordCard: View {
    let state: MihbaraWordCardState
    let dark: Bool
    let copied: Bool
    let lookUp: () -> Void
    let choose: (String) -> Void
    let note: () -> Void
    let copy: () -> Void
    let close: () -> Void

    private var ink: SwiftUI.Color { dark ? SwiftUI.Color(red: 233 / 255, green: 225 / 255, blue: 210 / 255) : SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255) }
    private var ink2: SwiftUI.Color { dark ? SwiftUI.Color(red: 171 / 255, green: 161 / 255, blue: 146 / 255) : SwiftUI.Color(red: 106 / 255, green: 96 / 255, blue: 82 / 255) }
    private var accent: SwiftUI.Color { dark ? SwiftUI.Color(red: 220 / 255, green: 165 / 255, blue: 100 / 255) : SwiftUI.Color(red: 158 / 255, green: 47 / 255, blue: 37 / 255) }
    private var surface: SwiftUI.Color { dark ? SwiftUI.Color(red: 42 / 255, green: 38 / 255, blue: 31 / 255) : SwiftUI.Color(red: 255 / 255, green: 253 / 255, blue: 248 / 255) }
    private var well: SwiftUI.Color { ink.opacity(dark ? 0.10 : 0.05) }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.word)
                        .font(.custom("Amiri-Bold", size: state.isWord ? 30 : 22, relativeTo: .title))
                        .foregroundStyle(ink).lineLimit(2).multilineTextAlignment(.leading)
                        .accessibilityIdentifier("mihbara-word-title")
                    if state.isWord {
                        Button(action: lookUp) {
                            HStack(spacing: 6) {
                                Image(systemName: "character.book.closed").font(.system(size: 15, weight: .semibold))
                                Text("معناها في قاموس الجهاز").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body))
                            }
                            .foregroundStyle(accent).frame(minHeight: 32).contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("mihbara-word-lookup")
                    } else if let page = state.pageText {
                        Text("فقرة مظلّلة من \(page)").font(MadarTypography.caption()).foregroundStyle(ink2)
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink2)
                        .frame(width: 44, height: 44).background(Circle().fill(well)).contentShape(Circle())
                }
                .accessibilityLabel("إغلاق")
                .accessibilityIdentifier("mihbara-word-close")
            }
            HStack(spacing: 12) {
                Text("ظلّل الفقرة").font(MadarTypography.fine()).foregroundStyle(ink2)
                ForEach(Array(MihbaraHighlight.colors.enumerated()), id: \.element) { index, color in
                    let selected = state.color == color
                    Button { choose(color) } label: {
                        Circle().fill(SwiftUI.Color(uiColor: UIColor(madarHex: (dark ? MihbaraHighlight.night : MihbaraHighlight.paper)[index])))
                            .overlay(Circle().strokeBorder(selected ? ink : ink2.opacity(0.35), lineWidth: selected ? 2.5 : 1))
                            .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(ink) } }
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .accessibilityLabel(selected ? "إزالة التظليل " + MihbaraHighlight.title(color) : "تظليل " + MihbaraHighlight.title(color))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("mihbara-highlight-\(color)")
                }
                Spacer(minLength: 0)
            }
            HStack(spacing: 10) {
                action("دوّن ملاحظة", icon: "square.and.pencil", id: "mihbara-word-note", run: note)
                action(copied ? "نُسخت" : "انسخ مع التوثيق", icon: copied ? "checkmark" : "doc.on.doc", id: "mihbara-word-copy", run: copy)
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(surface)
            .shadow(color: .black.opacity(dark ? 0.45 : 0.14), radius: 22, y: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mihbara-word-card")
    }

    private func action(_ title: String, icon: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 56)
            .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(well))
            .contentShape(Rectangle())
        }
        .accessibilityIdentifier(id)
    }
}

private struct MihbaraPageNoteSheet: View {
    let draft: MihbaraWordCardState
    let paper: SwiftUI.Color
    let pageText: String?
    let save: (String) async -> Bool
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var saving = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("إلغاء") { dismiss() }.font(MadarTypography.body()).frame(minHeight: 44)
                    .accessibilityIdentifier("mihbara-note-cancel")
                Spacer()
                Text("ملاحظة على الصفحة").font(MadarTypography.section())
                Spacer()
                Button("احفظ") {
                    saving = true
                    Task { if !(await save(text.trimmingCharacters(in: .whitespacesAndNewlines))) { saving = false } }
                }
                .font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body)).frame(minHeight: 44)
                .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                .accessibilityIdentifier("mihbara-note-save")
            }
            HStack(alignment: .top, spacing: 10) {
                RoundedRectangle(cornerRadius: 2).fill(SwiftUI.Color(red: 158 / 255, green: 47 / 255, blue: 37 / 255)).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.paragraphText).font(.custom("Amiri-Regular", size: 17, relativeTo: .body)).lineLimit(4).lineSpacing(4)
                    if let pageText { Text(pageText).font(MadarTypography.fine()).foregroundStyle(.secondary) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("ما الذي أوقفك هنا؟").font(MadarTypography.body()).foregroundStyle(.secondary).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $text).font(MadarTypography.body()).scrollContentBackground(.hidden).focused($focused)
                    .accessibilityLabel("نص الملاحظة").accessibilityIdentifier("mihbara-note-text")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(SwiftUI.Color.black.opacity(0.04)))
            Text("تُحفظ في دفتر هذا الكتاب مربوطة بهذه الفقرة.").font(MadarTypography.fine()).foregroundStyle(.secondary)
        }
        .padding(20)
        .background(paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .onAppear { focused = true }
    }
}

/// RMI1: the word's meaning comes only from the system dictionary.
private struct MihbaraDictionaryView: UIViewControllerRepresentable {
    let term: String
    func makeUIViewController(context: Context) -> UIReferenceLibraryViewController { UIReferenceLibraryViewController(term: term) }
    func updateUIViewController(_ controller: UIReferenceLibraryViewController, context: Context) {}
}
