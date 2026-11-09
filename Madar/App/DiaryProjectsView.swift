import SwiftUI
import MadarCore
import MadarDesign

/// §7.3 N04 projects: open projects with their linked lines; finished ones go to «الفصول».
struct DiaryProjectsPanel: View {
    @Bindable var app: AppSession
    var initialProjectID: UUID? = nil
    var initialProjectRequestID: UUID? = nil
    @Environment(\.roomTheme) private var theme
    @State private var projects: [DiaryProjectCard] = []
    @State private var creating = false
    @State private var detail: DiaryProjectCard?
    @State private var failure: String?
    @State private var routeMessage: String?
    @State private var handledRouteID: UUID?
    @State private var loadAttempt = 0
    #if DEBUG
    @State private var injectedReadFailure = false
    #endif
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) { Text("المشاريع").font(DiaryType.heading); Text("ما تبنيه على مهل، وسطورك عنه").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
            Button { creating = true } label: { Label("مشروع جديد", systemImage: "plus").font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 46).glassEffect(.regular.interactive(), in: .capsule) }
                .buttonStyle(.madarPlain).accessibilityIdentifier("diary-project-new")
            if let failure {
                Text(failure).font(MadarTypography.body()).accessibilityIdentifier("diary-project-read-error")
                Button { loadAttempt += 1 } label: { Text("أعد المحاولة")
                    .frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-project-retry")
            }
            if let routeMessage { Text(routeMessage).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-project-route-status") }
            let open = projects.filter { $0.finishedAt == nil }, chapters = projects.filter { $0.finishedAt != nil }
            if failure == nil && projects.isEmpty { Text("لا مشاريع بعد. اضغط «مشروع جديد» واكتب كلمة تدلّ عليه، ويقترح مدار ربط سطورك به.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 16) }
            ForEach(open) { project in row(project) }
            if !chapters.isEmpty {
                Text("الفصول").font(DiaryType.heading).padding(.top, 8)
                ForEach(chapters) { project in row(project) }
            }
        }
        .task(id: "\(app.prayerRevision)-\(loadAttempt)") { loadProjects() }
        .onChange(of: initialProjectID) { _, id in if let id, !projects.isEmpty { openRoutedProject(id) } }
        .onChange(of: initialProjectRequestID) { _, requestID in
            guard requestID != nil, let initialProjectID else { return }
            handledRouteID = nil
            if !projects.isEmpty { openRoutedProject(initialProjectID) }
        }
        .sheet(isPresented: $creating) { DiaryProjectEditor(app: app).environment(\.roomTheme, theme).presentationDetents([.medium, .large]) }
        .sheet(item: $detail) { project in DiaryProjectDetail(app: app, project: project).environment(\.roomTheme, theme) }
    }
    private func loadProjects() {
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if !injectedReadFailure, environment["MADAR_UI_DIARY_PROJECTS_READ_FAILURE_ONCE"] == "1",
               environment["MADAR_UI_DIARY_FIXTURE"] == "letters", environment["MADAR_UI_STORE_ID"] != nil {
                injectedReadFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            projects = try service.projects()
            failure = nil
            if let initialProjectID { openRoutedProject(initialProjectID) }
        } catch { projects = []; failure = "تعذّر فتح المشاريع المحفوظة. أعد المحاولة." }
    }
    private func openRoutedProject(_ id: UUID) {
        guard handledRouteID != id else { return }
        handledRouteID = id
        routeMessage = nil
        guard let project = projects.first(where: { $0.id == id }) else {
            routeMessage = "هذا المشروع لم يعد موجودًا في مذكراتك."
            return
        }
        detail = project
    }
    private func row(_ project: DiaryProjectCard) -> some View {
        Button { detail = project } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(project.name).font(DiaryType.heading); Spacer(); Text(project.lines.isEmpty ? "بلا سطور بعد" : arabicCount(project.lines.count, ["سطر واحد", "سطران", "أسطر", "سطرًا"], service.digits)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                if !project.intention.isEmpty { Text(project.intention).font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).lineLimit(2) }
                if let last = project.lines.last { Text(last.text).font(DiaryType.label).lineLimit(1) }
            }.padding(14).background(theme.surface, in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line) }.contentShape(.rect)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-project-row")
    }
}

struct DiaryProjectEditor: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var intention = ""
    @State private var keyword = ""
    @State private var failure: String?
    @State private var saving = false
    @State private var identity = UUID()
    @State private var confirmDiscard = false
    private var hasUnsavedInput: Bool { !name.isEmpty || !intention.isEmpty || !keyword.isEmpty }
    private var blocksRootRoute: Bool { hasUnsavedInput || saving }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                    Button("اختبر الجذر") { app.open(URL(string: "madar://notes")!) }
                        .accessibilityIdentifier("diary-project-editor-root-route")
                }
