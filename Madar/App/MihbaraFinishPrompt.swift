import SwiftUI
import MadarCore
import MadarDesign

/// FB-45 (§7.6): near the end of a book (98% or the last page) the reader asks «أنهيته؟» once, in place. A touch puts the
/// book on «أنهيتها» after the reading position is saved, then closes the reader. A finished book is not asked again.
struct MihbaraFinishPrompt: View {
    let app: AppSession
    let book: MihbaraBook
    let tint: Color
    let ink: Color
    let prepareToFinish: @MainActor () async -> Bool
    let resumeReading: @MainActor () -> Void
    let close: @MainActor () -> Void
    @State private var working = false

    var body: some View {
        Button {
            guard !working else { return }
            working = true
            Task { @MainActor in
                guard await prepareToFinish() else { resumeReading(); working = false; return }
                do {
                    try await app.executeBookCommand("book.moveShelf", payload: ["id": .string(book.id.uuidString), "shelf": .string("finished")])
                    close()
                } catch { resumeReading(); app.errorMessage = madarUserMessage(error); working = false }
            }
        } label: {
            Label("أنهيته؟ ضعه في «أنهيتها»", systemImage: "checkmark.seal")
                .font(MadarTypography.caption()).foregroundStyle(ink)
                .padding(.horizontal, 14).frame(minHeight: 44)
                .contentShape(.capsule)
        }
        .buttonStyle(.glass).tint(tint)
        .disabled(working)
        .accessibilityIdentifier("mihbara-reader-finish")
        .transition(.opacity.combined(with: .scale(scale: 0.96)))
    }
}
