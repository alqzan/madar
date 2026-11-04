import SwiftUI
import PDFKit
import SwiftData
import MadarCore
import MadarDesign
import MadarCommands
import MadarPrayer

/// A PDF page is a file coordinate. Its label is shown separately because it is
/// not evidence that the same number is printed on the photographed page.
struct MihbaraPDFReaderView: View {
    let app: AppSession
    let book: MihbaraBook
    /// Opens on this page (0-based) instead of the saved place: the original of a converted book, at the same page.
    var startPage: Int? = nil
    let close: () -> Void

    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.colorScheme) private var colorScheme
    @State private var document: PDFDocument?
    @State private var pageIndex = 0
    @State private var error: String?
    @State private var readingClock: ActiveReadingClock?
    @State private var sessionStart: Date?
    @State private var sessionStartIndex = 0
    @State private var sessionID = UUID()
    @State private var positionProgress = ReadingPositionProgress()
    @State private var sessionDayStamp: String?
    @State private var lastClockSample: Date?
    @State private var closing = false
    @State private var pendingSaveAlert: String?
    @State private var isPendingSaveAlert = false
    @State private var searching = false
    @State private var flowing = false
    @State private var inkLayer: MihbaraInkOverlay?
    @State private var inking = false
    @State private var inkTool: MihbaraInkTool = .pen
    @State private var inkRevision = 0
    #if DEBUG
    @State private var injectedOpenFailure = false
    #endif

    private var saveCoordinator: MihbaraReadingSaveCoordinator { .forSession(app) }
    private var service: AppMihbaraService { .init(app: app) }
    private var digits: MadarNumberFormatter { service.digits }
    private var canRead: Bool { app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized }
    private var readerTheme: RoomTheme { .init(room: "mihbara", dark: colorScheme == .dark) }
    private var paper: Color { readerTheme.background }
    private var ink: Color { readerTheme.ink }
    private var pageCount: Int { document?.pageCount ?? 0 }
    private var currentLabel: String? {
        guard let label = document?.page(at: pageIndex)?.label?.trimmingCharacters(in: .whitespacesAndNewlines),
              !label.isEmpty else { return nil }
        // PDFKit may localise its default labels («٢»); only a label that differs in value is news.
        let digits = label.map { $0.wholeNumberValue.map(String.init) ?? String($0) }.joined()
        guard digits != String(pageIndex + 1) else { return nil }
        return label
    }

    var body: some View {
        TimelineView(.periodic(from: .now, by: 5)) { tick in
            VStack(spacing: 0) {
                header
                Rectangle().fill(ink.opacity(0.10)).frame(height: 1)
                if let document {
                    MihbaraPDFPage(document: document, pageIndex: pageIndex, paper: paper, ink: inkLayer, inking: inking, onPageChange: pageChanged)
                        .accessibilityIdentifier("mihbara-pdf-content")
                } else {
                    VStack(spacing: 18) {
                        if let error {
                            Image(systemName: "doc.text.magnifyingglass").font(.largeTitle)
                            Text(error).font(MadarTypography.body()).multilineTextAlignment(.center)
                                .accessibilityIdentifier("mihbara-pdf-error")
                            // AU-46: a passing failure (locked data, busy file) can be retried without leaving.
                            Button("أعد المحاولة") { self.error = nil; Task { await openPDF() } }.font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("mihbara-pdf-retry")
                            Button("العودة إلى المحبرة", action: close).buttonStyle(MadarPrimaryButton())
                        } else { ProgressView("يفتح ملف PDF من جهازك…") }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
                }
                if inking, let inkLayer {
                    MihbaraInkBar(overlay: inkLayer, page: pageIndex, tool: $inkTool, revision: inkRevision) { setInking(false) }
                        .environment(\.roomTheme, readerTheme)
                        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.10)).frame(height: 1) }
                }
                footer
            }
            .foregroundStyle(ink)
            .background(paper.ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft)
            .onChange(of: tick.date) { _, now in
                guard scenePhase == .active, canRead else { return }
                advanceClock(to: now)
            }
        }
        .task { await openPDF() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resume(at: Date()) } else { pause(at: Date()) }
            if phase != .active { searching = false; flowing = false; inkLayer?.flushAll() }
        }
        .onChange(of: canRead) { _, authorized in
            if authorized, scenePhase == .active { resume(at: Date()) }
            else if !authorized { searching = false; flowing = false; pause(at: Date()) }
        }
        .sheet(isPresented: $searching) {
            MihbaraPDFSearchView(app: app, book: book) { index in
                pageChanged(index, true)
                searching = false
            }
            .environment(\.roomTheme, readerTheme).madarSheetErrorAlert(app)
        }
        .sheet(isPresented: $flowing) {
            MihbaraPDFFlowView(app: app, book: book) { flowing = false }
                .environment(\.roomTheme, readerTheme).madarSheetErrorAlert(app)
        }
        .onChange(of: inkTool) { _, tool in inkLayer?.tool = tool }
        .onDisappear { inkLayer?.flushAll(); pause(at: Date()) }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .alert("قارئ PDF", isPresented: Binding(get: { pendingSaveAlert != nil }, set: { if !$0 { pendingSaveAlert = nil; isPendingSaveAlert = false } })) {
            if isPendingSaveAlert && saveCoordinator.canRetryPendingWritesNow {
                Button("إعادة المحاولة") { retryPendingSaveAndClose() }
                    .accessibilityIdentifier("mihbara-reading-save-retry")
            }
            Button("حسنًا", role: .cancel) { pendingSaveAlert = nil; isPendingSaveAlert = false }
        } message: { Text(pendingSaveAlert ?? "") }
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(book.title).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline)).lineLimit(1)
                Text(book.author.isEmpty ? "ملف PDF على جهازك" : book.author).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
            }.frame(maxWidth: .infinity)
            HStack {
                Button(action: finishAndClose) {
                    Label("المحبرة", systemImage: "chevron.right")
                        .font(MadarTypography.caption()).frame(minHeight: 44)
                }
                .disabled(closing)
                .accessibilityIdentifier("mihbara-pdf-close")
                Spacer()
                if document != nil {
                    Button { searching = true } label: {
                        Image(systemName: "magnifyingglass").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("ابحث في PDF واستخرج نصه")
                    .accessibilityIdentifier("mihbara-pdf-search")
                    if inkLayer != nil {
                        Button { setInking(!inking) } label: {
                            Image(systemName: inking ? "pencil.tip.crop.circle.fill" : "pencil.tip.crop.circle").frame(width: 44, height: 44)
                        }
                        .accessibilityLabel(inking ? "أنهِ الرسم" : "ارسم على الصفحة")
                        .accessibilityValue(inkLayer.map { digits.string($0.drawnPages) } ?? "")
                        .accessibilityIdentifier("mihbara-pdf-ink")
                    }
                    Button { flowing = true } label: {
                        Image(systemName: "text.justify.leading").frame(width: 44, height: 44)
                    }
                    .accessibilityLabel("اجعله كتابًا منسابًا")
                    .accessibilityIdentifier("mihbara-pdf-flow")
                }
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if pageCount > 0 {
                ProgressView(value: Double(pageIndex + 1), total: Double(pageCount))
                    .tint(readerTheme.accentFill)
                    .accessibilityIdentifier("mihbara-pdf-progress")
                HStack(spacing: 8) {
                    Button { go(to: pageIndex - 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(pageIndex == 0).accessibilityLabel("الصفحة السابقة").accessibilityIdentifier("mihbara-pdf-previous")
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text("صفحة الملف \(digits.string(pageIndex + 1)) من \(digits.string(pageCount))")
                            .font(MadarTypography.caption())
                        if let currentLabel {
                            Text("رقمها المطبوع: \(digits.localized(currentLabel))")
                                .font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65))
                        }
                        if pageIndex + 1 >= pageCount {
                            Text("هذه آخر صفحة").font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65))
                                .accessibilityIdentifier("mihbara-pdf-remaining")
                        } else if let left = MihbaraCopy.remaining(pages: pageCount, read: pageIndex + 1, digits) {
                            Text(left).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65))
                                .accessibilityIdentifier("mihbara-pdf-remaining")
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("صفحة الملف \(digits.string(pageIndex + 1)) من \(digits.string(pageCount))")
                    .accessibilityIdentifier("mihbara-pdf-page")
                    Spacer(minLength: 0)
                    Button { go(to: pageIndex + 1) } label: { Image(systemName: "chevron.left").frame(width: 44, height: 44) }
                        .disabled(pageIndex + 1 >= pageCount).accessibilityLabel("الصفحة التالية").accessibilityIdentifier("mihbara-pdf-next")
                }
            }
        }
        .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 8)
        .background(paper)
        .overlay(alignment: .top) { Rectangle().fill(ink.opacity(0.10)).frame(height: 1) }
    }

    @MainActor private func openPDF() async {
        guard document == nil, error == nil else { return }
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if !injectedOpenFailure, UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
               environment["MADAR_UI_PDF_OPEN_FAILURE_ONCE"] == "1" {
                injectedOpenFailure = true
                throw PDFReaderError.unreadable
            }
            #endif
            let bytes = try await service.pdfDataOffMain(for: book)
            guard document == nil, let opened = PDFDocument(data: bytes), !opened.isLocked, opened.pageCount > 0,
                  opened.page(at: 0) != nil else { throw PDFReaderError.unreadable }
            document = opened
            inkLayer = makeInkLayer()
            pageIndex = startPage.map { min(max($0, 0), opened.pageCount - 1) } ?? restoredIndex(count: opened.pageCount)
            let now = Date()
            beginSegment(at: now)
            readingClock = ActiveReadingClock(startedAt: now, foreground: scenePhase == .active && canRead)
        } catch { self.error = madarUserMessage(error) }
    }

    private func restoredIndex(count: Int) -> Int {
        guard let data = book.locatorJSON,
              case .object(let object)? = try? JSONDecoder().decode(MadarCore.JSONValue.self, from: data),
              case .string(let hash)? = object["fileHash"], hash == book.fileHash,
              case .number(let number)? = object["pdfPageIndex"], number.isFinite,
              number >= 0, number < Double(count), number.rounded(.down) == number else { return 0 }
        return Int(number)
    }

    @MainActor private func go(to index: Int) {
        guard (0..<pageCount).contains(index) else { return }
        pageChanged(index, false)
    }

    @MainActor private func pageChanged(_ index: Int, _ explicitJump: Bool) {
        guard (0..<pageCount).contains(index), index != pageIndex else { return }
        let now = Date()
        advanceClock(to: now)
        readingClock?.interaction(at: now)
        positionProgress.observe(position: index + 1, at: now, explicitJump: explicitJump)
        pageIndex = index
        saveLocator(index)
    }

    private func locator(_ index: Int) -> String {
        let progression = pageCount > 1 ? Double(index) / Double(pageCount - 1) : 1.0
        var fields: [String: MadarCore.JSONValue] = [
            "href": .string("document.pdf"), "type": .string("application/pdf"),
            "pdfPageIndex": .number(Double(index)), "fileHash": .string(book.fileHash ?? ""),
            "locations": .object(["totalProgression": .number(progression)])
        ]
        if let label = document?.page(at: index)?.label, !label.isEmpty {
            fields["pdfPageLabel"] = .string(label)
        }
        let data = (try? JSONEncoder().encode(MadarCore.JSONValue.object(fields))) ?? Data()
        return String(data: data, encoding: .utf8) ?? "{}"
    }

    @MainActor private func saveLocator(_ index: Int) {
        saveCoordinator.enqueueLocatorJSON(locator(index), bookID: book.id)
    }

    @MainActor private func resume(at now: Date) {
        guard document != nil, canRead, scenePhase == .active, readingClock == nil else { return }
        beginSegment(at: now)
        readingClock = ActiveReadingClock(startedAt: now)
    }

    @MainActor private func dayStamp(at date: Date) -> String? {
        let context = ModelContext(app.container)
        guard let day = try? DiaryLineRenderer.today(context: context, now: date),
              let prayers = try? PrayerRepository(context: context) else { return nil }
        return day.description + "|" + prayers.place(at: date).timeZoneID + "|" + app.string("core.dayStart")
    }

    @MainActor private func beginSegment(at date: Date) {
        sessionID = UUID()
        sessionStart = date
        sessionStartIndex = pageIndex
        positionProgress = .init(startingAt: pageIndex + 1, at: date)
        sessionDayStamp = dayStamp(at: date)
        lastClockSample = date
    }

    @MainActor private func advanceClock(to date: Date) {
        guard var clock = readingClock else { return }
        let stamp = dayStamp(at: date)
        let previousStamp = sessionDayStamp ?? lastClockSample.flatMap { dayStamp(at: $0) }
        var split = false
        if let previousStamp, let stamp, stamp != previousStamp, let lastClockSample,
           let boundary = ReadingSessionBoundaryFinder.firstTransition(
                from: previousStamp,
                after: lastClockSample,
                through: date,
                stampAt: { self.dayStamp(at: $0) }
           ) {
            clock.advance(to: boundary.endsPreviousAt)
            readingClock = clock
            queueSessionSave(at: boundary.endsPreviousAt)
            clock.startSegment(at: boundary.startsNextAt)
            readingClock = clock
            beginSegment(at: boundary.startsNextAt)
            split = true
        }
        clock.advance(to: date)
        readingClock = clock
        if let stamp, sessionDayStamp == nil || stamp == sessionDayStamp || split {
            sessionDayStamp = stamp
            lastClockSample = date
        }
    }

    @MainActor private func queueSessionSave(at date: Date) {
        guard let clock = readingClock, clock.activeSeconds >= 60, let start = sessionStart else { return }
        let first = locator(sessionStartIndex), last = locator(pageIndex)
        let firstProgress = pageCount > 1 ? Double(sessionStartIndex) / Double(pageCount - 1) : 1.0
        let lastProgress = pageCount > 1 ? Double(pageIndex) / Double(pageCount - 1) : 1.0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        saveCoordinator.enqueue(sessionID: sessionID, payload: [
            "id": .string(sessionID.uuidString), "bookID": .string(book.id.uuidString),
            "start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: date)),
            "activeSeconds": .number(Double(min(86_400, clock.activeSeconds))),
            "fromPage": .number(0), "toPage": .number(0),
            "startLocator": .string(first), "endLocator": .string(last),
            "startProgression": .number(firstProgress), "endProgression": .number(lastProgress),
            "pagesCounted": .number(Double(positionProgress.pagesCounted))
        ])
    }

    @MainActor private func pause(at now: Date) {
        advanceClock(to: now)
        guard var clock = readingClock else { return }
        clock.setForeground(false, at: now)
        readingClock = nil
        saveLocator(pageIndex)
        readingClock = clock
        queueSessionSave(at: now)
        readingClock = nil
    }

    /// Drawings load with the file; a failed read leaves the reader open without the pen rather than risk overwriting them.
    @MainActor private func makeInkLayer() -> MihbaraInkOverlay? {
        do {
            let bookID = book.id
            let layer = MihbaraInkOverlay(saved: try service.pageInk(bookID: bookID)) { page, data in
                do {
                    try await app.executeBookCommand("ink.savePage", payload: ["bookID": .string(bookID.uuidString), "page": .number(Double(page)), "drawing": .string(data.base64EncodedString())])
                } catch { app.errorMessage = madarUserMessage(error) }
            }
            layer.tool = inkTool
            // One turn later, so PencilKit has registered the stroke with its undo manager before the bar asks it.
            layer.onChange = { DispatchQueue.main.async { inkRevision += 1 } }
            return layer
        } catch { return nil }
    }

    @MainActor private func setInking(_ on: Bool) {
        if !on { inkLayer?.flushAll() }
        inkLayer?.drawing = on
        withAnimation(.snappy) { inking = on }
    }

    @MainActor private func finishAndClose() {
        guard !closing else { return }
        closing = true
        app.armMihbaraLocatorFailureOnReaderCloseForUITest()
        inkLayer?.flushAll()
        pause(at: Date())
        Task { @MainActor in
            await saveCoordinator.waitForCurrentAttempt()
            guard !saveCoordinator.hasPending else {
                closing = false
                saveCoordinator.dismissPendingWriteError()
                isPendingSaveAlert = true
                pendingSaveAlert = pendingSaveMessage
                return
            }
            close()
        }
    }

    private var pendingSaveMessage: String {
        saveCoordinator.canRetryPendingWritesNow
            ? "لم يُحفظ موضع القراءة بعد. أعد المحاولة الآن لإكمال الحفظ قبل مغادرة القارئ."
            : "لم يُحفظ موضع القراءة بعد. أبقِ مدار مفتوحًا حتى يعود الإذن أو ينتهي التحديث، ثم أعد المحاولة."
    }

    @MainActor private func retryPendingSaveAndClose() {
        guard !closing else { return }
        closing = true
        pendingSaveAlert = nil
        isPendingSaveAlert = false
        saveCoordinator.retryPendingWritesNow()
        Task { @MainActor in
            await saveCoordinator.waitForCurrentAttempt()
            guard !saveCoordinator.hasPending else {
                closing = false
                saveCoordinator.dismissPendingWriteError()
                isPendingSaveAlert = true
                pendingSaveAlert = pendingSaveMessage
                return
            }
            close()
        }
    }
}

