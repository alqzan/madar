import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

/// Owner, 21 Oct 2026: «ابيها اجمل وبالوان اجمل… لو الكتاب كبير وضح… لو فيه مجلدات كثير وضح… ذكي بعرض العنوان».
/// Each book wears its own leather (only `contrast.pairs` combinations), grows with its printed size,
/// stacks its volumes behind it, and shows the title without the edition noise Turath titles carry.
struct MihbaraBookShape: Codable, Equatable { var pages: Int?; var volumes: Int }

enum MihbaraBookCovers {
    /// Owner, 22 Oct 2026: twenty bindings modelled on known printed editions (`BookBindings`, contrast-tested).
    static func binding(_ index: Int) -> BookBindings.Binding {
        let all = BookBindings.all; return all[((index % all.count) + all.count) % all.count]
    }

    static func color(_ hex: UInt32) -> Color {
        Color(.sRGB, red: Double((hex >> 16) & 0xFF) / 255, green: Double((hex >> 8) & 0xFF) / 255, blue: Double(hex & 0xFF) / 255, opacity: 1)
    }

    /// Stable per book, and never the same binding twice in a row on one shelf.
    static func leatherIndices(for books: [MihbaraBook]) -> [UUID: Int] { BookBindings.indices(for: books.map(\.id)) }

    /// «رياض الصالحين - ت الرسالة الثاني» → («رياض الصالحين», «ت الرسالة الثاني»); «الداء والدواء = الجواب الكافي» keeps
    /// its alternative name as the subtitle. The full title stays in the accessibility label and the book card.
    static func split(_ title: String) -> (main: String, note: String?) {
        let parts = BookTitle.parts(title); return (parts.short, parts.note)
    }

    /// Height and page-block thickness from the printed size: a short epistle is slim, an encyclopedia is tall and thick.
    static func metrics(pages: Int?) -> (height: CGFloat, thickness: CGFloat) {
        guard let pages, pages > 0 else { return (148, 5) }
        let p = Double(pages)
        let height = 132 + min(36, 9 * log2(max(1, p / 60)))
        let thickness = 3 + min(13, 2.2 * log2(max(1, p / 40)))
        return (CGFloat(height), CGFloat(thickness))
    }

    /// The size in words the reader can picture.
    static func sizeWord(_ shape: MihbaraBookShape?, _ digits: MadarNumberFormatter) -> String? {
        guard let shape else { return nil }
        if shape.volumes > 1 { return arabicCount(shape.volumes, ["مجلد واحد", "مجلدان", "مجلدات", "مجلدًا"], digits) }
        guard let pages = shape.pages, pages > 0 else { return nil }
        return MihbaraCopy.pages(pages, digits)
    }
}

struct MihbaraBookCover: View {
    let book: MihbaraBook
    let shape: MihbaraBookShape?
    let leather: Int
    let digits: MadarNumberFormatter
    @Environment(\.roomTheme) private var theme

