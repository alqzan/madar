import SwiftUI
import MadarDesign
import MadarQuran

struct QuranHifzCoachView: View {
    let state: QuranUISessionState
    let coach: QuranUICoach
    let busy: Bool
    let action: (QuranUISessionAction) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var sheet: CoachSheet?
    private enum CoachSheet: String, Identifiable { case methods, exit; var id: String { rawValue } }
    private func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body)
    }
    var body: some View {
        VStack(spacing: 0) {
            header
            if let page = state.page {
                QuranCoachPage(page: page, coach: coach, stage: state.stage) { action(.reveal(ayahID: $0, wordIndex: nil)) }
                    .padding(.horizontal, 6)
                    .overlay(alignment: .bottom) {
                        Text(coach.caption).font(font(12, bold: true)).multilineTextAlignment(.center)
                            .foregroundStyle(theme.onAccent).padding(.horizontal, 15).padding(.vertical, 10)
                            .background(theme.accent, in: Capsule()).padding(.horizontal, 22).offset(y: 8)
                            .accessibilityLabel(coach.stageTitle + "، " + coach.caption)
                            .accessibilityIdentifier("quran-session-stage")
                    }
            }
            if state.stage == .grading {
                VStack(alignment: .leading, spacing: 8) {
                    Text("تقييمك لهذا الوجه").font(font(13, bold: true))
                    ForEach(state.grades) { grade in
                        HStack(spacing: 8) {
                            ForEach(QuranUIGrade.allCases) { value in
                                Button { action(.grade(page: grade.page, grade: value)) } label: {
                                    Text(value.title).font(font(12, bold: value == grade.grade))
                                        .frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(value == grade.grade ? theme.onAccent : theme.ink)
                                        .background(value == grade.grade ? theme.accent : theme.surface, in: Capsule())
                                }.buttonStyle(.plain).accessibilityAddTraits(value == grade.grade ? .isSelected : [])
                                    .accessibilityIdentifier("quran-coach-grade-" + value.rawValue)
                            }
                        }
                    }
                }.padding(.horizontal, 20).padding(.top, 20)
            }
            controls.padding(.top, 24).padding(.horizontal, 12).padding(.bottom, 14)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .ignoresSafeArea(.container, edges: .bottom)
        .statusBarHidden().persistentSystemOverlays(.hidden)
        .onAppear { if coach.pastDay { sheet = .exit } }
        .sheet(item: $sheet) { route in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(route == .methods ? "طريقة الحفظ" : "الجلسة")
                        .font(.custom("Amiri-Bold", size: 25, relativeTo: .title2))
                    if route == .methods {
                        ForEach(QuranLearningMethod.allCases.filter { state.availableMethods[$0.rawValue] != nil }, id: \.rawValue) { method in
                            Button {
                                sheet = nil; action(.changeMethod(method.rawValue))
                            } label: {
                                HStack { Text(method.title); Spacer(); if state.method == method.rawValue { Image(systemName: "checkmark") } }
                                    .font(font(14)).frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("quran-method-" + method.rawValue)
                        }
                    } else {
                        Text(coach.pastDay ? "هذه جلسة من يوم سابق. احفظ ما تمّ بيومه أو تجاهل المسودة." : "المسودة محفوظة تلقائيًا. سجّل ما اجتاز التسميع المستور، أو تجاهل الجلسة، أو تابع.")
                            .font(font(14)).foregroundStyle(theme.secondaryInk)
                        sheetButton("أنهِ وسجّل ما تمّ", id: "quran-session-save-partial") { action(.commitPartial) }
                        sheetButton("تجاهل الجلسة", id: "quran-session-discard") { action(.discard) }
                        if !coach.pastDay { sheetButton("تابع", id: "quran-session-continue") {} }
                    }
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
            }
            .foregroundStyle(theme.ink).presentationBackground(theme.background)
            .presentationDetents([.height(route == .methods ? 410 : 360), .large])
            .presentationDragIndicator(.visible).environment(\.layoutDirection, .rightToLeft)
            .interactiveDismissDisabled(coach.pastDay)
        }
    }
    private func sheetButton(_ title: String, id: String, perform: @escaping () -> Void) -> some View {
        Button { sheet = nil; perform() } label: {
            Text(title).font(font(14, bold: true)).frame(maxWidth: .infinity, minHeight: 48)
                .background(theme.surface, in: Capsule()).contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private var header: some View {
        HStack(spacing: 10) {
            Button { sheet = .exit } label: {
                Image(systemName: "xmark").font(.system(size: 19, weight: .regular))
                    .frame(width: 44, height: 44).background(theme.color("track").opacity(0.35), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("إغلاق الجلسة").accessibilityIdentifier("quran-session-close")
            VStack(spacing: 4) {
                Text(state.title).font(font(14, bold: true))
                Text(state.segmentTitle + " · " + coach.pageProgress).font(font(11)).foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center)
                HStack(spacing: 3) {
                    ForEach(coach.pages, id: \.self) { page in
                        Capsule().fill(page <= (state.page?.page ?? 0) ? theme.color("hifz") : theme.color("track")).frame(height: 3)
                    }
                }.frame(maxWidth: 156)
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: 44, height: 44)
        }.padding(.horizontal, 12).padding(.bottom, 10)
            .accessibilityElement(children: .contain)
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button { sheet = .methods } label: {
                HStack(spacing: 5) {
                    Image(systemName: "star")
                    Text(state.availableMethods[state.method] ?? "المدرّب الموجّه").font(font(12, bold: true)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("quran-session-method")
            Button { action(state.primaryAction) } label: {
                Text(state.primaryTitle).font(font(14, bold: true)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(theme.onAccent)
                    .background(theme.accent, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("quran-session-advance")
            Button { action(.reveal(ayahID: coach.activeAyahID, wordIndex: nil)) } label: {
                Image(systemName: "chevron.forward.2").font(.system(size: 18)).frame(width: 48, height: 48)
                    .background(theme.color("track").opacity(0.4), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel("تلقين الآية").accessibilityIdentifier("quran-session-hint")
                .disabled(coach.bridge || state.stage == .grading)
        }.padding(8).background(theme.surface, in: Capsule()).disabled(busy)
    }
}
