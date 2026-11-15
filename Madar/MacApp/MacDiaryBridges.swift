import SwiftUI
import AppKit
import Quartz

/// The diary's attachment preview: the same Quick Look the Finder uses, inside a sheet with a close button.
struct DiaryQuickLook: View {
    let url: URL
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text(url.lastPathComponent).font(.headline).lineLimit(1)
                Spacer()
                Button("تمّ") { dismiss() }.keyboardShortcut(.defaultAction)
            }.padding(12)
            QuickLookView(url: url)
        }
        .frame(minWidth: 560, minHeight: 640)
    }
    private struct QuickLookView: NSViewRepresentable {
        let url: URL
        func makeNSView(context: Context) -> QLPreviewView {
            let view = QLPreviewView(frame: .zero, style: .normal)!
            view.previewItem = url as NSURL
            return view
        }
        func updateNSView(_ view: QLPreviewView, context: Context) { view.previewItem = url as NSURL }
    }
}

extension NSImage {
    convenience init?(systemName: String) { self.init(systemSymbolName: systemName, accessibilityDescription: nil) }
    /// AppKit images report points; the pixel size already sits in `size` for decoded photos.
    var scale: CGFloat { 1 }
    func jpegData(compressionQuality: CGFloat) -> Data? {
        guard let tiff = tiffRepresentation, let bitmap = NSBitmapImageRep(data: tiff) else { return nil }
        return bitmap.representation(using: .jpeg, properties: [.compressionFactor: compressionQuality])
    }
}

/// UIKit's PDF renderer, drawn with Core Graphics on the Mac: pages use UIKit's top-left origin so the shared drawing code is unchanged.
final class UIGraphicsPDFRenderer {
    final class Context {
        let cgContext: CGContext
        private let bounds: CGRect
        private var open = false
        init(cgContext: CGContext, bounds: CGRect) { self.cgContext = cgContext; self.bounds = bounds }
        func beginPage() {
            if open { finish() }
            var box = bounds
            cgContext.beginPage(mediaBox: &box)
            cgContext.saveGState()
            cgContext.translateBy(x: 0, y: bounds.height)
            cgContext.scaleBy(x: 1, y: -1)
            NSGraphicsContext.current = NSGraphicsContext(cgContext: cgContext, flipped: true)
            open = true
        }
        func finish() {
            guard open else { return }
            cgContext.restoreGState(); cgContext.endPage(); open = false
        }
    }
    private let bounds: CGRect
    init(bounds: CGRect) { self.bounds = bounds }
    func pdfData(actions: (Context) -> Void) -> Data {
        let data = NSMutableData()
        var box = bounds
        guard let consumer = CGDataConsumer(data: data as CFMutableData), let cg = CGContext(consumer: consumer, mediaBox: &box, nil) else { return Data() }
        let previous = NSGraphicsContext.current
        let context = Context(cgContext: cg, bounds: bounds)
        actions(context)
        context.finish()
        cg.closePDF()
        NSGraphicsContext.current = previous
        return data as Data
    }
}

/// The few `UIBezierPath` calls the shared drawing code makes, on top of `NSBezierPath`.
final class UIBezierPath {
    private let path = NSBezierPath()
    var lineWidth: CGFloat { get { path.lineWidth } set { path.lineWidth = newValue } }
    func move(to point: CGPoint) { path.move(to: point) }
    func addLine(to point: CGPoint) { path.line(to: point) }
    func stroke() { path.stroke() }
    func fill() { path.fill() }
}

extension NSImage {
    convenience init(cgImage: CGImage) { self.init(cgImage: cgImage, size: .zero) }
}

/// `UIPasteboard.general.string`, on the Mac's general pasteboard.
@MainActor final class UIPasteboard {
    static let general = UIPasteboard()
    var string: String? {
        get { NSPasteboard.general.string(forType: .string) }
        set { NSPasteboard.general.clearContents(); if let newValue { NSPasteboard.general.setString(newValue, forType: .string) } }
    }
}