#endif
                field("اسم المشروع", $name, id: "diary-project-name")
                field("نيّتك منه", $intention, id: "diary-project-intention")
                field("كلمة تدلّ عليه في كتابتك", $keyword, id: "diary-project-keyword")
                Text("الكلمة اقتراح فقط: يسألك مدار «يتعلّق بـ…؟» ولا يربط وحده.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                if let failure { Text(failure).font(MadarTypography.body()) }
                Spacer()
            }.padding(18).background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("مشروع جديد").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("إلغاء") { if hasUnsavedInput { confirmDiscard = true } else { dismiss() } }.madarWaitsForSave()
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("احفظ") {
                            guard !saving else { return }; saving = true
                            Task { defer { saving = false }
                                do { try await AppDiaryService(app: app).saveProject(identity, name: name, intention: intention, keyword: keyword.isEmpty ? name : keyword); dismiss() }
                                catch { failure = madarUserMessage(error) }
                            }
                        }
                            .disabled(saving || name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("diary-project-save")
                    }
                }.toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .madarSheetLock(saving: saving, draft: hasUnsavedInput)
                .confirmationDialog("تجاهل كتابة المشروع؟", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("تجاهل المسودة", role: .destructive) { dismiss() }.accessibilityIdentifier("diary-project-discard")
                    Button("أكمل الكتابة") { }
                } message: {
                    Text("لم تحفظ المشروع بعد.")
                }
        }.diaryRootDraftBlocking(app, isBlocking: blocksRootRoute)
    }
    private func field(_ title: String, _ value: Binding<String>, id: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
            TextField("", text: value).font(DiaryType.writing).padding(.horizontal, 12).frame(minHeight: 46)
                .background(theme.surface, in: .rect(cornerRadius: 12)).overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.line) }.accessibilityIdentifier(id)
        }
    }
}

struct DiaryProjectDetail: View {
    @Bindable var app: AppSession
    let project: DiaryProjectCard
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var reflection = ""
    @FocusState private var reflectionFocused: Bool
    @State private var finishing = false
    @State private var confirmDiscardReflection = false
    @State private var confirmDelete = false
    @State private var failure: String?
    @State private var saving = false
    private var service: AppDiaryService { .init(app: app) }
    private var hasUnsavedReflection: Bool { finishing && !reflection.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    private var blocksRootRoute: Bool { hasUnsavedReflection || saving }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                        Button("اختبر الجذر") { app.open(URL(string: "madar://notes")!) }
                            .accessibilityIdentifier("diary-project-detail-root-route")
                        Button("اختبر رابط مشروع آخر") { app.open(URL(string: "madar://notes/project/44444444-4444-4444-8444-444444444442")!) }
                            .accessibilityIdentifier("diary-project-detail-second-route")
                    }
#endif
                    if !project.intention.isEmpty { Text(project.intention).font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")) }
                    if let reflection = project.reflection { Text("خاتمة: " + reflection).font(DiaryType.writing) }
                    if project.lines.isEmpty { Text("لم تُربط سطور بعد.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")) }
                    ForEach(project.lines) { line in
                        VStack(alignment: .leading, spacing: 4) {
                            MadarDateLabel(service.bothDates(line.day)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                            Text(line.text).font(DiaryType.writing)
                        }.padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                    }
                    if project.finishedAt == nil {
                        if finishing {
                            TextField("كلمة تختم بها المشروع", text: $reflection, axis: .vertical).font(DiaryType.writing).focused($reflectionFocused).padding(12).background(theme.surface, in: .rect(cornerRadius: 12)).disabled(saving).accessibilityIdentifier("diary-project-reflection")
                            Button { guard !saving else { return }; saving = true; Task { defer { saving = false }; do { try await service.finishProject(project.id, reflection: reflection); dismiss() } catch { failure = madarUserMessage(error) } } } label: {
                                Text("أنهِ المشروع").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
                            }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("diary-project-finish-confirm")
                        } else {
                            Button { finishing = true } label: { Text("أنهِ المشروع").font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 46).glassEffect(.regular.interactive(), in: .capsule) }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-project-finish")
                        }
                    }
                    Button(role: .destructive) { guard !saving else { return }; confirmDelete = true } label: { Text("احذف المشروع").font(DiaryType.label).frame(minHeight: 44) }.disabled(saving).accessibilityIdentifier("diary-project-delete")
                    if let failure { Text(failure).font(MadarTypography.body()) }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItemGroup(placement: .topBarLeading) {
                    Button("تمّ") { if hasUnsavedReflection { reflectionFocused = false; confirmDiscardReflection = true } else { dismiss() } }.madarWaitsForSave().accessibilityIdentifier("diary-project-detail-close")
                } }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .madarSheetLock(saving: saving, draft: hasUnsavedReflection)
                .confirmationDialog("تتجاهل خاتمة المشروع؟", isPresented: $confirmDiscardReflection, titleVisibility: .visible) {
                    Button("تجاهل الخاتمة", role: .destructive) { guard !saving else { return }; reflection = ""; finishing = false; dismiss() }.disabled(saving).accessibilityIdentifier("diary-project-reflection-discard")
                    Button("أكمل الكتابة") {}.accessibilityIdentifier("diary-project-reflection-continue")
                } message: { Text("لم تُحفظ الخاتمة. يمكنك إكمالها أو إنهاء المشروع بها.") }
                .confirmationDialog("تبقى السطور بنصّها، ويختفي ربطها. يمكنك التراجع.", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("احذف المشروع", role: .destructive) { guard !saving else { return }; saving = true; Task { defer { saving = false }; do { try await service.deleteProject(project.id); dismiss() } catch { failure = madarUserMessage(error) } } }.disabled(saving).accessibilityIdentifier("diary-project-delete-confirm")
                }
        }
        .diaryRootDraftBlocking(app, isBlocking: blocksRootRoute)
    }
}
