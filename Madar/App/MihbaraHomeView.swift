import SwiftUI
import SwiftData
import MadarCore
import MadarDesign
import MadarData
import MadarCommands

struct MihbaraHomeView: View {
    let app: AppSession
    var isTabRoot = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading: MihbaraHomeReading?
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var roomWidth: CGFloat = 0
    @State private var shapes: [UUID: MihbaraBookShape] = [:]
    @State private var shelfWidth: CGFloat = 360
    @State private var motivationCues: [MihbaraMotivationCue] = []
    @State private var scrollTarget: String?
    @State private var tableID: UUID?
    @State private var sheet: MihbaraSheet?
    @State private var showingAddBook = false
    @State private var sunnahDrawerOpen = false
    @State private var readerRoute: MihbaraReaderRoute?
    @State private var notebookRouteID: UUID?
    @State private var renaming: MihbaraBook?
    @State private var pendingRemoval: MihbaraRemovalConfirmation?
    @State private var renameTitle = ""
    @State private var renameAuthor = ""
    @State private var manuallyOpen = false
    @State private var libraryQuery = ""
    @State private var libraryShelf = "all"
    @State private var pendingBookFile: URL?
    @State private var pendingGoodreadsFile: URL?
    @State private var pendingGoodreadsStage: GoodreadsCSVStage?
    @State private var pendingMotivationBook: UUID?
    @State private var slotBook: MihbaraBook?
    @State private var pendingSlotBook: MihbaraBook?
    @State private var pendingLibraryAction: MihbaraLibraryAction?
    @State private var libraryActionIsActive = false
    @State private var libraryActionWriteIsRunning = false
    @State private var restoreFileAfterSheet = false
    @State private var offerConversion: MihbaraBook?
    @State private var shelfReadFailed = false
    @State private var shelfReadTask: Task<Void, Never>?
    @State private var shelfReadRequestID = UUID()
    @State private var readingGoal: MihbaraReadingGoal?
    @State private var goalEditor: MihbaraGoalEditor?
    @State private var shelfReadError: String?
    #if DEBUG
    @State private var injectedShelfReadFailure = false
    @State private var injectedRouteOpenFailure = false
    @State private var injectedRouteForUITest = false
    #endif
    private var theme: RoomTheme { .init(room: "mihbara", dark: colorScheme == .dark) }
    private var service: AppMihbaraService { .init(app: app) }
    private var tableBook: MihbaraBook? { reading.flatMap { MihbaraStand.pick(from: $0.books, preferred: tableID) } }
    private func setStand(_ id: UUID) { tableID = id; MihbaraStand.save(id); try? app.publishSnapshot() }
    private var shelfReadFailurePanel: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(shelfReadError ?? "تعذّرت قراءة بيانات المحبرة الآن.")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Button("أعِد المحاولة") { load(retryingAfterFailure: true) }
                .font(MadarTypography.section()).frame(minHeight: 44)
                .foregroundStyle(theme.accent)
                .accessibilityIdentifier("mihbara-home-retry")
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(theme.surface, in: .rect(cornerRadius: 18))
    }
    @ViewBuilder private func deskAndContinuation(_ reading: MihbaraHomeReading) -> some View {
        VStack(spacing: 0) {
            desk(reading)
            if let book = lastReadBook(reading) {
                let index = MihbaraBookCovers.leatherIndices(for: reading.books)[book.id] ?? 0
                continueCard(book, leather: index)
                    .padding(.horizontal, 8).padding(.bottom, 12)
            }
        }
        .background(theme.color("wood"), in: .rect(topLeadingRadius: 26, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 26))
    }
    var body: some View {
        timelineContent
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if app.undoToastVisible && sheet == nil {
                UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).hostsUndo(app)
                    .accessibilityIdentifier("mihbara-undo")
            }
        }
        .task {
            #if DEBUG
            injectRouteForUITestIfNeeded()
            #endif
            load()
            MihbaraConversions.shared.onFinished = { load() }
            await MihbaraCoverStore.shared.reload(app.container)
        }
        .onDisappear { cancelShelfRead() }
        .modifier(MihbaraConversionOffer(app: app, book: $offerConversion))
        .onChange(of: app.mihbaraBookToOpen) { _, _ in openSpotlightBookIfNeeded() }
        .onChange(of: app.mihbaraRoute, initial: true) { _, route in
            if let route {
                openRoute(route)
            }
        }
        .onChange(of: app.mihbaraRootDraftBlockers.isEmpty) { _, empty in
            if empty, let route = app.mihbaraRoute { openRoute(route) }
        }
        .onChange(of: app.undoToken?.id) { load() }
        .onChange(of: app.prayerRevision) { load() }.onChange(of: reading?.day) { folded = false; manuallyOpen = false }
        .modifier(MihbaraHomeConfirmations(
            slotBook: $slotBook, pendingRemoval: $pendingRemoval,
            replacementBooks: { replacementBooks(for: $0) },
            removalTitle: removalTitle,
            moveToReading: { incoming, oldID in moveBook(incoming, to: "reading", replacing: oldID) },
            beginLibraryActionWrite: { libraryActionWriteIsRunning = true },
            onDismiss: finishLibraryAction,
            deleteBook: deleteBook, removeBookFile: removeBookFile
        ))
        .sheet(item: $sheet, onDismiss: sheetDismissed) { target in routeSheet(target) }
        .sheet(item: $goalEditor, onDismiss: { load() }) { target in
            HabitEditorView(session: app, reading: target.reading, id: target.id, initialSource: "reading").madarSheetErrorAlert(app)
        }
        // Owner, 21 Oct 2026: «اقدر اعدل اسم الكتاب». The spine keeps the short name the title is known by.
        .modifier(MihbaraRenameAlert(book: $renaming, title: $renameTitle, author: $renameAuthor, save: rename, onDismiss: finishLibraryAction))
        .modifier(MihbaraReaderCover(
            app: app, route: $readerRoute, theme: theme,
            bookForRoute: { readableBook($0) },
            originalPDFID: { originalPDFID($0) },
            onDismiss: { load(); finishLibraryAction() },
            onBookDetails: { id in sheet = .book(id) }
        ))
        .fullScreenCover(isPresented: $showingAddBook, onDismiss: { discardPendingGoodreads(); replayPendingMihbaraRouteIfReady() }) {
            if let reading {
                NavigationStack {
                    MihbaraAddBookView(
                        app: app,
                        readingBooks: reading.books.filter { $0.shelf == "reading" },
                        onPaperBookSaved: { showingAddBook = false; load() },
                        onPDFImported: {
                            pendingBookFile = nil; showingAddBook = false; load(); offerNewestPDF()
                        },
                        onEPUBImported: { pendingBookFile = nil; showingAddBook = false; load() },
                        onGoodreadsImported: { showingAddBook = false; load() },
                        pendingBookFile: $pendingBookFile,
                        pendingGoodreadsFile: $pendingGoodreadsFile,
                        pendingGoodreadsStage: $pendingGoodreadsStage
                    )
                }
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app)
            } else {
                // AU-18: never a blank full-screen cover with no way out.
                Color.clear.onAppear { showingAddBook = false }
            }
        }
    }
    @ViewBuilder private func routeSheet(_ target: MihbaraSheet) -> some View {
        NavigationStack {
            if let r = reading {
                switch target {
                case .library:
                    library(r)
                case .book(let id):
                    if let b = r.book(id) {
                        let fileUnavailable = !service.hasLocalFile(for: b)
                        if b.kind == "file", ["pdf", "pdfScanned"].contains(b.format ?? "") {
                            MihbaraImportedPDFSummary(book: b, fileUnavailable: fileUnavailable, onRestoreFile: requestBookFileRestore)
                        } else {
                            MihbaraBookCard(
                                app: app,
                                book: b,
                                books: r.books,
                                fileUnavailable: fileUnavailable,
                                onTable: { setStand(id); sheet = nil },
                                onRestoreFile: requestBookFileRestore,
                                onPaperIndexSaved: { load() },
                                shape: shapes[id]
                            )
                        }
                    }
                case .hadith(let number):
                    hadithRouteView(number, reading: r)
                case .opening:
                    MihbaraRahlOpeningView(app: app).presentationDetents([.large])
                case .notebook:
                    MihbaraNotebookContent(app: app, initialNoteID: notebookRouteID)
                case .motivation:
                    MihbaraMotivationCard(cues: motivationCues, action: performMotivation)
                }
            }
        }
        .environment(\.roomTheme, theme)
        .presentationDragIndicator(.visible)
        // iPad: the library, a book, a hadith and the notebook open as a full page; the small cards stay small.
        .modifier(PadPageSheet(on: { if case .opening = target { return false }; if case .motivation = target { return false }; return true }()))
        .madarSheetErrorAlert(app)
    }
    /// FB-34 (owner, 5 Nov: «الاحصائيات حقت الكتب شف لها طريقه»): what the stand used to tell, for every book in hand.
    @ViewBuilder private func inHand(_ reading: MihbaraHomeReading) -> some View {
        MihbaraReadingNow(app: app, books: reading.books, shapes: shapes, digits: service.digits, open: { openBook($0) })
        if let readingGoal {
            MihbaraReadingGoalCard(app: app, goal: readingGoal, digits: service.digits,
                                   onCreate: { goalEditor = .init(reading: nil) },
                                   onEdit: { goalEditor = .init(reading: $0) })
        }
    }
    private var wide: Bool { isPadWide(sizeClass) && roomWidth >= 960 }
    private var timelineContent: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { tick in
            ScrollViewReader { proxy in
                shelfScrollView(at: tick.date, proxy: proxy)
            }
        }
    }
    private func shelfScrollView(at date: Date, proxy: ScrollViewProxy) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    if isTabRoot { Color.clear.frame(width: 44, height: 44) }
                    else { Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right").padding(.horizontal, 12).frame(minHeight: 44).glassEffect(.regular.interactive(), in: .capsule) }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-back") }
                    Spacer(minLength: 8)
                    Text("المحبرة").font(MadarTypography.title())
                    Spacer(minLength: 8)
                    Image(systemName: "books.vertical").font(.title2).frame(width: 44, height: 44)
                }
                if shelfReadFailed { shelfReadFailurePanel }
                if let reading {
                    MadarDateLabel(app.dateLabels(reading.day)).foregroundStyle(theme.secondaryInk)
                    conversionCards
                    if wide {
                        // iPad landscape: the bookcase on the right, the books in hand and the goal beside it.
                        HStack(alignment: .top, spacing: 28) {
                            shelfView(reading).frame(maxWidth: .infinity)
                            VStack(alignment: .leading, spacing: 20) { inHand(reading) }.frame(width: 400)
                        }
                    } else {
                        shelfView(reading)
                        inHand(reading)
                    }
                }
            }
            .padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 28)
            .frame(maxWidth: wide ? 1100 : 650).frame(maxWidth: .infinity)
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        .madarTopClipped()
        .onChange(of: date) { if !shelfReadFailed { load() } }
        .onChange(of: scrollTarget) { _, target in handleScrollTargetChange(target, proxy: proxy) }
    }
    /// PDFs converting in the background, and those just finished («افتحه»).
    private var conversionCards: some View {
        ForEach(MihbaraConversions.shared.jobs) { job in
            MihbaraConversionCard(app: app, job: job, digits: service.digits) { id in readerRoute = MihbaraReaderRoute(bookID: id) }
        }
    }
    // AU-36: «كتاب آخر / كتابان آخران / ٣ كتب أخرى», never «كتاب واحد أخرى».
    private func moreBooks(_ count: Int) -> String {
        count == 1 ? "كتاب آخر" : count == 2 ? "كتابان آخران" : MihbaraCopy.books(count, service.digits) + " " + (count % 100 >= 3 && count % 100 <= 10 ? "أخرى" : "آخر")
    }
    private func replacementBooks(for incoming: MihbaraBook) -> [MihbaraBook] {
        let books = reading?.books ?? []
        return books.filter { $0.shelf == "reading" && $0.id != incoming.id }
    }
    private func readableBook(_ id: UUID) -> MihbaraBook? {
        guard let book = reading?.book(id), book.isReadableEPUB || book.isReadablePDF else { return nil }
        guard service.hasLocalFile(for: book) else { return nil }
        return book
    }
    private func handleScrollTargetChange(_ target: String?, proxy: ScrollViewProxy) {
        guard let target else { return }
        withAnimation(reduceMotion ? nil : .smooth) { proxy.scrollTo("shelf-" + target, anchor: .top) }
        scrollTarget = nil
    }
    @ViewBuilder private func hadithRouteView(_ number: Int, reading: MihbaraHomeReading) -> some View {
        if let hadith = reading.collection.hadiths.first(where: { $0.number == number }) {
            MihbaraHadithView(app: app, hadith: hadith, collection: reading.collection, day: reading.day)
        }
    }
    private func discardPendingGoodreads() {
        if let stage = pendingGoodreadsStage { GoodreadsCSVFiles.discard(id: stage.id, root: app.bookStagingDirectory) }
        pendingGoodreadsStage = nil
        pendingGoodreadsFile = nil
    }
    /// The PDF just added is offered for conversion (owner's choice, never automatic).
    private func offerNewestPDF() {
        let pdfs = (reading?.books ?? []).filter { $0.isReadablePDF && MihbaraConversions.shared.job(for: $0.id) == nil }
        offerConversion = pdfs.max { $0.updated < $1.updated }
    }
    private func originalPDFID(_ hash: String) -> UUID? {
        let all: [MihbaraBook] = (reading?.originals ?? []) + (reading?.books ?? [])
        return all.first { $0.isReadablePDF && $0.fileHash == hash }?.id
    }
    private func load(retryingAfterFailure: Bool = false) {
        guard !shelfReadFailed || retryingAfterFailure else { return }
        shelfReadTask?.cancel()
        let requestID = UUID()
        shelfReadRequestID = requestID
        shelfReadTask = Task { @MainActor in
            do {
                #if DEBUG
                let environment = ProcessInfo.processInfo.environment
                if !injectedShelfReadFailure,
                   environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
                   environment["MADAR_UI_MIHBARA_HOME_READ_FAILURE_ONCE"] == "1" {
                    injectedShelfReadFailure = true
                    throw CocoaError(.fileReadUnknown)
                }
                #endif
                let loaded = try await service.loadOffMain()
                guard !Task.isCancelled, shelfReadRequestID == requestID else { return }
                reading = loaded
                // A failed read keeps the last card; a nil card would offer to create a habit that may already exist.
                do { readingGoal = try service.readingGoal(today: loaded.day, book: MihbaraStand.pick(from: loaded.books, preferred: tableID)) } catch { app.errorMessage = madarUserMessage(error) }
                shelfReadFailed = false
                shelfReadError = nil
                let books = loaded.books
                MihbaraConversions.shared.resume(books, app: app)
                Task { shapes = await service.bookShapes(books) }
                if let route = app.mihbaraRoute { openRoute(route, using: loaded) }
                else { openSpotlightBookIfNeeded(using: loaded) }
            } catch is CancellationError {
                return
            } catch {
                guard !Task.isCancelled, shelfReadRequestID == requestID else { return }
                shelfReadFailed = true
                shelfReadError = "تعذّرت قراءة المحبرة الآن. كتبك محفوظة في مكانها؛ حاول مرة أخرى."
            }
        }
    }
    private func cancelShelfRead() {
        shelfReadRequestID = UUID()
        shelfReadTask?.cancel()
        shelfReadTask = nil
    }
    #if DEBUG
    private func injectRouteForUITestIfNeeded() {
        let environment = ProcessInfo.processInfo.environment
        guard !injectedRouteForUITest,
              environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
              let rawURL = environment["MADAR_UI_MIHBARA_ROUTE"], let url = URL(string: rawURL) else { return }
        injectedRouteForUITest = true
        app.open(url)
    }
    #endif
    private func openRoute(_ route: Route, using loadedReading: MihbaraHomeReading? = nil) {
        guard !shelfReadFailed, app.mihbaraRootDraftBlockers.isEmpty,
              pendingLibraryAction == nil, !libraryActionIsActive, !libraryActionWriteIsRunning else {
            return
        }
        // «افتح المحبرة» in «خصّص» hangs a second room over the tab; the one the reader sees takes the link, not the tab hidden underneath.
        if isTabRoot && app.mihbaraOpen { return }
        if route.path.isEmpty {
            readerRoute = nil
            showingAddBook = false
            // The room link closes the read-only sheets; the notebook may hold a draft and keeps its own close path.
            switch sheet {
            case .some(.library), .some(.book(_)), .some(.hadith(_)), .some(.notebook), .some(.opening):
                sheet = nil
                return
            default:
                break
            }
            app.mihbaraRoute = nil
            return
        }
        // A link never tears down an open sheet that may hold a draft; it waits and runs once that sheet closes.
        if let sheet {
            if case .library = sheet { self.sheet = nil }
            return
        }
        guard readerRoute == nil, !showingAddBook, renaming == nil, pendingRemoval == nil, slotBook == nil else { return }
        guard let reading = loadedReading ?? self.reading else { return }
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if !injectedRouteOpenFailure,
           environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           environment["MADAR_UI_MIHBARA_ROUTE_OPEN_FAILURE_ONCE"] == "1" {
            injectedRouteOpenFailure = true
            shelfReadFailed = true
            shelfReadError = "تعذّر فتح الوجهة الآن. حاول مرة أخرى."
            return
        }
        #endif
        guard let routeName = route.path.first else { app.mihbaraRoute = nil; return }
        switch routeName {
        case "desk":
            readerRoute = nil
            sheet = nil
            app.mihbaraRoute = nil
            return
        case "continue":
            // Siri and Shortcuts cannot read the store, so «أكمل القراءة» names no book: the book on the stand is chosen here.
            guard let book = MihbaraStand.pick(from: reading.books, preferred: tableID) else {
                app.mihbaraRoute = nil
                app.errorMessage = "ما على رفّ «أقرؤها» كتاب الآن؛ اختر كتابًا من مكتبتك لتكمله."
                return
            }
            switch openBook(book, locatorJSON: nil) {
            case .opened:
                app.mihbaraRoute = nil
                shelfReadFailed = false
                shelfReadError = nil
            case .deferred, .failed:
                break
            }
        case "book":
            guard route.path.count == 2, let rawID = route.path.last else { app.mihbaraRoute = nil; return }
            guard let id = UUID(uuidString: rawID), let book = reading.book(id) else {
                app.mihbaraRoute = nil
                app.errorMessage = "الكتاب لم يعد موجودًا في المحبرة."
                return
            }
            switch openBook(book, locatorJSON: route.parameters["loc"]) {
            case .opened:
                app.mihbaraRoute = nil
                shelfReadFailed = false
                shelfReadError = nil
            case .deferred, .failed:
                break
            }
        case "hadith" where route.path.count == 2 && route.path.last == "today":
            guard let hadith = reading.todayHadiths.first else {
                app.mihbaraRoute = nil
                app.errorMessage = "لا حديث لورد اليوم الآن."
                return
            }
            sheet = .hadith(hadith.number)
            app.mihbaraRoute = nil
        case "hadith" where route.path.count == 3:
            let collection = route.path[1], rawNumber = route.path[2]
            guard collection == reading.collection.collectionID,
                  let number = Int(rawNumber), reading.collection.hadiths.contains(where: { $0.number == number }) else {
                app.mihbaraRoute = nil
                app.errorMessage = "هذا الحديث لم يعد موجودًا في المحبرة."
                return
            }
            sheet = .hadith(number)
            app.mihbaraRoute = nil
        case "notebook":
            guard route.path.count == 2, let rawID = route.path.last else { app.mihbaraRoute = nil; return }
            guard let id = UUID(uuidString: rawID) else {
                app.mihbaraRoute = nil
                app.errorMessage = "فكرة الدفتر لم تعد موجودة."
                return
            }
            notebookRouteID = id
            sheet = .notebook
            app.mihbaraRoute = nil
        default:
            app.mihbaraRoute = nil
            return
        }
    }
    private func openSpotlightBookIfNeeded(using loadedReading: MihbaraHomeReading? = nil) {
        guard let id = app.mihbaraBookToOpen else { return }
        if isTabRoot && app.mihbaraOpen { return }
        guard let reading = loadedReading ?? self.reading else { load(); return }
        guard let book = reading.book(id) else {
            app.mihbaraBookToOpen = nil
            app.errorMessage = "الكتاب لم يعد موجودًا في المحبرة."
            return
        }
        if case .opened = openBook(book) { app.mihbaraBookToOpen = nil }
    }
    private func showMotivation() {
        guard let reading else { return }
        do {
            motivationCues = try service.motivationCues(for: reading, book: tableBook)
            sheet = .motivation
        } catch { app.errorMessage = madarUserMessage(error) }
    }
    private func performMotivation(_ cue: MihbaraMotivationCue) {
        if let number = cue.hadithNumber { sheet = .hadith(number); return }
        if let id = cue.bookID { pendingMotivationBook = id; sheet = nil }
    }
    private func sheetDismissed() {
        if let action = pendingLibraryAction {
            pendingLibraryAction = nil
            present(action)
            return
        }
        if restoreFileAfterSheet {
            restoreFileAfterSheet = false
            showingAddBook = true
        }
        openPendingMotivationBook()
        if let book = pendingSlotBook { pendingSlotBook = nil; slotBook = book }
        notebookRouteID = nil
        if let route = app.mihbaraRoute { openRoute(route) }
    }
    private func replayPendingMihbaraRouteIfReady() {
        guard app.mihbaraRoute != nil, pendingLibraryAction == nil, !libraryActionIsActive, !libraryActionWriteIsRunning,
              sheet == nil, readerRoute == nil, !showingAddBook, renaming == nil, pendingRemoval == nil,
              slotBook == nil, app.mihbaraRootDraftBlockers.isEmpty else { return }
        Task { @MainActor in
            await Task.yield()
            guard app.mihbaraRoute != nil, pendingLibraryAction == nil, !libraryActionIsActive, !libraryActionWriteIsRunning,
                  sheet == nil, readerRoute == nil, !showingAddBook, renaming == nil, pendingRemoval == nil,
                  slotBook == nil, app.mihbaraRootDraftBlockers.isEmpty,
                  let route = app.mihbaraRoute else { return }
            openRoute(route)
        }
    }
    private func finishLibraryAction() {
        guard !libraryActionWriteIsRunning else { return }
        libraryActionIsActive = false
        replayPendingMihbaraRouteIfReady()
    }
    private func scheduleLibraryAction(_ action: MihbaraLibraryAction) {
        if case .library? = sheet {
            pendingLibraryAction = action
            sheet = nil
        } else {
            present(action)
        }
    }
    private func present(_ action: MihbaraLibraryAction) {
        libraryActionIsActive = true
        switch action {
        case .rename(let book):
            renameTitle = book.title
            renameAuthor = book.author
            renaming = book
        case .remove(let target):
            pendingRemoval = target
        case .open(let book, let volume, let locatorJSON):
            if case .opened = openBook(book, volume: volume, locatorJSON: locatorJSON) {
                clearPendingBookOpen(for: book.id)
            }
            // The library transition is complete once the reader or details sheet
            // has been presented. Keeping this active until that destination closes
            // prevents a queued room-root link from dismissing it after saving.
            finishLibraryAction()
        }
    }
    private func clearPendingBookOpen(for id: UUID) {
        if app.mihbaraBookToOpen == id { app.mihbaraBookToOpen = nil }
        guard let route = app.mihbaraRoute, route.path.count == 2, route.path.first == "book",
              UUID(uuidString: route.path[1]) == id else { return }
        app.mihbaraRoute = nil
    }
    /// A book can change shelf from where it sits: long-press its spine or its library row. The table holds three at most.
    @ViewBuilder private func bookMenu(_ b: MihbaraBook) -> some View {
        let conversionRunning = MihbaraConversions.shared.job(for: b.id)?.state.isActive == true
        if b.shelf != "reading" { Button { moveBook(b, to: "reading") } label: { Label(b.shelf == "finished" || b.shelf == "old" ? "أعد قراءته" : "ابدأ قراءته", systemImage: "book.pages") } }
        if b.shelf == "reading" {
            Button { moveBook(b, to: "finished") } label: { Label("أنهيته", systemImage: "checkmark.circle") }
            Button { moveBook(b, to: "want") } label: { Label("أعده إلى أبي أقرأها", systemImage: "bookmark") }
        }
        // The «قديمًا» cabinet holds books read long ago; this is the only way in.
        if b.shelf == "finished" { Button { moveBook(b, to: "old") } label: { Label("انقله إلى «قديمًا»", systemImage: "archivebox") } }
        if b.shelf == "want" { Button { moveBook(b, to: "old") } label: { Label("قرأته قديمًا", systemImage: "archivebox") } }
        if b.shelf == "old" { Button { moveBook(b, to: "finished") } label: { Label("أعده إلى أنهيتها", systemImage: "checkmark.circle") } }
        if b.kind == "file" {
            Button { scheduleLibraryAction(.rename(b)) } label: { Label("غيّر الاسم", systemImage: "pencil") }
                .accessibilityIdentifier("mihbara-book-rename")
            if !conversionRunning {
                if service.hasLocalFile(for: b) {
                    Button(role: .destructive) { scheduleLibraryAction(.remove(.file(b))) } label: { Label("احذف ملف الكتاب", systemImage: "doc.badge.minus") }
                        .accessibilityIdentifier("mihbara-book-file-remove")
                } else {
                    Button { requestBookFileRestore() } label: { Label("أعد استيراد ملفه", systemImage: "arrow.down.doc") }
                        .accessibilityIdentifier("mihbara-book-file-restore")
                }
            }
        }
        if !conversionRunning {
            Button(role: .destructive) { scheduleLibraryAction(.remove(.book(b))) } label: { Label("احذف من مكتبتي", systemImage: "trash") }
                .accessibilityIdentifier("mihbara-book-delete")
        }
    }
    private func deleteBook(_ book: MihbaraBook) {
        libraryActionWriteIsRunning = true
        pendingRemoval = nil
        Task {
            defer { libraryActionWriteIsRunning = false; finishLibraryAction() }
            do {
                try await app.executeBookCommand("book.delete", payload: ["id": .string(book.id.uuidString)], undoMessage: "حُذف الكتاب من رفوف المحبرة")
                load()
            } catch { app.errorMessage = madarUserMessage(error) }
        }
    }
    private var removalTitle: String {
        switch pendingRemoval {
        case .book(let book): "احذف «\(book.title)» من مكتبتك؟"
        case .file(let book): "احذف ملف «\(book.title)»؟"
        case nil: "حذف الكتاب؟"
        }
    }
    private func removeBookFile(_ book: MihbaraBook) {
        libraryActionWriteIsRunning = true
        pendingRemoval = nil
        Task {
            defer { libraryActionWriteIsRunning = false; finishLibraryAction() }
            do {
                try await app.executeBookCommand("book.removeFile", payload: ["id": .string(book.id.uuidString)])
                load(); sheet = .book(book.id)
            } catch { app.errorMessage = madarUserMessage(error) }
        }
    }
    private func requestBookFileRestore() {
        restoreFileAfterSheet = true
        sheet = nil
    }
    private func rename() {
        guard let b = renaming else { return }
        let title = renameTitle.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != b.title || renameAuthor != b.author else {
            renaming = nil
            finishLibraryAction()
            return
        }
        let payload: [String: MadarCore.JSONValue] = ["id": .string(b.id.uuidString), "title": .string(String(title.prefix(300))),
                                                      "author": .string(String(renameAuthor.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)))]
        libraryActionWriteIsRunning = true
        renaming = nil
        Task {
            defer { libraryActionWriteIsRunning = false; finishLibraryAction() }
            do { try await app.executeBookCommand("book.rename", payload: payload); load() }
            catch { app.errorMessage = madarUserMessage(error) }
        }
    }
    private func moveBook(_ b: MihbaraBook, to shelf: String, replacing: UUID? = nil) {
        if shelf == "reading", replacing == nil, b.shelf != "reading", (reading?.books.filter { $0.shelf == "reading" }.count ?? 0) >= 3 {
            if sheet != nil { pendingSlotBook = b; sheet = nil } else { slotBook = b }
            return
        }
        var payload: [String: MadarCore.JSONValue] = ["id": .string(b.id.uuidString), "shelf": .string(shelf)]
        if let replacing { payload["replacing"] = .string(replacing.uuidString) }
        Task {
            do {
                try await app.executeBookCommand("book.moveShelf", payload: payload)
                if shelf == "reading" { setStand(b.id) }
                load()
            } catch { app.errorMessage = madarUserMessage(error) }
        }
    }
    private func openPendingMotivationBook() {
        guard let id = pendingMotivationBook else { return }
        pendingMotivationBook = nil
        guard let book = reading?.books.first(where: { $0.id == id }) else { return }
        openBook(book)
    }
    /// Owner, 22 Oct 2026 («٢»): one bookcase on the wall, its shelves named — what you read, what waits, what you
    /// finished — with no tabs; the book you are reading stands open on the stand in front of it.
    private func shelfView(_ r: MihbaraHomeReading) -> some View {
        let leathers = MihbaraBookCovers.leatherIndices(for: r.books)
        // FB-34: no stand any more, so every book you are reading stands on the top shelf.
        let readingBooks = shelfBooks(r.books, "reading")
        let want = shelfBooks(r.books, "want"), finished = shelfBooks(r.books, "finished")
        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("مكتبتك").font(MadarTypography.cardTitle())
                Spacer()
                Button { showingAddBook = true } label: {
                    if r.books.isEmpty { Image(systemName: "plus").frame(width: 44, height: 44) }
                    else { Label("أضف كتابًا", systemImage: "plus") }
                }.accessibilityLabel("أضف كتابًا").accessibilityIdentifier("mihbara-add-paper")
            }
            if r.books.isEmpty {
                emptyShelf(r)
                MihbaraShelfPlank().padding(.top, -14)
            } else {
                VStack(spacing: 10) {
                    wallShelf("reading", "أقرؤها الآن") {
                        if readingBooks.isEmpty { emptyWallShelf(want.isEmpty ? "ما تبدأ قراءته يقف هنا في أعلى المكتبة." : "اضغط كتابًا من «أبي أقرأها» مطوّلًا ثم «ابدأ قراءته».") }
                        else { bookcase(readingBooks, leathers: leathers, maxRows: 2) }
                    }
                    wallShelf("want", "أبي أقرأها") {
                        if want.isEmpty { emptyWallShelf("ما تنوي قراءته يقف هنا حتى تبدأه.") }
                        else { bookcase(want, leathers: leathers, maxRows: 3) }
                    }
                    wallShelf("finished", "أنهيتها") {
                        if finished.isEmpty { emptyWallShelf("ما تنهيه يستلقي هنا مع سنة إنهائه.") }
                        else { pileBookcase(finished, leathers: leathers, maxRows: 2) }
                    }
                }
                .padding(8)
                .background(LinearGradient(colors: [theme.color("wood"), theme.color("wood").mix(with: .black, by: 0.22)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 14))
                .shadow(color: theme.ink.opacity(0.18), radius: 8, y: 5)
            }
            HStack { Button("كل كتبي ‹") { sheet = .library }.accessibilityIdentifier("mihbara-library"); Spacer(); Text(shelfTotal(r.books.count)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
        }
    }
    /// One named shelf of the wall bookcase: a brass label, then its rows. Tapping the label brings the shelf into view.
    private func wallShelf<Content: View>(_ id: String, _ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Button { scrollTarget = id } label: {
                Text(title).font(MadarTypography.caption().weight(.semibold))
                    .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink)
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(theme.color("goldUnderstand"), in: .rect(cornerRadius: 4))
                    .shadow(color: .black.opacity(0.25), radius: 1.5, y: 1)
                    .frame(minHeight: 44, alignment: .bottom)
            }.buttonStyle(.madarPlain).accessibilityAddTraits(.isHeader).accessibilityIdentifier("mihbara-shelf-" + id)
            content()
        }
        .background(theme.background.opacity(0.92), in: .rect(cornerRadius: 6))
        .accessibilityElement(children: .contain).accessibilityIdentifier("mihbara-wall-" + id)
        .id("shelf-" + id)
    }
    private func emptyWallShelf(_ text: String) -> some View {
        VStack(spacing: 0) {
            Text(text).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).padding(.horizontal, 12)
            MihbaraShelfPlank()
        }
    }
    /// Owner, 22 Oct 2026: «اذا كبرت المكتبه يصير زي البوك شيلف كبير مليان وكم دور». Books fill a shelf to the width of
    /// the screen, then the next shelf down; a set stands whole on one shelf. Five shelves show; the rest wait in «كل كتبي».
    @ViewBuilder private func bookcase(_ books: [MihbaraBook], leathers: [UUID: Int], maxRows: Int = 5) -> some View {
        let rows = shelfRows(books, width: shelfWidth - 20)
        let shown = rows.prefix(maxRows), hidden = rows.dropFirst(maxRows).reduce(0) { $0 + $1.count }
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 9) { ForEach(row) { b in standing(b, leather: leathers[b.id] ?? 0) } }
                        .padding(.horizontal, 10).padding(.top, 16)
                }
                .scrollIndicators(.hidden).scrollBounceBehavior(.basedOnSize, axes: .horizontal)
                .background(LinearGradient(colors: [theme.color("wood").opacity(0.05), theme.color("wood").opacity(0.16)], startPoint: .top, endPoint: .bottom))
                MihbaraShelfPlank().padding(.top, -14)
            }
            if hidden > 0 {
                Button { sheet = .library } label: { Text(moreBooks(hidden) + " في «كل كتبي» ‹").font(MadarTypography.caption()) }
                    .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("mihbara-bookcase-more")
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
    }

    /// «أنهيتها» as a bookcase too: the piles of finished books fill a shelf, then the next one down.
    @ViewBuilder private func pileBookcase(_ books: [MihbaraBook], leathers: [UUID: Int], maxRows: Int = 5) -> some View {
        let rows = pileRows(piles(books), width: shelfWidth - 20)
        let shown = rows.prefix(maxRows), hidden = rows.dropFirst(maxRows).flatMap { $0 }.flatMap { $0 }.count
        VStack(spacing: 0) {
            ForEach(Array(shown.enumerated()), id: \.offset) { _, row in
                HStack(alignment: .bottom, spacing: 14) {
                    ForEach(Array(row.enumerated()), id: \.offset) { _, pile in pileView(pile, leathers: leathers) }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.top, 16).padding(.bottom, 12)
                .background(LinearGradient(colors: [theme.color("wood").opacity(0.05), theme.color("wood").opacity(0.16)], startPoint: .top, endPoint: .bottom))
                MihbaraShelfPlank().padding(.top, -14)
            }
            if hidden > 0 {
                Button { sheet = .library } label: { Text(moreBooks(hidden) + " في «كل كتبي» ‹").font(MadarTypography.caption()) }
                    .frame(maxWidth: .infinity, minHeight: 44)
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { shelfWidth = $0 }
    }

    private func pileRows(_ all: [[PileItem]], width: CGFloat) -> [[[PileItem]]] {
        var rows: [[[PileItem]]] = [], used: [CGFloat] = []
        for pile in all {
            let w = pile.map { pileLength($0) }.max() ?? 160
            if let i = used.firstIndex(where: { $0 + 14 + w <= width }) { rows[i].append(pile); used[i] += 14 + w }
            else { rows.append([pile]); used.append(w) }
        }
        return rows
    }

    /// How long a finished book is lying down: its spine's height.
    private func pileLength(_ item: PileItem) -> CGFloat {
        let shape = shapes[item.book.id]
        return MihbaraBookSpine.size(pagesPerVolume: shape?.pages.map { $0 / max(1, shape?.volumes ?? 1) } ?? item.book.pages).height * Self.lyingScale + 12
    }

    /// The width a book takes standing: a spine, or all of a set's volumes side by side.
    private func standingWidth(_ b: MihbaraBook) -> CGFloat {
        let shape = shapes[b.id], volumes = max(1, shape?.volumes ?? 1)
        let single = MihbaraBookSpine.size(pagesPerVolume: shape?.pages.map { $0 / volumes } ?? b.pages)
        guard volumes > 1 else { return single.width }
        let n = CGFloat(min(volumes, 8)), w = MihbaraBookSpine.volumeSize(single).width
        return n * w + (n - 1) * MihbaraBookSpine.volumeGap + (volumes > 8 ? 34 : 0)
    }

    /// Books in shelf order packed into rows no wider than the shelf: each book takes the first shelf with room for it,
    /// so a gap left before a wide set fills with the next slim books. A set wider than a shelf stands alone.
    private func shelfRows(_ books: [MihbaraBook], width: CGFloat) -> [[MihbaraBook]] {
        var rows: [[MihbaraBook]] = [], used: [CGFloat] = []
        for b in books {
            let w = standingWidth(b)
            if let i = used.firstIndex(where: { $0 + 9 + w <= width }) { rows[i].append(b); used[i] += 9 + w }
            else { rows.append([b]); used.append(w) }
        }
        return rows
    }

    /// One book as it stands on the shelf: a spine, or a numbered spine per volume for a set. Owner, 21 Oct 2026:
    /// tapping a volume opens that volume (at the saved place when it is inside it).
    @ViewBuilder private func standing(_ b: MihbaraBook, leather: Int) -> some View {
        let shape = shapes[b.id], volumes = max(1, shape?.volumes ?? 1)
        if volumes > 1 {
            HStack(alignment: .bottom, spacing: MihbaraBookSpine.volumeGap) {
                ForEach(0..<min(volumes, 8), id: \.self) { v in
                    Button { openBook(b, volume: v) } label: { MihbaraBookSpine(book: b, shape: shape, leather: leather, digits: service.digits, volume: v, volumeCount: min(volumes, 8)) }
                        .buttonStyle(.madarPlain).contextMenu { bookMenu(b) }
                        .accessibilityLabel(shelfLabel(b) + "، " + (BookVolumes.name(v) ?? "الجزء " + service.digits.string(v + 1)))
                        .accessibilityIdentifier("mihbara-book-" + b.id.uuidString + (v == 0 ? "" : "-v\(v + 1)"))
                }
                if volumes > 8 { Text("+" + service.digits.string(volumes - 8)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.leading, 4) }
            }
        } else {
            Button { openBook(b) } label: { MihbaraBookSpine(book: b, shape: shape, leather: leather, digits: service.digits) }
                .buttonStyle(.madarPlain).contextMenu { bookMenu(b) }.accessibilityLabel(shelfLabel(b)).accessibilityIdentifier("mihbara-book-" + b.id.uuidString)
        }
    }
    private struct PileItem { let book: MihbaraBook; let volume: Int?; var key: String { book.id.uuidString + "-\(volume ?? -1)" } }
    /// Finished books (each volume of a set on its own) in piles of up to four, the newest on top. A pile holds the
    /// books of one year, so the shelf reads as a history; books read long ago («قديمًا») make the last piles.
    private func piles(_ books: [MihbaraBook]) -> [[PileItem]] {
        var result: [[PileItem]] = [], year: String?
        for b in books {
            let n = max(1, shapes[b.id]?.volumes ?? 1)
            let items = n > 1 ? (0..<min(n, 6)).map { PileItem(book: b, volume: $0) } : [PileItem(book: b, volume: nil)]
            let key = pileYear(b)?.primary ?? "old"
            for item in items {
                if key != year || result.last?.count == 4 { result.append([]) }
                result[result.count - 1].append(item); year = key
            }
        }
        return result
    }
    /// A shelf's books in shelf order: what you touched last first; finished books by when you finished them.
    private func shelfBooks(_ books: [MihbaraBook], _ shelf: String) -> [MihbaraBook] {
        books.filter { shelf == "finished" ? ["finished", "old"].contains($0.shelf) : $0.shelf == shelf }.sorted { a, b in
            guard shelf == "finished" else { return a.updated > b.updated }
            if (a.shelf == "old") != (b.shelf == "old") { return b.shelf == "old" }
            return (a.finished ?? a.updated) > (b.finished ?? b.updated)
        }
    }
    /// The year a book was finished, in the user's first calendar and the other one; nil for a book read long ago.
    private func pileYear(_ b: MihbaraBook) -> (primary: String, secondary: String)? {
        guard b.shelf != "old", let date = b.finished else { return nil }
        let hijri = service.digits.string(Calendar(identifier: .islamicUmmAlQura).component(.year, from: date)) + " هـ"
        let gregorian = service.digits.string(Calendar(identifier: .gregorian).component(.year, from: date)) + " م"
        return app.string("core.firstCalendar") == "gregorian" ? (gregorian, hijri) : (hijri, gregorian)
    }
    /// One pile, newest on top, with its year written under the first pile of that year.
    private func pileView(_ pile: [PileItem], leathers: [UUID: Int]) -> some View {
        // The finished shelf in order, to tell whether this pile opens its year.
        let all = piles(shelfBooks(reading?.books ?? [], "finished"))
        let year = pile.first.flatMap { pileYear($0.book) }
        let index = all.firstIndex { $0.first?.key == pile.first?.key }
        let starts = index.map { $0 == 0 || pileYear(all[$0 - 1][0].book)?.primary != year?.primary } ?? true
        return VStack(spacing: 0) {
            if starts {
                VStack(spacing: 0) {
                    Text(year?.primary ?? "قديمًا").font(MadarTypography.fine().weight(.semibold))
                    if let secondary = year?.secondary { Text(secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                }.padding(.bottom, 4).accessibilityElement(children: .combine).accessibilityIdentifier("mihbara-pile-year")
            }
            ForEach(pile, id: \.key) { item in
                Button { openBook(item.book, volume: item.volume) } label: { lying(item, leather: leathers[item.book.id] ?? 0) }
                    .buttonStyle(.madarPlain).contextMenu { bookMenu(item.book) }.accessibilityLabel(shelfLabel(item.book)).accessibilityIdentifier("mihbara-book-" + item.book.id.uuidString)
            }
        }
    }

    private static let lyingScale: CGFloat = 0.8
    /// A finished book lying on its side, a little askew, as books left on a shelf after reading.
    private func lying(_ item: PileItem, leather: Int) -> some View {
        let shape = shapes[item.book.id]
        let size = MihbaraBookSpine.size(pagesPerVolume: shape?.pages.map { $0 / max(1, shape?.volumes ?? 1) } ?? item.book.pages)
        let seed = item.key.unicodeScalars.reduce(0) { ($0 &* 31 &+ Int($1.value)) % 9973 }
        let tilt = Double(seed % 7) - 3, shift = CGFloat(seed % 13) - 6
        // A little smaller than the standing books, so two piles share a shelf.
        return MihbaraBookSpine(book: item.book, shape: shape, leather: leather, digits: service.digits, volume: item.volume, lying: true)
            .rotationEffect(.degrees(-90))
            .scaleEffect(Self.lyingScale)
            .frame(width: size.height * Self.lyingScale, height: size.width * Self.lyingScale)
            .rotationEffect(.degrees(tilt)).offset(x: shift)
    }
    /// The spine shows a short title; VoiceOver hears the whole book: full title, author, size and progress.
    private func shelfLabel(_ b: MihbaraBook) -> String {
        var parts = [b.title]
        if !b.author.isEmpty { parts.append(b.author) }
        if let size = MihbaraBookCovers.sizeWord(shapes[b.id], service.digits) { parts.append(size) }
        if b.shelf == "reading", let p = MihbaraCopy.progressPercent(b.progress) { parts.append("قرأت " + service.digits.string(p) + "٪") }
        if b.shelf == "old" { parts.append("قرأته قديمًا") } else if b.shelf == "finished", let year = pileYear(b) { parts.append("أنهيته في " + year.primary) }
        return parts.joined(separator: "، ")
    }
    /// What an empty shelf says depends on which shelf it is and on what the other shelves hold.
    /// The bookcase before the first book.
    private func emptyShelf(_ r: MihbaraHomeReading) -> some View {
        Button { showingAddBook = true } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("أضف كتابك الأول").font(MadarTypography.cardTitle())
                Text("ضع كتابًا من مكتبتك على الرف، واحفظ أين وصلت.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }.frame(maxWidth: .infinity, minHeight: 95, alignment: .leading).contentShape(.rect)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-empty-shelf-add")
    }
    private func shelfTotal(_ count: Int) -> String {
        count == 0 ? "" : count == 1 ? "كتاب واحد على رفّك" : MihbaraCopy.books(count, service.digits) + " على رفوفك"
    }
    /// Owner, 21–22 Oct 2026: the desk is the stand in front of the bookcase. One large open book at your place, one
    /// button that continues it, and the day's wird under the stand.
    private func desk(_ r: MihbaraHomeReading) -> some View {
        VStack(spacing: 14) {
            HStack(alignment: .top) {
                if !RoomHomeLayout(session: app, key: "mihbara.layout").hidden.contains("notebook") {
                Button { notebookRouteID = nil; sheet = .notebook } label: {
                    // The notebook stays yellow in dark, so its label keeps the light room's ink.
                    Text("دفتر").font(.custom("ArefRuqaa-Regular", size: 18, relativeTo: .headline))
                        .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink).frame(width: 58, height: 70)
                        .background(theme.color("notebookYellow"), in: .rect(topLeadingRadius: 2, bottomLeadingRadius: 10, bottomTrailingRadius: 2, topTrailingRadius: 2))
                        .overlay(alignment: .top) { Rectangle().fill(theme.color("goldUnderstandText").opacity(0.7)).frame(height: 3).padding(.horizontal, 5) }
                        .shadow(color: theme.ink.opacity(0.18), radius: 5, y: 4).rotationEffect(.degrees(-3))
                }.buttonStyle(.madarPlain).accessibilityLabel("الدفتر الخاص").accessibilityHint("ملاحظاتك الخاصة تبقى داخل المحبرة").accessibilityIdentifier("mihbara-notebook")
                }
                Spacer(minLength: 8)
                if let b = tableBook, hasSavedPosition(b) { deskLabel("موضعك محفوظ").padding(.top, 12) }
                Spacer(minLength: 8)
                Button { sheet = .opening } label: {
                    Image(systemName: "slider.horizontal.3").font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(theme.ink).frame(width: 46, height: 46)
                }
                .buttonStyle(.madarPlain)
                .glassEffect(.regular.interactive(), in: Circle())
                .accessibilityLabel("وقت فتح ورد السنّة").accessibilityIdentifier("mihbara-opening-preference")
            }
            if let b = tableBook {
                if b.isReadableEPUB || b.isReadablePDF { fileTableBook(b) } else { paperTableBook(b) }
            } else {
                // With books waiting, the empty stand points at them rather than at «أضف». With no book at all, the shelf above
                // already invites the first one, so the stand says what it is for (all-data walk, 24 Oct 2026).
                let waiting = r.books.filter { $0.shelf == "want" }.count
                let placeholder = VStack(spacing: 12) {
                    Image(systemName: "book.pages").font(.largeTitle)
                    Text("مكان كتابك").font(MadarTypography.cardTitle())
                    Text(waiting > 0 ? "اختر كتابًا من «أبي أقرأها» (" + MihbaraCopy.books(waiting, service.digits) + ")، واضغطه مطوّلًا ثم «ابدأ قراءته»" : r.books.isEmpty ? "هنا يوضع الكتاب الذي تقرؤه، وتكمل منه حيث وقفت" : "أضف كتابًا وابدأ من موضعك")
                        .font(MadarTypography.caption()).multilineTextAlignment(.center).padding(.horizontal, 16)
                }.frame(maxWidth: .infinity, minHeight: 210).background(theme.surface, in: .rect(cornerRadius: 5))
                    .overlay { RoundedRectangle(cornerRadius: 5).stroke(theme.line, style: .init(lineWidth: 1, dash: [4,4])) }
                    .foregroundStyle(theme.ink)
                if r.books.isEmpty {
                    // Audit 28 Oct: the dashed stand looks tappable, so it is: it adds the first book.
                    Button { showingAddBook = true } label: { placeholder }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-empty-stand")
                } else {
                    Button { if waiting > 0 { scrollTarget = "want" } else { showingAddBook = true } } label: { placeholder }
                        .buttonStyle(.madarPlain)
                }
            }
            // The stand's crossed legs.
            ZStack { RoundedRectangle(cornerRadius: 7).fill(theme.color("desk")).frame(width: 190, height: 12).rotationEffect(.degrees(13)); RoundedRectangle(cornerRadius: 7).fill(theme.color("desk")).frame(width: 190, height: 12).rotationEffect(.degrees(-13)); Circle().fill(theme.color("goldUnderstand")).frame(width: 10) }.frame(height: 44).accessibilityHidden(true)
            wirdStrip(r)
        }.padding(18).padding(.vertical, 6).background(LinearGradient(colors: [theme.color("wood").opacity(0.78), theme.color("wood")], startPoint: .top, endPoint: .bottom), in: .rect(topLeadingRadius: 26, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 26))
    }
    /// The day's wird under the stand: which hadith, its opening words, how far through the collection, and «افهمه».
    @ViewBuilder private func wirdStrip(_ r: MihbaraHomeReading) -> some View {
        let hadith = r.todayHadiths.first
        let open = (r.opensAfterFajr || manuallyOpen || app.string("mihbara.rahlOpens") == "untilDone") && hadith != nil
        if open, let h = hadith {
            let left = r.collection.hadiths.count - r.readCount
            Button { sheet = .hadith(h.number) } label: {
                HStack(spacing: 12) {
                    RoundedRectangle(cornerRadius: 3).fill(theme.color("sunnahLeather").gradient).frame(width: 30, height: 44)
                        .overlay(alignment: .leading) { Rectangle().fill(theme.color("goldUnderstand")).frame(width: 3) }.accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text("ورد اليوم: " + h.title).font(MadarTypography.cardTitle()).lineLimit(2)
                        Text(excerpt(hadithMatn(h.text))).font(MadarTypography.caption()).lineLimit(1)
                        Text(r.readCount == 0 ? MihbaraCopy.hadiths(r.collection.hadiths.count, service.digits) + " تنتظرك" : service.digits.string(r.readCount) + " من " + service.digits.string(r.collection.hadiths.count) + "، " + (left <= 0 ? "أتممت الأربعين" : "بقي " + MihbaraCopy.hadiths(left, service.digits)))
                            .font(MadarTypography.fine())
                    }
                    Spacer(minLength: 4)
                    Text("افهمه").font(MadarTypography.caption().weight(.semibold)).padding(.horizontal, 12).frame(minHeight: 36)
                        .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink).background(theme.color("goldUnderstand"), in: .capsule)
                }
                .padding(12).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.color("desk"), in: .rect(cornerRadius: 14)).foregroundStyle(theme.color("onDesk"))
            }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-wird-open")
        } else {
            Button { manuallyOpen = true; if let h = hadith { sheet = .hadith(h.number) } } label: {
                HStack { Image(systemName: r.completedToday > 0 ? "checkmark.seal" : "book.closed"); VStack(alignment: .leading, spacing: 4) { Text(r.completedToday > 0 ? "أتممت ورد اليوم" : r.readCount == 42 ? "أتممت الأربعين النووية" : "وردك بعد الفجر").font(MadarTypography.cardTitle()); if r.completedToday > 0 { Text("الحديث القادم في يومك الجديد").font(MadarTypography.caption()) } }; Spacer() }.padding(16).background(theme.color("sunnahLeather"), in: .rect(cornerRadius: 12)).foregroundStyle(theme.onAccent)
            }.buttonStyle(.madarPlain).disabled(hadith == nil).accessibilityIdentifier("mihbara-wird-closed")
        }
    }
    /// The stand's one action, under the open book: where you continue, in pages.
    private func continueButton(_ title: String, _ b: MihbaraBook) -> some View {
        Button { openBook(b) } label: {
            Text(title).font(MadarTypography.body().weight(.semibold)).padding(.horizontal, 22).frame(minHeight: 48)
                .foregroundStyle(theme.onAccent).background(theme.accent, in: .capsule)
                .shadow(color: .black.opacity(0.25), radius: 5, y: 3)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-book-continue")
    }
    private func finishedHint(_ b: MihbaraBook) -> some View {
        Button { moveBook(b, to: "finished") } label: {
            Label("وصلت إلى آخره؟ انقله إلى «أنهيتها»", systemImage: "checkmark.circle").font(MadarTypography.caption())
                .padding(.horizontal, 14).frame(minHeight: 44).foregroundStyle(theme.color("onDesk"))
                .background(theme.color("desk"), in: .capsule)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-book-mark-finished")
    }
    /// A paper book on the stand: the right page names it, the left says where you are and what is left.
    private func paperTableBook(_ b: MihbaraBook) -> some View {
        let currentPage = b.page.flatMap { $0 > 0 ? $0 : nil }
        let nextPage: Int? = currentPage.flatMap { page -> Int? in
            guard b.pages.map({ page < $0 }) ?? true else { return nil }
            return page + 1
        }
        let remaining = b.shelf == "finished" ? nil : MihbaraCopy.remaining(pages: b.pages, read: currentPage, service.digits)
        return VStack(spacing: 12) {
            MihbaraOpenBook(
                theme: theme, sunnah: false,
                rightHeader: b.author, rightTitle: b.title, rightText: b.pages.map { MihbaraCopy.pages($0, service.digits) } ?? "كتاب ورقي",
                rightFooter: currentPage.map(service.digits.string) ?? "",
                leftHeader: "موضعك", leftTitle: "وصلت إلى", leftText: currentPage.map { "صفحة " + service.digits.string($0) } ?? "بداية الكتاب",
                leftFooter: remaining ?? "", action: "", ribbon: false
            ) { openBook(b) }
            continueButton(currentPage == nil ? "ابدأ القراءة" : nextPage.map { "أكمل من صفحة " + service.digits.string($0) } ?? "أكمل", b)
            if let currentPage, let total = b.pages, currentPage >= total, b.shelf == "reading" { finishedHint(b) }
        }
    }
    private func hasSavedPosition(_ b: MihbaraBook) -> Bool {
        (b.isReadableEPUB || b.isReadablePDF) ? b.progress != nil : (b.page ?? 0) > 0
    }
    /// An EPUB or PDF on the table: what it is, how far the reader is, and what is left, with no figure shown twice.
    private func fileTableBook(_ b: MihbaraBook) -> some View {
        let digits = service.digits
        // AU-25: a book opened but not read yet is «لم تبدأه بعد», not «قرأت منه ٠٪».
        let percent = MihbaraCopy.progressPercent(b.progress)
        let kind = b.format == "epub" ? "كتاب إلكتروني" : b.format == "pdfScanned" ? "ملف PDF مصوّر" : "ملف PDF"
        let total = b.pages.flatMap { $0 > 0 ? $0 : nil }
        let read = MihbaraCopy.pagesRead(b)
        let left: String
        if let percent, percent >= 100 { left = "أتممت قراءته" }
        else if let total, let read, total - read > 0 { left = MihbaraCopy.pagesLeft(total - read, digits) }
        else if let percent { left = "بقي " + digits.string(100 - percent) + "٪" }
        else { left = "" }
        let nearlyDone = (percent ?? 0) >= 99 && b.shelf == "reading"
        let action: String
        if percent == nil { action = "ابدأ القراءة" }
        else if let total, let read, read < total { action = "أكمل من صفحة " + digits.string(read + 1) }
        else { action = "أكمل القراءة" }
        return VStack(spacing: 12) {
            MihbaraOpenBook(
                theme: theme, sunnah: false,
                rightHeader: b.author, rightTitle: b.title, rightText: kind,
                rightFooter: total.map { MihbaraCopy.pages($0, digits) } ?? "",
                leftHeader: "موضعك", leftTitle: percent == nil ? "لم تبدأه بعد" : "قرأت منه",
                leftText: percent.map { digits.string($0) + "٪" } ?? "بداية الكتاب",
                leftFooter: left, action: "", ribbon: false
            ) { openBook(b) }
            continueButton(action, b)
            if nearlyDone { finishedHint(b) }
        }
    }
    private func sunnahDrawer(_ r: MihbaraHomeReading) -> some View {
        let count = r.collection.hadiths.count
        let nextHadith = r.todayHadiths.first ?? r.collection.hadiths.first
        return VStack(spacing: 0) {
            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.25)) { sunnahDrawerOpen.toggle() }
            } label: {
                HStack(spacing: 12) {
                    Text("درج كتب السنّة، كتاب واحد")
                        .font(MadarTypography.caption()).padding(.horizontal, 12).padding(.vertical, 9)
                        .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink).background(theme.color("goldUnderstand"), in: .rect(cornerRadius: 5))
                    Spacer(minLength: 0)
                    Capsule().fill(theme.color("goldUnderstand")).frame(width: 58, height: 10)
                        .shadow(color: .black.opacity(0.2), radius: 2, y: 2)
                    Spacer(minLength: 0)
                    Text(sunnahDrawerOpen ? "أغلقه" : "اسحبه").font(MadarTypography.fine()).foregroundStyle(theme.color("onDesk")).padding(7).background(theme.color("desk"), in: .capsule)
                }
                .padding(12).frame(minHeight: 64)
                .background(LinearGradient(colors: [theme.color("wood"), theme.color("desk")], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 9))
                .overlay { RoundedRectangle(cornerRadius: 9).stroke(theme.color("onDesk").opacity(0.12), lineWidth: 1) }
                .shadow(color: theme.ink.opacity(0.22), radius: 4, y: 4)
            }.buttonStyle(.madarPlain)
                .accessibilityIdentifier("mihbara-sunnah-drawer")
                .accessibilityValue(sunnahDrawerOpen ? "مفتوح" : "مغلق")
                .accessibilityHint("كتب السنّة وتقدمك فيها")
            if sunnahDrawerOpen {
                VStack(spacing: 14) {
                    HStack(spacing: 12) {
                        RoundedRectangle(cornerRadius: 4).fill(theme.color("sunnahLeather").gradient)
                            .frame(width: 31, height: 53)
                            .overlay(alignment: .leading) { Rectangle().fill(theme.color("goldUnderstand").opacity(0.45)).frame(width: 2).padding(.vertical, 7) }
                            .accessibilityHidden(true)
                        VStack(alignment: .leading, spacing: 5) {
                            Text(r.collection.title).font(.custom("thmanyahserifdisplay-Bold", size: 17, relativeTo: .headline)).foregroundStyle(theme.color("onDesk"))
                            Text(r.readCount == 0 ? "لم تبدأ الأربعين بعد" : "فهمت " + MihbaraCopy.hadithsObject(r.readCount, service.digits) + " من " + service.digits.string(count))
                                .font(MadarTypography.fine()).foregroundStyle(theme.color("onDesk"))
                        }
                        Spacer(minLength: 0)
                        Text("على المكتب").font(MadarTypography.fine()).padding(.horizontal, 9).padding(.vertical, 7)
                            .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink).background(theme.color("goldUnderstand"), in: .rect(cornerRadius: 7))
                        if let nextHadith {
                            Button(r.todayHadiths.isEmpty ? "اقرأ" : "الورد") { sheet = .hadith(nextHadith.number) }
                                .font(MadarTypography.caption()).frame(minWidth: 48, minHeight: 44)
                                .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink).background(theme.color("goldUnderstand"), in: .capsule)
                                .accessibilityIdentifier("mihbara-sunnah-drawer-read")
                        }
                    }.padding(8)
                    Button { showingAddBook = true } label: {
                        Label("أضف كتابًا من ملف", systemImage: "plus")
                            .font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(theme.color("onDesk"))
                            .overlay { RoundedRectangle(cornerRadius: 10).stroke(theme.color("onDesk").opacity(0.6), style: .init(lineWidth: 1, dash: [4, 3])) }
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-sunnah-drawer-add")
                }.padding(12).background(theme.color("desk"), in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 12))
                    .padding(.horizontal, 8).transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
    }
    /// OR-32, owner mockup A (26 Oct): the drawer gives way to «أكمل من حيث وقفت». The stand already continues the book
    /// on it, so this card names the last book you opened that is not on the stand; with none, it stays away.
    private func lastReadBook(_ r: MihbaraHomeReading) -> MihbaraBook? {
        r.books.first { $0.id != tableBook?.id && $0.shelf == "reading" && hasSavedPosition($0) }
    }
    private func continueCard(_ b: MihbaraBook, leather: Int) -> some View {
        let digits = service.digits
        // AU-25: a book opened but not read yet is «لم تبدأه بعد», not «قرأت منه ٠٪».
        let percent = MihbaraCopy.progressPercent(b.progress)
        let read = (b.isReadableEPUB || b.isReadablePDF) ? MihbaraCopy.pagesRead(b) : b.page
        let total = b.pages.flatMap { $0 > 0 ? $0 : nil }
        let where_: String = {
            if let read, let total { return "صفحة " + digits.string(read) + " من " + digits.string(total) }
            if let read { return "صفحة " + digits.string(read) }
            return "موضعك محفوظ"
        }()
        return HStack(alignment: .center, spacing: 16) {
            MihbaraBookCover(book: b, shape: shapes[b.id], leather: leather, digits: digits)
                .scaleEffect(0.78).frame(width: 96, height: 128)
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 8) {
                Text("أكمل من حيث وقفت").font(MadarTypography.fine()).foregroundStyle(theme.color("onDesk").opacity(0.85))
                Text(MihbaraBookCovers.split(b.title).main)
                    .font(.custom("thmanyahserifdisplay-Bold", size: 20, relativeTo: .title3))
                    .foregroundStyle(theme.color("onDesk")).lineLimit(2)
                HStack(spacing: 8) {
                    Text(where_).font(MadarTypography.caption())
                    if let percent { Text(digits.string(percent) + "٪").font(MadarTypography.caption()).bold() }
                }.foregroundStyle(theme.color("onDesk"))
                if let p = b.progress {
                    Capsule().fill(theme.color("onDesk").opacity(0.18)).frame(height: 5)
                        .overlay(alignment: .leading) {
                            GeometryReader { g in Capsule().fill(theme.color("goldUnderstand")).frame(width: max(5, g.size.width * p)) }
                        }
                        .accessibilityHidden(true)
                }
                Button { openBook(b) } label: {
                    // A paper book opens its card, where its page is kept; a file opens at its place.
                    Text(b.isReadableEPUB || b.isReadablePDF ? "أكمل القراءة" : "افتح الكتاب").font(MadarTypography.caption()).bold()
                        .foregroundStyle(RoomTheme(room: "mihbara", dark: false).ink)
                        .padding(.horizontal, 18).frame(minHeight: 44)
                        .background(theme.color("goldUnderstand"), in: .capsule)
                }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-continue-reading")
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(theme.color("desk"), in: .rect(cornerRadius: 16))
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.color("onDesk").opacity(0.12), lineWidth: 1) }
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("mihbara-continue-card")
    }
    @State private var folded = false
    private func deskLabel(_ text: String, title: Bool = false) -> some View {
        Group {
            if title { Text(text).font(MadarTypography.cardTitle()).foregroundStyle(theme.color("onDesk")) }
            else { Text(text).font(MadarTypography.fine()).foregroundStyle(theme.color("onDesk")).padding(.horizontal, 10).padding(.vertical, 7).background(theme.color("desk"), in: .capsule) }
        }
    }
    private func excerpt(_ text: String) -> String { text.count <= 165 ? text : String(text.prefix(165)).split(separator: " ").dropLast().joined(separator: " ") + "…" }
    private func hadithMatn(_ text: String) -> String {
        let parts = text.split(separator: "\"", omittingEmptySubsequences: false)
        guard parts.count >= 3 else { return text }
        return parts.dropFirst().dropLast().joined(separator: "\"").trimmingCharacters(in: .whitespacesAndNewlines)
    }
    private func library(_ r: MihbaraHomeReading) -> some View {
        let leathers = MihbaraBookCovers.leatherIndices(for: r.books)
        let query = foldedForSearch(libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines))
        let matchingBookIDs = Set(r.books.lazy.filter { book in
            let matchesText = query.isEmpty || foldedForSearch(book.title + " " + book.author).contains(query)
            return matchesText && (libraryShelf == "all" || libraryShelf == book.shelf)
        }.map(\.id))
        return ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack {
                    Text("مكتبتي").font(MadarTypography.title())
                    Spacer()
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1" {
                        Button("اختبر الطاولة") { app.open(URL(string: "madar://mihbara/desk")!) }
                            .accessibilityIdentifier("mihbara-desk-test-route")
                    }
                    if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_LIBRARY_ACTION_ROUTE_HARNESS"] == "1",
                       let book = r.books.first {
                        Button("اختبر الاسم ثم الرابط") {
                            scheduleLibraryAction(.rename(book))
                            app.open(URL(string: "madar://mihbara/hadith/today")!)
                        }
                        .accessibilityIdentifier("ui-test-mihbara-rename-then-route")
                    }
