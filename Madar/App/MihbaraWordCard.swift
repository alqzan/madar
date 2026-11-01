import SwiftUI
import UIKit
import Translation
import MadarDesign

struct MihbaraWordCard: View {
    let state: MihbaraWordCardState
    let palette: MihbaraReaderPalette
    let swatches: [String]
    let copied: Bool
    let wordSaved: Bool
    let translationAvailability: MihbaraTranslationAvailability
    let lookUp: () -> Void
    let saveWord: () -> Void
    let translate: () -> Void
    let choose: (String) -> Void
    let note: () -> Void
    let copy: () -> Void
    let makeQuoteCard: () -> Void
    let close: () -> Void

    @State private var meaning: String?

    private var ink: SwiftUI.Color { palette.ink }
    private var ink2: SwiftUI.Color { palette.ink2 }
    private var accent: SwiftUI.Color { palette.accent }
    private var surface: SwiftUI.Color { palette.bg }
    /// OR-31: an English word shows its Arabic at once, translated on the device, with nothing to tap.
    private var translatesWord: Bool { state.isWord && state.canSaveAsWord && translationAvailability == .installed }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(state.word)
                        .font(.custom("Amiri-Bold", size: state.isWord ? 30 : 22, relativeTo: .title))
                        .foregroundStyle(ink).lineLimit(2).multilineTextAlignment(.leading)
                        .accessibilityIdentifier("mihbara-word-title")
                    if translatesWord, let meaning {
                        Text(meaning)
                            .font(.custom("Amiri-Bold", size: 24, relativeTo: .title2))
                            .foregroundStyle(accent).lineLimit(2)
                            .environment(\.layoutDirection, .rightToLeft)
                            .transition(.opacity)
                            .accessibilityLabel("بالعربية: " + meaning)
                            .accessibilityIdentifier("mihbara-word-meaning")
                    }
                    if state.isWord, state.hasSystemDefinition {
                        Button(action: lookUp) {
                            HStack(spacing: 6) {
                                Image(systemName: "character.book.closed").font(.system(size: 15, weight: .semibold))
                                Text("معناها في قاموس الجهاز").font(.custom("thmanyahsans-Bold", size: 17, relativeTo: .body))
                            }
                            .foregroundStyle(accent).frame(minHeight: 36).contentShape(Capsule())
                        }
                        .glassEffect(.regular.interactive(), in: Capsule())
                        .accessibilityIdentifier("mihbara-word-lookup")
                    } else if state.isWord, let page = state.pageText {
                        // Most Arabic words have no device definition; a «no definition» line at each would be a dead end.
                        Text("من \(page)").font(MadarTypography.caption()).foregroundStyle(ink2)
                            .accessibilityIdentifier("mihbara-word-page")
                    } else if !state.isWord, let page = state.pageText {
                        Text("فقرة مظلّلة من \(page)").font(MadarTypography.caption()).foregroundStyle(ink2)
                    }
                }
                Spacer(minLength: 8)
                Button(action: close) {
                    Image(systemName: "xmark").font(.system(size: 14, weight: .semibold)).foregroundStyle(ink2)
                        .frame(width: 44, height: 44).contentShape(Circle())
                }
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("إغلاق")
                .accessibilityIdentifier("mihbara-word-close")
            }
            HStack(spacing: 12) {
                Text("ظلّل الفقرة").font(MadarTypography.fine()).foregroundStyle(ink2)
                ForEach(Array(MihbaraHighlight.colors.enumerated()), id: \.element) { index, color in
                    let selected = state.color == color
                    Button { choose(color) } label: {
                        Circle().fill(SwiftUI.Color(uiColor: UIColor(madarHex: swatches[index])))
                            .overlay(Circle().strokeBorder(selected ? ink : ink2.opacity(0.35), lineWidth: selected ? 2.5 : 1))
                            .overlay { if selected { Image(systemName: "checkmark").font(.system(size: 15, weight: .bold)).foregroundStyle(ink) } }
                            .frame(width: 44, height: 44).contentShape(Circle())
                    }
                    .accessibilityLabel(selected ? "إزالة التظليل " + MihbaraHighlight.title(color) : "تظليل " + MihbaraHighlight.title(color))
                    .accessibilityAddTraits(selected ? .isSelected : [])
                    .accessibilityIdentifier("mihbara-highlight-\(color)")
                }
                Spacer(minLength: 0)
            }
            GlassEffectContainer(spacing: 8) {
                VStack(spacing: 10) {
                    HStack(spacing: 10) {
                        action("دوّن ملاحظة", icon: "square.and.pencil", id: "mihbara-word-note", run: note)
                        action(copied ? "نُسخت" : "انسخ مع التوثيق", icon: copied ? "checkmark" : "doc.on.doc", id: "mihbara-word-copy", run: copy)
                    }
                    action("بطاقة اقتباس", icon: "quote.bubble", id: "mihbara-quote-card-open", run: makeQuoteCard)
                    if state.isWord && (state.canSaveAsWord || translationAvailability != .unsupported) {
                        HStack(spacing: 10) {
                            if state.canSaveAsWord {
                                if wordSaved {
                                    Text("في كلماتي")
                                        .font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline))
                                        .foregroundStyle(ink2).frame(maxWidth: .infinity, minHeight: 56)
                                        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
                                        .accessibilityIdentifier("mihbara-word-saved")
                                } else {
                                    action("أضف إلى كلماتي", icon: "text.book.closed", id: "mihbara-word-save", run: saveWord)
                                }
                            }
                            switch translationAvailability {
                            case .installed:
                                action("ترجم الفقرة", icon: "character.bubble", id: "mihbara-word-translate", run: translate)
                            case .needsDownload:
                                // iOS asks to download the language pack the first time it translates.
                                action("نزّل الترجمة وترجم الفقرة", icon: "arrow.down.circle", id: "mihbara-translation-download", run: translate)
                            case .checking:
                                availability("نتحقق من توفر الترجمة", id: "mihbara-translation-checking", progress: true)
                            case .unsupported:
                                EmptyView()
                            }
                        }
                    }
                }
            }
        }
        .padding(.horizontal, 20).padding(.top, 18).padding(.bottom, 16)
        .background(RoundedRectangle(cornerRadius: 28, style: .continuous).fill(surface)
            .shadow(color: .black.opacity(palette.isDark ? 0.45 : 0.14), radius: 22, y: 6))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mihbara-word-card")
        .mihbaraWordMeaning(active: translatesWord, word: state.word) { result in
            withAnimation(.easeOut(duration: 0.2)) { meaning = result }
        }
    }

    private func action(_ title: String, icon: String, id: String, run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack(spacing: 6) {
                Image(systemName: icon).font(.system(size: 14, weight: .semibold))
                Text(title).font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .subheadline)).lineLimit(1).minimumScaleFactor(0.85)
            }
            .foregroundStyle(ink).frame(maxWidth: .infinity, minHeight: 56)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .glassEffect(.regular.interactive(), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(id)
    }

    private func availability(_ title: String, id: String, progress: Bool = false) -> some View {
        HStack(spacing: 8) {
            if progress { ProgressView().controlSize(.small) }
            Text(title).font(MadarTypography.fine()).lineLimit(2).multilineTextAlignment(.center)
        }
        .foregroundStyle(ink2).frame(maxWidth: .infinity, minHeight: 56)
        .glassEffect(.regular, in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .accessibilityIdentifier(id)
    }
}

/// Translates one English word to Arabic on the device; quiet on failure, the paragraph translation stays available.
private extension View {
    @ViewBuilder func mihbaraWordMeaning(active: Bool, word: String, completion: @escaping @MainActor @Sendable (String?) -> Void) -> some View {
        if active {
            translationTask(
                source: Locale.Language(identifier: "en"),
                target: Locale.Language(identifier: "ar"),
                action: mihbaraWordMeaningAction(word: word, completion: completion)
            )
        } else {
            self
        }
    }
}

private func mihbaraWordMeaningAction(
    word: String,
    completion: @escaping @MainActor @Sendable (String?) -> Void
) -> @Sendable (TranslationSession) async -> Void {
    { session in
        let response = try? await session.translate(word)
        let text = response?.targetText.trimmingCharacters(in: .whitespacesAndNewlines)
        await completion(text?.isEmpty == false && text?.lowercased() != word.lowercased() ? text : nil)
    }
}
