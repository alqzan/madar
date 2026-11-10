import Foundation

/// Batch 3 «صحة مدار»: one read-only verdict over facts other rooms and services already own. Nothing here writes or counts anything new.
public struct MadarHealth: Equatable, Sendable {
    public enum Backup: Equatable, Sendable { case never, fresh(days: Int), stale(days: Int) }
    /// A backup older than this is called stale (the default schedule is weekly, so two weeks means two missed copies).
    public static let staleAfterDays = 14

    public let backup: Backup
    public let pendingActions: Int
    public let rejectedActions: Int
    public let notificationsAllowed: Bool

    public init(lastBackup: Date?, now: Date, pendingActions: Int, rejectedActions: Int, notificationsAllowed: Bool) {
        if let lastBackup {
            let days = max(0, Int(now.timeIntervalSince(lastBackup) / 86_400))
            backup = days >= Self.staleAfterDays ? .stale(days: days) : .fresh(days: days)
        } else { backup = .never }
        self.pendingActions = max(0, pendingActions); self.rejectedActions = max(0, rejectedActions)
        self.notificationsAllowed = notificationsAllowed
    }

    /// Things the user can act on. Pending widget actions are normal and drain by themselves, so they never count.
    public var attentionCount: Int {
        var count = 0
        if case .fresh = backup {} else { count += 1 }
        if rejectedActions > 0 { count += 1 }
        if !notificationsAllowed { count += 1 }
        return count
    }
    public var isHealthy: Bool { attentionCount == 0 }
}
