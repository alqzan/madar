import SwiftUI
import Translation
import MadarDesign

@available(iOS 18.0, *)
struct MihbaraTranslationSheet: View {
    let request: MihbaraTranslationRequest
    let paper: SwiftUI.Color
    let palette: MihbaraReaderPalette
    @Environment(\.dismiss) private var dismiss
    @State private var translatedText: String?
    @State private var failed = false

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button("تمّ") { dismiss() }
                    .font(MadarTypography.body()).frame(minWidth: 44, minHeight: 44)
                    .accessibilityIdentifier("mihbara-translation-close")
                Spacer()
                Text("ترجمة الفقرة").font(MadarTypography.section())
                Spacer()
                Color.clear.frame(width: 44, height: 44).accessibilityHidden(true)
            }
            Text("ترجمة آلية تقريبية · تُعالج على الجهاز")
                .font(MadarTypography.fine()).foregroundStyle(palette.ink2)
            Rectangle().fill(palette.line).frame(height: 1)
            ScrollView {
                if let translatedText {
                    Text(translatedText).font(.custom("Amiri-Regular", size: 20, relativeTo: .body))
                        .lineSpacing(7).foregroundStyle(palette.ink).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("mihbara-translation-result")
                } else if failed {
                    Text("تعذّرت الترجمة. تحقّق من تثبيت اللغتين ثم حاول مجددًا.")
                        .font(MadarTypography.body()).foregroundStyle(palette.ink2)
                        .accessibilityIdentifier("mihbara-translation-error")
                } else {
                    ProgressView("تُترجم الفقرة على الجهاز…")
                        .font(MadarTypography.body()).tint(palette.accent)
                        .accessibilityIdentifier("mihbara-translation-progress")
                }
            }
            Spacer(minLength: 0)
        }
        .padding(20).background(paper.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .translationTask(
            source: Locale.Language(identifier: request.sourceLanguage),
            target: Locale.Language(identifier: "ar"),
            action: Self.translationAction(text: request.text) { result in
                translatedText = result
                failed = result == nil
            }
        )
    }

    nonisolated private static func translationAction(
        text: String,
        completion: @escaping @MainActor @Sendable (String?) -> Void
    ) -> @Sendable (TranslationSession) async -> Void {
        { session in
            do {
                let response = try await session.translate(text)
                await completion(response.targetText)
            } catch {
                await completion(nil)
            }
        }
    }
}
