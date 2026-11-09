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
    /// Long press on a hidden word records a slip on that exact word (§7.4 MistakeEvent.wordIndex).
    var markWord: ((Int, Int) -> Void)? = nil
    var readingTap: (() -> Void)? = nil
    /// Owner's MedinaOld reference: ornament only; the verified edition stays intact.
    var medinaStyle = false
    /// FB-33: the ayah the reader pressed on, softly lit while its tafsir is open.
    var selectedAyah: Int? = nil
    var ayahPress: ((Int) -> Void)? = nil
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 4) {
            if medinaStyle {
                // FB-33, owner's printed Madinah page: the juz on the right, the surah on the left, no frame.
                HStack(spacing: 8) {
                    Text(page.juzTitle).frame(maxWidth: .infinity, alignment: .leading)
                    Text("سورة " + page.surahTitle).frame(maxWidth: .infinity, alignment: .trailing)
                }.font(.custom("Amiri-Bold", size: 17)).lineLimit(1).minimumScaleFactor(0.7)
                    .foregroundStyle(theme.color("reviewText"))
                    .padding(.horizontal, 16).frame(height: 30)
                    // Owner, 5 Nov: keep the Quran's green and gold without a frame: one gold rule under the header.
                    .overlay(alignment: .bottom) {
                        LinearGradient(colors: [theme.color("gold").opacity(0), theme.color("gold"), theme.color("gold").opacity(0)], startPoint: .leading, endPoint: .trailing)
                            .frame(height: 1.2).padding(.horizontal, 12)
                    }
            } else {
                HStack {
                    Text(page.juzTitle)
                    Spacer()
                    Text("سورة " + page.surahTitle)
                }.font(.custom("Amiri-Bold", size: 13)).foregroundStyle(theme.color("hifzText"))
                    .padding(.horizontal, 12).frame(height: 26)
            }
            if let reference = coach.referenceText, stage == .repetition, !coach.bridge {
                Text(reference).font(.custom(page.postScriptName, size: 16)).foregroundStyle(theme.color("mushafInk"))
                    .padding(8).frame(maxWidth: .infinity).background(theme.color("hifzTint"))
            }
            ZStack {
                if coach.review, stage == .review {
                    QuranCoachTextCanvas(
                        page: page, coach: coach, stage: stage, ink: UIColor(theme.color("mushafInk")), tint: .clear,
                        reveal: { _ in }, blurredWordsOnly: true, medinaStyle: medinaStyle
                    )
                    .blur(radius: 3.5).opacity(0.28).padding(.horizontal, medinaStyle ? 12 : 8).padding(
                        .vertical, medinaStyle ? 14 : 4
                    )
                    .allowsHitTesting(false).accessibilityHidden(true)
                }
                QuranCoachTextCanvas(
                    page: page, coach: coach, stage: stage, ink: UIColor(theme.color("mushafInk")),
                    tint: UIColor(theme.color("hifzTint")), reveal: reveal, markWord: markWord, readingTap: readingTap,
                    mark: UIColor(theme.color("due")), sealInk: UIColor(theme.color(medinaStyle ? "reviewText" : "hifzText")),
                    sealTint: UIColor(theme.color("reviewTint")), medinaStyle: medinaStyle,
                    gold: UIColor(theme.color("gold")), paper: UIColor(theme.color("mushafPaper")),
                    selectedAyah: selectedAyah, ayahPress: ayahPress
                )
                .padding(.horizontal, medinaStyle ? 12 : 8).padding(.vertical, medinaStyle ? 8 : 4)
                .accessibilityHidden(true)
            }
            .accessibilityRepresentation {
                ForEach(page.semanticAyat.filter { coach.plannedAyahs.contains($0.id) }) { ayah in
                    if stage == .grading {
                        Text(ayah.title + "، " + ayah.text)
                    } else if (stage == .covered || coach.review) && !coach.revealedAyahs.contains(ayah.id) {
                        Button("اكشف " + ayah.title) { reveal(ayah.id) }
                    } else {
                        Button {
                            reveal(ayah.id)
                        } label: {
                            Text(ayah.title + "، " + ayah.text)
                        }
                    }
                }
            }
            if medinaStyle {
                QuranPageNumberOval(number: page.numberLabel, gold: theme.color("gold"), ink: theme.color("onCover"), green: theme.color("cover"))
                    .frame(height: 30).accessibilityHidden(true)
            } else {
                HStack {
                    Spacer(); Text(page.numberLabel).font(.custom("Amiri-Bold", size: 13))
                }
                .foregroundStyle(theme.color("hifzText")).padding(.horizontal, 12).frame(height: 22)
            }
        }
        .background(theme.color("mushafPaper"))
    }
}

