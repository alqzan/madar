import Foundation
import SwiftData

/// Frozen schema 6: the inventory before the M5-X00 flexible schedules (owner, 16 Oct). Only Obligation and
/// MoneyTransaction changed; they are pinned in `MadarFrozenMoneyV6` with their V6 shape, which schemas 2–5 share.
public enum MadarSchemaV6: VersionedSchema {
    public static let versionIdentifier = Schema.Version(6, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 6
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, MadarFrozenTripV12.Trip.self, MadarFrozenUpcomingDayV10.UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, MadarFrozenDiaryV7.Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MadarFrozenMoneyV6.MoneyTransaction.self, Allocation.self, MadarFrozenReconciliationV8.Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, MadarFrozenMoneyV6.Obligation.self, InstallmentItem.self, MadarFrozenCategoryV9.Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, MadarFrozenHabitEventV11.HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}

/// V2–V6 shapes of MoneyTransaction and Obligation, before schema 7 added the stamp's reason and the free interval and
/// first due day. Never edit.
public enum MadarFrozenMoneyV6 {
    @Model public final class MoneyTransaction {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var dayKey: String = ""
        public var eventAt: Date = Date()
        public var tzID: String = ""
        public var dayPolicy: String = ""
        public var kind: String = "expense"
        public var amountMinor: Int = 0
        public var currency: String = "SAR"
        public var homeAmountMinor: Int = 0
        public var homeCurrency: String = "SAR"
        public var rateAtTime: String? = nil
        public var rateSource: String? = nil
        public var merchant: String? = nil
        public var counterparty: String? = nil
        public var categoryID: UUID? = nil
        public var method: String = "cash"
        public var fromAccountID: UUID? = nil
        public var toAccountID: UUID? = nil
        public var cardID: UUID? = nil
        public var relatedTransactionID: UUID? = nil
        public var obligationID: UUID? = nil
        public var installmentID: UUID? = nil
        public var cycleID: UUID? = nil
        public var ignoredFromBudget: Bool = false
        public var source: String = "bank"
        public var messageID: UUID? = nil
        public var tripID: UUID? = nil
        public var showInDiary: Bool = true
        public var reviewState: String = "ok"
        public init() {}
    }
    @Model public final class Obligation {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var kind: String = "bill"
        public var name: String = ""
        public var provider: String? = nil
        public var amountMinor: Int = 0
        public var totalMinor: Int = 0
        public var currency: String = "SAR"
        public var dueDay: Int? = nil
        public var remainingCount: Int? = nil
        public var purchaseTransactionID: UUID? = nil
        public var sourceMessageID: UUID? = nil
        public init() {}
    }
}
