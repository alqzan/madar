import SwiftUI
import SwiftData
import LocalAuthentication
import MadarCore
import MadarDesign
import MadarData

struct MihbaraHomeView: View {
    let app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var reading: MihbaraHomeReading?
    @State private var shelf = "reading"
    @State private var tableID: UUID?
    @State private var sheet: MihbaraSheet?
    @State private var manuallyOpen = false
    @State private var libraryQuery = ""
    @State private var libraryShelf = "all"
    private var theme: RoomTheme { .init(room: "mihbara", dark: colorScheme == .dark) }
    private var service: AppMihbaraService { .init(app: app) }
    private var tableBook: MihbaraBook? { reading?.books.first { $0.id == tableID } ?? reading?.books.first { $0.shelf == "reading" } }
    var body: some View {
        TimelineView(.periodic(from: Date(timeIntervalSince1970: 0), by: 60)) { tick in
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    HStack { Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right") }.accessibilityIdentifier("mihbara-back"); Spacer(); Text("المحبرة").font(MadarTypography.title()); Image(systemName: "books.vertical").font(.title2) }
                    if let r = reading {
                        MadarDateLabel(app.dateLabels(r.day)).foregroundStyle(theme.secondaryInk)
                        shelfView(r)
                        desk(r)
                    }
                }.padding(.horizontal, 16).padding(.top, 10).padding(.bottom, 28).frame(maxWidth: 650).frame(maxWidth: .infinity)
            }.onChange(of: tick.date) { load() }
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if app.undoToken != nil {
                UndoToast(message: app.undoMessage, undo: app.undo)
                    .accessibilityIdentifier("mihbara-undo")
            }
        }
        .task { load() }.onChange(of: app.prayerRevision) { load() }.onChange(of: reading?.day) { folded = false; manuallyOpen = false }
        .sheet(item: $sheet) { target in
            NavigationStack {
                if let r = reading {
                    switch target {
                    case .add: MihbaraPaperEditor(app: app, readingBooks: r.books.filter { $0.shelf == "reading" })
                    case .library: library(r)
                    case .book(let id): if let b = r.books.first(where: { $0.id == id }) { MihbaraBookCard(app: app, book: b, books: r.books) { tableID = id; sheet = nil } }
                    case .hadith(let n): if let h = r.collection.hadiths.first(where: { $0.number == n }) { MihbaraHadithView(app: app, hadith: h, collection: r.collection, day: r.day) }
                    case .notebook:
                        if let lock = app.lockController { MadarLockGate(controller: lock, feature: .app) { MihbaraNotebookView(app: app) } }
                        else { ProgressView("تُفتح بيانات المحبرة…") }
                    }
                }
            }.environment(\.roomTheme, theme).presentationDragIndicator(.visible)
        }
    }
    private func load() { do { reading = try service.load() } catch { app.errorMessage = error.localizedDescription } }
    private func shelfView(_ r: MihbaraHomeReading) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack { Text("رفّك").font(MadarTypography.cardTitle()); Spacer(); Button { sheet = .add } label: { Label("كتاب ورقي", systemImage: "plus") }.accessibilityIdentifier("mihbara-add-paper") }
            HStack(spacing: 8) {
                ForEach([("reading","أقرؤها الآن"),("want","أبي أقرأها"),("finished","أنهيتها")], id: \.0) { value in
                    Button { shelf = value.0 } label: { Text(value.1).font(MadarTypography.caption()).padding(.horizontal, 10).frame(minHeight: 44).background(shelf == value.0 ? theme.ink : .clear, in: .capsule).foregroundStyle(shelf == value.0 ? theme.background : theme.ink) }.accessibilityIdentifier("mihbara-shelf-" + value.0)
                }
            }.fixedSize(horizontal: false, vertical: true)
            let books = r.books.filter { $0.shelf == shelf }
            if books.isEmpty {
                VStack(alignment: .leading, spacing: 6) { Text(r.books.isEmpty ? "أضف كتابك الأول" : "مساحة لكتابك القادم").font(MadarTypography.cardTitle()); Text(r.books.isEmpty ? "ضع كتابًا من مكتبتك على الرف، واحفظ أين وصلت." : "انقل كتابًا إلى هذا الرف من بطاقته.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }.frame(maxWidth: .infinity, minHeight: 95, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 12) {
                        ForEach(books) { b in
                            Button { sheet = .book(b.id) } label: {
                                VStack(spacing: 8) {
                                    if b.id == tableBook?.id {
                                        VStack(spacing: 10) { Text(b.title).font(MadarTypography.caption()); Text("على الطاولة").font(MadarTypography.fine()) }.padding(12).frame(width: 110, height: 145).foregroundStyle(theme.secondaryInk).overlay { RoundedRectangle(cornerRadius: 5).stroke(theme.line, style: .init(lineWidth: 1, dash: [4,4])) }
                                    } else {
                                    VStack(spacing: 8) { Text(b.title).font(.custom("thmanyahserifdisplay-Bold", size: 18, relativeTo: .headline)).lineLimit(3); Text(b.author).font(MadarTypography.fine()).lineLimit(1); Spacer(minLength: 0); Rectangle().frame(height: 1).opacity(0.4); if let p = b.progress { Text(service.digits.string(Int(p * 100)) + "٪").font(MadarTypography.fine()) } }
                                        .padding(12).frame(width: 110, height: 145).foregroundStyle(theme.color("onNavy")).background(theme.color("navy"), in: .rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 9, topTrailingRadius: 9)).overlay(alignment: .leading) { Rectangle().fill(theme.line).frame(width: 5) }.shadow(color: theme.ink.opacity(0.14), radius: 5, x: 0, y: 5)
                                    }
                                }
                            }.buttonStyle(.plain).accessibilityIdentifier("mihbara-book-" + b.id.uuidString)
                        }
                    }.padding(.bottom, 8)
                }.scrollIndicators(.hidden)
            }
            Rectangle().fill(theme.color("wood").gradient).frame(height: 9).shadow(color: theme.ink.opacity(0.14), radius: 5, y: 5)
            HStack { Button("كل كتبي ‹") { sheet = .library }.accessibilityIdentifier("mihbara-library"); Spacer(); Text(service.digits.string(r.books.count) + " على رفوفك").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            MihbaraOldBooksCabinet(books: r.books.filter { $0.shelf == "old" }, theme: theme) { sheet = .book($0) }
        }
    }
    private func desk(_ r: MihbaraHomeReading) -> some View {
        let hadith = r.todayHadiths.first
        let open = (r.opensAfterFajr || manuallyOpen || app.string("mihbara.rahlOpens") == "untilDone") && hadith != nil
        return VStack(alignment: .leading, spacing: 22) {
            HStack {
                deskLabel("على الطاولة", title: true)
                Spacer()
                Button { sheet = .notebook } label: {
                    Text("دفتر").font(.custom("ArefRuqaa-Regular", size: 18, relativeTo: .headline))
                        .foregroundStyle(theme.ink).frame(width: 58, height: 70)
                        .background(theme.color("notebookYellow"), in: .rect(topLeadingRadius: 2, bottomLeadingRadius: 10, bottomTrailingRadius: 2, topTrailingRadius: 2))
                        .overlay(alignment: .top) { Rectangle().fill(theme.color("goldUnderstandText").opacity(0.7)).frame(height: 3).padding(.horizontal, 5) }
                        .shadow(color: theme.ink.opacity(0.18), radius: 5, y: 4).rotationEffect(.degrees(-3))
                }.buttonStyle(.plain).accessibilityLabel("الدفتر الخاص").accessibilityHint("يتطلب فتحه مصادقة الجهاز").accessibilityIdentifier("mihbara-notebook")
            }
            if open, let h = hadith {
                HStack { deskLabel("على الرَّحل، ورد اليوم أولًا"); Spacer(); Button("اطوه ⌃") { manuallyOpen = false; folded = true }.font(MadarTypography.caption()).padding(9).background(theme.color("desk"), in: .capsule).foregroundStyle(theme.color("onDesk")) }
                if !folded {
                    VStack(spacing: 0) {
                        MihbaraOpenBook(
                            theme: theme, sunnah: true,
                            rightHeader: r.collection.title, rightTitle: h.title, rightText: excerpt(hadithMatn(h.text)), rightFooter: service.digits.string(h.number),
                            leftHeader: "ورد اليوم", leftTitle: "حديث واحد",
                            leftText: "بقي " + service.digits.string(max(0, r.collection.hadiths.count - r.readCount)) + " حديثًا",
                            leftFooter: service.digits.string(r.readCount) + " من " + service.digits.string(r.collection.hadiths.count),
                            action: "افهمه"
                        ) { sheet = .hadith(h.number) }
                        ZStack { RoundedRectangle(cornerRadius: 7).fill(theme.color("desk")).frame(width: 225, height: 13).rotationEffect(.degrees(17)); RoundedRectangle(cornerRadius: 7).fill(theme.color("desk")).frame(width: 225, height: 13).rotationEffect(.degrees(-17)); Circle().fill(theme.color("goldUnderstand")).frame(width: 11) }.frame(height: 58).accessibilityHidden(true)
                    }.transition(.opacity.combined(with: .scale(scale: 0.97)))
                } else { Button("افتح ورد اليوم") { folded = false }.buttonStyle(.borderedProminent).tint(theme.color("sunnahLeather")) }
            } else {
                Button { manuallyOpen = true; folded = false; if let h = hadith { sheet = .hadith(h.number) } } label: {
                    HStack { Image(systemName: r.completedToday > 0 ? "checkmark.seal" : "book.closed"); VStack(alignment: .leading, spacing: 4) { Text(r.completedToday > 0 ? "أتممت ورد اليوم" : r.readCount == 42 ? "أتممت الأربعين النووية" : "وردك بعد الفجر").font(MadarTypography.cardTitle()); if r.completedToday > 0 { Text("الحديث القادم في يومك الجديد").font(MadarTypography.caption()) } }; Spacer() }.padding(16).background(theme.color("sunnahLeather"), in: .rect(cornerRadius: 12)).foregroundStyle(theme.onAccent)
                }.buttonStyle(.plain).disabled(hadith == nil).accessibilityIdentifier("mihbara-wird-closed")
            }
            HStack { deskLabel("كتاب القراءة"); Spacer(); deskLabel("موضعك محفوظ") }
            if let b = tableBook {
                let currentPage = b.page.flatMap { $0 > 0 ? $0 : nil }
                let nextPage: Int? = currentPage.flatMap { page -> Int? in
                    guard b.pages.map({ page < $0 }) ?? true else { return nil }
                    return page + 1
                }
                MihbaraOpenBook(
                    theme: theme, sunnah: false,
                    rightHeader: b.author, rightTitle: b.title, rightText: b.pages.map { service.digits.string($0) + " صفحة" } ?? "كتاب ورقي",
                    rightFooter: currentPage.map(service.digits.string) ?? "",
                    leftHeader: "موضعك", leftTitle: "وصلت إلى", leftText: currentPage.map { "صفحة " + service.digits.string($0) } ?? "بداية الكتاب",
                    leftFooter: nextPage.map(service.digits.string) ?? "", action: "أكمل"
                ) { sheet = .book(b.id) }
            } else {
                Button { sheet = .add } label: { VStack(spacing: 12) { Image(systemName: "book.pages").font(.largeTitle); Text("مكان كتابك").font(MadarTypography.cardTitle()); Text("أضف كتابًا ورقيًا وابدأ من موضعك").font(MadarTypography.caption()) }.frame(maxWidth: .infinity, minHeight: 210).background(theme.surface, in: .rect(cornerRadius: 5)).overlay { RoundedRectangle(cornerRadius: 5).stroke(theme.line, style: .init(lineWidth: 1, dash: [4,4])) } }.buttonStyle(.plain).foregroundStyle(theme.ink)
            }
        }.padding(18).padding(.vertical, 8).background(LinearGradient(colors: [theme.color("wood").opacity(0.78), theme.color("wood")], startPoint: .top, endPoint: .bottom), in: .rect(topLeadingRadius: 26, bottomLeadingRadius: 12, bottomTrailingRadius: 12, topTrailingRadius: 26)).animation(reduceMotion ? nil : .smooth(duration: 0.35), value: open && !folded)
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
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                HStack { Text("مكتبتي").font(MadarTypography.title()); Spacer(); Button("تمّ") { sheet = nil } }
                ZStack {
                    UnevenRoundedRectangle(topLeadingRadius: 70, bottomLeadingRadius: 3, bottomTrailingRadius: 3, topTrailingRadius: 70).fill(theme.color("navy").gradient)
                    Circle().fill(theme.color("goldUnderstand")).frame(width: 40, height: 40).offset(x: -55, y: -5)
                    Rectangle().fill(theme.surface).frame(width: 5)
                    Rectangle().fill(theme.surface).frame(height: 4)
                }.frame(height: 125).padding(.horizontal, 65).accessibilityHidden(true)
                TextField("ابحث في كتبك…", text: $libraryQuery).font(MadarTypography.body()).padding(15).background(theme.surface, in: .capsule).accessibilityIdentifier("mihbara-library-search")
                Picker("رفّ الكتب", selection: $libraryShelf) { Text("كل الكتب").tag("all"); Text("أقرؤها الآن").tag("reading"); Text("أبي أقرأها").tag("want"); Text("أنهيتها").tag("finished"); Text("قديمًا").tag("old") }.pickerStyle(.menu)
                Text("البحث يُبرز المطابق، وكل كتبك تبقى في مكانها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                ForEach(r.books) { b in
                    let queryMatches = libraryQuery.isEmpty || (b.title + " " + b.author).folding(options: [.diacriticInsensitive,.caseInsensitive], locale: Locale(identifier: "ar")).contains(libraryQuery.folding(options: [.diacriticInsensitive,.caseInsensitive], locale: Locale(identifier: "ar")))
                    Button { sheet = .book(b.id) } label: {
                        HStack { Image(systemName: "book.closed"); VStack(alignment: .leading) { Text(b.title).font(MadarTypography.cardTitle()); Text(b.author).font(MadarTypography.caption()) }; Spacer(); Text(b.shelf == "reading" ? "أقرؤه" : b.shelf == "want" ? "أبي أقرأه" : "أنهيته").font(MadarTypography.fine()) }.padding(16).background(theme.surface, in: .rect(cornerRadius: 14))
                    }.buttonStyle(.plain).opacity(queryMatches && (libraryShelf == "all" || libraryShelf == b.shelf) ? 1 : 0.3)
                }
            }.padding(20)
        }.background(theme.background).foregroundStyle(theme.ink)
    }

}
private enum MihbaraSheet: Identifiable { case add, library, book(UUID), hadith(Int), notebook; var id: String { String(describing: self) } }