    var body: some View {
        let binding = MihbaraBookCovers.binding(leather)
        let fill = MihbaraBookCovers.color(binding.base), ink = MihbaraBookCovers.color(binding.ink)
        let metrics = MihbaraBookCovers.metrics(pages: shape?.pages.map { $0 / max(1, shape?.volumes ?? 1) } ?? book.pages)
        let title = MihbaraBookCovers.split(book.title)
        let volumes = min(max(shape?.volumes ?? 1, 1), 4)
        let width: CGFloat = 112
        ZStack(alignment: .bottomTrailing) {
            // Further volumes stand behind the first, each a little offset: the shelf shows a set, not one book.
            ForEach((1..<volumes).reversed(), id: \.self) { i in
                RoundedRectangle(cornerRadius: 7).fill(fill.opacity(1 - Double(i) * 0.16))
                    .frame(width: width, height: metrics.height)
                    .overlay { RoundedRectangle(cornerRadius: 7).stroke(ink.opacity(0.18), lineWidth: 0.8) }
                    .offset(x: -CGFloat(i) * 7, y: -CGFloat(i) * 3)
            }
            face(title: title, fill: fill, ink: ink, width: width, height: metrics.height)
                .overlay(alignment: .trailing) {
                    // The page block: thicker for longer books.
                    LinearGradient(colors: [theme.surface, theme.surface.opacity(0.82), theme.surface], startPoint: .top, endPoint: .bottom)
                        .frame(width: metrics.thickness, height: metrics.height - 8)
                        .overlay { VStack(spacing: 2.2) { ForEach(0..<Int(metrics.height / 4), id: \.self) { _ in Rectangle().fill(theme.ink.opacity(0.06)).frame(height: 0.5) } } }
                        .clipShape(.rect(bottomTrailingRadius: 2, topTrailingRadius: 2))
                        .offset(x: metrics.thickness - 1)
                        .accessibilityHidden(true)
                }
        }
        .padding(.leading, CGFloat(volumes - 1) * 7).padding(.trailing, metrics.thickness)
        .shadow(color: theme.ink.opacity(0.18), radius: 6, x: 0, y: 6)
    }

    private func face(title: (main: String, note: String?), fill: Color, ink: Color, width: CGFloat, height: CGFloat) -> some View {
        let size: CGFloat = title.main.count <= 10 ? 20 : title.main.count <= 20 ? 17 : 15
        return VStack(spacing: 6) {
            // A thin gilt frame, the room's ornament on every cover.
            Capsule().fill(ink.opacity(0.55)).frame(width: 26, height: 1.5).padding(.top, 2)
            Text(title.main).font(.custom("thmanyahserifdisplay-Bold", size: size, relativeTo: .headline))
                .multilineTextAlignment(.center).lineLimit(4).minimumScaleFactor(max(11 / size, 0.75))
            if let note = title.note {
                Text(note).font(MadarTypography.fine()).lineLimit(1).opacity(0.85)
            }
            Spacer(minLength: 0)
            if !book.author.isEmpty { Text(book.author).font(MadarTypography.fine()).lineLimit(1).opacity(0.9) }
            footer(ink: ink)
        }
        .foregroundStyle(ink)
        .padding(.horizontal, 10).padding(.vertical, 10)
        .frame(width: width, height: height)
        .background {
            ZStack {
                fill
                LinearGradient(colors: [.white.opacity(0.10), .clear, .black.opacity(0.12)], startPoint: .topLeading, endPoint: .bottomTrailing)
                RoundedRectangle(cornerRadius: 4).stroke(ink.opacity(0.28), lineWidth: 0.8).padding(5)
            }
        }
        .clipShape(.rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 8, topTrailingRadius: 8))
        .overlay(alignment: .leading) { Rectangle().fill(.black.opacity(0.18)).frame(width: 5).accessibilityHidden(true) }
    }

    @ViewBuilder private func footer(ink: Color) -> some View {
        if book.shelf == "reading", let p = book.progress, p > 0 {
            VStack(spacing: 3) {
                GeometryReader { g in
                    ZStack(alignment: .trailing) {
                        Capsule().fill(ink.opacity(0.22))
                        Capsule().fill(ink).frame(width: max(3, g.size.width * p))
                    }
                }.frame(height: 3)
                Text(digits.string(Int((p * 100).rounded())) + "٪").font(MadarTypography.fine())
            }
        } else if let size = MihbaraBookCovers.sizeWord(shape, digits) {
            Text(size).font(MadarTypography.fine()).lineLimit(1).opacity(0.9)
        }
    }
}

