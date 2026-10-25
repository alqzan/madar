import Foundation
import SwiftData
public enum MadarSchema: VersionedSchema {
    public static let versionIdentifier = Schema.Version(11, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 11
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}
@MainActor public enum RecordBridge {
    public static func all(_ context: ModelContext, syncedOnly: Bool = true) throws -> [DataRecord] {
        var rows: [DataRecord] = []
        rows += try context.fetch(FetchDescriptor<Setting>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<LayoutState>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Preset>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Trip>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<UpcomingDay>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ImportBatch>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ImportLink>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<PrayerLog>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QadaItem>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QiyamNight>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HifzPlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HifzSession>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<PageGrade>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MistakeSpot>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MistakeEvent>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QuranDayState>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<QuranAllotment>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<RecoveryPlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<DayPage>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Niyya>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Entry>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HiddenAutoLine>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MarginNote>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Letter>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Project>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Media>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Account>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Card>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Statement>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<CashbackEntry>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MoneyTransaction>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Allocation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Reconciliation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<BankMessage>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Cycle>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<CyclePolicy>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Envelope>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<EnvelopePlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Obligation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<InstallmentItem>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Category>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<CategoryLimit>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MerchantRule>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ZakatProfile>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Book>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ReadingSession>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Highlight>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<NotebookNote>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HadithProgress>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<UserWord>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Habit>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HabitPolicy>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HabitPause>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HabitLog>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<HabitEvent>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<WidgetConfig>()).map { try $0.record() }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<DeviceSetting>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<NotificationLedger>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<CommandReceipt>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<PageSchedule>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<SessionDraft>()).map { try $0.record() } }
        if !syncedOnly { rows += try context.fetch(FetchDescriptor<ProcessingJob>()).map { try $0.record() } }
        return rows
    }
    public static func deviceRecords(_ context: ModelContext) throws -> [DataRecord] {
        var rows: [DataRecord] = []
        rows += try context.fetch(FetchDescriptor<DeviceSetting>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<NotificationLedger>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<CommandReceipt>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<PageSchedule>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<SessionDraft>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ProcessingJob>()).map { try $0.record() }
        return rows
    }
    public static func instances(_ context: ModelContext) throws -> [any MadarRecordModel] {
        var result: [any MadarRecordModel] = []
        result += try context.fetch(FetchDescriptor<Setting>())
        result += try context.fetch(FetchDescriptor<LayoutState>())
        result += try context.fetch(FetchDescriptor<Preset>())
        result += try context.fetch(FetchDescriptor<Trip>())
        result += try context.fetch(FetchDescriptor<UpcomingDay>())
        result += try context.fetch(FetchDescriptor<ImportBatch>())
        result += try context.fetch(FetchDescriptor<ImportLink>())
        result += try context.fetch(FetchDescriptor<PrayerLog>())
        result += try context.fetch(FetchDescriptor<QadaItem>())
        result += try context.fetch(FetchDescriptor<QiyamNight>())
        result += try context.fetch(FetchDescriptor<HifzPlan>())
        result += try context.fetch(FetchDescriptor<HifzSession>())
        result += try context.fetch(FetchDescriptor<PageGrade>())
        result += try context.fetch(FetchDescriptor<MistakeSpot>())
        result += try context.fetch(FetchDescriptor<MistakeEvent>())
        result += try context.fetch(FetchDescriptor<QuranDayState>())
        result += try context.fetch(FetchDescriptor<QuranAllotment>())
        result += try context.fetch(FetchDescriptor<RecoveryPlan>())
        result += try context.fetch(FetchDescriptor<DayPage>())
        result += try context.fetch(FetchDescriptor<Niyya>())
        result += try context.fetch(FetchDescriptor<Entry>())
        result += try context.fetch(FetchDescriptor<HiddenAutoLine>())
        result += try context.fetch(FetchDescriptor<MarginNote>())
        result += try context.fetch(FetchDescriptor<Letter>())
        result += try context.fetch(FetchDescriptor<Project>())
        result += try context.fetch(FetchDescriptor<Media>())
        result += try context.fetch(FetchDescriptor<Account>())
        result += try context.fetch(FetchDescriptor<Card>())
        result += try context.fetch(FetchDescriptor<Statement>())
        result += try context.fetch(FetchDescriptor<CashbackEntry>())
        result += try context.fetch(FetchDescriptor<MoneyTransaction>())
        result += try context.fetch(FetchDescriptor<Allocation>())
        result += try context.fetch(FetchDescriptor<Reconciliation>())
        result += try context.fetch(FetchDescriptor<BankMessage>())
        result += try context.fetch(FetchDescriptor<Cycle>())
        result += try context.fetch(FetchDescriptor<CyclePolicy>())
        result += try context.fetch(FetchDescriptor<Envelope>())
        result += try context.fetch(FetchDescriptor<EnvelopePlan>())
        result += try context.fetch(FetchDescriptor<Obligation>())
        result += try context.fetch(FetchDescriptor<InstallmentItem>())
        result += try context.fetch(FetchDescriptor<Category>())
        result += try context.fetch(FetchDescriptor<CategoryLimit>())
        result += try context.fetch(FetchDescriptor<MerchantRule>())
        result += try context.fetch(FetchDescriptor<ZakatProfile>())
        result += try context.fetch(FetchDescriptor<Book>())
        result += try context.fetch(FetchDescriptor<ReadingSession>())
        result += try context.fetch(FetchDescriptor<Highlight>())
        result += try context.fetch(FetchDescriptor<NotebookNote>())
        result += try context.fetch(FetchDescriptor<HadithProgress>())
        result += try context.fetch(FetchDescriptor<UserWord>())
        result += try context.fetch(FetchDescriptor<Habit>())
        result += try context.fetch(FetchDescriptor<HabitPolicy>())
        result += try context.fetch(FetchDescriptor<HabitPause>())
        result += try context.fetch(FetchDescriptor<HabitLog>())
        result += try context.fetch(FetchDescriptor<HabitEvent>())
        result += try context.fetch(FetchDescriptor<WidgetConfig>())
        return result
    }
    public static func insert(_ record: DataRecord, in context: ModelContext) throws {
        switch record.model {
        case "Setting":
            let row = Setting(); context.insert(row); try row.apply(record)
        case "LayoutState":
            let row = LayoutState(); context.insert(row); try row.apply(record)
        case "Preset":
            let row = Preset(); context.insert(row); try row.apply(record)
        case "Trip":
            let row = Trip(); context.insert(row); try row.apply(record)
        case "UpcomingDay":
            let row = UpcomingDay(); context.insert(row); try row.apply(record)
        case "ImportBatch":
            let row = ImportBatch(); context.insert(row); try row.apply(record)
        case "ImportLink":
            let row = ImportLink(); context.insert(row); try row.apply(record)
        case "PrayerLog":
            let row = PrayerLog(); context.insert(row); try row.apply(record)
        case "QadaItem":
            let row = QadaItem(); context.insert(row); try row.apply(record)
        case "QiyamNight":
            let row = QiyamNight(); context.insert(row); try row.apply(record)
        case "HifzPlan":
            let row = HifzPlan(); context.insert(row); try row.apply(record)
        case "HifzSession":
            let row = HifzSession(); context.insert(row); try row.apply(record)
        case "PageGrade":
            let row = PageGrade(); context.insert(row); try row.apply(record)
        case "MistakeSpot":
            let row = MistakeSpot(); context.insert(row); try row.apply(record)
        case "MistakeEvent":
            let row = MistakeEvent(); context.insert(row); try row.apply(record)
        case "QuranDayState":
            let row = QuranDayState(); context.insert(row); try row.apply(record)
        case "QuranAllotment":
            let row = QuranAllotment(); context.insert(row); try row.apply(record)
        case "RecoveryPlan":
            let row = RecoveryPlan(); context.insert(row); try row.apply(record)
        case "DayPage":
            let row = DayPage(); context.insert(row); try row.apply(record)
        case "Niyya":
            let row = Niyya(); context.insert(row); try row.apply(record)
        case "Entry":
            let row = Entry(); context.insert(row); try row.apply(record)
        case "HiddenAutoLine":
            let row = HiddenAutoLine(); context.insert(row); try row.apply(record)
        case "MarginNote":
            let row = MarginNote(); context.insert(row); try row.apply(record)
        case "Letter":
            let row = Letter(); context.insert(row); try row.apply(record)
        case "Project":
            let row = Project(); context.insert(row); try row.apply(record)
        case "Media":
            let row = Media(); context.insert(row); try row.apply(record)
        case "Account":
            let row = Account(); context.insert(row); try row.apply(record)
        case "Card":
            let row = Card(); context.insert(row); try row.apply(record)
        case "Statement":
            let row = Statement(); context.insert(row); try row.apply(record)
        case "CashbackEntry":
            let row = CashbackEntry(); context.insert(row); try row.apply(record)
        case "MoneyTransaction":
            let row = MoneyTransaction(); context.insert(row); try row.apply(record)
        case "Allocation":
            let row = Allocation(); context.insert(row); try row.apply(record)
        case "Reconciliation":
            let row = Reconciliation(); context.insert(row); try row.apply(record)
        case "BankMessage":
            let row = BankMessage(); context.insert(row); try row.apply(record)
        case "Cycle":
            let row = Cycle(); context.insert(row); try row.apply(record)
        case "CyclePolicy":
            let row = CyclePolicy(); context.insert(row); try row.apply(record)
        case "Envelope":
            let row = Envelope(); context.insert(row); try row.apply(record)
        case "EnvelopePlan":
            let row = EnvelopePlan(); context.insert(row); try row.apply(record)
        case "Obligation":
            let row = Obligation(); context.insert(row); try row.apply(record)
        case "InstallmentItem":
            let row = InstallmentItem(); context.insert(row); try row.apply(record)
        case "Category":
            let row = Category(); context.insert(row); try row.apply(record)
        case "CategoryLimit":
            let row = CategoryLimit(); context.insert(row); try row.apply(record)
        case "MerchantRule":
            let row = MerchantRule(); context.insert(row); try row.apply(record)
        case "ZakatProfile":
            let row = ZakatProfile(); context.insert(row); try row.apply(record)
        case "Book":
            let row = Book(); context.insert(row); try row.apply(record)
        case "ReadingSession":
            let row = ReadingSession(); context.insert(row); try row.apply(record)
        case "Highlight":
            let row = Highlight(); context.insert(row); try row.apply(record)
        case "NotebookNote":
            let row = NotebookNote(); context.insert(row); try row.apply(record)
        case "HadithProgress":
            let row = HadithProgress(); context.insert(row); try row.apply(record)
        case "UserWord":
            let row = UserWord(); context.insert(row); try row.apply(record)
        case "Habit":
            let row = Habit(); context.insert(row); try row.apply(record)
        case "HabitPolicy":
            let row = HabitPolicy(); context.insert(row); try row.apply(record)
        case "HabitPause":
            let row = HabitPause(); context.insert(row); try row.apply(record)
        case "HabitLog":
            let row = HabitLog(); context.insert(row); try row.apply(record)
        case "HabitEvent":
            let row = HabitEvent(); context.insert(row); try row.apply(record)
        case "WidgetConfig":
            let row = WidgetConfig(); context.insert(row); try row.apply(record)
        case "DeviceSetting":
            let row = DeviceSetting(); context.insert(row); try row.apply(record)
        case "NotificationLedger":
            let row = NotificationLedger(); context.insert(row); try row.apply(record)
        case "CommandReceipt":
            let row = CommandReceipt(); context.insert(row); try row.apply(record)
        case "PageSchedule":
            let row = PageSchedule(); context.insert(row); try row.apply(record)
        case "SessionDraft":
            let row = SessionDraft(); context.insert(row); try row.apply(record)
        case "ProcessingJob":
            let row = ProcessingJob(); context.insert(row); try row.apply(record)
        default: throw DataError.unknownModel(record.model)
        }
    }
    public static func upsert(_ record: DataRecord, in context: ModelContext) throws {
        switch record.model {
        case "Setting":
            let rows = try context.fetch(FetchDescriptor<Setting>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Setting()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "LayoutState":
            let rows = try context.fetch(FetchDescriptor<LayoutState>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? LayoutState()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Preset":
            let rows = try context.fetch(FetchDescriptor<Preset>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Preset()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Trip":
            let rows = try context.fetch(FetchDescriptor<Trip>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Trip()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "UpcomingDay":
            let rows = try context.fetch(FetchDescriptor<UpcomingDay>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? UpcomingDay()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "ImportBatch":
            let rows = try context.fetch(FetchDescriptor<ImportBatch>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? ImportBatch()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "ImportLink":
            let rows = try context.fetch(FetchDescriptor<ImportLink>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? ImportLink()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "PrayerLog":
            let rows = try context.fetch(FetchDescriptor<PrayerLog>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? PrayerLog()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "QadaItem":
            let rows = try context.fetch(FetchDescriptor<QadaItem>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? QadaItem()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "QiyamNight":
            let rows = try context.fetch(FetchDescriptor<QiyamNight>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? QiyamNight()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HifzPlan":
            let rows = try context.fetch(FetchDescriptor<HifzPlan>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HifzPlan()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HifzSession":
            let rows = try context.fetch(FetchDescriptor<HifzSession>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HifzSession()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "PageGrade":
            let rows = try context.fetch(FetchDescriptor<PageGrade>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? PageGrade()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "MistakeSpot":
            let rows = try context.fetch(FetchDescriptor<MistakeSpot>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? MistakeSpot()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "MistakeEvent":
            let rows = try context.fetch(FetchDescriptor<MistakeEvent>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? MistakeEvent()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "QuranDayState":
            let rows = try context.fetch(FetchDescriptor<QuranDayState>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? QuranDayState()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "QuranAllotment":
            let rows = try context.fetch(FetchDescriptor<QuranAllotment>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? QuranAllotment()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "RecoveryPlan":
            let rows = try context.fetch(FetchDescriptor<RecoveryPlan>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? RecoveryPlan()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "DayPage":
            let rows = try context.fetch(FetchDescriptor<DayPage>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? DayPage()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Niyya":
            let rows = try context.fetch(FetchDescriptor<Niyya>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Niyya()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Entry":
            let rows = try context.fetch(FetchDescriptor<Entry>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Entry()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HiddenAutoLine":
            let rows = try context.fetch(FetchDescriptor<HiddenAutoLine>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HiddenAutoLine()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "MarginNote":
            let rows = try context.fetch(FetchDescriptor<MarginNote>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? MarginNote()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Letter":
            let rows = try context.fetch(FetchDescriptor<Letter>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Letter()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Project":
            let rows = try context.fetch(FetchDescriptor<Project>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Project()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Media":
            let rows = try context.fetch(FetchDescriptor<Media>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Media()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Account":
            let rows = try context.fetch(FetchDescriptor<Account>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Account()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Card":
            let rows = try context.fetch(FetchDescriptor<Card>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Card()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Statement":
            let rows = try context.fetch(FetchDescriptor<Statement>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Statement()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "CashbackEntry":
            let rows = try context.fetch(FetchDescriptor<CashbackEntry>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? CashbackEntry()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "MoneyTransaction":
            let rows = try context.fetch(FetchDescriptor<MoneyTransaction>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? MoneyTransaction()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Allocation":
            let rows = try context.fetch(FetchDescriptor<Allocation>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Allocation()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Reconciliation":
            let rows = try context.fetch(FetchDescriptor<Reconciliation>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Reconciliation()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "BankMessage":
            let rows = try context.fetch(FetchDescriptor<BankMessage>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? BankMessage()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Cycle":
            let rows = try context.fetch(FetchDescriptor<Cycle>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Cycle()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "CyclePolicy":
            let rows = try context.fetch(FetchDescriptor<CyclePolicy>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? CyclePolicy()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Envelope":
            let rows = try context.fetch(FetchDescriptor<Envelope>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Envelope()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "EnvelopePlan":
            let rows = try context.fetch(FetchDescriptor<EnvelopePlan>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? EnvelopePlan()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Obligation":
            let rows = try context.fetch(FetchDescriptor<Obligation>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Obligation()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "InstallmentItem":
            let rows = try context.fetch(FetchDescriptor<InstallmentItem>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? InstallmentItem()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Category":
            let rows = try context.fetch(FetchDescriptor<Category>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Category()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "CategoryLimit":
            let rows = try context.fetch(FetchDescriptor<CategoryLimit>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? CategoryLimit()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "MerchantRule":
            let rows = try context.fetch(FetchDescriptor<MerchantRule>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? MerchantRule()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "ZakatProfile":
            let rows = try context.fetch(FetchDescriptor<ZakatProfile>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? ZakatProfile()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Book":
            let rows = try context.fetch(FetchDescriptor<Book>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Book()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "ReadingSession":
            let rows = try context.fetch(FetchDescriptor<ReadingSession>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? ReadingSession()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Highlight":
            let rows = try context.fetch(FetchDescriptor<Highlight>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Highlight()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "NotebookNote":
            let rows = try context.fetch(FetchDescriptor<NotebookNote>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? NotebookNote()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HadithProgress":
            let rows = try context.fetch(FetchDescriptor<HadithProgress>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HadithProgress()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "UserWord":
            let rows = try context.fetch(FetchDescriptor<UserWord>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? UserWord()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "Habit":
            let rows = try context.fetch(FetchDescriptor<Habit>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? Habit()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HabitPolicy":
            let rows = try context.fetch(FetchDescriptor<HabitPolicy>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HabitPolicy()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HabitPause":
            let rows = try context.fetch(FetchDescriptor<HabitPause>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HabitPause()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HabitLog":
            let rows = try context.fetch(FetchDescriptor<HabitLog>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HabitLog()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "HabitEvent":
            let rows = try context.fetch(FetchDescriptor<HabitEvent>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? HabitEvent()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "WidgetConfig":
            let rows = try context.fetch(FetchDescriptor<WidgetConfig>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? WidgetConfig()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "DeviceSetting":
            let rows = try context.fetch(FetchDescriptor<DeviceSetting>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? DeviceSetting()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "NotificationLedger":
            let rows = try context.fetch(FetchDescriptor<NotificationLedger>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? NotificationLedger()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "CommandReceipt":
            let rows = try context.fetch(FetchDescriptor<CommandReceipt>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? CommandReceipt()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "PageSchedule":
            let rows = try context.fetch(FetchDescriptor<PageSchedule>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? PageSchedule()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "SessionDraft":
            let rows = try context.fetch(FetchDescriptor<SessionDraft>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? SessionDraft()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        case "ProcessingJob":
            let rows = try context.fetch(FetchDescriptor<ProcessingJob>())
            let row = rows.first { $0.id == record.id && $0.mergedInto?.uuidString == record.fields["mergedInto"]?.string } ?? ProcessingJob()
            if row.modelContext == nil { context.insert(row) }
            try row.apply(record)
        default: throw DataError.unknownModel(record.model)
        }
    }
}
