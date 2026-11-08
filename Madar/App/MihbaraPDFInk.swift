import PDFKit
import PencilKit
import SwiftData
import SwiftUI
import MadarCore
import MadarData
import MadarDesign

/// Keeps each page's latest unsaved bytes until its serial write succeeds.
/// A failed older write cannot discard a newer drawing or revive a cleared page.
@MainActor final class MihbaraInkSaveQueue {
    private struct Snapshot {
        let id = UUID()
        let data: Data
    }
    private var pending: [Int: Snapshot] = [:]
    private var chain: Task<Void, Never>?
    private var generation = 0
    private let save: (Int, Data) async throws -> Void
    var hasPending: Bool { !pending.isEmpty }

    init(save: @escaping (Int, Data) async throws -> Void) { self.save = save }

    func enqueue(page: Int, data: Data) {
        let snapshot = Snapshot(data: data)
        pending[page] = snapshot
        append(page: page, snapshot: snapshot)
    }

    private func append(page: Int, snapshot: Snapshot) {
        let previous = chain
        generation += 1
        chain = Task {
            await previous?.value
            // Coalesce a page that changed again before this attempt began.
            guard pending[page]?.id == snapshot.id else { return }
            do {
                try await save(page, snapshot.data)
                if pending[page]?.id == snapshot.id { pending[page] = nil }
            } catch {
                // Preserve the latest bytes, including an empty drawing (clear).
            }
        }
    }

    func waitForCurrentAttempt() async -> Bool {
        while let current = chain {
            let observedGeneration = generation
            await current.value
            if observedGeneration == generation { break }
        }
        return !hasPending
    }

    func retryAndWait() async -> Bool {
        _ = await waitForCurrentAttempt()
        for page in pending.keys.sorted() {
            if let snapshot = pending[page] { append(page: page, snapshot: snapshot) }
        }
        return await waitForCurrentAttempt()
    }
}

/// Owner, 30 Oct 2026 («الرسم على صفحات PDF»): the reader draws, underlines and circles on a PDF page with a finger
/// (or a Pencil where one exists). Each page's drawing is kept beside the book (`ink.savePage`, a Media row keyed
/// `pdf-ink:<book>:<page>`) and never written into the PDF, whose bytes are pinned by `fileHash`. Drawings are stored
/// in page points, so they land on the same words whatever the zoom or the screen.
enum MihbaraInkTool: String, CaseIterable, Identifiable {
    case pen, marker, eraser
    var id: String { rawValue }
    var title: String { switch self { case .pen: "قلم"; case .marker: "مظلّل"; case .eraser: "ممحاة" } }
    var symbol: String { switch self { case .pen: "pencil"; case .marker: "highlighter"; case .eraser: "eraser" } }
    var tool: PKTool {
        switch self {
        // These tokens stay fixed because PDF pages are white paper in both app appearances.
        case .pen: PKInkingTool(.pen, color: UIColor(MadarToken.colors["rooms.notes.pdf.pen"]!), width: 2)
        case .marker: PKInkingTool(.marker, color: UIColor(MadarToken.colors["rooms.notes.pdf.marker"]!), width: 14)
        case .eraser: PKEraserTool(.vector)
        }
    }
}

extension AppMihbaraService {
    /// The saved drawings of a PDF book, by 0-based page index.
    func pageInk(bookID: UUID) throws -> [Int: Data] {
        try Self.pageInk(container: app.container, bookID: bookID)
    }

    /// Fetch a book's drawings away from the UI executor; each worker owns its own context.
    func pageInkOffMain(bookID: UUID) async throws -> [Int: Data] {
        let container = app.container
        let worker = Task.detached(priority: .userInitiated) {
            try Self.pageInk(container: container, bookID: bookID)
        }
        let result = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return result
    }

