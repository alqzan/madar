import SwiftUI
import WidgetKit
import ActivityKit
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
    var body: some Widget {
        FoundationWidget()
        NextPrayerWidget()
        PrayerCountdownActivityWidget()
    }
}

private struct PrayerCountdownActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerCountdownAttributes.self) { context in
            HStack(spacing: 12) {
                Image(systemName: "moon.stars").font(.title2).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("الصلاة القادمة").font(.caption)
                    Text(context.state.prayerName).font(.headline)
                }
                Spacer(minLength: 8)
                Text(context.state.prayerAt, style: .timer).monospacedDigit().font(.body)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .padding()
            .activityBackgroundTint(.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack {
                        Text(context.state.prayerName).font(.headline)
                        Spacer()
                        Text(context.state.prayerAt, style: .timer).monospacedDigit()
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image(systemName: "moon.stars")
            } compactTrailing: {
                Text(context.state.prayerAt, style: .timer).monospacedDigit()
            } minimal: {
                Image(systemName: "moon.stars")
            }
            .widgetURL(URL(string: "madar://prayer"))
            .keylineTint(.teal)
        }
    }
}
