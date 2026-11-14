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
                ForEach(days){row in Button{reader=row.day}label:{VStack(alignment:.leading,spacing:8){MadarDateLabel(service.bothDates(row.day,calendar:app.diaryFirstCalendar)).font(DiaryType.label);Text(row.excerpt).font(DiaryType.writing).lineLimit(4)}.frame(maxWidth:.infinity,alignment:.leading).padding(16).background(theme.surface,in:.rect(cornerRadius:16)).contentShape(.rect)}.buttonStyle(.madarPlain).accessibilityIdentifier("diary-week-day-"+row.id)}
                Button {writing=true} label: { Text("اكتب عن أسبوعك").font(DiaryType.heading).frame(minHeight:54).contentShape(Rectangle()) }.accessibilityIdentifier("diary-week-write")
                if let failure{Text(failure).font(DiaryType.label)}
            }.padding(18)}.background(theme.background).foregroundStyle(theme.ink).navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.topBarLeading){Button("الصفحة"){dismiss()}.accessibilityIdentifier("diary-week-close")}}.tint(theme.accent)
                .task{do{days=try await service.weekDaysOffMain(ending:day)}catch{failure=madarUserMessage(error)}}
                .sheet(isPresented:Binding(get:{reader != nil},set:{if !$0{reader=nil}})){if let reader{DiaryDayView(app:app,day:reader,showsNavigationTools:false).environment(\.roomTheme,theme).madarSheetErrorAlert(app)}}
                .sheet(isPresented:$writing){if let today=try? service.currentDay(){DiaryDayView(app:app,day:today,focusComposerOnOpen:true,showsNavigationTools:false).environment(\.roomTheme,theme).madarSheetErrorAlert(app)}}
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

