import SwiftUI
import MadarCore
import MadarDesign

/// N2: a fixed, dated timeline. The rail is ornament; every card has a full-size labelled tap target.
struct DiaryEchoesView: View {
    let snapshot: DiaryHomeSnapshot
    let service: AppDiaryService
    let open: (GregorianDay) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var selected = "today"
    var body: some View {
        ScrollViewReader { proxy in
            VStack(alignment: .leading, spacing: 0) {
                ScrollView(.horizontal) {
                    HStack(spacing: 5) {
                        jump("today", "اليوم", proxy: proxy)
                        ForEach(snapshot.echoes, id: \.distance.rawValue) { echo in jump(echo.distance.rawValue, echo.distance.title, proxy: proxy) }
                    }
                }.scrollIndicators(.hidden).padding(.bottom, 16)
                VStack(alignment: .leading, spacing: 4) {
                    Text("أصداء اليوم").font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .largeTitle))
                    Text("كلما نزلت رجعت في الزمن، والورق يصفرّ كلما بَعُد").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }
                .padding(.bottom, 22)
                timelineRow(title: "اليوم", day: snapshot.today, current: true) {
                    Button { open(snapshot.today) } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 6) {
                                Text("صفحة اليوم").font(MadarTypography.section())
                                Text(snapshot.todayPage.lines.isEmpty ? "اكتب ما تيسّر من يومك." : snapshot.todayPage.excerpt).font(.custom("thmanyahseriftext-Regular", size: 17, relativeTo: .body)).lineLimit(2)
                                Text("حتى الآن").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            Image(systemName: "chevron.forward").foregroundStyle(theme.color("ink3Text"))
                        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 24)).overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.line) }
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-echo-today")
                }.id("today")
                ForEach(snapshot.echoes, id: \.distance.rawValue) { echo in
                    let page = snapshot.days.first { $0.day == echo.day }
                    timelineRow(title: page.map { service.distance($0.day, snapshot.today) } ?? "قبل " + echo.distance.title, day: page?.day ?? echo.target, current: false) {
                        if let page { memoryCard(page, distance: echo.distance) }
                        else {
                            Text("لا ذكرى قرب هذا التاريخ").font(MadarTypography.caption()).foregroundStyle(theme.color("ink3Text"))
                                .frame(maxWidth: .infinity, minHeight: 64, alignment: .leading).padding(.horizontal, 16)
                                .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line, style: StrokeStyle(lineWidth: 1, dash: [4, 4])) }
                        }
                    }.id(echo.distance.rawValue)
                }
            }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-echoes")
        }
    }
    private func jump(_ id: String, _ title: String, proxy: ScrollViewProxy) -> some View {
        Button { selected = id; withAnimation { proxy.scrollTo(id, anchor: .top) } } label: {
            Text(title).font(MadarTypography.caption()).padding(.horizontal, 14).frame(minHeight: 44)
                .foregroundStyle(selected == id ? theme.background : theme.ink)
                .background(selected == id ? theme.ink : theme.ink.opacity(0.06), in: .capsule)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-echo-jump-" + id).accessibilityAddTraits(selected == id ? .isSelected : [])
    }
    private func timelineRow<Content: View>(title: String, day: GregorianDay, current: Bool, @ViewBuilder content: () -> Content) -> some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(spacing: 0) {
                Circle().fill(current ? theme.accent : theme.background).frame(width: current ? 22 : 12, height: current ? 22 : 12)
                    .padding(4).overlay { Circle().stroke(current ? theme.accent : theme.color("ink3Text"), lineWidth: 2) }.frame(width: 32, height: 32)
                Rectangle().fill(theme.accent.opacity(0.35)).frame(width: 2).frame(maxHeight: .infinity)
            }.accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 10) {
                ViewThatFits(in: .horizontal) {
                    HStack(alignment: .firstTextBaseline) { Text(title).font(DiaryType.heading); MadarDateLabel(service.bothDates(day)).font(DiaryType.label) }
                    VStack(alignment: .leading, spacing: 3) { Text(title).font(DiaryType.heading); MadarDateLabel(service.bothDates(day)).font(DiaryType.label) }
                }.foregroundStyle(current ? theme.accent : theme.ink)
                content()
            }.padding(.bottom, 30)
        }.fixedSize(horizontal: false, vertical: true)
    }
    private func memoryCard(_ page: DiaryDisplayDay, distance: DiaryEchoDistance) -> some View {
        Button { open(page.day) } label: {
            VStack(alignment: .leading, spacing: 0) {
                if let data = page.photo {
                    DiaryDataThumbnail(data: data, maxPixel: 900) { image in
                        GeometryReader { geometry in image.resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                    }.frame(height: 176)
                }
                VStack(alignment: .leading, spacing: 12) {
                    Text(page.excerpt).font(DiaryType.writing).lineSpacing(8).lineLimit(4).multilineTextAlignment(.leading).frame(maxWidth: .infinity, alignment: .leading)
                    // The row above already shows this day in both calendars; the card adds only where it was written.
                    if let place = page.place { Label(place, systemImage: "mappin").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                }.padding(16)
            }.background(theme.surface).clipShape(.rect(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.line) }
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-echo-" + distance.rawValue)
    }
}
