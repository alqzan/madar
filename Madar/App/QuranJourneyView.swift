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
    var body: some View {
        ScrollView {
            VStack(spacing: 12) {
                QuranScreenHeader(title: "السجلّ", close: close); QuranLogTabs(selection: $selection)
                if let value {
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("رحلة الحفظ").font(quranFont(17, bold: true))
                            Text("أوجه القرآن الباقية").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
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
                } else if let error { Text(error) }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review"))
            .task { do { value = try await service.journeyLog() } catch { self.error = quranUserMessage(error) } }
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
    private func journeyChart(_ v: QuranUIJourney) -> some View {
        VStack(spacing: 8) {
            Canvas { context, size in
                let firstDay = v.points.first?.day, end = v.forecastDay ?? v.points.last?.day
                let length = max(1, firstDay.flatMap { f in end.map { f.quranDistance(to: $0) } } ?? 1)
                func point(_ p: QuranUIJourneyPoint) -> CGPoint { CGPoint(x: size.width * (1 - CGFloat(firstDay?.quranDistance(to: p.day) ?? 0) / CGFloat(length)), y: (1 - CGFloat(p.remaining) / 604) * size.height) }
                for n in [0, 151, 302, 453, 604] {
                    let y = (1 - CGFloat(n) / 604) * size.height
                    var line = Path(); line.move(to: CGPoint(x: 0, y: y)); line.addLine(to: CGPoint(x: size.width, y: y)); context.stroke(line, with: .color(theme.line), lineWidth: 0.6)
                }
                var path = Path()
                for (i, p) in v.points.enumerated() { if i == 0 { path.move(to: point(p)) } else { path.addLine(to: point(p)) } }
                context.stroke(path, with: .color(theme.color("review")), lineWidth: 2)
                if let last = v.points.last {
                    let p = point(last); context.fill(Path(ellipseIn: CGRect(x: p.x - 4, y: p.y - 4, width: 8, height: 8)), with: .color(theme.color("review")))
                    context.draw(Text("اليوم").font(quranFont(11)).foregroundStyle(theme.secondaryInk), at: CGPoint(x: p.x, y: min(size.height - 16, p.y + 14)))
                    if v.forecastDay != nil { var tail = Path(); tail.move(to: p); tail.addLine(to: CGPoint(x: 0, y: size.height)); context.stroke(tail, with: .color(theme.color("hifz")), style: StrokeStyle(lineWidth: 2, dash: [4, 4])) }
                }
            }.frame(height: 150).accessibilityLabel("تبقّى " + service.faceCount(v.remaining) + " من القرآن")
            HStack { Text("البداية"); Spacer(); Text("تقدير").foregroundStyle(theme.color("hifzText")) }.font(quranFont(11)).foregroundStyle(theme.secondaryInk)
        }
    }
}
