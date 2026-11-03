import SwiftUI
import MadarDesign
import MadarData
import Photos

/// Owner, 3 Nov 2026: «ابي استقبال التطبيق سهل»: a welcome that says what Madar is, then one permission per screen
/// with the reason in one sentence. No default city is announced and no field is shown.
struct FirstRunView: View {
    @Bindable var session: AppSession
    @State private var step = 0
    @StateObject private var locator = CityLocator()
    @Environment(\.roomTheme) private var theme
    private let lastStep = 2

    private struct Page { let symbol: String; let title: String; let text: String }
    private var page: Page {
        switch step {
        case 0: Page(symbol: "circle.hexagongrid", title: "مرحبًا بك في مدار",
                     text: "مدار يرتّب يومك حول الصلاة: صلواتك، وردك من القرآن، وعاداتك، ومذكراتك. تبدأ بقسم واحد وتضيف الباقي متى شئت.")
        case 1: Page(symbol: "location.circle", title: "موقعك",
                     text: "نحتاج مدينتك لحساب مواقيت الصلاة بدقة. يقرأ مدار موقعك مرة واحدة ليعرف المدينة، ويحفظها على جهازك فقط.")
        default: Page(symbol: "photo.on.rectangle", title: "صورك",
                      text: "إذا سمحت، تقدر تضيف صورًا من يومك إلى مذكراتك. لا ينسخ مدار صورك ولا يرسلها لأحد، ويمكنك تخطي هذا الآن.")
        }
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    HStack(spacing: 8) {
                        ForEach(0...lastStep, id: \.self) { dot in Capsule().fill(dot == step ? theme.accentFill : theme.line).frame(width: dot == step ? 30 : 8, height: 8) }
                    }.accessibilityHidden(true)
                    Image(systemName: page.symbol).font(.system(size: 54)).foregroundStyle(theme.accent).accessibilityHidden(true)
                    Text(page.title).font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                    Text(page.text).font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    if let message = locator.message, step == 1 {
                        Text(message).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        if locator.needsSettings {
                            Button("افتح إعدادات الآيفون") { if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) } }
                                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("first-run-open-settings")
                        }
                    }
                    actions
                }.padding(24).padding(.top, 64).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(theme.background).foregroundStyle(theme.ink).font(MadarTypography.body())
        }
        .interactiveDismissDisabled()
    }

    @ViewBuilder private var actions: some View {
        switch step {
        case 0:
            Button("لنبدأ") { step = 1 }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("first-run-continue")
        case 1:
            Button(locator.working ? "أبحث عن موقعك…" : "اسمح بالموقع") { locator.start(save) }
                .buttonStyle(MadarPrimaryButton()).disabled(locator.working).accessibilityIdentifier("first-run-locate")
            NavigationLink("اختر مدينتي بنفسي") { CityEditor(session: session).onDisappear { if !session.cityName.isEmpty { step = 2 } } }
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("first-run-city")
        default:
            Button("اسمح بالصور") {
                Task { _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite); session.completeOnboarding() }
            }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("first-run-photos")
            Button("ليس الآن") { session.completeOnboarding() }
                .frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).accessibilityIdentifier("first-run-continue")
        }
    }

    /// The located city is saved at once; only its name is kept, never the position.
    private func save(_ found: CityLocator.Found) {
        session.set(.object(["name": .string(found.name), "country": .string(found.country), "lat": .number(found.lat), "lon": .number(found.lon),
                             "tz": .string(found.tz), "currency": .string(found.currency)]), key: "core.homeCity")
        step = 2
    }
}