#endif
                    Button("تمّ") { sheet = nil }.frame(minWidth: 44, minHeight: 44)
                }
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 70).fill(theme.color("navy").gradient)
                    Circle().fill(theme.color("goldUnderstand")).frame(width: 40, height: 40).offset(x: -55, y: -5)
                    Rectangle().fill(theme.surface).frame(width: 5)
                    Rectangle().fill(theme.surface).frame(height: 4)
                }.frame(height: 125).padding(.horizontal, 65).accessibilityHidden(true)
                TextField("ابحث في كتبك…", text: $libraryQuery).font(MadarTypography.body()).padding(15).background(theme.surface, in: .capsule).accessibilityIdentifier("mihbara-library-search")
                Picker("رفّ الكتب", selection: $libraryShelf) { Text("كل الكتب").tag("all"); Text("أقرؤها الآن").tag("reading"); Text("أبي أقرأها").tag("want"); Text("أنهيتها").tag("finished"); Text("قديمًا").tag("old") }.pickerStyle(.menu)
                MihbaraTextSearchSection(query: libraryQuery, books: r.books, service: service) { hit in
                    sheet = nil
                    readerRoute = MihbaraReaderRoute(bookID: hit.bookID, page: hit.pdfPage, locatorJSON: hit.locatorJSON)
                }
                libraryStatus(r, matchingBookCount: matchingBookIDs.count)
                // Owner, 21 Oct 2026: the «قديمًا» cabinet is a section here now, after the three shelves.
                ForEach(Self.librarySections, id: \.shelf) { section in
                    // A search or shelf filter leaves only what matches; a grid of dimmed covers is still in the way.
                    let books = r.books.filter { $0.shelf == section.shelf && matchingBookIDs.contains($0.id) }
                    if !books.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text(section.title).font(MadarTypography.section())
                            if let note = section.note { Text(note).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                        }.padding(.top, 6).accessibilityAddTraits(.isHeader).accessibilityIdentifier("mihbara-library-section-" + section.shelf)
                        // OR-32 (owner mockup A): the library is a wall of covers, three to a row.
                        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 12, alignment: .top), count: 3), spacing: 18) {
                            ForEach(books) { b in libraryCover(b, leather: leathers[b.id] ?? 0) }
                        }
                    }
                }
                // Owner, 30 Oct 2026: «سلة المحذوفات» — what was deleted by mistake comes back after the undo is gone.
                NavigationLink {
                    MihbaraTrashView(app: app, onRestored: { load() }).environment(\.roomTheme, theme)
                } label: {
                    Label("سلة المحذوفات", systemImage: "trash").font(MadarTypography.body())
                        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading).padding(.horizontal, 16)
                        .background(theme.surface, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.madarPlain).padding(.top, 8).accessibilityIdentifier("mihbara-library-trash")
            }.padding(20)
        }.background(theme.background).foregroundStyle(theme.ink)
    }
    private static let librarySections: [(shelf: String, title: String, note: String?)] = [
        ("reading", "أقرؤها الآن", nil), ("want", "أبي أقرأها", nil), ("finished", "أنهيتها", nil),
        ("old", "قديمًا", "كتب قرأتها منذ زمن، وتستقر أيضًا أسفل «أنهيتها» في الغرفة."),
    ]
    private func libraryCover(_ b: MihbaraBook, leather: Int) -> some View {
        Button { openBook(b) } label: {
            VStack(spacing: 5) {
                MihbaraBookCover(book: b, shape: shapes[b.id], leather: leather, digits: service.digits)
                    .scaleEffect(0.7).frame(width: 88, height: 118)
                    .accessibilityHidden(true)
                Text(b.title).font(MadarTypography.fine()).lineLimit(2).multilineTextAlignment(.center)
                HStack(spacing: 4) {
                    Text(libraryShelfName(b.shelf))
                    if let p = MihbaraCopy.progressPercent(b.progress), b.shelf != "finished" { Text(service.digits.string(p) + "٪") }
                }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                Text(libraryDetail(b)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1)
                    .minimumScaleFactor(0.85)
            }.frame(maxWidth: .infinity).contentShape(.rect)
        }
        .buttonStyle(.madarPlain)
        .contextMenu { bookMenu(b) }
        .accessibilityIdentifier("mihbara-library-book-" + b.id.uuidString)
    }
    private func libraryRow(_ b: MihbaraBook, matchingBookIDs: Set<UUID>) -> some View {
                    Button { openBook(b) } label: {
                        HStack(spacing: 12) {
                            Image(systemName: b.isReadablePDF ? "doc.text" : b.isReadableEPUB ? "book" : "book.closed").font(.title3).foregroundStyle(theme.secondaryInk).frame(width: 28)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(b.title).font(MadarTypography.cardTitle())
                                Text(b.author).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                Text(libraryDetail(b)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }
                            Spacer(minLength: 8)
                            VStack(alignment: .trailing, spacing: 3) {
                                Text(libraryShelfName(b.shelf)).font(MadarTypography.fine())
                                if let p = MihbaraCopy.progressPercent(b.progress), b.shelf != "finished" { Text(service.digits.string(p) + "٪").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                            }
                        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.madarPlain).opacity(matchingBookIDs.contains(b.id) ? 1 : 0.3)
                        .contextMenu { bookMenu(b) }
                        .accessibilityIdentifier("mihbara-library-book-" + b.id.uuidString)
    }

    private func foldedForSearch(_ text: String) -> String {
        text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Locale(identifier: "ar"))
    }
    private func libraryShelfName(_ shelf: String) -> String {
        switch shelf { case "reading": "أقرؤه"; case "want": "أبي أقرأه"; case "old": "قديمًا"; default: "أنهيته" }
    }
    /// «ملف PDF، ٣٠٠ صفحة»: what the book is and how big, so rows with the same title are told apart.
    private func libraryDetail(_ b: MihbaraBook) -> String {
        let kind = b.isReadableEPUB || b.format == "epub" ? "كتاب إلكتروني" : b.format == "pdfScanned" ? "ملف PDF مصوّر" : b.format == "pdf" ? "ملف PDF" : "كتاب ورقي"
        guard let pages = b.pages, pages > 0 else { return kind }
        return kind + "، " + MihbaraCopy.pages(pages, service.digits)
    }
    @ViewBuilder private func libraryStatus(_ r: MihbaraHomeReading, matchingBookCount: Int) -> some View {
        let query = libraryQuery.trimmingCharacters(in: .whitespacesAndNewlines)
        if r.books.isEmpty {
            Text("لم تضف كتبًا بعد. أضف أول كتاب من الرف، فتجده هنا.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
        } else if !query.isEmpty || libraryShelf != "all" {
            Text(matchingBookCount == 0 ? "لا كتاب يطابق بحثك، وكل كتبك باقية في مكانها." : "المطابق: " + MihbaraCopy.books(matchingBookCount, service.digits) + "، وكل كتبك باقية في مكانها.")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("mihbara-library-status")
        } else {
            Text(MihbaraCopy.books(r.books.count, service.digits) + " في مكتبتك.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }
    }

    @discardableResult private func openBook(_ book: MihbaraBook, volume: Int? = nil, locatorJSON: String? = nil) -> MihbaraBookOpenResult {
        if case .library? = sheet {
            scheduleLibraryAction(.open(book, volume: volume, locatorJSON: locatorJSON))
            return .deferred
        }
        guard book.isReadableEPUB || book.isReadablePDF else { sheet = .book(book.id); return .opened }
        guard service.hasLocalFile(for: book) else { sheet = .book(book.id); return .opened }
        do {
            // A reader can close while its last locator is being committed. Refresh
            // the managed generation before constructing the next reader route.
            try app.reload()
            reading = try service.load()
            let pdfPage = book.isReadablePDF ? MihbaraPDFLocator.pageIndex(locatorJSON: locatorJSON, fileHash: book.fileHash) : nil
            readerRoute = MihbaraReaderRoute(bookID: book.id, volume: volume, page: pdfPage, locatorJSON: locatorJSON)
            return .opened
        } catch {
            app.errorMessage = madarUserMessage(error)
            shelfReadFailed = true
            shelfReadError = "تعذّر فتح الكتاب الآن. كتبك محفوظة في مكانها؛ حاول مرة أخرى."
            return .failed
        }
    }

}
private enum MihbaraRemovalConfirmation { case book(MihbaraBook), file(MihbaraBook) }
private enum MihbaraSheet: Identifiable { case library, book(UUID), hadith(Int), opening, notebook, motivation; var id: String { String(describing: self) } }
private enum MihbaraLibraryAction { case rename(MihbaraBook), remove(MihbaraRemovalConfirmation), open(MihbaraBook, volume: Int?, locatorJSON: String?) }
private enum MihbaraBookOpenResult { case opened, deferred, failed }
private struct MihbaraGoalEditor: Identifiable { let reading: HabitReading?; var id: UUID { reading?.id ?? fresh }; private let fresh = UUID()
    init(reading: HabitReading?) { self.reading = reading }
}
private struct MihbaraRenameAlert: ViewModifier {
    @Binding var book: MihbaraBook?
    @Binding var title: String
    @Binding var author: String
    let save: () -> Void
    let onDismiss: () -> Void

    func body(content: Content) -> some View {
        content.alert("اسم الكتاب", isPresented: Binding(get: { book != nil }, set: { if !$0 { book = nil; onDismiss() } })) {
            TextField("عنوان الكتاب", text: $title).accessibilityIdentifier("mihbara-rename-title")
            TextField("المؤلف", text: $author).accessibilityIdentifier("mihbara-rename-author")
            Button("احفظ", action: save).disabled(title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("mihbara-rename-save")
            Button("إلغاء", role: .cancel) { book = nil; onDismiss() }
        } message: {
            let sourceTitle = title.isEmpty ? (book?.title ?? "") : title
            Text("على الرف: «" + BookTitle.parts(sourceTitle).short + "»")
        }
    }
}
private struct MihbaraHomeConfirmations: ViewModifier {
    @Binding var slotBook: MihbaraBook?
    @Binding var pendingRemoval: MihbaraRemovalConfirmation?
    let replacementBooks: (MihbaraBook) -> [MihbaraBook]
    let removalTitle: String
    let moveToReading: (MihbaraBook, UUID) -> Void
    let beginLibraryActionWrite: () -> Void
    let onDismiss: () -> Void
    let deleteBook: (MihbaraBook) -> Void
    let removeBookFile: (MihbaraBook) -> Void

    func body(content: Content) -> some View {
        content
            .confirmationDialog("رف «أقرأها» ممتلئ: اختر كتابًا يرجع إلى «أبي أقرأها»", isPresented: Binding(get: { slotBook != nil }, set: { if !$0 { slotBook = nil; onDismiss() } }), titleVisibility: .visible, presenting: slotBook) { incoming in
                ForEach(replacementBooks(incoming)) { old in
                    Button(old.title) { moveToReading(incoming, old.id) }
                }
            }
            .confirmationDialog(removalTitle, isPresented: Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil; onDismiss() } }), titleVisibility: .visible) {
                if let pendingRemoval {
                    switch pendingRemoval {
                    case .book(let book): Button("احذف من مكتبتي", role: .destructive) { beginLibraryActionWrite(); deleteBook(book) }
                    case .file(let book): Button("احذف ملف الكتاب", role: .destructive) { beginLibraryActionWrite(); removeBookFile(book) }
                    }
                }
                Button("إلغاء", role: .cancel) { pendingRemoval = nil; onDismiss() }
            } message: {
                if case .book? = pendingRemoval {
                    Text("يبقى عنوانه وسجل جلسات القراءة وتظليلاته وملفه محفوظة؛ يختفي الكتاب من رفوف المحبرة فقط.")
                } else if case .file? = pendingRemoval {
                    Text("يبقى عنوان الكتاب وموضعه وجلساته وتظليلاته. لا تراجع، ويعود الملف إن اخترته نفسه من «من ملف».")
                }
            }
    }
}
private struct MihbaraReaderCover: ViewModifier {
    let app: AppSession
    @Binding var route: MihbaraReaderRoute?
    let theme: RoomTheme
    let bookForRoute: (UUID) -> MihbaraBook?
    let originalPDFID: (String) -> UUID?
    let onDismiss: () -> Void
    let onBookDetails: (UUID) -> Void

    func body(content: Content) -> some View {
        content.fullScreenCover(item: $route, onDismiss: onDismiss) { destination in
            if let book = bookForRoute(destination.bookID) {
                Group {
                    if book.isReadablePDF {
                        MihbaraPDFReaderView(app: app, book: book, startPage: destination.page) { route = nil }
                    } else {
                        MihbaraReaderView(app: app, book: book, volume: destination.volume,
                            initialLocatorJSON: destination.locatorJSON,
                            originalPDF: originalPDFID,
                            openOriginal: { id, page in route = MihbaraReaderRoute(bookID: id, page: page) }) { route = nil }
                    }
                }
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app)
            } else {
                VStack(spacing: 16) {
                    Text("ملف الكتاب غير متاح الآن").font(MadarTypography.body())
                    Button("تفاصيل الكتاب واستعادة ملفه") { route = nil; onBookDetails(destination.bookID) }.buttonStyle(MadarPrimaryButton())
                    Button("العودة إلى المحبرة") { route = nil }.buttonStyle(MadarPrimaryButton())
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(theme.background).foregroundStyle(theme.ink)
            }
        }
    }
}
/// Owner, 25 Oct 2026: «اول ما احمل بي دي اف يقولي ترا بحوله لك ولي انا الخيار».
private struct MihbaraConversionOffer: ViewModifier {
    let app: AppSession
    @Binding var book: MihbaraBook?
    func body(content: Content) -> some View {
        content.alert("نحوّله كتابًا منسابًا؟", isPresented: Binding(get: { book != nil }, set: { if !$0 { book = nil } })) {
            Button("حوّله") { if let book { MihbaraConversions.shared.start(book, app: app) }; book = nil }
                .accessibilityIdentifier("mihbara-offer-convert")
            Button("أبقه PDF", role: .cancel) { book = nil }
        } message: {
            Text("يُكبَّر خطه لشاشتك، ويبقى الـPDF الأصلي متاحًا من «الأصل».")
        }
    }
}

private struct MihbaraReaderRoute: Identifiable { let bookID: UUID; var volume: Int? = nil; var page: Int? = nil; var locatorJSON: String? = nil; var id: String { bookID.uuidString + "-\(volume ?? -1)-\(page ?? -1)-" + (locatorJSON ?? "") } }

enum MihbaraPDFLocator {
    static func pageIndex(locatorJSON: String?, fileHash: String?) -> Int? {
        guard let locatorJSON, let fileHash,
              let data = locatorJSON.data(using: .utf8),
              case .object(let object)? = try? JSONDecoder().decode(MadarCore.JSONValue.self, from: data),
              case .string(let routedHash)? = object["fileHash"], routedHash == fileHash,
              case .number(let number)? = object["pdfPageIndex"], number.isFinite,
              number >= 0, number < Double(Int.max), number.rounded(.down) == number else { return nil }
        return Int(number)
    }
}

private struct MihbaraMotivationCard: View {
    let cues: [MihbaraMotivationCue]
    let action: (MihbaraMotivationCue) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var index = 0
    private var cue: MihbaraMotivationCue? { cues.indices.contains(index) ? cues[index] : nil }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                if let cue {
                    VStack(alignment: .leading, spacing: 14) {
                        Text(cue.title).font(MadarTypography.cardTitle()).accessibilityIdentifier("mihbara-motivate-title")
                        Text(cue.message).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                            .accessibilityIdentifier("mihbara-motivate-message")
                        Text(cue.source).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("mihbara-motivate-source")
                    }
                    .padding(20).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: .rect(cornerRadius: 20))
                    .overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line.opacity(0.7), lineWidth: 1) }
                    .shadow(color: theme.ink.opacity(0.08), radius: 12, y: 5)

                    Button { action(cue) } label: {
                        Text(cue.actionTitle).font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 52)
                    }
                    .buttonStyle(MadarPrimaryButton())
                    .accessibilityIdentifier("mihbara-motivate-action")

                    if cues.count > 1 {
                        Button {
                            withAnimation(reduceMotion ? nil : .snappy(duration: 0.3)) { index = (index + 1) % cues.count }
                        } label: {
                            Text("اقتراح آخر").font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 46)
                        }
                        .buttonStyle(.madarPlain).glassEffect(.regular.interactive(), in: Capsule())
                        .accessibilityIdentifier("mihbara-motivate-next")
                    }
                } else {
                    Text("أتممت ورد اليوم. عد إلى كتابك حين يحين وقتك.")
                        .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                }
            }
            .padding(20).frame(maxWidth: 560).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.medium, .large])
        .toolbar {
            ToolbarItem(placement: .principal) { Text("حمّسني").font(MadarTypography.section()) }
            ToolbarItem(placement: .topBarTrailing) { Button("تمّ") { dismiss() }.accessibilityIdentifier("mihbara-motivate-close") }
        }
    }
}

