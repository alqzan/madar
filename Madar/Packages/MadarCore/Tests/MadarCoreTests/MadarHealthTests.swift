import Foundation
import Testing
@testable import MadarCore

/// Batch 3 «صحة مدار»: the verdict counts only what the user can fix (stale or missing backup, rejected actions, notifications off).
struct MadarHealthTests {
    private let now = Date(timeIntervalSince1970: 1_792_000_000)
    private func health(backupDaysAgo: Double?, pending: Int = 0, rejected: Int = 0, notifications: Bool = true) -> MadarHealth {
        MadarHealth(lastBackup: backupDaysAgo.map { now.addingTimeInterval(-$0 * 86_400) }, now: now, pendingActions: pending, rejectedActions: rejected, notificationsAllowed: notifications)
    }
    @Test func aRecentBackupAndQuietInboxIsHealthy() {
        let value = health(backupDaysAgo: 3)
        #expect(value.backup == .fresh(days: 3))
        #expect(value.isHealthy)
    }
    @Test func theBackupGoesStaleAtFourteenDays() {
        #expect(health(backupDaysAgo: 13.9).backup == .fresh(days: 13))
        #expect(health(backupDaysAgo: 14).backup == .stale(days: 14))
        #expect(health(backupDaysAgo: 14).attentionCount == 1)
        #expect(health(backupDaysAgo: nil).backup == .never)
        #expect(health(backupDaysAgo: nil).attentionCount == 1)
    }
    @Test func pendingActionsAreNormalButRejectedOnesAndSilencedNotificationsNeedAttention() {
        #expect(health(backupDaysAgo: 1, pending: 4).isHealthy)
        #expect(health(backupDaysAgo: 1, rejected: 2).attentionCount == 1)
        #expect(health(backupDaysAgo: 1, notifications: false).attentionCount == 1)
        #expect(health(backupDaysAgo: nil, rejected: 1, notifications: false).attentionCount == 3)
    }
    @Test func aBackupFromTheFutureIsNotNegative() {
        #expect(health(backupDaysAgo: -2).backup == .fresh(days: 0))
    }
}
