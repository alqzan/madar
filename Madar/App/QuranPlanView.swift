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
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let evaluatedAt = service.currentTime()
            let currentDay = service.forecastDay(at: evaluatedAt)
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                QuranScreenHeader(title: "خطّتك", close: close)
                if let overview {
                    let forecasts = overview.day == currentDay ? overview.forecasts : [:]
                    QuranPaperCard {
                        VStack(spacing: 0) {
                            levelRow("درجة الحفظ المعتادة", key: "quran.hifzLevel", dot: "hifz")
                            line; levelRow("درجة المراجعة المعتادة", key: "quran.reviewLevel")
                            line
                            if let p = overview.input {
                                row("وحدة خطة الحفظ", detail: QuranPlanCopy.amount(p, digits: service.numerals), dot: "hifz")
                                line; row("وتيرة المراجعة المعتادة", detail: p.rhythm.title)
                                line
                            }
                            choiceRow("يوم الراحة", key: "quran.restDay", options: QuranUIRestDays.days + [("none","بلا")], dot: nil)
                            line; choiceRow("التذكير", key: "quran.wirdReminder", options: [("afterFajr","بعد الفجر"),("afterAsr","بعد العصر"),("afterIsha","بعد العشاء"),("off","بلا")], dot: nil)
                            line; choiceRow("جدول المراجعة", key: "quran.reviewSchedule", options: [("spaced","متباعدة"),("fixedJuzDaily","جزء يوميًا"),("fixedManzilWeekly","المنازل الأسبوعية")])
                        }
                    }
                    Button(overview.input == nil ? "ابدأ خطة الحفظ" : "عدّل خطة الحفظ") { showSetup = true }.font(quranFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("quran-plan-edit")
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Text("موعد الختمة").font(quranFont(17, bold: true)); Spacer(); Text("تقدير لكل درجة").font(quranFont(11)).foregroundStyle(theme.secondaryInk) }
                            if let input = overview.input {
                                let level = app.string("quran.hifzLevel")
                                Text(forecasts[level]?.title ?? (overview.day == currentDay ? "—" : "نحسب موعدك")).font(quranSerif(29)).accessibilityIdentifier("quran-plan-forecast")
                                if let secondary = forecasts[level]?.secondaryDate { Text(secondary).font(quranFont(12)).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("quran-plan-forecast-secondary") }
                                Text(forecasts[level]?.assumptions ?? "").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                if let days = forecasts[level]?.estimatedDays { Text("بعد " + span(days)).font(quranFont(13, bold: true)).accessibilityIdentifier("quran-plan-span") }
                                // Each level as the time it would take, a length the user can picture; the chosen level's date is above in both calendars.
                                let longest = CGFloat(max(1, forecasts.values.compactMap(\.estimatedDays).max() ?? 1))
                                ForEach(QuranUILevel.allCases) { item in
                                    HStack(spacing: 10) {
                                        Text(item.title).font(quranFont(12, bold: item.id == level)).frame(width: 48, alignment: .leading)
                                        GeometryReader { proxy in
                                            ZStack(alignment: .leading) {
                                                Capsule().fill(theme.color("hifzTint"))
                                                Capsule().fill(theme.color("hifz").opacity(item.id == level ? 1 : 0.45)).frame(width: proxy.size.width * CGFloat(forecasts[item.id]?.estimatedDays ?? 0) / longest)
                                            }
                                        }.frame(height: 6)
                                        Text(forecasts[item.id]?.estimatedDays.map(span) ?? "—").font(quranFont(12, bold: item.id == level)).frame(width: 82, alignment: .trailing)
                                    }.accessibilityElement(children: .combine)
                                }
                                if let warning = forecasts[level]?.warning { Text(warning).font(quranFont(13)).foregroundStyle(theme.color("dueText")) }
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
            .fullScreenCover(isPresented: $showSetup, onDismiss: { load(at: service.currentTime()) }) { QuranPlanSetupView(service: service, close: { showSetup = false }) }
            .task(id: currentDay) { load(at: evaluatedAt) }.onChange(of: app.settingsWriteInProgress) { if !app.settingsWriteInProgress { load(at: service.currentTime()) } }.onChange(of: app.undoToken?.id) { load(at: service.currentTime()) }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("تمّ") { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
        }
    }
    private var line: some View { Divider().overlay(theme.line) }
    /// «نحو ١٣ شهرًا»; under two months the days themselves.
    private func span(_ days: Int) -> String {
        if days < 60 { return service.dayCount(days) }
        let months = Int((Double(days) / 30.44).rounded()), n = service.numerals.string(months)
        return "نحو " + (months == 2 ? "شهرين" : (3...10).contains(months) ? n + " أشهر" : n + " شهرًا")
    }
    /// As in the design, each row's dot says what it governs: gold memorisation, green review, ink for the day itself.
    private func row(_ title: String, detail: String, dot: String? = "review", chevron: Bool = false) -> some View {
        HStack {
            Circle().fill(dot.map { theme.color($0) } ?? theme.secondaryInk).frame(width: 7, height: 7)
            Text(title).font(quranFont(13, bold: true)); Spacer(); Text(detail).font(quranFont(12)).foregroundStyle(theme.secondaryInk)
            if chevron { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)).foregroundStyle(theme.secondaryInk).accessibilityHidden(true) }
        }.frame(minHeight: 46)
    }
    private func levelRow(_ title: String, key: String, dot: String = "review") -> some View { choiceRow(title, key: key, options: QuranUILevel.allCases.map { ($0.id,$0.title) }, dot: dot) }
    private func choiceRow(_ title: String, key: String, options: [(String,String)], dot: String? = "review") -> some View {
        Menu { ForEach(options, id: \.0) { value, label in Button(label) { app.set(.string(value), key: key) }.accessibilityIdentifier("quran-plan-option-" + key + "-" + value) } } label: { row(title, detail: options.first { $0.0 == app.string(key) }?.1 ?? "—", dot: dot, chevron: true) }.accessibilityIdentifier("quran-plan-" + key)
    }
    private func load(at instant: Date? = nil) { do { overview = try service.planOverview(at: instant); error = nil } catch { self.error = quranUserMessage(error) } }
    private func run(_ work: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; Task { defer { busy = false }; do { try await work() } catch { self.error = quranUserMessage(error) } } }
}
