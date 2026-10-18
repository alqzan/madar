import SwiftUI
import PDFKit
import MadarCore
import MadarDesign

/// A PDF page is a file coordinate. Its label is shown separately because it is
/// not evidence that the same number is printed on the photographed page.
struct MihbaraPDFReaderView: View {
    let app: AppSession
    let book: MihbaraBook
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
    @State private var closing = false

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
                    MihbaraPDFPage(document: document, pageIndex: pageIndex, paper: paper, onPageChange: pageChanged)
                        .accessibilityIdentifier("mihbara-pdf-content")
                } else {
                    VStack(spacing: 18) {
                        if let error {
                            Image(systemName: "doc.text.magnifyingglass").font(.largeTitle)
                            Text(error).font(MadarTypography.body()).multilineTextAlignment(.center)
                            Button("العودة إلى المحبرة", action: close).buttonStyle(MadarPrimaryButton())
                        } else { ProgressView("يفتح ملف PDF من جهازك…") }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity).padding(28)
                    .accessibilityIdentifier("mihbara-pdf-error")
                }
                footer
            }
            .foregroundStyle(ink)
            .background(paper.ignoresSafeArea())
            .environment(\.layoutDirection, .rightToLeft)
            .onChange(of: tick.date) { _, now in
                guard scenePhase == .active, canRead else { return }
                readingClock?.advance(to: now)
            }
        }
        .task { openPDF() }
        .onChange(of: scenePhase) { _, phase in
            if phase == .active { resume(at: Date()) } else { pause(at: Date()) }
        }
        .onChange(of: canRead) { _, authorized in
            if authorized, scenePhase == .active { resume(at: Date()) }
            else if !authorized { pause(at: Date()) }
        }
        .onDisappear { pause(at: Date()) }
        .toolbarVisibility(.hidden, for: .navigationBar)
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 2) {
                Text(book.title).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline)).lineLimit(1)
                Text(book.author.isEmpty ? "PDF من مكتبتك" : book.author).font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65)).lineLimit(1)
            }.frame(maxWidth: .infinity)
            HStack {
                Button(action: finishAndClose) {
                    Label("المحبرة", systemImage: "chevron.right")
                        .font(MadarTypography.caption()).frame(minHeight: 44)
                }
                .disabled(closing)
                .accessibilityIdentifier("mihbara-pdf-close")
                Spacer()
            }
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private var footer: some View {
        VStack(spacing: 8) {
            if pageCount > 0 {
                ProgressView(value: Double(pageIndex + 1), total: Double(pageCount))
                    .tint(Color(red: 158 / 255, green: 47 / 255, blue: 37 / 255))
                    .accessibilityIdentifier("mihbara-pdf-progress")
                HStack(spacing: 8) {
                    Button { go(to: pageIndex - 1) } label: { Image(systemName: "chevron.right").frame(width: 44, height: 44) }
                        .disabled(pageIndex == 0).accessibilityLabel("الصفحة السابقة").accessibilityIdentifier("mihbara-pdf-previous")
                    Spacer(minLength: 0)
                    VStack(spacing: 2) {
                        Text("صفحة الملف \(digits.string(pageIndex + 1)) من \(digits.string(pageCount))")
                            .font(MadarTypography.caption())
                        if let currentLabel {
                            Text("تسمية PDF: \(digits.localized(currentLabel))")
                                .font(MadarTypography.fine()).foregroundStyle(ink.opacity(0.65))
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

    @MainActor private func openPDF() {
        guard document == nil, error == nil else { return }
        do {
            let bytes = try service.pdfData(for: book)
            guard let opened = PDFDocument(data: bytes), !opened.isLocked, opened.pageCount > 0,
                  opened.page(at: 0) != nil else { throw PDFReaderError.unreadable }
            document = opened
            pageIndex = restoredIndex(count: opened.pageCount)
            let now = Date()
            sessionStart = now
            sessionStartIndex = pageIndex
            positionProgress = .init(startingAt: pageIndex + 1, at: now)
            readingClock = ActiveReadingClock(startedAt: now, foreground: scenePhase == .active && canRead)
        } catch { self.error = error.localizedDescription }
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
        sessionID = UUID()
        sessionStart = now
        sessionStartIndex = pageIndex
        positionProgress = .init(startingAt: pageIndex + 1, at: now)
        readingClock = ActiveReadingClock(startedAt: now)
    }

    @MainActor private func pause(at now: Date) {
        guard var clock = readingClock else { return }
        clock.setForeground(false, at: now)
        readingClock = nil
        saveLocator(pageIndex)
        guard clock.activeSeconds >= 60, let start = sessionStart else { return }
        let first = locator(sessionStartIndex), last = locator(pageIndex)
        let firstProgress = pageCount > 1 ? Double(sessionStartIndex) / Double(pageCount - 1) : 1.0
        let lastProgress = pageCount > 1 ? Double(pageIndex) / Double(pageCount - 1) : 1.0
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        saveCoordinator.enqueue(sessionID: sessionID, payload: [
            "id": .string(sessionID.uuidString), "bookID": .string(book.id.uuidString),
            "start": .string(formatter.string(from: start)), "end": .string(formatter.string(from: now)),
            "activeSeconds": .number(Double(min(86_400, clock.activeSeconds))),
            "fromPage": .number(0), "toPage": .number(0),
            "startLocator": .string(first), "endLocator": .string(last),
            "startProgression": .number(firstProgress), "endProgression": .number(lastProgress),
            "pagesCounted": .number(Double(positionProgress.pagesCounted))
        ])
    }

    @MainActor private func finishAndClose() {
        guard !closing else { return }
        closing = true
        pause(at: Date())
        Task { @MainActor in
            await saveCoordinator.waitForCurrentAttempt()
            guard !saveCoordinator.hasPending else {
                closing = false
                app.errorMessage = "موضعك ينتظر الحفظ. أعد المحاولة حين تتاح بيانات الجهاز."
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
    let onPageChange: (Int, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageChange: onPageChange) }

    func makeUIView(context: Context) -> RestoringPDFView {
        let view = RestoringPDFView(initialPageIndex: pageIndex)
        view.backgroundColor = UIColor(paper)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
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
