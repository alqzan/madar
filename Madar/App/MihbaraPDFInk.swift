import PDFKit
import PencilKit
import SwiftData
import SwiftUI
import MadarCore
import MadarData
import MadarDesign

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
        // Fixed colours: the PDF page itself is always white paper, in light and dark mode alike.
        case .pen: PKInkingTool(.pen, color: UIColor(red: 0.12, green: 0.16, blue: 0.27, alpha: 1), width: 2)
        case .marker: PKInkingTool(.marker, color: UIColor(red: 0.98, green: 0.82, blue: 0.25, alpha: 1), width: 14)
        case .eraser: PKEraserTool(.vector)
        }
    }
}

extension AppMihbaraService {
    /// The saved drawings of a PDF book, by 0-based page index.
    func pageInk(bookID: UUID) throws -> [Int: Data] {
        let prefix = "pdf-ink:\(bookID.uuidString):"
        let rows = try ModelContext(app.container).fetch(FetchDescriptor<Media>(predicate: #Predicate { $0.kind == "drawing" && $0.deletedAt == nil && $0.mergedInto == nil }))
        var result: [Int: (Date, Data)] = [:]
        for row in rows {
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
    private let save: (Int, Data) async -> Void
    /// Pages whose saved drawing could not be read: shown untouched and never drawn over, so nothing overwrites them.
    private let unreadable: Set<Int>
    /// Saves run one after another, so a cleared page never comes back from an earlier save finishing late.
    private var chain: Task<Void, Never>?
    var onChange: () -> Void = {}
    var drawing = false { didSet { canvases.values.forEach { $0.isUserInteractionEnabled = drawing && !unreadable.contains($0.pageIndex) } } }
    var tool: MihbaraInkTool = .pen { didSet { canvases.values.forEach { $0.tool = tool.tool } } }

    init(saved: [Int: Data], save: @escaping (Int, Data) async -> Void) {
        drawings = saved.compactMapValues { try? PKDrawing(data: $0) }
        unreadable = Set(saved.keys).subtracting(drawings.keys)
        self.save = save
    }

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
        let data = drawing.strokes.isEmpty ? Data() : drawing.dataRepresentation(), previous = chain, save = save
        chain = Task { await previous?.value; await save(index, data) }
    }
    func flushAll() { for index in Array(pending.keys) { flush(index) } }

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
