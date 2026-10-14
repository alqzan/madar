import SwiftUI
import UIKit
import CoreText
import MadarDesign
import MadarQuran

/// Original page glyphs retain the verified word map; semantic ayahs live above them.
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
                Text("سورة " + page.surahTitle)
            }.font(.custom("Amiri-Bold", size: 13)).foregroundStyle(theme.color("hifzText"))
                .padding(.horizontal, 12).frame(height: 26)
            if let reference = coach.referenceText, stage == .repetition, !coach.bridge {
                Text(reference).font(.custom(page.postScriptName, size: 16)).foregroundStyle(theme.color("mushafInk"))
                    .padding(8).frame(maxWidth: .infinity).background(theme.color("hifzTint"))
            }
            ZStack {
                if coach.review, stage == .review {
                    QuranCoachTextCanvas(page: page, coach: coach, stage: stage, ink: UIColor(theme.color("mushafInk")), tint: .clear, reveal: { _ in }, blurredWordsOnly: true)
                        .blur(radius: 3.5).opacity(0.28).padding(.horizontal, 8).padding(.vertical, 4)
                        .allowsHitTesting(false).accessibilityHidden(true)
                }
                QuranCoachTextCanvas(page: page, coach: coach, stage: stage, ink: UIColor(theme.color("mushafInk")), tint: UIColor(theme.color("hifzTint")), reveal: reveal, sealInk: UIColor(theme.color("hifzText")), sealTint: UIColor(theme.color("reviewTint")))
                    .padding(.horizontal, 8).padding(.vertical, 4).accessibilityHidden(true)
            }
            .accessibilityRepresentation {
                ForEach(page.semanticAyat.filter { coach.plannedAyahs.contains($0.id) }) { ayah in
                    if stage == .grading { Text(ayah.title + "، " + ayah.text) }
                    else if (stage == .covered || coach.review) && !coach.revealedAyahs.contains(ayah.id) {
                        Button("اكشف " + ayah.title) { reveal(ayah.id) }
                    } else {
                        Button { reveal(ayah.id) } label: { Text(ayah.title + "، " + ayah.text) }
                    }
                }
            }
            HStack { Spacer(); Text(page.numberLabel).font(.custom("Amiri-Bold", size: 13)) }
                .foregroundStyle(theme.color("hifzText")).padding(.horizontal, 12).frame(height: 22)
        }
        .background(theme.color("mushafPaper"))
    }
}