private enum PDFReaderError: LocalizedError {
    case unreadable
    var errorDescription: String? { "تعذر فتح PDF المحلي. قد يكون الملف تالفًا أو محميًا بكلمة مرور." }
}

private struct MihbaraPDFPage: UIViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int
    let paper: Color
    var ink: MihbaraInkOverlay? = nil
    var inking = false
    let onPageChange: (Int, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageChange: onPageChange) }

    func makeUIView(context: Context) -> RestoringPDFView {
        let view = RestoringPDFView(initialPageIndex: pageIndex)
        view.backgroundColor = UIColor(paper)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        // The overlay provider must be set before the document, so every page gets its canvas.
        view.pageOverlayViewProvider = ink
        view.document = document
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewPageChanged, object: view, queue: .main
        ) { [weak view, weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                // PDFKit announces its default first page while it attaches and lays out
                // the document. Only report pages once the restored page is on screen.
                guard let view, view.reportsPageChanges, let coordinator, let page = view.currentPage,
                      let index = view.document?.index(for: page), index >= 0 else { return }
                coordinator.onPageChange(index, false)
            }
        }
        return view
    }

    func updateUIView(_ view: RestoringPDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange
        // While drawing, PDFKit's own gestures step aside so a finger draws instead of scrolling.
        if view.isInMarkupMode != inking { view.isInMarkupMode = inking }
        guard view.reportsPageChanges, let page = document.page(at: pageIndex), view.currentPage !== page else { return }
        view.go(to: page)
    }

    static func dismantleUIView(_ view: RestoringPDFView, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        view.document = nil
    }

    @MainActor final class Coordinator {
        var onPageChange: (Int, Bool) -> Void
        var observer: NSObjectProtocol?
        init(onPageChange: @escaping (Int, Bool) -> Void) { self.onPageChange = onPageChange }
    }
}

/// A `go(to:)` before the first layout is dropped by PDFKit, so the saved page is
/// applied on the first sized layout and page reports start only after it lands.
final class RestoringPDFView: PDFView {
    private let initialPageIndex: Int
    private(set) var reportsPageChanges = false
    private var fallbackScheduled = false

    init(initialPageIndex: Int) {
        self.initialPageIndex = initialPageIndex
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard !reportsPageChanges, bounds.width > 0, bounds.height > 0, let document else { return }
        if let page = document.page(at: initialPageIndex), currentPage !== page { go(to: page) }
        if !fallbackScheduled {
            // Never leave the reader unable to report pages if PDFKit refuses the jump.
            fallbackScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reportsPageChanges = true }
        }
        guard currentPage.flatMap({ document.index(for: $0) }) == initialPageIndex else { return }
        DispatchQueue.main.async { [weak self] in self?.reportsPageChanges = true }
    }
}