@MainActor extension AppMihbaraService {
    private static var shapeCacheURL: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("MihbaraBookShapes.json")
    }

    /// Printed pages and volumes for every book: a paper or PDF book already knows its pages; an EPUB is read
    /// once from its own page list and remembered by file hash (a derived cache, never a record).
    func bookShapes(_ books: [MihbaraBook]) async -> [UUID: MihbaraBookShape] {
        var cache = (try? JSONDecoder().decode([String: MihbaraBookShape].self, from: Data(contentsOf: Self.shapeCacheURL))) ?? [:]
        var result: [UUID: MihbaraBookShape] = [:], changed = false
        for book in books {
            #if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_FIXTURE"] == "bindings",
               let item = AppSession.bindingShelf.first(where: { $0.title == book.title }) {
                result[book.id] = .init(pages: item.pages, volumes: item.volumes); continue
            }
            #endif
            if !book.isReadableEPUB { result[book.id] = .init(pages: book.pages, volumes: 1); continue }
            guard let hash = book.fileHash else { continue }
            if let known = cache[hash] { result[book.id] = known; continue }
            guard let data = try? epubData(for: book) else { continue }
            let shape = await Task.detached(priority: .utility) { () -> MihbaraBookShape? in
                let file = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".epub")
                defer { try? FileManager.default.removeItem(at: file) }
                guard (try? data.write(to: file, options: .completeFileProtection)) != nil else { return nil }
                return (try? EPUBBookFiles.printedShape(file: file)).flatMap { $0 }.map { MihbaraBookShape(pages: $0.pages, volumes: $0.volumes) }
                    ?? MihbaraBookShape(pages: nil, volumes: 1)
            }.value
            if let shape { cache[hash] = shape; result[book.id] = shape; changed = true }
        }
        if changed, let encoded = try? JSONEncoder().encode(cache) { try? encoded.write(to: Self.shapeCacheURL, options: [.atomic, .completeFileProtection]) }
        return result
    }
}

/// Owner, 21 Oct 2026: «ابيه كأنه واقعي». A real shelf shows spines: each book stands upright, as thick as its
/// printed pages, a set shows each of its volumes numbered, and the title runs down the spine between gilt bands.
struct MihbaraBookSpine: View {
    let book: MihbaraBook
    let shape: MihbaraBookShape?
    let leather: Int
    let digits: MadarNumberFormatter
    /// Zero-based volume of a set; nil for a single book.
    var volume: Int? = nil
    /// How many volumes of the set stand side by side; the title is spread across them.
    var volumeCount: Int? = nil
    /// A finished book lying on its side keeps its title along the length.
    var lying = false
    @Environment(\.roomTheme) private var theme

    /// The gap between the volumes of a set on the shelf.
    static let volumeGap: CGFloat = 1

    static func size(pagesPerVolume pages: Int?) -> CGSize {
        guard let pages, pages > 0 else { return .init(width: 44, height: 162) }
        let p = Double(pages)
        return .init(width: 40 + min(22, 4.6 * log2(max(1, p / 50))), height: 148 + min(36, 8.5 * log2(max(1, p / 60))))
    }

    /// A volume of a set is a big printed volume: wider and taller than a single book, room for its ornament.
    static func volumeSize(_ single: CGSize) -> CGSize { CGSize(width: max(58, single.width * 1.3), height: max(246, single.height + 66)) }

    private struct Palette { let fill, shade, ink, accent, accentInk: Color; let binding: BookBindings.Binding }

