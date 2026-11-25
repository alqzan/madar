import SwiftUI
import Observation
import MadarDesign
import MadarData

struct FirstRunView: View {
    @Bindable var session: AppSession
    @State private var choosingCity = false
    @State private var asksForCity = false
    @State private var name = ""
    @StateObject private var locator = CityLocator()
    @FocusState private var editingName: Bool
    @Environment(\.roomTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType

    var body: some View {
        NavigationStack {
            ScrollView {
                layout
                    .padding(24)
                    .padding(.vertical, 18)
                    .frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background.ignoresSafeArea())
            .foregroundStyle(theme.ink)
            .tint(theme.accent)
            .navigationDestination(isPresented: $choosingCity) {
                CityEditor(session: session, onSaved: { session.completeOnboarding(displayName: name) })
            }
        }
        .interactiveDismissDisabled()
        #if DEBUG && os(iOS)
        .onAppear { MadarSmokeReadiness.markVisible("first-run") }
        #endif
    }

    @ViewBuilder private var layout: some View {
        if isPadWide(sizeClass) && !dynamicType.isAccessibilitySize {
            ViewThatFits(in: .horizontal) {
                HStack(alignment: .center, spacing: 44) {
                    introduction.frame(width: 310, alignment: .leading)
                    actions.frame(width: 350)
                }
                .padding(.top, 60)
                compact
            }
        } else {
            compact
        }
    }

    private var compact: some View {
        VStack(alignment: .leading, spacing: 26) {
            introduction
            actions
        }.frame(maxWidth: 490)
    }

    private var introduction: some View {
        VStack(alignment: .leading, spacing: 16) {
            MadarGlyph(asksForCity ? "location" : "MadarOrbit", size: 48)
                .frame(width: 92, height: 92)
                .foregroundStyle(theme.accent)
                .background(theme.surface, in: .circle)
                .overlay { Circle().strokeBorder(theme.line) }
            Text(asksForCity ? cityTitle : "أهلًا بك في مدار")
                .font(MadarTypography.title())
                .accessibilityAddTraits(.isHeader)
            Text(asksForCity
                 ? "اختر مدينتك عشان يضبط مدار بداية يومك والتذكيرات المرتبطة بمواقيت الصلاة."
                 : "هنا تجمع عاداتك، وردك، مذكراتك وقراءاتك، وتتابع مالك على وتيرتك.")
                .font(MadarTypography.body())
                .foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cityTitle: String {
        let name = MadarTour.cleanName(name)
        return name.isEmpty ? "خلّنا نضبط مدينتك" : "خلّنا نضبط مدينتك يا \(MadarTour.isolate(name))"
    }

    @ViewBuilder private var actions: some View {
        if asksForCity { cityActions } else { welcomeActions }
    }

    private var welcomeActions: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 8) {
                Text("وش تحب نناديك؟").font(MadarTypography.section())
                TextField("الاسم اللي تحبّه", text: $name)
                    .font(MadarTypography.body())
                    .textContentType(.nickname)
                    .submitLabel(.continue)
                    .focused($editingName)
                    .onSubmit(next)
                    .accessibilityLabel("الاسم الذي تحب أن نناديك به، اختياري")
                    .accessibilityIdentifier("first-run-name")
                    .padding(13)
                    .background(theme.background, in: .rect(cornerRadius: 13))
                Text("تقدر تتركه فاضي. نستخدمه بس في تحية البهو.")
                    .font(MadarTypography.caption())
                    .foregroundStyle(theme.secondaryInk)
            }
            .padding(16)
            .background(theme.surface, in: .rect(cornerRadius: 22))

            Label("مدار يشتغل بدون حساب. اسمك وبياناتك محفوظة على جهازك.", systemImage: "lock")
                .font(MadarTypography.caption())
                .foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("first-run-privacy")

            Button("لنبدأ", action: next)
                .buttonStyle(MadarPrimaryButton())
                .accessibilityIdentifier("first-run-continue")
        }
    }

    private func next() {
        editingName = false
        asksForCity = true
    }

