import SwiftUI
import LocalAuthentication
import MadarDesign

struct MihbaraQuoteCardSheet: View {
    @Bindable var app: AppSession
    let card: MihbaraQuoteCardContent
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var quote: String
    @State private var extras: Set<MihbaraQuoteExtra> = []
    @State private var shareError: String?
    @State private var sharing = false
    @State private var rootBlockerID = UUID()
    @FocusState private var editing: Bool

    init(app: AppSession, card: MihbaraQuoteCardContent) {
        self.app = app
        self.card = card
        _quote = State(initialValue: card.quote)
    }

    private var background: SwiftUI.Color { theme.background }
    private var ink: SwiftUI.Color { theme.ink }
    private var secondaryInk: SwiftUI.Color { theme.secondaryInk }
    private var trimmedQuote: String { quote.trimmingCharacters(in: .whitespacesAndNewlines) }
    private var blocksRootRoute: Bool { quote != card.quote || !extras.isEmpty || sharing }

    /// Extras with nothing to show (a book without an author, a page without a printed label) are not offered.
    private var offeredExtras: [MihbaraQuoteExtra] {
        MihbaraQuoteExtra.allCases.filter { extra in
            switch extra {
            case .author: !card.author.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            case .location: card.location != nil
            default: true
            }
        }
    }

    private var artwork: MihbaraQuoteCardArtwork {
        MihbaraQuoteCardArtwork(card: card, quote: trimmedQuote, extras: extras)
    }