    var body: some View {
        let b = MihbaraBookCovers.binding(leather)
        let c = Palette(fill: MihbaraBookCovers.color(b.base), shade: MihbaraBookCovers.color(b.shade), ink: MihbaraBookCovers.color(b.ink),
                        accent: MihbaraBookCovers.color(b.accent), accentInk: MihbaraBookCovers.color(b.accentInk), binding: b)
        let perVolume = shape?.pages.map { $0 / max(1, shape?.volumes ?? 1) } ?? book.pages
        let single = Self.size(pagesPerVolume: perVolume)
        // A volume of a set is a big printed volume: wider and a little taller than a single book.
        let size = volume == nil || lying ? single : Self.volumeSize(single)
        let parts = BookTitle.parts(book.title)
        ZStack {
            // Rounded leather or cloth: the darker shade at both edges, a soft highlight a third of the way in.
            LinearGradient(stops: [.init(color: c.shade, location: 0), .init(color: c.fill, location: 0.22),
                                   .init(color: c.fill, location: 0.7), .init(color: c.shade, location: 1)], startPoint: .leading, endPoint: .trailing)
            LinearGradient(stops: [.init(color: .clear, location: 0.2), .init(color: .white.opacity(0.13), location: 0.36), .init(color: .clear, location: 0.55)],
                           startPoint: .leading, endPoint: .trailing)
            decoration(c, size: size)
            if let volume, !lying {
                volumeSpine(parts, volume: volume, c: c, size: size)
            } else {
                singleSpine(parts, c: c, size: size)
            }
        }
        .frame(width: size.width, height: size.height)
        .clipShape(.rect(topLeadingRadius: 3, bottomLeadingRadius: 2, bottomTrailingRadius: 2, topTrailingRadius: 3))
        .overlay(alignment: .top) {
            // A reading ribbon hangs from the book you are in.
            if book.shelf == "reading", (book.progress ?? 0) > 0, volume == nil || volume == 0 {
                Rectangle().fill(theme.color("ribbonRead")).frame(width: 6, height: 20).offset(x: size.width / 4, y: -8)
                    .accessibilityHidden(true)
            }
        }
        .shadow(color: .black.opacity(0.22), radius: 1.5, x: 1, y: 0)
    }

    /// Each binding's gilt motif, chosen with its ornament so no two neighbours look alike.
    private func motif(_ b: BookBindings.Binding) -> MihbaraMotif {
        switch b.ornament {
        case .goldBands: .roundel; case .lozengeBand: .lozenge; case .arabesqueHead: .almond; case .raisedRibs: .fleuron
        case .titlePanel: .rosette; case .twoTone: .star; case .stripedBands: .lozenge; case .plainModern: .roundel
        case .geometricStar: .star; case .dottedBorder: .rosette
        }
    }

    /// Head and foot space a binding's ornament takes, so text never sits on a band.
    private func margin(_ o: BookBindings.Ornament) -> CGFloat {
        switch o { case .twoTone: 34; case .stripedBands: 30; case .raisedRibs, .arabesqueHead: 26; case .plainModern: 12; default: 16 }
    }

    /// Ornament drawn across the whole spine, under the text.
    @ViewBuilder private func decoration(_ c: Palette, size: CGSize) -> some View {
        switch c.binding.ornament {
        case .twoTone:
            VStack(spacing: 0) {
                c.accent.frame(height: 28); c.ink.opacity(0.8).frame(height: 1)
                Spacer(minLength: 0)
                c.ink.opacity(0.8).frame(height: 1); c.accent.frame(height: 28)
            }.accessibilityHidden(true)
        case .stripedBands:
            VStack(spacing: 0) {
                Spacer().frame(height: 12); c.accent.frame(height: 10)
                Spacer(minLength: 0)
                c.accent.frame(height: 10); Spacer().frame(height: 12)
            }.accessibilityHidden(true)
        case .dottedBorder:
            RoundedRectangle(cornerRadius: 2).stroke(c.ink.opacity(0.75), style: StrokeStyle(lineWidth: 1.2, dash: [0.1, 3.2], dashPhase: 0))
                .padding(4).accessibilityHidden(true)
        case .raisedRibs:
            VStack(spacing: 0) {
                ribs(c).padding(.top, 6)
                Spacer(minLength: 0)
                ribs(c).padding(.bottom, 6)
            }.accessibilityHidden(true)
        default: EmptyView()
        }
    }

    private func ribs(_ c: Palette) -> some View {
        VStack(spacing: 4) {
            ForEach(0..<2, id: \.self) { _ in
                LinearGradient(colors: [c.shade, .white.opacity(0.22), c.shade], startPoint: .top, endPoint: .bottom)
                    .frame(height: 5).overlay(alignment: .top) { c.ink.opacity(0.55).frame(height: 0.6) }
            }
        }
    }

