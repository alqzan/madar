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
                QuranScreenHeader(title: "السجلّ", close: close); QuranLogTabs(selection: $selection)
                if let value {
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("رحلة الحفظ").font(quranFont(17, bold: true))
                            Text("ما في صدرك من القرآن، والختمة في الأعلى").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                            journeyChart(value)
                            MadarDateLabel("بالخطة: " + value.planned).font(quranFont(13, bold: true))
                            MadarDateLabel("بوتيرتك: " + value.actual).font(quranFont(13, bold: true)).accessibilityIdentifier("quran-journey-forecast")
                            Text(value.explanation).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                        }
                    }
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("منذ البداية").font(quranFont(17, bold: true))
                            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 9) {
                                ForEach(value.stats) { stat in
                                    VStack(alignment: .leading, spacing: 5) {
                                        Text(stat.title).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                        Text(stat.value).font(quranSerif(25)).accessibilityIdentifier("quran-journey-" + stat.id)
                                        Text(stat.detail).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                                    }.frame(maxWidth: .infinity, minHeight: 100, alignment: .leading).padding(10).background(theme.color("reviewTint"), in: .rect(cornerRadius: 15))
                                }
                            }
                        }
                    }
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("المصحف بتاريخ حفظه").font(quranFont(17, bold: true))
                            Text("المحفوظ مصمت، المراجَع بنقطة، المستحق بخط مائل، وورد اليوم بإطار").font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            QuranPageMap(pages: value.pages, dates: value.pageDates, shades: value.shades) { page = $0; showPage = true }
                            Stepper("الوجه " + service.numerals.string(page), value: $page, in: 1...604).font(quranFont(14))
                            Button("تفاصيل الوجه") { showPage = true }.frame(minHeight: 44).accessibilityIdentifier("quran-journey-page")
                        }
                    }
                } else if let error {
                    Text(error)
                    // AU-95: one failed read used to leave this page dead.
                    Button("أعِد المحاولة") { self.error = nil; attempt += 1 }.frame(minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("quran-journey-retry")
                }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review"))
            .task(id: attempt) { do { value = try await service.journeyLog() } catch { self.error = quranUserMessage(error) } }
            .sheet(isPresented: $showPage) {
                VStack(alignment: .leading, spacing: 16) {
                    Text("الوجه " + service.numerals.string(page)).font(quranSerif(26))
                    Text(value?.pageDates[page].map { "حُفظ في " + $0 } ?? "لم يكتمل حفظه بعد").font(quranFont(15))
                    Button("افتح في المصحف") { showPage = false; reader = page }.frame(minHeight: 44)
                    Button("تمّ") { showPage = false }.frame(minHeight: 44)
                }.padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(theme.ink).background(theme.surface).presentationDetents([.height(260)]).environment(\.layoutDirection, .rightToLeft)
            }
            .fullScreenCover(isPresented: Binding(get: { reader != nil }, set: { if !$0 { reader = nil } })) { QuranMushafView(service: service, initialPage: reader ?? page, close: { reader = nil }) }
    }
    /// Canonical «رحلة الحفظ»: the line climbs from the first day (right) towards the khatma (top left); quarter rules
    /// are named, the area held is shaded, and each juz still ahead is a gold bead on the dashed estimate.
    private func journeyChart(_ v: QuranUIJourney) -> some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                // As in the design, the days so far fill the right half and the estimate the left, so a short past is never squeezed.
                let firstDay = v.points.first?.day, today = v.points.last?.day
                let past = max(1, firstDay.flatMap { f in today.map { f.quranDistance(to: $0) } } ?? 1)
                let pastWidth = v.forecastDay == nil ? size.width : size.width / 2
                let top: CGFloat = 14, height = size.height - top
                func y(_ remaining: Int) -> CGFloat { top + CGFloat(remaining) / 604 * height }
                func point(_ p: QuranUIJourneyPoint) -> CGPoint { CGPoint(x: size.width - pastWidth * CGFloat(firstDay?.quranDistance(to: p.day) ?? 0) / CGFloat(past), y: y(p.remaining)) }
                for (n, name) in [(0, "الختمة"), (151, "ثلاثة أرباع"), (302, "النصف"), (453, "الربع")] {
                    var line = Path(); line.move(to: CGPoint(x: 0, y: y(n))); line.addLine(to: CGPoint(x: size.width, y: y(n)))
                    context.stroke(line, with: .color(theme.line), style: StrokeStyle(lineWidth: 0.7, dash: [3, 3]))
                    context.draw(Text(name).font(quranFont(10)).foregroundStyle(theme.secondaryInk), at: CGPoint(x: 2, y: y(n) - 7), anchor: .leading)
                }
                guard let firstPoint = v.points.first, let last = v.points.last else { return }
                var path = Path()
                for (i, p) in v.points.enumerated() { if i == 0 { path.move(to: point(p)) } else { path.addLine(to: point(p)) } }
                var area = path; area.addLine(to: CGPoint(x: point(last).x, y: size.height)); area.addLine(to: CGPoint(x: point(firstPoint).x, y: size.height)); area.closeSubpath()
                context.fill(area, with: .color(theme.color("reviewTint")))
                context.stroke(path, with: .color(theme.color("review")), style: StrokeStyle(lineWidth: 2.2, lineCap: .round, lineJoin: .round))
                let now = point(last)
                if v.forecastDay != nil {
                    let goal = CGPoint(x: 0, y: top)
                    var tail = Path(); tail.move(to: now); tail.addLine(to: goal)
                    context.stroke(tail, with: .color(theme.color("review").opacity(0.7)), style: StrokeStyle(lineWidth: 1.6, dash: [4, 4]))
                    // One bead per juz still ahead, placed where the estimate crosses its page count.
                    let held = 604 - last.remaining
                    for juz in 1...30 where Double(juz) * 604 / 30 > Double(held) + 4 {
                        let t = (Double(juz) * 604 / 30 - Double(held)) / Double(max(1, last.remaining))
                        let c = CGPoint(x: now.x + (goal.x - now.x) * t, y: now.y + (goal.y - now.y) * t)
                        context.fill(Path(ellipseIn: CGRect(x: c.x - 3.5, y: c.y - 3.5, width: 7, height: 7)), with: .color(theme.color("hifz")))
                    }
                }
                context.fill(Path(ellipseIn: CGRect(x: now.x - 8, y: now.y - 8, width: 16, height: 16)), with: .color(theme.surface))
                context.stroke(Path(ellipseIn: CGRect(x: now.x - 8, y: now.y - 8, width: 16, height: 16)), with: .color(theme.color("review")), lineWidth: 2)
                context.fill(Path(ellipseIn: CGRect(x: now.x - 5, y: now.y - 5, width: 10, height: 10)), with: .color(theme.color("review")))
            }.frame(height: 200).accessibilityLabel("تبقّى " + service.faceCount(v.remaining) + " من القرآن")
            HStack {
                Text(v.first); Spacer()
                Text("اليوم، " + service.faceCount(604 - v.remaining)).font(quranFont(11, bold: true)).foregroundStyle(theme.ink); Spacer()
                Text(v.forecastDay == nil ? "الختمة" : "الختمة تقديرًا")
            }.font(quranFont(11)).foregroundStyle(theme.secondaryInk)
            HStack(spacing: 14) {
                legend("في صدرك") { Capsule().fill(theme.color("review")).frame(width: 16, height: 3) }
                if v.forecastDay != nil {
                    legend("تقدير بوتيرتك") { Capsule().fill(theme.color("review").opacity(0.7)).frame(width: 5, height: 3); Capsule().fill(theme.color("review").opacity(0.7)).frame(width: 5, height: 3) }
                    legend("تمام جزء") { Circle().fill(theme.color("hifz")).frame(width: 7, height: 7) }
                }
                Spacer(minLength: 0)
            }.font(quranFont(11)).foregroundStyle(theme.secondaryInk).accessibilityHidden(true)
        }
    }
    private func legend<Mark: View>(_ text: String, @ViewBuilder mark: () -> Mark) -> some View {
        HStack(spacing: 5) { HStack(spacing: 2) { mark() }; Text(text) }
    }
}
