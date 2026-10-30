import SwiftUI
import MadarCore
import MadarDesign

struct DiaryIntentionsView:View {
    @Bindable var app:AppSession
    let day:GregorianDay
    let evening:Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var rows:[DiaryIntention]=[]
    @State private var text=""
    @State private var editing:UUID?
    @State private var busy=false
    @State private var failure:String?
    @State private var saved=false
    @State private var confirmDiscard=false
    @FocusState private var focused:Bool
    private var service:AppDiaryService{.init(app:app)}
    private var hasUnsavedInput:Bool {
        if let editing, let row=rows.first(where:{$0.id==editing}) { return text != row.text }
        return !text.isEmpty
    }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    Text(evening ? "حصيلة النيّات" : "نيّة اليوم").font(DiaryType.title)
                    MadarDateLabel(service.bothDates(day,calendar:FirstCalendar(rawValue:app.string("core.firstCalendar")) ?? .hijri)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if evening {Text("كيف مضت نيّتك؟ اختر ما يصف يومك.").font(DiaryType.writing)}
                    ForEach(rows){row in
                        VStack(alignment:.leading,spacing:10){
                            HStack(alignment:.top){Text(row.text).font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading);Button("عدّل"){editing=row.id;text=row.text;focused=true}.font(DiaryType.label).frame(minHeight:44).accessibilityIdentifier("diary-niyya-edit-"+row.id.uuidString)}
                            HStack(spacing:6){ForEach([("done","تمّت"),("partial","جزئيًا"),("notEasy","ما تيسّرت")],id:\.0){value,title in
                                Button{run{try await service.setIntentionResult(row.id,result:value)}}label:{Text(title).font(DiaryType.label).frame(maxWidth:.infinity,minHeight:44).background(row.result==value ? theme.color("ghad").opacity(0.12):.clear,in:.capsule).overlay{Capsule().stroke(row.result==value ? theme.color("ghad"):theme.line)}}.buttonStyle(.madarPlain).accessibilityIdentifier("diary-niyya-result-"+value+"-"+row.id.uuidString).accessibilityAddTraits(row.result==value ? .isSelected:[])
                            }}
                            if row.result != nil {Button("امسح النتيجة"){run{try await service.setIntentionResult(row.id,result:nil)}}.font(DiaryType.label).frame(minHeight:44).accessibilityIdentifier("diary-niyya-clear-"+row.id.uuidString)}
                        }.padding(16).background(theme.surface,in:.rect(cornerRadius:18)).overlay{RoundedRectangle(cornerRadius:18).stroke(theme.line)}
                    }
                    VStack(alignment:.leading,spacing:12){
                        Text(editing == nil ? "أضف نيّة" : "عدّل النيّة").font(DiaryType.heading)
                        TextField("نيّتك بكلماتك",text:$text).font(DiaryType.writing).focused($focused).accessibilityIdentifier("diary-niyya-text")
                        HStack{Button("حفظ النيّة"){let id=editing ?? UUID(),value=text;run{try await service.saveIntention(value,id:id,day:day);text="";editing=nil;focused=false}}.frame(minHeight:44).disabled(text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty).accessibilityIdentifier("diary-niyya-save");if editing != nil{Button("إلغاء التعديل"){editing=nil;text="";focused=false}.frame(minHeight:44)}}.font(MadarTypography.body())
                    }.padding(16).background(theme.surface,in:.rect(cornerRadius:18)).overlay{RoundedRectangle(cornerRadius:18).stroke(theme.line)}
                    if let failure{Text(failure).font(DiaryType.label)}
                    if busy{ProgressView()}
                    if saved,app.undoToken != nil {Button("تراجع عن آخر تعديل"){app.undo();saved=false}.font(MadarTypography.body()).frame(minHeight:44).accessibilityIdentifier("diary-niyya-undo")}
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink).scrollDismissesKeyboard(.interactively).navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItem(placement:.topBarLeading){Button("الصفحة"){if hasUnsavedInput {focused=false;confirmDiscard=true} else {dismiss()}}.disabled(busy).accessibilityIdentifier("diary-niyya-close")}}.tint(theme.accent).toolbarBackground(theme.background,for:.navigationBar)
                .interactiveDismissDisabled(hasUnsavedInput || busy)
                .confirmationDialog("تتجاهل النيّة؟",isPresented:$confirmDiscard,titleVisibility:.visible){
                    Button("تجاهل المسودة",role:.destructive){text="";editing=nil;dismiss()}.accessibilityIdentifier("diary-niyya-discard")
                    Button("أكمل الكتابة"){}.accessibilityIdentifier("diary-niyya-continue")
                } message:{Text("لم تحفظ التغييرات على النيّة.")}
                .task(id:app.prayerRevision){load()}.disabled(busy)
        }
    }
    private func load(){do{rows=try service.intentions(day);failure=nil}catch{failure=madarUserMessage(error)}}
    private func run(_ action:@escaping @MainActor () async throws -> Void){busy=true;Task{@MainActor in defer{busy=false};do{try await action();saved=true;load()}catch{failure=madarUserMessage(error)}}}
}

/// OR-15 (owner, 27 Oct 2026): the current page stays; one slim arc from Fajr to Isha ties morning and evening.
/// The sun walks it by day and a crescent rests on it after Maghrib.
struct DiaryDayArcView:View {
    let arc:DiaryDayArc
    @Environment(\.roomTheme) private var theme
    var body:some View {
        Canvas{context,size in
            let inset=20.0,base=size.height-8,lift=size.height-18
            func point(_ t:Double)->CGPoint{
                // RTL: Fajr sits on the trailing (right) edge, Isha on the leading edge.
                let x=size.width-inset-t*(size.width-2*inset)
                return .init(x:x,y:base-lift*4*t*(1-t))
            }
            var path=Path();path.move(to:point(0));for i in 1...40 {path.addLine(to:point(Double(i)/40))}
            context.stroke(path,with:.color(theme.line),style:.init(lineWidth:1,dash:[2,4]))
            var walked=Path();walked.move(to:point(0));for i in 1...40 where Double(i)/40<=arc.progress {walked.addLine(to:point(Double(i)/40))};walked.addLine(to:point(arc.progress))
            context.stroke(walked,with:.color(theme.accent.opacity(0.7)),style:.init(lineWidth:1.6,lineCap:.round))
            for m in arc.marks {let c=point(m);context.fill(Path(ellipseIn:.init(x:c.x-2.5,y:c.y-2.5,width:5,height:5)),with:.color(m<=arc.progress ? theme.accent:theme.line))}
            let c=point(arc.progress)
            if arc.night {
                let r=8.5;var moon=Path(ellipseIn:.init(x:c.x-r,y:c.y-r,width:2*r,height:2*r))
                moon=moon.subtracting(Path(ellipseIn:.init(x:c.x-r*0.35,y:c.y-r*1.15,width:2*r,height:2*r)))
                context.fill(moon,with:.color(theme.color("pencil")))
            } else {
                context.fill(Path(ellipseIn:.init(x:c.x-11,y:c.y-11,width:22,height:22)),with:.color(theme.color("highlight").opacity(0.7)))
                context.fill(Path(ellipseIn:.init(x:c.x-5.5,y:c.y-5.5,width:11,height:11)),with:.color(theme.accent))
            }
        }.frame(height:34).accessibilityElement().accessibilityLabel(arc.night ? "مساء اليوم":"اليوم بين الفجر والعشاء").accessibilityIdentifier("diary-day-arc")
    }
}