    nonisolated private static func pageInk(container: ModelContainer, bookID: UUID) throws -> [Int: Data] {
        let prefix = "pdf-ink:\(bookID.uuidString):"
        var descriptor = FetchDescriptor<Media>(predicate: #Predicate {
            $0.kind == "drawing" && $0.deletedAt == nil && $0.mergedInto == nil && $0.sourceID?.starts(with: prefix) == true
        })
        descriptor.propertiesToFetch = [\.sourceID, \.updatedAt, \.data]
        let context = ModelContext(container)
        let rows = try context.fetch(descriptor)
        var result: [Int: (Date, Data)] = [:]
        for (index, row) in rows.enumerated() {
            if index.isMultiple(of: 128) { try Task.checkCancellation() }
            guard let key = row.sourceID, key.hasPrefix(prefix), let page = Int(key.dropFirst(prefix.count)), let data = row.data, !data.isEmpty else { continue }
            if (result[page]?.0 ?? .distantPast) < row.updatedAt { result[page] = (row.updatedAt, data) }
        }
        return result.mapValues(\.1)
    }
}

/// A canvas that holds its page's drawing in page points and shows it scaled to its own size.
final class MihbaraInkCanvas: PKCanvasView {
    let pageIndex: Int
    let pageWidth: CGFloat
    var pageDrawing = PKDrawing()
    private var appliedWidth: CGFloat = 0
    private(set) var applying = false

    init(pageIndex: Int, pageWidth: CGFloat) {
        self.pageIndex = pageIndex; self.pageWidth = max(pageWidth, 1)
        super.init(frame: .zero)
        backgroundColor = .clear; isOpaque = false
        isScrollEnabled = false; drawingPolicy = .anyInput
        showsVerticalScrollIndicator = false; showsHorizontalScrollIndicator = false
    }
    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func layoutSubviews() {
        super.layoutSubviews()
        guard bounds.width > 0, abs(bounds.width - appliedWidth) > 0.5 else { return }
        show(pageDrawing)
    }
    func show(_ drawing: PKDrawing) {
        pageDrawing = drawing
        guard bounds.width > 0 else { return }
        appliedWidth = bounds.width
        applying = true; defer { applying = false }
        let scale = bounds.width / pageWidth
        self.drawing = drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
    }
    /// The drawing on screen, back in page points.
    func capture() -> PKDrawing {
        // The scale the strokes are shown at, not the new size a pending layout has not applied yet.
        guard appliedWidth > 0 else { return pageDrawing }
        let scale = pageWidth / appliedWidth
        pageDrawing = drawing.transformed(using: CGAffineTransform(scaleX: scale, y: scale))
        return pageDrawing
    }
}

/// Gives PDFKit one canvas per visible page and saves a page shortly after the reader lifts the finger.
@MainActor final class MihbaraInkOverlay: NSObject, @preconcurrency PDFPageOverlayViewProvider, PKCanvasViewDelegate {
    private var drawings: [Int: PKDrawing]
    private var canvases: [Int: MihbaraInkCanvas] = [:]
    private var pending: [Int: DispatchWorkItem] = [:]
    private let saves: MihbaraInkSaveQueue
    /// Pages whose saved drawing could not be read: shown untouched and never drawn over, so nothing overwrites them.
    private let unreadable: Set<Int>
    var onChange: () -> Void = {}
    var drawing = false { didSet { canvases.values.forEach { $0.isUserInteractionEnabled = drawing && !unreadable.contains($0.pageIndex) } } }
    var tool: MihbaraInkTool = .pen { didSet { canvases.values.forEach { $0.tool = tool.tool } } }

    init(saved: [Int: Data], save: @escaping (Int, Data) async throws -> Void) {
        drawings = saved.compactMapValues { try? PKDrawing(data: $0) }
        unreadable = Set(saved.keys).subtracting(drawings.keys)
        self.saves = MihbaraInkSaveQueue(save: save)
    }

    var hasPendingWrites: Bool { !pending.isEmpty || saves.hasPending }
    var drawnPages: Int { drawings.values.filter { !$0.strokes.isEmpty }.count }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> UIView? {
        do {
            guard let index = page.document?.index(for: page), index >= 0 else { return nil }
            if let canvas = canvases[index] { return canvas }
            // A page turned a quarter is shown with its height across.
            let box = page.bounds(for: view.displayBox), turned = abs(page.rotation) % 180 == 90
            let canvas = MihbaraInkCanvas(pageIndex: index, pageWidth: turned ? box.height : box.width)
            canvas.pageDrawing = drawings[index] ?? PKDrawing()
            canvas.tool = tool.tool; canvas.isUserInteractionEnabled = drawing && !unreadable.contains(index); canvas.delegate = self
            canvas.accessibilityIdentifier = "mihbara-pdf-ink-canvas-\(index)"
            canvases[index] = canvas
            return canvas
        }
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: UIView, for page: PDFPage) {
        do {
            guard let canvas = overlayView as? MihbaraInkCanvas else { return }
            flush(canvas.pageIndex)
            canvases[canvas.pageIndex] = nil
        }
    }

