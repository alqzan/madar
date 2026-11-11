import Foundation
import SwiftData

/// Exact V17 trip shape, frozen before `Trip.dismissedAt` (D7) and the named Mushaf bookmarks (D8) were added in V18 (owner, 11 Nov 2026).
public enum MadarFrozenTripV17 {
    @Model public final class Trip {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var city: String = ""
        public var country: String = ""
        public var currency: String? = nil
        public var lat: Double = 0.0
        public var lon: Double = 0.0
        public var tzID: String = ""
        public var fxRateToHome: String? = nil
        public var fxSetAt: Date? = nil
        public var mode: String = "auto"
        public var dismissed: Bool = false
        public var start: Date? = nil
        public var end: Date? = nil
        public var homeKm: Double? = nil
        public var journeyID: UUID? = nil
        public init() {}
    }
}

public enum MadarSchemaV17: VersionedSchema {
    public static let versionIdentifier = Schema.Version(17, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 17
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, MadarFrozenTripV17.Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self, AccountTail.self, BankReading.self, UpcomingDue.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig", "AccountTail", "BankReading", "UpcomingDue"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}
