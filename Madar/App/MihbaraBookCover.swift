import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

/// Owner, 21 Oct 2026: «ابيها اجمل وبالوان اجمل… لو الكتاب كبير وضح… لو فيه مجلدات كثير وضح… ذكي بعرض العنوان».
/// Each book wears its own leather (only `contrast.pairs` combinations), grows with its printed size,
/// stacks its volumes behind it, and shows the title without the edition noise Turath titles carry.
struct MihbaraBookShape: Codable, Equatable { var pages: Int?; var volumes: Int }

enum MihbaraBookCovers {
    /// (cover, ink) pairs approved in design-tokens `contrast.pairs` for small text.
    static let leathers: [(fill: String, ink: String)] = [
        ("navy", "onNavy"), ("sunnahLeather", "goldInk"), ("ribbonRead", "surface"),
        ("desk", "onDesk"), ("goldUnderstand", "ink"), ("accent", "onAccent")
    ]

    /// Stable per book, and never the same leather twice in a row on one shelf.
    static func leatherIndices(for books: [MihbaraBook]) -> [UUID: Int] {
        var result: [UUID: Int] = [:], previous = -1
        for book in books {
            var index = stableHash(book.id.uuidString) % leathers.count
            if index == previous { index = (index + 1) % leathers.count }
            result[book.id] = index; previous = index
        }
        return result
    }

    private static func stableHash(_ text: String) -> Int {
        var h: UInt64 = 1469598103934665603
        for byte in text.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
        return Int(h % 1_000_003)
    }

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
        let pair = MihbaraBookCovers.leathers[leather % MihbaraBookCovers.leathers.count]
        let fill = theme.color(pair.fill), ink = theme.color(pair.ink)
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
    @Environment(\.roomTheme) private var theme

    static func size(pagesPerVolume pages: Int?) -> CGSize {
        guard let pages, pages > 0 else { return .init(width: 34, height: 162) }
        let p = Double(pages)
        return .init(width: 24 + min(26, 5.5 * log2(max(1, p / 50))), height: 148 + min(36, 8.5 * log2(max(1, p / 60))))
    }

    var body: some View {
        let pair = MihbaraBookCovers.leathers[leather % MihbaraBookCovers.leathers.count]
        let fill = theme.color(pair.fill), ink = theme.color(pair.ink)
        let perVolume = shape?.pages.map { $0 / max(1, shape?.volumes ?? 1) } ?? book.pages
        let size = Self.size(pagesPerVolume: perVolume)
        let title = MihbaraBookCovers.split(book.title).main
        ZStack {
            // Rounded leather: dark at both edges, a soft highlight a third of the way in.
            LinearGradient(stops: [.init(color: .black.opacity(0.30), location: 0), .init(color: .clear, location: 0.18),
                                   .init(color: .white.opacity(0.16), location: 0.36), .init(color: .clear, location: 0.6),
                                   .init(color: .black.opacity(0.34), location: 1)], startPoint: .leading, endPoint: .trailing)
                .background(fill)
            VStack(spacing: 0) {
                bands(ink).padding(.top, 12)
                Text(title)
                    .font(.custom("thmanyahserifdisplay-Bold", size: size.width < 32 ? 13 : 15, relativeTo: .caption))
                    .lineLimit(size.width < 40 ? 1 : 2).minimumScaleFactor(size.width < 32 ? 1 : 11 / 15).multilineTextAlignment(.center)
                    .frame(width: size.height - 72, height: size.width - 6)
                    .rotationEffect(.degrees(90))
                    .frame(width: size.width, height: size.height - 72)
                Spacer(minLength: 0)
                bands(ink)
                // A set's volume number sits on a gilt label, as on a printed multi-volume set.
                if volume != nil {
                    Text(footer).font(MadarTypography.fine().weight(.semibold)).lineLimit(1).fixedSize()
                        .padding(.horizontal, 3).frame(minWidth: 22, minHeight: 20)
                        .background(theme.color("goldUnderstand"), in: .rect(cornerRadius: 2)).foregroundStyle(theme.color("ink"))
                        .padding(.vertical, 6)
                } else {
                    Text(footer).font(MadarTypography.fine()).lineLimit(1).minimumScaleFactor(1).frame(height: 22).padding(.bottom, 6)
                }
            }
            .foregroundStyle(ink)
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

    private var footer: String {
        if let volume { return "ج " + digits.string(volume + 1) }
        if book.shelf == "reading", let p = book.progress, p > 0 { return digits.string(Int((p * 100).rounded())) + "٪" }
        return ""
    }

    private func bands(_ ink: Color) -> some View {
        VStack(spacing: 2.5) { Rectangle().frame(height: 1.2); Rectangle().frame(height: 0.6) }.opacity(0.55).padding(.horizontal, 4)
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
