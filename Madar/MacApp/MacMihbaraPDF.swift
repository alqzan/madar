import SwiftUI
import AppKit
import PDFKit

/// The Mihbara PDF page on the Mac: PDFKit's own AppKit view, with the same page restore and page reports as the iPhone reader,
/// so a book read on the Mac keeps the same saved page. Drawing on pages (PencilKit) stays on iPhone and iPad; the Mac reader never
/// creates an ink layer, so its pen button and bar are not shown.
struct MihbaraPDFPage: NSViewRepresentable {
    let document: PDFDocument
    let pageIndex: Int
    let paper: Color
    var ink: MihbaraInkOverlay? = nil
    var inking = false
    var twoUp = false
    let onPageChange: (Int, Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onPageChange: onPageChange) }

    func makeNSView(context: Context) -> RestoringPDFView {
        let view = RestoringPDFView(initialPageIndex: pageIndex)
        view.backgroundColor = NSColor(paper)
        view.autoScales = true
        view.displayMode = .singlePageContinuous
        view.displayDirection = .vertical
        view.document = document
        context.coordinator.observer = NotificationCenter.default.addObserver(
            forName: Notification.Name.PDFViewPageChanged, object: view, queue: .main
        ) { [weak view, weak coordinator = context.coordinator] _ in
            MainActor.assumeIsolated {
                guard let view, view.reportsPageChanges, let coordinator, let page = view.currentPage,
                      let index = view.document?.index(for: page), index >= 0 else { return }
                coordinator.onPageChange(index, false)
            }
        }
        return view
    }

    func updateNSView(_ view: RestoringPDFView, context: Context) {
        context.coordinator.onPageChange = onPageChange
        let mode: PDFDisplayMode = twoUp ? .twoUpContinuous : .singlePageContinuous
        if view.displayMode != mode {
            view.displayMode = mode
            view.displaysAsBook = twoUp
            view.displaysRTL = twoUp
            view.autoScales = true
        }
        guard view.reportsPageChanges, let page = document.page(at: pageIndex), view.currentPage !== page else { return }
        view.go(to: page)
    }

    static func dismantleNSView(_ view: RestoringPDFView, coordinator: Coordinator) {
        if let observer = coordinator.observer { NotificationCenter.default.removeObserver(observer) }
        view.document = nil
    }

    @MainActor final class Coordinator {
        var onPageChange: (Int, Bool) -> Void
        var observer: NSObjectProtocol?
        init(onPageChange: @escaping (Int, Bool) -> Void) { self.onPageChange = onPageChange }
    }
}

/// PDFKit drops a `go(to:)` before the first layout, so the saved page is applied on the first sized layout (as on iOS).
final class RestoringPDFView: PDFView {
    private let initialPageIndex: Int
    private(set) var reportsPageChanges = false
    private var fallbackScheduled = false

    init(initialPageIndex: Int) {
        self.initialPageIndex = initialPageIndex
        super.init(frame: .zero)
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layout() {
        super.layout()
        guard !reportsPageChanges, bounds.width > 0, bounds.height > 0, let document else { return }
        if let page = document.page(at: initialPageIndex), currentPage !== page { go(to: page) }
        if !fallbackScheduled {
            fallbackScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in self?.reportsPageChanges = true }
        }
        guard currentPage.flatMap({ document.index(for: $0) }) == initialPageIndex else { return }
        DispatchQueue.main.async { [weak self] in self?.reportsPageChanges = true }
    }
}

/// PencilKit drawing is an iPhone/iPad tool. These names keep the shared PDF reader complete; the Mac never creates an overlay.
enum MihbaraInkTool: String, CaseIterable, Identifiable {
    case pen, marker, eraser
    var id: String { rawValue }
}

@MainActor final class MihbaraInkOverlay {
    var tool: MihbaraInkTool = .pen
    var drawing = false
    var drawnPages = 0
    var hasPendingWrites: Bool { false }
    func flushAll() {}
    func flushAllAndWait(retry: Bool = false) async -> Bool { true }
}

struct MihbaraInkBar: View {
    let overlay: MihbaraInkOverlay
    let page: Int
    @Binding var tool: MihbaraInkTool
    let revision: Int
    let done: () -> Void
    var body: some View { EmptyView() }
}
