import SwiftUI
import MadarCore
import MadarDesign

struct DiaryLaunchView: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @State private var writingDirectly = false
    @State private var welcomed: Bool?
    @State private var failure: String?
    @State private var welcomeLookupAttempt = 0
    @State private var welcomeChecking = false
    @State private var injectedWelcomeFailure = false
    var body: some View {
        Group {
            if welcomed == true || writingDirectly { DiaryHomeView(app: app) }
            else if welcomed == false { DiaryWelcomeView(app: app) { welcomed = true } }
            else if welcomeChecking || failure == nil { ProgressView("تُفتح صفحتك…") }
            else if let failure {
                VStack(spacing: 14) {
                    Text(failure).font(DiaryType.writing).multilineTextAlignment(.center).accessibilityIdentifier("diary-welcome-error")
                    Button("أعد المحاولة") { welcomeLookupAttempt += 1 }
                        .disabled(welcomeChecking).accessibilityIdentifier("diary-welcome-retry")
                }.padding(28).frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
            }
        }.onChange(of: app.diaryRoute, initial: true) { _, route in
            if route?.path.first == "write" { writingDirectly = true }
        }.task(id: welcomeLookupAttempt) {
            welcomeChecking = true
            failure = nil
            defer { welcomeChecking = false }
            do {
                #if DEBUG
                if !injectedWelcomeFailure && ProcessInfo.processInfo.environment["MADAR_UI_DIARY_WELCOME_READ_FAILURE_ONCE"] == "1" {
                    injectedWelcomeFailure = true
                    throw CocoaError(.fileReadUnknown)
                }
                #endif
                welcomed = try AppDiaryService(app: app).hasWelcomed()
            } catch { failure = "تعذّر فتح صفحة اليوميات. أعد المحاولة." }
        }
        // The diary opens from the glass accessory, not a tab: hiding the bar during the welcome left no way to another room.
    }
}
struct DiaryWelcomeView: View {
    @Bindable var app: AppSession
    let finished: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var step = 0
    @State private var saving = false
    @State private var failure: String?
    private let titles = ["دفتر يكتب معك", "ما تعيشه، بأسلوب المذكرات", "للذكرى أكثر من تقويم", "سطر واحد يكفي للبداية"]
    var body: some View {
        VStack(spacing: 20) {
            HStack(spacing: 6) { ForEach(0..<4) { index in Capsule().fill(index == step ? theme.accent : theme.line).frame(width: index == step ? 20 : 6, height: 6) } }.padding(.top, 22).accessibilityLabel("الخطوة " + app.digits(step+1) + " من أربع")
            ScrollView {
                VStack(spacing: 24) {
                    if step == 0 {
                        ZStack {
                            RoundedRectangle(cornerRadius: 5).fill(MadarToken.colors["rooms.notes.lockCover.leather"] ?? theme.accent)
                            Rectangle().fill(theme.ink.opacity(0.16)).frame(width: 10).frame(maxWidth: .infinity, alignment: .leading)
                            VStack(spacing: 16) { Text("مذكراتي").font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)); Rectangle().fill(theme.color("onAccent")).frame(width: 60, height: 1); Text("صفحاتك، كما عشتها").font(DiaryType.label) }.foregroundStyle(MadarToken.colors["rooms.notes.lockCover.text"] ?? theme.onAccent)
                        }.frame(width: 176, height: 232).shadow(color: theme.ink.opacity(0.18), radius: 14, y: 15).padding(.top, 12)
                    } else {
                        Image(systemName: step == 1 ? "text.alignright" : step == 2 ? "calendar" : "pencil.line").font(.system(size: 66, weight: .ultraLight)).foregroundStyle(theme.accent).padding(.vertical, 30).accessibilityHidden(true)
                    }
                    Text(titles[step]).font(DiaryType.title).multilineTextAlignment(.center).accessibilityIdentifier("diary-welcome-title")
                    if step == 0 {
                        Text("تكتب ما تيسّر، ومدار يكمل من صلواتك وحفظك ومراجعتك. كل سطر بوقته، وكل ذكرى بتاريخها.").font(DiaryType.writing).lineSpacing(8).multilineTextAlignment(.center).foregroundStyle(theme.color("ink3Text"))
                    } else if step == 1 {
                        Text("اختر ما يدخل صفحتك تلقائيًا. يمكنك تغييره لاحقًا، وتبقى كتابتك كما هي.").font(MadarTypography.body()).multilineTextAlignment(.center)
                        ForEach([("salah", "الصلاة"), ("quran", "القرآن"), ("habits", "العادات"), ("mihbara", "المحبرة")], id: \.0) { key, title in
                            Toggle(title, isOn: Binding(get: { app.values["notes.autoLines"]?.object?[key] == .bool(true) || (key == "habits" && app.values["notes.autoLines"]?.object?["habits"] == nil) }, set: { value in var map = app.values["notes.autoLines"]?.object ?? [:]; map[key] = .bool(value); app.set(.object(map), key: "notes.autoLines") })).font(MadarTypography.section()).tint(theme.color("ghad")).padding(14).background(theme.surface, in: .rect(cornerRadius: 18))
                        }
                    } else if step == 2 {
                        Text("المطابقة تغيّر الذكريات التي تراها، وتحافظ على التاريخ الأصلي لكل صفحة.").font(MadarTypography.body()).multilineTextAlignment(.center)
                        if let definition = app.schema.settings.first(where: { $0.key == "notes.match" }) { SettingControl(definition: definition, session: app) }
                    } else {
                        Text("لا يلزم أن تكتب يومًا كاملًا. افتح صفحة اليوم واكتب ما تريد الاحتفاظ به، أو ارجع إلى أمس بختم «كُتبت لاحقًا».").font(DiaryType.writing).lineSpacing(8).multilineTextAlignment(.center)
                    }
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.accent) }
                }.padding(.horizontal, 28).padding(.bottom, 20)
            }
            HStack(spacing: 10) {
                if step > 0 { Button("السابق") { step -= 1 }.font(MadarTypography.section()).frame(minHeight: 52).padding(.horizontal, 16) }
                // Audit 28 Oct: four steps with no way past them; every choice already has its agreed default.
                else { Button("ابدأ مباشرة") { Task { await finish() } }.font(MadarTypography.section()).frame(minHeight: 52).padding(.horizontal, 16)
                    .disabled(saving || app.settingsWriteInProgress).accessibilityIdentifier("diary-welcome-skip") }
                Button(step == 3 ? "افتح دفتري" : "التالي") {
                    if step < 3 { step += 1 } else { Task { await finish() } }
                }.font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
                    .disabled(saving || app.settingsWriteInProgress).accessibilityIdentifier("diary-welcome-next")
            }.padding(.horizontal, 24).padding(.bottom, 18)
        }.foregroundStyle(theme.ink).background(theme.background)
    }
    private func finish() async {
        saving = true
        do { try await app.executeDiaryCommand("diary.completeWelcome", payload: [:]); finished() }
        catch { failure = madarUserMessage(error); saving = false }
    }
}