/// The printed page number sits in a small gold oval between two fine rules ending in lozenges.
private struct QuranPageNumberOval: View {
    let number: String, gold: Color, ink: Color, green: Color
    var body: some View {
        HStack(spacing: 6) {
            rule(flipped: false)
            Text(number).font(.custom("Amiri-Bold", size: 15)).foregroundStyle(ink).monospacedDigit()
                .padding(.horizontal, 14).frame(minWidth: 52, minHeight: 26)
                .background { Ellipse().fill(green) }
                .overlay { Ellipse().inset(by: 2.4).stroke(gold, lineWidth: 1) }
                .overlay { Ellipse().stroke(gold.opacity(0.7), lineWidth: 0.8) }
            rule(flipped: true)
        }
    }
    /// Right to left: the first rule sits on the right, so each line fades toward the page edge.
    private func rule(flipped: Bool) -> some View {
        let line = Rectangle()
            .fill(LinearGradient(colors: flipped ? [gold.opacity(0), gold.opacity(0.8)] : [gold.opacity(0.8), gold.opacity(0)], startPoint: .leading, endPoint: .trailing))
            .frame(width: 46, height: 0.8)
        let lozenge = Rectangle().fill(gold).frame(width: 5, height: 5).rotationEffect(.degrees(45))
        return HStack(spacing: 4) {
            if flipped { lozenge; line } else { line; lozenge }
        }
    }
}

