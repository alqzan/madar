import SwiftUI
import MadarData
import MadarDesign

struct FirstRunView: View {
    @Bindable var session: AppSession
    @State private var step = 0
    @State private var cityChosen = false
    @Environment(\.roomTheme) private var theme
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 28) {
                    HStack(spacing: 8) {
                        ForEach([0, 1], id: \.self) { dot in Capsule().fill(dot == step ? theme.accentFill : theme.line).frame(width: dot == step ? 30 : 8, height: 8) }
                    }.accessibilityLabel(step == 0 ? "الخطوة الأولى من خطوتين" : "الخطوة الثانية من خطوتين")
                    Image(systemName: step == 0 ? "circle.hexagongrid" : "location.circle").font(.system(size: 54)).foregroundStyle(theme.accent).accessibilityHidden(true)
                    Text(step == 0 ? "مدار" : "ابدأ من مدينتك").font(MadarTypography.title())
                    Text(step == 0 ? "يومك بين الصلوات" : "نحتاج مدينتك لمواقيت الصلاة وبداية يومك، وتعمل دون اتصال.").font(MadarTypography.cardTitle())
                    if step == 1 {
                        MadarCard {
                            VStack(alignment: .leading, spacing: 16) {
                                Text(cityChosen || session.cityName.isEmpty ? session.cityName : session.cityName + "، حتى تختار مدينتك").font(MadarTypography.section())
                                Text("المواقيت بطريقة أم القرى").foregroundStyle(theme.secondaryInk)
                                NavigationLink("اختر مدينة") { CityEditor(session: session).onDisappear { cityChosen = true } }
                                    .frame(minHeight: 44).accessibilityIdentifier("first-run-city")
                            }
                        }
                    }
                    if step == 1 && session.bool("salah.askReminder") && session.canRequestNotificationPermission {
                        MadarCard {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("تنبيهات الصلاة").font(MadarTypography.section())
                                Text("ينبّهك مدار عند دخول الوقت، ولا يصلك شيء أثناء الصلاة نفسها. يمكنك تغيير ذلك من خصّص.").foregroundStyle(theme.secondaryInk)
                                Button("اسمح بالتنبيهات") { session.requestPrayerNotificationPermission() }
                                    .frame(minHeight: 44).accessibilityIdentifier("first-run-notifications")
                            }
                        }
                    }
                    Button(step == 0 ? "لنبدأ" : "ابدأ يومك") {
                        if step == 0 { step = 1 } else { session.completeOnboarding() }
                    }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("first-run-continue")
                    if step == 0 {
                        Button("انتقل إلى المدينة") { step = 1 }.frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("first-run-skip")
                    }
                }.padding(24).padding(.top, 64).frame(maxWidth: 560).frame(maxWidth: .infinity)
            }.background(theme.background).foregroundStyle(theme.ink).font(MadarTypography.body())
        }
        .interactiveDismissDisabled()
    }
}
