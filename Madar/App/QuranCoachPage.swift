import SwiftUI
import UIKit
import CoreText
import MadarDesign
import MadarQuran
import MadarCore

/// The verified word map is drawn with the bundled Hafs font. Semantic ayahs live above it.
struct QuranCoachPage: View {
    let page: QuranUIPage
    let coach: QuranUICoach
    let stage: QuranUISessionStage
    let reveal: (Int) -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 4) {
            HStack {
                Text(page.juzTitle)
                Spacer()
                Text(page.numberLabel).font(.custom("Amiri-Bold", size: 17))
                Spacer()
                Text(page.surahTitle).font(.custom(page.postScriptName, size: 20))
            }.font(.custom("Amiri-Regular", size: 20)).foregroundStyle(theme.color("mushafInk"))
                .padding(.horizontal, 18).frame(height: 30)
            if let reference = coach.referenceText, stage == .repetition, !coach.bridge {
                Text(reference).font(.custom(page.postScriptName, size: 16)).foregroundStyle(theme.color("mushafInk"))
                    .padding(8).frame(maxWidth: .infinity).background(theme.color("hifzTint"))
            }
            ZStack {
                QuranCoachTextCanvas(page: page, coach: coach, stage: stage, ink: UIColor(theme.color("mushafInk")), tint: UIColor(theme.color("hifzTint")), reveal: reveal)
                    .padding(.horizontal, 19).padding(.vertical, 17).accessibilityHidden(true)
                QuranPageOrnament().allowsHitTesting(false)
                GeometryReader { proxy in
                    ForEach(page.lines.filter(\.surahOpening)) { line in
                        QuranPageOrnament(opening: true)
                            .frame(width: proxy.size.width - 42, height: (proxy.size.width - 42) * 66 / 541)
                            .position(x: proxy.size.width / 2, y: 17 + (CGFloat(line.id) - 0.5) * (proxy.size.height - 34) / CGFloat(page.lines.count))
                    }
                }.allowsHitTesting(false)
            }
            .accessibilityRepresentation {
                ForEach(page.semanticAyat.filter { coach.plannedAyahs.contains($0.id) }) { ayah in
                    if stage == .grading { Text(ayah.title + "، " + ayah.text) }
                    else if stage == .covered && !coach.revealedAyahs.contains(ayah.id) {
                        Button("اكشف " + ayah.title) { reveal(ayah.id) }
                    } else {
                        Button { reveal(ayah.id) } label: { Text(ayah.title + "، " + ayah.text) }
                    }
                }
            }
        }
        .background(theme.color("mushafPaper"))
        .brightness(theme.dark ? -0.14 : 0)
    }
}

private struct QuranCoachTextCanvas: UIViewRepresentable {
    let page: QuranUIPage
    let coach: QuranUICoach
    let stage: QuranUISessionStage
    let ink: UIColor
    let tint: UIColor
    let reveal: (Int) -> Void
    func makeUIView(context: Context) -> QuranCoachTextView { QuranCoachTextView() }
    func updateUIView(_ view: QuranCoachTextView, context: Context) {
        view.page = page; view.coach = coach; view.stage = stage; view.ink = ink; view.tint = tint; view.reveal = reveal
        view.setNeedsDisplay()
    }
}

