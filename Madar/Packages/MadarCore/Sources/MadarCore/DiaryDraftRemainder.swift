import Foundation

/// What is left in the diary field after a send (T02): the field is cleared of what was sent,
/// never of words typed while the send was in flight.
public enum DiaryDraftRemainder {
    public static func remaining(current: String, sent: String) -> String {
        if current == sent { return "" }
        if !sent.isEmpty, current.hasPrefix(sent) {
            return String(current.dropFirst(sent.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return current
    }
}