    /// The small ornament at head or foot for bindings whose decoration is not drawn across the spine.
    @ViewBuilder private func cap(_ c: Palette, foot: Bool) -> some View {
        switch c.binding.ornament {
        case .goldBands, .titlePanel, .geometricStar:
            VStack(spacing: 2.5) { Rectangle().frame(height: 1.2); Rectangle().frame(height: 0.6) }
                .rotationEffect(.degrees(foot ? 180 : 0)).opacity(0.75).padding(.horizontal, 4).foregroundStyle(c.ink)
        case .lozengeBand:
            VStack(spacing: 2) {
                Rectangle().frame(height: 1)
                HStack(spacing: 3) { ForEach(0..<5, id: \.self) { _ in Rectangle().frame(width: 4, height: 4).rotationEffect(.degrees(45)) } }.frame(height: 7)
                Rectangle().frame(height: 1)
            }.opacity(0.75).padding(.horizontal, 5).foregroundStyle(c.ink)
        case .arabesqueHead:
            MihbaraArch().stroke(c.ink.opacity(0.8), lineWidth: 1.1)
                .overlay { MihbaraArch().stroke(c.ink.opacity(0.4), lineWidth: 0.6).padding(3) }
                .frame(height: 18).padding(.horizontal, 6).rotationEffect(.degrees(foot ? 180 : 0))
        default: EmptyView()
        }
    }

    /// A single book: the title down the spine (or across it on a short modern cover), the binding's caps around it.
    private func singleSpine(_ parts: BookTitle.Parts, c: Palette, size: CGSize) -> some View {
        let o = c.binding.ornament, m = margin(o)
        let across = c.binding.acrossWhenShort && !lying && parts.short.count <= 12
        let titleInk = o == .titlePanel ? c.accentInk : c.ink
        let footInk = o == .twoTone ? c.accentInk : c.ink
        let titleHeight = size.height - m * 2 - 30
        return VStack(spacing: 0) {
            ZStack(alignment: .top) { Color.clear; cap(c, foot: false).padding(.top, o == .arabesqueHead ? 5 : 10) }.frame(height: m)
            Group {
                if across {
                    Text(parts.short.split(separator: " ").joined(separator: "\n"))
                        .font(.custom("thmanyahserifdisplay-Bold", size: 14, relativeTo: .caption)).multilineTextAlignment(.center)
                        .lineLimit(3).minimumScaleFactor(11 / 14).padding(.horizontal, 3)
                        .frame(width: size.width, height: titleHeight, alignment: .top).padding(.top, 8)
                } else {
                    Text(parts.short)
                        .font(.custom("thmanyahserifdisplay-Bold", size: 15, relativeTo: .caption))
                        .lineLimit(size.width < 48 ? 1 : 2).minimumScaleFactor(11 / 15).multilineTextAlignment(.center)
                        .frame(width: titleHeight - 8, height: size.width - 14)
                        .rotationEffect(.degrees(90))
                        .frame(width: size.width - 10, height: titleHeight)
                }
            }
            .foregroundStyle(titleInk)
            .background {
                if o == .titlePanel {
                    RoundedRectangle(cornerRadius: 2).fill(c.accent).overlay { RoundedRectangle(cornerRadius: 2).stroke(c.ink.opacity(0.7), lineWidth: 0.8).padding(1.5) }
                        .padding(.horizontal, 5).padding(.vertical, 2)
                }
            }
            Spacer(minLength: 0)
            if o != .plainModern || !across {
                MihbaraMotifShape(motif: motif(c.binding)).stroke(c.ink.opacity(0.85), lineWidth: 0.9)
                    .frame(width: min(20, size.width - 18), height: min(20, size.width - 18)).padding(.bottom, 3).accessibilityHidden(true)
            }
            Text(footer).font(MadarTypography.fine()).lineLimit(1).minimumScaleFactor(1).frame(height: 18).foregroundStyle(footInk)
                .padding(.bottom, o == .twoTone ? 6 : 0)
            ZStack(alignment: .bottom) { Color.clear; cap(c, foot: true).padding(.bottom, o == .arabesqueHead ? 5 : 8) }.frame(height: o == .twoTone ? 4 : m - 6)
        }
        .foregroundStyle(c.ink)
    }

