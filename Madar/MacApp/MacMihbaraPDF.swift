import SwiftUI
import AppKit
import PDFKit
import PencilKit
import MadarDesign

/// PDFKit uses PencilKit's shared drawing format so marks appear on iPhone and iPad too.
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
        view.pageOverlayViewProvider = ink
        ink?.drawing = inking
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
        view.pageOverlayViewProvider = ink
        ink?.drawing = inking
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

enum MihbaraInkTool: String, CaseIterable, Identifiable {
    case pen, marker, eraser
    var id: String { rawValue }
    var title: String { switch self { case .pen: "قلم"; case .marker: "مظلّل"; case .eraser: "ممحاة" } }
    var symbol: String { switch self { case .pen: "pencil"; case .marker: "highlighter"; case .eraser: "eraser" } }
}

@MainActor final class MihbaraInkOverlay: NSObject, @preconcurrency PDFPageOverlayViewProvider {
    private var drawings: [Int: PKDrawing]
    private let unreadable: Set<Int>
    private var canvases: [Int: MacMihbaraInkCanvas] = [:]
    private var pending: [Int: Data] = [:]
    private var inFlight = Set<Int>()
    private var failed = Set<Int>()
    private let save: (Int, Data) async throws -> Void
    var onChange: () -> Void = {}
    var tool = MihbaraInkTool.pen { didSet { canvases.values.forEach { $0.tool = tool } } }
    var drawing = false { didSet { canvases.values.forEach { $0.enabled = drawing && !unreadable.contains($0.pageIndex) } } }
    var drawnPages: Int { drawings.values.filter { !$0.strokes.isEmpty }.count }
    var hasPendingWrites: Bool { !pending.isEmpty || !inFlight.isEmpty }

    init(saved: [Int: Data], save: @escaping (Int, Data) async throws -> Void) {
        drawings = saved.compactMapValues { try? PKDrawing(data: $0) }
        unreadable = Set(saved.keys).subtracting(drawings.keys)
        self.save = save
    }

    func pdfView(_ view: PDFView, overlayViewFor page: PDFPage) -> NSView? {
        guard let index = page.document?.index(for: page), index >= 0 else { return nil }
        if let canvas = canvases[index] { return canvas }
        let box = page.bounds(for: view.displayBox)
        let turned = abs(page.rotation) % 180 == 90
        let canvas = MacMihbaraInkCanvas(pageIndex: index,
                                         pageSize: CGSize(width: turned ? box.height : box.width,
                                                          height: turned ? box.width : box.height))
        canvas.drawing = drawings[index] ?? PKDrawing()
        canvas.tool = tool
        canvas.enabled = drawing && !unreadable.contains(index)
        canvas.onChange = { [weak self] drawing in self?.replace(drawing, for: index) }
        canvases[index] = canvas
        return canvas
    }

    func pdfView(_ pdfView: PDFView, willEndDisplayingOverlayView overlayView: NSView, for page: PDFPage) {
        guard let canvas = overlayView as? MacMihbaraInkCanvas else { return }
        replace(canvas.drawing, for: canvas.pageIndex)
        canvases[canvas.pageIndex] = nil
    }

    func flushAll() { canvases.values.forEach { replace($0.drawing, for: $0.pageIndex) } }

    func flushAllAndWait(retry: Bool = false) async -> Bool {
        flushAll()
        if retry {
            for page in failed { failed.remove(page); startSave(page) }
        }
        while !inFlight.isEmpty { try? await Task.sleep(for: .milliseconds(15)) }
        return pending.isEmpty && failed.isEmpty
    }

    private func replace(_ drawing: PKDrawing, for page: Int) {
        guard !unreadable.contains(page), drawings[page] != drawing else { return }
        drawings[page] = drawing
        pending[page] = drawing.dataRepresentation()
        onChange()
        startSave(page)
    }

    private func startSave(_ page: Int) {
        guard !inFlight.contains(page), !failed.contains(page), pending[page] != nil else { return }
        inFlight.insert(page)
        Task {
            while let data = pending.removeValue(forKey: page) {
                do { try await save(page, data); failed.remove(page) }
                catch {
                    if pending[page] == nil { pending[page] = data }
                    failed.insert(page)
                    break
                }
            }
            inFlight.remove(page)
            if pending[page] != nil && !failed.contains(page) { startSave(page) }
        }
    }
}

