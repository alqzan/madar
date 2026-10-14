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
    @State private var error: String?
    var body: some View {
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
        }
        .alert("لم تكتمل العملية", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("تمّ") { error = nil } } message: { Text(error ?? "") }
        .interactiveDismissDisabled()
    }
    private var stageTitle: String {
        switch state.stage { case .repetition: "التكرار"; case .lineStarts: "أوائل الأسطر"; case .recall: "استرجاع بالتلقين"; case .covered: "تسميع مستور"; case .grading: "تقييمك"; default: "المراجعة" }
    }
    private func perform(_ action: QuranUISessionAction) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { switch try await service.session(draftID: state.id, action: action) {
        case .active(let next): state = next
        case .completed, .discarded: close()
        } } catch { self.error = quranUserMessage(error) } }
    }
}
