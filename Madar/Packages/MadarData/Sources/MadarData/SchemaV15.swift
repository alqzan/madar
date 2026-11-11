import Foundation
import SwiftData

/// Exact V15 diary shapes, frozen before local voice insights and intention check-ins were added in V16.
public enum MadarFrozenDiaryV15 {
    @Model public final class Niyya {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var dayKey: String = ""
        public var order: Int = 0
        public var text: String = ""
        public var result: String? = nil
        public init() {}
    }

    @Model public final class Media {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var kind: String = "photo"
        public var contentType: String = ""
        @Attribute(.externalStorage) public var data: Data? = nil
        public var sizeBytes: Int = 0
        public var sha256: String = ""
        public var durationS: Int? = nil
        public var sourceID: String? = nil
        public var state: String = "ok"
        public var importBatchID: UUID? = nil
        public init() {}
    }
}

public enum MadarSchemaV15: VersionedSchema {
    public static let versionIdentifier = Schema.Version(15, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 15
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, MadarFrozenTripV17.Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, MadarFrozenDiaryV15.Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, MadarFrozenDiaryV15.Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = MadarSchema.syncedNames
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}
