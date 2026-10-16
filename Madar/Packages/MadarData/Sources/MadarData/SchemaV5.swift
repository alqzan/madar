import Foundation
import SwiftData

/// Frozen schema 5: the inventory before the M5-V04 repayment fields (owner, 16 Oct). Only EnvelopePlan changed; it is
/// pinned in `MadarFrozenMoneyV5` with its V5 shape. Schemas 2–4 keep `MadarFrozenMoneyV4`.
public enum MadarSchemaV5: VersionedSchema {
    public static let versionIdentifier = Schema.Version(5, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 5
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, MadarFrozenMoneyV5.EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}

/// V5 shape of EnvelopePlan, before schema 6 added the repayment total and salary count. Never edit.
public enum MadarFrozenMoneyV5 {
    @Model public final class EnvelopePlan {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var envelopeID: UUID? = nil
        public var kind: String = "fund"
        public var source: String = "salary"
        public var perPaycheckMinor: Int = 0
        public var untilDate: Date? = nil
        public var period: String = "perCycle"
        public var startDayKey: String? = nil
        public init() {}
    }
}
