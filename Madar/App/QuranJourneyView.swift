import SwiftUI
import MadarDesign

struct QuranJourneyView: View {
    let service: AppQuranService
    let close: () -> Void
    @Binding var selection: QuranLogTab
    @Environment(\.roomTheme) private var theme
    @State private var value: QuranUIJourney?
    @State private var page = 1
    @State private var showPage = false
    @State private var reader: Int?
    @State private var error: String?
    @State private var attempt = 0

    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                QuranScreenHeader(title: "السجلّ", close: close)
                QuranLogTabs(selection: $selection)
                if let value {
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 9) {
                            HStack(alignment: .firstTextBaseline, spacing: 8) {
                                Text("رحلة الحفظ").font(quranFont(17, bold: true))
                                Spacer(minLength: 6)
                                Text("منذ " + value.first).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                    .multilineTextAlignment(.leading)
                            }
                            Text(forecastHeadline(value)).font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityIdentifier("quran-journey-forecast")
                            journeyChart(value)
                            if !value.planned.isEmpty {
                                Text("موعد الخطة: " + value.planned).font(quranFont(11, bold: true)).foregroundStyle(theme.secondaryInk)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(value.explanation).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            HStack {
                                Text("منذ البداية").font(quranFont(17, bold: true))
                                Spacer(minLength: 8)
                                Text("أرقامك كلها").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            }
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                                ForEach(value.stats) { stat in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(stat.title).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                        Text(stat.value).font(quranSerif(25)).fixedSize(horizontal: false, vertical: true)
                                            .accessibilityIdentifier("quran-journey-" + stat.id)
                                        Text(stat.detail).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                            .fixedSize(horizontal: false, vertical: true)
                                    }
                                    .frame(maxWidth: .infinity, minHeight: 100, alignment: .leading)
                                    .padding(10)
                                    .background(statisticBackground(stat.id), in: .rect(cornerRadius: 15))
                                }
                            }
                        }
                    }
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 11) {
                            Text("المصحف بتاريخ حفظه").font(quranFont(17, bold: true))
                            Text("المحفوظ مصمت، المراجَع بنقطة، المستحق بخط مائل، وورد اليوم بإطار")
                                .font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            QuranPageMap(pages: value.pages, dates: value.pageDates, shades: value.shades, rows: value.mapRows) {
                                page = $0
                                showPage = true
                            }
                            dateScale(value)
                        }
                    }
                } else if let error {
                    Text(error)
                    // AU-95: one failed read used to leave this page dead.
                    Button { self.error = nil; attempt += 1 } label: { Text("أعِد المحاولة").frame(minHeight: 44).contentShape(Rectangle()) }
                        .accessibilityIdentifier("quran-journey-retry")
                }
            }
            .padding(16)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .tint(theme.color("review"))
        .task(id: attempt) {
            do { value = try await service.journeyLog() }
            catch { self.error = quranUserMessage(error) }
        }
        .sheet(isPresented: $showPage) {
            VStack(alignment: .leading, spacing: 16) {
                Text("الوجه " + service.numerals.string(page)).font(quranSerif(26))
                Text(value?.pageDates[page].map { "حُفظ في " + $0 } ?? "لم يكتمل حفظه بعد").font(quranFont(15))
                Button { showPage = false; reader = page } label: { Text("افتح في المصحف").frame(minHeight: 44).contentShape(Rectangle()) }
                Button { showPage = false } label: { Text("تمّ").frame(minHeight: 44).contentShape(Rectangle()) }
            }
            .padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
            .foregroundStyle(theme.ink)
            .background(theme.surface)
            .presentationDetents([.height(260)])
            .environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(isPresented: Binding(get: { reader != nil }, set: { if !$0 { reader = nil } })) {
            QuranMushafView(service: service, initialPage: reader ?? page, close: { reader = nil })
        }
    }

    private func forecastHeadline(_ value: QuranUIJourney) -> String {
        if value.forecastDay != nil {
            return "بوتيرتك في آخر ٢٨ يومًا، تختم بإذن الله نحو " + value.actual
        }
        if value.actual == "ختمت القرآن" { return "حفظت صفحات القرآن كلها" }
        return value.actual
    }

    private func statisticBackground(_ id: String) -> Color {
        switch id {
        case "hifz", "recited": theme.color("reviewTint")
        case "days", "work": theme.color("gold").opacity(0.22)
        default: theme.color("gold").opacity(0.12)
        }
    }

    private func dateScale(_ value: QuranUIJourney) -> some View {
        VStack(spacing: 6) {
            Capsule()
                .fill(LinearGradient(
                    colors: [theme.color("memorized").opacity(0.4), theme.color("memorized")],
                    startPoint: UnitPoint(x: 0, y: 0.5), endPoint: UnitPoint(x: 1, y: 0.5)
                ))
                .frame(height: 7)
            HStack(alignment: .top, spacing: 8) {
                Text(value.oldestPageDate.map { "الأقدم: " + $0 } ?? "لا حفظ مؤرخ بعد")
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value.newestPageDate.map { "الأحدث: " + $0 } ?? "")
                    .frame(maxWidth: .infinity, alignment: .trailing)
            }
            .font(quranFont(11))
            .foregroundStyle(theme.secondaryInk)
            .fixedSize(horizontal: false, vertical: true)
        }
        .accessibilityElement(children: .combine)
    }

    /// The journey climbs from the first day (right) towards the khatma (top left); named quarter rules,
    /// the area already held, and one gold bead for each juz still ahead.
    private func journeyChart(_ value: QuranUIJourney) -> some View {
        VStack(spacing: 7) {
            Canvas { context, size in
                let firstDay = value.points.first?.day
                let today = value.points.last?.day
                let axisInset: CGFloat = 76
                let plotWidth = max(1, size.width - axisInset)
                let past = max(1, firstDay.flatMap { first in today.map { first.quranDistance(to: $0) } } ?? 1)
                let pastWidth = value.forecastDay == nil ? plotWidth : plotWidth / 2
                let top: CGFloat = 14
                let height = max(1, size.height - top - 10)
                func y(_ remaining: Int) -> CGFloat { top + CGFloat(remaining) / 604 * height }
                func point(_ item: QuranUIJourneyPoint) -> CGPoint {
                    let elapsed = CGFloat(firstDay?.quranDistance(to: item.day) ?? 0)
                    return CGPoint(x: axisInset + plotWidth - pastWidth * elapsed / CGFloat(past), y: y(item.remaining))
                }

                for (remaining, label) in [(0, "الختمة"), (151, "ثلاثة أرباع"), (302, "النصف"), (453, "الربع")] {
                    var guide = Path()
                    guide.move(to: CGPoint(x: axisInset, y: y(remaining)))
                    guide.addLine(to: CGPoint(x: size.width, y: y(remaining)))
                    context.stroke(guide, with: .color(theme.line), style: StrokeStyle(lineWidth: 0.8, dash: [3, 3]))
                    context.draw(Text(label).font(quranFont(11)).foregroundStyle(theme.secondaryInk),
                        at: CGPoint(x: axisInset - 8, y: y(remaining) - 7), anchor: .trailing)
                }

                guard let firstPoint = value.points.first, let last = value.points.last else { return }
                var path = Path()
                for (index, item) in value.points.enumerated() {
                    if index == 0 { path.move(to: point(item)) } else { path.addLine(to: point(item)) }
                }
                var area = path
                area.addLine(to: CGPoint(x: point(last).x, y: size.height))
                area.addLine(to: CGPoint(x: point(firstPoint).x, y: size.height))
                area.closeSubpath()
                context.fill(area, with: .color(theme.color("reviewTint")))
                context.stroke(path, with: .color(theme.color("review")), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))

                let now = point(last)
                if value.forecastDay != nil {
                    let goal = CGPoint(x: axisInset, y: top)
                    var estimate = Path()
                    estimate.move(to: now)
                    estimate.addLine(to: goal)
                    context.stroke(estimate, with: .color(theme.color("review").opacity(0.7)), style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
                    let held = 604 - last.remaining
                    for juz in 1...30 where Double(juz) * 604 / 30 > Double(held) + 4 {
                        let fraction = (Double(juz) * 604 / 30 - Double(held)) / Double(max(1, last.remaining))
                        let bead = CGPoint(x: now.x + (goal.x - now.x) * fraction, y: now.y + (goal.y - now.y) * fraction)
                        context.fill(Path(ellipseIn: CGRect(x: bead.x - 3.5, y: bead.y - 3.5, width: 7, height: 7)), with: .color(theme.color("hifz")))
                    }
                }
                context.fill(Path(ellipseIn: CGRect(x: now.x - 8, y: now.y - 8, width: 16, height: 16)), with: .color(theme.surface))
                context.stroke(Path(ellipseIn: CGRect(x: now.x - 8, y: now.y - 8, width: 16, height: 16)), with: .color(theme.color("review")), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: now.x - 5, y: now.y - 5, width: 10, height: 10)), with: .color(theme.color("review")))
            }
            .frame(height: 190)
            .accessibilityLabel("تبقّى " + service.faceCount(value.remaining) + " من القرآن")

            HStack(alignment: .top, spacing: 6) {
                axisDate("البداية", value.first)
                axisDate("اليوم، " + service.faceCount(604 - value.remaining), value.today)
                axisDate("الختمة", value.forecastDay == nil ? (value.actual == "ختمت القرآن" ? "تمّت" : "غير متاحة") : value.actual)
            }

            HStack(spacing: 12) {
                legend("في صدرك") { Capsule().fill(theme.color("review")).frame(width: 16, height: 3) }
                if value.forecastDay != nil {
                    legend("تقدير بوتيرتك") {
                        HStack(spacing: 2) {
                            Capsule().fill(theme.color("review").opacity(0.7)).frame(width: 5, height: 3)
                            Capsule().fill(theme.color("review").opacity(0.7)).frame(width: 5, height: 3)
                        }
                    }
                    legend("تمام جزء") { Circle().fill(theme.color("hifz")).frame(width: 7, height: 7) }
                }
                Spacer(minLength: 0)
            }
            .font(quranFont(11))
            .foregroundStyle(theme.secondaryInk)
            .accessibilityHidden(true)
        }
    }

    private func axisDate(_ title: String, _ date: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).font(quranFont(11, bold: true))
            Text(date).font(quranFont(11)).fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .multilineTextAlignment(.leading)
    }

    private func legend<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) { mark(); Text(text) }
    }
}