private struct QuranCoachTextCanvas: UIViewRepresentable {
    let page: QuranUIPage
    let coach: QuranUICoach
    let stage: QuranUISessionStage
    let ink: UIColor
    let tint: UIColor
    let reveal: (Int) -> Void
    var markWord: ((Int, Int) -> Void)? = nil
    var readingTap: (() -> Void)? = nil
    var mark: UIColor = .red
    var blurredWordsOnly = false
    var sealInk: UIColor = .black
    var sealTint: UIColor = .clear
    var medinaStyle = false
    var gold: UIColor = .clear
    var paper: UIColor = .clear
    var selectedAyah: Int? = nil
    var ayahPress: ((Int) -> Void)? = nil
    func makeUIView(context: Context) -> QuranCoachTextView { QuranCoachTextView() }
    func updateUIView(_ view: QuranCoachTextView, context: Context) {
        view.page = page; view.coach = coach; view.stage = stage; view.ink = ink; view.tint = tint;
        view.reveal = reveal; view.markWord = markWord; view.readingTap = readingTap; view.mark = mark;
        view.blurredWordsOnly = blurredWordsOnly; view.sealInk = sealInk; view.sealTint = sealTint
        view.medinaStyle = medinaStyle; view.gold = gold; view.paper = paper
        view.selectedAyah = selectedAyah; view.ayahPress = ayahPress
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
    var markWord: ((Int, Int) -> Void)?
    var readingTap: (() -> Void)?
    var mark = UIColor.red
    var blurredWordsOnly = false
    var sealInk = UIColor.black
    var sealTint = UIColor.clear
    var medinaStyle = false
    var gold = UIColor.clear
    var paper = UIColor.clear
    var selectedAyah: Int?
    var ayahPress: ((Int) -> Void)?
    private var bandImage: UIImage?
    private var bandInk = UIColor.clear
    private var bandGold = UIColor.clear
    private var hits: [(CGRect, Int, Int?)] = []
    override init(frame: CGRect) {
        super.init(frame: frame); isOpaque = false; backgroundColor = .clear
        addGestureRecognizer(UITapGestureRecognizer(target: self, action: #selector(tap(_:))))
        addGestureRecognizer(UILongPressGestureRecognizer(target: self, action: #selector(press(_:))))
        // Owner 20 Oct: uncover the page with the finger, the way a hand slides off a covered line.
        let drag = UIPanGestureRecognizer(target: self, action: #selector(drag(_:))); drag.maximumNumberOfTouches = 1
        addGestureRecognizer(drag)
        isAccessibilityElement = false
    }
    required init?(coder: NSCoder) { nil }
    override func draw(_ rect: CGRect) {
        guard let page, let coach, let context = UIGraphicsGetCurrentContext(), bounds.width > 0,
            let unicodeFont = UIFont(name: page.postScriptName, size: 23.3),
            let printedName = page.printedPostScriptName, let printedFont = UIFont(name: printedName, size: 23.3)
        else { return }
        hits = []
        let rowHeight = bounds.height / CGFloat(page.lines.count)
        let minimumGap: CGFloat = 2.5
        let preferredSize: CGFloat = 23.3
        // The compact control strip leaves the page its normal type size.
        let pageSize = preferredSize
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
                if masks[word.ayahID] == nil {
                    masks[word.ayahID] = QuranCoachProgress.hiddenWordIndices(
                        ayahID: word.ayahID, wordCount: word.ayahWordCount, step: coach.repetition)
                }
                return !(masks[word.ayahID]?.contains(index) ?? false)
            }
            return true
        }
        for (rowIndex, row) in page.lines.enumerated() {
            let top = CGFloat(rowIndex) * rowHeight
            if row.words.isEmpty {
                if medinaStyle && row.surahOpening {
                    drawSurahBand(
                        in: CGRect(x: 0, y: top + 2, width: bounds.width, height: rowHeight - 4), context: context)
                }
                let text = medinaStyle && row.surahOpening ? "سُورَةُ " + row.glyphs : row.glyphs
                let line = CTLineCreateWithAttributedString(
                    NSAttributedString(
                        string: text,
                        attributes: [
                            .font: unicodeFont.withSize(medinaStyle && row.surahOpening ? 21 : preferredSize),
                            .foregroundColor: ink,
                        ]))
                var ascent: CGFloat = 0, descent: CGFloat = 0
                let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, nil))
                let baseline = top + (rowHeight - ascent - descent) / 2 + ascent
                draw(line, at: CGPoint(x: (bounds.width - width) / 2, y: baseline), context: context)
                if row.surahOpening && !medinaStyle {
                    context.setStrokeColor(sealInk.withAlphaComponent(0.22).cgColor); context.setLineWidth(0.5)
                    for y in [top + 2, top + rowHeight - 2] {
                        context.move(to: CGPoint(x: bounds.width * 0.12, y: y));
                        context.addLine(to: CGPoint(x: bounds.width * 0.88, y: y))
                    }
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
                    let text = NSMutableAttributedString(
                        string: glyphs, attributes: [.font: printedFont.withSize(size), .foregroundColor: color])
                    // QCF contains presentation glyphs only. Spaces explicitly use the verified Unicode font.
                    for (offset, character) in glyphs.utf16.enumerated() where character == 32 {
                        text.addAttribute(
                            .font, value: unicodeFont.withSize(size), range: NSRange(location: offset, length: 1))
                    }
                    return CTLineCreateWithAttributedString(text)
                }
            }
            var size = pageSize, wordLines = lines(size: pageSize)
            func lineWidths(_ wordLines: [CTLine], size: CGFloat) -> [CGFloat] {
                wordLines.map { CGFloat(CTLineGetTypographicBounds($0, nil, nil, nil)) }
            }
            var widths = lineWidths(wordLines, size: pageSize)
            let gapCount = CGFloat(max(0, widths.count - 1))
            let total = widths.reduce(0, +)
            if total + minimumGap * gapCount > bounds.width {
                size *= max(0.1, (bounds.width - minimumGap * gapCount) / total)
                wordLines = lines(size: size); widths = lineWidths(wordLines, size: size)
            }
            let gap =
                row.centered || gapCount == 0
                ? minimumGap : max(minimumGap, (bounds.width - widths.reduce(0, +)) / gapCount)
            let lineWidth = widths.reduce(0, +) + gap * gapCount
            var right = row.centered ? (bounds.width + lineWidth) / 2 : bounds.width
            var ascent: CGFloat = 0, descent: CGFloat = 0
            for line in wordLines {
                var a: CGFloat = 0, d: CGFloat = 0
                _ = CTLineGetTypographicBounds(line, &a, &d, nil); ascent = max(ascent, a); descent = max(descent, d)
            }
            let baseline = top + (rowHeight - ascent - descent) / 2 + ascent
            var frames: [CGRect] = []
            for width in widths {
                frames.append(CGRect(x: right - width, y: top, width: width, height: rowHeight)); right -= width + gap
            }
            var highlight: CGRect?
            for (index, word) in row.words.enumerated() {
                let active = coach.bridge ? coach.plannedAyahs.contains(word.ayahID) : word.ayahID == coach.activeAyahID
                if active && shown[index] && stage == .repetition && coach.method == "coach" {
                    let box = CGRect(
                        x: frames[index].minX - gap / 2, y: baseline - ascent, width: frames[index].width + gap,
                        height: ascent + descent)
                    highlight = highlight.map { $0.union(box) } ?? box
                }
            }
            if let highlight { tint.setFill(); UIBezierPath(roundedRect: highlight, cornerRadius: 4).fill() }
            // FB-33: the pressed ayah is lit across each of its lines, as Quran readers do.
            if let selectedAyah {
                var lit: CGRect?
                for (index, word) in row.words.enumerated() where word.ayahID == selectedAyah {
                    let box = CGRect(x: frames[index].minX - gap / 2, y: top + 1.5, width: frames[index].width + gap, height: rowHeight - 3)
                    lit = lit.map { $0.union(box) } ?? box
                }
                if let lit {
                    gold.withAlphaComponent(0.2).setFill()
                    UIBezierPath(roundedRect: lit.intersection(bounds.insetBy(dx: -2, dy: 0)), cornerRadius: 7).fill()
                }
            }
            for (index, word) in row.words.enumerated() {
                if shown[index] && word.index == nil && !blurredWordsOnly {
                    let image = CTLineGetImageBounds(wordLines[index], nil)
                    let box = CGRect(
                        x: frames[index].minX + image.minX, y: baseline - image.maxY, width: image.width,
                        height: image.height)
                    // FB-33: the printed marker keeps the font's own ornament, lit by a soft gold disc.
                    let diameter = min(box.width, box.height) * (medinaStyle ? 0.74 : 0.5)
                    (medinaStyle ? gold.withAlphaComponent(0.55) : sealTint).setFill();
                    UIBezierPath(
                        ovalIn: CGRect(
                            x: box.midX - diameter / 2, y: box.midY - diameter / 2, width: diameter, height: diameter)
                    ).fill()
                }
                draw(wordLines[index], at: CGPoint(x: frames[index].minX, y: baseline), context: context)
                if let wordIndex = word.index, coach.flaggedWords.contains(QuranUICoach.wordKey(word.ayahID, wordIndex))
                {
                    mark.setFill();
                    UIBezierPath(
                        ovalIn: CGRect(x: frames[index].midX - 2.5, y: baseline + descent * 0.4, width: 5, height: 5)
                    ).fill()
                }
                hits.append((frames[index].insetBy(dx: -gap / 2, dy: 0), word.ayahID, word.index))
            }
        }
    }
    /// Use the already verified, owner-authorized 1405 ornament without importing
    /// its text or page map. Paper pixels become transparent; only ink is tinted.
    private func drawSurahBand(in box: CGRect, context: CGContext) {
        if bandInk != sealInk || bandGold != gold || bandImage == nil {
            bandInk = sealInk; bandGold = gold
            bandImage = QuranSurahArtwork.image(ink: sealInk, gold: gold)
        }
        if let bandImage {
            bandImage.draw(in: box)
        } else {
            sealInk.setStroke()
            let frame = UIBezierPath(rect: box.insetBy(dx: 0.5, dy: 0.5)); frame.lineWidth = 0.7; frame.stroke()
        }
    }

    private func draw(_ line: CTLine, at point: CGPoint, context: CGContext) {
        context.saveGState(); context.textMatrix = .identity
        context.translateBy(x: 0, y: bounds.height); context.scaleBy(x: 1, y: -1)
        context.textPosition = CGPoint(x: point.x, y: bounds.height - point.y)
        CTLineDraw(line, context); context.restoreGState()
    }
    @objc private func tap(_ gesture: UITapGestureRecognizer) {
        if let readingTap { readingTap(); return }
        guard let coach, stage != .grading, !coach.bridge else { return }
        let point = gesture.location(in: self)
        if let id = hits.first(where: { $0.0.contains(point) })?.1, coach.plannedAyahs.contains(id) { reveal?(id) }
    }
    private var dragRevealed: Set<Int> = []
    /// Sliding down the page reveals each covered planned ayah the finger passes over, once, in the order it was touched.
    /// A sideways swipe anywhere (owner OR-19) reveals the next covered ayah in reading order, like turning a card.
    @objc private func drag(_ gesture: UIPanGestureRecognizer) {
        guard let coach, stage != .grading, !coach.bridge, readingTap == nil else { return }
        if gesture.state == .began { dragRevealed = [] }
        let move = gesture.translation(in: self)
        if gesture.state == .ended {
            guard dragRevealed.isEmpty, abs(move.x) > 50, abs(move.x) > abs(move.y) * 1.5,
                let next = coach.plannedAyahs.subtracting(coach.revealedAyahs).min()
            else { return }
            UISelectionFeedbackGenerator().selectionChanged()
            reveal?(next)
            return
        }
        guard gesture.state == .changed, abs(move.y) >= abs(move.x) else { return }
        let point = gesture.location(in: self)
        guard let id = hits.first(where: { $0.0.insetBy(dx: 0, dy: -6).contains(point) })?.1,
            coach.plannedAyahs.contains(id),
            !coach.revealedAyahs.contains(id), !dragRevealed.contains(id)
        else { return }
        dragRevealed.insert(id)
        UISelectionFeedbackGenerator().selectionChanged()
        reveal?(id)
    }
    /// Only while the words are hidden from the reciter: blind recitation, or the covered one-step review.
    @objc private func press(_ gesture: UILongPressGestureRecognizer) {
        // FB-33: while reading, a long press on an ayah opens its tafsir.
        if let ayahPress, readingTap != nil {
            guard gesture.state == .began,
                let hit = hits.first(where: { $0.0.insetBy(dx: 0, dy: -4).contains(gesture.location(in: self)) })
            else { return }
            UIImpactFeedbackGenerator(style: .soft).impactOccurred()
            ayahPress(hit.1)
            return
        }
        guard gesture.state == .began, let coach, !coach.bridge, stage == .covered || (coach.review && stage == .review)
        else { return }
        let point = gesture.location(in: self)
        guard let hit = hits.first(where: { $0.0.contains(point) }), let word = hit.2,
            coach.plannedAyahs.contains(hit.1),
            !coach.revealedAyahs.contains(hit.1)
        else { return }
        UIImpactFeedbackGenerator(style: .light).impactOccurred()
        markWord?(hit.1, word)
        UIAccessibility.post(notification: .announcement, argument: "سُجّل التعثر في هذه الكلمة")
    }
}

/// The packaged SVG has four raster strips and an empty title panel. Compositing
/// those verified strips keeps the traditional engraved detail at native scale.
private enum QuranSurahArtwork {
    static let source: UIImage? = {
        guard let manifest = try? QuranResourceManifest.bundled(),
            let data = try? manifest.ornament(named: "surah-opening"),
            let svg = String(data: data, encoding: .utf8),
            let expression = try? NSRegularExpression(
                pattern:
                    #"<image x="([^"]+)" y="([^"]+)" width="([^"]+)" height="([^"]+)" href="data:image/png;base64,([^"]+)""#
            )
        else { return nil }
        let text = svg as NSString
        let matches = expression.matches(in: svg, range: NSRange(location: 0, length: text.length))
        guard matches.count == 4 else { return nil }
        let format = UIGraphicsImageRendererFormat(); format.scale = 2
        return UIGraphicsImageRenderer(size: CGSize(width: 541, height: 66), format: format).image { _ in
            for match in matches {
                guard let bytes = Data(base64Encoded: text.substring(with: match.range(at: 5))),
                    let image = UIImage(data: bytes)
                else { continue }
                let values = (1...4).map { Double(text.substring(with: match.range(at: $0))) ?? 0 }
                image.draw(in: CGRect(x: values[0], y: values[1], width: values[2], height: values[3]))
            }
        }
    }()

    static func image(ink: UIColor, gold: UIColor) -> UIImage? {
        guard let source = source?.cgImage else { return nil }
        let width = source.width, height = source.height
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        var dark = (CGFloat(0), CGFloat(0), CGFloat(0), CGFloat(0)), light = dark
        ink.getRed(&dark.0, green: &dark.1, blue: &dark.2, alpha: &dark.3)
        gold.getRed(&light.0, green: &light.1, blue: &light.2, alpha: &light.3)
        return pixels.withUnsafeMutableBytes { bytes -> UIImage? in
            guard
                let context = CGContext(
                    data: bytes.baseAddress, width: width, height: height, bitsPerComponent: 8, bytesPerRow: width * 4,
                    space: CGColorSpaceCreateDeviceRGB(),
                    bitmapInfo: CGBitmapInfo.byteOrder32Big.rawValue | CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            context.draw(source, in: CGRect(x: 0, y: 0, width: width, height: height))
            let values = bytes.bindMemory(to: UInt8.self)
            for offset in stride(from: 0, to: values.count, by: 4) {
                guard values[offset + 3] > 0 else { continue }
                let r = CGFloat(values[offset]) / 255, g = CGFloat(values[offset + 1]) / 255,
                    b = CGFloat(values[offset + 2]) / 255
                let luminance = 0.2126 * r + 0.7152 * g + 0.0722 * b
                let alpha = min(1, max(0, (0.82 - luminance) * 5)) * CGFloat(values[offset + 3]) / 255
                let tint = luminance < 0.4 || g > r ? dark : light
                values[offset] = UInt8((tint.0 * alpha * 255).rounded())
                values[offset + 1] = UInt8((tint.1 * alpha * 255).rounded())
                values[offset + 2] = UInt8((tint.2 * alpha * 255).rounded())
                values[offset + 3] = UInt8((alpha * 255).rounded())
            }
            return context.makeImage().map { UIImage(cgImage: $0, scale: 2, orientation: .up) }
        }
    }
}
