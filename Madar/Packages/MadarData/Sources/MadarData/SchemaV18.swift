import Foundation
import SwiftData

/// Exact V18 model list, frozen before the manual exchange-rate model was added in V19 (owner, 22 Nov 2026). No existing model changed
/// shape, so the live classes are reused.
public enum MadarSchemaV18: VersionedSchema {
    public static let versionIdentifier = Schema.Version(18, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 18
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self, AccountTail.self, BankReading.self, UpcomingDue.self, MushafBookmark.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig", "AccountTail", "BankReading", "UpcomingDue", "MushafBookmark"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}
