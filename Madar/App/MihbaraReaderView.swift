import SwiftUI
import Observation
import UIKit
import WebKit
import SwiftData
import AVFoundation
import Translation
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
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var publication: Publication?
    @State private var localURL: URL?
    @State private var initialLocator: Locator?
    @State private var currentLocator: Locator?
    @State private var navigatorController: EPUBNavigatorViewController?
    @State private var focusPositionLabel: String?
    @State private var focusChromeVisible = false
    @State private var printPages: [MihbaraPrintPage] = []
    @State private var printMarkedLocator: Locator?
    @State private var positionCount = 0
    @State private var showingContents = false
    @State private var showingReaderSettings = false
    @State private var speechController = MihbaraSpeechController()
    @State private var autoScrollTask: Task<Void, Never>?
    @State private var autoScrollRunID = UUID()
    @State private var autoScrollPaused = false
    @State private var autoScrollPositionLabel: String?
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
    @State private var quoteCard: MihbaraQuoteCardContent?
    @State private var noteDraft: MihbaraWordCardState?
    @State private var lookupTerm: MihbaraLookupTerm?
    @State private var translationRequest: MihbaraTranslationRequest?
    @State private var translationAvailability: MihbaraTranslationAvailability = .unsupported
    @State private var wordAlreadySaved = false
    @State private var lastDecorationTap = Date.distantPast
    @State private var readerUndoID: UUID?
    @State private var copiedAt: Date?
    @State private var footnote: MihbaraFootnote?
    /// M6-V12: an English book reads left to right with its own settings (`mihbara.readerEn`).
    @State private var isEnglish = false
    @State private var readingHistorySeconds = 0
    @State private var readingHistoryProgression = 0.0
    private var settingsKey: String { isEnglish ? "mihbara.readerEn" : "mihbara.readerAr" }
    private var englishReaderFont: MihbaraEnglishReaderFont {
        guard let value = readerSettings["font"]?.string else { return .literata }
        return MihbaraEnglishReaderFont(rawValue: value) ?? .literata
    }

    /// `mihbara.readerAr.theme`; «تلقائي» is paper by day and night after dark.
    private var palette: MihbaraReaderPalette {
        let chosen = readerSettings["theme"]?.string.flatMap(MihbaraReaderTheme.init(rawValue:)) ?? .auto
        return chosen.palette(dark: colorScheme == .dark)
    }
    private var paper: SwiftUI.Color { palette.bg }
    private var saveCoordinator: MihbaraReadingSaveCoordinator { .forSession(app) }
    private var digits: MadarNumberFormatter { AppMihbaraService(app: app).digits }
    private var readerTheme: ReadiumNavigator.Theme { palette.isDark ? .dark : .light }
    private var isSpeaking: Bool { speechController.isSpeaking }
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
        var merged = app.schema.settings.first(where: { $0.key == settingsKey })?.defaultValue.object ?? [:]
        if case .object(let stored)? = app.values[settingsKey] { merged.merge(stored) { _, new in new } }
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
    private var readerWordSpacing: Bool { readerBool("wordSpacing", false) }
    private var readerHyphenation: Bool { readerBool("hyphenation", true) }
    private var readerMode: String {
        guard let mode = readerSettings["mode"]?.string, ["pages", "scroll", "focus"].contains(mode) else { return "pages" }
        return mode
    }
    private var autoScrollSpeed: MihbaraAutoScrollSpeed {
        MihbaraAutoScrollSpeed(rawValue: readerSettings["autoScroll"]?.string ?? "off") ?? .off
    }
    private var readerFocus: Bool { readerMode == "focus" }
    private var readerScroll: Bool { readerMode != "pages" }
    private var readerFooter: MihbaraReaderFooter { readerSettings["footer"]?.string.flatMap(MihbaraReaderFooter.init(rawValue:)) ?? .full }
    private var englishReaderFooter: MihbaraEnglishReaderFooter { readerSettings["footer"]?.string.flatMap(MihbaraEnglishReaderFooter.init(rawValue:)) ?? .remaining }
    private var readerFont: MihbaraReaderFont {
        guard case .string(let id)? = readerSettings["font"] else { return .amiri }
        return MihbaraReaderFont(rawValue: id) ?? .amiri
    }
    private var readerFontPercent: Double { Double(95 + (readerSize - 1) * 10) }
    private var readerPreferences: EPUBPreferences {
        EPUBPreferences(
            backgroundColor: ReadiumNavigator.Color(hex: palette.hex.bg),
            fontFamily: isEnglish ? englishReaderFont.family : readerFont.family,
            // Readium's fontSize is a multiplier: 1.0 is the publisher's 100%.
            fontSize: readerFontPercent / 100,
            // A multiplier of the regular 400 weight, landing on a face the font really has.
            fontWeight: readerHeavier ? (isEnglish ? englishReaderFont.heavierWeight : readerFont.heavierWeight) : nil,
            hyphens: isEnglish ? readerHyphenation : nil,
            ligatures: true,
            lineHeight: [1.6, 1.95, 2.25, 2.6][readerLineSpacing - 1],
            pageMargins: [0.6, 1.0, 1.5, 2.0][readerMargins - 1],
            // Line height, alignment and weight apply only over the publisher's own styles.
            publisherStyles: false,
            readingProgression: isEnglish ? .ltr : .rtl,
            scroll: readerScroll,
            textAlign: readerJustify ? .justify : .start,
            textColor: ReadiumNavigator.Color(hex: palette.hex.ink),
            theme: readerTheme,
            wordSpacing: isEnglish && readerWordSpacing ? 0.1 : 0.0
        )
    }

    var body: some View {
        // A fixed origin: `.now` would restart the timeline on every redraw.
        TimelineView(.periodic(from: Date(timeIntervalSinceReferenceDate: 0), by: 5)) { tick in
            VStack(spacing: 0) {
                if !readerFocus || focusChromeVisible {
                    header
                    Rectangle().fill(palette.line).frame(height: 1)
                }
                if let publication {
                    MihbaraEPUBNavigator(
                        publication: publication,
                        initialLocation: initialLocator,
                        preferences: readerPreferences,
                        background: palette.hex.bg,
                        onLocation: locationChanged,
                        onInteraction: readerTapped,
                        onSelection: selectionChanged,
                        onDocumentReady: { applyFocusMode(); synchronizeAutoScroll() },
                        onFootnote: { note in
                            recordInteraction()
                            lastDecorationTap = Date()
                            if wordCard != nil { closeWordCard() }
                            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { footnote = note }
                        },
                        onReady: { navigator in
                            navigatorController = navigator
                            applyFocusMode()
                            synchronizeAutoScroll()
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
                if readerFocus { focusFooter } else { footer }
            }
            .overlay(alignment: .bottom) {
                VStack(spacing: 8) {
                    if readerFocus && wordCard == nil && footnote == nil { focusControls }
                    readerOverlay
                }
                .padding(.bottom, readerFocus && wordCard == nil && footnote == nil ? 45 : 0)
            }
            .background(paper.ignoresSafeArea())
        .foregroundStyle(palette.ink)
            .environment(\.layoutDirection, .rightToLeft)
            .onChange(of: tick.date) { _, date in
                advanceClock(to: date)
            }
        }
        .task { await openPublication() }
        .onChange(of: app.values[settingsKey]) {
            navigatorController?.submitPreferences(readerPreferences)
            applyFocusMode()
        }
        .onChange(of: autoScrollSpeed) { _, speed in
            if speed == .off {
                cancelAutoScroll(clearActive: true)
            } else {
                autoScrollPaused = false
                cancelAutoScroll(clearActive: false)
                synchronizeAutoScroll()
            }
        }
        .onChange(of: readerMode) { _, mode in
            if mode != "scroll" {
                cancelAutoScroll(clearActive: true)
            } else {
                synchronizeAutoScroll()
            }
        }
        .onChange(of: readerFocus) { _, isFocused in
            if isFocused { focusChromeVisible = false }
            applyFocusMode()
        }
        // An undo from the toast, or anywhere else, repaints the page from the store.
        .onChange(of: app.undoToken?.id) { reloadHighlights() }
        .onChange(of: palette) { applyHighlights() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active {
                resumeReader(at: Date())
                synchronizeAutoScroll()
            } else {
                pauseReader(at: Date())
                stopNarration()
                cancelAutoScroll(clearActive: false)
            }
        }
        .onChange(of: saveCoordinator.canWrite) { _, authorized in
            if authorized, scenePhase == .active { resumeReader(at: Date()); synchronizeAutoScroll() }
            else if !authorized { pauseReader(at: Date()); stopNarration(); cancelAutoScroll(clearActive: false) }
        }
        .onChange(of: showingContents || showingReaderSettings || noteDraft != nil || lookupTerm != nil || translationRequest != nil || wordCard != nil || quoteCard != nil || footnote != nil) { _, covered in
            if covered { pauseReader(at: Date()); stopNarration(); cancelAutoScroll(clearActive: false) }
            else if scenePhase == .active { resumeReader(at: Date()); synchronizeAutoScroll() }
        }
        .onChange(of: speechController.isActive) { _, isActive in
            if isActive { cancelAutoScroll(clearActive: false) }
            else { synchronizeAutoScroll() }
        }
        .onDisappear {
            pauseReader(at: Date())
            stopNarration()
            cancelAutoScroll(clearActive: true)
            pendingLocatorSave?.cancel()
            if let localURL { try? FileManager.default.removeItem(at: localURL) }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .statusBarHidden(true)
        .sheet(isPresented: $showingContents) {
            MihbaraContentsSheet(publication: publication, palette: palette, current: currentLocator) { link in
                showingContents = false
                Task { @MainActor in
                    _ = await navigatorController?.go(to: link, options: .animated)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(isPresented: $showingReaderSettings) {
            MihbaraReaderSettingsSheet(
                app: app, paper: paper, palette: palette, english: isEnglish,
                options: .init(theme: readerSettings["theme"]?.string.flatMap(MihbaraReaderTheme.init(rawValue:)) ?? .auto, size: readerSize, font: readerFont, mode: readerMode, lineSpacing: readerLineSpacing,
                               margins: readerMargins, justify: readerJustify, heavier: readerHeavier, footer: readerFooter,
                               englishFont: englishReaderFont, englishFooter: englishReaderFooter, hyphenation: readerHyphenation, wordSpacing: readerWordSpacing,
                               autoScroll: autoScrollSpeed),
                undoTokenID: readerUndoID,
                set: updateReaderSetting,
                reset: { app.reset([settingsKey]) { readerUndoID = app.undoToken?.id } }
            )
            .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(item: $noteDraft) { draft in
            MihbaraPageNoteSheet(draft: draft, palette: palette, pageText: draft.pageText) { text in
                await savePageNote(text, for: draft)
            }
            .environment(\.layoutDirection, .rightToLeft)
        }
        .sheet(item: $lookupTerm) { term in
            MihbaraDictionaryView(term: term.word).ignoresSafeArea()
        }
        .sheet(item: $translationRequest) { request in
            if #available(iOS 18.0, *) {
                MihbaraTranslationSheet(request: request, paper: paper, palette: palette)
                    .environment(\.layoutDirection, .rightToLeft)
            } else {
                Text("الترجمة غير متاحة في هذا الإصدار.")
                    .font(MadarTypography.body()).padding(28).background(paper.ignoresSafeArea())
            }
        }
        .sheet(item: $quoteCard) { card in
            MihbaraQuoteCardSheet(app: app, card: card)
                .environment(\.layoutDirection, .rightToLeft)
                .presentationDetents([.large])
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
                    .foregroundStyle(palette.ink2)
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
                        Image(systemName: speechController.isActive ? (isSpeaking ? "pause.fill" : "play.fill") : "headphones").font(.system(size: 18, weight: .regular))
                            .frame(width: 32, height: 44).contentShape(Rectangle())
                    }
                    .accessibilityLabel(speechController.isActive ? (isSpeaking ? "إيقاف القراءة الصوتية مؤقتًا" : "متابعة القراءة الصوتية") : "استمع إلى هذا الفصل")
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
        if isEnglish || readerFooter != .none { footerContent }
    }

    private var focusFooter: some View {
        Text(footerLabel)
            .font(MadarTypography.caption())
            .foregroundStyle(palette.ink2)
            .lineLimit(1)
            .minimumScaleFactor(0.85)
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 18)
            .padding(.top, 8)
            .padding(.bottom, 11)
            .background(paper)
            .accessibilityIdentifier("mihbara-reader-footer-value")
    }

    private var focusControls: some View {
        GlassEffectContainer(spacing: 8) {
            HStack(spacing: 12) {
                Button { stepFocus(-1) } label: {
                    Image(systemName: "chevron.up")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 34)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("الفقرة السابقة")
                .accessibilityValue(focusPositionLabel ?? "")
                .accessibilityIdentifier("mihbara-focus-previous")

                Text("وضع التركيز")
                    .font(MadarTypography.caption().weight(.semibold))
                    .fixedSize()

                Button { stepFocus(1) } label: {
                    Image(systemName: "chevron.down")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 36, height: 34)
                        .contentShape(.capsule)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("الفقرة التالية")
                .accessibilityValue(focusPositionLabel ?? "")
                .accessibilityIdentifier("mihbara-focus-next")
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 7)
            .padding(.vertical, 5)
            .glassEffect(.regular.interactive(), in: Capsule())
            .overlay { Capsule().stroke(palette.line.opacity(0.8), lineWidth: 0.7) }
            .shadow(color: .black.opacity(palette.isDark ? 0.22 : 0.12), radius: 15, y: 5)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mihbara-focus-controls")
        }
    }

    private var footerContent: some View {
        VStack(spacing: 7) {
            if let readerProgress {
                ProgressView(value: readerProgress)
                    .tint(palette.accent)
                    .accessibilityLabel("تقدّم الكتاب")
                    .accessibilityValue(digits.string(Int((readerProgress * 100).rounded())) + "٪")
                    .accessibilityIdentifier("mihbara-reader-progress")
            } else {
                Rectangle().fill(palette.line).frame(height: 3)
            }
            if isEnglish {
                HStack(alignment: .center) {
                    Text(footerLabel)
                        .font(MadarTypography.caption()).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("mihbara-reader-footer-value")
                    Spacer(minLength: 4)
                }
            } else if readerFooter != .bar {
                HStack(alignment: .center, spacing: 12) {
                    Text(printPageLabel)
                        .font(MadarTypography.caption()).lineLimit(1).minimumScaleFactor(0.8)
                        .accessibilityIdentifier("mihbara-reader-print-page")
                    Spacer(minLength: 4)
                    if readerFooter == .full || speechController.isActive {
                        Text(speechController.isActive ? (isSpeaking ? "تُقرأ الفقرة بصوت \(isEnglish ? "إنجليزي" : "عربي")" : "القراءة الصوتية متوقفة مؤقتًا") : (readingClock?.activeSeconds ?? 0) >= 60 ? "الجلسة بدأت · تُسجَّل وحدها" : "تُسجَّل الجلسة بعد دقيقة نشاط")
                            .font(MadarTypography.fine()).foregroundStyle(palette.ink2)
                    }
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 11)
        .overlay(alignment: .top) { Rectangle().fill(palette.line).frame(height: 1) }
        .background(paper)
    }

    private var footerLabel: String {
        guard isEnglish else { return printPageLabel }
        switch englishReaderFooter {
        case .page:
            if !printPages.isEmpty { return printPageLabel }
            if let position = currentLocator?.locations.position, positionCount > 0 {
                return "الموضع \(digits.string(position)) من \(digits.string(positionCount))"
            }
            return "موضع القراءة يتضح بعد فتح الصفحة"
        case .percentage:
            guard let readerProgress else { return "النسبة غير متاحة في هذا الملف" }
            return "تقدّم \(digits.string(Int((readerProgress * 100).rounded())))٪"
        case .remaining:
            guard let readerProgress, readerProgress < 0.99 else { return readerProgress == nil ? "نحسب الوقت مع تقدّم القراءة" : "بقي أقل من دقيقة" }
            let activeSeconds = readingHistorySeconds + Int(readingClock?.activeSeconds ?? 0)
            let measuredProgress = max(readerProgress, readingHistoryProgression)
            guard activeSeconds >= 60, measuredProgress > 0 else { return "نقدّر الوقت بعد دقيقة قراءة" }
            let minutes = max(0, Int(ceil(Double(activeSeconds) * (1 - readerProgress) / measuredProgress / 60)))
            return minutes == 0 ? "بقي أقل من دقيقة" : "المتبقي تقريبًا: " + PrayerCopy.minutes(minutes, digits: digits)
        }
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
            isEnglish = opened.metadata.languages.first?.lowercased().hasPrefix("en") ?? false

            let saved = readiumLocator(book.locatorJSON)
            let now = Date()
            let (readyPublication, firstLocator, readyPages, readyPositionCount) = await prepareReader(from: opened)
            let startLocator = saved ?? firstLocator
            initialLocator = startLocator
            currentLocator = startLocator
            let context = ModelContext(app.container)
            let sessions = (try? context.fetch(FetchDescriptor<ReadingSession>()))?.filter {
                $0.bookID == book.id && $0.deletedAt == nil && $0.mergedInto == nil
            } ?? []
            readingHistorySeconds = sessions.reduce(0) { $0 + max(0, $1.activeSeconds) }
            readingHistoryProgression = sessions.reduce(0.0) { max($0, $1.endProgression) }
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
        if readerFocus { applyFocusMode() }
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
        if let footnote {
            MihbaraFootnoteCard(note: footnote, palette: palette, number: digits.localized(footnote.number)) {
                withAnimation(.easeOut(duration: 0.2)) { self.footnote = nil }
            }
            .padding(.horizontal, 12).padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if let wordCard {
            MihbaraWordCard(
                state: wordCard, palette: palette, swatches: palette.hex.highlight, copied: copiedAt != nil,
                wordSaved: wordAlreadySaved, translationAvailability: translationAvailability,
                lookUp: { lookupTerm = .init(word: wordCard.word) },
                saveWord: { Task { await saveWordToLibrary(wordCard) } },
                translate: { translationRequest = .init(text: wordCard.paragraphText, sourceLanguage: "en") },
                choose: { color in Task { await chooseHighlight(color, for: wordCard) } },
                note: { noteDraft = wordCard },
                copy: { Task { await copyWithCitation(wordCard) } },
                makeQuoteCard: { makeQuoteCard(from: wordCard) },
                close: closeWordCard
            )
            .padding(.horizontal, 12).padding(.bottom, 10)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        } else if speechController.isActive {
            listeningPlayer
        } else if shouldShowAutoScrollPlayer {
            autoScrollPlayer
        } else if let token = app.undoToken, token.id == readerUndoID, !showingReaderSettings {
            UndoToast(message: app.undoMessage, undo: app.undo)
                .accessibilityIdentifier("mihbara-reader-toast")
                .padding(.bottom, 64)
        }
    }

    private var shouldShowAutoScrollPlayer: Bool {
        autoScrollSpeed != .off && readerMode == "scroll" && !showingReaderSettings
            && !showingContents && noteDraft == nil && lookupTerm == nil && quoteCard == nil
            && translationRequest == nil && wordCard == nil && footnote == nil
    }

    private var autoScrollPlayer: some View {
        GlassEffectContainer(spacing: 10) {
            HStack(spacing: 12) {
                Button {
                    if autoScrollPaused {
                        autoScrollPaused = false
                        synchronizeAutoScroll()
                    } else {
                        autoScrollPaused = true
                        cancelAutoScroll(clearActive: false)
                    }
                } label: {
                    Image(systemName: autoScrollPaused ? "play.fill" : "pause.fill")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(palette.bg)
                        .frame(width: 42, height: 42)
                        .background(palette.accent, in: Circle())
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel(autoScrollPaused ? "متابعة التمرير التلقائي" : "إيقاف التمرير مؤقتًا")
                .accessibilityIdentifier("mihbara-auto-scroll-play-pause")

                VStack(alignment: .leading, spacing: 2) {
                    Text(autoScrollPaused ? "التمرير متوقف مؤقتًا" : "تمرير تلقائي · \(autoScrollSpeed.title)")
                        .font(MadarTypography.caption().weight(.semibold))
                        .lineLimit(1)
                    Text(autoScrollPositionLabel ?? "يتابع الفقرة الحالية")
                        .font(MadarTypography.fine()).foregroundStyle(palette.ink2).lineLimit(1)
                        .accessibilityIdentifier("mihbara-auto-scroll-position")
                }
                Spacer(minLength: 4)

                Button { updateReaderSetting("autoScroll", .string("off")) } label: {
                    Image(systemName: "stop.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .frame(width: 38, height: 38)
                        .contentShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("إيقاف التمرير التلقائي")
                .accessibilityIdentifier("mihbara-auto-scroll-stop")
            }
            .foregroundStyle(palette.ink)
            .padding(.horizontal, 13).padding(.vertical, 9)
            .background(paper.opacity(palette.isDark ? 0.72 : 0.82), in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 24, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 24, style: .continuous).stroke(palette.line, lineWidth: 0.8) }
            .shadow(color: .black.opacity(palette.isDark ? 0.22 : 0.12), radius: 15, y: 5)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mihbara-auto-scroll-player")
        }
        .padding(.horizontal, 12).padding(.bottom, 10)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    private var listeningPlayer: some View {
        GlassEffectContainer(spacing: 10) {
            VStack(spacing: 11) {
                HStack(spacing: 12) {
                    Button(action: toggleNarration) {
                        Image(systemName: isSpeaking ? "pause.fill" : "play.fill")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(palette.bg)
                            .frame(width: 46, height: 46)
                            .background(palette.accent, in: Circle())
                            .contentShape(Circle())
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel(isSpeaking ? "إيقاف القراءة الصوتية مؤقتًا" : "متابعة القراءة الصوتية")
                    .accessibilityIdentifier("mihbara-listening-play-pause")

                    VStack(alignment: .trailing, spacing: 3) {
                        Text(isSpeaking ? "يقرأ لك الآن" : "القراءة متوقفة مؤقتًا")
                            .font(MadarTypography.section())
                            .foregroundStyle(palette.ink)
                            .accessibilityIdentifier("mihbara-listening-title")
                        Text("صوت \(isEnglish ? "إنجليزي" : "عربي") من جهازك، الفقرة \(digits.string(speechController.currentIndex + 1)) من \(digits.string(speechController.paragraphCount))")
                            .font(MadarTypography.fine())
                            .foregroundStyle(palette.ink2)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                            .accessibilityIdentifier("mihbara-listening-paragraph")
                    }
                    .frame(maxWidth: .infinity, alignment: .trailing)

                    Button(action: stopNarration) {
                        Image(systemName: "xmark")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(palette.ink2)
                            .frame(width: 40, height: 40)
                            .contentShape(Circle())
                    }
                    .glassEffect(.regular.interactive(), in: Circle())
                    .accessibilityLabel("إنهاء الاستماع")
                    .accessibilityIdentifier("mihbara-listening-stop")
                }

                HStack(spacing: 6) {
                    ForEach(MihbaraListeningSpeed.allCases, id: \.self) { speed in
                        let selected = speechController.speed == speed.rawValue
                        Button { speechController.setSpeed(speed.rawValue) } label: {
                            Text(digits.localized(speed.numberText + "×"))
                                .font(MadarTypography.fine())
                                .foregroundStyle(selected ? palette.bg : palette.ink2)
                                .frame(maxWidth: .infinity, minHeight: 40)
                                .background(selected ? palette.accent : .clear, in: Capsule())
                                .contentShape(Capsule())
                        }
                        .buttonStyle(.plain)
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .accessibilityLabel("سرعة \(digits.localized(speed.numberText)) مرة")
                        .accessibilityValue(selected ? "السرعة الحالية" : "")
                        .accessibilityIdentifier("mihbara-listening-speed-\(speed.identifier)")
                    }
                }
            }
            .padding(.horizontal, 14)
            .padding(.vertical, 12)
            .background(paper.opacity(palette.isDark ? 0.72 : 0.82), in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 26, style: .continuous))
            .overlay { RoundedRectangle(cornerRadius: 26, style: .continuous).stroke(palette.line, lineWidth: 0.8) }
            .shadow(color: .black.opacity(palette.isDark ? 0.24 : 0.13), radius: 18, y: 7)
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mihbara-listening-player")
        }
        .padding(.horizontal, 12)
        .padding(.bottom, 10)
        .transition(reduceMotion ? .opacity : .move(edge: .bottom).combined(with: .opacity))
    }

    @MainActor private func applyFocusMode() {
        guard let navigatorController else { return }
        let enabled = readerFocus
        let script = "window.madarReaderSetFocusMode ? window.madarReaderSetFocusMode(\(enabled ? "true" : "false")) : ''"
        Task { @MainActor in
            guard case .success(let value) = await navigatorController.evaluateJavaScript(script),
                  self.navigatorController === navigatorController,
                  readerFocus == enabled else { return }
            focusPositionLabel = focusPositionLabel(from: value)
        }
    }

    @MainActor private func synchronizeAutoScroll() {
        let shouldRun = autoScrollSpeed != .off && readerMode == "scroll"
            && scenePhase == .active && !showingContents && !showingReaderSettings
            && noteDraft == nil && lookupTerm == nil && translationRequest == nil
            && wordCard == nil && footnote == nil && !speechController.isActive
            && !isClosing && saveCoordinator.canWrite
        guard shouldRun else {
            cancelAutoScroll(clearActive: autoScrollSpeed == .off || readerMode != "scroll")
            return
        }
        guard !autoScrollPaused, autoScrollTask == nil, let navigatorController else { return }
        let runID = UUID()
        autoScrollRunID = runID
        let speed = autoScrollSpeed
        autoScrollTask = Task { @MainActor in
            await runAutoScroll(on: navigatorController, speed: speed, runID: runID)
        }
    }

    @MainActor private func cancelAutoScroll(clearActive: Bool) {
        autoScrollRunID = UUID()
        autoScrollTask?.cancel()
        autoScrollTask = nil
        if clearActive {
            autoScrollPositionLabel = nil
            guard let navigatorController else { return }
            Task { @MainActor in
                _ = await navigatorController.evaluateJavaScript("window.madarReaderAutoScrollClear ? window.madarReaderAutoScrollClear() : ''")
            }
        }
    }

    @MainActor private func runAutoScroll(on navigator: EPUBNavigatorViewController, speed: MihbaraAutoScrollSpeed, runID: UUID) async {
        defer {
            if autoScrollRunID == runID { autoScrollTask = nil }
        }
        let start = await navigator.evaluateJavaScript("window.madarReaderAutoScrollStart ? window.madarReaderAutoScrollStart() : ''")
        guard autoScrollRunID == runID, !Task.isCancelled,
              case .success(let startValue) = start,
              let position = autoScrollPosition(from: startValue) else { return }
        autoScrollPositionLabel = position.label(digits: digits)
        var words = position.wordCount

        while autoScrollRunID == runID, !Task.isCancelled {
            let seconds = min(32, max(2.5, Double(words) / speed.wordsPerMinute * 60))
            do { try await Task.sleep(for: .seconds(seconds)) } catch { return }
            guard autoScrollRunID == runID, !Task.isCancelled else { return }
            let result = await navigator.evaluateJavaScript("window.madarReaderAutoScrollStep ? window.madarReaderAutoScrollStep() : ''")
            guard autoScrollRunID == runID, !Task.isCancelled, case .success(let value) = result,
                  let raw = value as? String else { return }
            if raw == "end" {
                autoScrollPaused = true
                return
            }
            guard let next = autoScrollPosition(from: raw) else { return }
            autoScrollPositionLabel = next.label(digits: digits)
            words = next.wordCount
        }
    }

    private func autoScrollPosition(from value: Any) -> MihbaraAutoScrollPosition? {
        guard let raw = value as? String, let data = raw.data(using: .utf8) else { return nil }
        return try? JSONDecoder().decode(MihbaraAutoScrollPosition.self, from: data)
    }

    @MainActor private func stepFocus(_ direction: Int) {
        guard let navigatorController else { return }
        // A scroll-mode preference change can reload the same locator without a location callback.
        // Re-enable focus in the current document before stepping so its per-document state is restored.
        let script = "if (window.madarReaderSetFocusMode) window.madarReaderSetFocusMode(true); window.madarReaderStepFocus ? window.madarReaderStepFocus(\(direction)) : ''"
        Task { @MainActor in
            guard case .success(let value) = await navigatorController.evaluateJavaScript(script),
                  self.navigatorController === navigatorController,
                  readerFocus else { return }
            focusPositionLabel = focusPositionLabel(from: value)
        }
    }

    private func focusPositionLabel(from value: Any) -> String? {
        guard let raw = value as? String else { return nil }
        let parts = raw.split(separator: "/", maxSplits: 1)
        guard parts.count == 2, let index = Int(parts[0]), let total = Int(parts[1]), index > 0, total > 0 else { return nil }
        return "الفقرة \(digits.string(index)) من \(digits.string(total))"
    }

    @MainActor private func readerTapped() {
        recordInteraction()
        if readerFocus {
            if reduceMotion { focusChromeVisible.toggle() }
            else { withAnimation(.easeInOut(duration: 0.18)) { focusChromeVisible.toggle() } }
        }
        guard wordCard != nil || footnote != nil else { return }
        let tapped = Date()
        Task { @MainActor in
            // A tap on a highlight or a note marker reports both the tap and its target; the target wins.
            try? await Task.sleep(for: .milliseconds(300))
            guard lastDecorationTap < tapped.addingTimeInterval(-0.05) else { return }
            if wordCard != nil { closeWordCard() }
            if footnote != nil { withAnimation(.easeOut(duration: 0.2)) { footnote = nil } }
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
            state.hasSystemDefinition = selectionText.map(UIReferenceLibraryViewController.dictionaryHasDefinition(forTerm:)) ?? false
            copiedAt = nil
            wordAlreadySaved = savedWordExists(state.word, language: isEnglish ? "en" : "ar")
            translationAvailability = isEnglish ? .checking : .unsupported
            withAnimation(.spring(response: 0.32, dampingFraction: 0.86)) { wordCard = state }
            if isEnglish { Task { await refreshTranslationAvailability(for: state.id) } }
        }
    }

    @MainActor private func savedWordExists(_ word: String, language: String) -> Bool {
        let key = UserWordIdentity.key(language: language, word: word)
        let context = ModelContext(app.container)
        return (try? context.fetch(FetchDescriptor<UserWord>()))?.contains {
            $0.deletedAt == nil && $0.mergedInto == nil && UserWordIdentity.key(language: $0.language, word: $0.word) == key
        } ?? false
    }

    @MainActor private func refreshTranslationAvailability(for cardID: UUID) async {
        guard #available(iOS 18.0, *) else { translationAvailability = .unsupported; return }
        let availability = LanguageAvailability()
        let status = await availability.status(
            from: Locale.Language(identifier: "en"),
            to: Locale.Language(identifier: "ar")
        )
        guard wordCard?.id == cardID else { return }
        switch status {
        case .installed: translationAvailability = .installed
        case .supported: translationAvailability = .needsDownload
        case .unsupported: translationAvailability = .unsupported
        @unknown default: translationAvailability = .unsupported
        }
    }

    @MainActor private func saveWordToLibrary(_ card: MihbaraWordCardState) async {
        guard card.canSaveAsWord, let selection = card.selection,
              let locator = try? selection.jsonString() else { return }
        let language = isEnglish ? "en" : "ar"
        do {
            try await app.executeBookCommand("word.save", payload: [
                "id": .string(UUID().uuidString), "word": .string(card.word), "language": .string(language),
                "bookID": .string(book.id.uuidString), "bookTitle": .string(book.title),
                "locator": .string(locator), "context": .string(String(card.paragraphText.prefix(4000)))
            ], undoMessage: "أُضيفت إلى كلماتي · التراجع متاح لعشر دقائق")
            wordAlreadySaved = true
            readerUndoID = app.undoToken?.id
            closeWordCard()
        } catch { readerAlert = error.localizedDescription }
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
        let palette = palette.hex.highlight
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
            try? await Task.sleep(for: .seconds(2.4))
            if copiedAt == stamp { copiedAt = nil }
        }
    }

    @MainActor private func makeQuoteCard(from state: MihbaraWordCardState) {
        guard state.highlightID != nil else { return }
        let quote = state.paragraphText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !quote.isEmpty else { return }
        quoteCard = MihbaraQuoteCardContent(
            quote: quote, bookTitle: book.title, author: book.author,
            pageLabel: state.pageLabel, turathID: book.turathID, digits: digits
        )
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
            readingHistorySeconds += readingClock?.activeSeconds ?? 0
            readingHistoryProgression = max(readingHistoryProgression, currentLocator?.locations.totalProgression ?? 0)
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
        if key == "autoScroll", value.string != "off" {
            settings["mode"] = .string("scroll")
        }
        if key == "mode", value.string != "scroll" {
            settings["autoScroll"] = .string("off")
        }
        app.set(.object(settings), key: settingsKey) { readerUndoID = app.undoToken?.id }
    }

    @MainActor private func toggleNarration() {
        if speechController.isActive {
            speechController.togglePlayback()
            return
        }
        guard let navigatorController else {
            readerAlert = "لم يجهز القارئ للصوت بعد."
            return
        }
        recordInteraction()
        Task { @MainActor in
            let result = await navigatorController.evaluateJavaScript("window.madarReaderSpeechQueue ? window.madarReaderSpeechQueue() : ''")
            guard case .success(let value) = result, let raw = value as? String,
                  let data = raw.data(using: .utf8), let document = try? JSONDecoder().decode(MihbaraSpeechDocument.self, from: data) else {
                readerAlert = "تعذّر تجهيز فقرات هذا الفصل للاستماع."
                return
            }
            guard !document.paragraphs.isEmpty else {
                readerAlert = "لا يوجد نص قابل للقراءة في هذا الموضع."
                return
            }
            let prefix = isEnglish ? "en" : "ar"
            let preferred = isEnglish ? "en-US" : "ar-SA"
            let voices = AVSpeechSynthesisVoice.speechVoices().filter { $0.language.hasPrefix(prefix) }
            guard let voice = voices.first(where: { $0.language == preferred }) ?? voices.first else {
                readerAlert = "لا يتوفر صوت \(isEnglish ? "إنجليزي" : "عربي") على هذا الجهاز. ثبّت صوتًا من إعدادات تسهيلات الاستخدام ثم حاول مجددًا."
                return
            }
            let navigator = navigatorController
            speechController.onHighlightedParagraph = { [weak navigator] index in
                guard let navigator else { return }
                let script = index.map { "window.madarReaderSpeechSetActive ? window.madarReaderSpeechSetActive(\($0)) : ''" }
                    ?? "window.madarReaderSpeechClear ? window.madarReaderSpeechClear() : ''"
                Task { @MainActor in _ = await navigator.evaluateJavaScript(script) }
            }
            do {
                try speechController.start(
                    paragraphs: document.paragraphs,
                    startIndex: document.startIndex,
                    voice: voice
                )
            } catch {
                readerAlert = "تعذّر تشغيل الصوت. أعد المحاولة."
            }
        }
    }

    @MainActor private func stopNarration() {
        speechController.stop()
    }
}

private struct MihbaraContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let publication: Publication?
    let palette: MihbaraReaderPalette
    var current: Locator? = nil
    let select: (ReadiumShared.Link) -> Void

    private var items: [MihbaraTOCItem] { Self.flatten(publication?.manifest.tableOfContents ?? []) }

    /// The chapter the reader is in: the last entry whose file is at or before the current file. When several
    /// entries share that file the sheet can't tell which one the reader is in, so it marks none rather than guess.
    private var currentItem: MihbaraTOCItem? {
        guard let publication, let current else { return nil }
        let base = publication.baseURL
        var spineByFile: [String: Int] = [:]
        for (index, link) in publication.readingOrder.enumerated() {
            let key = link.url(relativeTo: base).removingFragment().string
            if spineByFile[key] == nil { spineByFile[key] = index }
        }
        guard let here = spineByFile[current.href.removingFragment().string]
            ?? publication.readingOrder.firstIndex(where: { $0.url(relativeTo: base).removingFragment().isEquivalentTo(current.href.removingFragment()) })
        else { return nil }
        let placed: [(item: MihbaraTOCItem, spine: Int)] = items.compactMap { item in
            spineByFile[item.link.url(relativeTo: base).removingFragment().string].map { (item: item, spine: $0) }
        }.filter { $0.spine <= here }
        guard let nearest = placed.map(\.spine).max() else { return nil }
        let candidates = placed.filter { $0.spine == nearest }
        if candidates.count == 1 { return candidates[0].item }
        let fragments = current.locations.fragments
        return candidates.first { entry in
            entry.item.link.url(relativeTo: base).fragment.map { fragments.contains($0) } ?? false
        }?.item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("فهرس الكتاب").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
                Spacer()
                Button("تمّ") { dismiss() }.font(MadarTypography.caption()).accessibilityIdentifier("mihbara-reader-contents-close")
            }
            if items.isEmpty {
                Text("لا يتضمن هذا الكتاب فهرسًا").font(MadarTypography.body()).foregroundStyle(palette.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let currentID = currentItem?.id
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                let here = item.id == currentID
                                Button { select(item.link) } label: {
                                    HStack(spacing: 10) {
                                        Text(item.link.title ?? "موضع في الكتاب").font(here ? MadarTypography.body().weight(.bold) : MadarTypography.body()).lineLimit(2)
                                        Spacer(minLength: 12)
                                        if here { Text("أنت هنا").font(MadarTypography.fine()).foregroundStyle(palette.ink2) }
                                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.ink2)
                                    }
                                    .padding(.leading, CGFloat(item.depth) * 18)
                                    .padding(.vertical, 12)
                                    .background(here ? palette.line.opacity(0.35) : .clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .accessibilityAddTraits(here ? .isSelected : [])
                                .accessibilityIdentifier("mihbara-reader-toc-" + item.id)
                                Rectangle().fill(palette.line).frame(height: 1)
                            }
                        }
                    }
                    .onAppear { if let currentID { proxy.scrollTo(currentID, anchor: .center) } }
                }
            }
        }
        .padding(20)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
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

enum MihbaraEnglishReaderFont: String, CaseIterable, Identifiable {
    case literata, sourceSerif, atkinsonHyperlegible, ibmPlexSerif
    var id: String { rawValue }
    var title: String {
        switch self {
        case .literata: "Literata"
        case .sourceSerif: "Source Serif"
        case .atkinsonHyperlegible: "Atkinson"
        case .ibmPlexSerif: "Plex Serif"
        }
    }
    var family: FontFamily {
        switch self {
        case .literata: FontFamily(rawValue: "Literata")
        case .sourceSerif: FontFamily(rawValue: "Source Serif 4")
        case .atkinsonHyperlegible: FontFamily(rawValue: "Atkinson Hyperlegible")
        case .ibmPlexSerif: FontFamily(rawValue: "IBM Plex Serif")
        }
    }
    var previewName: String {
        switch self {
        case .literata: "Literata-Regular"
        case .sourceSerif: "SourceSerif4Roman-Regular"
        case .atkinsonHyperlegible: "AtkinsonHyperlegible-Regular"
        case .ibmPlexSerif: "IBMPlexSerif-Regular"
        }
    }
    var files: [(name: String, ext: String, weight: CSSFontWeight)] {
        switch self {
        case .literata: [("Literata-Variable", "ttf", .variable(100...900))]
        case .sourceSerif: [("SourceSerif4-Variable", "ttf", .variable(200...900))]
        case .atkinsonHyperlegible: [("AtkinsonHyperlegible-Regular", "ttf", .standard(.normal)), ("AtkinsonHyperlegible-Bold", "ttf", .standard(.bold))]
        case .ibmPlexSerif: [("IBMPlexSerif-Regular", "ttf", .standard(.normal)), ("IBMPlexSerif-Bold", "ttf", .standard(.bold))]
        }
    }
    var heavierWeight: Double { self == .literata || self == .sourceSerif ? 600.0 / 400 : 700.0 / 400 }
}

enum MihbaraEnglishReaderFooter: String, CaseIterable, Identifiable {
    case remaining, percentage, page
    var id: String { rawValue }
    var title: String {
        switch self {
        case .remaining: "الوقت المتبقي"
        case .percentage: "النسبة"
        case .page: "رقم الصفحة"
        }
    }
}

struct MihbaraReaderOptions: Equatable {
    var theme: MihbaraReaderTheme
    var size: Int, font: MihbaraReaderFont, mode: String, lineSpacing: Int, margins: Int, justify: Bool, heavier: Bool, footer: MihbaraReaderFooter
    var englishFont: MihbaraEnglishReaderFont, englishFooter: MihbaraEnglishReaderFooter, hyphenation: Bool, wordSpacing: Bool
    var autoScroll: MihbaraAutoScrollSpeed
}

enum MihbaraAutoScrollSpeed: String, CaseIterable, Identifiable {
    case off, slow, medium, fast
    var id: String { rawValue }
    var title: String {
        switch self { case .off: "إيقاف"; case .slow: "بطيء"; case .medium: "متوسط"; case .fast: "سريع" }
    }
    var wordsPerMinute: Double {
        switch self { case .off: 170; case .slow: 110; case .medium: 175; case .fast: 260 }
    }
}

private struct MihbaraAutoScrollPosition: Decodable {
    let index: Int
    let total: Int
    let wordCount: Int
    func label(digits: MadarNumberFormatter) -> String {
        "الفقرة \(digits.string(index)) من \(digits.string(total))"
    }
}

/// «عرض الصفحة»: every choice is saved to `mihbara.readerAr` at once and applied live.
private struct MihbaraReaderSettingsSheet: View {
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
        guard let token = app.undoToken, let undoTokenID else { return false }
        return token.id == undoTokenID
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 9) {
                header
                themeRow
                sizeRow
                fontRow
                modeRow
                autoScrollRow
                Button { withAnimation(.smooth(duration: 0.25)) { more.toggle() } } label: {
                    Text(more ? "خيارات أقل" : "خيارات أكثر").font(MadarTypography.caption().weight(.semibold))
                        .frame(maxWidth: .infinity, minHeight: 32)
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
            if hasSettingsUndo {
                UndoToast(message: app.undoMessage, undo: app.undo)
                    .accessibilityIdentifier("mihbara-reader-undo")
                    .padding(.horizontal, 12)
                    .padding(.top, 4)
            }
        }
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            Text("عرض الصفحة").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
            Spacer(minLength: 8)
            Text(english ? "كتاب إنجليزي · إعداداتك للإنجليزي" : "كتاب عربي · إعداداتك للعربي").font(MadarTypography.fine().weight(.semibold))
                .lineLimit(1).minimumScaleFactor(0.8)
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
                                    Text(option.title).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.72)).lineLimit(1).minimumScaleFactor(0.75)
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
                .buttonStyle(.plain)
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
    let background: String
    let onLocation: (Locator, Bool) -> Void
    let onInteraction: () -> Void
    let onSelection: (Selection) -> Void
    let onDocumentReady: () -> Void
    let onFootnote: (MihbaraFootnote) -> Void
    let onReady: (EPUBNavigatorViewController) -> Void
    let onError: (NavigatorError) -> Void

    /// One opaque band behind the whole paragraph, across the page width (design tokens: never alpha over ink).
    private static var highlightTemplates: [Decoration.Style.Id: HTMLDecorationTemplate] {
        [.highlight: HTMLDecorationTemplate(
            // Per line, so a paragraph that crosses a page break is drawn on each page; the boxes grow
            // by the line gap so the lines join into one band.
            layout: .boxes, width: .viewport,
            element: { decoration in
                let tint = (decoration.style.config as? Decoration.Style.HighlightConfig)?.tint ?? .yellow
                return "<div class=\"madar-highlight\" style=\"background-color: \(tint.madarCSS) !important;\"/>"
            },
            stylesheet: ".madar-highlight { z-index: -1; margin: calc(-0.5em * var(--USER__lineHeight, 2) + 0.5em - 1px) 0 0 0; padding: 0 0 calc(1em * var(--USER__lineHeight, 2) - 1em + 2px) 0; box-sizing: content-box; }"
        )]
    }

    /// Every bundled reader font is declared once, so switching in the Aa sheet applies live.
    private static var fontDeclarations: [AnyHTMLFontFamilyDeclaration] {
        let arabic: [AnyHTMLFontFamilyDeclaration] = MihbaraReaderFont.allCases.compactMap { font -> AnyHTMLFontFamilyDeclaration? in
            let faces = font.files.compactMap { file -> CSSFontFace? in
                guard let url = Bundle.main.url(forResource: file.name, withExtension: file.ext).flatMap(FileURL.init(url:)) else { return nil }
                return CSSFontFace(file: url, preload: font == .amiri && file.weight == .normal, style: .normal, weight: .standard(file.weight))
            }
            guard !faces.isEmpty else { return nil }
            return CSSFontFamilyDeclaration(fontFamily: font.family, fontFaces: faces).eraseToAnyHTMLFontFamilyDeclaration()
        }
        let english: [AnyHTMLFontFamilyDeclaration] = MihbaraEnglishReaderFont.allCases.compactMap { font -> AnyHTMLFontFamilyDeclaration? in
            let faces = font.files.compactMap { file -> CSSFontFace? in
                guard let url = Bundle.main.url(forResource: file.name, withExtension: file.ext).flatMap(FileURL.init(url:)) else { return nil }
                return CSSFontFace(file: url, preload: font == .literata, style: .normal, weight: file.weight)
            }
            guard !faces.isEmpty else { return nil }
            return CSSFontFamilyDeclaration(fontFamily: font.family, fontFaces: faces).eraseToAnyHTMLFontFamilyDeclaration()
        }
        return arabic + english
    }

    func makeCoordinator() -> Coordinator {
        let coordinator = Coordinator(onLocation: onLocation, onInteraction: onInteraction, onSelection: onSelection, onDocumentReady: onDocumentReady, onReady: onReady, onError: onError)
        coordinator.onFootnote = onFootnote
        return coordinator
    }

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
            navigator.view.backgroundColor = UIColor(madarHex: background)
            context.coordinator.background = background
            let coordinator = context.coordinator
            Task { @MainActor in
                await Task.yield()
                coordinator.onReady(navigator)
            }
            return navigator
        } catch {
            let unavailable = UIViewController()
            unavailable.view.backgroundColor = UIColor(madarHex: background)
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
        if context.coordinator.background != background {
            context.coordinator.background = background
            controller.view.backgroundColor = UIColor(madarHex: background)
        }
        context.coordinator.onLocation = onLocation
        context.coordinator.onInteraction = onInteraction
        context.coordinator.onSelection = onSelection
        context.coordinator.onDocumentReady = onDocumentReady
        context.coordinator.onFootnote = onFootnote
        context.coordinator.onReady = onReady
        context.coordinator.onError = onError
        (controller as? EPUBNavigatorViewController)?.delegate = context.coordinator
    }

    final class Coordinator: NSObject, EPUBNavigatorDelegate, WKScriptMessageHandler {
        var onLocation: (Locator, Bool) -> Void
        var onInteraction: () -> Void
        var onSelection: (Selection) -> Void
        var onDocumentReady: () -> Void
        var onFootnote: (MihbaraFootnote) -> Void = { _ in }
        var background = ""
        var onReady: (EPUBNavigatorViewController) -> Void
        var onError: (NavigatorError) -> Void

        init(onLocation: @escaping (Locator, Bool) -> Void, onInteraction: @escaping () -> Void, onSelection: @escaping (Selection) -> Void, onDocumentReady: @escaping () -> Void, onReady: @escaping (EPUBNavigatorViewController) -> Void, onError: @escaping (NavigatorError) -> Void) {
            self.onLocation = onLocation
            self.onInteraction = onInteraction
            self.onSelection = onSelection
            self.onDocumentReady = onDocumentReady
            self.onReady = onReady
            self.onError = onError
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) { onLocation(locator, false) }
        func navigator(_ navigator: Navigator, didJumpTo locator: Locator) { onLocation(locator, true) }
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) { onError(error) }
        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) {
            guard message.name == "madarReaderDocumentReady" else { return }
            onDocumentReady()
        }
        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) { onInteraction() }
        func navigator(_ navigator: Navigator, presentExternalURL url: URL) { onInteraction() }
        /// A note reference opens Madar's footnote card instead of jumping to the notes file.
        func navigator(_ navigator: Navigator, shouldNavigateToNoteAt link: ReadiumShared.Link, content: String, referrer: String?) -> Bool {
            guard let note = MihbaraFootnote(html: content, referrer: referrer) else { return true }
            onFootnote(note)
            return false
        }
        /// Madar's word card replaces the system edit menu (RMI1: meaning through the system Look Up only).
        func navigator(_ navigator: SelectableNavigator, shouldShowMenuForSelection selection: Selection) -> Bool {
            onSelection(selection)
            return false
        }
        func navigator(_ navigator: EPUBNavigatorViewController, setupUserScripts userContentController: WKUserContentController) {
            userContentController.add(self, name: "madarReaderDocumentReady")
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
                    h1:lang(ar)::before { content: 'فصل'; display: block; color: #6A6052; font-size: .56em; font-weight: 400; margin-bottom: .32em; }
                    h1::after { content: ''; display: block; width: 3.8em; border-top: 1px solid #B7AA95; margin: .58em auto 0; }
                    p { margin-block: .7em !important; }
                    \(MihbaraReaderTheme.pageCSS)
                    a[role~='doc-noteref'] { display: inline-flex !important; align-items: center; justify-content: center; box-sizing: border-box; width: 1.45em; height: 1.45em; padding: 0 0 .12em 0 !important; margin-inline: .12em; border-radius: 50%; background: #9E2F25 !important; color: #FAF6EA !important; font-size: .7em; font-weight: 700; line-height: 1 !important; text-indent: 0 !important; vertical-align: .35em; text-decoration: none !important; }
                  `;
                  head.appendChild(style);
                }
                return true;
              };
              if (!apply()) new MutationObserver((_, observer) => { if (apply()) observer.disconnect(); }).observe(document, {childList:true, subtree:true});
              // Qur'an quotations: every run from ﴿ to ﴾, even across inline tags, takes the verse colour.
              const verses = () => {
                if (!document.body || document.body.dataset.madarAyah) return;
                document.body.dataset.madarAyah = '1';
                const walker = document.createTreeWalker(document.body, NodeFilter.SHOW_TEXT, {
                  acceptNode: (node) => node.parentElement && node.parentElement.closest('script, style, .madar-ayah') ? NodeFilter.FILTER_REJECT : NodeFilter.FILTER_ACCEPT
                });
                const nodes = [];
                while (walker.nextNode()) nodes.push(walker.currentNode);
                let inside = false;
                for (const node of nodes) {
                  const text = node.nodeValue;
                  if (!inside && !text.includes('﴿')) continue;
                  const parts = [];
                  let start = 0;
                  for (let i = 0; i < text.length; i++) {
                    if (!inside && text[i] === '﴿') { if (i > start) parts.push([text.slice(start, i), false]); start = i; inside = true; }
                    else if (inside && text[i] === '﴾') { parts.push([text.slice(start, i + 1), true]); start = i + 1; inside = false; }
                  }
                  if (start < text.length) parts.push([text.slice(start), inside]);
                  if (!parts.some(([, verse]) => verse)) continue;
                  const fragment = document.createDocumentFragment();
                  for (const [value, verse] of parts) {
                    if (!verse) { fragment.appendChild(document.createTextNode(value)); continue; }
                    const span = document.createElement('span');
                    span.className = 'madar-ayah';
                    span.textContent = value;
                    fragment.appendChild(span);
                  }
                  node.parentNode.replaceChild(fragment, node);
                }
              };
              if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', verses); else verses();

              const focusBlocks = () => Array.from(document.body?.querySelectorAll('p, li, blockquote') ?? [])
                // Empty page-break paragraphs still receive a line box in some EPUBs. Treating
                // one as a reading paragraph leaves every visible line dimmed at that boundary.
                .filter(block => !block.closest('[hidden], [aria-hidden="true"]')
                  && block.getBoundingClientRect().height > 0
                  && (block.innerText || '').trim().length > 0);
              const focusDescription = (block, blocks) => {
                if (!block || !blocks.length) return '';
                const index = blocks.indexOf(block);
                return index < 0 ? '' : `${index + 1}/${blocks.length}`;
              };
              const setFocusBlock = (block, blocks = focusBlocks()) => {
                for (const candidate of blocks) {
                  const active = candidate === block;
                  candidate.classList.toggle('madar-focus-active', active);
                  if (active) candidate.setAttribute('aria-current', 'location');
                  else candidate.removeAttribute('aria-current');
                }
                return focusDescription(block, blocks);
              };
              const nearestFocusBlock = (blocks) => {
                if (!blocks.length) return null;
                const visible = blocks.filter(block => {
                  const rect = block.getBoundingClientRect();
                  return rect.bottom > 0 && rect.top < window.innerHeight;
                });
                const candidates = visible.length ? visible : blocks;
                const center = window.innerHeight / 2;
                return candidates.reduce((best, block) => {
                  if (!best) return block;
                  const rect = block.getBoundingClientRect();
                  const bestRect = best.getBoundingClientRect();
                  return Math.abs(rect.top + rect.height / 2 - center) < Math.abs(bestRect.top + bestRect.height / 2 - center) ? block : best;
                }, null);
              };
              let focusTargetSequence = 0;
              const scrollFocusBlock = (block, behavior) => {
                if (!block.id) block.id = 'madar-focus-target-' + (++focusTargetSequence);
                // Readium owns the EPUB scroll surface. Its locator helper reaches the right
                // vertical offset when DOM scrollIntoView cannot move the navigator's container.
                if (window.readium?.scrollToId) window.readium.scrollToId(block.id, behavior === 'smooth');
                else block.scrollIntoView({ behavior, block: 'center', inline: 'nearest' });
              };
              window.madarReaderSetFocusMode = (enabled) => {
                const body = document.body;
                if (!body) return '';
                if (!enabled) {
                  delete body.dataset.madarFocus;
                  for (const block of focusBlocks()) {
                    block.classList.remove('madar-focus-active');
                    block.removeAttribute('aria-current');
                  }
                  return '';
                }
                body.dataset.madarFocus = 'true';
                const blocks = focusBlocks();
                const active = blocks.find(block => block.classList.contains('madar-focus-active')) || nearestFocusBlock(blocks);
                return setFocusBlock(active, blocks);
              };
              window.madarReaderStepFocus = (direction) => {
                if (!document.body?.dataset.madarFocus) return '';
                const blocks = focusBlocks();
                if (!blocks.length) return '';
                const active = blocks.find(block => block.classList.contains('madar-focus-active')) || nearestFocusBlock(blocks);
                const index = blocks.indexOf(active);
                const next = blocks[index + direction];
                if (!next) return focusDescription(active, blocks);
                const behavior = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';
                scrollFocusBlock(next, behavior);
                return setFocusBlock(next, blocks);
              };
              window.madarReaderSpeechQueue = () => {
                const blocks = focusBlocks();
                if (!blocks.length) return '';
                const active = blocks.find(block => block.classList.contains('madar-focus-active')) || nearestFocusBlock(blocks);
                const paragraphs = blocks.map((block, index) => ({ index, text: (block.innerText || '').replace(/\\s+/g, ' ').trim() }));
                return JSON.stringify({ paragraphs, startIndex: Math.max(0, blocks.indexOf(active)) });
              };
              window.madarReaderSpeechSetActive = (index) => {
                const blocks = focusBlocks();
                const active = blocks[index];
                if (!active) return '';
                for (const block of blocks) {
                  const selected = block === active;
                  block.classList.toggle('madar-speech-active', selected);
                  if (selected) block.setAttribute('aria-current', 'location');
                  else if (!block.classList.contains('madar-focus-active')) block.removeAttribute('aria-current');
                }
                if (!active.id) active.id = 'madar-speech-target-' + index;
                const behavior = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';
                scrollFocusBlock(active, behavior);
                return focusDescription(active, blocks);
              };
              window.madarReaderSpeechClear = () => {
                for (const block of focusBlocks()) {
                  block.classList.remove('madar-speech-active');
                  if (!block.classList.contains('madar-focus-active')) block.removeAttribute('aria-current');
                }
                return '';
              };
              const autoScrollInfo = (block, blocks) => {
                const words = (block?.innerText || '').trim().split(/\\s+/).filter(Boolean).length;
                return JSON.stringify({ index: blocks.indexOf(block) + 1, total: blocks.length, wordCount: Math.max(1, words) });
              };
              const setAutoScrollBlock = (block, blocks) => {
                for (const candidate of blocks) {
                  const active = candidate === block;
                  candidate.classList.toggle('madar-auto-scroll-active', active);
                  if (active) candidate.setAttribute('aria-current', 'location');
                  else if (!candidate.classList.contains('madar-focus-active') && !candidate.classList.contains('madar-speech-active')) candidate.removeAttribute('aria-current');
                }
                return autoScrollInfo(block, blocks);
              };
              const visibleFocusBlock = (block) => {
                if (!block) return false;
                const rect = block.getBoundingClientRect();
                return rect.bottom > 0 && rect.top < window.innerHeight;
              };
              window.madarReaderAutoScrollStart = () => {
                const blocks = focusBlocks();
                if (!blocks.length) return '';
                const marked = blocks.find(block => block.classList.contains('madar-auto-scroll-active'));
                const active = marked && visibleFocusBlock(marked) ? marked : nearestFocusBlock(blocks);
                return setAutoScrollBlock(active, blocks);
              };
              window.madarReaderAutoScrollStep = () => {
                const blocks = focusBlocks();
                if (!blocks.length) return 'end';
                const marked = blocks.find(block => block.classList.contains('madar-auto-scroll-active'));
                // A manual swipe becomes the new starting point on the next tick.
                const active = marked && visibleFocusBlock(marked) ? marked : nearestFocusBlock(blocks);
                const next = blocks[blocks.indexOf(active) + 1];
                if (!next) return 'end';
                if (!next.id) next.id = 'madar-auto-scroll-target-' + (blocks.indexOf(next) + 1);
                const behavior = window.matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth';
                scrollFocusBlock(next, behavior);
                return setAutoScrollBlock(next, blocks);
              };
              window.madarReaderAutoScrollClear = () => {
                for (const block of focusBlocks()) {
                  block.classList.remove('madar-auto-scroll-active');
                  if (!block.classList.contains('madar-focus-active') && !block.classList.contains('madar-speech-active')) block.removeAttribute('aria-current');
                }
                return '';
              };
              let focusFrame = 0;
              document.addEventListener('scroll', () => {
                if (!document.body?.dataset.madarFocus || focusFrame) return;
                focusFrame = requestAnimationFrame(() => {
                  focusFrame = 0;
                  const blocks = focusBlocks();
                  setFocusBlock(nearestFocusBlock(blocks), blocks);
                });
              }, true);
              const notifyDocumentReady = () => window.webkit.messageHandlers.madarReaderDocumentReady.postMessage(true);
              if (document.readyState === 'loading') document.addEventListener('DOMContentLoaded', notifyDocumentReady, { once: true });
              else queueMicrotask(notifyDocumentReady);
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
    var hasSystemDefinition = false

    var canSaveAsWord: Bool {
        guard isWord else { return false }
        let parts = word.split(whereSeparator: \.isWhitespace)
        return parts.count == 1 && parts[0].unicodeScalars.contains(where: CharacterSet.letters.contains)
    }
}

struct MihbaraQuoteCardContent: Identifiable {
    let id = UUID()
    let quote: String
    let bookTitle: String
    let author: String
    let location: String?
    let sourceURL: URL?
    let sourceName: String

    init(quote: String, bookTitle: String, author: String, pageLabel: String?, turathID: Int?, digits: MadarNumberFormatter) {
        self.quote = quote
        self.bookTitle = bookTitle
        self.author = author
        if let pageLabel, !pageLabel.isEmpty {
            let parts = pageLabel.split(separator: "/", omittingEmptySubsequences: false)
            if turathID != nil, parts.count == 2, !parts[0].isEmpty, !parts[1].isEmpty {
                location = "ج \(digits.localized(String(parts[0])))، ص \(digits.localized(String(parts[1])))"
            } else {
                location = "ص \(digits.localized(pageLabel))"
            }
        } else {
            location = nil
        }
        sourceURL = turathID.flatMap { URL(string: "https://shamela.ws/book/\($0)") }
        sourceName = sourceURL == nil ? "من مكتبتك" : "المكتبة الشاملة"
    }

    var sourceAddress: String? {
        guard let sourceURL else { return nil }
        return sourceURL.host.map { $0 + sourceURL.path }
    }
}

struct MihbaraLookupTerm: Identifiable { var word: String; var id: String { word } }
struct MihbaraTranslationRequest: Identifiable {
    let id = UUID()
    let text: String
    let sourceLanguage: String
}
enum MihbaraTranslationAvailability: Equatable { case checking, installed, needsDownload, unsupported }
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
    let palette: MihbaraReaderPalette
    let swatches: [String]
    let copied: Bool
    let wordSaved: Bool
    let translationAvailability: MihbaraTranslationAvailability
    let lookUp: () -> Void
    let saveWord: () -> Void
    let translate: () -> Void
    let choose: (String) -> Void
    let note: () -> Void
    let copy: () -> Void
    let makeQuoteCard: () -> Void
    let close: () -> Void

    private var ink: SwiftUI.Color { palette.ink }
    private var ink2: SwiftUI.Color { palette.ink2 }
    private var accent: SwiftUI.Color { palette.accent }
    private var surface: SwiftUI.Color { palette.bg }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.word)
                        .font(.custom("Amiri-Bold", size: state.isWord ? 30 : 22, relativeTo: .title))
                        .foregroundStyle(ink).lineLimit(2).multilineTextAlignment(.leading)
                        .accessibilityIdentifier("mihbara-word-title")
                    if state.isWord, state.hasSystemDefinition {
                        Button(action: lookUp) {
                            HStack(spacing: 6) {
                                Image(systemName: "character.book.closed").font(.system(size: 15, weight: .semibold))
                                Text("معناها في قاموس الجهاز").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body))
                            }
                            .foregroundStyle(accent).frame(minHeight: 36).contentShape(Capsule())
                        }
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .accessibilityIdentifier("mihbara-word-lookup")
                    } else if state.isWord {
                        Text("لا يوجد تعريف لهذه الكلمة في قاموس الجهاز")
                            .font(MadarTypography.fine()).foregroundStyle(ink2)
                            .accessibilityIdentifier("mihbara-word-lookup-unavailable")
                    } else if let page = state.pageText {
                        Text("فقرة مظلّلة من \(page)").font(MadarTypography.caption()).foregroundStyle(ink2)
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink2)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("إغلاق")
                .accessibilityIdentifier("mihbara-word-close")
            }
            HStack(spacing: 12) {
                Text("ظلّل الفقرة").font(MadarTypography.fine()).foregroundStyle(ink2)
                ForEach(Array(MihbaraHighlight.colors.enumerated()), id: \.element) { index, color in
                    let selected = state.color == color
                    Button { choose(color) } label: {
                        Circle().fill(SwiftUI.Color(uiColor: UIColor(madarHex: swatches[index])))
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
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        action("دوّن ملاحظة", icon: "square.and.pencil", id: "mihbara-word-note", run: note)
                        action(copied ? "نُسخت" : "انسخ مع التوثيق", icon: copied ? "checkmark" : "doc.on.doc", id: "mihbara-word-copy", run: copy)
                    }
                    if state.highlightID != nil {
                        action("بطاقة اقتباس", icon: "quote.bubble", id: "mihbara-quote-card-open", run: makeQuoteCard)
                    }
                    if state.isWord && (state.canSaveAsWord || translationAvailability != .unsupported) {
                        HStack(spacing: 10) {
                            if state.canSaveAsWord {
                                if wordSaved {
                                    Text("في كلماتي")
                                        .font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline))
                                        .foregroundStyle(ink2).frame(maxWidth: .infinity, minHeight: 56)
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .accessibilityIdentifier("mihbara-word-saved")
                                } else {
                                    action("أضف إلى كلماتي", icon: "text.book.closed", id: "mihbara-word-save", run: saveWord)
                                }
                            }
                            switch translationAvailability {
                            case .installed:
                                action("ترجم الفقرة", icon: "character.bubble", id: "mihbara-word-translate", run: translate)
                            case .needsDownload:
                                availability("ثبّت حزمة الترجمة من الإعدادات", id: "mihbara-translation-download")
                            case .checking:
                                availability("نتحقق من توفر الترجمة", id: "mihbara-translation-checking", progress: true)
                            case .unsupported:
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(surface)
            .shadow(color: .black.opacity(palette.isDark ? 0.45 : 0.14), radius: 22, y: 6))
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
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(id)
    }

    private func availability(_ title: String, id: String, progress: Bool = false) -> some View {
        HStack(spacing: 8) {
            if progress { ProgressView().controlSize(.small) }
            Text(title).font(MadarTypography.fine()).lineLimit(2).multilineTextAlignment(.center)
        }
        .foregroundStyle(ink2).frame(maxWidth: .infinity, minHeight: 56)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(id)
    }
}

private struct MihbaraQuoteCardSheet: View {
    let app: AppSession
    let card: MihbaraQuoteCardContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var image: UIImage?
    @State private var shareError: String?

    private var background: SwiftUI.Color { theme.background }
    private var ink: SwiftUI.Color { theme.ink }
    private var secondaryInk: SwiftUI.Color { theme.secondaryInk }

    var body: some View {
        VStack(spacing: 14) {
            GlassEffectContainer(spacing: 12) {
                ZStack {
                    Text("بطاقة اقتباس").font(MadarTypography.section())
                        .frame(maxWidth: .infinity)
                    HStack {
                        Spacer(minLength: 44)
                        closeButton
                    }
                }
                if image != nil {
                    shareButton
                    .accessibilityIdentifier("mihbara-quote-card-share")
                    .accessibilityHint(card.sourceURL == nil ? "يشارك صورة البطاقة" : "يشارك صورة البطاقة ورابط الكتاب في الشاملة")
                }
            }

            if let image {
                ScrollView {
                    Image(uiImage: image)
                        .resizable().scaledToFit().frame(maxWidth: 360)
                        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
                        .shadow(color: ink.opacity(0.18), radius: 18, y: 7)
                        .accessibilityLabel(accessibilityDescription)
                        .accessibilityIdentifier("mihbara-quote-card-preview")
                        .padding(.horizontal, 20).padding(.vertical, 8)
                }
                .scrollIndicators(.hidden)
            } else {
                ProgressView("يجهّز البطاقة…").font(MadarTypography.caption())
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .accessibilityIdentifier("mihbara-quote-card-rendering")
            }

            Text("الفقرة التي ظلّلتها، مع موضعها ورابط مصدرها عند توفره.")
                .font(MadarTypography.fine()).foregroundStyle(secondaryInk)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            if let shareError {
                Text(shareError).font(MadarTypography.caption()).foregroundStyle(ink)
                    .accessibilityIdentifier("mihbara-quote-card-error")
            }
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 18)
        .foregroundStyle(ink).background(background.ignoresSafeArea())
        .task { renderCard() }
        .alert("مشاركة البطاقة", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("حسنًا", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
    }

    private var accessibilityDescription: String {
        [card.quote, card.bookTitle, card.author, card.location, card.sourceName, card.sourceAddress]
            .compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "، ")
    }

    private var closeLabel: some View {
        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
            .foregroundStyle(secondaryInk).frame(width: 44, height: 44).contentShape(Circle())
    }

    private var shareLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
            Text("شارك البطاقة").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body))
        }
        .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 54).contentShape(Capsule())
    }

    @ViewBuilder private var closeButton: some View {
        if #available(iOS 26.0, *) {
            Button { dismiss() } label: { closeLabel }
                .buttonStyle(.glass).buttonBorderShape(.circle)
                .accessibilityLabel("إغلاق").accessibilityIdentifier("mihbara-quote-card-close")
        } else {
            Button { dismiss() } label: { closeLabel }
                .buttonStyle(.bordered)
                .accessibilityLabel("إغلاق").accessibilityIdentifier("mihbara-quote-card-close")
        }
    }

    @ViewBuilder private var shareButton: some View {
        if #available(iOS 26.0, *) {
            Button(action: shareCard) { shareLabel }
                .buttonStyle(.glass)
        } else {
            Button(action: shareCard) { shareLabel }
                .buttonStyle(.bordered)
        }
    }

    @MainActor private func renderCard() {
        guard image == nil else { return }
        let renderer = ImageRenderer(content: MihbaraQuoteCardArtwork(card: card))
        renderer.scale = 2
        image = renderer.uiImage
        if image == nil { shareError = "تعذّر إنشاء صورة البطاقة." }
    }

    private func shareCard() {
        guard let image else { return }
        Task { @MainActor in
            do {
                guard let controller = app.lockController, let presenter = app.privacyPresenter else {
                    throw PrivacyAuthorizationError.stale
                }
                let authorization = try await controller.authorize([.app])
                try controller.validate(authorization)
                var items: [Any] = [image]
                if let sourceURL = card.sourceURL { items.append(sourceURL) }
                try presenter.present(items: items, authorization: authorization)
            } catch {
                shareError = "تعذّرت المشاركة. أعد المحاولة من البطاقة."
            }
        }
    }
}

private struct MihbaraQuoteCardArtwork: View {
    let card: MihbaraQuoteCardContent
    private let theme = RoomTheme(room: "mihbara")
    private var forest: SwiftUI.Color { theme.accentFill }
    private var paper: SwiftUI.Color { theme.surface }
    private var ink: SwiftUI.Color { theme.ink }
    private var muted: SwiftUI.Color { theme.secondaryInk }
    private var gold: SwiftUI.Color { theme.color("goldUnderstand") }
    private var goldText: SwiftUI.Color { theme.color("goldUnderstandText") }

    private var displayedQuote: String {
        guard card.quote.count > 520 else { return card.quote }
        return String(card.quote.prefix(519)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    private var quoteSize: CGFloat {
        if displayedQuote.count > 360 { 35 }
        else if displayedQuote.count > 240 { 41 }
        else if displayedQuote.count > 150 { 47 }
        else { 55 }
    }

    var body: some View {
        ZStack {
            forest
            RoundedRectangle(cornerRadius: 54, style: .continuous).fill(paper).padding(28)
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .stroke(gold.opacity(0.78), lineWidth: 2).padding(48)

            VStack(spacing: 0) {
                HStack(alignment: .firstTextBaseline) {
                    Text("مِحبرة").font(.custom("thmanyahserifdisplay-Bold", size: 45, relativeTo: .title))
                    Spacer()
                    Text("مَدَار").font(.custom("thmanyahsans-Bold", size: 22, relativeTo: .headline)).tracking(4)
                }
                .foregroundStyle(ink)
                Text("مما ظلّلته في كتابك")
                    .font(.custom("thmanyahsans-Medium", size: 23, relativeTo: .subheadline))
                    .foregroundStyle(muted).padding(.top, 8)

                Spacer(minLength: 42)
                Text("❝").font(.custom("Amiri-Bold", size: 104, relativeTo: .largeTitle))
                    .foregroundStyle(gold).frame(height: 86)
                Text(displayedQuote)
                    .font(.custom("Amiri", size: quoteSize, relativeTo: .title2))
                    .foregroundStyle(ink).multilineTextAlignment(.center)
                    .lineSpacing(15).lineLimit(13).minimumScaleFactor(0.68)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("mihbara-quote-card-artwork-quote")
                Spacer(minLength: 48)

                Rectangle().fill(gold.opacity(0.72)).frame(height: 2).padding(.horizontal, 120)
                    .padding(.bottom, 25)
                Text(card.bookTitle).font(.custom("thmanyahserifdisplay-Bold", size: 31, relativeTo: .title3))
                    .foregroundStyle(ink).multilineTextAlignment(.center).lineLimit(2)
                    .minimumScaleFactor(0.8)
                if !card.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(card.author).font(.custom("thmanyahsans-Medium", size: 23, relativeTo: .body))
                        .foregroundStyle(muted).padding(.top, 8).lineLimit(1).minimumScaleFactor(0.8)
                }
                if let location = card.location {
                    Text(location).font(.custom("thmanyahsans-Bold", size: 22, relativeTo: .body))
                        .foregroundStyle(ink).padding(.top, 8)
                }
                Text("المصدر: \(card.sourceName)")
                    .font(.custom("thmanyahsans-Medium", size: 20, relativeTo: .caption))
                    .foregroundStyle(muted).padding(.top, 16)
                if let sourceAddress = card.sourceAddress {
                    Text(sourceAddress).font(.system(size: 18, weight: .medium, design: .rounded))
                        .foregroundStyle(ink).padding(.top, 5)
                }
                Spacer(minLength: 12)
                Text("مِحبرة مدار").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .footnote))
                    .foregroundStyle(goldText)
            }
            .padding(.horizontal, 118).padding(.vertical, 105)
            .environment(\.layoutDirection, .rightToLeft)
            .multilineTextAlignment(.center)
        }
        .frame(width: 1080, height: 1350)
        .environment(\.colorScheme, .light)
    }
}

private struct MihbaraPageNoteSheet: View {
    let draft: MihbaraWordCardState
    let palette: MihbaraReaderPalette
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
                RoundedRectangle(cornerRadius: 2).fill(palette.accent).frame(width: 3)
                VStack(alignment: .leading, spacing: 4) {
                    Text(draft.paragraphText).font(.custom("Amiri-Regular", size: 17, relativeTo: .body)).foregroundStyle(palette.ink).lineLimit(4).lineSpacing(4)
                    if let pageText { Text(pageText).font(MadarTypography.fine()).foregroundStyle(palette.ink2) }
                }
            }
            .fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text("ما الذي أوقفك هنا؟").font(MadarTypography.body()).foregroundStyle(palette.ink2).padding(.top, 8).padding(.leading, 5)
                }
                TextEditor(text: $text).font(MadarTypography.body()).foregroundStyle(palette.ink).scrollContentBackground(.hidden).focused($focused)
                    .accessibilityLabel("نص الملاحظة").accessibilityIdentifier("mihbara-note-text")
            }
            .padding(10)
            .background(RoundedRectangle(cornerRadius: 16, style: .continuous).fill(palette.ink.opacity(palette.isDark ? 0.10 : 0.05)))
            Text("تُحفظ في دفتر هذا الكتاب مربوطة بهذه الفقرة.").font(MadarTypography.fine()).foregroundStyle(palette.ink2)
        }
        .padding(20)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
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

@available(iOS 18.0, *)
private struct MihbaraTranslationSheet: View {
    let request: MihbaraTranslationRequest
    let paper: SwiftUI.Color
    let palette: MihbaraReaderPalette
    @Environment(\.dismiss) private var dismiss
    @State private var translatedText: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("تم") { dismiss() }
                    .font(MadarTypography.body()).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("mihbara-translation-close")
                Spacer()
                Text("ترجمة الفقرة").font(MadarTypography.section())
                Spacer()
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            Text("ترجمة آلية تقريبية · تُعالج على الجهاز")
                .font(MadarTypography.fine()).foregroundStyle(palette.ink2)
            Rectangle().fill(palette.line).frame(height: 1)
            ScrollView {
                if let translatedText {
                    Text(translatedText).font(.custom("Amiri-Regular", size: 20, relativeTo: .body))
                        .lineSpacing(7).foregroundStyle(palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("mihbara-translation-result")
                } else if failed {
                    Text("تعذّرت الترجمة. تحقّق من تثبيت اللغتين ثم حاول مجددًا.")
                        .font(MadarTypography.body()).foregroundStyle(palette.ink2)
                        .accessibilityIdentifier("mihbara-translation-error")
                } else {
                    ProgressView("تُترجم الفقرة على الجهاز…")
                        .font(MadarTypography.body()).tint(palette.accent)
                        .accessibilityIdentifier("mihbara-translation-progress")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20).background(paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .translationTask(
            source: Locale.Language(identifier: request.sourceLanguage),
            target: Locale.Language(identifier: "ar"),
            action: Self.translationAction(text: request.text) { result in
                translatedText = result
                failed = result == nil
            }
        )
    }

    nonisolated private static func translationAction(
        text: String,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) -> @Sendable (TranslationSession) async -> Void {
        { session in
            do {
                let response = try await session.translate(text)
                await completion(response.targetText)
            } catch {
                await completion(nil)
            }
        }
    }
}

// MARK: - M6-V09 footnotes

/// A book's own footnote, as plain text: the back link to the text is dropped.
struct MihbaraFootnote: Equatable {
    var number: String
    var text: String

    init?(html: String, referrer: String?) {
        func plain(_ value: String) -> String {
            var text = value.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: "</p>\\s*<p[^>]*>", with: "\n", options: .regularExpression)
            text = text.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            for (entity, character) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&amp;", "&")] {
                text = text.replacingOccurrences(of: entity, with: character)
            }
            return text.replacingOccurrences(of: "[ \\t]+", with: " ", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // Back links point to the reference in the text (role doc-backlink, or an anchor into the body).
        let body = html.replacingOccurrences(of: "<a[^>]*(doc-backlink|href=\"[^\"]*#ref[^\"]*\")[^>]*>.*?</a>", with: "", options: [.regularExpression, .caseInsensitive])
        let text = plain(body)
        guard !text.isEmpty else { return nil }
        self.text = String(text.prefix(4000))
        self.number = plain(referrer ?? "")
    }
}

private struct MihbaraFootnoteCard: View {
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
            if !number.isEmpty {
                Text(number).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline)).foregroundStyle(onAccent)
                    .frame(minWidth: 32, minHeight: 32).background(Circle().fill(accent))
                    .accessibilityHidden(true)
            }
            VStack(alignment: .leading, spacing: 4) {
                Text("حاشية الكتاب").font(MadarTypography.fine()).foregroundStyle(ink2)
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

// MARK: - M6-V10 reader themes

/// `mihbara.readerAr.theme`. Colours are `rooms.mihbara.readerThemes` (calm = the `quiet` palette).
enum MihbaraReaderTheme: String, CaseIterable, Identifiable {
    case auto, paper, warm, calm, night, black
    var id: String { rawValue }
    var title: String {
        switch self { case .auto: "تلقائي"; case .paper: "ورق"; case .warm: "دافئ"; case .calm: "هادئ"; case .night: "ليل"; case .black: "أسود" }
    }
    struct Hex: Equatable { var bg, ink, ink2, accent, onAccent: String; var highlight: [String]; var verse: String }
    var hex: Hex {
        switch self {
        case .auto, .paper: Hex(bg: "#FAF6EA", ink: "#2A2118", ink2: "#6A6052", accent: "#9E2F25", onAccent: "#FAF6EA", highlight: ["#F3E3A0", "#D5E5C3", "#F1D0C8"], verse: "#24412F")
        case .warm: Hex(bg: "#F3E7CF", ink: "#2E2216", ink2: "#6A573F", accent: "#8E3F22", onAccent: "#F3E7CF", highlight: ["#EDD58E", "#D2DDB4", "#EBC6B6"], verse: "#24412F")
        case .calm: Hex(bg: "#E5E4DF", ink: "#1F1E1B", ink2: "#58564F", accent: "#3F5A73", onAccent: "#E5E4DF", highlight: ["#E6D894", "#C9D8BE", "#E2C3BD"], verse: "#24412F")
        case .night: Hex(bg: "#1F1C17", ink: "#E9E1D2", ink2: "#ABA192", accent: "#DCA564", onAccent: "#1F1C17", highlight: ["#5A4A1F", "#2F4A2C", "#5A2F2A"], verse: "#E2C27A")
        case .black: Hex(bg: "#000000", ink: "#D9D3C7", ink2: "#9A9387", accent: "#D9B25F", onAccent: "#000000", highlight: ["#4A3D14", "#233A21", "#4A2420"], verse: "#E2C27A")
        }
    }
    func palette(dark: Bool) -> MihbaraReaderPalette {
        let resolved: MihbaraReaderTheme = self == .auto ? (dark ? .night : .paper) : self
        return MihbaraReaderPalette(theme: resolved, hex: resolved.hex)
    }
    /// The page knows its theme only by the background Readium writes on `:root`, so each palette keys on it.
    static var pageCSS: String {
        [MihbaraReaderTheme.paper, .warm, .calm, .night, .black].map { theme in
            let h = theme.hex, root = ":root[style*=\"\(h.bg)\"]"
            return "\(root) body span.madar-ayah.madar-ayah.madar-ayah { color: \(h.verse) !important; } "
                + "\(root) body a[role~='doc-noteref'][role~='doc-noteref'] { background: \(h.accent) !important; color: \(h.onAccent) !important; }"
                + "\(root) body[data-madar-focus='true'] :is(p, li, blockquote) { color: \(h.ink2) !important; } "
                + "\(root) body[data-madar-focus='true'] :is(p, li, blockquote).madar-focus-active { color: \(h.ink) !important; }"
                + "\(root) body[data-madar-focus='true'] { padding-bottom: 8rem !important; } "
                + "\(root) body :is(p, li, blockquote).madar-speech-active { background-color: \(h.highlight[1]) !important; border-radius: .32em; box-decoration-break: clone; -webkit-box-decoration-break: clone; } "
                + "\(root) body :is(p, li, blockquote).madar-auto-scroll-active { background-color: \(h.highlight[1]) !important; border-radius: .32em; box-decoration-break: clone; -webkit-box-decoration-break: clone; } "
                + "@media (prefers-reduced-motion: no-preference) { \(root) body[data-madar-focus='true'] :is(p, li, blockquote) { transition: color .18s ease; } }"
        }.joined(separator: "\n")
    }
}

struct MihbaraReaderPalette: Equatable {
    var theme: MihbaraReaderTheme
    var hex: MihbaraReaderTheme.Hex
    var isDark: Bool { theme == .night || theme == .black }
    var bg: SwiftUI.Color { .init(uiColor: UIColor(madarHex: hex.bg)) }
    var ink: SwiftUI.Color { .init(uiColor: UIColor(madarHex: hex.ink)) }
    var ink2: SwiftUI.Color { .init(uiColor: UIColor(madarHex: hex.ink2)) }
    var accent: SwiftUI.Color { .init(uiColor: UIColor(madarHex: hex.accent)) }
    var onAccent: SwiftUI.Color { .init(uiColor: UIColor(madarHex: hex.onAccent)) }
    var line: SwiftUI.Color { ink.opacity(isDark ? 0.16 : 0.10) }
}

private struct MihbaraSpeechParagraph: Decodable, Sendable {
    var index: Int
    var text: String
}

private struct MihbaraSpeechDocument: Decodable, Sendable {
    var paragraphs: [MihbaraSpeechParagraph]
    var startIndex: Int
}

private enum MihbaraListeningSpeed: Double, CaseIterable, Hashable {
    case normal = 1
    case quick = 1.25
    case quicker = 1.5
    case double = 2

    var numberText: String {
        switch self {
        case .normal: "1"
        case .quick: "1٫25"
        case .quicker: "1٫5"
        case .double: "2"
        }
    }

    var identifier: String {
        switch self {
        case .normal: "1"
        case .quick: "1_25"
        case .quicker: "1_5"
        case .double: "2"
        }
    }
}

@Observable @MainActor private final class MihbaraSpeechController: NSObject {
    private let synthesizer: AVSpeechSynthesizer
    private var paragraphs: [MihbaraSpeechParagraph] = []
    private var voice: AVSpeechSynthesisVoice?
    private var currentUtteranceID: ObjectIdentifier?
    var onHighlightedParagraph: (@MainActor (Int?) -> Void)?
    private(set) var isActive = false
    private(set) var isSpeaking = false
    private(set) var currentIndex = 0
    private(set) var paragraphCount = 0
    private(set) var speed = 1.0

    override init() {
        synthesizer = AVSpeechSynthesizer()
        super.init()
        synthesizer.delegate = self
    }

    func start(paragraphs: [MihbaraSpeechParagraph], startIndex: Int, voice: AVSpeechSynthesisVoice) throws {
        guard !paragraphs.isEmpty else { throw CocoaError(.fileReadNoSuchFile) }
        try AVAudioSession.sharedInstance().setCategory(.playback, mode: .spokenAudio, options: [.duckOthers])
        try AVAudioSession.sharedInstance().setActive(true)
        self.paragraphs = paragraphs
        self.voice = voice
        currentIndex = min(paragraphs.count - 1, max(0, startIndex))
        paragraphCount = paragraphs.count
        speed = MihbaraListeningSpeed.normal.rawValue
        isActive = true
        speakCurrentParagraph()
    }

    func togglePlayback() {
        guard isActive else { return }
        if isSpeaking {
            _ = synthesizer.pauseSpeaking(at: .immediate)
            isSpeaking = false
        } else if synthesizer.isPaused {
            isSpeaking = synthesizer.continueSpeaking()
        } else {
            speakCurrentParagraph()
        }
    }

    func setSpeed(_ value: Double) {
        guard MihbaraListeningSpeed.allCases.contains(where: { $0.rawValue == value }), speed != value else { return }
        let wasSpeaking = isSpeaking
        speed = value
        guard isActive, currentUtteranceID != nil else { return }
        currentUtteranceID = nil
        _ = synthesizer.stopSpeaking(at: .immediate)
        isSpeaking = false
        if wasSpeaking { speakCurrentParagraph() }
    }

    func stop() {
        guard isActive || synthesizer.isSpeaking || synthesizer.isPaused else { return }
        currentUtteranceID = nil
        _ = synthesizer.stopSpeaking(at: .immediate)
        isActive = false
        isSpeaking = false
        onHighlightedParagraph?(nil)
        onHighlightedParagraph = nil
        paragraphs = []
        voice = nil
        currentIndex = 0
        paragraphCount = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    private func speakCurrentParagraph() {
        guard isActive, paragraphs.indices.contains(currentIndex), let voice else { finish() ; return }
        let text = paragraphs[currentIndex].text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { advance() ; return }
        let utterance = AVSpeechUtterance(string: text)
        utterance.voice = voice
        utterance.rate = min(AVSpeechUtteranceMaximumSpeechRate, AVSpeechUtteranceDefaultSpeechRate * Float(speed))
        currentUtteranceID = ObjectIdentifier(utterance)
        isSpeaking = true
        onHighlightedParagraph?(paragraphs[currentIndex].index)
        synthesizer.speak(utterance)
    }

    private func advance() {
        guard isActive else { return }
        currentUtteranceID = nil
        if currentIndex + 1 < paragraphs.count {
            currentIndex += 1
            speakCurrentParagraph()
        } else {
            finish()
        }
    }

    private func finish() {
        isActive = false
        isSpeaking = false
        currentUtteranceID = nil
        onHighlightedParagraph?(nil)
        onHighlightedParagraph = nil
        paragraphs = []
        voice = nil
        currentIndex = 0
        paragraphCount = 0
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    fileprivate func didFinish(_ id: ObjectIdentifier) {
        guard currentUtteranceID == id else { return }
        advance()
    }

    fileprivate func didCancel(_ id: ObjectIdentifier) {
        guard currentUtteranceID == id else { return }
        currentUtteranceID = nil
        isSpeaking = false
    }
}

extension MihbaraSpeechController: AVSpeechSynthesizerDelegate {
    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didFinish utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didFinish(id) }
    }

    nonisolated func speechSynthesizer(_ synthesizer: AVSpeechSynthesizer, didCancel utterance: AVSpeechUtterance) {
        let id = ObjectIdentifier(utterance)
        Task { @MainActor [weak self] in self?.didCancel(id) }
    }
}
