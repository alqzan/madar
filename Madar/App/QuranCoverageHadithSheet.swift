import SwiftUI
import MadarDesign

enum QuranMemorizationHadith {
    static let text = "«يُقال لصاحب القرآن: اقرأ وارتق ورتّل، كما كنت ترتّل في الدنيا؛ فإن منزلك عند آخر آية تقرؤها»"
}

/// Arabic wording of Sunan Abi Dawud 1464, verified at https://sunnah.com/abudawud:1464.
struct QuranCoverageHadithSheet: View {
    let theme: RoomTheme
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 22) {
                Text("اقرأ وارتق")
                    .font(.custom("Amiri-Bold", size: 28, relativeTo: .title))
                    .foregroundStyle(theme.color("hifzText"))
                Text("قال رسول الله ﷺ")
                    .font(.custom("thmanyahsans-Regular", size: 13, relativeTo: .body))
                    .foregroundStyle(theme.secondaryInk)
                Text(QuranMemorizationHadith.text)
                    .font(.custom("Amiri-Bold", size: 22, relativeTo: .title2))
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("quran-hadith-text")
                Text("عن عبد الله بن عمرو رضي الله عنهما\nرواه أبو داود، حديث ١٤٦٤")
                    .font(.custom("thmanyahsans-Regular", size: 12, relativeTo: .body))
                    .foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("quran-hadith-source")
                Rectangle().fill(theme.color("line")).frame(height: 1)
                Text("في صدرك هو ما أكملت حفظه من القرآن، وتعينك المراجعة على تثبيته.")
                    .font(.custom("thmanyahsans-Regular", size: 14, relativeTo: .body))
                Button("تمّ") { dismiss() }
                    .font(.custom("thmanyahsans-Bold", size: 14, relativeTo: .body))
                    .frame(maxWidth: .infinity, minHeight: 48)
                    .foregroundStyle(theme.onAccent)
                    .background(theme.color("accent"), in: Capsule())
                    .accessibilityIdentifier("quran-hadith-close")
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundStyle(theme.ink)
        .background(theme.background.ignoresSafeArea())
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(theme.background)
    }
}