    private var cityActions: some View {
        VStack(alignment: .leading, spacing: 12) {
            Button("اختر مدينتي بنفسي") {
                locator.cancel()
                choosingCity = true
            }
            .buttonStyle(MadarPrimaryButton())
            .disabled(session.userWriteInProgress)
            .accessibilityIdentifier("first-run-city")

            Button(locator.working ? "أبحث عن مدينتك…" : "استخدم موقعي") { locator.start(save) }
                .buttonStyle(.madarPlain)
                .font(MadarTypography.section())
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .disabled(locator.working || session.userWriteInProgress)
                .accessibilityIdentifier("first-run-locate")

            Text("إذا اخترت استخدام موقعك، يتعرّف النظام على مدينتك عبر Apple مرة واحدة. يحفظ مدار الموقع التقريبي للمدينة.")
                .font(MadarTypography.caption())
                .foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)

            if let message = locator.message {
                Text(message).font(MadarTypography.body()).foregroundStyle(theme.ink)
                if locator.needsSettings {
                    Button("افتح إعدادات الجهاز") { MadarPlatform.openAppSettings() }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("first-run-open-settings")
                }
            }

            Button("رجوع") {
                locator.cancel()
                asksForCity = false
            }
            .frame(minHeight: 44)
            .disabled(session.userWriteInProgress)
            .accessibilityIdentifier("first-run-back")
        }
    }

    private func save(_ found: CityLocator.Found) {
        session.set(.object(["name": .string(found.name), "country": .string(found.country),
                             "lat": .number(found.lat), "lon": .number(found.lon),
                             "tz": .string(found.tz), "currency": .string(found.currency)]), key: "core.homeCity") {
            session.completeOnboarding(displayName: name)
        }
    }
}

struct MadarWelcomeNameView: View {
    let tour: MadarTour
    @State private var name: String
    @Environment(\.dismiss) private var dismiss

    init(tour: MadarTour) {
        self.tour = tour
        _name = State(initialValue: tour.displayName)
    }

    var body: some View {
        SettingsPage(title: "اسم الترحيب") {
            MadarCard {
                VStack(alignment: .leading, spacing: 10) {
                    TextField("الاسم اللي تحبّه", text: $name)
                        .textContentType(.nickname)
                        .submitLabel(.done)
                        .onSubmit(save)
                        .accessibilityIdentifier("welcome-name-setting")
                        .frame(minHeight: 44)
                    Text("الاسم يبقى على جهازك. اترك الحقل فاضي لتحذفه من التحية.")
                        .font(MadarTypography.caption())
                }
            }
            Button("احفظ", action: save)
                .buttonStyle(MadarPrimaryButton())
                .accessibilityIdentifier("welcome-name-save")
        }
    }

    private func save() {
        tour.updateName(name)
        dismiss()
    }
}

@MainActor @Observable
final class MadarTour {
    enum Step: String, CaseIterable {
        case welcome, search, arrange, settingsDoor, navigation
        case habitPeriods, habitAdd, mushaf, quranPlan, diaryWrite, diaryBrowse
        case expense, moneyAccounts, bookAdd, bookShelf, yearCalendars, yearUpcoming
        case settingsSearch, settingsWidgets, settingsBackup

        var tab: String {
            switch self {
            case .habitPeriods, .habitAdd: "habits"
            case .mushaf, .quranPlan: "quran"
            case .diaryWrite, .diaryBrowse: "notes"
            case .expense, .moneyAccounts: "money"
            case .bookAdd, .bookShelf: "mihbara"
            case .settingsSearch, .settingsWidgets, .settingsBackup: "customize"
            default: "foundation"
            }
        }

        var showsYear: Bool { self == .yearCalendars || self == .yearUpcoming }

        var themeRoom: String {
            switch tab {
            case "habits": "salah"
            case "quran": "quran"
            case "notes": "notes"
            case "money": "mal"
            case "mihbara": "mihbara"
            default: "bahw"
            }
        }

