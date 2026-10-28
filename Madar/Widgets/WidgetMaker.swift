import SwiftUI
import WidgetKit
import AppIntents
import MadarCore
import MadarSnapshots

struct SavedMadarWidget: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "ودجة محفوظة")
    static let defaultQuery = SavedMadarWidgetQuery()
    let id: UUID
    let name: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(name)") }
}
struct SavedMadarWidgetQuery: EntityStringQuery {
    private func all() -> [SavedMadarWidget] {
        let store = try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        return (store?.read(WidgetCatalogSnapshot.name, as: WidgetCatalogSnapshot.self)?.payload.configs ?? []).map { .init(id: $0.id, name: $0.name) }
    }
    func suggestedEntities() async throws -> [SavedMadarWidget] { all() }
    func entities(for identifiers: [UUID]) async throws -> [SavedMadarWidget] {
        let values = all()
        return identifiers.map { id in values.first { $0.id == id } ?? .init(id: id, name: "ودجة غير متاحة") }
    }
    func entities(matching string: String) async throws -> [SavedMadarWidget] { all().filter { $0.name.localizedStandardContains(string) } }
}
struct MakerWidgetIntent: WidgetConfigurationIntent {
    static let title: LocalizedStringResource = "ودجتك من مدار"
    @Parameter(title: "القالب") var preset: SavedMadarWidget?
}
struct MakerWidgetEntry: TimelineEntry {
    let date: Date
    let config: WidgetCatalogSnapshot.Config?
    let locked: Bool
    let stale: Bool
    let timeZoneID: String
    var relevance: TimelineEntryRelevance? { .init(score: locked || stale || config?.rows.isEmpty != false ? 0 : 1) }
}
struct MakerWidgetProvider: AppIntentTimelineProvider {
    func placeholder(in context: Context) -> MakerWidgetEntry { .init(date: .now, config: nil, locked: false, stale: false, timeZoneID: "Asia/Riyadh") }
    func snapshot(for configuration: MakerWidgetIntent, in context: Context) async -> MakerWidgetEntry { load(configuration, at: .now) }
    func timeline(for configuration: MakerWidgetIntent, in context: Context) async -> Timeline<MakerWidgetEntry> {
        let now = Date(), store = try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        let expiry = store?.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: now)?.validUntil ?? now.addingTimeInterval(900)
        var dates = [now]
        var next = Date(timeIntervalSince1970: (floor(now.timeIntervalSince1970 / 60) + 1) * 60)
        while next < expiry { dates.append(next); next = next.addingTimeInterval(60) }
        var entries = dates.map { load(configuration, at: $0) }
        entries.append(load(configuration, at: expiry.addingTimeInterval(1)))
        return .init(entries: entries, policy: .after(expiry))
    }
    private func load(_ configuration: MakerWidgetIntent, at date: Date) -> MakerWidgetEntry {
        let store = try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        let metadata = store?.read(WidgetCatalogSnapshot.name, as: WidgetCatalogSnapshot.self, now: date)
        let values = store?.read(WidgetCatalogSnapshot.valuesName, as: WidgetCatalogSnapshot.self, now: date)
        let chosen = configuration.preset.map { preset in metadata?.payload.configs.first { $0.id == preset.id } } ?? metadata?.payload.configs.first
        var config = chosen.flatMap { selected in values?.payload.configs.first { $0.id == selected.id } }
        let prayer = store?.read("prayerNext", as: PrayerNextSnapshot.self, now: date)?.payload
        if var value = config {
            value.rows = value.rows.compactMap { row in
                var row = row
                if row.id == "prayerNext" {
                    guard let next = prayer?.state(at: date)?.item else { return nil }
                    row.title = next.name; row.targetDate = next.at
                } else if row.id == "iftar" {
                    guard let next = prayer?.items.first(where: { $0.prayer == "maghrib" && $0.at > date }) else { return nil }
                    row.targetDate = next.at
                }
                return row
            }
            config = value
        }
        return .init(date: date, config: config ?? chosen, locked: metadata?.payload.locked == true,
                     stale: chosen != nil && values == nil, timeZoneID: values?.tzID ?? metadata?.tzID ?? "Asia/Riyadh")
    }
}
private struct MakerWidgetView: View {
    let entry: MakerWidgetEntry
    @Environment(\.widgetFamily) private var family
    @Environment(\.colorScheme) private var colorScheme
    private var style: WidgetMakerStyle { entry.config.flatMap { try? JSONDecoder().decode(WidgetMakerStyle.self, from: $0.styleJSON) } ?? .init() }
    var body: some View {
        WidgetMakerContent(config: entry.config, family: family, date: entry.date, locked: entry.locked, stale: entry.stale, permitsActions: true, usesSystemRendering: true, timeZoneID: entry.timeZoneID)
            .containerBackground(for: .widget) {
                if [.accessoryCircular, .accessoryRectangular, .accessoryInline].contains(family) { Color.clear }
                else { WidgetMakerContent.background(style, dark: colorScheme == .dark) }
            }
    }
}
struct MadarMakerWidget: Widget {
    var body: some WidgetConfiguration {
        AppIntentConfiguration(kind: "MadarMaker", intent: MakerWidgetIntent.self, provider: MakerWidgetProvider()) { MakerWidgetView(entry: $0) }
            .configurationDisplayName("ودجتك من مدار").description("اختر واحدة مما صنعت في «ودجاتي» داخل مدار.")
            .supportedFamilies(MadarWidgetFamilies.homeAndAccessories)
    }
}
