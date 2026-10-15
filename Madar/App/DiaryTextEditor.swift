import SwiftUI
import MadarCore
import MadarDesign

struct DiaryTextEditor: View {
    @Bindable var app: AppSession
    let margin: GregorianDay?
    var initialDay = "today"
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var day = "today"
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if let margin {
                    Text("هامش " + AppDiaryService(app: app).dateTitle(margin, calendar: .gregorian)).font(MadarTypography.caption()).padding(14)
                } else {
                    HStack(spacing: 8) {
                        choice("today", "اليوم"); choice("yesterday", "أمس")
                        Spacer()
                    }.padding(.horizontal, 16).padding(.bottom, 14)
                }
                ZStack(alignment: .topLeading) {
                    Canvas { context, size in
                        var path = Path()
                        for y in stride(from: 12.0, through: size.height, by: 34) { path.move(to: .init(x: 0, y: y)); path.addLine(to: .init(x: size.width, y: y)) }
                        context.stroke(path, with: .color(theme.line), lineWidth: 0.5)
                        var marginLine = Path(); marginLine.move(to: .init(x: size.width - 22, y: 0)); marginLine.addLine(to: .init(x: size.width - 22, y: size.height))
                        context.stroke(marginLine, with: .color(theme.color("margin")), lineWidth: 1)
                    }.accessibilityHidden(true)
                    TextEditor(text: $text).scrollContentBackground(.hidden)
                        .font(.custom("thmanyahseriftext-Regular", size: 19, relativeTo: .body)).lineSpacing(12)
                        .padding(.horizontal, 30).padding(.top, 10).focused($focused).accessibilityIdentifier("diary-editor-text")
                    if text.isEmpty { Text("اكتب ما تيسّر…").font(.custom("thmanyahseriftext-Regular", size: 21, relativeTo: .body)).foregroundStyle(theme.color("ink3Text")).padding(.horizontal, 38).padding(.top, 19).allowsHitTesting(false) }
                }
                HStack {
                    Text(AppDiaryService(app: app).digits.string(text.count) + " / " + AppDiaryService(app: app).digits.string(2000)).font(MadarTypography.fine())
                    Spacer()
                    if day == "yesterday" { Text("كُتبت لاحقًا").font(MadarTypography.caption()).foregroundStyle(theme.color("late")) }
                }.padding(14)
                if let failure { Text(failure).font(MadarTypography.caption()).padding(12).accessibilityIdentifier("diary-editor-error") }
            }
            .foregroundStyle(theme.ink).background(theme.background)
            .navigationTitle(margin == nil ? "صفحة اليوم" : "اكتب في هامشها").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) { Button("إلغاء") { dismiss() }.accessibilityIdentifier("diary-editor-cancel") }
                ToolbarItem(placement: .topBarTrailing) {
                    Button(saving ? "يُحفظ…" : "تمّ") { Task { await save() } }.fontWeight(.bold)
                        .disabled(saving || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || text.count > 2000)
                        .accessibilityIdentifier("diary-editor-save")
                }
            }.tint(theme.accent)
        }.task { day = initialDay; focused = true }.interactiveDismissDisabled(!text.isEmpty)
    }
    private func choice(_ value: String, _ label: String) -> some View {
        Button { day = value } label: { Text(label).font(MadarTypography.caption()).padding(.horizontal, 16).frame(minHeight: 42).foregroundStyle(day == value ? theme.background : theme.ink).background(day == value ? theme.ink : theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line, lineWidth: 1) } }
            .buttonStyle(.plain).accessibilityIdentifier("diary-editor-" + value).accessibilityAddTraits(day == value ? .isSelected : [])
    }
    private func save() async {
        guard !saving else { return }; saving = true
        do {
            var payload: [String: MadarCore.JSONValue] = ["text": .string(text)]
            if let margin { payload["targetDayKey"] = .string(margin.description) }
            else { payload["day"] = .string(day) }
            try await app.executeDiaryCommand(margin == nil ? "diary.appendLine" : "diary.addMargin", payload: payload)
            dismiss()
        } catch { failure = error.localizedDescription; saving = false }
    }
}

struct DiaryDayView: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var page: DiaryDisplayDay?
    @State private var failure: String?
    @State private var writing = false
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(AppDiaryService(app: app).dateTitle(day, calendar: FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri))
                        .font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .title)).accessibilityIdentifier("diary-day-title")
                    if day == (try? AppDiaryService(app: app).currentDay()) { Text("حتى الآن").font(MadarTypography.caption()).foregroundStyle(theme.color("ink3Text")) }
                    if let page {
                        ForEach(page.lines) { line in
                            HStack(alignment: .firstTextBaseline, spacing: 12) {
                                Text(AppDiaryService(app: app).time(line.at)).font(MadarTypography.fine()).foregroundStyle(theme.color("ink3Text")).frame(width: 45)
                                VStack(alignment: .leading, spacing: 6) {
                                    Text(line.text).font(.custom("thmanyahseriftext-Regular", size: 19, relativeTo: .body)).lineSpacing(12)
                                    if line.kind == "late" { Text("كُتبت لاحقًا").font(MadarTypography.fine()) }
                                    if line.kind == "margin" { Text("هامش · " + AppDiaryService(app: app).time(line.at)).font(MadarTypography.fine()) }
                                    if ["salah", "quran"].contains(line.kind) { Text(line.kind == "salah" ? "الصلاة" : "القرآن").font(MadarTypography.fine()) }
                                }.foregroundStyle(line.kind == "margin" ? theme.color("pencil") : line.kind == "late" ? theme.color("late") : line.kind == "normal" ? theme.ink : theme.color("autoInkText"))
                            }.frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 10)
                            Divider().overlay(theme.line)
                        }
                        if let data = page.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFit().padding(8).background(theme.surface).rotationEffect(.degrees(-2)).padding(.horizontal, 36) }
                        if page.lines.isEmpty { Text("صفحة تنتظر سطرك.").font(MadarTypography.body()) }
                    }
                    if let failure { Text(failure) }
                }.padding(20)
            }.background(theme.background).foregroundStyle(theme.ink)
                .toolbar {
                    ToolbarItem(placement: .topBarLeading) { Button("المذكرات") { dismiss() }.accessibilityIdentifier("diary-day-close") }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button(day == (try? AppDiaryService(app: app).currentDay()) ? "اكتب" : "اكتب في هامشها") { writing = true }.accessibilityIdentifier("diary-day-write")
                    }
                }
                .sheet(isPresented: $writing) { DiaryTextEditor(app: app, margin: day == (try? AppDiaryService(app: app).currentDay()) ? nil : day).environment(\.roomTheme, theme) }
        }
        .task(id: app.prayerRevision) {
            do { let service = AppDiaryService(app: app); try await service.prepareClosedDay(day); page = try service.day(day) }
            catch { failure = error.localizedDescription }
        }
    }
}
