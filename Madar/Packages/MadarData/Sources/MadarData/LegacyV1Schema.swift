import Foundation
import SwiftData
extension MadarSchemaV1: VersionedSchema {
    public static let versionIdentifier = Schema.Version(1, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 1
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, Transaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "Transaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}
@MainActor enum LegacyRecordBridge {
    public static func all(_ context: ModelContext, syncedOnly: Bool = true) throws -> [DataRecord] {
        var rows: [DataRecord] = []
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Setting>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.LayoutState>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Preset>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Trip>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.UpcomingDay>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.ImportBatch>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.ImportLink>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.PrayerLog>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.QadaItem>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.QiyamNight>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HifzPlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HifzSession>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.PageGrade>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.MistakeSpot>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.MistakeEvent>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.QuranDayState>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.QuranAllotment>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.RecoveryPlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.DayPage>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Niyya>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Entry>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HiddenAutoLine>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.MarginNote>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Letter>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Project>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Media>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Account>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Card>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Statement>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.CashbackEntry>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Transaction>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Allocation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Reconciliation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.BankMessage>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Cycle>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.CyclePolicy>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Envelope>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.EnvelopePlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Obligation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.InstallmentItem>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Category>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.CategoryLimit>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.MerchantRule>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.ZakatProfile>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Book>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.ReadingSession>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Highlight>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.NotebookNote>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HadithProgress>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.UserWord>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.Habit>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HabitPolicy>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HabitPause>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.HabitLog>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MadarSchemaV1.WidgetConfig>()).map { try $0.record() }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<MadarSchemaV1.DeviceSetting>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<MadarSchemaV1.NotificationLedger>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<MadarSchemaV1.CommandReceipt>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<MadarSchemaV1.PageSchedule>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<MadarSchemaV1.SessionDraft>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<MadarSchemaV1.ProcessingJob>()).map { try $0.record() } }
        return rows
    }
}