private struct MihbaraRahlOpeningView: View {
    let app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    private let key = "mihbara.rahlOpens"
    private let choices = [("afterFajr", "بعد الفجر"), ("untilDone", "حتى يتمّه"), ("manual", "يدويًا")]
    private var selected: String {
        let value = app.string(key)
        return value.isEmpty ? "afterFajr" : value
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                if app.undoToastVisible {
                    UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).hostsUndo(app)
                        .accessibilityIdentifier("mihbara-undo")
                }
                Text("اختر متى ينفتح الرَّحل لوردك اليوم.")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                VStack(spacing: 10) {
                    ForEach(choices, id: \.0) { value, label in
                        let isSelected = selected == value
                        Button { app.set(.string(value), key: key) } label: {
                            HStack(spacing: 12) {
                                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                                Text(label).font(MadarTypography.section())
                                Spacer()
                            }
                            .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
                            .padding(.horizontal, 16)
                            .foregroundStyle(isSelected ? theme.onAccent : theme.ink)
                            .background(isSelected ? theme.color("sunnahLeather") : theme.surface, in: .rect(cornerRadius: 14))
                        }
                        .buttonStyle(.madarPlain)
                        .accessibilityValue(isSelected ? "محدد" : "غير محدد")
                        .accessibilityIdentifier("mihbara-rahlOpens-" + value)
                    }
                }
                Button("أعِد الإعداد الافتراضي") { app.reset([key]) }
                    .font(MadarTypography.caption()).frame(minHeight: 44)
                    .accessibilityIdentifier("mihbara-rahlOpens-reset")
            }.padding(20)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .toolbar {
            ToolbarItem(placement: .principal) { Text("فتح الرَّحل").font(MadarTypography.section()) }
            ToolbarItem(placement: .topBarTrailing) { Button("تمّ") { dismiss() }.accessibilityIdentifier("mihbara-rahlOpens-close") }
        }
    }
}

