import SwiftUI
import MadarCore
import MadarDesign

struct DiarySearchView: View {
    private struct SearchRequest: Equatable {
        let indexGeneration: Int
        let chips: [DiarySearchChip]
    }
    private struct AdjustedSearch {
        let query: String
        let chips: [DiarySearchChip]
    }
    @Bindable var app: AppSession
    var initialQuery: String? = nil
    var initialQueryRequestID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var query=""
    @State private var index:DiarySearchIndex?
    @State private var chips:[DiarySearchChip]=[]
    @State private var adjustedSearch: AdjustedSearch?
    @State private var results:[DiarySearchDocument]=[]
    @State private var searching=false
    @State private var indexGeneration=0
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
    var body:some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment:.leading,spacing:18) {
                    HStack {
                        Image(systemName: "magnifyingglass")
                        TextField("ابحث في مذكراتك: كلمة، أو تاريخ", text: Binding(get: { query }, set: { if $0 != query { adjustedSearch = nil; query = $0 } }))
                            .font(DiaryType.writing).focused($focused).submitLabel(.search).onSubmit { focused = false }
                            .accessibilityIdentifier("diary-search-query")
                        if !query.isEmpty {
                            Button { beginSearch(""); chips = [] } label: {
                                Image(systemName: "xmark.circle.fill").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                            }.buttonStyle(.madarPlain).accessibilityLabel("مسح البحث")
                        }
                    }.padding(.horizontal, 16).padding(.vertical, 8).frame(minHeight: 56)
                        .background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line) }
                    if let failure {
                        VStack(alignment:.leading,spacing:10) {
                            Text(failure).font(DiaryType.writing).accessibilityIdentifier("diary-search-read-error")
                            Button("أعد المحاولة") { loadAttempt += 1 }
                                .font(DiaryType.label).frame(minHeight:44).accessibilityIdentifier("diary-search-retry")
                        }
                    }
                    let found = results
                    if !chips.isEmpty {
                        ScrollView(.horizontal) {
                            HStack(spacing: 8) {
                                ForEach(chips) { chip in
                                    HStack(spacing: 0) {
                                        Button { focused = false; editing = chip; replacement = chip.label } label: {
                                            Label(chip.label, systemImage: "pencil")
                                                .padding(.leading, 12).frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                                        }.accessibilityLabel("عدّل الفلتر " + chip.label).accessibilityIdentifier("diary-search-edit-" + chip.label)
                                        Button { adjustFilters(chips.filter { $0.id != chip.id }) } label: {
                                            Image(systemName: "xmark").frame(minWidth: 44, minHeight: 44).contentShape(.rect)
                                        }.accessibilityLabel("حذف فلتر " + chip.label).accessibilityIdentifier("diary-search-remove-" + chip.label)
                                    }.buttonStyle(.madarPlain).font(DiaryType.label)
                                        .background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line) }
                                }
                            }
                        }.scrollIndicators(.hidden)
                        if chips.contains(where:{if case .words=$0.rule {true}else{false}}) { Text("بحثت عن الكلمات: "+chips.compactMap{if case .words(let words)=$0.rule {words}else{nil}}.joined(separator:"، ")).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                        if !found.isEmpty { Text(arabicCount(found.count,["نتيجة واحدة","نتيجتان","نتائج","نتيجة"],service.digits)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                        if searching {
                            ProgressView("نبحث في مذكراتك…").font(DiaryType.label).accessibilityIdentifier("diary-search-loading")
                        } else if found.isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("لا نتائج لهذا البحث").font(DiaryType.heading).accessibilityIdentifier("diary-search-empty")
                                Text("جرّب كلمة أقصر، أو احذف أحد الفلاتر لتوسيع البحث.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text"))
                                Button { beginSearch("", focus: true); chips = [] } label: {
                                    Label("ابدأ بحثًا جديدًا", systemImage: "arrow.counterclockwise").font(DiaryType.label).padding(.horizontal, 16).frame(minHeight: 44)
                                        .background(theme.surface, in: Capsule()).glassEffect(.regular.interactive(), in: .capsule)
                                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-search-restart")
                            }.padding(.vertical, 24)
                        }
                        ForEach(found) { row in Button { open(row) } label: {
                            VStack(alignment:.leading,spacing:8) {Text(row.text).font(DiaryType.writing).lineLimit(4).multilineTextAlignment(.leading);Text(source(row.kind)+"، "+service.bothDates(row.day,calendar:app.diaryFirstCalendar)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}.padding(16).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:14)).overlay{RoundedRectangle(cornerRadius:14).stroke(theme.line)}
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-search-result-"+row.id) }
                    } else if let index {
                        if index.documents.isEmpty { Text("لم تكتب شيئًا بعد. تظهر هنا نتائج بحثك حين تكتب أول يوم.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 12) }
                        else { ForEach(["العام الماضي","صور","هوامش"],id:\.self) { example in Button {beginSearch(example)} label:{Text(example).font(DiaryType.writing).frame(maxWidth:.infinity,alignment:.leading).padding(16).overlay{RoundedRectangle(cornerRadius:14).stroke(theme.line)}}.buttonStyle(.madarPlain) } }
                        Text("فهرس الكتاب").font(DiaryType.heading).foregroundStyle(theme.accent).padding(.top,12)
                        if index.terms.isEmpty {Text("تظهر هنا الأماكن والوسوم التي استخدمتها.").font(DiaryType.writing)}
                        ForEach(index.terms,id:\.1) { name,filter,count in Button {beginSearch(filter)} label:{HStack{Text(name).font(DiaryType.writing);Rectangle().fill(theme.line).frame(height:1);Text(PrayerCopy.days(count, digits: service.digits)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}.frame(minHeight:44)}.buttonStyle(.madarPlain) }
                    } else if failure == nil {
                        ProgressView("نجهّز فهرس مذكراتك…").font(DiaryType.label).padding(.vertical, 12).accessibilityIdentifier("diary-search-index-loading")
                    }
                }.padding(18)
            }.navigationBarTitleDisplayMode(.inline).scrollDismissesKeyboard(.interactively).background(theme.background).foregroundStyle(theme.ink)
                .toolbar{
                    ToolbarItem(placement:.topBarLeading){Button{dismiss()}label:{HStack(spacing:5){Image(systemName:"chevron.backward");Text("رجوع").font(DiaryType.label)}}.accessibilityIdentifier("diary-search-close")}
                    ToolbarItem(placement:.principal){Text("في الكتابة والهوامش والتسجيلات").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))}
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                        ToolbarItem(placement:.topBarTrailing) { Button("اختبر الجذر") { app.open(URL(string:"madar://notes")!) }.accessibilityIdentifier("ui-test-open-diary-root") }
                    }
