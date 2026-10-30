import SwiftUI
import MadarCore
import MadarDesign

struct DiarySearchView: View {
    @Bindable var app: AppSession
    var initialQuery: String? = nil
    var initialQueryRequestID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var query=""
    @State private var index:DiarySearchIndex?
    @State private var chips:[DiarySearchChip]=[]
    @State private var failure:String?
    @State private var loadAttempt=0
    #if DEBUG
    @State private var injectedReadFailure=false
    #endif
    @State private var editing:DiarySearchChip?
    @State private var replacement=""
    @State private var reader:GregorianDay?
    @State private var readerEntryID:UUID?
    @State private var readerEntryRouteID:UUID?
    @State private var letterHubOpen=false
    @State private var routedLetterID:UUID?
    @FocusState private var focused:Bool
    private var service:AppDiaryService { .init(app:app) }
    private var results:[DiarySearchDocument] { guard let index,!chips.isEmpty else{return []};return index.documents.filter{index.parser.matches($0,chips:chips)} }
    var body:some View {
        NavigationStack {
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    HStack { Image(systemName:"magnifyingglass"); TextField("ابحث في مذكراتك: كلمة، أو تاريخ",text:$query).font(DiaryType.writing).focused($focused).submitLabel(.search).onSubmit{focused=false}.accessibilityIdentifier("diary-search-query"); if !query.isEmpty { Button {query="";chips=[]} label:{Image(systemName:"xmark.circle.fill")}.accessibilityLabel("مسح البحث") } }.padding(16).background(theme.surface,in:.capsule).overlay{Capsule().stroke(theme.line)}
                    if let failure {
                        VStack(alignment:.leading,spacing:10) {
                            Text(failure).font(DiaryType.writing).accessibilityIdentifier("diary-search-read-error")
                            Button("أعد المحاولة") { loadAttempt += 1 }
                                .font(DiaryType.label).frame(minHeight:44).accessibilityIdentifier("diary-search-retry")
                        }
                    }
                    if !chips.isEmpty {
                        ScrollView(.horizontal) {HStack { ForEach(chips) { chip in HStack(spacing:8) {
                            Button(chip.label) {editing=chip;replacement=chip.label}.accessibilityIdentifier("diary-search-edit-"+chip.label)
                            Button {chips.removeAll{$0.id==chip.id}} label:{Image(systemName:"xmark")}.accessibilityLabel("حذف فلتر "+chip.label).accessibilityIdentifier("diary-search-remove-"+chip.label)
                        }.font(DiaryType.label).padding(.horizontal,12).frame(minHeight:44).background(theme.surface,in:.capsule).overlay{Capsule().stroke(theme.line)} } }}.scrollIndicators(.hidden)
                        if chips.contains(where:{if case .words=$0.rule {true}else{false}}) { Text("بحثت عن الكلمات: "+chips.compactMap{if case .words(let words)=$0.rule {words}else{nil}}.joined(separator:"، ")).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                        if !results.isEmpty { Text(arabicCount(results.count,["نتيجة واحدة","نتيجتان","نتائج","نتيجة"],service.digits)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                        if results.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("لا أيام تطابق هذا البحث").font(DiaryType.heading).accessibilityIdentifier("diary-search-empty")
                                Text("جرّب كلمة أقصر، أو احذف أحد الفلاتر لتوسيع البحث.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text"))
                                Button { query = ""; chips = []; focused = true } label: {
                                    Label("ابدأ بحثًا جديدًا", systemImage: "arrow.counterclockwise").font(DiaryType.label).padding(.horizontal, 16).frame(minHeight: 44)
                                        .background(theme.surface, in: Capsule()).overlay { Capsule().stroke(theme.line) }
                                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-search-restart")
                            }.padding(.vertical, 24)
                        }
                        ForEach(results) { row in Button { open(row) } label: {
                            VStack(alignment:.leading,spacing:8) {Text(row.text).font(DiaryType.writing).lineLimit(4).multilineTextAlignment(.leading);Text(source(row.kind)+"، "+service.bothDates(row.day,calendar:FirstCalendar(rawValue:app.string("core.firstCalendar")) ?? .hijri)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:14)).overlay{RoundedRectangle(cornerRadius:14).stroke(theme.line)}
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-search-result-"+row.id) }
                    } else if let index {
                        ForEach(["العام الماضي","صور","هوامش"],id:\.self) { example in Button {query=example;focused=false} label:{Text(example).font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading).padding(16).overlay{RoundedRectangle(cornerRadius:14).stroke(theme.line)}}.buttonStyle(.madarPlain) }
                        Text("فهرس الكتاب").font(DiaryType.heading).foregroundStyle(theme.accent).padding(.top,12)
                        if index.terms.isEmpty {Text("تظهر هنا الأماكن والمشاريع والوسوم التي استخدمتها.").font(DiaryType.writing)}
                        ForEach(index.terms,id:\.1) { name,filter,count in Button {query=filter;focused=false} label:{HStack{Text(name).font(DiaryType.writing);Rectangle().fill(theme.line).frame(height:1);Text(PrayerCopy.days(count, digits: service.digits)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}.frame(minHeight:44)}.buttonStyle(.madarPlain) }
                    }
                }.padding(18)
            }.navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively).background(theme.background).foregroundStyle(theme.ink)
                .toolbar{ToolbarItem(placement:.topBarLeading){Button{dismiss()}label:{HStack(spacing:5){Image(systemName:"chevron.backward");Text("رجوع").font(DiaryType.label)}}.accessibilityIdentifier("diary-search-close")};ToolbarItem(placement:.principal){Text("في الكتابة والهوامش والتسجيلات").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}}
                .toolbarBackground(theme.background,for:.navigationBar).tint(theme.accent)
                .task(id: loadAttempt) { loadIndex() }
                .onChange(of: initialQueryRequestID, initial: true) { _, _ in applyInitialQuery() }
                .onChange(of: app.prayerRevision) { _, _ in if failure == nil { loadIndex() } }
                .onChange(of:query){_,value in chips=index?.parser.parse(value) ?? []}
                .alert("تعديل الفلتر",isPresented:Binding(get:{editing != nil},set:{if !$0{editing=nil}})){TextField("الكلمة أو التاريخ",text:$replacement);Button("تطبيق"){if let old=editing,let i=chips.firstIndex(where:{$0.id==old.id}),let parser=index?.parser {chips.replaceSubrange(i...i,with:parser.parse(replacement))};editing=nil};Button("إلغاء",role:.cancel){editing=nil}}
                .sheet(isPresented:Binding(get:{reader != nil},set:{if !$0{reader=nil;readerEntryID=nil;readerEntryRouteID=nil}})){if let reader {DiaryDayView(app:app,day:reader,initialEntryID:readerEntryID,initialEntryRouteID:readerEntryRouteID).environment(\.roomTheme,theme).madarSheetErrorAlert(app)}}
                .fullScreenCover(isPresented: $letterHubOpen, onDismiss: { routedLetterID = nil }) {
                    DiaryHubView(app: app, initialTab: "letters", initialLetterID: routedLetterID).environment(\.roomTheme, theme).madarSheetErrorAlert(app)
                }
        }
    }
    private func loadIndex() {
        do {
            #if DEBUG
            let environment=ProcessInfo.processInfo.environment
            if !injectedReadFailure, environment["MADAR_UI_DIARY_SEARCH_READ_FAILURE_ONCE"] == "1",
               environment["MADAR_UI_DIARY_FIXTURE"] == "editor", environment["MADAR_UI_STORE_ID"] != nil {
                injectedReadFailure=true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            index=try service.searchIndex()
            chips=index?.parser.parse(query) ?? []
            failure=nil
        } catch { index=nil; chips=[]; failure="تعذّر فتح فهرس المذكرات. أعد المحاولة." }
    }
    private func applyInitialQuery() {
        query = initialQuery ?? ""
        chips = index?.parser.parse(query) ?? []
        focused = false
    }
    private func open(_ row: DiarySearchDocument) {
        focused=false
        if row.kind == "letter", let id=UUID(uuidString:row.id) {
            routedLetterID=id
            letterHubOpen=true
            return
        }
        if let id=UUID(uuidString:row.id) {
            do {
                if let actualDay=try service.entryDay(id) { readerEntryID=id; readerEntryRouteID=UUID(); reader=actualDay }
                else { readerEntryID=nil; readerEntryRouteID=nil; reader=row.day }
            } catch { app.errorMessage=madarUserMessage(error) }
        } else { readerEntryID=nil; reader=row.day }
    }
    private func source(_ kind:String)->String {switch kind{case "photo":"صورة";case "audio":"تسجيل";case "margin":"هامش";case "intention":"نيّة";case "tomorrow":"لِغد";case "letter":"رسالة مفتوحة";default:"كتابتك"}}
}