        var copy: (title: String, message: String) {
            switch self {
            case .welcome: ("جولة في مدار", "أنت الآن في البهو. هنا يجتمع اللي تتابعه في يومك، ومنه تبدأ جولتك بين الأقسام.")
            case .search: ("ابحث في مدار", "العدسة تفتح البحث في مدار. استخدمها إذا تبي ترجع لعادة أو مذكّرة أو كتاب.")
            case .arrange: ("رتّب البهو", "من «رتّب» حرّك الودجات، غيّر أحجامها أو اختر اللي تبي تعرضه.")
            case .settingsDoor: ("إعدادات مدار", "من زر الضبط غيّر المدينة، المظهر، التذكيرات وإعدادات كل قسم.")
            case .navigation: ("انتقل بين الأقسام", "أسماء الأقسام في شريط التنقّل. اختر أي قسم للذهاب إليه، واختر «البهو» للرجوع.")
            case .habitPeriods: ("فترات العادات", "بعد ما تضيف عادة، تظهر فترات يومك. اضغط فترة لتشوف عاداتها، وسجّل من الدائرة بجانب العادة.")
            case .habitAdd: ("أضف عادة", "زر الإضافة يبدأ عادة جديدة. اختر طريقة متابعتها والوقت اللي يناسبك.")
            case .mushaf: ("المصحف", "زر «المصحف» يفتح القراءة. قلّب الأوجه، واضغط وسط الصفحة لإظهار أدواتها. إذا عندك خطة حفظ، تجده ضمن «أدوات».")
            case .quranPlan: ("خطة الحفظ", "من «ابدأ خطة الحفظ» تحدد مقدارك. بعد ذلك تتابع ورد اليوم والمراجعة، وتعدّل الخطة من «خطّتك».")
            case .diaryWrite: ("اكتب يومك", "ابدأ من حقل الكتابة في صفحة اليوم. بجانبه أدوات التسجيل الصوتي وإضافة صورة.")
            case .diaryBrowse: ("تصفّح مذكراتك", "من «المزيد» اختر «اقرأ» لقراءة صفحة اليوم. للأيام السابقة، افتح «كل الذكريات». تلقى «التقويم» في «طريقة العرض».")
            case .expense: ("سجّل مصروفًا", "زر الإضافة في المال يفتح المصروف. اكتب المبلغ واختر مصدر الدفع، ثم اضغط التسجيل.")
            case .moneyAccounts: ("حساباتك", "ابدأ من «أضف حسابك يدويًا». تفتح «الحسابات» لاحقًا من أدوات المال لمراجعة رصيدها وإدارتها.")
            case .bookAdd: ("أضف كتابًا", "زر الإضافة يسجّل كتابًا ورقيًا أو يضيف ملف PDF أو EPUB إلى المحبرة.")
            case .bookShelf: ("رفوفك", "اضغط كتابًا لتفتحه وتكمل من مكانك. من «كل كتبي» تقدر تبحث في المكتبة.")
            case .yearCalendars: ("السنة", "افتح هذه الصفحة من ودجة «السنة» في البهو. إذا عرضت التقويمين، بدّل بين «هجرية» و«ميلادية» من الشريط.")
            case .yearUpcoming: ("الأيام القادمة", "من زر الإضافة في قسم الأيام القادمة سجّل يومًا يهمّك وتابع كم بقي عليه.")
            case .settingsSearch: ("ابحث في الإعدادات", "اكتب اسم الشيء اللي تبي تغيره، مثل «المظهر»، وافتح الخيار من النتائج.")
            case .settingsWidgets: ("ودجات البهو", "من «أقسامك والبهو» تتحكم في عرض الودجات وترتيبها، وتلقى ودجات الشاشة الرئيسية على الآيفون والآيباد.")
            case .settingsBackup: ("النسخ والاستعادة", "من «النسخ والاستعادة» تقدر تحفظ نسخة مشفّرة من بياناتك أو تستعيدها. تقدر تعيد هذه الجولة من «جولة مدار» في الإعدادات.")
            }
        }
    }

    private(set) var step: Step?
    private(set) var targetFrame: CGRect?
    private(set) var displayName: String
    private let key: String

