import SwiftUI
import MadarCore
import MadarDesign

struct DiaryYearbookView:View {
    @Bindable var app:AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.scenePhase) private var phase
    @State private var year:Int?
    @State private var years:[Int]=[]
    @State private var pages:[DiaryExportPage]=[]
    @State private var margins=true
    @State private var sources=true
    @State private var photos=true
    @State private var includeIndex=true
    @State private var artifact:DiaryExportArtifact?
    /// Bumped by every clear, so a file finished after the screen moved on is deleted, never kept.
    @State private var generation = 0
    @State private var preview=false
    @State private var busy=false
    @State private var failure:String?
    @State private var attempt = 0
#if DEBUG
    @State private var loadCount = 0
#endif
    private var service:AppDiaryService{.init(app:app)}
    private var selectedYear:Int{year ?? (try? service.currentDay().year) ?? Calendar.current.component(.year,from:.now)}
    private var bookColor:Color{MadarToken.colors["rooms.notes.lockCover.leather"] ?? theme.accent}
    private var coverInk:Color{MadarToken.colors["rooms.notes.lockCover.text"] ?? theme.background}
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:20) {
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                        Button("اختبر الجذر"){app.open(URL(string:"madar://notes")!)}.accessibilityIdentifier("diary-book-root-route")
                    }