    var body: some View {
        VStack(spacing: 12) {
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1" {
                Button("اختبر الجذر") { app.open(URL(string: "madar://mihbara")!) }
                    .accessibilityIdentifier("mihbara-quote-card-root-route")
            }
#endif
            GlassEffectContainer(spacing: 12) {
                ZStack {
                    Text("بطاقة اقتباس").font(MadarTypography.section())
                        .frame(maxWidth: .infinity)
                    HStack {
                        Spacer(minLength: 44)
                        closeButton
                    }
                }
                shareButton
                    .disabled(trimmedQuote.isEmpty || sharing)
                    .accessibilityIdentifier("mihbara-quote-card-share")
                    .accessibilityHint(extras.contains(.source) && card.sourceURL != nil ? "يشارك صورة البطاقة ورابط الكتاب في الشاملة" : "يشارك صورة البطاقة")
            }

            ScrollView {
                VStack(spacing: 18) {
                    preview
                    editor
                    extrasPicker
                }
                .padding(.horizontal, 8).padding(.bottom, 12)
            }
            .scrollIndicators(.hidden)
            .scrollDismissesKeyboard(.interactively)
        }
        .padding(.horizontal, 12).padding(.top, 14).padding(.bottom, 12)
        .foregroundStyle(ink).background(background.ignoresSafeArea())
        .interactiveDismissDisabled(blocksRootRoute)
        .onChange(of: blocksRootRoute, initial: true) { _, blocked in
            app.setMihbaraRootDraftBlocker(rootBlockerID, active: blocked)
        }
        .onDisappear { app.setMihbaraRootDraftBlocker(rootBlockerID, active: false) }
        .toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("تمّ") { editing = false }.accessibilityIdentifier("mihbara-quote-card-done")
            }
        }
        .alert("مشاركة البطاقة", isPresented: Binding(get: { shareError != nil }, set: { if !$0 { shareError = nil } })) {
            Button("حسنًا", role: .cancel) { shareError = nil }
        } message: { Text(shareError ?? "") }
    }

    /// The card itself, drawn live at its real size and scaled to the sheet, so every edit shows at once.
    private var preview: some View {
        GeometryReader { proxy in
            let width = proxy.size.width
            artwork
                .scaleEffect(width / MihbaraQuoteCardArtwork.size.width)
                .frame(width: width, height: width * MihbaraQuoteCardArtwork.size.height / MihbaraQuoteCardArtwork.size.width)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
                .shadow(color: ink.opacity(0.18), radius: 16, y: 6)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(accessibilityDescription)
                .accessibilityIdentifier("mihbara-quote-card-preview")
                .animation(.easeInOut(duration: 0.2), value: extras)
        }
        .aspectRatio(MihbaraQuoteCardArtwork.size.width / MihbaraQuoteCardArtwork.size.height, contentMode: .fit)
        .frame(maxWidth: 300)
        .allowsHitTesting(false)
    }

    private var editor: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("النص").font(MadarTypography.caption()).foregroundStyle(secondaryInk)
                Spacer()
                if quote != card.quote {
                    Button { quote = card.quote } label: { Text("أعد النص كما في الكتاب")
                        .font(MadarTypography.caption()).foregroundStyle(ink)
                        .frame(minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityIdentifier("mihbara-quote-card-restore")
                }
            }
            TextEditor(text: $quote)
                .font(.custom("Amiri", size: 19, relativeTo: .body))
                .lineSpacing(6)
                .scrollContentBackground(.hidden)
                .focused($editing)
                .frame(minHeight: 120, maxHeight: 220)
                .padding(10)
                .background(RoundedRectangle(cornerRadius: 18, style: .continuous).fill(theme.surface))
                .overlay(RoundedRectangle(cornerRadius: 18, style: .continuous).strokeBorder(secondaryInk.opacity(0.22), lineWidth: 1))
                .accessibilityLabel("نص الاقتباس")
                .accessibilityIdentifier("mihbara-quote-card-text")
            Text(trimmedQuote.isEmpty ? "اكتب ما تريد أن يبقى من الفقرة." : "احذف منه ما شئت أو أضف؛ البطاقة تتبعك.")
                .font(MadarTypography.fine()).foregroundStyle(secondaryInk)
        }
    }

    private var extrasPicker: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("أضف إلى البطاقة").font(MadarTypography.caption()).foregroundStyle(secondaryInk)
            MihbaraQuoteFlowRows(spacing: 8) {
                ForEach(offeredExtras) { extra in
                    let on = extras.contains(extra)
                    Button {
                        if on { extras.remove(extra) } else { extras.insert(extra) }
                    } label: {
                        HStack(spacing: 6) {
                            Image(systemName: on ? "checkmark" : "plus").font(.system(size: 12, weight: .bold))
                            Text(extra.title).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline))
                        }
                        .padding(.horizontal, 14).frame(minHeight: 44)
                        .foregroundStyle(on ? theme.background : ink)
                        .background(Capsule().fill(on ? ink : theme.surface))
                        .overlay(Capsule().strokeBorder(secondaryInk.opacity(on ? 0 : 0.3), lineWidth: 1))
                        .contentShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(on ? "أزل " + extra.title : "أضف " + extra.title)
                    .accessibilityAddTraits(on ? .isSelected : [])
                    .accessibilityIdentifier("mihbara-quote-extra-\(extra.rawValue)")
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private var accessibilityDescription: String {
        var parts: [String?] = [trimmedQuote]
        if extras.contains(.book) { parts.append(card.bookTitle) }
        if extras.contains(.author) { parts.append(card.author) }
        if extras.contains(.location) { parts.append(card.location) }
        if extras.contains(.source) { parts += [card.sourceName, card.sourceAddress] }
        if extras.contains(.signature) { parts.append("مِحبرة مدار") }
        return parts.compactMap { $0?.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }.joined(separator: "، ")
    }

    private var closeLabel: some View {
        Image(systemName: "xmark").font(.system(size: 14, weight: .semibold))
            .foregroundStyle(secondaryInk).frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle).contentShape(Circle())
    }

    private var shareLabel: some View {
        HStack(spacing: 8) {
            Image(systemName: "square.and.arrow.up").font(.system(size: 17, weight: .semibold))
            Text("شارك البطاقة").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body))
        }
        .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 54).contentShape(Capsule())
    }

    @ViewBuilder private var closeButton: some View {
        Button { dismiss() } label: { closeLabel }
            .buttonStyle(.glass).buttonBorderShape(.circle)
            .accessibilityLabel("إغلاق").accessibilityIdentifier("mihbara-quote-card-close")
    }

    @ViewBuilder private var shareButton: some View {
        Button(action: shareCard) { shareLabel }
            .buttonStyle(.glass)
    }

    /// The image is drawn from the card exactly as it stands when the reader taps share.
    private func shareCard() {
        editing = false
        let renderer = ImageRenderer(content: artwork)
        renderer.scale = 2
        guard let image = renderer.uiImage else {
            shareError = "تعذّر إنشاء صورة البطاقة."
            return
        }
        sharing = true
        Task { @MainActor in
            defer { sharing = false }
            do {
                guard let controller = app.lockController, let presenter = app.privacyPresenter else {
                    throw PrivacyAuthorizationError.stale
                }
                let authorization = try await controller.authorize([.app])
                try controller.validate(authorization)
                var items: [Any] = [image]
                if extras.contains(.source), let sourceURL = card.sourceURL { items.append(sourceURL) }
                try presenter.present(items: items, authorization: authorization)
            } catch {
                // Cancelling Face ID is the reader's choice, not a failure.
                if let la = error as? LAError, [.userCancel, .systemCancel, .appCancel].contains(la.code) { return }
                shareError = "تعذّرت المشاركة. أعد المحاولة من البطاقة."
            }
        }
    }
}
