import SwiftUI
import MadarCore
import MadarDesign

struct DiaryExportView:View {
    @Bindable var app:AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var phase
    @State private var options=DiaryExportOptions()
    @State private var years:[Int]=[]
    @State private var artifact:DiaryExportArtifact?
    /// Bumped by every clear, so a file finished after the screen moved on is deleted, never kept.
    @State private var generation = 0
    @State private var preview=false
    @State private var busy=false
    @State private var failure:String?
    private var service:AppDiaryService{.init(app:app)}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18){
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" { Button("اختبر الجذر"){app.open(URL(string:"madar://notes")!)}.accessibilityIdentifier("diary-export-root-route") }
#endif
                    Text("تصدير المذكرات").font(DiaryType.title)
                    Text("كلّها أو سنة أو شهر").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    card {
                        HStack{Text("الفترة");Spacer();Picker("السنة",selection:$options.year){Text("كل الأيام").tag(Int?.none);ForEach(years,id:\.self){year in yearOption(year).tag(Optional(year))}}.labelsHidden().accessibilityIdentifier("diary-export-year")}.font(DiaryType.label)
                        if let year = options.year { MadarDateLabel(app.yearLabels(year)) }
                        if options.year != nil {Picker("الشهر الميلادي",selection:$options.month){Text("السنة كاملة").tag(Int?.none);ForEach(1...12,id:\.self){Text(service.digits.string($0)).tag(Optional($0))}}.font(DiaryType.label).accessibilityIdentifier("diary-export-month")}
                        Text("الصيغة").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                        ForEach([("pdf","PDF","الصفحات بالهوامش والصور"),("markdown","Markdown","ملف لكل يوم والمرفقات الأصلية في أرشيف"),("json","JSON لداي ون","نص وصور، وبقية المرفقات محفوظة في الأرشيف")],id:\.0){id,title,subtitle in
                            Button{options.format=id}label:{HStack{VStack(alignment:.leading,spacing:4){Text(title).font(MadarTypography.body());Text(subtitle).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))};Spacer();Image(systemName:options.format==id ? "checkmark.circle.fill":"circle").foregroundStyle(options.format==id ? theme.accent:theme.line)}.frame(minHeight:54).contentShape(.rect)}.buttonStyle(.madarPlain).accessibilityIdentifier("diary-export-format-"+id)
                            if id != "json" {Divider().overlay(theme.line)}
                        }
                    }
                    card {
                        Text("مع المذكرات").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                        Toggle("الهوامش",isOn:$options.margins).accessibilityIdentifier("diary-export-margins")
                        Divider().overlay(theme.line)
                        Toggle("سطور الأقسام",isOn:$options.sources).accessibilityIdentifier("diary-export-sources")
                    }.font(MadarTypography.body()).tint(theme.color("ghad"))
                    if let failure {Text(failure).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}
                    if busy {ProgressView("يجهّز صفحاتك…").frame(maxWidth:.infinity)}
                    Button{prepare()}label:{Text("صدّر").font(DiaryType.heading).frame(maxWidth:.infinity,minHeight:56).foregroundStyle(theme.background).background(theme.ink,in:.capsule)}.buttonStyle(.madarPlain).disabled(busy).accessibilityIdentifier("diary-export-prepare")
                    if let artifact { ready(artifact) }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink).navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItemGroup(placement:.topBarLeading){Button{dismiss()}label:{HStack{Image(systemName:"chevron.backward");Text("رجوع").font(DiaryType.label)}}.disabled(busy).accessibilityIdentifier("diary-export-close")
                }}.tint(theme.accent).toolbarBackground(theme.background,for:.navigationBar)
                .task{do{years=Set(try service.exportPages(.init()).map(\.day.year)+[service.currentDay().year]).sorted(by:>)}catch{failure=madarUserMessage(error)}}
                .onChange(of:options.year){_,_ in options.month=nil;clear()}.onChange(of:options.month){_,_ in clear()}.onChange(of:options.format){_,_ in clear()}.onChange(of:options.margins){_,_ in clear()}.onChange(of:options.sources){_,_ in clear()}
                .onChange(of:phase){_,value in if value == .background {preview=false;clear()}}
                .sheet(isPresented:$preview){if let artifact {DiaryQuickLook(url:artifact.url)}}
                .onDisappear{clear()}
        }
    }
    private func yearOption(_ year:Int)->some View {
        let labels=app.yearLabels(year)
        let primary=Text(labels.primary).font(DiaryType.label)
        let secondary=Text(labels.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
        return Text("\(primary)\n\(secondary)")
            .accessibilityLabel(labels.combined)
    }
    private func ready(_ file:DiaryExportArtifact)->some View {
        VStack(alignment:.leading,spacing:12) {
            Text(file.dayCount == 0 ? "جاهز" : "جاهز: "+PrayerCopy.days(file.dayCount, digits: service.digits)).font(DiaryType.label).accessibilityIdentifier("diary-export-ready")
            if let note=file.omittedNote{Text(note).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("diary-export-omitted")}
            HStack {
                Button("معاينة الملف"){preview=true}.accessibilityIdentifier("diary-export-preview")
                Spacer()
                Button("حفظ أو مشاركة"){Task{do{try await service.shareDiary(file)}catch{failure=madarUserMessage(error)}}}.accessibilityIdentifier("diary-export-share")
            }.font(MadarTypography.body()).frame(minHeight:44)
        }
    }
    private func card<Content:View>(@ViewBuilder _ content:()->Content)->some View{VStack(alignment:.leading,spacing:12,content:content).padding(16).background(theme.surface,in:.rect(cornerRadius:18)).overlay{RoundedRectangle(cornerRadius:18).stroke(theme.line)}}
    private func prepare(){busy=true;failure=nil;clear();let started=generation;Task{@MainActor in await Task.yield();defer{busy=false};do{let made=try service.exportDiary(options);if started == generation {artifact=made}else{try? FileManager.default.removeItem(at:made.url.deletingLastPathComponent())}}catch{failure=madarUserMessage(error)}}}
    private func clear(){generation += 1;if let artifact {try? FileManager.default.removeItem(at:artifact.url.deletingLastPathComponent())};artifact=nil}
}
