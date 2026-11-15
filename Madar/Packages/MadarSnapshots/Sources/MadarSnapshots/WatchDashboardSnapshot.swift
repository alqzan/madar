import Foundation

/// A small, read-only companion view. It contains no money, diary, book text, or write routes.
public struct WatchDashboardSnapshot: Codable, Sendable, Equatable {
    public struct NextPrayer: Codable, Sendable, Equatable {
        public var name: String
        public var at: Date
        public init(name: String, at: Date) { self.name = name; self.at = at }
    }

    public struct Progress: Codable, Sendable, Equatable {
        public var completed: Int
        public var total: Int
        public init(completed: Int, total: Int) { self.completed = completed; self.total = total }
    }

    public var datePrimary: String
    public var dateSecondary: String
    public var numerals: String
    public var prayers: [NextPrayer]
    public var quran: Progress?
    public var habits: Progress?

    public init(datePrimary: String, dateSecondary: String, numerals: String,
                prayers: [NextPrayer], quran: Progress?, habits: Progress?) {
        self.datePrimary = datePrimary
        self.dateSecondary = dateSecondary
        self.numerals = numerals
        self.prayers = prayers.sorted { $0.at < $1.at }
        self.quran = quran
        self.habits = habits
    }

    public func digits(_ value: Int) -> String {
        guard numerals != "western" else { return String(value) }
        let map: [Character: Character] = ["0": "٠", "1": "١", "2": "٢", "3": "٣", "4": "٤", "5": "٥", "6": "٦", "7": "٧", "8": "٨", "9": "٩"]
        return String(String(value).map { map[$0] ?? $0 })
    }

    public func nextPrayer(after date: Date) -> NextPrayer? {
        prayers.first { $0.at > date }
    }
}