private struct MihbaraOldBooksCabinet: View {
    let books: [MihbaraBook]
    let theme: RoomTheme
    var shapes: [UUID: MihbaraBookShape] = [:]
    var digits: MadarNumberFormatter = .init()
    let openBook: (UUID) -> Void
    private var leathers: [UUID: Int] { MihbaraBookCovers.leatherIndices(for: books) }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Text("خزانة «قديمًا»").font(MadarTypography.cardTitle())
                Spacer()
                HStack(spacing: 5) {
                    Circle().fill(theme.color("onDesk").opacity(0.55)).frame(width: 3, height: 3)
                    Circle().fill(theme.color("onDesk").opacity(0.35)).frame(width: 3, height: 3)
                    Circle().fill(theme.color("onDesk").opacity(0.45)).frame(width: 3, height: 3)
                }.accessibilityHidden(true)
            }
            if books.isEmpty {
                Text("كتب أنهيتها منذ زمن تستقر هنا حين تستورد قراءاتك القديمة.")
                    .font(MadarTypography.caption())
                    .foregroundStyle(theme.color("onDesk"))
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(books) { book in
                            Button { openBook(book.id) } label: {
                                // The cabinet is desk-dark, so a desk-coloured leather would vanish; it takes the next one.
                                let index = leathers[book.id] ?? 0
                                MihbaraBookSpine(book: book, shape: shapes[book.id], leather: index == 3 ? 4 : index, digits: digits)
                            }
                            .buttonStyle(.madarPlain)
                            .accessibilityLabel("افتح كتابًا قديمًا: " + book.title)
                            .accessibilityHint("خيارات العودة إلى القراءة أو إلى رف أبي أقرأها")
                            .accessibilityIdentifier("mihbara-old-book-" + book.id.uuidString)
                        }
                    }.padding(.horizontal, 6).padding(.top, 10)
                }.scrollIndicators(.hidden)
                MihbaraShelfPlank().padding(.top, -12)
            }
        }
        .padding(14)
        .background(theme.color("desk"), in: .rect(cornerRadius: 16))
        .foregroundStyle(theme.color("onDesk"))
    }
}

