import Foundation
import SwiftData

/// Frozen schema 2. The only schema-3 addition is the optional Friday noon kind.
public enum MadarSchemaV2: VersionedSchema {
    public static let versionIdentifier = Schema.Version(2, 0, 0)
    // Pin the complete v2 inventory here; later models belong only to later schemas.
    public static let syncedTypes: [any PersistentModel.Type] = [
        Setting.self, LayoutState.self, Preset.self, Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self,
        PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self,
        MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self,
        DayPage.self, Niyya.self, MadarFrozenDiaryV7.Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self,
        Media.self, MadarFrozenMoneyV4.Account.self, MadarFrozenMoneyV4.Card.self, Statement.self, CashbackEntry.self, MadarFrozenMoneyV6.MoneyTransaction.self,
        Allocation.self, MadarFrozenReconciliationV8.Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self,
        MadarFrozenMoneyV4.EnvelopePlan.self, MadarFrozenMoneyV6.Obligation.self, InstallmentItem.self, MadarFrozenCategoryV9.Category.self, CategoryLimit.self,
        MerchantRule.self, MadarFrozenMoneyV4.ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self,
        HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self,
        WidgetConfig.self
    ]
    public static let deviceTypes: [any PersistentModel.Type] = [
        DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self,
        ProcessingJob.self
    ]
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let syncedNames: [String] = [
        "Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog",
        "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent",
        "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine",
        "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry",
        "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope",
        "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile",
        "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy",
        "HabitPause", "HabitLog", "WidgetConfig"
    ]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }

    @Model public final class PrayerLog {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var dayKey: String = ""
        public var prayer: String = "fajr"
        public var status: String = "jamaah"
        public var heart: String? = nil
        public var eventAt: Date = Date()
        public var tzID: String = ""
        public var dayPolicy: String = ""
        public var loggedAt: Date? = nil
        public var source: String = "app"
        public var tripID: UUID? = nil
        public var pairID: UUID? = nil
        public var shortened: Bool? = nil
        public init() {}
    }
}
