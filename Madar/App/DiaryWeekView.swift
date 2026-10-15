import SwiftUI
import MadarCore
import MadarDesign

struct DiaryWeekView:View {
    @Bindable var app:AppSession
    let day:GregorianDay
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var days:[DiaryDaySummary]=[]
    @State private var reader:GregorianDay?
    @State private var writing=false
    @State private var failure:String?
    private var service:AppDiaryService{.init(app:app)}
    var body:some View {
        NavigationStack {
            ScrollView {VStack(alignment:.leading,spacing:16){
                Text("صندوق الأسبوع").font(DiaryType.title)
                Text("ارجع إلى ما كتبت، ثم اكتب ما تختاره عن أسبوعك.").font(DiaryType.writing)
                if days.isEmpty {Text("لم تُكتب صفحات هذا الأسبوع بعد.").font(DiaryType.writing)}
                ForEach(days){row in Button{reader=row.day}label:{VStack(alignment:.leading,spacing:8){Text(service.dateTitle(row.day,calendar:FirstCalendar(rawValue:app.string("core.firstCalendar")) ?? .hijri)).font(DiaryType.label);Text(row.excerpt).font(DiaryType.writing).lineLimit(4)}.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(theme.surface,in:.rect(cornerRadius:16)).contentShape(.rect)}.buttonStyle(.plain).accessibilityIdentifier("diary-week-day-"+row.id)}
                Button("اكتب عن أسبوعك"){writing=true}.font(DiaryType.heading).frame(minHeight:54).accessibilityIdentifier("diary-week-write")
                if let failure{Text(failure).font(DiaryType.label)}
            }.padding(18)}.background(theme.background).foregroundStyle(theme.ink).navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.topBarLeading){Button("الصفحة"){dismiss()}.accessibilityIdentifier("diary-week-close")}}.tint(theme.accent)
                .task{do{days=try service.weekDays(ending:day)}catch{failure=error.localizedDescription}}
                .sheet(isPresented:Binding(get:{reader != nil},set:{if !$0{reader=nil}})){if let reader{DiaryDayView(app:app,day:reader).environment(\.roomTheme,theme)}}
                .sheet(isPresented:$writing){DiaryTextEditor(app:app,margin:nil).environment(\.roomTheme,theme)}
        }
    }
}
struct DiaryFridayFrame:Shape {
    func path(in rect:CGRect)->Path {
        var p=Path();p.addRoundedRect(in:rect.insetBy(dx:2,dy:2),cornerSize:CGSize(width:6,height:6));p.addRoundedRect(in:rect.insetBy(dx:6,dy:6),cornerSize:CGSize(width:3,height:3))
        for x in [rect.minX+6,rect.maxX-6] {p.move(to:CGPoint(x:x,y:rect.minY));p.addLine(to:CGPoint(x:x+6,y:rect.minY+6));p.addLine(to:CGPoint(x:x,y:rect.minY+12));p.addLine(to:CGPoint(x:x-6,y:rect.minY+6));p.closeSubpath()};return p
    }
}

struct DiaryRibbonShape:Shape {
    func path(in r:CGRect)->Path {Path{p in p.move(to:r.origin);p.addLine(to:CGPoint(x:r.maxX,y:0));p.addLine(to:CGPoint(x:r.maxX,y:r.maxY));p.addLine(to:CGPoint(x:r.midX,y:r.maxY-9));p.addLine(to:CGPoint(x:0,y:r.maxY));p.closeSubpath()}}
}