    func canvasViewDrawingDidChange(_ canvasView: PKCanvasView) {
        do {
            guard let canvas = canvasView as? MihbaraInkCanvas, !canvas.applying else { return }
            let index = canvas.pageIndex
            drawings[index] = canvas.capture()
            pending[index]?.cancel()
            let work = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.flush(index) } }
            pending[index] = work
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8, execute: work)
            onChange()
        }
    }

    /// Saves one page now if it has unsaved strokes.
    func flush(_ index: Int) {
        guard let work = pending.removeValue(forKey: index) else { return }
        work.cancel()
        if let canvas = canvases[index] { drawings[index] = canvas.capture() }
        guard !unreadable.contains(index) else { return }
        let drawing = drawings[index] ?? PKDrawing()
        let data = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation()
        saves.enqueue(page: index, data: data)
    }
    func flushAll() { for index in Array(pending.keys) { flush(index) } }
    func flushAllAndWait(retry: Bool = false) async -> Bool {
        flushAll()
        if retry { return await saves.retryAndWait() }
        return await saves.waitForCurrentAttempt()
    }

    func undo(page: Int) { canvases[page]?.undoManager?.undo() }
    func canUndo(page: Int) -> Bool { canvases[page]?.undoManager?.canUndo ?? false }
    func clear(page: Int) {
        guard !unreadable.contains(page) else { return }
        if let canvas = canvases[page], !canvas.drawing.strokes.isEmpty { canvas.drawing = PKDrawing(); return }
        // No canvas on screen for this page: clear the kept drawing and save it directly.
        guard hasInk(page: page) else { return }
        drawings[page] = PKDrawing()
        pending[page] = DispatchWorkItem {}
        flush(page); onChange()
    }
    func hasInk(page: Int) -> Bool { !(drawings[page]?.strokes.isEmpty ?? true) }
}

/// The tools under the page while drawing: pen, marker, eraser, undo and «امسح الصفحة».
struct MihbaraInkBar: View {
    let overlay: MihbaraInkOverlay
    let page: Int
    @Binding var tool: MihbaraInkTool
    let revision: Int
    let done: () -> Void
    @Environment(\.roomTheme) private var theme

    var body: some View {
        HStack(spacing: 6) {
            ForEach(MihbaraInkTool.allCases) { item in
                Button { tool = item } label: {
                    Image(systemName: item.symbol).font(.title3)
                        .frame(width: 44, height: 44)
                        .background(tool == item ? theme.accentFill.opacity(0.18) : .clear, in: .circle)
                }
                .buttonStyle(.madarPlain).accessibilityLabel(item.title)
                .accessibilityAddTraits(tool == item ? .isSelected : [])
                .accessibilityIdentifier("mihbara-pdf-ink-tool-\(item.rawValue)")
            }
            Button { overlay.undo(page: page) } label: { Image(systemName: "arrow.uturn.backward").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.madarPlain).disabled(!overlay.canUndo(page: page)).accessibilityLabel("تراجع")
                .accessibilityIdentifier("mihbara-pdf-ink-undo")
            Button { overlay.clear(page: page) } label: { Image(systemName: "trash").font(.title3).frame(width: 44, height: 44) }
                .buttonStyle(.madarPlain).disabled(!overlay.hasInk(page: page)).accessibilityLabel("امسح رسم هذه الصفحة")
                .accessibilityIdentifier("mihbara-pdf-ink-clear")
            Spacer(minLength: 4)
            Button("تمّ", action: done).font(MadarTypography.caption()).padding(.horizontal, 16).frame(minHeight: 44)
                .background(theme.accentFill, in: .capsule).foregroundStyle(theme.onAccent)
                .buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-pdf-ink-done")
        }
        .id(revision)
        .padding(.horizontal, 12).padding(.vertical, 6)
    }
}