    init() {
        #if DEBUG
        let store = ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:))
        key = store.map { "Madar.UITest.\($0.uuidString).welcome" } ?? "Madar.welcome"
        #else
        key = "Madar.welcome"
        #endif
        displayName = UserDefaults.standard.string(forKey: key + ".name") ?? ""
    }

    var pending: Bool { UserDefaults.standard.bool(forKey: key + ".tourPending") }
    var completed: Bool { UserDefaults.standard.bool(forKey: key + ".tourCompleted") }
    var pendingStep: Step {
        UserDefaults.standard.string(forKey: key + ".tourStep").flatMap(Step.init(rawValue:)) ?? .welcome
    }

    func prepareFirstRun(name: String) {
        updateName(name)
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["MADAR_UI_STORE_ID"] != nil, environment["MADAR_UI_TOUR"] != "1" { return }
        #endif
        UserDefaults.standard.set(true, forKey: key + ".tourPending")
    }

    func updateName(_ name: String) {
        displayName = Self.cleanName(name)
        let nameKey = key + ".name"
        if displayName.isEmpty {
            UserDefaults.standard.removeObject(forKey: nameKey)
        } else {
            UserDefaults.standard.set(displayName, forKey: nameKey)
        }
    }

    func show(_ step: Step) {
        targetFrame = nil
        self.step = step
        if pending { UserDefaults.standard.set(step.rawValue, forKey: key + ".tourStep") }
    }

    func measure(_ frame: CGRect, for step: Step) {
        if self.step == step, !frame.isEmpty { targetFrame = frame }
    }

    func end(completed: Bool) {
        step = nil
        targetFrame = nil
        UserDefaults.standard.removeObject(forKey: key + ".tourPending")
        UserDefaults.standard.removeObject(forKey: key + ".tourStep")
        if completed { UserDefaults.standard.set(true, forKey: key + ".tourCompleted") }
    }

    static func cleanName(_ name: String) -> String {
        String(name.filter { !$0.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) } }
            .trimmingCharacters(in: .whitespacesAndNewlines).prefix(40))
    }

    static func isolate(_ name: String) -> String { "\u{2068}" + name + "\u{2069}" }
}

extension AppSession {
    func startPendingMadarTour() {
        if onboardingComplete, madarTour.pending, madarTour.step == nil {
            startMadarTour(at: madarTour.pendingStep)
        }
    }

    func startMadarTour(at step: MadarTour.Step = .welcome) {
        guard madarTour.step == nil else { return }
        pendingIntro = nil
        habitsOpen = false
        showMadarTourStep(step)
    }

    func showMadarTourStep(_ step: MadarTour.Step) {
        madarTour.show(step)
        if step.tab == "customize" { settingsQuery = "" }
        selectedTab = step.tab
        yearOpen = step.showsYear
    }

    func endMadarTour(completed: Bool = false, returnToLobby: Bool = true) {
        if returnToLobby { selectedTab = "foundation" }
        yearOpen = false
        madarTour.end(completed: completed)
    }
}

extension EnvironmentValues {
    @Entry var madarTour: MadarTour? = nil
}

extension View {
    func madarTourAnchor(_ step: MadarTour.Step) -> some View {
        modifier(MadarTourAnchor(step: step))
    }

    func madarTourHost(_ session: AppSession) -> some View {
        modifier(MadarTourHost(session: session))
    }

    func madarTourScroll(_ proxy: ScrollViewProxy, ready: Bool = true, to steps: MadarTour.Step...) -> some View {
        modifier(MadarTourScroll(proxy: proxy, ready: ready, steps: steps))
    }
}

private struct MadarTourScrollTarget: Hashable {
    let step: MadarTour.Step
}

private struct MadarTourAnchor: ViewModifier {
    let step: MadarTour.Step
    @Environment(\.madarTour) private var tour
    @Environment(\.isFrontRoom) private var isFrontRoom

    func body(content: Content) -> some View {
        content.id(MadarTourScrollTarget(step: step)).background {
            if isFrontRoom, let tour, tour.step == step {
                Color.clear.onGeometryChange(for: CGRect.self) { $0.frame(in: .global) } action: {
                    tour.measure($0, for: step)
                }
            }
        }
    }
}

private struct MadarTourScroll: ViewModifier {
    let proxy: ScrollViewProxy
    let ready: Bool
    let steps: [MadarTour.Step]
    @Environment(\.madarTour) private var tour
    @Environment(\.isFrontRoom) private var isFrontRoom

    func body(content: Content) -> some View {
        let step = isFrontRoom && ready ? tour?.step : nil
        content.task(id: step) {
            guard let step, steps.contains(step) else { return }
            await Task.yield()
            guard !Task.isCancelled else { return }
            proxy.scrollTo(MadarTourScrollTarget(step: step), anchor: .center)
        }
    }
}

private struct MadarTourHost: ViewModifier {
    let session: AppSession
    @Environment(\.roomTheme) private var theme

