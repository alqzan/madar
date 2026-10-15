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
    @FocusState private var focused:Bool
    private var service:AppDiaryService{.init(app:app)}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
                    Text(evening ? "حصيلة النيّات" : "نيّة اليوم").font(DiaryType.title)
                    Text(service.dateTitle(day,calendar:FirstCalendar(rawValue:app.string("core.firstCalendar")) ?? .hijri)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if evening {Text("كيف مضت نيّتك؟ اختر ما يصف يومك.").font(DiaryType.writing)}
                    ForEach(rows){row in
                        VStack(alignment:.leading,spacing:10){
                            HStack(alignment:.top){Text(row.text).font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading);Button("عدّل"){editing=row.id;text=row.text;focused=true}.font(DiaryType.label).frame(minHeight:44).accessibilityIdentifier("diary-niyya-edit-"+row.id.uuidString)}
                            HStack(spacing:6){ForEach([("done","تمّت"),("partial","جزئيًا"),("notEasy","ما تيسّرت")],id:\.0){value,title in
                                Button{run{try await service.setIntentionResult(row.id,result:value)}}label:{Text(title).font(DiaryType.label).frame(maxWidth:.infinity,minHeight:44).background(row.result==value ? theme.color("ghad").opacity(0.12):.clear,in:.capsule).overlay{Capsule().stroke(row.result==value ? theme.color("ghad"):theme.line)}}.buttonStyle(.plain).accessibilityIdentifier("diary-niyya-result-"+value+"-"+row.id.uuidString).accessibilityAddTraits(row.result==value ? .isSelected:[])
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
                .toolbar{ToolbarItem(placement:.topBarLeading){Button("الصفحة"){dismiss()}.disabled(busy).accessibilityIdentifier("diary-niyya-close")}}.tint(theme.accent).toolbarBackground(theme.background,for:.navigationBar)
                .task(id:app.prayerRevision){load()}.disabled(busy)
        }
    }
    private func load(){do{rows=try service.intentions(day);failure=nil}catch{failure=error.localizedDescription}}
    private func run(_ action:@escaping @MainActor () async throws -> Void){busy=true;Task{@MainActor in defer{busy=false};do{try await action();saved=true;load()}catch{failure=error.localizedDescription}}}
}
