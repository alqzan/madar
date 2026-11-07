import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands

struct QuranPlanView: View {
    let service: AppQuranService
    let close: () -> Void
    let onSetupPresentationChange: (Bool) -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.isFrontRoom) private var isFrontRoom
    @State private var overview: QuranUIPlanOverview?
    @State private var error: String?
    @State private var busy = false
    @State private var showSetup = false
    @State private var previewLevel: QuranUILevel?
    @State private var overviewRequestID = UUID()
    @State private var loadedMadarDay: GregorianDay?
    @State private var madarDayRevision = -1
    @State private var madarDayGeneration = -1
    private var app: AppSession { service.app }
    private var displayedMadarDay: GregorianDay? {
        guard madarDayRevision == app.prayerRevision, madarDayGeneration == app.storeGeneration else { return nil }
        return loadedMadarDay
    }
    private func dayReadKey(at instant: Date) -> [Int] {
        [Int(instant.timeIntervalSince1970 / 60), app.prayerRevision, app.storeGeneration, isFrontRoom ? 1 : 0]
    }
    private let resetKeys = ["quran.hifzLevel", "quran.reviewLevel", "quran.restDay", "quran.wirdReminder", "quran.reviewSchedule"]
    init(service: AppQuranService, close: @escaping () -> Void, onSetupPresentationChange: @escaping (Bool) -> Void = { _ in }) {
        self.service = service
        self.close = close
        self.onSetupPresentationChange = onSetupPresentationChange
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let evaluatedAt = service.currentTime()
            let dayReadKey = dayReadKey(at: evaluatedAt)
            let currentDay = displayedMadarDay
            ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                QuranScreenHeader(title: "خطّتك", close: close)
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_QURAN_PLAN_ROOT_ROUTE_HARNESS"] == "1",
                   ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
                    Button("اختبر رابط الجذر") { app.open(URL(string: "madar://quran")!) }
                        .accessibilityIdentifier("quran-plan-root-route")
                }
