import Foundation
import SwiftData

/// Frozen schema 4: the inventory before the M5-D01 money fields (RM1, RM3, RM5, RM7). The four money models it
/// changed are pinned in `MadarFrozenMoneyV4` with their V4 shape; schemas 2 and 3 use the same pinned shapes.
public enum MadarSchemaV4: VersionedSchema {
    public static let versionIdentifier = Schema.Version(4, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 4
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, MadarFrozenTripV12.Trip.self, MadarFrozenUpcomingDayV10.UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, MadarFrozenDiaryV7.Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, MadarFrozenMoneyV4.Account.self, MadarFrozenMoneyV4.Card.self, Statement.self, CashbackEntry.self, MadarFrozenMoneyV6.MoneyTransaction.self, Allocation.self, MadarFrozenReconciliationV8.Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, MadarFrozenMoneyV4.EnvelopePlan.self, MadarFrozenMoneyV6.Obligation.self, InstallmentItem.self, MadarFrozenCategoryV9.Category.self, CategoryLimit.self, MerchantRule.self, MadarFrozenMoneyV4.ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, MadarFrozenHabitPolicyV14.HabitPolicy.self, HabitPause.self, HabitLog.self, MadarFrozenHabitEventV11.HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}

/// V4 shapes of the money models that schema 5 extended. Never edit: they describe stores already on devices.
public enum MadarFrozenMoneyV4 {
    @Model public final class Account {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var name: String = ""
        public var bank: String = ""
        public var kind: String = "current"
        public var ownerName: String? = nil
        public var ownership: String = "mine"
        public var zakatInclude: Bool = true
        public var currency: String = "SAR"
        public var balanceMinor: Int = 0
        public var balanceAt: Date? = nil
        public var parentID: UUID? = nil
        public var senderIDs: [String] = []
        public init() {}
    }
    @Model public final class Card {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var name: String = ""
        public var bank: String = ""
        public var last4: String = ""
        public var aliases: [String] = []
        public var holderName: String? = nil
        public var network: String = ""
        public var limitMinor: Int? = nil
        public var cashbackBp: Int? = nil
        public var aprBp: Int? = nil
        public var accountID: UUID? = nil
        public var fieldSourcesJSON: Data = Data()
        public init() {}
    }
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
        public init() {}
    }
    @Model public final class ZakatProfile {
        public var id: UUID = UUID()
        public var createdAt: Date = Date()
        public var updatedAt: Date = Date()
        public var deletedAt: Date? = nil
        public var writerID: String = ""
        public var mergedInto: UUID? = nil
        public var deletionBarrierAt: Date? = nil
        public var restoredAt: Date? = nil
        public var hawlStartHijri: String = ""
        public var goldPricePerGramMinor: Int? = nil
        public var goldPriceSetAt: Date? = nil
        public var nisabMg: Int = 85000
        public var debtsPolicy: String = "unset"
        public var otherAssetsMinor: Int = 0
        public var lastPaidAt: Date? = nil
        public init() {}
    }
}