private struct MihbaraNotebookView: View {
    let app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomTheme) private var theme
    @State private var unlocked = false
    @State private var authenticating = false
    @State private var failed = false
    @State private var authGeneration = 0

    var body: some View {
        Group {
            if unlocked {
                MihbaraNotebookContent(app: app) { lock() }
            } else {
                VStack(spacing: 18) {
                    Image(systemName: "lock.doc").font(.system(size: 34)).accessibilityHidden(true)
                    Text("الدفتر الخاص").font(MadarTypography.title())
                    Text("ملاحظاتك لا تظهر قبل مصادقة الجهاز.").font(MadarTypography.body()).multilineTextAlignment(.center).foregroundStyle(theme.secondaryInk)
                    if failed { Text("لم يُفتح الدفتر. جرّب مرة أخرى.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    Button(authenticating ? "يفتح الدفتر…" : "افتح الدفتر") { Task { await authenticate() } }
                        .buttonStyle(MadarPrimaryButton()).disabled(authenticating).accessibilityIdentifier("mihbara-notebook-unlock")
                }.padding(24).frame(maxWidth: .infinity, maxHeight: .infinity).background(theme.background)
            }
        }
        .foregroundStyle(theme.ink).toolbar {
            ToolbarItem(placement: .principal) { Text("دفتر المحبرة").font(MadarTypography.section()) }
            ToolbarItem(placement: .topBarTrailing) { Button("تمّ") { lock(); dismiss() }.accessibilityIdentifier("mihbara-notebook-close") }
        }
        .onChange(of: scenePhase) { _, phase in if phase != .active { lock() } }
        .onDisappear { lock() }
    }

    @MainActor private func authenticate() async {
        guard !authenticating else { return }
        authenticating = true; failed = false
        let generation = authGeneration, context = LAContext()
        context.localizedCancelTitle = "إلغاء"; context.localizedFallbackTitle = "رمز الجهاز"
        defer { context.invalidate(); authenticating = false }
        do {
            guard try await context.evaluatePolicy(.deviceOwnerAuthentication, localizedReason: "افتح ملاحظات المحبرة الخاصة") else { throw PrivacyAuthorizationError.refused }
            guard generation == authGeneration, scenePhase == .active else { return }
            unlocked = true
        } catch {
            if generation == authGeneration, scenePhase == .active { failed = true }
        }
    }

    private func lock() { authGeneration += 1; unlocked = false; failed = false }
}

private struct MihbaraNotebookContent: View {
    struct Note: Identifiable { let id: UUID; let text: String; let updatedAt: Date }
    struct Editor: Identifiable { let id: UUID; let text: String }
    let app: AppSession
    let lock: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var notes: [Note] = []
    @State private var editor: Editor?
    @State private var failure: String?
    @State private var idleTask: Task<Void, Never>?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("ملاحظاتك الخاصة").font(MadarTypography.title()); Spacer(); Button { activity(); editor = .init(id: UUID(), text: "") } label: { Label("ملاحظة جديدة", systemImage: "plus") }.accessibilityIdentifier("mihbara-note-add") }
                Text("تبقى هنا في دفتر المحبرة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                if notes.isEmpty {
                    Text("ابدأ بملاحظة صغيرة؛ ستجدها هنا حين تعود.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity, minHeight: 110, alignment: .leading)
                } else {
                    ForEach(notes) { note in
                        Button { activity(); editor = .init(id: note.id, text: note.text) } label: {
                            VStack(alignment: .leading, spacing: 10) { Text(note.text).font(MadarTypography.body()).lineLimit(5).multilineTextAlignment(.leading); Text("ملاحظة خاصة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                                .frame(maxWidth: .infinity, alignment: .leading).padding(16).background(theme.surface, in: .rect(cornerRadius: 14))
                        }.buttonStyle(.plain).accessibilityIdentifier("mihbara-note-" + note.id.uuidString)
                    }
                }
            }.padding(18)
        }
        .background(theme.background)
        .onScrollPhaseChange { _, phase in if phase == .interacting { activity() } }
        .sheet(item: $editor) { current in
            MihbaraNotebookEditor(note: current, save: save, delete: delete, activity: activity)
                .environment(\.roomTheme, theme).presentationDragIndicator(.visible)
        }
        .safeAreaInset(edge: .bottom) { if app.undoToken != nil { UndoToast(message: app.undoMessage, undo: { app.undo(); load() }).accessibilityIdentifier("mihbara-undo") } }
        .task { load(); activity() }
        .onChange(of: app.undoToken?.id) { load() }
        .onDisappear { idleTask?.cancel(); notes.removeAll(); editor = nil; lock() }
    }

    private func load() {
        do {
            let rows = try ModelContext(app.container).fetch(FetchDescriptor<NotebookNote>())
            notes = rows.filter { $0.isPrivate && $0.link == "general" && $0.targetID == nil && $0.deletedAt == nil && $0.mergedInto == nil }
                .map { Note(id: $0.id, text: $0.text, updatedAt: $0.updatedAt) }.sorted { $0.updatedAt > $1.updatedAt }
            failure = nil
        } catch { notes.removeAll(); failure = "تعذّر فتح الملاحظات المحفوظة." }
    }

    private func activity() {
        idleTask?.cancel()
        idleTask = Task { try? await Task.sleep(for: .seconds(300)); guard !Task.isCancelled else { return }; lock() }
    }

    private func save(_ note: Editor, text: String) {
        activity()
        Task {
            do { try await app.executeBookCommand("notebook.savePrivate", payload: ["id": .string(note.id.uuidString), "text": .string(text)]); load() }
            catch { failure = "لم تُحفظ الملاحظة. أعد المحاولة." }
        }
    }

    private func delete(_ note: Editor) {
        activity()
        Task {
            do { try await app.executeBookCommand("notebook.deletePrivate", payload: ["id": .string(note.id.uuidString)]); load() }
            catch { failure = "لم تُحذف الملاحظة. أعد المحاولة." }
        }
    }
}