#endif
                if let overview {
                    let forecasts = overview.day == currentDay ? overview.forecasts : [:]
                    QuranPaperCard {
                        VStack(spacing: 0) {
                            // AU-04 (R18-Khitta): the plan itself heads the card, what it memorises, one tap from its editor.
                            if let p = overview.input, let surah = (try? QuranResources.catalog())?.ayah(id: p.startAyah)?.surahNameArabic {
                                Button { showSetup = true } label: { row("خطة الحفظ", detail: "من سورة " + surah, dot: "hifz", chevron: true).contentShape(Rectangle()) }
                                    .buttonStyle(.madarPlain).accessibilityIdentifier("quran-plan-summary")
                                line
                            }
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
                    Button(overview.input == nil ? "ابدأ خطة الحفظ" : "عدّل خطة الحفظ") { showSetup = true }.font(quranFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("quran-plan-edit")
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Text("موعد الختمة").font(quranFont(17, bold: true)); Spacer(); Text("تقدير لكل درجة").font(quranFont(11)).foregroundStyle(theme.secondaryInk) }
                            if let input = overview.input {
                                let level = previewLevel?.rawValue ?? app.string("quran.hifzLevel")
                                forecastTrack
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
                                    Button { var p = input; p.missPolicy = key; run { try await service.perform(.savePlan(p)); await load() } } label: {
                                        HStack(spacing: 10) {
                                            Image(systemName: input.missPolicy == key ? "largecircle.fill.circle" : "circle").foregroundStyle(input.missPolicy == key ? theme.color("hifzText") : theme.secondaryInk)
                                            VStack(alignment: .leading, spacing: 3) {
                                                Text(title).font(quranFont(14, bold: input.missPolicy == key))
                                                Text(key == "ask" ? "تختار عند كل ورد فائت" : key == "spread" ? "ثلث الورد في ثلاثة أيام حفظ" : key == "double" ? "ورد إضافي في يوم حفظ واحد" : "تُكمل بالمعتاد")
                                                    .font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                            }
                                            Spacer()
                                        }.padding(.horizontal, 14).frame(minHeight: 64).contentShape(.rect)
                                            .background(input.missPolicy == key ? theme.color("hifzTint") : theme.surface, in: .rect(cornerRadius: 17))
                                            .overlay { RoundedRectangle(cornerRadius: 17).stroke(input.missPolicy == key ? theme.color("hifz") : theme.color("track"), lineWidth: 1) }
                                    }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-plan-miss-" + key)
                                        .accessibilityAddTraits(input.missPolicy == key ? .isSelected : [])
                                }
                                missedDayChart(overview, policy: input.missPolicy)
                            }
                        }
                    }
                    Button("أعِد المتفق عليه") { app.reset(resetKeys) }.font(quranFont(14)).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("quran-plan-reset")
                    Text(overview.version).font(quranFont(11)).accessibilityIdentifier("quran-plan-version").foregroundStyle(theme.secondaryInk)
                }
                if let error { Text(error).font(quranFont(13)) }
                // AU-95: a failed first read left only the header; one tap reads the plan again.
                if overview == nil, error != nil {
                    Button("أعِد المحاولة") { reload(at: service.currentTime()) }.font(quranFont(14, bold: true)).frame(minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("quran-plan-retry")
                }
            }.padding(16)
        }.madarTopClipped().background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review")).disabled(busy || app.settingsWriteInProgress)
            .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).hostsUndo(app).accessibilityIdentifier("quran-plan-undo") } }
            .fullScreenCover(isPresented: $showSetup, onDismiss: { reload(at: service.currentTime()) }) { QuranPlanSetupView(service: service, close: { showSetup = false }) }
            .task(id: dayReadKey) { await refreshMadarDay(at: evaluatedAt, key: dayReadKey) }
            .task(id: currentDay) {
                if overview == nil || overview?.day != currentDay { await load(at: evaluatedAt) }
            }
            .onChange(of: app.settingsWriteInProgress) { if !app.settingsWriteInProgress { reload(at: service.currentTime()) } }
            .onChange(of: app.undoToken?.id) { reload(at: service.currentTime()) }
            .onChange(of: showSetup, initial: true) { _, presented in onSetupPresentationChange(presented) }
            .onChange(of: app.string("quran.hifzLevel")) { previewLevel = nil }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("تمّ") { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
        }
    }
    private var line: some View { Divider().overlay(theme.line) }
    @MainActor private func refreshMadarDay(at instant: Date, key: [Int]) async {
        guard isFrontRoom else { return }
        do {
            let day = try await service.forecastDayOffMain(at: instant)
            try Task.checkCancellation()
            guard isFrontRoom, key == dayReadKey(at: service.currentTime()) else { return }
            loadedMadarDay = day
            madarDayRevision = key[1]
            madarDayGeneration = key[2]
        } catch is CancellationError {
        } catch {
            guard key == dayReadKey(at: service.currentTime()) else { return }
            loadedMadarDay = nil
            madarDayRevision = key[1]
            madarDayGeneration = key[2]
        }
    }
    private func missedDayChart(_ overview: QuranUIPlanOverview, policy: String) -> some View {
        let choice = policy == "ask" ? "spread" : policy
        let days = overview.missPreviews[choice] ?? []
        let highest = max(0.000001, days.map { $0.base + $0.extra }.max() ?? 1)
        return VStack(alignment: .leading, spacing: 12) {
            Divider().overlay(theme.line)
            Text("لو فاتك ورد واحد").font(quranFont(14, bold: true))
            Text("وردك المعتاد: " + overview.habitualAmount).font(quranFont(12)).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("quran-plan-example-amount")
            if policy == "ask" {
                Text("تختار التوزيع عند الفوات.").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
            }
            HStack(alignment: .top, spacing: 8) {
                ForEach(days) { day in
                    VStack(spacing: 7) {
                        Text(day.extra == 0 ? "وردك" : choice == "spread" ? "وردك وثلثه" : "وردان")
                            .font(quranFont(11, bold: day.extra > 0)).foregroundStyle(theme.color("hifzText"))
                            .frame(minHeight: 30).multilineTextAlignment(.center)
                        VStack(spacing: 0) {
                            Spacer(minLength: 0)
                            Rectangle().fill(theme.color("hifz")).frame(height: 70 * day.extra / highest)
                            Rectangle().fill(theme.color("hifzTint")).frame(height: 70 * day.base / highest)
                        }.frame(height: 70).clipShape(.rect(topLeadingRadius: 5, topTrailingRadius: 5)).accessibilityHidden(true)
                        MadarDateLabel(app.dateLabels(day.day, first: .hijri, compact: true), primaryFont: quranFont(11), secondaryFont: quranFont(11))
                            .foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center)
                    }.frame(maxWidth: .infinity).accessibilityElement(children: .combine)
                        .accessibilityIdentifier("quran-plan-miss-preview-" + day.id)
                }
            }
            Text("الأيام المعروضة أيام حفظ، بلا يوم الراحة. المعاينة لا تسجّل تعويضًا ولا تغيّر موعد الختمة.")
                .font(quranFont(11)).foregroundStyle(theme.secondaryInk)
        }
    }
    /// The home room's four-stop track, reused as a read-only forecast comparison here.
    private var forecastTrack: some View {
        let selected = previewLevel ?? QuranUILevel(rawValue: app.string("quran.hifzLevel")) ?? .medium
        let current = QuranUILevel.allCases.firstIndex(of: selected) ?? 1
        return VStack(alignment: .leading, spacing: 8) {
            Text("لو ثبتّ على درجة واحدة").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
            GeometryReader { proxy in
                HStack(spacing: 0) {
                    ForEach(Array(QuranUILevel.allCases.enumerated()), id: \.element) { index, item in
                        Button { previewLevel = item } label: {
                            VStack(spacing: 7) {
                                ZStack {
                                    Rectangle().fill(theme.color("track")).frame(height: 4).padding(.leading, index == 0 ? 22 : 0).padding(.trailing, index == 3 ? 22 : 0)
                                    if index <= current {
                                        Rectangle().fill(theme.color("hifz")).frame(height: 4).padding(.leading, index == 0 ? 22 : 0).padding(.trailing, index == 3 ? 22 : 0)
                                    }
                                    Circle().fill(index <= current ? theme.color("hifz") : theme.surface).frame(width: index == current ? 20 : 12, height: index == current ? 20 : 12)
                                        .overlay { Circle().stroke(index <= current ? theme.color("hifz") : theme.color("track"), lineWidth: 2) }
                                }.frame(height: 24)
                                Text(item.title).font(quranFont(12, bold: index == current))
                            }.frame(maxWidth: .infinity, minHeight: 48).contentShape(.rect)
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-plan-preview-" + item.rawValue)
                            .accessibilityAddTraits(index == current ? .isSelected : [])
                    }
                }.simultaneousGesture(DragGesture(minimumDistance: 12).onChanged { gesture in
                    let position = min(1, max(0, 1 - gesture.location.x / max(1, proxy.size.width)))
                    previewLevel = QuranUILevel.allCases[Int((position * 3).rounded())]
                })
            }.frame(height: 54)
            Text("معاينة للموعد؛ درجتك المعتادة لا تتغيّر.").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
        }
    }
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
    @MainActor private func load(at instant: Date? = nil) async {
        let requestID = UUID(); overviewRequestID = requestID
        do {
            let value = try await service.planOverview(at: instant)
            try Task.checkCancellation()
            guard overviewRequestID == requestID else { return }
            overview = value; error = nil
        } catch is CancellationError {
        } catch {
            guard overviewRequestID == requestID else { return }
            self.error = quranUserMessage(error)
        }
    }
    private func reload(at instant: Date? = nil) {
        Task { @MainActor in await load(at: instant) }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; Task { defer { busy = false }; do { try await work() } catch { self.error = quranUserMessage(error) } } }
}
