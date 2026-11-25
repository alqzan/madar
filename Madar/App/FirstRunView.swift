import SwiftUI
import MadarDesign
import MadarData

struct FirstRunView: View {
    @Bindable var session: AppSession
    @State private var choosingCity = false
    @State private var step: Step = .welcome
    @StateObject private var locator = CityLocator()
    @Environment(\.roomTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType

    private enum Step {
        case welcome, city
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                layout
                    .padding(.horizontal, 24)
                    .padding(.vertical, 30)
                    .frame(maxWidth: .infinity)
            }
            .background(theme.background.ignoresSafeArea())
            .foregroundStyle(theme.ink)
            .tint(theme.accent)
            .navigationDestination(isPresented: $choosingCity) {
                CityEditor(session: session, onSaved: { session.completeOnboarding() })
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
                    header.frame(width: 340, alignment: .leading)
                    actions.frame(width: 320)
                }
                .padding(.top, 62)
                compactLayout
            }
        } else {
            compactLayout
        }
    }

    private var compactLayout: some View {
        VStack(alignment: .leading, spacing: 22) {
            header
            actions
        }
        .frame(maxWidth: 540)
    }

    @ViewBuilder private var actions: some View {
        switch step {
        case .welcome: welcomeActions
        case .city: cityActions
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 16) {
            MadarGlyph(step == .welcome ? "MadarOrbit" : "location", size: 46)
                .frame(width: 80, height: 80)
                .foregroundStyle(theme.accent)
                .background(theme.surface, in: .rect(cornerRadius: 24))
                .overlay { RoundedRectangle(cornerRadius: 24).strokeBorder(theme.line) }
            Text(step == .welcome ? "مرحبًا بك في مدار" : "اختر مدينتك")
                .font(MadarTypography.title())
                .accessibilityAddTraits(.isHeader)
            Text(step == .welcome
                 ? "من البهو تشوف ما يهمّك اليوم. ابدأ بعادة، أو افتح المصحف، أو اكتب أول سطر في مذكراتك."
                 : "تضبط مدينتك بداية يومك والمواعيد المرتبطة بمواقيت الصلاة. تقدر تغيّرها لاحقًا من الإعدادات.")
                .font(MadarTypography.body())
                .foregroundStyle(theme.secondaryInk)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var welcomeActions: some View {
        VStack(spacing: 8) {
            Button("لنبدأ") { step = .city }
                .buttonStyle(MadarPrimaryButton())
                .accessibilityIdentifier("first-run-continue")
            NavigationLink { MadarGuideView() } label: {
                Label("تعرّف على أقسام مدار", systemImage: "book")
                    .font(MadarTypography.section())
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.madarPlain)
            .foregroundStyle(theme.accent)
            .accessibilityIdentifier("first-run-guide")
        }
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

            Button(locator.working ? "أبحث عن موقعك…" : "استخدم موقعي") { locator.start(save) }
                .buttonStyle(.madarPlain)
                .font(MadarTypography.section())
                .foregroundStyle(theme.accent)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
                .disabled(locator.working || session.userWriteInProgress)
                .accessibilityIdentifier("first-run-locate")

            Text("إذا استخدمت موقعك، يتعرّف النظام على مدينتك عبر Apple مرة واحدة، ويحفظ مدار موقعًا تقريبيًا للمدينة.")
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
                step = .welcome
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
            session.completeOnboarding()
        }
    }
}