private final class QuranCoachTextView: UIView {
    var page: QuranUIPage?
    var coach: QuranUICoach?
    var stage: QuranUISessionStage = .repetition
    var ink = UIColor.black
    var tint = UIColor.clear
    var reveal: ((Int) -> Void)?
    private var hits: [(CTLine, CGFloat, [(NSRange, Int)])] = []
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ rect: CGRect) {
        guard let page, let coach, let context = UIGraphicsGetCurrentContext(), bounds.width > 0,
              let baseFont = UIFont(name: page.postScriptName, size: 23.3) else { return }
        hits = []
        let rowHeight = bounds.height / CGFloat(page.lines.count)
        var masks: [Int: Set<Int>] = [:]
        for (index, row) in page.lines.enumerated() {
            let content = NSMutableAttributedString(string: "")
            var ranges: [(NSRange, Int)] = []
            var highlighted: [NSRange] = []
            var lineStartSeen = false
            for word in row.words {
                let planned = coach.plannedAyahs.contains(word.ayahID)
                let active = coach.bridge ? planned : word.ayahID == coach.activeAyahID
                let revealed = coach.revealedAyahs.contains(word.ayahID)
                var visible = true
                if planned && !coach.bridge && !revealed {
                    if stage == .covered { visible = false }
                    else if active && stage == .lineStarts { visible = !lineStartSeen; lineStartSeen = true }
                    else if active && stage == .recall { visible = word.index == 0 }
                    else if active && coach.method == "completeAyah" { visible = (word.index ?? Int.max) < 2 }
                    else if active && coach.method == "next" { visible = false }
                    else if active && coach.method == "gradual", let wordIndex = word.index {
                        if masks[word.ayahID] == nil { masks[word.ayahID] = QuranCoachProgress.hiddenWordIndices(ayahID: word.ayahID, wordCount: word.ayahWordCount, step: coach.repetition) }
                        visible = !(masks[word.ayahID]?.contains(wordIndex) ?? false)
                    }
                }
                let color = visible ? ink.withAlphaComponent(active || stage == .grading || (planned && stage == .covered) ? 1 : 0.22) : .clear
                let text = word.text + " "
                let range = NSRange(location: content.length, length: (text as NSString).length)
                content.append(NSAttributedString(string: text, attributes: [.foregroundColor: color]))
                ranges.append((range, word.ayahID))
                if active && visible && stage == .repetition && coach.method == "coach" {
                    if let last = highlighted.last, NSMaxRange(last) == range.location {
                        highlighted[highlighted.count - 1] = NSUnionRange(last, range)
                    } else { highlighted.append(range) }
                }
            }
            if row.words.isEmpty { content.append(NSAttributedString(string: row.glyphs, attributes: [.foregroundColor: ink])) }
            let paragraph = NSMutableParagraphStyle(); paragraph.baseWritingDirection = .rightToLeft
            var size: CGFloat = 23.3
            func line(_ size: CGFloat) -> CTLine {
                content.addAttributes([.font: baseFont.withSize(size), .paragraphStyle: paragraph], range: NSRange(location: 0, length: content.length))
                return CTLineCreateWithAttributedString(content)
            }
            var drawn = line(size)
            let natural = CGFloat(CTLineGetTypographicBounds(drawn, nil, nil, nil))
            if natural > bounds.width { size *= bounds.width / natural; drawn = line(size) }
            let width = CGFloat(CTLineGetTypographicBounds(drawn, nil, nil, nil))
            var x: CGFloat = row.centered ? (bounds.width - width) / 2 : 0
            if !row.centered, let justified = CTLineCreateJustifiedLine(drawn, 1, Double(bounds.width)) { drawn = justified }
            else if !row.centered { x = (bounds.width - width) / 2 }
            var ascent: CGFloat = 0, descent: CGFloat = 0
            _ = CTLineGetTypographicBounds(drawn, &ascent, &descent, nil)
            let top = CGFloat(index) * rowHeight
            let baseline = top + (rowHeight - ascent - descent) / 2 + ascent
            for range in highlighted {
                let a = CTLineGetOffsetForStringIndex(drawn, range.location, nil)
                let b = CTLineGetOffsetForStringIndex(drawn, NSMaxRange(range), nil)
                let box = CGRect(x: x + min(a, b), y: baseline - ascent, width: abs(b - a), height: ascent + descent)
                tint.setFill(); UIBezierPath(roundedRect: box.insetBy(dx: -1, dy: 0), cornerRadius: 4).fill()
            }
            context.saveGState(); context.textMatrix = .identity
            context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
            context.textPosition = CGPoint(x: x, y: bounds.height - baseline); CTLineDraw(drawn, context); context.restoreGState()
            hits.append((drawn, x, ranges))
        }
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let coach, stage != .grading, !coach.bridge, !hits.isEmpty else { return }
        let point = gesture.location(in: self)
        let row = min(hits.count - 1, max(0, Int(point.y / (bounds.height / CGFloat(hits.count)))))
        let (line, x, ranges) = hits[row]
        let offset = CTLineGetStringIndexForPosition(line, CGPoint(x: point.x - x, y: 0))
        if let id = ranges.first(where: { NSLocationInRange(offset, $0.0) })?.1, coach.plannedAyahs.contains(id) { reveal?(id) }
    }
}

private struct QuranOrnamentPiece: Identifiable { let image: UIImage; let rect: CGRect; var id: String { "\(rect.minX):\(rect.minY)" } }
private final class QuranOrnamentParser: NSObject, XMLParserDelegate {
    var pieces: [QuranOrnamentPiece] = []
    func parser(_ parser: XMLParser, didStartElement name: String, namespaceURI: String?, qualifiedName: String?, attributes: [String: String]) {
        guard name == "image", let href = attributes["href"], let encoded = href.split(separator: ",", maxSplits: 1).last,
              let data = Data(base64Encoded: String(encoded)), let image = UIImage(data: data),
              let x = Double(attributes["x"] ?? ""), let y = Double(attributes["y"] ?? ""),
              let width = Double(attributes["width"] ?? ""), let height = Double(attributes["height"] ?? "") else { return }
        pieces.append(QuranOrnamentPiece(image: image, rect: CGRect(x: x, y: y, width: width, height: height)))
    }
}
private struct QuranPageOrnament: View {
    var opening = false
    private static func load(_ name: String) -> [QuranOrnamentPiece] {
        guard let data = try? QuranResourceManifest.bundled().ornament(named: name) else { return [] }
        let delegate = QuranOrnamentParser(), parser = XMLParser(data: data); parser.delegate = delegate
        return parser.parse() ? delegate.pieces : []
    }
    private static let framePieces = load("page-frame")
    private static let openingPieces = load("surah-opening")
    var body: some View {
        GeometryReader { proxy in
            ForEach(opening ? Self.openingPieces : Self.framePieces) { piece in
                let x = proxy.size.width / (opening ? 541 : 643), y = proxy.size.height / (opening ? 66 : 926)
                Image(uiImage: piece.image).resizable()
                    .frame(width: piece.rect.width * x, height: piece.rect.height * y)
                    .position(x: piece.rect.midX * x, y: piece.rect.midY * y)
            }
        }.accessibilityHidden(true)
    }
}
