import SwiftUI
import Combine
import MadarDesign

struct QuranYearView: View {
    let service: AppQuranService
    let close: () -> Void
    @Binding var selection: QuranLogTab
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var type
    @State private var value: QuranUIYear?
    @State private var review = true
    @State private var month: QuranUIYearMonth?
    @State private var error: String?
    @State private var loadRequestID = UUID()
    @State private var reloadTask: Task<Void, Never>?
#if DEBUG
    @State private var loadCount = 0
#endif
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                QuranScreenHeader(title: "السجلّ", close: close)
                QuranLogTabs(selection: $selection)
                if let value {
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 16) {
                            HStack { Text("سنة كاملة").font(quranFont(17, bold: true)); Spacer(); Text("آخر سنة").font(quranFont(11)).foregroundStyle(theme.secondaryInk) }
                            Picker("النشاط", selection: $review) { Text("المراجعة").tag(true); Text("الحفظ").tag(false) }.pickerStyle(.segmented).frame(maxWidth: 210).accessibilityIdentifier("quran-year-kind")
                            // OR-21: say what the year holds for the chosen kind, not only how many days.
                            let faces = value.days.reduce(0) { $0 + (review ? $1.review : $1.hifz) }
                            VStack(alignment: .leading, spacing: 3) {
                                Text(faces == 0 ? (review ? "لا مراجعة مسجّلة هذه السنة" : "لا حفظ مسجّل هذه السنة") : service.faceCount(faces) + (review ? " راجعت" : " حفظت") + (faces == 1 ? "ه" : faces == 2 ? "هما" : "ها") + " هذه السنة")
                                    .font(quranSerif(20)).accessibilityIdentifier("quran-year-active")
                                if value.activeDays > 0 { Text("في " + service.dayCount(value.activeDays) + " من الصحبة").font(quranFont(12)).foregroundStyle(theme.secondaryInk) }
                            }
                            if type.isAccessibilitySize {
                                ForEach(value.months) { m in monthRow(m) }
                            } else {
                                Canvas { context, size in
                                    let gap: CGFloat = 1.5, w = (size.width - 52 * gap) / 53, h = (size.height - 6 * gap) / 7
                                    for (i, day) in value.days.enumerated() {
                                        let n = review ? Double(day.review) / 8 : Double(day.hifz)
                                        let x = size.width - CGFloat(i / 7 + 1) * w - CGFloat(i / 7) * gap
                                        let rect = CGRect(x: x, y: CGFloat(i % 7) * (h + gap), width: w, height: h)
                                        context.fill(Path(roundedRect: rect, cornerRadius: 1), with: .color((review ? theme.color("review") : theme.color("hifz")).opacity(n == 0 ? 0.12 : min(1, 0.3 + n * 0.7))))
                                    }
                                }.frame(height: 78).accessibilityLabel("خريطة النشاط من الأقدم يمينًا إلى اليوم يسارًا")
                                HStack(alignment: .top) { edgeMonth(value.days.first); Spacer(); edgeMonth(value.days.last) }.foregroundStyle(theme.secondaryInk)
                            }
                            HStack(spacing: 5) { Text("أقل"); ForEach([0.15,0.35,0.6,1.0], id: \.self) { a in RoundedRectangle(cornerRadius: 2).fill(theme.color(review ? "review" : "hifz").opacity(a)).frame(width: 10, height: 10) }; Text("أكثر"); Spacer(); Text("الحفظ والمراجعة") }.font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                        }
                    }
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 18) {
                            Text("الأشهر الهجرية").font(quranFont(17, bold: true))
                            Text(value.title).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            if let best = value.months.max(by: { $0.hifz < $1.hifz }), best.hifz > 0 {
                                Text("أكثر شهر حفظًا: " + best.title + (best.secondary.isEmpty ? "" : "، " + best.secondary) + " (" + service.faceCount(best.hifz) + ")").font(quranFont(13)).accessibilityIdentifier("quran-year-best")
                            }
                            monthBars(value.months, review: false)
                            Divider().overlay(theme.line)
                            monthBars(value.months, review: true)
                        }
                    }
                } else if let error {
                    Text(error).accessibilityIdentifier("quran-year-error")
                    Button("حاول مرة أخرى", action: reload).accessibilityIdentifier("quran-year-retry")
                } else {
                    ProgressView("نجهّز سجل السنة…")
                        .frame(maxWidth: .infinity)
                        .padding(50)
                        .accessibilityIdentifier("quran-year-loading")
                }
            }.padding(16).padding(.bottom, 20)
        }.foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea()).tint(theme.color("review"))
            .task {
                await load()
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
                   environment["MADAR_UI_QURAN_YEAR_READ_FAILURE_AFTER_FIRST"] == "1" {
                    await Task.yield()
                    await load()
                }
                #endif
            }
            // Left open past midnight, the log follows the day it is now.
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in reload() }
            .refreshesAtMadarDay(service.app) { reload() }
            .onDisappear {
                reloadTask?.cancel()
                reloadTask = nil
                loadRequestID = UUID()
            }
            .sheet(item: $month) { item in
                ScrollView { VStack(alignment: .leading, spacing: 14) {
                    Text(item.title).font(quranSerif(25))
                    if !item.secondary.isEmpty { Text(item.secondary).font(quranFont(13)).foregroundStyle(theme.secondaryInk) }
                    ForEach(value?.days.filter { $0.monthID == item.id && ($0.hifz > 0 || $0.review > 0) } ?? []) { day in
                        MadarDateLabel(day.date); Text("حفظ " + service.faceCount(day.hifz) + "، مراجعة " + service.faceCount(day.review)).font(quranFont(13))
                    }
                    if item.hifz == 0 && item.review == 0 { Text("لا جلسات مسجّلة").font(quranFont(15)) }
                    Button("تمّ") { month = nil }.frame(minHeight: 44)
                }.padding(24) }.background(theme.surface).foregroundStyle(theme.ink).presentationDetents([.medium, .large]).environment(\.layoutDirection, .rightToLeft)
            }
    }
    private func edgeMonth(_ day: QuranUIYearDay?) -> some View {
        VStack(spacing: 1) { Text(day?.month ?? "").font(quranFont(11)); Text(day?.secondaryMonth ?? "").font(quranFont(11)).opacity(0.8) }
    }
    private func monthRow(_ m: QuranUIYearMonth) -> some View {
        Button { month = m } label: {
            VStack(alignment: .leading, spacing: 2) {
                Text(m.title + "، حفظ " + service.faceCount(m.hifz) + "، مراجعة " + service.faceCount(m.review)).font(quranFont(14))
                if !m.secondary.isEmpty { Text(m.secondary).font(quranFont(11)).foregroundStyle(theme.secondaryInk) }
            }.frame(minHeight: 44)
        }
    }
    private func monthBars(_ months: [QuranUIYearMonth], review: Bool) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            let peak = months.map { review ? $0.review : $0.hifz }.max() ?? 0
            HStack {
                Circle().fill(theme.color(review ? "review" : "hifz")).frame(width: 8, height: 8)
                Text(review ? "المراجعة · أوجه" : "الحفظ · أوجه").font(quranFont(13, bold: true)); Spacer()
                Text(peak > 0 ? "الأعلى " + service.faceCount(peak) : "المس شهرًا للتفاصيل").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
            }
            if !type.isAccessibilitySize {
                let maxValue = max(1, months.map { review ? $0.review : $0.hifz }.max() ?? 1)
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(months) { m in
                        Button { month = m } label: {
                            VStack(spacing: 5) {
                                RoundedRectangle(cornerRadius: 4).fill(theme.color(review ? "review" : "hifz")).frame(height: max(3, CGFloat(review ? m.review : m.hifz) / CGFloat(maxValue) * 70))
                                Text(shortMonth(m.title)).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            }.frame(maxWidth: .infinity, minHeight: 100, alignment: .bottom)
                        }.buttonStyle(.madarPlain).accessibilityLabel(m.title + "، " + service.faceCount(review ? m.review : m.hifz)).accessibilityIdentifier("quran-year-month-" + m.id + (review ? "-review" : "-hifz"))
                    }
                }
            }
        }
    }
    private func shortMonth(_ title: String) -> String {
        let abbreviations = [("يناير", "ينا"), ("فبراير", "فبر"), ("مارس", "مار"), ("أبريل", "أبر"), ("مايو", "ماي"), ("يونيو", "يون"), ("يوليو", "يول"), ("أغسطس", "أغس"), ("سبتمبر", "سبت"), ("أكتوبر", "أكت"), ("نوفمبر", "نوف"), ("ديسمبر", "ديس"),
            ("جمادى الأولى", "جم١"), ("جمادى الآخرة", "جم٢"), ("ربيع الأول", "رب١"), ("ربيع الآخر", "رب٢"), ("ذو القعدة", "قع"), ("ذو الحجة", "حج"), ("محرم", "مح"), ("صفر", "صف"), ("رجب", "رج"), ("شعبان", "شع"), ("رمضان", "رم"), ("شوال", "شو")]
        if let range = title.components(separatedBy: "–").first, title.contains("–"),
           let start = abbreviations.first(where: { range.hasPrefix($0.0) })?.1,
           let endText = title.components(separatedBy: "–").dropFirst().first,
           let end = abbreviations.first(where: { endText.trimmingCharacters(in: .whitespaces).hasPrefix($0.0) })?.1 {
            return start + "–" + end
        }
        return abbreviations.first { title.hasPrefix($0.0) }?.1 ?? title
    }
    @MainActor private func reload() {
        reloadTask?.cancel()
        let requestID = UUID()
        loadRequestID = requestID
        reloadTask = Task { await load(requestID: requestID) }
    }
    @MainActor private func load(requestID: UUID? = nil) async {
        let requestID = requestID ?? UUID()
        loadRequestID = requestID
        guard !Task.isCancelled else { return }
        error = nil
        do {
            #if DEBUG
            loadCount += 1
            let environment = ProcessInfo.processInfo.environment
            if loadCount == 2,
               environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               environment["MADAR_UI_QURAN_YEAR_READ_FAILURE_AFTER_FIRST"] == "1" {
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            let result = try await service.yearLogOffMain()
            try Task.checkCancellation()
            guard loadRequestID == requestID else { return }
            value = result
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled, loadRequestID == requestID else { return }
            value = nil
            self.error = quranUserMessage(error)
        }
    }
}