private struct MihbaraNotebookEditor: View {
    let note: MihbaraNotebookContent.Editor
    let save: (MihbaraNotebookContent.Editor, String) -> Void
    let delete: (MihbaraNotebookContent.Editor) -> Void
    let activity: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var text: String
    init(note: MihbaraNotebookContent.Editor, save: @escaping (MihbaraNotebookContent.Editor, String) -> Void, delete: @escaping (MihbaraNotebookContent.Editor) -> Void, activity: @escaping () -> Void) {
        self.note = note; self.save = save; self.delete = delete; self.activity = activity; _text = State(initialValue: note.text)
    }
    var body: some View {
        NavigationStack {
            TextEditor(text: $text).font(MadarTypography.body()).scrollContentBackground(.hidden).padding(12).background(theme.background)
                .accessibilityIdentifier("mihbara-note-text")
                .onChange(of: text) { activity() }
                .toolbar {
                    ToolbarItem(placement: .principal) { Text("ملاحظة خاصة").font(MadarTypography.section()) }
                    ToolbarItem(placement: .topBarLeading) { if !note.text.isEmpty { Button("حذف", role: .destructive) { delete(note); dismiss() }.accessibilityIdentifier("mihbara-note-delete") } }
                    ToolbarItem(placement: .topBarTrailing) { Button("حفظ") { save(note, text); dismiss() }.disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000).accessibilityIdentifier("mihbara-note-save") }
                }
        }.environment(\.roomTheme, theme)
    }
}