#endif
                }
                .toolbarBackground(theme.background,for:.navigationBar).tint(theme.accent)
                .task(id: loadAttempt) { await loadIndex() }
                .onChange(of: initialQueryRequestID, initial: true) { _, _ in applyInitialQuery() }
                .onChange(of: app.prayerRevision) { _, _ in if failure == nil { Task { await loadIndex() } } }
                .task(id:query) {
                    guard adjustedSearch?.query != query else { return }
                    // Typing waits a moment so a long diary is filtered once per word, not once per key.
                    if !query.isEmpty { try? await Task.sleep(for:.milliseconds(220)); guard !Task.isCancelled else {return} }
                    guard adjustedSearch?.query != query else { return }
                    chips=index?.parser.parse(query) ?? []
                }
                .onChange(of: chips) { _, _ in
                    results = []
                    searching = index != nil && !chips.isEmpty
                }
                .task(id: SearchRequest(indexGeneration: indexGeneration, chips: chips)) {
                    guard let index, !chips.isEmpty else { results = []; searching = false; return }
                    let requestChips = chips
                    let requestGeneration = indexGeneration
                    searching = true
                    do {
                        let matches = try await index.matching(requestChips)
                        guard !Task.isCancelled, requestGeneration == indexGeneration, requestChips == chips else { return }
                        results = matches
                        searching = false
                    } catch is CancellationError { return }
                    catch {
                        guard !Task.isCancelled, requestGeneration == indexGeneration, requestChips == chips else { return }
                        results = []
                        searching = false
                    }
                }
                .alert("تعديل البحث", isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }), presenting: editing) { chip in
                    TextField("الكلمة أو التاريخ", text: $replacement)
                    Button("ابحث") {
                        if let i = chips.firstIndex(where: { $0.id == chip.id }), let parser = index?.parser {
                            var updated = chips
                            updated.replaceSubrange(i...i, with: parser.parse(replacement))
                            adjustFilters(updated)
                        }
                        editing = nil
                    }
                    Button("إلغاء", role: .cancel) { editing = nil }
                }
                .sheet(isPresented:Binding(get:{reader != nil},set:{if !$0{reader=nil;readerEntryID=nil;readerEntryRouteID=nil}})){if let reader {DiaryDayView(app:app,day:reader,initialEntryID:readerEntryID,initialEntryRouteID:readerEntryRouteID).environment(\.roomTheme,theme).madarSheetErrorAlert(app)}}
                .fullScreenCover(isPresented: $letterHubOpen, onDismiss: { routedLetterID = nil }) {
                    DiaryHubView(app: app, initialTab: "letters", initialLetterID: routedLetterID).environment(\.roomTheme, theme).madarSheetErrorAlert(app)
                }
        }
    }
    private func loadIndex() async {
        do {
            #if DEBUG
            let environment=ProcessInfo.processInfo.environment
            if !injectedReadFailure, environment["MADAR_UI_DIARY_SEARCH_READ_FAILURE_ONCE"] == "1",
               environment["MADAR_UI_DIARY_FIXTURE"] == "editor", environment["MADAR_UI_STORE_ID"] != nil {
                injectedReadFailure=true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            index=try await service.searchIndexOffMain()
            indexGeneration += 1
            if let adjustedSearch, adjustedSearch.query == query { chips = adjustedSearch.chips }
            else { chips=index?.parser.parse(query) ?? [] }
            failure=nil
        } catch { index=nil; chips=[]; failure="تعذّر فتح فهرس المذكرات. أعد المحاولة." }
    }
    private func applyInitialQuery() {
        beginSearch(initialQuery ?? "", focus: initialQuery?.isEmpty ?? true)
        chips = index?.parser.parse(query) ?? []
    }
    private func beginSearch(_ text: String, focus: Bool = false) {
        adjustedSearch = nil
        query = text
        focused = focus
    }
    private func adjustFilters(_ updated: [DiarySearchChip]) {
        let text = updated.map(\.label).joined(separator: " ")
        // Keep the selected rules: reparsing joined labels could reinterpret adjacent month/year filters.
        adjustedSearch = AdjustedSearch(query: text, chips: updated)
        chips = updated
        query = text
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
