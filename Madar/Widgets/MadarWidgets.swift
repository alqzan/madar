import SwiftUI
import WidgetKit
import MadarSnapshots

private struct FoundationEntry: TimelineEntry {
    let date: Date
    let ready: Bool
}
private struct FoundationProvider: TimelineProvider {
    func placeholder(in context: Context) -> FoundationEntry { .init(date: .now, ready: false) }
    func getSnapshot(in context: Context, completion: @escaping (FoundationEntry) -> Void) {
        completion(.init(date: .now, ready: false))
    }
    func getTimeline(in context: Context, completion: @escaping (Timeline<FoundationEntry>) -> Void) {
        let store = try? SnapshotStore.appGroup("group.com.alqzan.madar2")
        let value = store?.read("foundation", as: FoundationSnapshot.self)
        completion(Timeline(entries: [.init(date: .now, ready: value != nil)], policy: .after(.now.addingTimeInterval(3600))))
    }
}
private struct FoundationWidget: Widget {
    let kind = "MadarFoundation"
    var body: some WidgetConfiguration {
        StaticConfiguration(kind: kind, provider: FoundationProvider()) { entry in
            VStack(alignment: .leading, spacing: 8) {
                Image(systemName: "circle.circle").font(.title).widgetAccentable()
                Text("مدار").font(.title2.weight(.semibold))
                Text("افتح مدار").font(.body)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .containerBackground(.background, for: .widget)
        }
        .configurationDisplayName("مدار")
        .description("افتح مدار من الشاشة الرئيسية.")
        .supportedFamilies([.systemSmall])
    }
}
@main struct MadarWidgetBundle: WidgetBundle {
    var body: some Widget { FoundationWidget() }
}
