import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

struct PrayerHeartAnswerSheet: View {
    let session: AppSession
    let cell: PrayerCell
    let finished: () -> Void
    let rootDraftChanged: (UUID, Bool) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var answer: PrayerHeart?
    @State private var rootBlockerID = UUID()
    private var hasUnsavedInput: Bool { answer != cell.heart }
    init(session: AppSession, cell: PrayerCell, finished: @escaping () -> Void, rootDraftChanged: @escaping (UUID, Bool) -> Void) {
        self.session = session; self.cell = cell; self.finished = finished; self.rootDraftChanged = rootDraftChanged
        _answer = State(initialValue: cell.heart)
    }
    @State private var contentHeight: CGFloat = 520
    /// RP6 in the room's own paper sheet (was a stock grey Form): three answers as cards, the chosen one marked by the prayer star.
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text("سؤال القلب").font(.custom("thmanyahserifdisplay-Bold", size: 30, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                Text(prayerTitle(cell.reference.prayer)).font(PrayerHomeType.smallBold).foregroundStyle(theme.color("accentText"))
            }
            Text("كيف كان حضور قلبك في " + prayerTitle(cell.reference.prayer) + "؟").font(PrayerHomeType.body).padding(.top, 10)
            Text("سؤال اختياري للتأمّل، بلا درجة أو مقارنة.").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.top, 4)
            VStack(spacing: 10) { ForEach(PrayerHeart.allCases, id: \.self) { answerCard($0) } }.padding(.top, 18)
            Button { save(answer) } label: {
                Text("احفظ الإجابة").font(PrayerHomeType.strong).foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity, minHeight: 56).background(theme.ink, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.madarPlain).disabled(answer == nil).opacity(answer == nil ? 0.4 : 1).padding(.top, 18)
            .accessibilityIdentifier("prayer-heart-save")
            // With an answer already saved, "skip" must not erase it: it just closes.
            Button { if cell.heart == nil { save(nil) } else { finished() } } label: { Text(cell.heart == nil ? "أمرّ" : "أبقِ جوابي").font(PrayerHomeType.strong).foregroundStyle(theme.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 44).padding(.top, 4).contentShape(Rectangle()) }.accessibilityIdentifier("prayer-heart-skip")
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 + 20 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background).foregroundStyle(theme.ink)
        .disabled(session.prayerWriteInProgress)
        .presentationDetents([.height(min(max(contentHeight, 300), 760)), .large])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }
    private func answerCard(_ heart: PrayerHeart) -> some View {
        let chosen = answer == heart
        return Button { answer = heart } label: {
            HStack(spacing: 14) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(heartTitle(heart)).font(PrayerHomeType.strong)
                    Text(heartSentence(heart)).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                }
                Spacer(minLength: 8)
                ZStack {
                    Circle().stroke(chosen ? theme.accent : theme.ink.opacity(0.18), lineWidth: 1.2)
                    if chosen { PrayerStar().fill(theme.accent).frame(width: 14, height: 14).transition(.scale.combined(with: .opacity)) }
                }
                .frame(width: 28, height: 28).accessibilityHidden(true)
            }
            .padding(.horizontal, 18).frame(minHeight: 66)
            .background(theme.color("surface"), in: .rect(cornerRadius: 18))
            .overlay { RoundedRectangle(cornerRadius: 18).stroke(chosen ? theme.accent : theme.line, lineWidth: chosen ? 1.5 : 1) }
            .contentShape(.rect(cornerRadius: 18))
        }
        .buttonStyle(.madarPlain).animation(reduceMotion ? nil : .snappy(duration: 0.22), value: chosen)
        .accessibilityIdentifier("prayer-heart-\(heart.rawValue)").accessibilityAddTraits(chosen ? [.isSelected] : [])
    }
    private func save(_ value: PrayerHeart?) {
        session.answerPrayerHeart(cell.reference, heart: value) { succeeded in if succeeded { finished() } }
    }
}
