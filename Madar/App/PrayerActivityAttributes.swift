import ActivityKit
import Foundation

struct PrayerCountdownAttributes: ActivityAttributes {
    struct ContentState: Codable, Hashable {
        var prayerName: String
        var prayerAt: Date
    }

    var activityKey: String
    var scheduledStartAt: Date
    var budgetRequestID: String? = nil
    var numerals: String? = nil
}

/// Generic external activities for diary letters, Ramadan iftar, and travel.
/// Sensitive diary text is deliberately absent from both the attributes and state.
struct MadarContextActivityAttributes: ActivityAttributes {
    enum Kind: String, Codable, Hashable {
        case letter
        case iftar
        case travel
    }

    struct ContentState: Codable, Hashable {
        var eventAt: Date?
        var city: String?
        var timeZoneID: String?
    }

    var activityKey: String
    var kind: Kind
    var startedAt: Date
    var numerals: String? = nil
}

extension MadarContextActivityAttributes.Kind {
    var title: String {
        switch self {
        case .letter: "رسالة تنتظر وقتها"
        case .iftar: "موعد الإفطار"
        case .travel: "توقيت المدينة"
        }
    }

    var symbol: String {
        switch self {
        case .letter: "envelope"
        case .iftar: "sunset"
        case .travel: "airplane"
        }
    }

    /// A stale date can precede the event (for example, at quiet-hours start), so stale copy
    /// must never claim that the event itself has happened.
    var staleTitle: String {
        switch self {
        case .letter: "افتح مدار لتحديث حالة الرسالة"
        case .iftar: "افتح مدار لتحديث وقت الإفطار"
        case .travel: "افتح مدار لتحديث التوقيت"
        }
    }

    var compactStaleTitle: String { "حدّث" }

    var destination: URL? {
        switch self {
        case .letter: URL(string: "madar://notes/letters")
        case .iftar: URL(string: "madar://prayer")
        case .travel: URL(string: "madar://prayer")
        }
    }
}
