import SwiftUI
import ReadiumShared
import MadarDesign

struct MihbaraContentsSheet: View {
    @Environment(\.dismiss) private var dismiss
    let publication: Publication?
    let palette: MihbaraReaderPalette
    var current: Locator? = nil
    let select: (ReadiumShared.Link) -> Void

    private var items: [MihbaraTOCItem] { Self.flatten(publication?.manifest.tableOfContents ?? []) }

    /// The chapter the reader is in: the last entry whose file is at or before the current file. When several
    /// entries share that file the sheet can't tell which one the reader is in, so it marks none rather than guess.
    private var currentItem: MihbaraTOCItem? {
        guard let publication, let current else { return nil }
        let base = publication.baseURL
        var spineByFile: [String: Int] = [:]
        for (index, link) in publication.readingOrder.enumerated() {
            let key = link.url(relativeTo: base).removingFragment().string
            if spineByFile[key] == nil { spineByFile[key] = index }
        }
        guard let here = spineByFile[current.href.removingFragment().string]
            ?? publication.readingOrder.firstIndex(where: { $0.url(relativeTo: base).removingFragment().isEquivalentTo(current.href.removingFragment()) })
        else { return nil }
        let placed: [(item: MihbaraTOCItem, spine: Int)] = items.compactMap { item in
            spineByFile[item.link.url(relativeTo: base).removingFragment().string].map { (item: item, spine: $0) }
        }.filter { $0.spine <= here }
        guard let nearest = placed.map(\.spine).max() else { return nil }
        let candidates = placed.filter { $0.spine == nearest }
        if candidates.count == 1 { return candidates[0].item }
        let fragments = current.locations.fragments
        return candidates.first { entry in
            entry.item.link.url(relativeTo: base).fragment.map { fragments.contains($0) } ?? false
        }?.item
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("فهرس الكتاب").font(.custom("thmanyahserifdisplay-Bold", size: 22, relativeTo: .title2))
                Spacer()
                Button { dismiss() } label: { Text("تمّ").font(MadarTypography.caption()).frame(minWidth: 44, minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("mihbara-reader-contents-close")
            }
            if items.isEmpty {
                Text("لا يتضمن هذا الكتاب فهرسًا").font(MadarTypography.body()).foregroundStyle(palette.ink2)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                let currentID = currentItem?.id
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(spacing: 0) {
                            ForEach(items) { item in
                                let here = item.id == currentID
                                Button { select(item.link) } label: {
                                    HStack(spacing: 10) {
                                        Text(item.link.title ?? "موضع في الكتاب").font(here ? MadarTypography.body().weight(.bold) : MadarTypography.body()).lineLimit(2)
                                        Spacer(minLength: 12)
                                        if here { Text("أنت هنا").font(MadarTypography.fine()).foregroundStyle(palette.ink2) }
                                        Image(systemName: "chevron.left").font(.system(size: 11, weight: .medium)).foregroundStyle(palette.ink2)
                                    }
                                    .padding(.leading, CGFloat(item.depth) * 18)
                                    .padding(.vertical, 12)
                                    .background(here ? palette.line.opacity(0.35) : .clear)
                                    .contentShape(Rectangle())
                                }
                                .buttonStyle(.plain)
                                .id(item.id)
                                .accessibilityAddTraits(here ? .isSelected : [])
                                .accessibilityIdentifier("mihbara-reader-toc-" + item.id)
                                Rectangle().fill(palette.line).frame(height: 1)
                            }
                        }
                    }
                    .onAppear { if let currentID { proxy.scrollTo(currentID, anchor: .center) } }
                }
            }
        }
        .padding(20)
        .foregroundStyle(palette.ink)
        .tint(palette.accent)
        .background(palette.bg.ignoresSafeArea())
        .presentationDetents([.medium, .large])
    }

    private static func flatten(_ links: [ReadiumShared.Link]) -> [MihbaraTOCItem] {
        func walk(_ links: [ReadiumShared.Link], _ depth: Int) -> [(link: ReadiumShared.Link, depth: Int)] {
            links.flatMap { [(link: $0, depth: depth)] + walk($0.children, depth + 1) }
        }
        return walk(links, 0).enumerated().map { MihbaraTOCItem(link: $1.link, depth: $1.depth, order: $0) }
    }
}

private struct MihbaraTOCItem: Identifiable {
    let link: ReadiumShared.Link
    let depth: Int
    /// Position in the index: several entries can open the same page (a scanned book's printed contents),
    /// and an id made from the link alone made SwiftUI repeat one entry's title in their place.
    let order: Int
    var id: String { "\(order)" }
}