private struct MihbaraOldBooksCabinet: View {
    let books: [MihbaraBook]
    let theme: RoomTheme
    let openBook: (UUID) -> Void

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
                Text("الكتب التي تنهيها تحفظ مكانها هنا.")
                    .font(MadarTypography.caption())
                    .foregroundStyle(theme.color("onDesk"))
                    .frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            } else {
                ScrollView(.horizontal) {
                    HStack(alignment: .bottom, spacing: 10) {
                        ForEach(books) { book in
                            Button { openBook(book.id) } label: {
                                VStack(alignment: .leading, spacing: 8) {
                                    Text(book.title).font(MadarTypography.section()).lineLimit(3).fixedSize(horizontal: false, vertical: true)
                                    Spacer(minLength: 0)
                                    Text(book.author).font(MadarTypography.fine()).lineLimit(1)
                                }
                                .padding(12).frame(width: 118, height: 116, alignment: .leading)
                                .foregroundStyle(theme.color("onNavy"))
                                .background(theme.color("navy").gradient, in: .rect(topLeadingRadius: 3, bottomLeadingRadius: 3, bottomTrailingRadius: 8, topTrailingRadius: 8))
                                .overlay(alignment: .leading) { Rectangle().fill(theme.color("wood")).frame(width: 5) }
                                .shadow(color: theme.ink.opacity(0.18), radius: 4, x: 0, y: 4)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("افتح كتابًا قديمًا: " + book.title)
                            .accessibilityHint("خيارات العودة إلى القراءة أو إلى رف أبي أقرأها")
                            .accessibilityIdentifier("mihbara-old-book-" + book.id.uuidString)
                        }
                    }.padding(.vertical, 4)
                }.scrollIndicators(.hidden)
                Rectangle().fill(theme.color("wood").gradient).frame(height: 8).shadow(color: theme.ink.opacity(0.16), radius: 4, y: 3)
            }
        }
        .padding(14)
        .background(theme.color("desk"), in: .rect(cornerRadius: 16))
        .foregroundStyle(theme.color("onDesk"))
    }
}

