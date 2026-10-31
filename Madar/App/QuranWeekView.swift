import SwiftUI
import Combine
import MadarDesign

struct QuranWeekView: View {
    let service: AppQuranService
    let close: () -> Void
    var selection: Binding<QuranLogTab>? = nil
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var type
    @State private var week: QuranUIWeek?
    @State private var selected: QuranUIWeekDay?
    @State private var error: String?
#if DEBUG
    @State private var loadCount = 0
#endif
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 14) {
                    Button(action: close) { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }.accessibilityLabel("رجوع").accessibilityIdentifier("quran-week-close")
                    Text("السجلّ").font(serif(28)); Spacer()
                }.padding(.vertical, 4)
                if let selection { QuranLogTabs(selection: selection) }
                if let week {
                    if service.app.string("quran.weekLogView") != "summary" { rings(week) }
                    summary(week)
                } else if let error { Text(error).accessibilityIdentifier("quran-week-error"); Button("حاول مرة أخرى", action: load).frame(minHeight: 44).accessibilityIdentifier("quran-week-retry") }
                else { ProgressView().frame(maxWidth: .infinity).padding(50) }
            }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 24)
        }.foregroundStyle(theme.ink).background(theme.background.ignoresSafeArea()).tint(theme.color("review"))
            .task {
                load()
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
                   environment["MADAR_UI_QURAN_WEEK_READ_FAILURE_AFTER_FIRST"] == "1" {
                    await Task.yield()
                    load()
                }
                #endif
            }
            // Left open past midnight, the log follows the day it is now.
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in load() }
            .refreshesAtMadarDay(service.app) { load() }
            .sheet(item: $selected) { day in
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        Text(day.date).font(serif(22))
                        Text(day.rest ? "يوم راحة، مراجعة فقط" : day.active ? "يوم عمل" : "لا جلسات مسجّلة").font(font(15, bold: true))
                        // AU-23: a quiet day says so once, not as two zeros.
                        if day.hifz > 0 || day.review > 0 {
                            Text(day.hifz > 0 ? "حفظت " + service.faceCount(day.hifz, accusative: true) : "لم تحفظ جديدًا").font(font(16))
                            Text(day.review > 0 ? "راجعت " + service.faceCount(day.review, accusative: true) : "لم تراجع").font(font(16)).accessibilityIdentifier("quran-week-day-review")
                        }
                        if day.partialAyahs > 0 { Text(QuranDayCloseCopy.ayahs(day.partialAyahs, digits: service.numerals) + " من وجه لم يكتمل بعد").font(font(14)) }
                        Text("الخارجية لحفظ وجه، والداخلية لمراجعة ثمانية أوجه؛ يوم الراحة لا يدخل في أيام الحفظ.").font(font(13)).foregroundStyle(theme.secondaryInk)
                        Button("تمّ") { selected = nil }.frame(maxWidth: .infinity, minHeight: 44)
                    }.padding(24)
                }.foregroundStyle(theme.ink).background(theme.surface).presentationDetents([.height(400), .large]).presentationDragIndicator(.visible).environment(\.layoutDirection, .rightToLeft)
            }
    }
    private func rings(_ value: QuranUIWeek) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                Text("حلقات آخر سبعة أيام").font(font(17, bold: true))
                Text("أغلقت الحلقتين في " + service.numerals.string(value.closedDays) + " من " + service.numerals.string(value.eligibleDays) + (value.eligibleDays == 1 ? " يوم الحفظ" : value.eligibleDays == 2 ? " يومَي الحفظ" : " أيام الحفظ"))
                    .font(font(14)).accessibilityIdentifier("quran-week-closed")
                if type.isAccessibilitySize {
                    ForEach(value.days) { day in Button { selected = day } label: { Text(day.label + "، حفظ " + faces(day.hifz) + "، مراجعة " + faces(day.review)).font(font(15)).frame(minHeight: 44) }.buttonStyle(.madarPlain) }
                } else {
                    HStack(spacing: 3) {
                        ForEach(value.days) { day in
                            Button { selected = day } label: {
                                VStack(spacing: 9) {
                                    ZStack {
                                        Circle().stroke(theme.color("track"), lineWidth: 4)
                                        Circle().trim(from: 0, to: min(1, Double(day.hifz))).stroke(theme.color("gold"), lineWidth: 4).rotationEffect(.degrees(-90)).scaleEffect(x: -1, y: 1)
                                        Circle().stroke(theme.color("track"), lineWidth: 3).padding(7)
                                        Circle().trim(from: 0, to: min(1, Double(day.review) / 8)).stroke(theme.color("review"), lineWidth: 3).padding(7).rotationEffect(.degrees(-90)).scaleEffect(x: -1, y: 1)
                                        if day.closed { Image(systemName: "checkmark").font(.system(size: 11, weight: .bold)).foregroundStyle(theme.color("reviewText")) }
                                    }.frame(width: 38, height: 38)
                                    Text(day.label).font(font(11, bold: day.today)).foregroundStyle(theme.secondaryInk)
                                }.frame(maxWidth: .infinity, minHeight: 62)
                            }.buttonStyle(.madarPlain).accessibilityLabel(day.label + "، حفظ " + faces(day.hifz) + "، مراجعة " + faces(day.review))
                                .accessibilityIdentifier("quran-week-day-" + day.id)
                        }
                    }
                }
                HStack(spacing: 6) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.color("gold")).frame(width: 9, height: 9); Text("الحفظ من وجه")
                    RoundedRectangle(cornerRadius: 3).fill(theme.color("review")).frame(width: 9, height: 9); Text("المراجعة من ثمانية أوجه")
                }.font(font(11)).foregroundStyle(theme.secondaryInk)
            }
        }
    }
    private func summary(_ value: QuranUIWeek) -> some View {
        card {
            VStack(alignment: .leading, spacing: 12) {
                HStack { Text("ملخّص الأسبوع").font(font(17, bold: true)); Spacer(); Text("مقارنة بالأسبوع الذي قبله").font(font(11)).foregroundStyle(theme.secondaryInk) }
                statistic("الحفظ", amount: faces(value.hifz), change: value.hifzChange, bars: value.days.map { Double($0.hifz) }, color: theme.color("gold"), id: "quran-week-hifz")
                Divider().overlay(theme.line)
                statistic("المراجعة", amount: faces(value.review), change: value.reviewChange, bars: value.days.map { Double($0.review) }, color: theme.color("review"), id: "quran-week-review")
                Divider().overlay(theme.line)
                statistic("أيام العمل", amount: service.numerals.string(value.activeDays) + " من " + service.numerals.string(value.eligibleDays), change: value.activeChange, bars: value.days.map { $0.eligible && $0.active ? 1 : 0 }, color: theme.secondaryInk, id: "quran-week-work")
            }
        }
    }
    private func statistic(_ title: String, amount: String, change: String, bars: [Double], color: Color, id: String) -> some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(font(12)).foregroundStyle(theme.secondaryInk)
                Text(amount).font(serif(25)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier(id)
                Text(change).font(font(11, bold: true)).foregroundStyle(theme.color("reviewText")).fixedSize(horizontal: false, vertical: true)
            }.frame(maxWidth: .infinity, alignment: .leading)
            if !type.isAccessibilitySize {
                HStack(alignment: .bottom, spacing: 3) {
                    ForEach(Array(bars.enumerated()), id: \.offset) { _, value in
                        RoundedRectangle(cornerRadius: 3).fill(value > 0 ? color : theme.color("track")).frame(maxWidth: .infinity).frame(height: max(3, CGFloat(value / max(1, bars.max() ?? 1)) * 44))
                    }
                }.frame(width: 116, height: 44, alignment: .bottom).accessibilityHidden(true)
            }
        }
    }
    private func card<Content: View>(@ViewBuilder content: () -> Content) -> some View { content().padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 24)).shadow(color: theme.ink.opacity(0.04), radius: 14, y: 8) }
    private func faces(_ value: Int) -> String { QuranDayCloseCopy.faces(value, digits: service.numerals) }
    private func font(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body) }
    private func serif(_ size: CGFloat) -> Font { .custom("Amiri-Bold", size: size, relativeTo: .title2) }
    private func load() {
        do {
            #if DEBUG
            loadCount += 1
            let environment = ProcessInfo.processInfo.environment
            if loadCount == 2,
               environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               environment["MADAR_UI_QURAN_WEEK_READ_FAILURE_AFTER_FIRST"] == "1" {
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            week = try service.weeklyLog(); error = nil
        } catch { week = nil; self.error = quranUserMessage(error) }
    }
}
