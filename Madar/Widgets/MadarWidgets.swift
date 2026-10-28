import SwiftUI
import WidgetKit
import ActivityKit
import AppIntents
import UIKit
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
                Image("MadarOrbit").renderingMode(.template).resizable().scaledToFit().frame(width: 28, height: 28).widgetAccentable()
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
        MadarMakerWidget()
        NextPrayerWidget()
        QuranWidget()
        AdditionalRoomWidgets().body
        QuranReviewTimerControl()
        PrayerCountdownActivityWidget()
        MadarContextActivityWidget()
        PrayerLogControl()
        PrayerCountdownControl()
    }
}

private struct PrayerCountdownActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: PrayerCountdownAttributes.self) { context in
            HStack(spacing: 12) {
                Image("MadarPrayer").renderingMode(.template).resizable().scaledToFit().frame(width: 24, height: 24).accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("الصلاة القادمة").font(.caption)
                    Text(context.state.prayerName).font(.headline)
                }
                Spacer(minLength: 8)
                PrayerActivityTimer(start: context.attributes.scheduledStartAt, end: context.state.prayerAt, numerals: context.attributes.numerals).font(.body)
            }
            .environment(\.layoutDirection, .rightToLeft)
            .padding()
            .activityBackgroundTint(Color(uiColor: .secondarySystemBackground))
            .activitySystemActionForegroundColor(Color(uiColor: .label))
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.center) {
                    HStack {
                        Text(context.state.prayerName).font(.headline)
                        Spacer()
                        PrayerActivityTimer(start: context.attributes.scheduledStartAt, end: context.state.prayerAt, numerals: context.attributes.numerals)
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
            } compactLeading: {
                Image("MadarPrayer").renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
            } compactTrailing: {
                PrayerActivityTimer(start: context.attributes.scheduledStartAt, end: context.state.prayerAt, numerals: context.attributes.numerals)
            } minimal: {
                Image("MadarPrayer").renderingMode(.template).resizable().scaledToFit().frame(width: 18, height: 18)
            }
            .widgetURL(URL(string: "madar://prayer"))
            .keylineTint(.teal)
        }
    }
}

private struct MadarContextActivityWidget: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: MadarContextActivityAttributes.self) { context in
            HStack(spacing: 12) {
                ContextActivityIcon(kind: context.attributes.kind).frame(width: 24, height: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(context.attributes.kind.title).font(.caption)
                    if context.isStale {
                        Text(context.attributes.kind.staleTitle).font(.headline)
                    } else if context.attributes.kind == .travel, let city = context.state.city {
                        Text(city).font(.headline).privacySensitive()
                    } else {
                        Text(context.attributes.kind == .iftar ? "الإفطار" : "مدار").font(.headline)
                    }
                }
                Spacer(minLength: 8)
                if !context.isStale {
                    ContextActivityTime(attributes: context.attributes, state: context.state).font(.body)
                }
            }
            .environment(\.layoutDirection, .rightToLeft)
            .padding()
            .activityBackgroundTint(.black.opacity(0.92))
            .activitySystemActionForegroundColor(.white)
            .widgetURL(context.attributes.kind.destination)
        } dynamicIsland: { context in
            DynamicIsland {
                DynamicIslandExpandedRegion(.leading) {
                    ContextActivityIcon(kind: context.attributes.kind).frame(width: 22, height: 22)
                }
                DynamicIslandExpandedRegion(.center) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(context.attributes.kind.title).font(.caption2)
                        if context.isStale {
                            Text(context.attributes.kind.staleTitle).font(.headline)
                        } else if context.attributes.kind == .travel, let city = context.state.city {
                            Text(city).font(.headline).privacySensitive()
                        }
                    }
                    .environment(\.layoutDirection, .rightToLeft)
                }
                DynamicIslandExpandedRegion(.trailing) {
                    if !context.isStale {
                        ContextActivityTime(attributes: context.attributes, state: context.state).font(.caption)
                    }
                }
                DynamicIslandExpandedRegion(.bottom) {
                    if context.attributes.kind == .letter && !context.isStale {
                        // Audit 28 Oct: the title above already says «رسالة تنتظر وقتها»; the bottom says when it opens.
                        Text("تُفتح في وقتها").font(.caption)
                    }
                }
            } compactLeading: {
                ContextActivityIcon(kind: context.attributes.kind).frame(width: 16, height: 16)
            } compactTrailing: {
                if context.isStale {
                    Text(context.attributes.kind.compactStaleTitle).font(.caption2)
                } else {
                    ContextActivityTime(attributes: context.attributes, state: context.state).font(.caption2)
                }
            } minimal: {
                ContextActivityIcon(kind: context.attributes.kind).frame(width: 16, height: 16)
            }
            .widgetURL(context.attributes.kind.destination)
            .keylineTint(context.attributes.kind == .iftar ? .orange : .teal)
        }
    }
}

private struct ContextActivityIcon: View {
    let kind: MadarContextActivityAttributes.Kind
    var body: some View {
        Image(systemName: kind.symbol)
            .resizable()
            .scaledToFit()
            .foregroundStyle(Color(uiColor: .label))
            .accessibilityHidden(true)
    }
}

private struct ContextActivityTime: View {
    let attributes: MadarContextActivityAttributes
    let state: MadarContextActivityAttributes.ContentState

    var body: some View {
        Group {
            if attributes.kind == .iftar, let eventAt = state.eventAt {
                Text(.currentDate, format: .timer(countingDownIn:
                    min(attributes.startedAt, eventAt.addingTimeInterval(-1))..<eventAt,
                    maxFieldCount: 2, maxPrecision: .seconds(60)))
            } else if attributes.kind == .travel, let timeZoneID = state.timeZoneID {
                Text(.currentDate, format: Date.FormatStyle(date: .omitted, time: .shortened,
                    locale: Locale(identifier: numeralLocaleID), timeZone: TimeZone(identifier: timeZoneID) ?? .current))
            } else if let eventAt = state.eventAt {
                Text(eventAt, style: .time)
            } else {
                EmptyView()
            }
        }
        .monospacedDigit()
        .environment(\.locale, Locale(identifier: numeralLocaleID))
    }

    private var numeralLocaleID: String {
        attributes.numerals == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab"
    }
}

/// RL7: hours and minutes; the discrete system formatter refreshes only when a minute changes.
private struct PrayerActivityTimer: View {
    let start: Date
    let end: Date
    let numerals: String?
    var body: some View {
        Text(.currentDate, format: .timer(countingDownIn: min(start, end.addingTimeInterval(-1))..<end,
            maxFieldCount: 2, maxPrecision: .seconds(60)))
            .monospacedDigit()
            .environment(\.locale, Locale(identifier: numerals == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab"))
    }
}
