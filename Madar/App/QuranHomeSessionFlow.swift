import SwiftUI
import MadarDesign

/// The home needs a durable entry/exit flow. V02 owns the detailed coach's canonical visual acceptance.
struct QuranHomeSessionFlow: View {
    let service: AppQuranService
    @Binding var state: QuranUISessionState
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var showExit = false
    @State private var busy = false
    @State private var queuedReveals: [Int] = []
    /// A slip long-pressed while another save is running waits its turn; it is never dropped.
    @State private var queuedMistakes: [QuranUISessionAction] = []
    /// AU-95: «أنهِ وسجّل» or «تجاهل» tapped while a reveal or grade is still saving runs once it lands, instead of
    /// closing the sheet and silently doing nothing.
    @State private var queuedFinish: QuranUISessionAction?
    @State private var finishing = false
    @State private var autoAdvance: UUID?
    @State private var error: String?
    @State private var showDayClose = false
    @State private var showKhatmaMoment = false
    var body: some View {
        Group {
            if showDayClose {
                QuranDayCloseView(service: service, close: close)
            } else if let qiyam = state.qiyam {
                QuranQiyamSessionView(state: state, qiyam: qiyam, busy: busy, action: perform, close: close)
            } else if state.drill != nil {
                QuranDrillView(service: service, initial: state, close: close)
            } else if let coach = state.coach {
                QuranHifzCoachView(state: state, coach: coach, busy: busy, action: perform)
            } else { legacyBody }
        }
        .alert("لم تكتمل العملية", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("تمّ") { error = nil } } message: { Text(error ?? "") }
        .sheet(isPresented: $showKhatmaMoment) {
            QuranKhatmaMomentSheet(close: { showKhatmaMoment = false })
                .environment(\.roomTheme, theme)
                .environment(\.layoutDirection, .rightToLeft)
        }
        .interactiveDismissDisabled()
    }
    private var legacyBody: some View {
        VStack(spacing: 18) {
            HStack { Text(state.title).font(MadarTypography.cardTitle()); Spacer(); Button("إغلاق", systemImage: "xmark") { showExit = true }.labelStyle(.iconOnly).frame(width: 44, height: 44) }
            Text(state.segmentTitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Text(stageTitle).font(MadarTypography.section()).accessibilityIdentifier("quran-session-stage")
            ScrollView {
                VStack(spacing: 20) { ForEach(state.verses) { verse in
                    if verse.hidden {
                        Button("اكشف " + verse.title) { perform(.reveal(ayahID: verse.id, wordIndex: nil)) }
                            .font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 50).background(theme.color("hifzTint"), in: .rect(cornerRadius: 14))
                    } else if let name = state.page?.postScriptName { Text(verse.text).font(.custom(name, size: 23.3)).lineSpacing(14).frame(maxWidth: .infinity, alignment: .leading) }
                    else { Text("تعذّر تحميل هذا الوجه").font(MadarTypography.body()) }
                } }
            }
            if state.stage == .grading || state.stage == .review || state.stage == .qiyam {
                ForEach(state.grades) { grade in
                    Picker(grade.title, selection: Binding(get: { grade.grade }, set: { perform(.grade(page: grade.page, grade: $0)) })) {
                        ForEach(QuranUIGrade.allCases) { Text($0.title).tag($0) }
                    }.pickerStyle(.segmented)
                }
            }
            ForEach(state.answers) { answer in Button(answer.text) { perform(.chooseAnswer(answer.id)) }.font(MadarTypography.body()).frame(minHeight: 44) }
            Button(state.primaryTitle) { perform(state.primaryAction) }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("quran-session-advance")
        }.padding(20).foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea())
        .confirmationDialog("الجلسة", isPresented: $showExit, titleVisibility: .visible) {
            Button("أنهِ وسجّل ما تمّ") { perform(.commitPartial) }
            Button("تجاهل الجلسة", role: .destructive) { perform(.discard) }
            Button("تابع", role: .cancel) {}
        } message: { Text("«تجاهل الجلسة» لا يسجّل شيئًا مما أنجزته الآن.") } // AU-46
    }
    private var stageTitle: String {
        switch state.stage { case .repetition: "التكرار"; case .lineStarts: "أوائل الأسطر"; case .recall: "استرجاع بالتلقين"; case .covered: "تسميع مستور"; case .grading: "تقييمك"; default: "المراجعة" }
    }
    /// Owner 20 Oct: review had too many taps per page. In review only: the last uncovered ayah opens
    /// grading at once (the suggested grade is already chosen), and a grade moves on to the next page after
    /// a short beat; another grade in that beat replaces the pending move. Saving the session stays explicit.
    private func autoStep(after action: QuranUISessionAction, _ next: QuranUISessionState) {
        guard next.coach?.review == true else { return }
        let token = UUID(); autoAdvance = token
        switch action {
        case .reveal where next.stage != .grading && queuedReveals.isEmpty:
            if case .advance = next.primaryAction { schedule(token, after: 0.35) }
        case .grade where next.stage == .grading && next.primaryTitle == "تابع":
            schedule(token, after: 0.7)
        default: break
        }
    }
    /// Only ayahs still covered on the page in front of the reader; anything else is stale.
    private func drainReveals() {
        if !queuedMistakes.isEmpty { perform(queuedMistakes.removeFirst()); return }
        if let finish = queuedFinish { queuedFinish = nil; queuedReveals = []; perform(finish); return }
        let open = (state.coach?.plannedAyahs ?? []).subtracting(state.coach?.revealedAyahs ?? [])
        queuedReveals.removeAll { !open.contains($0) }
        guard state.stage != .grading, !queuedReveals.isEmpty else { queuedReveals = []; return }
        perform(.reveal(ayahID: queuedReveals.removeFirst(), wordIndex: nil))
    }
    private func schedule(_ token: UUID, after seconds: Double) {
        Task { try? await Task.sleep(for: .seconds(seconds)); guard autoAdvance == token else { return }
            // A save still running would drop the advance and leave the page waiting; try again shortly.
            if busy { schedule(token, after: 0.3) } else { autoAdvance = nil; perform(.advance) } }
    }
    private func perform(_ action: QuranUISessionAction) {
        // A finger dragged across the covered page reveals several ayahs in a row: queue them
        // instead of dropping the ones that arrive while the previous reveal is still saving.
        if busy {
            switch action {
            case .reveal(let ayah, nil) where !queuedReveals.contains(ayah): queuedReveals.append(ayah)
            case .mistake(let ayah, let word):
                let queued = queuedMistakes.contains { if case .mistake(ayah, word) = $0 { true } else { false } }
                if !queued { queuedMistakes.append(action) }
            case .commit where !finishing, .commitPartial where !finishing, .discard where !finishing: queuedFinish = action
            default: break
            }
            return
        }
        busy = true
        switch action { case .commit, .commitPartial, .discard: finishing = true; default: break }
        switch action { case .reveal, .mistake: break; default: queuedReveals = []; queuedMistakes = [] }
        Task { defer { busy = false; finishing = false; drainReveals() }; do { switch try await service.session(draftID: state.id, action: action) {
        case .active(let next): state = next; autoStep(after: action, next)
        case .completed(_, let reachedKhatm):
            queuedReveals = []; queuedMistakes = []; autoAdvance = nil
            if case .commit = action, state.coach?.pastDay != true {
                showDayClose = true
                showKhatmaMoment = reachedKhatm
            } else { close() }
        case .discarded: queuedReveals = []; queuedMistakes = []; close()
        } } catch { self.error = quranUserMessage(error) } }
    }
}

private struct QuranKhatmaMomentSheet: View {
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        VStack(spacing: 24) {
            Text("أتممت حفظ القرآن، تقبّل الله منك.")
                .font(.custom("Amiri-Bold", size: 27, relativeTo: .title2))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity)
                .accessibilityIdentifier("quran-khatma-moment-message")
            doneButton
        }
        .padding(.horizontal, 24)
        .padding(.vertical, 30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .foregroundStyle(theme.ink)
        .background(theme.background.ignoresSafeArea())
        .presentationDetents(dynamicType.isAccessibilitySize ? [.medium, .large] : [.height(250)])
        .presentationDragIndicator(.visible)
    }

    @ViewBuilder private var doneButton: some View {
        Button("تمّ", action: close)
            .font(.custom("thmanyahsans-Bold", size: 15, relativeTo: .body))
            .frame(maxWidth: .infinity, minHeight: 48)
            .buttonStyle(.glass)
            .accessibilityIdentifier("quran-khatma-moment-dismiss")
    }
}