#endif
                    HStack{Text("كتاب السنة").font(DiaryType.title);Spacer();Picker("السنة الميلادية",selection:Binding(get:{selectedYear},set:{year=$0})){ForEach(years,id:\.self){year in yearOption(year).tag(year)}}.labelsHidden().accessibilityIdentifier("diary-book-year")}
                    Text("سنة في كتاب واحد، وكل يوم يبدأ صفحة").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    cover.frame(maxWidth:.infinity)
                    if pages.isEmpty {Text("لم تكتب في هذه السنة بعد.").font(DiaryType.writing)} else {spread}
                    VStack(alignment:.leading,spacing:12){
                        Text("في الكتاب").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                        Toggle("الهوامش",isOn:$margins).accessibilityIdentifier("diary-book-margins");Divider().overlay(theme.line)
                        Toggle("سطور الأقسام",isOn:$sources).accessibilityIdentifier("diary-book-sources");Divider().overlay(theme.line)
                        Toggle("الصور",isOn:$photos).accessibilityIdentifier("diary-book-photos");Divider().overlay(theme.line)
                        Toggle("فهرس في آخره",isOn:$includeIndex).accessibilityIdentifier("diary-book-index")
                    }.font(MadarTypography.body()).tint(theme.color("ghad")).padding(16).background(theme.surface,in:.rect(cornerRadius:18)).overlay{RoundedRectangle(cornerRadius:18).stroke(theme.line)}
                    if let failure {Text(failure).font(DiaryType.label).accessibilityIdentifier("diary-book-error")}
                    // AU-95: a failed first read left «جهّز الكتاب» dim for good; read the years again.
                    if failure != nil, pages.isEmpty {Button("أعِد المحاولة"){failure=nil;attempt+=1}.font(DiaryType.label).frame(minHeight:44).contentShape(Rectangle()).accessibilityIdentifier("diary-book-retry")}
                    if busy {ProgressView("يجهّز الكتاب…")}
                    Button{prepare()}label:{Text("جهّز الكتاب").font(DiaryType.heading).frame(maxWidth:.infinity,minHeight:56).foregroundStyle(theme.background).background(theme.ink,in:.capsule)}.buttonStyle(.madarPlain).disabled(busy || pages.isEmpty).accessibilityIdentifier("diary-book-prepare")
                    if let artifact {HStack{Button("اقرأ الكتاب"){preview=true}.accessibilityIdentifier("diary-book-preview");Spacer();Button("حفظ أو مشاركة"){Task{do{try await service.shareDiary(artifact)}catch{failure=madarUserMessage(error)}}}}}
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink).navigationBarTitleDisplayMode(.inline)
                .toolbar{ToolbarItemGroup(placement:.topBarLeading){Button{dismiss()}label:{HStack{Image(systemName:"chevron.backward");Text("رجوع").font(DiaryType.label)}}.disabled(busy).accessibilityIdentifier("diary-book-close")
                }}.tint(theme.accent).toolbarBackground(theme.background,for:.navigationBar)
                .task(id:attempt){do{
                    years=Set(try service.exportPages(.init()).map(\.day.year)+[service.currentDay().year]).sorted(by:>)
                    load()
                    #if DEBUG
                    let environment = ProcessInfo.processInfo.environment
                    if environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
                       environment["MADAR_UI_DIARY_YEARBOOK_READ_FAILURE_AFTER_FIRST"] == "1" {
                        await Task.yield()
                        load()
                    }
                    #endif
                }catch{pages=[];failure=madarUserMessage(error)}}
                .onChange(of:year){_,_ in load()}.onChange(of:margins){_,_ in load()}.onChange(of:sources){_,_ in load()}.onChange(of:photos){_,_ in load()}.onChange(of:includeIndex){_,_ in clear()}
                .onChange(of:phase){_,v in if v == .background {preview=false;clear()}}
                .sheet(isPresented:$preview){if let artifact {DiaryQuickLook(url:artifact.url)}}
                .onDisappear{clear()}
        }
    }
    private func yearOption(_ year:Int)->some View {
        let labels=app.yearLabels(year)
        let primary=Text(labels.primary).font(DiaryType.label)
        let secondary=Text(labels.secondary).font(MadarTypography.fine()).foregroundColor(theme.secondaryInk)
        return Text("\(primary)\n\(secondary)")
            .accessibilityLabel(labels.combined)
    }
    private var cover:some View {
        VStack(spacing:20){Text("مذكرات").font(.custom("thmanyahserifdisplay-Bold",size:32,relativeTo:.largeTitle));Rectangle().fill(coverInk.opacity(0.6)).frame(width:60,height:1);VStack(spacing: 4) { Text(app.yearLabels(selectedYear).primary).font(.custom("thmanyahseriftext-Bold",size:26,relativeTo:.largeTitle)).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.85).padding(.horizontal,12); Text(app.yearLabels(selectedYear).secondary).font(DiaryType.label) };Text(pages.isEmpty ? "لا أيام بعد" : arabicCount(pages.count,["يوم واحد محفوظ","يومان محفوظان","أيام محفوظة","يومًا محفوظًا"],service.digits)).font(DiaryType.label)}
            .foregroundStyle(coverInk).frame(width:210,height:280).background(bookColor,in:.rect(topLeadingRadius:4,bottomLeadingRadius:4,bottomTrailingRadius:10,topTrailingRadius:10))
            .overlay(alignment:.trailing){Rectangle().fill(.black.opacity(0.14)).frame(width:10)}.shadow(color:theme.ink.opacity(0.2),radius:16,x:5,y:14).padding(.vertical,4).accessibilityElement(children:.combine).accessibilityIdentifier("diary-book-cover")
    }
    private var spread:some View {
        let sample=Array(pages.suffix(2))
        return Group {
            if typeSize.isAccessibilitySize {VStack(spacing:1){ForEach(sample,id:\.day.description){previewPage($0)}}}
            else {HStack(alignment:.top,spacing:1){ForEach(sample,id:\.day.description){previewPage($0)}}}
        }.background(theme.line).clipShape(.rect(cornerRadius:4)).shadow(color:theme.ink.opacity(0.12),radius:8,y:7)
    }
    private func previewPage(_ page:DiaryExportPage)->some View {
        VStack(alignment:.leading,spacing:8){MadarDateLabel(page.title);ForEach(Array(page.lines.prefix(4))){line in Text(AppDiaryService.exportLabel(line.kind)+line.text).font(.custom("thmanyahseriftext-Regular",size:12,relativeTo:.caption)).foregroundStyle(line.kind=="margin" ? theme.color("pencil"):theme.ink).lineLimit(3)};if photos,let item=page.media.first(where:{$0.kind=="photo"}),let image=UIImage(data:item.data){Image(uiImage:image).resizable().scaledToFill().frame(height:50).clipped()};Spacer(minLength:0)}.frame(maxWidth:.infinity,alignment:.leading).frame(minHeight:155,alignment:.top).padding(10).background(theme.surface)
    }
    private func load(){clear();pages=[];do{
        #if DEBUG
        loadCount += 1
        let environment = ProcessInfo.processInfo.environment
        if loadCount == 2,
           environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           environment["MADAR_UI_DIARY_YEARBOOK_READ_FAILURE_AFTER_FIRST"] == "1" {
            throw CocoaError(.fileReadUnknown)
        }
        #endif
        pages=try service.yearbookPages(year:selectedYear,margins:margins,sources:sources,photos:photos);failure=nil
    }catch{pages=[];failure=madarUserMessage(error)}}
    private func prepare(){busy=true;failure=nil;clear();let started=generation;Task{@MainActor in await Task.yield();defer{busy=false};do{let made=try service.exportYearbook(pages:pages,year:selectedYear,index:includeIndex);if started == generation {artifact=made}else{try? FileManager.default.removeItem(at:made.url.deletingLastPathComponent())}}catch{failure=madarUserMessage(error)}}}
    private func clear(){generation += 1;if let artifact {try? FileManager.default.removeItem(at:artifact.url.deletingLastPathComponent())};artifact=nil}
}
