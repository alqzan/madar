import Foundation

public struct QuranWidgetSnapshot: Codable, Sendable, Equatable {
    public struct Day: Codable, Sendable, Equatable {
        public var label: String
        public var hifz: Double
        public var review: Double
        public init(label: String, hifz: Double, review: Double) { self.label = label; self.hifz = hifz; self.review = review }
    }
    public var coverage: String
    public var fraction: Double
    public var nextTitle: String
    public var nextDetail: String
    public var route: String
    public var done: Int
    public var total: Int
    public var hifzToday: String
    public var reviewToday: String
    public var hifzWeek: String
    public var reviewWeek: String
    public var days: [Day]
    public init(coverage: String, fraction: Double, nextTitle: String, nextDetail: String, route: String, done: Int, total: Int, hifzToday: String, reviewToday: String, hifzWeek: String, reviewWeek: String, days: [Day]) {
        self.coverage = coverage; self.fraction = fraction; self.nextTitle = nextTitle; self.nextDetail = nextDetail; self.route = route; self.done = done; self.total = total
        self.hifzToday = hifzToday; self.reviewToday = reviewToday; self.hifzWeek = hifzWeek; self.reviewWeek = reviewWeek; self.days = days
    }
}
