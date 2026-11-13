import Foundation

/// A compact elapsed-time display for diary recordings.
public enum DiaryDurationFormat {
    public static func elapsed(_ totalSeconds: Int, digits: MadarNumberFormatter = .init()) -> String {
        let value = max(0, totalSeconds)
        if value < 60 {
            return value == 2 ? "ثانيتان" : digits.string(value) + (value == 1 ? " ثانية" : value >= 3 && value <= 10 ? " ثوانٍ" : " ثانية")
        }
        let seconds = twoDigits(value % 60, digits: digits)
        let totalMinutes = value / 60
        if totalMinutes < 60 { return digits.string(totalMinutes) + ":" + seconds }
        return digits.string(totalMinutes / 60) + ":" + twoDigits(totalMinutes % 60, digits: digits) + ":" + seconds
    }

    public static func totalSeconds(_ totalSeconds: Int, digits: MadarNumberFormatter = .init()) -> String {
        let value = max(0, totalSeconds)
        let unit = value >= 3 && value <= 10 ? " ثوانٍ" : " ثانية"
        return digits.string(value) + unit
    }

    private static func twoDigits(_ value: Int, digits: MadarNumberFormatter) -> String {
        let formatted = digits.string(value)
        return value < 10 ? digits.string(0) + formatted : formatted
    }
}
