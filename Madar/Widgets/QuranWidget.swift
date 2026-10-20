import SwiftUI
import WidgetKit
import AppIntents
import MadarSnapshots
import MadarDesign

extension QuranWidgetTemplate: AppEnum {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "قالب القرآن")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.coverage: "في صدرك", .path: "مسار اليوم", .week: "الحفظ والمراجعة"]
}
struct QuranWidgetConfiguration: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "القرآن"
    @Parameter(title: "القالب", default: .coverage) var template: QuranWidgetTemplate
}
struct QuranWidgetEntry: TimelineEntry { let date: Date; let value: QuranWidgetSnapshot?; let template: QuranWidgetTemplate }
struct QuranWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> QuranWidgetEntry { .init(date: .now, value: nil, template: .coverage) }
    func snapshot(for configuration: QuranWidgetConfiguration, in context: Context) async -> QuranWidgetEntry { load(configuration) }
    func timeline(for configuration: QuranWidgetConfiguration, in context: Context) async -> Timeline<QuranWidgetEntry> {
        let now = Date(), store = try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        let snapshot = store?.read("quran", as: QuranWidgetSnapshot.self, now: now)
        let until = snapshot?.validUntil ?? now.addingTimeInterval(900)
        let entries = [QuranWidgetEntry(date: now, value: snapshot?.payload, template: configuration.template), .init(date: until, value: nil, template: configuration.template)]
        return Timeline(entries: entries, policy: .after(until))
    }
    private func load(_ configuration: QuranWidgetConfiguration) -> QuranWidgetEntry {
        let store = try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        return .init(date: .now, value: store?.read("quran", as: QuranWidgetSnapshot.self)?.payload, template: configuration.template)
    }
}
private struct QuranWidgetView: View {
    let entry: QuranWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var scheme
    private var extraLargePortrait: Bool { if #available(iOS 27.0, *) { family == .systemExtraLargePortrait } else { false } }
    var body: some View {
        Group {
            if family == .accessoryInline { Text("القرآن، " + (entry.value?.nextDetail ?? "افتح مدار")) }
            else { QuranWidgetContent(snapshot: entry.value, template: entry.template, compact: family == .accessoryCircular || family == .accessoryRectangular, extraLarge: extraLargePortrait) }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .widgetURL(URL(string: entry.value?.route ?? "madar://quran"))
        .containerBackground(for: .widget) { RoomTheme(room: "quran", dark: scheme == .dark).surface }
    }
}
struct QuranWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MadarQuran", intent: QuranWidgetConfiguration.self, provider: QuranWidgetProvider()) { QuranWidgetView(entry: $0) }
            .configurationDisplayName("القرآن").description("في صدرك، ومسار اليوم، والحفظ والمراجعة.")
            .supportedFamilies(MadarWidgetFamilies.homeAndAccessories)
    }
}
struct QuranReviewTimerControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "com.alqzan.madar2.quran-review") {
            ControlWidgetButton(action: StartQuranSessionIntent(step: .review)) { Label("مؤقّت المراجعة", systemImage: "stopwatch") }
        }.displayName("مؤقّت المراجعة").description("ابدأ المراجعة أو استأنف جلستك، والمؤقّت في طريقة الجلسة.")
    }
}
