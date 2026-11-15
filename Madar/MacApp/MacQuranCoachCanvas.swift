import SwiftUI
import AppKit
import MadarQuran

/// The Mac's Mushaf page body, first slice. The iPhone/iPad page draws the verified glyph lines with UIKit; until that drawing is
/// ported to AppKit, the Mac sets the page's own semantic ayat in the same Hafs face, right to left, with the same coach behaviour:
/// a covered ayah shows as a soft band that a click uncovers, a click on an open ayah opens its tafsir (or advances reading), and the
/// pressed ayah is lit while its tafsir is open. Nothing is recorded here that the iPhone page would not record.
struct QuranCoachTextCanvas: View {
    let page: QuranUIPage
    let coach: QuranUICoach
    let stage: QuranUISessionStage
    let ink: NSColor
    let tint: NSColor
    let reveal: (Int) -> Void
    var markWord: ((Int, Int) -> Void)? = nil
    var readingTap: (() -> Void)? = nil
    var mark: NSColor = .red
    var blurredWordsOnly = false
    var sealInk: NSColor = .black
    var sealTint: NSColor = .clear
    var medinaStyle = false
    var gold: NSColor = .clear
    var paper: NSColor = .clear
    var selectedAyah: Int? = nil
    var ayahPress: ((Int) -> Void)? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(page.semanticAyat) { ayah in row(ayah) }
            }
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.hidden)
    }

    private func covered(_ ayah: QuranUIVerse) -> Bool {
        guard coach.plannedAyahs.contains(ayah.id), !coach.revealedAyahs.contains(ayah.id) else { return false }
        return stage == .covered || stage == .recall || stage == .lineStarts || (coach.review && stage == .review)
    }

    @ViewBuilder private func row(_ ayah: QuranUIVerse) -> some View {
        let planned = coach.plannedAyahs.isEmpty || coach.plannedAyahs.contains(ayah.id)
        let hidden = covered(ayah)
        Text(ayah.text)
            .font(.custom(page.postScriptName, size: 26))
            .foregroundStyle(Color(nsColor: ink))
            .lineSpacing(10)
            .multilineTextAlignment(.leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .opacity(hidden ? 0 : planned ? 1 : 0.45)
            .overlay {
                if hidden {
                    RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: tint))
                        .overlay { Text("اكشف " + ayah.title).font(.custom("Amiri-Bold", size: 15)).foregroundStyle(Color(nsColor: sealInk)) }
                }
            }
            .padding(.horizontal, 6).padding(.vertical, 2)
            .background {
                if selectedAyah == ayah.id { RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: gold).opacity(0.18)) }
            }
            .contentShape(Rectangle())
            .onTapGesture {
                if hidden { reveal(ayah.id) }
                else if let ayahPress { ayahPress(ayah.id) }
                else if let readingTap { readingTap() }
                else { reveal(ayah.id) }
            }
            .contextMenu {
                if let markWord, planned { Button("سجّل زلّة في هذه الآية") { markWord(ayah.id, 0) } }
            }
            .help(ayah.title)
    }
}
