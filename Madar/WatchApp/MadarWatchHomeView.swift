import SwiftUI
import MadarSnapshots

struct MadarWatchHomeView: View {
    @EnvironmentObject private var store: WatchSnapshotStore
    private let gold = Color(red: 0.82, green: 0.67, blue: 0.40)

    var body: some View {
        TimelineView(.periodic(from: .now, by: 60)) { timeline in
            if let envelope = store.envelope,
               envelope.generatedAt <= timeline.date, envelope.validUntil > timeline.date {
                dashboard(envelope, now: timeline.date)
            } else {
                unavailable
            }
        }
        .environment(\.layoutDirection, .rightToLeft)
        .preferredColorScheme(.dark)
    }

    private var unavailable: some View {
        VStack(spacing: 8) {
            Image(systemName: store.envelope == nil ? "iphone.gen3" : "arrow.clockwise")
                .font(.system(size: 24, weight: .light)).foregroundStyle(gold)
            Text(store.envelope == nil ? "افتح مدار على الآيفون" : "افتح مدار لتحديث بيانات الساعة")
                .font(.system(size: 15, weight: .medium, design: .rounded))
                .multilineTextAlignment(.center)
            Text("ستظهر هنا عاداتك وملخص اليوم")
                .font(.system(size: 11)).foregroundStyle(.secondary).multilineTextAlignment(.center)
        }
        .padding(14).frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func dashboard(_ envelope: SnapshotEnvelope<WatchDashboardSnapshot>, now: Date) -> some View {
        let snapshot = envelope.payload
        return ScrollView {
            VStack(spacing: 10) {
                VStack(spacing: 2) {
                    Text(snapshot.datePrimary).font(.system(size: 14, weight: .semibold, design: .rounded))
                    Text(snapshot.dateSecondary).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                // Owner 17 Nov 2026: the prayer card gave way to today's habits (decision 1 of the habits-replace-prayer plan).
                if let habits = snapshot.habits {
                    progressCard(title: "العادات", symbol: "leaf", progress: habits, snapshot: snapshot)
                }
                if let quran = snapshot.quran {
                    progressCard(title: "القرآن", symbol: "book.closed", progress: quran, snapshot: snapshot)
                }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
        }
    }

    private func prayerCard(_ snapshot: WatchDashboardSnapshot, timeZoneID: String, now: Date) -> some View {
        VStack(spacing: 5) {
            Label("الصلاة القادمة", systemImage: "sun.horizon")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(gold)
            if let prayer = snapshot.nextPrayer(after: now) {
                Text(prayer.name).font(.system(size: 20, weight: .semibold, design: .rounded))
                Text(formattedTime(prayer.at, numerals: snapshot.numerals, timeZoneID: timeZoneID))
                    .font(.system(size: 13, weight: .medium, design: .rounded)).foregroundStyle(.secondary)
                if prayer.at > now {
                    Text(countdown(prayer.at.timeIntervalSince(now), snapshot: snapshot))
                        .font(.system(size: 16, weight: .semibold, design: .rounded).monospacedDigit())
                        .contentTransition(.numericText())
                }
            } else {
                Text("لا تتوفر مواقيت الآن").font(.system(size: 13)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity).padding(.vertical, 10)
        .background(.thinMaterial, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 16, style: .continuous).strokeBorder(gold.opacity(0.22), lineWidth: 1))
    }

    private func progressCard(title: String, symbol: String, progress: WatchDashboardSnapshot.Progress,
                              snapshot: WatchDashboardSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Label(title, systemImage: symbol).font(.system(size: 12, weight: .medium)).foregroundStyle(gold)
            if progress.total > 0 {
                ProgressView(value: Double(progress.completed), total: Double(progress.total)).tint(gold)
                Text("أتممت \(snapshot.digits(progress.completed)) من \(snapshot.digits(progress.total))")
                    .font(.system(size: 11, weight: .medium)).foregroundStyle(.secondary)
            } else {
                Text(title == "العادات" ? "ما عليك عادة اليوم" : "لا وِرد محدد اليوم")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(9)
        .background(.white.opacity(0.055), in: RoundedRectangle(cornerRadius: 13, style: .continuous))
    }

    private func countdown(_ interval: TimeInterval, snapshot: WatchDashboardSnapshot) -> String {
        let minutes = max(0, Int(interval / 60))
        let hoursText = snapshot.digits(minutes / 60)
        let remainder = minutes % 60
        return hoursText + ":" + snapshot.digits(remainder / 10) + snapshot.digits(remainder % 10)
    }

    private func formattedTime(_ date: Date, numerals: String, timeZoneID: String) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: numerals == "western" ? "en_US" : "ar_SA")
        formatter.timeZone = TimeZone(identifier: timeZoneID) ?? .current
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}