    func body(content: Content) -> some View {
        let tour = session.madarTour
        content
            .environment(\.madarTour, tour)
            .allowsHitTesting(tour.step == nil)
            .accessibilityHidden(tour.step != nil)
            .overlay {
                if let step = tour.step {
                    MadarTourOverlay(session: session, step: step)
                        .environment(\.roomTheme, RoomTheme(room: step.themeRoom, dark: theme.dark))
                }
            }
    }
}

private struct MadarTourOverlay: View {
    let session: AppSession
    let step: MadarTour.Step
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AccessibilityFocusState private var focusTitle: Bool

    private var index: Int { MadarTour.Step.allCases.firstIndex(of: step) ?? 0 }
    private var last: Bool { index == MadarTour.Step.allCases.count - 1 }
    var body: some View {
        GeometryReader { proxy in
            let top = highlight(in: proxy).map { $0.midY > proxy.size.height * 0.53 } ?? false
            ZStack(alignment: top ? .top : .bottom) {
                spotlight
                ViewThatFits(in: .vertical) {
                    card
                    ScrollView { card }.frame(maxHeight: proxy.size.height * 0.70)
                }
                .frame(maxWidth: 485)
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .contentShape(Rectangle())
        }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(.isModal)
        .accessibilityAction(.escape) { session.endMadarTour() }
        .onChange(of: step, initial: true) { _, _ in focusTitle = true }
    }

    private var spotlight: some View {
        GeometryReader { proxy in
            let frame = highlight(in: proxy)
            ZStack {
                Path { path in
                    path.addRect(CGRect(origin: .zero, size: proxy.size))
                    if let frame {
                        path.addRoundedRect(in: frame, cornerSize: CGSize(width: 12, height: 12))
                    }
                }
                .fill(.black.opacity(0.53), style: .init(eoFill: true))
                .accessibilityHidden(true)

                if let frame {
                    RoundedRectangle(cornerRadius: 12).strokeBorder(theme.accentFill, lineWidth: 3)
                        .frame(width: frame.width, height: frame.height)
                        .position(x: frame.midX, y: frame.midY)
                        .accessibilityLabel(step.copy.title)
                        .accessibilityIdentifier("madar-tour-spotlight")
                }
            }
        }
        // The spotlight traces physical screen coordinates; the card itself follows the app's RTL layout.
        .environment(\.layoutDirection, .leftToRight)
        .ignoresSafeArea(.container)
    }

    private func highlight(in proxy: GeometryProxy) -> CGRect? {
        guard let target = session.madarTour.targetFrame else { return nil }
        let origin = proxy.frame(in: .global).origin
        let area = CGRect(origin: .zero, size: proxy.size)
        let local = target.offsetBy(dx: -origin.x, dy: -origin.y).insetBy(dx: -5, dy: -5)
        let clipped = local.intersection(area)
        guard !clipped.isNull, clipped.height >= min(28, local.height) else { return nil }
        return clipped
    }

    private var card: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack {
                Text(session.digits(index + 1) + " من " + session.digits(MadarTour.Step.allCases.count))
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Spacer()
                Button("تخطَّ الجولة") { session.endMadarTour() }
                    .buttonStyle(.madarPlain)
                    .frame(minHeight: 44)
                    .accessibilityIdentifier("madar-tour-skip")
            }
            Text(step.copy.title)
                .font(MadarTypography.cardTitle())
                .contentTransition(.opacity)
                .accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("madar-tour-title")
                .accessibilityFocused($focusTitle)
            Text(step.copy.message)
                .font(MadarTypography.body())
                .contentTransition(.opacity)
                .foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 16) {
                Button(last ? "تمّ" : "التالي") {
                    if last { session.endMadarTour(completed: true) }
                    else { session.showMadarTourStep(MadarTour.Step.allCases[index + 1]) }
                }
                .buttonStyle(MadarPrimaryButton())
                .accessibilityIdentifier("madar-tour-next")
                if index > 0 {
                    Button("السابق") { session.showMadarTourStep(MadarTour.Step.allCases[index - 1]) }
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("madar-tour-back")
                }
            }
        }
        .padding(16)
        .background(theme.surface, in: .rect(cornerRadius: 24))
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.18), value: step)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("madar-tour-card")
    }
}
