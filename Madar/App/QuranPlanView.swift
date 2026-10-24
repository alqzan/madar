import SwiftUI
import MadarDesign

struct QuranPlanView: View {
    let service: AppQuranService
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var overview: QuranUIPlanOverview?
    @State private var error: String?
    @State private var busy = false
    @State private var showSetup = false
    private var app: AppSession { service.app }
    private let resetKeys = ["quran.hifzLevel", "quran.reviewLevel", "quran.restDay", "quran.wirdReminder", "quran.reviewSchedule"]
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                QuranScreenHeader(title: "خطّتك", close: close)
                if let overview {
                    QuranPaperCard {
                        VStack(spacing: 0) {
                            levelRow("درجة الحفظ المعتادة", key: "quran.hifzLevel")
                            line; levelRow("درجة المراجعة المعتادة", key: "quran.reviewLevel")
                            line
                            if let p = overview.input {
                                row("وحدة خطة الحفظ", detail: QuranPlanCopy.amount(p, digits: service.numerals))
                                line; row("وتيرة المراجعة المعتادة", detail: p.rhythm.title)
                                line
                            }
                            choiceRow("يوم الراحة", key: "quran.restDay", options: QuranUIRestDays.days + [("none","بلا")])
                            line; choiceRow("التذكير", key: "quran.wirdReminder", options: [("afterFajr","بعد الفجر"),("afterAsr","بعد العصر"),("afterIsha","بعد العشاء"),("off","بلا")])
                            line; choiceRow("جدول المراجعة", key: "quran.reviewSchedule", options: [("spaced","متباعدة"),("fixedJuzDaily","جزء يوميًا"),("fixedManzilWeekly","المنازل الأسبوعية")])
                        }
                    }
                    Button(overview.input == nil ? "ابدأ خطة الحفظ" : "عدّل خطة الحفظ") { showSetup = true }.font(quranFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("quran-plan-edit")
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Text("موعد الختمة").font(quranFont(17, bold: true)); Spacer(); Text("تقدير لكل درجة").font(quranFont(11)).foregroundStyle(theme.secondaryInk) }
                            if let input = overview.input {
                                let level = app.string("quran.hifzLevel")
                                Text(overview.forecasts[level]?.title ?? "—").font(quranSerif(29)).accessibilityIdentifier("quran-plan-forecast")
                                if let secondary = overview.forecasts[level]?.secondaryDate { Text(secondary).font(quranFont(12)).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("quran-plan-forecast-secondary") }
                                Text(overview.forecasts[level]?.assumptions ?? "").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                ForEach(QuranUILevel.allCases) { item in
                                    HStack { Text(item.title).font(quranFont(12, bold: item.id == level)).frame(width: 48, alignment: .leading)
                                        Capsule().fill(theme.color("hifz").opacity(item.id == level ? 1 : 0.4)).frame(width: 150 * CGFloat(overview.forecasts[item.id]?.estimatedDays ?? 0) / CGFloat(max(1, overview.forecasts.values.compactMap(\.estimatedDays).max() ?? 1)), height: 4)
                                        Spacer(minLength: 4); VStack(alignment: .trailing, spacing: 2) { Text(overview.forecasts[item.id]?.title ?? "—").font(quranFont(12)); if let secondary = overview.forecasts[item.id]?.secondaryDate { Text(secondary).font(quranFont(11)).foregroundStyle(theme.secondaryInk) } } }
                                }
                                if let warning = overview.forecasts[level]?.warning { Text(warning).font(quranFont(13)).foregroundStyle(theme.color("dueText")) }
                                Text(input.startAyah == 1 ? "ختم القرآن يتطلّب اكتمال الأوجه كلها، والفجوات معها." : "هذا موعد نطاق خطّتك؛ ختم القرآن لا يكون إلا بحفظ الأوجه كلها.").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                            } else { Text("ابدأ خطة الحفظ ليظهر تقديرك").font(quranFont(15)) }
                        }
                    }
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack { Text("سلسلتك").font(quranFont(17, bold: true)); Spacer(); Text(overview.streak).font(quranSerif(31)) }
                            Text("آخر أربعة أسابيع").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 4), count: 7), spacing: 4) {
                                ForEach(overview.days) { day in RoundedRectangle(cornerRadius: 5).fill(theme.color("memorized").opacity(day.hifz > 0 || day.review > 0 ? 1 : 0.12)).frame(height: 18).accessibilityLabel(day.date + (day.hifz > 0 || day.review > 0 ? "، عمل" : "، بلا عمل")) }
                            }
                        }
                    }
                    if let input = overview.input {
                        QuranPaperCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("لو فاتك يوم").font(quranFont(17, bold: true))
                                Text("اختر ما يحدث في يوم الحفظ التالي").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                                ForEach([("ask","اسألني كل مرة"),("spread","وزّعه على ثلاثة أيام"),("double","ضاعف اليوم"),("skip","تجاوزه")], id: \.0) { key, title in
                                    Button { var p = input; p.missPolicy = key; run { try await service.perform(.savePlan(p)); load() } } label: {
                                        HStack { Image(systemName: input.missPolicy == key ? "largecircle.fill.circle" : "circle"); Text(title).font(quranFont(14, bold: input.missPolicy == key)); Spacer() }.frame(minHeight: 44).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("quran-plan-miss-" + key)
                                }
                                Text("وزّعه: وجه واحد فائت يضيف ثلث وجه في كل يوم من ثلاثة أيام الحفظ، حسب مقدار وردك. تُطبّق السياسة المحفوظة في يوم الحفظ التالي.").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                            }
                        }
                    }
                    Button("أعِد المتفق عليه") { app.reset(resetKeys) }.font(quranFont(14)).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("quran-plan-reset")
                    Text(overview.version).font(quranFont(11)).accessibilityIdentifier("quran-plan-version").foregroundStyle(theme.secondaryInk)
                }
                if let error { Text(error).font(quranFont(13)) }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review")).disabled(busy || app.settingsWriteInProgress)
            .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: app.undo).accessibilityIdentifier("quran-plan-undo") } }
            .fullScreenCover(isPresented: $showSetup, onDismiss: load) { QuranPlanSetupView(service: service, close: { showSetup = false }) }
            .task { load() }.onChange(of: app.settingsWriteInProgress) { if !app.settingsWriteInProgress { load() } }.onChange(of: app.undoToken?.id) { load() }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("تمّ") { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
    }
    private var line: some View { Divider().overlay(theme.line) }
    private func row(_ title: String, detail: String) -> some View { HStack { Circle().fill(theme.color("review")).frame(width: 5, height: 5); Text(title).font(quranFont(13, bold: true)); Spacer(); Text(detail).font(quranFont(12)).foregroundStyle(theme.secondaryInk) }.frame(minHeight: 46) }
    private func levelRow(_ title: String, key: String) -> some View { choiceRow(title, key: key, options: QuranUILevel.allCases.map { ($0.id,$0.title) }) }
    private func choiceRow(_ title: String, key: String, options: [(String,String)]) -> some View {
        Menu { ForEach(options, id: \.0) { value, label in Button(label) { app.set(.string(value), key: key) }.accessibilityIdentifier("quran-plan-option-" + key + "-" + value) } } label: { row(title, detail: options.first { $0.0 == app.string(key) }?.1 ?? "—") }.accessibilityIdentifier("quran-plan-" + key)
    }
    private func load() { do { overview = try service.planOverview() } catch { self.error = quranUserMessage(error) } }
    private func run(_ work: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; Task { defer { busy = false }; do { try await work() } catch { self.error = quranUserMessage(error) } } }
}
