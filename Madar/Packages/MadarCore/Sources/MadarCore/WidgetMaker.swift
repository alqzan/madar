import Foundation

/// X3's stored style uses the existing WidgetConfig.styleJSON. WidgetKit still chooses the actual family.
public struct WidgetMakerStyle: Codable, Equatable, Hashable, Sendable {
    public var family = "manuscript"
    public var font = "naskh"
    public var numerals = "hindi"
    public var density = "regular"
    public var color = "gold"
    public var showArt = true
    public var smartBundle = true
    public var hideWhenEmpty = false
    public var hideMoney = true
    public var iftarCountdown = true
    public var interactive = true
    /// Preview surface and placement in the lobby; this never installs or resizes a system widget.
    public var surface = "home"
    public init() {}
    public var isValid: Bool {
        ["manuscript", "glass", "ink"].contains(family) && ["naskh", "modern"].contains(font)
        && ["hindi", "western"].contains(numerals) && ["compact", "regular", "airy"].contains(density)
        && ["gold", "green", "blue", "clay", "plum", "sepia", "ink"].contains(color)
        && ["home", "lock", "lobby", "standby"].contains(surface)
    }
    public static func capacity(for family: String) -> Int {
        switch family { case "small": 2; case "medium": 3; case "large": 5; case "extraLargePortrait": 7; case "accessoryRectangular": 2; default: 1 }
    }
    public static let familyIDs = ["small", "medium", "large", "extraLargePortrait", "accessoryCircular", "accessoryRectangular", "accessoryInline"]
    public static let itemIDs = ["prayerNext", "habitsToday", "moneyNow", "ramadan", "year", "upcoming", "quranCoverage", "quranReview", "book", "hadith", "diaryLine", "hijriClock"]
    public static func validItem(_ value: String) -> Bool {
        if itemIDs.contains(value) { return true }
        let parts = value.split(separator: ":", omittingEmptySubsequences: false)
        return parts.count == 2 && ["habit", "day"].contains(String(parts[0])) && UUID(uuidString: String(parts[1])) != nil
    }
}