struct MihbaraInkBar: View {
    let overlay: MihbaraInkOverlay
    let page: Int
    @Binding var tool: MihbaraInkTool
    let revision: Int
    let done: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            ForEach(MihbaraInkTool.allCases) { option in
                toolButton(option)
            }
            Spacer(minLength: 8)
            if overlay.hasPendingWrites { ProgressView().controlSize(.small).accessibilityLabel("يحفظ الرسم") }
            Button("تمّ", action: done).keyboardShortcut(.cancelAction)
        }
        .padding(.horizontal, 16).padding(.vertical, 8)
        .environment(\.layoutDirection, .rightToLeft)
    }

    private func toolButton(_ option: MihbaraInkTool) -> some View {
        let selected = tool == option
        return Button { tool = option } label: {
            HStack(spacing: 6) {
                Image(systemName: option.symbol)
                Text(option.title)
            }
            .padding(.horizontal, 12).frame(minHeight: 40)
        }
        .buttonStyle(.bordered)
        .tint(selected ? .accentColor : .primary)
        .accessibilityAddTraits(selected ? .isSelected : [])
    }
}

@MainActor private final class MacMihbaraInkCanvas: NSView {
    let pageIndex: Int
    let pageSize: CGSize
    var drawing = PKDrawing() { didSet { needsDisplay = true } }
    var tool = MihbaraInkTool.pen
    var enabled = false
    var onChange: ((PKDrawing) -> Void)?
    private var path = NSBezierPath()

    override var isFlipped: Bool { true }

    init(pageIndex: Int, pageSize: CGSize) {
        self.pageIndex = pageIndex
        self.pageSize = CGSize(width: max(1, pageSize.width), height: max(1, pageSize.height))
        super.init(frame: .zero)
        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor
    }

    @available(*, unavailable) required init?(coder: NSCoder) { fatalError("init(coder:) is not used") }

    override func hitTest(_ point: NSPoint) -> NSView? { enabled ? super.hitTest(point) : nil }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        super.draw(dirtyRect)
        let image = drawing.image(from: CGRect(origin: .zero, size: pageSize), scale: 1)
        image.draw(in: bounds, from: .zero, operation: .sourceOver, fraction: 1, respectFlipped: true, hints: nil)
        guard path.elementCount > 0, tool != .eraser else { return }
        (tool == .pen ? inkColor : inkColor.withAlphaComponent(0.42)).setStroke()
        path.lineWidth = tool == .pen ? 2.2 : 13
        path.lineCapStyle = .round; path.lineJoinStyle = .round
        path.stroke()
    }

    override func mouseDown(with event: NSEvent) {
        guard enabled else { return }
        path = NSBezierPath(); path.move(to: point(event)); path.line(to: point(event))
        needsDisplay = true
    }

    override func mouseDragged(with event: NSEvent) {
        guard enabled else { return }
        path.line(to: point(event)); needsDisplay = true
    }

    override func mouseUp(with event: NSEvent) {
        guard enabled, path.elementCount > 0 else { return }
        path.line(to: point(event))
        let scale = pageSize.width / max(bounds.width, 1)
        let pagePath = path.copy() as! NSBezierPath
        pagePath.transform(using: AffineTransform(scale: scale))
        let width = tool == .pen ? 2.2 * scale : 13 * scale
        let pathPoints = PKStrokePath(bezierPath: pagePath.cgPath, creationDate: Date()) { point in
            PKStrokePoint(location: point.location, timeOffset: Double(point.index) / 60,
                          size: CGSize(width: width, height: width), opacity: 1, force: 1,
                          azimuth: 0, altitude: .pi / 2)
        }
        if tool == .eraser {
            drawing = drawing.erasingPath(pathPoints)
        } else {
            let ink = PKInk(tool == .marker ? .marker : .pen, color: inkColor)
            drawing = drawing.appending(PKDrawing(strokes: [PKStroke(ink: ink, path: pathPoints)]))
        }
        path = NSBezierPath(); onChange?(drawing); needsDisplay = true
    }

    private var inkColor: NSColor {
        let token = tool == .marker ? "rooms.notes.pdf.marker" : "rooms.notes.pdf.pen"
        let color = NSColor(MadarToken.colors[token] ?? .black)
        return color.usingColorSpace(.deviceRGB) ?? .black
    }

    private func point(_ event: NSEvent) -> NSPoint { convert(event.locationInWindow, from: nil) }
}

private extension NSBezierPath {
    var cgPath: CGPath {
        let result = CGMutablePath()
        for index in 0..<elementCount {
            var points = [NSPoint](repeating: .zero, count: 3)
            switch element(at: index, associatedPoints: &points) {
            case .moveTo: result.move(to: points[0])
            case .lineTo: result.addLine(to: points[0])
            case .curveTo, .cubicCurveTo: result.addCurve(to: points[2], control1: points[0], control2: points[1])
            case .quadraticCurveTo: result.addQuadCurve(to: points[1], control: points[0])
            case .closePath: result.closeSubpath()
            @unknown default: break
            }
        }
        return result
    }
}
