import SwiftUI
import MadarDesign

struct MihbaraQuoteCardArtwork: View {
    static let size = CGSize(width: 1080, height: 1350)
    let card: MihbaraQuoteCardContent
    let quote: String
    let extras: Set<MihbaraQuoteExtra>
    private let theme = RoomTheme(room: "mihbara")
    private var forest: SwiftUI.Color { theme.accentFill }
    private var paper: SwiftUI.Color { theme.surface }
    private var ink: SwiftUI.Color { theme.ink }
    private var muted: SwiftUI.Color { theme.secondaryInk }
    private var gold: SwiftUI.Color { theme.color("goldUnderstand") }
    private var goldText: SwiftUI.Color { theme.color("goldUnderstandText") }

    private var displayedQuote: String {
        guard quote.count > 520 else { return quote }
        return String(quote.prefix(519)).trimmingCharacters(in: .whitespacesAndNewlines) + "…"
    }
    private var quoteSize: CGFloat {
        if displayedQuote.count > 360 { hasCitation ? 35 : 39 }
        else if displayedQuote.count > 240 { hasCitation ? 41 : 46 }
        else if displayedQuote.count > 150 { hasCitation ? 47 : 52 }
        else if displayedQuote.count > 60 { 55 }
        else { 66 }
    }
    private var hasCitation: Bool {
        !extras.isDisjoint(with: [.book, .author, .location, .source])
    }

    var body: some View {
        ZStack {
            forest
            RoundedRectangle(cornerRadius: 54, style: .continuous).fill(paper).padding(28)
            RoundedRectangle(cornerRadius: 44, style: .continuous)
                .stroke(gold.opacity(0.78), lineWidth: 2).padding(48)

            VStack(spacing: 0) {
                Spacer(minLength: 24)
                Text("❝").font(.custom("Amiri-Bold", size: 104, relativeTo: .largeTitle))
                    .foregroundStyle(gold).frame(height: 86)
                Text(displayedQuote)
                    .font(.custom("Amiri", size: quoteSize, relativeTo: .title2))
                    .foregroundStyle(ink).multilineTextAlignment(.center)
                    .lineSpacing(15).lineLimit(hasCitation ? 13 : 16).minimumScaleFactor(0.68)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 10)
                    .accessibilityIdentifier("mihbara-quote-card-artwork-quote")
                Spacer(minLength: 40)

                if hasCitation {
                    Rectangle().fill(gold.opacity(0.72)).frame(height: 2).padding(.horizontal, 120)
                        .padding(.bottom, 25)
                }
                if extras.contains(.book) {
                    Text(card.bookTitle).font(.custom("thmanyahserifdisplay-Bold", size: 31, relativeTo: .title3))
                        .foregroundStyle(ink).multilineTextAlignment(.center).lineLimit(2)
                        .minimumScaleFactor(0.8)
                }
                if extras.contains(.author), !card.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text(card.author).font(.custom("thmanyahsans-Medium", size: 23, relativeTo: .body))
                        .foregroundStyle(muted).padding(.top, 8).lineLimit(1).minimumScaleFactor(0.8)
                }
                if extras.contains(.location), let location = card.location {
                    Text(location).font(.custom("thmanyahsans-Bold", size: 22, relativeTo: .body))
                        .foregroundStyle(ink).padding(.top, 8)
                }
                if extras.contains(.source) {
                    Text("المصدر: \(card.sourceName)")
                        .font(.custom("thmanyahsans-Medium", size: 20, relativeTo: .caption))
                        .foregroundStyle(muted).padding(.top, 16)
                    if let sourceAddress = card.sourceAddress {
                        Text(sourceAddress).font(.system(size: 18, weight: .medium, design: .rounded))
                            .foregroundStyle(ink).padding(.top, 5)
                    }
                }
                if extras.contains(.signature) {
                    Text("مِحبرة مدار").font(.custom("thmanyahsans-Bold", size: 19, relativeTo: .footnote))
                        .tracking(2).foregroundStyle(goldText).padding(.top, hasCitation ? 22 : 0)
                }
                Spacer(minLength: 12)
            }
            .frame(maxHeight: .infinity)
            .padding(.horizontal, 118).padding(.vertical, 105)
            .environment(\.layoutDirection, .rightToLeft)
            .multilineTextAlignment(.center)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .environment(\.colorScheme, .light)
    }
}
