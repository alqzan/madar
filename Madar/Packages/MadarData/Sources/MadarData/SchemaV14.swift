import Foundation
import SwiftData

/// Exact V14 habit policy shape, frozen before optional intervalDays was added in V15 (FB-39, owner 6 Nov: «كل ٣ أيام»).
public enum MadarFrozenHabitPolicyV14 {
    @Model public final class HabitPolicy {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var habitID: UUID? = nil
        public var effectiveFrom: String = ""
        public var frequency: String = "daily"
        public var weekdays: [String]? = nil
        public var monthDays: [Int]? = nil
        public var monthCalendar: String? = nil
        public var yearMonth: Int? = nil
        public var yearDay: Int? = nil
        public var measure: String = "once"
        public var unit: String? = nil
        public var target: Int? = nil
        public var minimum: Int? = nil
        public var restWeekdays: [String]? = nil
        public var windowAnchor: String? = nil
        public var windowStartMin: Int? = nil
        public var windowEndMin: Int? = nil
        public init() {}
    }
}

public enum MadarSchemaV14: VersionedSchema {
    public static let versionIdentifier = Schema.Version(14, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 14
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, MadarFrozenTripV17.Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, MadarFrozenHabitPolicyV14.HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}
