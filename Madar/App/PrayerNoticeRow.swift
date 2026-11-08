import SwiftUI
import MadarDesign

struct PrayerNoticeRow: View {
    let title: String
    let detail: String
    let action: String?
    let identifier: String
    let perform: (() -> Void)?
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType

    init(title: String, detail: String, action: String?, identifier: String, perform: (() -> Void)? = nil) {
        self.title = title
        self.detail = detail
        self.action = action
        self.identifier = identifier
        self.perform = perform
    }

    @ViewBuilder
    var body: some View {
        if let perform {
            Button(action: perform) {
                content
            }
            .buttonStyle(.madarPlain)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier(identifier)
        } else {
            content
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(identifier)
        }
    }

    private var content: some View {
        PrayerPaperCard {
            let layout = dynamicType.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 10)) : AnyLayout(HStackLayout(spacing: 12))
            layout {
                HStack(alignment: .top, spacing: 12) {
                    Rectangle().fill(theme.accent).frame(width: 8, height: 8).rotationEffect(.degrees(45)).padding(.top, 7)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(PrayerHomeType.strong).fixedSize(horizontal: false, vertical: true)
                        Text(detail).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                if let action {
                    Text(action).font(PrayerHomeType.strong).foregroundStyle(theme.accent)
                }
            }
        }
    }
}