    /// Owner, 22 Oct 2026, of the printed «زاد المعاد» set: «زا في مجلد ثم د في مجلد… الكتابه متفرقه بين المجلدات بشكل افقي
    /// والكتب عموديه». The volumes stand upright and the name runs once, large and horizontal, across all of them: each
    /// spine carries its slice of the letters, inside the binding's ornament, with the volume number in a medallion.
    private func volumeSpine(_ parts: BookTitle.Parts, volume: Int, c: Palette, size: CGSize) -> some View {
        let o = c.binding.ornament, m = margin(o)
        let count = max(1, volumeCount ?? 1), gap = Self.volumeGap
        let total = CGFloat(count) * size.width + CGFloat(count - 1) * gap
        // Volume 1 stands rightmost, where an Arabic title starts; measure from the left edge of the whole set.
        let fromLeft = CGFloat(count - 1 - volume) * (size.width + gap)
        let rest = parts.main.count > parts.short.count ? String(parts.main.dropFirst(parts.short.count)).trimmingCharacters(in: .whitespaces) : ""
        let titleInk = o == .titlePanel ? c.accentInk : c.ink
        // The name fills the whole set, so it begins on volume 1 even in a long set.
        let titleSize = min(76, max(34, total * 1.6 / CGFloat(max(4, parts.short.count))))
        return VStack(spacing: 8) {
            ZStack(alignment: .top) { Color.clear; cap(c, foot: false).padding(.top, o == .arabesqueHead ? 5 : 8) }.frame(height: m)
            if o != .plainModern {
                MihbaraLattice(ink: c.ink).frame(height: 22).padding(.horizontal, 8)
                    .overlay { MihbaraMotifShape(motif: motif(c.binding)).fill(c.fill).overlay { MihbaraMotifShape(motif: motif(c.binding)).stroke(c.ink, lineWidth: 0.9) }.frame(width: 18, height: 18) }
            }
            VStack(spacing: 4) {
                // Words spread over the whole set, the first on volume 1 and the last on the last volume.
                let words = parts.short.split(separator: " ").map(String.init)
                HStack(spacing: 0) {
                    ForEach(Array(words.enumerated()), id: \.offset) { i, word in
                        if i > 0 { Spacer(minLength: 10) }
                        Text(word).font(.custom("thmanyahserifdisplay-Bold", size: titleSize, relativeTo: .title))
                            .lineLimit(1).minimumScaleFactor(13 / titleSize)
                    }
                }
                .padding(.horizontal, count > 2 ? size.width * 0.3 : 0)
                .environment(\.layoutDirection, .rightToLeft)
                if !rest.isEmpty {
                    Text(rest).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .caption)).lineLimit(1).minimumScaleFactor(0.66)
                }
            }
            .foregroundStyle(titleInk)
            .padding(.horizontal, 10)
            .frame(width: total, height: 104)
            .offset(x: -fromLeft)
            .frame(width: size.width, height: 104, alignment: .leading)
            .clipped()
            .environment(\.layoutDirection, .leftToRight)
            .background { if o == .titlePanel { c.accent.padding(.vertical, -4) } }
            .overlay { Rectangle().stroke(c.ink.opacity(0.6), lineWidth: 0.8).padding(.vertical, -4).padding(.horizontal, 2) }
            .accessibilityHidden(true)
            Spacer(minLength: 0)
            ZStack {
                if o == .geometricStar { MihbaraStar().stroke(c.ink.opacity(0.85), lineWidth: 1).frame(width: 34, height: 34) }
                else { Circle().stroke(c.ink.opacity(0.8), lineWidth: 1).frame(width: 26, height: 26)
                    Circle().stroke(c.ink.opacity(0.35), lineWidth: 0.6).frame(width: 32, height: 32) }
                Text(digits.string(volume + 1)).font(MadarTypography.caption().weight(.bold))
            }
            if o != .plainModern {
                HStack(spacing: 6) {
                    ForEach(0..<2, id: \.self) { _ in MihbaraMotifShape(motif: .fleuron).stroke(c.ink.opacity(0.7), lineWidth: 0.7).frame(width: 9, height: 9) }
                }.accessibilityHidden(true)
            }
            ZStack(alignment: .bottom) { Color.clear; cap(c, foot: true).padding(.bottom, o == .arabesqueHead ? 5 : 8) }.frame(height: m)
        }
        .foregroundStyle(c.ink)
    }

    private var footer: String {
        if let volume { return "ج " + digits.string(volume + 1) }
        if book.shelf == "reading", let p = book.progress, p > 0 { return digits.string(Int((p * 100).rounded())) + "٪" }
        return ""
    }
}