private struct QuranCoachTextCanvas: UIViewRepresentable {
    let page: QuranUIPage
    let coach: QuranUICoach
    let stage: QuranUISessionStage
    let ink: UIColor
    let tint: UIColor
    let reveal: (Int) -> Void
    var blurredWordsOnly = false
    var sealInk: UIColor = .black
    var sealTint: UIColor = .clear
    func makeUIView(context: Context) -> QuranCoachTextView { QuranCoachTextView() }
    func updateUIView(_ view: QuranCoachTextView, context: Context) {
        view.page = page; view.coach = coach; view.stage = stage; view.ink = ink; view.tint = tint; view.reveal = reveal; view.blurredWordsOnly = blurredWordsOnly; view.sealInk = sealInk; view.sealTint = sealTint
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
    var blurredWordsOnly = false
    var sealInk = UIColor.black
    var sealTint = UIColor.clear
    private var hits: [(CGRect, Int)] = []
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ rect: CGRect) {
        guard let page, let coach, let context = UIGraphicsGetCurrentContext(), bounds.width > 0,
              let unicodeFont = UIFont(name: page.postScriptName, size: 23.3),
              let printedName = page.printedPostScriptName, let printedFont = UIFont(name: printedName, size: 23.3) else { return }
        hits = []
        let rowHeight = bounds.height / CGFloat(page.lines.count)
        let minimumGap: CGFloat = 2.5
        let preferredSize: CGFloat = 23.3
        // Keep the normal page unchanged. In shorter layouts (such as grading),
        // fit the glyph height to each row so vowel marks retain clear air.
        var pageSize = preferredSize
        for row in page.lines where !row.words.isEmpty {
            for word in row.words {
                let glyphs = word.printedGlyphs ?? ""
                let text = NSMutableAttributedString(string: glyphs, attributes: [.font: printedFont])
                for (offset, character) in glyphs.utf16.enumerated() where character == 32 {
                    text.addAttribute(.font, value: unicodeFont, range: NSRange(location: offset, length: 1))
                }
                let image = CTLineGetImageBounds(CTLineCreateWithAttributedString(text), nil)
                pageSize = min(pageSize, preferredSize * rowHeight * 0.82 / max(image.height, 1))
            }
        }
        var masks: [Int: Set<Int>] = [:]
        func visibility(_ word: QuranUIWord, firstInLine: Bool) -> Bool {
            let planned = coach.plannedAyahs.contains(word.ayahID)
            let active = coach.bridge ? planned : word.ayahID == coach.activeAyahID
            let revealed = coach.revealedAyahs.contains(word.ayahID)
            if blurredWordsOnly { return planned && !revealed && word.index != nil }
            guard planned, !coach.bridge, !revealed else { return true }
            if coach.review && stage == .review { return word.index == nil }
            if stage == .covered { return false }
            guard active else { return true }
            if stage == .lineStarts { return firstInLine }
            if stage == .recall { return word.index == 0 }
            if coach.method == "completeAyah" { return (word.index ?? Int.max) < 2 }
            if coach.method == "next" { return false }
            if coach.method == "gradual", let index = word.index {
                if masks[word.ayahID] == nil { masks[word.ayahID] = QuranCoachProgress.hiddenWordIndices(ayahID: word.ayahID, wordCount: word.ayahWordCount, step: coach.repetition) }
                return !(masks[word.ayahID]?.contains(index) ?? false)
            }
            return true
        }
        for (rowIndex, row) in page.lines.enumerated() {
            let top = CGFloat(rowIndex) * rowHeight
            if row.words.isEmpty {
                let line = CTLineCreateWithAttributedString(NSAttributedString(string: row.glyphs, attributes: [.font: unicodeFont, .foregroundColor: ink]))
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
                let baseline = top + (rowHeight - ascent - descent) / 2 + ascent
                draw(line, at: CGPoint(x: (bounds.width - width) / 2, y: baseline), context: context)
                if row.surahOpening {
                    context.setStrokeColor(sealInk.withAlphaComponent(0.22).cgColor); context.setLineWidth(0.5)
                    for y in [top + 2, top + rowHeight - 2] { context.move(to: CGPoint(x: bounds.width * 0.12, y: y)); context.addLine(to: CGPoint(x: bounds.width * 0.88, y: y)) }
                    context.strokePath()
                }
                continue
            }
            var seenActive = false
            let shown = row.words.map { word in
                let active = coach.bridge ? coach.plannedAyahs.contains(word.ayahID) : word.ayahID == coach.activeAyahID
                let first = active && !seenActive
                if active { seenActive = true }
                return visibility(word, firstInLine: first)
            }
            func lines(size: CGFloat) -> [CTLine] {
                row.words.enumerated().map { index, word in
                    let glyphs = word.printedGlyphs ?? ""
                    let color = shown[index] ? (word.index == nil && !blurredWordsOnly ? sealInk : ink) : .clear
                    let text = NSMutableAttributedString(string: glyphs, attributes: [.font: printedFont.withSize(size), .foregroundColor: color])
                    // QCF contains presentation glyphs only. Spaces explicitly use the verified Unicode font.
                    for (offset, character) in glyphs.utf16.enumerated() where character == 32 {
                        text.addAttribute(.font, value: unicodeFont.withSize(size), range: NSRange(location: offset, length: 1))
                    }
                    return CTLineCreateWithAttributedString(text)
                }
            }
            var size = pageSize, wordLines = lines(size: pageSize)
            var widths = wordLines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
            let gapCount = CGFloat(max(0, widths.count - 1))
            let total = widths.reduce(0, +)
            if total + minimumGap * gapCount > bounds.width {
                size *= max(0.1, (bounds.width - minimumGap * gapCount) / total)
                wordLines = lines(size: size); widths = wordLines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
            }
            let gap = row.centered || gapCount == 0 ? minimumGap : max(minimumGap, (bounds.width - widths.reduce(0, +)) / gapCount)
            let lineWidth = widths.reduce(0, +) + gap * gapCount
            var right = row.centered ? (bounds.width + lineWidth) / 2 : bounds.width
            var ascent: CGFloat = 0, descent: CGFloat = 0
            for line in wordLines {
                var a: CGFloat = 0, d: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &a, &d, nil); ascent = max(ascent, a); descent = max(descent, d)
            }
            let baseline = top + (rowHeight - ascent - descent) / 2 + ascent
            var frames: [CGRect] = []
            for width in widths { frames.append(CGRect(x: right - width, y: top, width: width, height: rowHeight)); right -= width + gap }
            var highlight: CGRect?
            for (index, word) in row.words.enumerated() {
                let active = coach.bridge ? coach.plannedAyahs.contains(word.ayahID) : word.ayahID == coach.activeAyahID
                if active && shown[index] && stage == .repetition && coach.method == "coach" {
                    let box = CGRect(x: frames[index].minX - gap / 2, y: baseline - ascent, width: frames[index].width + gap, height: ascent + descent)
                    highlight = highlight.map { $0.union(box) } ?? box
                }
            }
            if let highlight { tint.setFill(); UIBezierPath(roundedRect: highlight, cornerRadius: 4).fill() }
            for (index, word) in row.words.enumerated() {
                if shown[index] && word.index == nil && !blurredWordsOnly {
                    let image = CTLineGetImageBounds(wordLines[index], nil)
                    let box = CGRect(x: frames[index].minX + image.minX, y: baseline - image.maxY, width: image.width, height: image.height)
                    let diameter = min(box.width, box.height) * 0.5
                    sealTint.setFill(); UIBezierPath(ovalIn: CGRect(x: box.midX - diameter / 2, y: box.midY - diameter / 2, width: diameter, height: diameter)).fill()
                }
                draw(wordLines[index], at: CGPoint(x: frames[index].minX, y: baseline), context: context)
                hits.append((frames[index].insetBy(dx: -gap / 2, dy: 0), word.ayahID))
            }
        }
    }
    private func draw(_ line: CTLine, at point: CGPoint, context: CGContext) {
        context.saveGState(); context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: point.x, y: bounds.height - point.y)
        CTLineDraw(line, context); context.restoreGState()
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        guard let coach, stage != .grading, !coach.bridge else { return }
        let point = gesture.location(in: self)
        if let id = hits.first(where: { $0.0.contains(point) })?.1, coach.plannedAyahs.contains(id) { reveal?(id) }
    }
}
