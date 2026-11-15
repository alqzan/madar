import AppKit
import SwiftUI
import MadarDesign

struct MacMihbaraQuoteCardSheet: View {
    let card: MihbaraQuoteCardContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var quote: String
    @State private var extras: Set<MihbaraQuoteExtra> = []
    @State private var error: String?

    init(card: MihbaraQuoteCardContent) {
        self.card = card
        _quote = State(initialValue: card.quote)
    }

    private var trimmedQuote: String { quote.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var artwork: MihbaraQuoteCardArtwork { .init(card: card, quote: trimmedQuote, extras: extras) }
    private var offeredExtras: [MihbaraQuoteExtra] {
        MihbaraQuoteExtra.allCases.filter { extra in
            switch extra {
            case .author: !card.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .location: card.location != nil
            default: true
            }
        }
    }

    var body: some View {
        VStack(spacing: 14) {
            HStack {
                Button("تمّ") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Text("بطاقة اقتباس").font(MadarTypography.section())
                Spacer()
                Button { share() } label: { Label("مشاركة", systemImage: "square.and.arrow.up") }
                    .disabled(trimmedQuote.isEmpty)
            }
            ScrollView {
                VStack(spacing: 16) {
                    GeometryReader { proxy in
                        artwork
                            .scaleEffect(proxy.size.width / MihbaraQuoteCardArtwork.size.width)
                            .frame(width: proxy.size.width,
                                   height: proxy.size.width * MihbaraQuoteCardArtwork.size.height / MihbaraQuoteCardArtwork.size.width)
                            .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
                    }
                    .aspectRatio(MihbaraQuoteCardArtwork.size.width / MihbaraQuoteCardArtwork.size.height, contentMode: .fit)
                    .frame(maxWidth: 320)

                    VStack(alignment: .leading, spacing: 8) {
                        HStack {
                            Text("النص").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Spacer()
                            if quote != card.quote { Button("أعد النص كما في الكتاب") { quote = card.quote } }
                        }
                        TextEditor(text: $quote)
                            .font(.custom("Amiri", size: 18, relativeTo: .body))
                            .lineSpacing(5).frame(minHeight: 100, maxHeight: 180)
                            .scrollContentBackground(.hidden)
                            .padding(8).background(theme.surface, in: .rect(cornerRadius: 14))
                        Text(trimmedQuote.isEmpty ? "اكتب ما تريد أن يبقى من الفقرة." : "اختصر النص أو أضف إليه؛ البطاقة تتبعك.")
                            .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    .frame(maxWidth: 520)

                    VStack(alignment: .leading, spacing: 8) {
                        Text("أضف إلى البطاقة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        HStack(spacing: 8) {
                            ForEach(offeredExtras) { extra in
                                let selected = extras.contains(extra)
                                Button {
                                    if selected { extras.remove(extra) } else { extras.insert(extra) }
                                } label: {
                                    Label(extra.title, systemImage: selected ? "checkmark" : "plus")
                                        .padding(.horizontal, 12).frame(minHeight: 38)
                                }
                                .buttonStyle(.bordered)
                                .tint(selected ? theme.ink : theme.secondaryInk)
                            }
                        }
                    }
                    .frame(maxWidth: 520, alignment: .leading)
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
            }
        }
        .padding(18).frame(minWidth: 620, minHeight: 720)
        .foregroundStyle(theme.ink).background(theme.background)
        .environment(\.layoutDirection, .rightToLeft)
        .alert("بطاقة اقتباس", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) {
            Button("حسنًا", role: .cancel) { error = nil }
        } message: { Text(error ?? "") }
    }

    private func share() {
        guard let image = renderImage() else { error = "تعذّر إنشاء صورة البطاقة."; return }
        var items: [Any] = [image]
        if extras.contains(.source), let sourceURL = card.sourceURL { items.append(sourceURL) }
        guard let view = NSApp.keyWindow?.contentView else { error = "افتح البطاقة داخل نافذة مدار ثم أعد المحاولة."; return }
        let picker = NSSharingServicePicker(items: items)
        picker.show(relativeTo: NSRect(x: view.bounds.midX, y: view.bounds.midY, width: 1, height: 1), of: view, preferredEdge: .minY)
    }

    private func renderImage() -> NSImage? {
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 2
        return renderer.nsImage
    }
}