/// Owner, 22 Oct 2026: «ابي فيها اشكال جماليه بالكتب… مهب بس الاسم». The gilt motifs printed bindings carry.
enum MihbaraMotif { case rosette, almond, star, lozenge, roundel, fleuron }

struct MihbaraMotifShape: Shape {
    let motif: MihbaraMotif
    func path(in r: CGRect) -> Path {
        var p = Path()
        let c = CGPoint(x: r.midX, y: r.midY), rad = min(r.width, r.height) / 2
        switch motif {
        case .rosette:
            // Eight petals round a small centre.
            for i in 0..<8 {
                let a = Double(i) * .pi / 4
                let petal = Path(ellipseIn: CGRect(x: -rad * 0.22, y: -rad, width: rad * 0.44, height: rad))
                p.addPath(petal.applying(CGAffineTransform(rotationAngle: a).concatenating(CGAffineTransform(translationX: c.x, y: c.y))))
            }
            p.addEllipse(in: CGRect(x: c.x - rad * 0.18, y: c.y - rad * 0.18, width: rad * 0.36, height: rad * 0.36))
        case .almond:
            // A pointed oval (shamsa) with an inner one.
            for k in [1.0, 0.62] {
                let h = r.height / 2 * k, w = r.width / 2 * k
                p.move(to: CGPoint(x: c.x, y: c.y - h))
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y + h), control: CGPoint(x: c.x + w * 2, y: c.y))
                p.addQuadCurve(to: CGPoint(x: c.x, y: c.y - h), control: CGPoint(x: c.x - w * 2, y: c.y))
            }
        case .star:
            p.addPath(MihbaraStar().path(in: r))
            p.addEllipse(in: r.insetBy(dx: r.width * 0.36, dy: r.height * 0.36))
        case .lozenge:
            for k in [1.0, 0.55] {
                let h = r.height / 2 * k, w = r.width / 2 * k
                p.move(to: CGPoint(x: c.x, y: c.y - h)); p.addLine(to: CGPoint(x: c.x + w, y: c.y))
                p.addLine(to: CGPoint(x: c.x, y: c.y + h)); p.addLine(to: CGPoint(x: c.x - w, y: c.y)); p.closeSubpath()
            }
        case .roundel:
            p.addEllipse(in: r.insetBy(dx: (r.width - rad * 2) / 2, dy: (r.height - rad * 2) / 2))
            p.addEllipse(in: CGRect(x: c.x - rad * 0.6, y: c.y - rad * 0.6, width: rad * 1.2, height: rad * 1.2))
            for i in 0..<12 {
                let a = Double(i) * .pi / 6
                p.move(to: CGPoint(x: c.x + cos(a) * rad * 0.6, y: c.y + sin(a) * rad * 0.6))
                p.addLine(to: CGPoint(x: c.x + cos(a) * rad, y: c.y + sin(a) * rad))
            }
        case .fleuron:
            // A three-lobed leaf on a stem.
            p.addEllipse(in: CGRect(x: c.x - rad * 0.3, y: r.minY, width: rad * 0.6, height: rad * 0.9))
            p.addEllipse(in: CGRect(x: r.minX, y: c.y - rad * 0.35, width: rad * 0.9, height: rad * 0.6))
            p.addEllipse(in: CGRect(x: r.maxX - rad * 0.9, y: c.y - rad * 0.35, width: rad * 0.9, height: rad * 0.6))
            p.move(to: CGPoint(x: c.x, y: c.y)); p.addLine(to: CGPoint(x: c.x, y: r.maxY))
        }
        return p
    }
}

