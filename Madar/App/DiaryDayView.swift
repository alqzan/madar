import SwiftUI
import MadarCore
import MadarDesign

struct DiaryDayView: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var selected: GregorianDay?
    @State private var page: DiaryDisplayDay?
    @State private var failure: String?
    @State private var writing = false
    @State private var retry = 0
    @State private var intentions:[DiaryIntention]=[]
    @State private var intentionsOpen=false
    @State private var niyyaSaved=false
    private var shownDay: GregorianDay { selected ?? day }
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var today: GregorianDay { (try? service.currentDay()) ?? day }
    private var first: FirstCalendar { FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri }
    private var secondInk: Color { switch app.string("notes.secondInk") { case "green": theme.color("ghad"); case "brown": theme.color("autoInkText"); default: theme.color("pencil") } }
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    Text(service.weekday(shownDay) + " · " + service.dateTitle(shownDay, calendar: first == .hijri ? .gregorian : .hijri))
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    Text(service.dateTitle(shownDay, calendar: first)).font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)).accessibilityIdentifier("diary-day-title")
                    HStack(spacing: 6) {
                        dateChoice("اليوم", id: "today", value: today)
                        dateChoice("أمس", id: "yesterday", value: today.adding(days: -1))
                        dateChoice("قبل سنة", id: "year", value: aYearAgo)
                        Spacer(minLength: 0)
                        if shownDay == today { Text("حتى الآن").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                    }
                }.padding(.horizontal, 18).padding(.bottom, 12)
                if shownDay == today || !intentions.isEmpty {
                    Button {intentionsOpen=true} label:{
                        HStack(alignment:.firstTextBaseline,spacing:10){Text("النيّة").font(DiaryType.label).foregroundStyle(theme.accent);Text(intentions.first?.text ?? "أضف نيّتك لليوم").font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading).lineLimit(2);Image(systemName:"chevron.backward").font(.caption)}.padding(.horizontal,18).frame(minHeight:54).contentShape(.rect)
                    }.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-open")
                }
                GeometryReader { geometry in ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        if let page {
                            ForEach(page.lines.filter{$0.kind != "intention"}) { line in
                                lineRow(line, page: page)
                                ForEach(page.media.filter { $0.entryID == line.id }) { media in DiaryMediaCard(app: app, media: media, transcript: line.text) }
                            }
                            if !page.media.contains(where: { $0.id == page.photoID }), let data = page.photo, let image = UIImage(data: data) {
                                Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 150).padding(8).background(theme.surface)
                                    .overlay(alignment: .top) { Rectangle().fill(theme.line).frame(width: 48, height: 16).rotationEffect(.degrees(-5)).offset(y: -8) }
                                    .rotationEffect(.degrees(-2)).shadow(color: theme.ink.opacity(0.1), radius: 5, y: 5)
                                    .padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .center).accessibilityLabel("صورة من هذا اليوم")
                            }
                            if page.lines.isEmpty && page.photo == nil { Text(shownDay == today ? "صفحة تنتظر سطرك." : "لم تُكتب سطور في هذا اليوم.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 40).padding(.horizontal, 54) }
                        } else if failure == nil { ProgressView("تُفتح الصفحة…").padding(30) }
                        if let failure {
                            VStack(alignment: .leading, spacing: 10) { Text(failure).font(MadarTypography.body()); Button("حاول مرة أخرى") { retry += 1 }.frame(minHeight: 44) }.padding(20)
                        }
                        Spacer(minLength: 70)
                    }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).frame(minHeight:geometry.size.height,alignment:.topLeading).background {
                        Canvas { context, size in
                            var rules = Path()
                            for y in stride(from: 14.0, through: size.height, by: 34) { rules.move(to: .init(x: 0, y: y)); rules.addLine(to: .init(x: size.width, y: y)) }
                            context.stroke(rules, with: .color(theme.line), lineWidth: 0.7)
                            var margin = Path(); margin.move(to: .init(x: size.width-50, y: 0)); margin.addLine(to: .init(x: size.width-50, y: size.height))
                            context.stroke(margin, with: .color(theme.color("margin")), lineWidth: 1)
                        }
                    }
                }
                }
            }.background(theme.background).foregroundStyle(theme.ink)
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    HStack(spacing:10){
                        Button { writing = true } label: { Label(shownDay == today ? "اكتب" : "اكتب في هامشها", systemImage: "pencil").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(service.intentionEvening(shownDay) && shownDay==today ? theme.ink:theme.background).background(service.intentionEvening(shownDay) && shownDay==today ? theme.surface:theme.ink,in:.capsule) }.buttonStyle(.plain).accessibilityIdentifier("diary-day-write")
                        if shownDay==today,!intentions.isEmpty {Button{intentionsOpen=true}label:{Text("حصيلة النيّات").font(DiaryType.label).frame(minHeight:54).padding(.horizontal,16).foregroundStyle(service.intentionEvening(shownDay) ? theme.background:theme.ink).background(service.intentionEvening(shownDay) ? theme.ink:theme.surface,in:.capsule).overlay{Capsule().stroke(theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-evening")}
                    }.padding(.horizontal,18).padding(.vertical,8).background(theme.background)
                }
                .toolbar {
                    ToolbarItem(placement:.topBarTrailing){if niyyaSaved,app.undoToken != nil{Button("تراجع"){app.undo();niyyaSaved=false}.accessibilityIdentifier("diary-day-niyya-undo")}}
                    ToolbarItem(placement: .topBarLeading) { Button { dismiss() } label: { Label("المذكرات", systemImage: "chevron.backward") }.accessibilityIdentifier("diary-day-close") }
                }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .sheet(isPresented:$intentionsOpen){DiaryIntentionsView(app:app,day:shownDay,evening:service.intentionEvening(shownDay)).environment(\.roomTheme,theme)}
                .sheet(isPresented: $writing) { DiaryTextEditor(app: app, margin: shownDay == today ? nil : shownDay).environment(\.roomTheme, theme) }
                .task(id: shownDay.description + ":" + String(app.prayerRevision) + ":" + String(retry)) {
                    do { try await service.prepareClosedDay(shownDay); page = try service.day(shownDay); intentions=try service.intentions(shownDay); failure = nil }
                    catch { page = nil; failure = error.localizedDescription }
                }
        }
    }
    private var aYearAgo: GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        return calendar.date(byAdding: .year, value: -1, to: today.date(in: app.activePlace.timeZone)).map { GregorianDay.containing($0, in: app.activePlace.timeZone) } ?? today.adding(days: -365)
    }
    private func dateChoice(_ title: String, id: String, value: GregorianDay) -> some View {
        Button { selected = value } label: { Text(title).font(DiaryType.label).frame(minHeight: 44).padding(.horizontal, 12).background(shownDay == value ? theme.surface : .clear, in: .rect(topLeadingRadius: 10, topTrailingRadius: 10)).overlay { UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(shownDay == value ? theme.color("ink3Text") : theme.line) } }
            .buttonStyle(.plain).accessibilityIdentifier("diary-day-" + id).accessibilityAddTraits(shownDay == value ? .isSelected : [])
    }
    private func lineRow(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        let auto = ["salah", "quran"].contains(line.kind)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(service.time(line.at)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text")).frame(width: 38, alignment: .center)
            VStack(alignment: .leading, spacing: 5) {
                Text(line.text).font(.custom("thmanyahseriftext-Regular", size: auto ? 17 : 19, relativeTo: .body)).lineSpacing(11).italic(auto || line.kind == "margin")
                    .textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
                    .contextMenu {if shownDay==today,["normal","late","ghad"].contains(line.kind),!line.text.isEmpty {Button("اجعلها نيّة اليوم"){Task{do{try await service.saveIntention(line.text,day:shownDay);niyyaSaved=true}catch{failure=error.localizedDescription}}}}}
                if line.kind == "late" { Text("كُتبت لاحقًا").font(DiaryType.label) }
                if line.kind == "margin" {
                    Text("هامش · " + (page.marginDays[line.id].map { service.dateTitle($0, calendar: .gregorian) } ?? "تاريخ الكتابة غير متاح")).font(DiaryType.label)
                }
                if auto { Text(line.kind == "salah" ? "الصلاة" : "القرآن").font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)) }
            }.foregroundStyle(line.kind == "margin" ? secondInk : line.kind == "late" ? theme.color("late") : auto ? theme.color("autoInkText") : theme.ink)
        }.padding(.leading, 6).padding(.trailing, 18).padding(.vertical, 10).frame(minHeight: 34)
    }
}