struct MihbaraOpenBook: View {
    var theme: RoomTheme; var sunnah: Bool; var rightHeader: String; var rightTitle: String; var rightText: String; var rightFooter: String; var leftHeader: String; var leftTitle: String; var leftText: String; var leftFooter: String; var action: String; var open: () -> Void
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
                HStack { Spacer(); Button(action, action: open).font(MadarTypography.section()).frame(width: 50, height: 56).foregroundStyle(sunnah ? theme.color("goldUnderstandText") : theme.background).background(sunnah ? theme.color("notebookYellow") : theme.color("ribbonRead"), in: .rect(bottomLeadingRadius: 12, bottomTrailingRadius: 2)).offset(y: -6).accessibilityIdentifier(sunnah ? "mihbara-wird-open" : "mihbara-book-continue") }.padding(.horizontal, 12).frame(height: 24)
            }
        }
    }
    private func page(header: String, title: String, text: String, footer: String) -> some View {
        VStack(spacing: sunnah ? 8 : 12) { Text(header).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2); Spacer(minLength: 0); Text(title).font(.custom(sunnah ? "Amiri-Regular" : "Amiri-Bold", size: sunnah ? 16 : 23, relativeTo: .title2)).multilineTextAlignment(.center); Text(text).font(.custom("Amiri-Regular", size: sunnah ? 18 : 21, relativeTo: .body)).multilineTextAlignment(.center).lineLimit(sunnah ? 5 : 4); Spacer(minLength: 0); Text(footer).font(.custom("Amiri-Regular", size: 14, relativeTo: .caption)) }.padding(.horizontal, 12).padding(.vertical, sunnah ? 10 : 16).frame(maxWidth: .infinity).frame(minHeight: sunnah ? 180 : 220).background(theme.surface).overlay(alignment: .leading) { LinearGradient(colors: [theme.ink.opacity(0.08), .clear], startPoint: .leading, endPoint: .trailing).frame(width: 15).allowsHitTesting(false) }
    }
}