/// A gilt lattice of small lozenges filling a framed panel, as on the head and foot of printed sets.
struct MihbaraLattice: View {
    let ink: Color
    var body: some View {
        Canvas { context, size in
            let step: CGFloat = 8
            var path = Path()
            var y: CGFloat = 0, row = 0
            while y <= size.height {
                var x: CGFloat = row % 2 == 0 ? 0 : step / 2
                while x <= size.width {
                    path.move(to: CGPoint(x: x, y: y - 2.6)); path.addLine(to: CGPoint(x: x + 2.6, y: y))
                    path.addLine(to: CGPoint(x: x, y: y + 2.6)); path.addLine(to: CGPoint(x: x - 2.6, y: y)); path.closeSubpath()
                    x += step
                }
                y += step / 2; row += 1
            }
            context.stroke(path, with: .color(ink.opacity(0.55)), lineWidth: 0.7)
        }
        .overlay { Rectangle().stroke(ink.opacity(0.75), lineWidth: 0.9) }
        .overlay { Rectangle().stroke(ink.opacity(0.35), lineWidth: 0.6).padding(-2.5) }
        .accessibilityHidden(true)
    }
}

/// A pointed arch, as at the head of classical and Mushaf bindings.
struct MihbaraArch: Shape {
    func path(in r: CGRect) -> Path {
        var p = Path()
        p.move(to: CGPoint(x: r.minX, y: r.maxY))
        p.addLine(to: CGPoint(x: r.minX, y: r.midY))
        p.addQuadCurve(to: CGPoint(x: r.midX, y: r.minY), control: CGPoint(x: r.minX, y: r.minY + r.height * 0.1))
        p.addQuadCurve(to: CGPoint(x: r.maxX, y: r.midY), control: CGPoint(x: r.maxX, y: r.minY + r.height * 0.1))
        p.addLine(to: CGPoint(x: r.maxX, y: r.maxY))
        return p
    }
}

/// An eight-point star: two squares, one turned by 45°.
struct MihbaraStar: Shape {
    func path(in r: CGRect) -> Path {
        let side = min(r.width, r.height) / 1.414, square = CGRect(x: r.midX - side / 2, y: r.midY - side / 2, width: side, height: side)
        var p = Path(square)
        p.addPath(Path(square).applying(CGAffineTransform(translationX: r.midX, y: r.midY).rotated(by: .pi / 4).translatedBy(x: -r.midX, y: -r.midY)))
        return p
    }
}

/// The plank books stand on: a lit top surface, a darker front edge, and the shadow the books cast on the wall.
struct MihbaraShelfPlank: View {
    @Environment(\.roomTheme) private var theme
    var body: some View {
        VStack(spacing: 0) {
            LinearGradient(colors: [theme.color("wood").opacity(0.75), theme.color("wood")], startPoint: .top, endPoint: .bottom).frame(height: 7)
            LinearGradient(colors: [theme.color("wood"), .black.opacity(0.35)], startPoint: .top, endPoint: .bottom)
                .background(theme.color("wood")).frame(height: 10)
        }
        .shadow(color: theme.ink.opacity(0.22), radius: 6, y: 6)
        .accessibilityHidden(true)
    }
}
