import SwiftUI
import MadarCore
import MadarDesign
import MadarCommands
import MadarQuran

struct QuranPlanSetupView: View {
    let service: AppQuranService
    let close: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var input: QuranUIPlanInput?
    @State private var initialStart = 1
    @State private var customStartAyah = 1
    @State private var step = 0
    @State private var customStart = false
    @State private var page = 1
    @State private var forecastState: QuranUIForecastState?
    @State private var busy = false
    @State private var error: String?
    #if DEBUG
        @State private var injectedLoadFailure = false
    #endif
    private let titles = ["من أين تبدأ؟", "كم وردك؟", "كيف تتعلّم؟", "يوم الراحة", "هذه خطّتك"]
    private func loadPlan() {
        error = nil
        do {
            #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if !injectedLoadFailure, UUID(uuidString: environment["MADAR_UI_STORE_ID"] ?? "") != nil,
                    environment["MADAR_UI_QURAN_PLAN_READ_FAILURE_ONCE"] == "1"
                {
                    injectedLoadFailure = true
                    throw CocoaError(.fileReadUnknown)
                }
            #endif
            let p = try service.planInput()
            let startPage = try QuranResources.catalog().ayah(id: p.startAyah)?.page ?? 1
            input = p; initialStart = p.startAyah
            customStartAyah = p.startAyah
            page = startPage
        } catch { self.error = quranUserMessage(error) }
    }
    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { _ in
            let evaluatedAt = service.currentTime()
            let forecastDay = service.forecastDay(at: evaluatedAt)
            let forecastKey = input.map { QuranUIForecastKey(input: $0, day: forecastDay) }
            VStack(spacing: 0) {
                QuranScreenHeader(title: "خطة الحفظ") { if step > 0 { step -= 1 } else { close() } }.padding(
                    .horizontal, 16)
                #if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_QURAN_ROUTE_SETUP_HARNESS"] == "1",
                        ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil
                    {
                        Button("اختبر رابط الوجه") { service.app.open(URL(string: "madar://quran/page/2")!) }
                            .accessibilityIdentifier("ui-test-open-quran-page-from-setup")
                    }
                #endif
                Text("تُقبل في قلبك من حيث أنت").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                HStack(spacing: 5) {
                    ForEach(0..<4) { n in
                        Capsule().fill(n <= step ? theme.color("hifz") : theme.color("track")).frame(height: 4)
                    }
                }.padding(16).accessibilityLabel("الخطوة " + service.numerals.string(min(step + 1, 4)) + " من ٤")
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        Text(step < 4 ? "الخطوة " + service.numerals.string(step + 1) + " من " + service.numerals.string(4) : "الملخّص").font(
                            quranFont(12)
                        ).foregroundStyle(theme.secondaryInk)
                        Text(titles[step]).font(quranSerif(33)).accessibilityIdentifier("quran-setup-title")
                        if let input { content(input) }
                        if let error { Text(error).font(quranFont(13)).foregroundStyle(theme.color("dueText")) }
                        // AU-46: a failed first read is not a dead end.
                        if input == nil, error != nil {
                            Button("حاول مرة أخرى") {
                                self.error = nil; loadPlan()
                            }.font(quranFont(15, bold: true)).frame(minHeight: 44).accessibilityIdentifier(
                                "quran-setup-retry")
                        }
                    }.padding(16)
                }
                if let input {
                    let visibleForecast = forecastDay.flatMap { forecastState?.visible(for: input, on: $0) }
                    VStack(spacing: 10) {
                        QuranPaperCard {
                            VStack(alignment: .leading, spacing: 5) {
                                Text("الإتمام المتوقع بالخطة").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                                Text(visibleForecast?.title ?? "نحسب موعدك").font(quranSerif(27))
                                    .accessibilityIdentifier("quran-setup-forecast")
                                if let secondary = visibleForecast?.secondaryDate {
                                    Text(secondary).font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                                        .accessibilityIdentifier("quran-setup-forecast-secondary")
                                }
                                if let warning = visibleForecast?.warning {
                                    Text(warning).font(quranFont(13, bold: true)).foregroundStyle(
                                        theme.color("dueText"))
                                }
                                Text("تقدير بافتراض إتمام أيام الحفظ بلا فوت أو تثبيت.").font(quranFont(11))
                                    .foregroundStyle(theme.secondaryInk)
                            }
                        }
                        Button(step == 4 ? (busy ? "نحفظ الخطة…" : "احفظ الخطة") : "التالي") {
                            if step < 4 {
                                step += 1
                            } else {
                                busy = true;
                                Task {
                                    defer { busy = false };
                                    do { try await service.perform(.savePlan(input)); close() } catch {
                                        self.error = quranUserMessage(error)
                                    }
                                }
                            }
                        }.font(quranFont(16, bold: true)).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(
                            theme.onAccent
                        ).background(theme.accent, in: Capsule()).accessibilityIdentifier("quran-setup-next")
                    }.padding(16)
                }
            }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review"))
                .disabled(busy)
                .task { loadPlan() }
                .task(id: forecastKey) {
                    guard let input, let forecastKey else { forecastState = nil; return }
                    do {
                        let result = try await service.previewPlan(input, at: evaluatedAt)
                        try Task.checkCancellation()
                        guard let day = forecastKey.day,
                            service.forecastDay(at: service.currentTime()) == day
                        else { return }
                        forecastState = QuranUIForecastState(input: input, day: day, forecast: result)
                        error = nil
                    } catch is CancellationError {} catch { self.error = quranUserMessage(error) }
                }
        }
    }
    @ViewBuilder private func content(_ p: QuranUIPlanInput) -> some View {
        switch step {
        case 0:
            option(
                "أكمل بالترتيب المعتاد من موضعك", detail: "الفجوة الأولى تبقى أول الورد، وما في صدرك يبقى للمراجعة",
                selected: !customStart, id: "quran-setup-continue"
            ) {
                customStart = false; input?.startAyah = initialStart
            }
            option(
                "من موضع أختاره", detail: "حدّد الوجه والآية التي تبدأ منها", selected: customStart,
                id: "quran-setup-custom"
            ) {
                customStart = true; input?.startAyah = customStartAyah
            }
            if customStart {
                QuranPaperCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Stepper("الوجه " + service.numerals.string(page), value: $page, in: 1...604)
                            .accessibilityIdentifier("quran-setup-page")
                        Picker(
                            "بداية الورد",
                            selection: Binding(
                                get: { customStartAyah },
                                set: { value in
                                    customStartAyah = value; input?.startAyah = value
                                }
                            )
                        ) {
                            ForEach(ayahs(page), id: \.id) { ayah in
                                Text(ayah.surahNameArabic + " " + service.numerals.string(ayah.ayahNumber)).tag(ayah.id)
                            }
                        }.accessibilityIdentifier("quran-setup-ayah")
                    }.font(quranFont(15))
                }.onChange(of: page) { choosePage(page) }
            }
        case 1:
            QuranPaperCard {
                VStack(alignment: .leading, spacing: 18) {
                    Text("الوحدة").font(quranFont(15, bold: true))
                    ForEach(QuranUIUnit.allCases) { unit in
                        Button {
                            if input?.unit != unit { input?.unit = unit; input?.amount = 1 }
                        } label: {
                            HStack {
                                Text(unit.title); Spacer();
                                if unit == p.unit { Image(systemName: "checkmark.circle.fill") }
                            }.frame(minHeight: 44).contentShape(Rectangle())
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-setup-unit-" + unit.id)
                    }
                    Stepper(
                        QuranPlanCopy.amount(p, digits: service.numerals), value: binding(\.amount),
                        in: 1...(p.unit == .ayah ? 6236 : 604), step: 1
                    ).accessibilityIdentifier("quran-setup-amount")
                }.font(quranFont(15))
            }
        case 2:
            ForEach(QuranUIRhythm.allCases) { rhythm in
                option(
                    rhythm.title,
                    detail: rhythm == .light
                        ? "تكرار الآية ثلاث مرات"
                        : rhythm == .balanced ? "تكرار الآية خمس مرات" : "تكرار الآية سبع مرات",
                    selected: rhythm == p.rhythm, id: "quran-setup-rhythm-" + rhythm.id
                ) { input?.rhythm = rhythm }
            }
            Text("الإيقاع يضبط التدريب ومواعيد المراجعة؛ درجة الحفظ المعتادة تضبط مقدار يومك.").font(quranFont(13))
                .foregroundStyle(theme.secondaryInk)
        case 3:
            Text("يوم للمراجعة دون حفظ جديد").font(quranFont(13)).foregroundStyle(theme.secondaryInk)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 4), spacing: 8) {
                ForEach(QuranUIRestDays.days, id: \.0) { key, title in
                    let selected = p.restDay == key
                    Button {
                        input?.restDay = key
                    } label: {
                        Text(title).font(quranFont(14, bold: selected)).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(selected ? theme.onAccent : theme.ink)
                            .background(selected ? theme.accent : theme.surface, in: .rect(cornerRadius: 16))
                            .overlay {
                                RoundedRectangle(cornerRadius: 16).stroke(selected ? .clear : theme.line, lineWidth: 1)
                            }
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-setup-rest-" + key)
                        .accessibilityAddTraits(selected ? .isSelected : [])
                }
            }
            option("بلا يوم راحة", detail: "الحفظ كل يوم", selected: p.restDay == "none", id: "quran-setup-rest-none") {
                input?.restDay = "none"
            }
        default:
            QuranPaperCard {
                VStack(alignment: .leading, spacing: 16) {
                    Text(startTitle(p.startAyah)).font(quranSerif(24))
                    Text(QuranPlanCopy.amount(p, digits: service.numerals) + " في يوم الحفظ").font(
                        quranFont(16, bold: true))
                    Text("إيقاع " + p.rhythm.title).font(quranFont(15))
                    Text("الراحة: " + QuranUIRestDays.title(p.restDay)).font(quranFont(15))
                    Text("تُحفظ نسخة جديدة من الخطة، وتبقى جلساتك السابقة مرتبطة بنسختها.").font(quranFont(13))
                        .foregroundStyle(theme.secondaryInk)
                }
            }
        }
    }
    private func option(_ title: String, detail: String, selected: Bool, id: String, action: @escaping () -> Void)
        -> some View
    {
        Button(action: action) {
            HStack(spacing: 12) {
                Image(systemName: selected ? "largecircle.fill.circle" : "circle");
                VStack(alignment: .leading, spacing: 5) {
                    Text(title).font(quranFont(17, bold: true));
                    Text(detail).font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                }; Spacer(minLength: 0)
            }.padding(18).frame(maxWidth: .infinity, minHeight: 80, alignment: .leading).background(
                theme.surface, in: .rect(cornerRadius: 22)
            ).overlay {
                RoundedRectangle(cornerRadius: 22).stroke(
                    selected ? theme.color("hifz") : theme.line, lineWidth: selected ? 2 : 1)
            }.contentShape(Rectangle())
        }.buttonStyle(.madarPlain).accessibilityIdentifier(id).accessibilityAddTraits(selected ? .isSelected : [])
    }
    private func binding<T>(_ key: WritableKeyPath<QuranUIPlanInput, T>) -> Binding<T> {
        Binding(get: { input![keyPath: key] }, set: { input?[keyPath: key] = $0 })
    }
    private func ayahs(_ page: Int) -> [QuranAyahResourceRecord] {
        (try? QuranResources.catalog().ayahs(on: page)) ?? []
    }
    private func choosePage(_ number: Int) {
        guard let first = ayahs(number).first else { return }
        customStartAyah = first.id
        input?.startAyah = first.id
    }
    private func startTitle(_ id: Int) -> String {
        guard let ayah = try? QuranResources.catalog().ayah(id: id) else { return "" };
        return "من " + ayah.surahNameArabic + " " + service.numerals.string(ayah.ayahNumber)
    }
}