/// OR-16 (owner, 27 Oct 2026): Friday and Ramadan each come in three looks the owner picks in the diary settings.
enum DiaryFridayStyle:String {case mihrab,ribbon,medallion
    @MainActor init(_ app:AppSession){self=Self(rawValue:app.string("notes.fridayStyle")) ?? .mihrab}
}
enum DiaryRamadanStyle:String {case night,lantern,paper
    @MainActor init(_ app:AppSession){self=Self(rawValue:app.string("notes.ramadanStyle")) ?? .night}
}
/// A pointed mihrab arch with an inner line, open at the bottom; it stands behind the Friday title.
struct DiaryMihrabShape:Shape {
    func path(in r:CGRect)->Path {
        var p=Path()
        for inset in [0.0,6.0] {
            let a=r.insetBy(dx:inset,dy:inset),shoulder=a.minY+a.height*0.42
            p.move(to:CGPoint(x:a.minX,y:r.maxY));p.addLine(to:CGPoint(x:a.minX,y:shoulder))
            p.addQuadCurve(to:CGPoint(x:a.midX,y:a.minY),control:CGPoint(x:a.minX,y:a.minY+a.height*0.08))
            p.addQuadCurve(to:CGPoint(x:a.maxX,y:shoulder),control:CGPoint(x:a.maxX,y:a.minY+a.height*0.08))
            p.addLine(to:CGPoint(x:a.maxX,y:r.maxY))
        }
        return p
    }
}
/// An eight-point star: two squares, one turned a quarter.
struct DiaryStarShape:Shape {
    func path(in r:CGRect)->Path {
        let c=CGPoint(x:r.midX,y:r.midY),s=min(r.width,r.height)/2*0.72
        var p=Path()
        for turn in [0.0,Double.pi/4] {
            let pts=(0..<4).map{i->CGPoint in let a=turn+Double(i)*Double.pi/2+Double.pi/4;return CGPoint(x:c.x+s*1.414*cos(a)*0.72,y:c.y+s*1.414*sin(a)*0.72)}
            p.addLines(pts);p.closeSubpath()
        }
        return p
    }
}
struct DiaryCrescentShape:Shape {
    func path(in r:CGRect)->Path {
        let d=min(r.width,r.height),o=CGRect(x:r.midX-d/2,y:r.midY-d/2,width:d,height:d)
        return Path(ellipseIn:o).subtracting(Path(ellipseIn:o.offsetBy(dx:d*0.3,dy:-d*0.12)))
    }
}
/// A small hanging lantern: cap, glass body with panes, and a glow.
struct DiaryLanternView:View {
    let gold:Color
    var body:some View {
        Canvas{context,size in
            let w=size.width,h=size.height,mid=w/2
            var chain=Path();chain.move(to:CGPoint(x:mid,y:0));chain.addLine(to:CGPoint(x:mid,y:h*0.14));context.stroke(chain,with:.color(gold),lineWidth:1)
            context.fill(Path(ellipseIn:CGRect(x:mid-w*0.5,y:h*0.3,width:w,height:h*0.6)),with:.color(gold.opacity(0.18)))
            var cap=Path();cap.move(to:CGPoint(x:mid-w*0.22,y:h*0.3));cap.addLine(to:CGPoint(x:mid,y:h*0.14));cap.addLine(to:CGPoint(x:mid+w*0.22,y:h*0.3));cap.closeSubpath();context.fill(cap,with:.color(gold))
            var body=Path();body.move(to:CGPoint(x:mid-w*0.26,y:h*0.32));body.addLine(to:CGPoint(x:mid+w*0.26,y:h*0.32));body.addLine(to:CGPoint(x:mid+w*0.18,y:h*0.82));body.addLine(to:CGPoint(x:mid-w*0.18,y:h*0.82));body.closeSubpath()
            context.fill(body,with:.color(gold.opacity(0.35)));context.stroke(body,with:.color(gold),lineWidth:1.4)
            var panes=Path();panes.move(to:CGPoint(x:mid,y:h*0.32));panes.addLine(to:CGPoint(x:mid,y:h*0.82));context.stroke(panes,with:.color(gold),lineWidth:1)
            context.fill(Path(roundedRect:CGRect(x:mid-w*0.22,y:h*0.82,width:w*0.44,height:h*0.06),cornerRadius:2),with:.color(gold))
        }.accessibilityHidden(true)
    }
}
/// The Ramadan banner in the chosen look. Colours come from existing token pairs: travel navy with diary paper,
/// the lock cover's leather, clasp and text, and the Ramadan accent on the diary surface.
struct DiaryRamadanBanner:View {
    let style:DiaryRamadanStyle
    let dayText:String
    let headline:String
    @Environment(\.roomTheme) private var theme
    private func token(_ key:String,_ fallback:Color)->Color {MadarToken.colors[key] ?? fallback}
    var body:some View {
        let navy=token("rooms.notes.travel.light.ink",.indigo),paper=token("rooms.notes.light.bg",.white)
        let leather=token("rooms.notes.lockCover.leather",.brown),clasp=token("rooms.notes.lockCover.clasp",.yellow),cover=token("rooms.notes.lockCover.text",.white)
        let accent=token(theme.dark ? "rooms.notes.ramadan.accentDark":"rooms.notes.ramadan.accent",theme.accent)
        let (ground,ink,gold):(Color,Color,Color)=switch style {case .night:(navy,paper,clasp);case .lantern:(leather,cover,clasp);case .paper:(theme.surface,theme.ink,accent)}
        HStack(alignment:.center,spacing:14){
            VStack(alignment:.leading,spacing:6){
                Text(dayText).font(DiaryType.label).foregroundStyle(style == .paper ? accent:gold)
                Text(headline).font(.custom("thmanyahserifdisplay-Bold",size:24,relativeTo:.title2)).foregroundStyle(ink)
            }
            Spacer(minLength:8)
            switch style {
            case .night: DiaryCrescentShape().fill(gold).frame(width:38,height:38).accessibilityHidden(true)
            case .lantern: DiaryLanternView(gold:gold).frame(width:44,height:64)
            case .paper: ZStack{Circle().stroke(accent.opacity(0.6),lineWidth:1);DiaryCrescentShape().fill(accent).frame(width:24,height:24)}.frame(width:46,height:46).accessibilityHidden(true)
            }
        }
        .padding(.horizontal,18).padding(.vertical,style == .paper ? 14:18)
        .background{
            ZStack{
                RoundedRectangle(cornerRadius:20).fill(ground)
                if style == .night {
                    Canvas{context,size in for (x,y,r) in [(0.12,0.25,1.2),(0.3,0.7,0.9),(0.48,0.2,1.1),(0.62,0.6,0.8),(0.22,0.45,0.7),(0.55,0.85,1.0)] {context.fill(Path(ellipseIn:CGRect(x:size.width*x,y:size.height*y,width:r*2,height:r*2)),with:.color(paper.opacity(0.7)))}}.allowsHitTesting(false)
                }
                if style == .paper {RoundedRectangle(cornerRadius:20).stroke(accent.opacity(0.35))}
            }
        }
        .accessibilityElement(children:.combine)
    }
}
