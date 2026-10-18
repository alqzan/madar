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

private struct MihbaraOfflineHTTPClient: HTTPClient {
    func stream(request: HTTPRequestConvertible, consume: @escaping (Data, Double?) -> HTTPResult<Void>) async -> HTTPResult<HTTPResponse> {
        .failure(.offline(nil))
    }
}

/// Retained by the app session, rather than a reader subtree that an app lock can remove.
@MainActor private final class MihbaraReadingSaveCoordinator {
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
            pendingLocators[bookID] = LocatorWrite(bookID: bookID, commandID: UUID(), payload: ["id": .string(bookID.uuidString), "locator": .string(json)])
            flush()
        } catch { app?.errorMessage = error.localizedDescription }
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
    private var readerSize: Int {
        guard case .object(let settings)? = app.values["mihbara.readerAr"],
              case .number(let size)? = settings["size"] else { return 4 }
        return min(7, max(1, Int(size)))
    }
    private var readerFontPercent: Double { Double(70 + (readerSize - 1) * 10) }
    private var readerPreferences: EPUBPreferences {
        EPUBPreferences(
            fontFamily: .serif,
            fontSize: readerFontPercent,
            ligatures: true,
            readingProgression: .rtl,
            scroll: false,
            textAlign: .justify,
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
                        onInteraction: recordInteraction,
                        onReady: { navigatorController = $0 },
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
            .background(paper.ignoresSafeArea())
        .foregroundStyle(colorScheme == .dark ? SwiftUI.Color(red: 233 / 255, green: 225 / 255, blue: 210 / 255) : SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255))
            .environment(\.layoutDirection, .rightToLeft)
            .onChange(of: tick.date) { _, date in
                advanceClock(to: date)
                isSpeaking = speechSynthesizer.isSpeaking
            }
        }
        .task { await openPublication() }
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
            MihbaraReaderSizeSheet(size: readerSize, paper: paper) { size in
                updateReaderSize(size)
            }
            .environment(\.layoutDirection, .rightToLeft)
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

    private var footer: some View {
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
            HStack(alignment: .center, spacing: 12) {
                Text(printPageLabel)
                    .font(MadarTypography.caption()).lineLimit(1).minimumScaleFactor(0.8)
                    .accessibilityIdentifier("mihbara-reader-print-page")
                Spacer(minLength: 4)
                Text(isSpeaking ? "تُقرأ الصفحة بصوت عربي" : "تُسجَّل الجلسة بعد دقيقة نشاط")
                    .font(MadarTypography.fine()).foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 18).padding(.top, 9).padding(.bottom, 11)
        .overlay(alignment: .top) { Rectangle().fill(SwiftUI.Color.black.opacity(colorScheme == .dark ? 0.22 : 0.08)).frame(height: 1) }
        .background(paper)
    }

    private var printPageLabel: String {
        guard let last = printPages.last else { return "موضع من الكتاب" }
        guard let ordinal = pageCoordinate(currentLocator), printPages.indices.contains(ordinal - 1) else {
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

            let opened = try await Self.readPublication(at: file)

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

    nonisolated private static func readPublication(at file: URL) async throws -> sending Publication {
        let http = MihbaraOfflineHTTPClient()
        let retriever = AssetRetriever(httpClient: http)
        guard let fileURL = FileURL(url: file), case .success(let asset) = await retriever.retrieve(url: fileURL) else {
            throw DataError.invalidValue("تعذّر فتح بنية ملف EPUB")
        }
        let parser = DefaultPublicationParser(httpClient: http, assetRetriever: retriever, pdfFactory: DefaultPDFDocumentFactory())
        let opener = PublicationOpener(parser: parser, onCreatePublication: { manifest, container, _ in
            let htmlResources = Set((manifest.readingOrder + manifest.resources)
                .filter { $0.mediaType?.isHTML == true }.map { $0.url().removingFragment() })
            container = container.map { href, resource in
                let path = href.string.lowercased().split(separator: "?").first.map(String.init) ?? ""
                guard htmlResources.contains(href.removingFragment()) || [".xhtml", ".html", ".htm"].contains(where: { path.hasSuffix($0) }) else { return resource }
                return TransformingResource(resource) { result in
                    result.flatMap { bytes in
                        let encoding: String.Encoding = String(data: bytes, encoding: .utf8) == nil ? .utf16 : .utf8
                        guard let source = String(data: bytes, encoding: encoding),
                              let secured = ReadingDocumentPolicy.secure(source), let securedBytes = secured.data(using: encoding) else {
                            return .failure(.decoding("EPUB document has no safe HTML head"))
                        }
                        return .success(securedBytes)
                    }
                }
            }
        })
        guard case .success(let opened) = await opener.open(asset: asset, allowUserInteraction: false) else {
            throw DataError.invalidValue("ملف EPUB غير مكتمل أو غير مدعوم")
        }

        return opened
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
        scheduleLocatorSave(locator)
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

    @MainActor private func updateReaderSize(_ size: Int) {
        guard (1...7).contains(size) else { return }
        var settings = app.values["mihbara.readerAr"]?.object ?? [
            "theme": .string("auto"), "size": .number(4), "font": .string("amiri"),
            "mode": .string("pages"), "tashkil": .bool(true), "footnotes": .string("tap")
        ]
        settings["size"] = .number(Double(size))
        app.set(.object(settings), key: "mihbara.readerAr") {
            navigatorController?.submitPreferences(readerPreferences)
        }
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

private struct MihbaraReaderSizeSheet: View {
    @Environment(\.dismiss) private var dismiss
    let size: Int
    let paper: SwiftUI.Color
    let select: (Int) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("إعدادات القراءة").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
                    Text("حجم الخط العربي").font(MadarTypography.caption()).foregroundStyle(.secondary)
                }
                Spacer()
                Button("تمّ") { dismiss() }.font(MadarTypography.caption()).accessibilityIdentifier("mihbara-reader-settings-close")
            }
            HStack(spacing: 8) {
                ForEach(1...7, id: \.self) { value in
                    Button { select(value) } label: {
                        Text("Aa").font(.system(size: CGFloat(12 + value), weight: .medium, design: .serif))
                            .frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(value == size ? SwiftUI.Color.white : SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255))
                            .background(value == size ? SwiftUI.Color(red: 158 / 255, green: 47 / 255, blue: 37 / 255) : paper)
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("حجم الخط \(value)")
                    .accessibilityAddTraits(value == size ? .isSelected : [])
                    .accessibilityIdentifier("mihbara-reader-size-\(value)")
                }
            }
            .accessibilityElement(children: .contain)
        }
        .padding(22)
        .foregroundStyle(SwiftUI.Color(red: 42 / 255, green: 33 / 255, blue: 24 / 255))
        .background(paper.ignoresSafeArea())
        .presentationDetents([.height(190)])
    }
}

