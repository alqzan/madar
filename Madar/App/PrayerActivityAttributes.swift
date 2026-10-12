import ActivityKit
import Foundation

struct PrayerCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var prayerName: String
        var prayerAt: Date
    }

    var activityKey: String
    var scheduledStartAt: Date
}
