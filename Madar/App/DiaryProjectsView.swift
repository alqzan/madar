import SwiftUI
import MadarCore
import MadarDesign

/// §7.3 N04 projects: open projects with their linked lines; finished ones go to «الفصول».
struct DiaryProjectsPanel: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @State private var projects: [DiaryProjectCard] = []
    @State private var creating = false
    @State private var detail: DiaryProjectCard?
    @State private var failure: String?
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) { Text("المشاريع").font(DiaryType.heading); Text("ما تبنيه على مهل، وسطورك عنه").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
            Button { creating = true } label: { Label("مشروع جديد", systemImage: "plus").font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 46).overlay { Capsule().stroke(theme.line) } }
                .buttonStyle(.plain).accessibilityIdentifier("diary-project-new")
            if let failure { Text(failure).font(MadarTypography.body()) }
            let open = projects.filter { $0.finishedAt == nil }, chapters = projects.filter { $0.finishedAt != nil }
            if projects.isEmpty { Text("لا مشاريع بعد. اضغط «مشروع جديد» واكتب كلمة تدلّ عليه، ويقترح مدار ربط سطورك به.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 16) }
            ForEach(open) { project in row(project) }
            if !chapters.isEmpty {
                Text("الفصول").font(DiaryType.heading).padding(.top, 8)
                ForEach(chapters) { project in row(project) }
            }
        }
        .task(id: app.prayerRevision) { do { projects = try service.projects(); failure = nil } catch { failure = madarUserMessage(error) } }
        .sheet(isPresented: $creating) { DiaryProjectEditor(app: app).environment(\.roomTheme, theme).presentationDetents([.medium, .large]) }
        .sheet(item: $detail) { project in DiaryProjectDetail(app: app, project: project).environment(\.roomTheme, theme) }
    }
    private func row(_ project: DiaryProjectCard) -> some View {
        Button { detail = project } label: {
            VStack(alignment: .leading, spacing: 6) {
                HStack { Text(project.name).font(DiaryType.heading); Spacer(); Text(project.lines.isEmpty ? "بلا سطور بعد" : arabicCount(project.lines.count, ["سطر واحد", "سطران", "أسطر", "سطرًا"], service.digits)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                if !project.intention.isEmpty { Text(project.intention).font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).lineLimit(2) }
                if let last = project.lines.last { Text(last.text).font(DiaryType.label).lineLimit(1) }
            }.padding(14).background(theme.surface, in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line) }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("diary-project-row")
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
    @State private var identity = UUID()
    @State private var saving = false
    @State private var confirmDiscard = false
    private var hasUnsavedInput: Bool { !name.isEmpty || !intention.isEmpty || !keyword.isEmpty }
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 14) {
                field("اسم المشروع", $name, id: "diary-project-name")
                field("نيّتك منه", $intention, id: "diary-project-intention")
                field("كلمة تدلّ عليه في كتابتك", $keyword, id: "diary-project-keyword")
                Text("الكلمة اقتراح فقط: يسألك مدار «يتعلّق بـ…؟» ولا يربط وحده.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                if let failure { Text(failure).font(MadarTypography.body()) }
                Spacer()
            }.padding(18).background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("مشروع جديد").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { if hasUnsavedInput { confirmDiscard = true } else { dismiss() } }.disabled(saving) }
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
                .interactiveDismissDisabled(hasUnsavedInput)
                .confirmationDialog("تجاهل كتابة المشروع؟", isPresented: $confirmDiscard, titleVisibility: .visible) {
                    Button("تجاهل المسودة", role: .destructive) { dismiss() }.accessibilityIdentifier("diary-project-discard")
                    Button("أكمل الكتابة") { }
                } message: {
                    Text("لم تحفظ المشروع بعد.")
                }
        }
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
    @State private var finishing = false
    @State private var confirmDelete = false
    @State private var failure: String?
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
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
                            TextField("كلمة تختم بها المشروع", text: $reflection, axis: .vertical).font(DiaryType.writing).padding(12).background(theme.surface, in: .rect(cornerRadius: 12)).accessibilityIdentifier("diary-project-reflection")
                            Button { Task { do { try await service.finishProject(project.id, reflection: reflection); dismiss() } catch { failure = madarUserMessage(error) } } } label: {
                                Text("أنهِ المشروع").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
                            }.buttonStyle(.plain).accessibilityIdentifier("diary-project-finish-confirm")
                        } else {
                            Button { finishing = true } label: { Text("أنهِ المشروع").font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 46).overlay { Capsule().stroke(theme.line) } }.buttonStyle(.plain).accessibilityIdentifier("diary-project-finish")
                        }
                    }
                    Button(role: .destructive) { confirmDelete = true } label: { Text("احذف المشروع").font(DiaryType.label).frame(minHeight: 44) }.accessibilityIdentifier("diary-project-delete")
                    if let failure { Text(failure).font(MadarTypography.body()) }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle(project.name).navigationBarTitleDisplayMode(.inline)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تمّ") { dismiss() } } }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .confirmationDialog("تبقى السطور بنصّها، ويختفي ربطها. يمكنك التراجع.", isPresented: $confirmDelete, titleVisibility: .visible) {
                    Button("احذف المشروع", role: .destructive) { Task { do { try await service.deleteProject(project.id); dismiss() } catch { failure = madarUserMessage(error) } } }
                }
        }
    }
}
