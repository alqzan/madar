import SwiftUI
import MadarDesign

func quranFont(_ size: CGFloat, bold: Bool = false) -> Font {
    .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body)
}
func quranSerif(_ size: CGFloat) -> Font { .custom("Amiri-Bold", size: size, relativeTo: .title2) }
struct QuranPaperCard<Content: View>: View {
    @Environment(\.roomTheme) private var theme
    @ViewBuilder var content: () -> Content
    var body: some View { content().padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 24)).shadow(color: theme.ink.opacity(0.04), radius: 14, y: 8) }
}
struct QuranScreenHeader: View {
    let title: String
    let close: () -> Void
    var body: some View {
        HStack(spacing: 12) {
            Button(action: close) { Image(systemName: "chevron.backward").frame(width: 44, height: 44) }.accessibilityLabel("رجوع").accessibilityIdentifier("quran-screen-close")
            Text(title).font(quranSerif(28)); Spacer()
        }.padding(.vertical, 4)
    }
}
enum QuranLogTab: String, CaseIterable, Identifiable {
    case week, year, all, sessions
    var id: String { rawValue }
    var title: String { switch self { case .week: "الأسبوع"; case .year: "السنة"; case .all: "منذ البداية"; case .sessions: "الجلسات" } }
}
struct QuranLogTabs: View {
    @Binding var selection: QuranLogTab
    @Environment(\.roomTheme) private var theme
    var body: some View {
        HStack(spacing: 3) {
            ForEach(QuranLogTab.allCases) { tab in
                Button { selection = tab } label: { Text(tab.title).font(quranFont(12, bold: selection == tab)).frame(maxWidth: .infinity, minHeight: 44).background(selection == tab ? theme.surface : .clear, in: Capsule()) }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("quran-log-" + tab.id).accessibilityAddTraits(selection == tab ? .isSelected : [])
            }
        }.padding(4).background(theme.color("track"), in: Capsule())
    }
}
struct QuranLogView: View {
    let service: AppQuranService
    let close: () -> Void
    let initialSessionID: UUID?
    @State private var selection: QuranLogTab
    init(service: AppQuranService, close: @escaping () -> Void, initialTab: QuranLogTab = .week, initialSessionID: UUID? = nil) {
        self.service = service; self.close = close; self.initialSessionID = initialSessionID
        _selection = State(initialValue: initialTab)
    }
    var body: some View {
        switch selection {
        case .week: QuranWeekView(service: service, close: close, selection: $selection)
        case .year: QuranYearView(service: service, close: close, selection: $selection)
        case .all: QuranJourneyView(service: service, close: close, selection: $selection)
        case .sessions: QuranSessionLogView(service: service, close: close, selection: $selection, initialSessionID: initialSessionID)
        }
    }
}
