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
    @State private var fullPage = false
    private enum CoachSheet: String, Identifiable { case methods, exit; var id: String { rawValue } }
    private func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body)
    }
    var body: some View {
        VStack(spacing: 0) {
            if !fullPage { header }
            if let page = state.page {
                QuranCoachPage(page: page, coach: coach, stage: state.stage) { action(.reveal(ayahID: $0, wordIndex: nil)) }
                    .padding(.horizontal, 6)
                    .allowsHitTesting(!fullPage).accessibilityHidden(fullPage)
                    .overlay {
                        if fullPage {
                            Button { fullPage = false } label: { Color.clear.contentShape(Rectangle()) }
                                .buttonStyle(.plain).accessibilityLabel("إظهار أدوات الجلسة")
                                .accessibilityIdentifier("quran-session-show-tools")
                        }
                    }
                    .overlay(alignment: .bottom) {
                        if !fullPage {
                        Text(coach.caption).font(font(12, bold: true)).multilineTextAlignment(.center)
                            .foregroundStyle(theme.onAccent).padding(.horizontal, 15).padding(.vertical, 10)
                            .background(theme.accent, in: Capsule()).padding(.horizontal, 22).offset(y: 8)
                            .accessibilityLabel(coach.stageTitle + "، " + coach.caption)
                            .accessibilityIdentifier("quran-session-stage")
                        }
                    }
            }
            if state.stage == .grading && !fullPage {
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
            if !fullPage { controls.padding(.top, 20).padding(.horizontal, 12).padding(.bottom, 14) }
        }
        .padding(.bottom, fullPage ? 14 : 0)
        .background(theme.color("mushafPaper").ignoresSafeArea()).foregroundStyle(theme.ink)
        .ignoresSafeArea(.container, edges: .bottom)
        .statusBarHidden().persistentSystemOverlays(.hidden)
        .onAppear { if coach.pastDay { sheet = .exit } }
        .sheet(item: $sheet) { route in
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(route == .methods ? (coach.review ? "طريقة المراجعة" : "طريقة الحفظ") : "الجلسة")
                        .font(.custom("Amiri-Bold", size: 25, relativeTo: .title2))
                    if route == .methods {
                        if coach.review {
                            Text("سرد متصل").font(font(16, bold: true))
                            Text("سمّع من حفظك ثم اكشف الآية. «تعثّرت» يسجّل موضع الخطأ، والتقييم لكل وجه.").font(font(14)).foregroundStyle(theme.secondaryInk)
                        }
                        ForEach(QuranLearningMethod.allCases.filter { state.availableMethods[$0.rawValue] != nil }, id: \.rawValue) { method in
                            Button {
                                sheet = nil; action(.changeMethod(method.rawValue))
                            } label: {
                                HStack { Text(method.title); Spacer(); if state.method == method.rawValue { Image(systemName: "checkmark") } }
                                    .font(font(14)).frame(minHeight: 44).contentShape(Rectangle())
                            }.buttonStyle(.plain).accessibilityIdentifier("quran-method-" + method.rawValue)
                        }
                    } else {
                        Text(coach.pastDay ? "هذه جلسة من يوم سابق. احفظ ما تمّ بيومه أو تجاهل المسودة." : coach.review ? "المسودة محفوظة تلقائيًا. سجّل الأوجه التي قيّمتها، أو تجاهل الجلسة، أو تابع." : "المسودة محفوظة تلقائيًا. سجّل ما اجتاز التسميع المستور، أو تجاهل الجلسة، أو تابع.")
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
                Text(state.title).font(font(14, bold: true)).lineLimit(1).minimumScaleFactor(0.8)
                Text(coach.pageProgress + "، " + state.segmentTitle).font(font(11)).foregroundStyle(theme.secondaryInk)
                    .multilineTextAlignment(.center).lineLimit(2)
                HStack(spacing: 3) {
                    ForEach(coach.pages, id: \.self) { page in
                        Capsule().fill((coach.pages.firstIndex(of: page) ?? 0) <= (coach.pages.firstIndex(of: state.page?.page ?? 0) ?? 0) ? theme.color(coach.review ? "review" : "hifz") : theme.color("track")).frame(height: 3)
                    }
                }.frame(maxWidth: 156)
            }.frame(maxWidth: .infinity)
            Button { fullPage = true } label: {
                Image(systemName: "arrow.up.left.and.arrow.down.right").font(.system(size: 15))
                    .frame(width: 44, height: 44)
            }.buttonStyle(.plain).accessibilityLabel("عرض الصفحة كاملة")
                .accessibilityIdentifier("quran-session-full-page")
        }.padding(.horizontal, 12).padding(.bottom, 10)
            .accessibilityElement(children: .contain)
    }
    private var controls: some View {
        HStack(spacing: 8) {
            Button { sheet = .methods } label: {
                HStack(spacing: 5) {
                    Image(systemName: coach.review ? "text.justify" : "star")
                    Text(state.availableMethods[state.method] ?? "المدرّب الموجّه").font(font(12, bold: true)).multilineTextAlignment(.center)
                }.frame(maxWidth: .infinity, minHeight: 48).contentShape(Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("quran-session-method")
            Button { action(state.primaryAction) } label: {
                Text(state.primaryTitle).font(font(14, bold: true)).multilineTextAlignment(.center)
                    .frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(theme.onAccent)
                    .background(theme.accent, in: Capsule())
            }.buttonStyle(.plain).accessibilityIdentifier("quran-session-advance")
            Button { action(coach.review ? .mistake(ayahID: coach.activeAyahID, wordIndex: nil) : .reveal(ayahID: coach.activeAyahID, wordIndex: nil)) } label: {
                Image(systemName: coach.review ? "flag" : "chevron.forward.2").font(.system(size: 18)).frame(width: 48, height: 48)
                    .background(theme.color("track").opacity(0.4), in: Circle())
            }.buttonStyle(.plain).accessibilityLabel(coach.review ? "تعثّرت" : "تلقين الآية").accessibilityIdentifier("quran-session-hint")
                .disabled(coach.bridge || state.stage == .grading || (coach.review && coach.flaggedAyahs.contains(coach.activeAyahID)))
        }.padding(8).background(theme.surface, in: Capsule()).disabled(busy)
    }
}