/// The same guide is available before setup and from Settings after setup.
struct MadarGuideView: View {
    static let title = "دليل مدار"
    var openTab: ((String) -> Void)?
    @Environment(\.roomTheme) private var theme
    @Environment(\.horizontalSizeClass) private var sizeClass
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.dismiss) private var dismiss
    @State private var expanded: Topic?

    private enum Topic: String, CaseIterable, Identifiable {
        case lobby, habits, quran, notes, money, mihbara, year, preferences
        var id: String { rawValue }

        var room: BahwBlock? {
            switch self {
            case .habits: .habits
            case .quran: .quran
            case .notes: .notes
            case .money: .mal
            case .mihbara: .mihbara
            case .lobby, .year, .preferences: nil
            }
        }

        @MainActor var tab: String? {
            if self == .lobby { return "foundation" }
            return AppSession.roomTabs.first { $0.block == room }?.tab
        }

        @MainActor var title: String {
            switch self {
            case .lobby: "البهو"
            case .year: "السنة والأيام القادمة"
            case .preferences: "الإعدادات والنسخ الاحتياطي"
            default: tab.flatMap { AppSession.tabInfo[$0]?.title } ?? ""
            }
        }

        var symbol: String {
            switch self {
            case .lobby: "MadarOrbit"
            case .year: BahwBlock.year.symbol
            case .preferences: "gearshape"
            default: room?.symbol ?? ""
            }
        }

        var summary: String {
            switch self {
            case .lobby: "ما يهمّك اليوم، والبحث في مدار."
            case .year: "أيام سنتك ومواعيدك القادمة."
            case .preferences: "مدينتك وتذكيراتك ونسختك الاحتياطية."
            default: room?.intro.sentence ?? ""
            }
        }

        @MainActor var steps: [String] {
            switch self {
            case .lobby:
                ["اختر «البهو» من شريط الأقسام أو القائمة الجانبية لتعود إلى يومك.",
                 "اضغط العدسة للبحث في مدار.",
                 "اضغط «رتّب» لتغيّر ترتيب الودجات أو تُظهر ما تحتاجه منها."]
            case .year:
                ["في البهو، افتح ودجة «السنة» أو «الأيام القادمة». تقدر تُظهرها من «رتّب» إذا كانت مخفية.",
                 "تصفّح السنة، أو أضف يومًا يهمّك من «الأيام القادمة» وتابع كم بقي عليه."]
            case .preferences:
                ["اضغط أيقونة الضبط في البهو لفتح الإعدادات.",
                 "غيّر مدينتك من «اليوم والتقويم»."] +
                (MadarPlatform.hasNotifications ? ["اضبط تذكيراتك من «الإشعارات»."] : []) +
                ["من «النسخ والاستعادة»، تقدر تحفظ نسخة مشفّرة من بياناتك أو تستعيدها."]
            default:
                room?.intro.steps ?? []
            }
        }
    }

    var body: some View {
        let wide = isPadWide(sizeClass) && !dynamicType.isAccessibilitySize
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 7) {
                    Text(Self.title)
                        .font(MadarTypography.title())
                        .accessibilityAddTraits(.isHeader)
                        .accessibilityIdentifier("madar-guide-title")
                    Text("اختر قسمًا لتعرف كيف تبدأ فيه وترجع له.")
                        .font(MadarTypography.body())
                        .foregroundStyle(theme.secondaryInk)
                }
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 14, alignment: .top), count: wide ? 2 : 1),
                          alignment: .leading, spacing: 12) {
                    ForEach(Topic.allCases) { topic in topicCard(topic) }
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 22)
            .frame(maxWidth: wide ? 960 : 580)
            .frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .tint(theme.accent)
        .toolbarVisibility(.visible, for: .navigationBar)
    }

    private func topicCard(_ topic: Topic) -> some View {
        let tone = RoomTheme(room: topic.room?.themeRoom ?? "bahw", dark: theme.dark)
        let isExpanded = expanded == topic
        return VStack(alignment: .leading, spacing: 0) {
            Button {
                expanded = isExpanded ? nil : topic
            } label: {
                HStack(alignment: .center, spacing: 12) {
                    MadarGlyph(topic.symbol, size: 24)
                        .frame(width: 42, height: 42)
                        .foregroundStyle(tone.accent)
                        .background(tone.background, in: .rect(cornerRadius: 13))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(topic.title).font(MadarTypography.section()).foregroundStyle(theme.ink)
                        Text(topic.summary).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.footnote.weight(.semibold))
                        .foregroundStyle(theme.secondaryInk)
                        .accessibilityHidden(true)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(14)
                .contentShape(Rectangle())
            }
            .buttonStyle(.madarPlain)
            .accessibilityAddTraits(isExpanded ? .isSelected : [])
            .accessibilityIdentifier("madar-guide-topic-" + topic.id)

            if isExpanded {
                VStack(alignment: .leading, spacing: 12) {
                    ForEach(topic.steps, id: \.self) { step in
                        HStack(alignment: .firstTextBaseline, spacing: 8) {
                            Image(systemName: "circle.fill").font(.system(size: 5))
                                .foregroundStyle(theme.accent).accessibilityHidden(true)
                            Text(step).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                    if let tab = topic.tab, let openTab {
                        Button("افتح \(topic.title)") {
                            dismiss()
                            openTab(tab)
                        }
                        .font(MadarTypography.section())
                        .frame(minHeight: 44)
                        .accessibilityIdentifier("madar-guide-open-" + topic.id)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("madar-guide-steps-" + topic.id)
            }
        }
        .background(theme.surface, in: .rect(cornerRadius: 20))
        .overlay { RoundedRectangle(cornerRadius: 20).strokeBorder(theme.line).allowsHitTesting(false) }
    }
}