private struct MihbaraEPUBNavigator: UIViewControllerRepresentable {
    let publication: Publication
    let initialLocation: Locator?
    let preferences: EPUBPreferences
    let onLocation: (Locator, Bool) -> Void
    let onInteraction: () -> Void
    let onReady: (EPUBNavigatorViewController) -> Void
    let onError: (NavigatorError) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onLocation: onLocation, onInteraction: onInteraction, onReady: onReady, onError: onError) }

    func makeUIViewController(context: Context) -> UIViewController {
        let configuration = EPUBNavigatorViewController.Configuration(
            preferences: preferences,
            contentInset: [.compact: (top: 25, bottom: 22), .regular: (top: 38, bottom: 34)]
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
        context.coordinator.onReady = onReady
        context.coordinator.onError = onError
        (controller as? EPUBNavigatorViewController)?.delegate = context.coordinator
    }

    final class Coordinator: NSObject, EPUBNavigatorDelegate {
        var onLocation: (Locator, Bool) -> Void
        var onInteraction: () -> Void
        var onReady: (EPUBNavigatorViewController) -> Void
        var onError: (NavigatorError) -> Void

        init(onLocation: @escaping (Locator, Bool) -> Void, onInteraction: @escaping () -> Void, onReady: @escaping (EPUBNavigatorViewController) -> Void, onError: @escaping (NavigatorError) -> Void) {
            self.onLocation = onLocation
            self.onInteraction = onInteraction
            self.onReady = onReady
            self.onError = onError
        }

        func navigator(_ navigator: Navigator, locationDidChange locator: Locator) { onLocation(locator, false) }
        func navigator(_ navigator: Navigator, didJumpTo locator: Locator) { onLocation(locator, true) }
        func navigator(_ navigator: Navigator, presentError error: NavigatorError) { onError(error) }
        func navigator(_ navigator: VisualNavigator, didTapAt point: CGPoint) { onInteraction() }
        func navigator(_ navigator: Navigator, presentExternalURL url: URL) { onInteraction() }
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
                    h1 { font-size: 1.45em !important; line-height: 1.35 !important; margin-block: .35em .55em !important; text-align: center !important; }
                    h1::before { content: 'فصل'; display: block; color: #6A6052; font-size: .56em; font-weight: 400; margin-bottom: .32em; }
                    h1::after { content: ''; display: block; width: 3.8em; border-top: 1px solid #B7AA95; margin: .58em auto 0; }
                    p { line-height: 1.55 !important; margin-block: .58em !important; }
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