struct MihbaraOpenBook: View {
    var theme: RoomTheme; var sunnah: Bool; var rightHeader: String; var rightTitle: String; var rightText: String; var rightFooter: String; var leftHeader: String; var leftTitle: String; var leftText: String; var leftFooter: String; var action: String; var ribbon = true; var open: () -> Void
    @Environment(\.dynamicTypeSize) private var type
    var body: some View {
        VStack(spacing: 0) {
            if type.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) { Text(rightTitle).font(MadarTypography.cardTitle()); Text(rightText).font(MadarTypography.body()); Text(leftTitle + " " + leftText).font(MadarTypography.body()); Button(action, action: open).frame(minHeight: 44) }.padding(18).background(theme.surface)
            } else {
                HStack(spacing: 2) {
                    page(header: rightHeader, title: rightTitle, text: rightText, footer: rightFooter)
                    page(header: leftHeader, title: leftTitle, text: leftText, footer: leftFooter)
                }.padding(sunnah ? 6 : 2).background(sunnah ? theme.color("sunnahLeather") : theme.surface, in: .rect(cornerRadius: 5)).shadow(color: theme.ink.opacity(0.25), radius: 9, y: 9)
                if ribbon { HStack { Spacer(); Button(action, action: open).font(MadarTypography.section()).frame(width: 50, height: 56).foregroundStyle(sunnah ? theme.color("goldUnderstandText") : theme.background).background(sunnah ? theme.color("notebookYellow") : theme.color("ribbonRead"), in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 2)).offset(y: -6).accessibilityIdentifier(sunnah ? "mihbara-wird-open" : "mihbara-book-continue") }.padding(.horizontal, 12).frame(height: 24) }
            }
        }
    }
    private func page(header: String, title: String, text: String, footer: String) -> some View {
        VStack(spacing: sunnah ? 8 : 12) { Text(header).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2); Spacer(minLength: 0); Text(title).font(.custom(sunnah ? "Amiri-Regular" : "Amiri-Bold", size: sunnah ? 16 : 23, relativeTo: .title2)).multilineTextAlignment(.center); Text(text).font(.custom("Amiri-Regular", size: sunnah ? 18 : 21, relativeTo: .body)).multilineTextAlignment(.center).lineLimit(sunnah ? 5 : 4); Spacer(minLength: 0); Text(footer).font(.custom("Amiri-Regular", size: 14, relativeTo: .caption)) }.padding(.horizontal, 12).padding(.vertical, sunnah ? 10 : 16).frame(maxWidth: .infinity).frame(minHeight: sunnah ? 180 : 220).background(theme.surface).overlay(alignment: .leading) { LinearGradient(colors: [theme.ink.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 15).allowsHitTesting(false) }
    }
}

/// iPad: a sheet full of reading or writing opens as a page instead of a small form. iPhone sheets are unchanged.
struct PadPageSheet: ViewModifier {
    let on: Bool
    func body(content: Content) -> some View {
        if on { content.presentationSizing(.page) } else { content }
    }
}
