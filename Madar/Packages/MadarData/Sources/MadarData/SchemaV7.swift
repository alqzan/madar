import Foundation
import SwiftData

/// V7 is pinned before `Entry.tags` was added. Never edit this version or its diary entity.
public enum MadarSchemaV7: VersionedSchema {
    public static let versionIdentifier = Schema.Version(7, 0, 0)
    public static var models: [any PersistentModel.Type] { syncedTypes + deviceTypes }
    public static let version = 7
    public static let syncedTypes: [any PersistentModel.Type] = [Setting.self, LayoutState.self, Preset.self, Trip.self, UpcomingDay.self, ImportBatch.self, ImportLink.self, PrayerLog.self, QadaItem.self, QiyamNight.self, HifzPlan.self, HifzSession.self, PageGrade.self, MistakeSpot.self, MistakeEvent.self, QuranDayState.self, QuranAllotment.self, RecoveryPlan.self, DayPage.self, Niyya.self, MadarFrozenDiaryV7.Entry.self, HiddenAutoLine.self, MarginNote.self, Letter.self, Project.self, Media.self, Account.self, Card.self, Statement.self, CashbackEntry.self, MoneyTransaction.self, Allocation.self, Reconciliation.self, BankMessage.self, Cycle.self, CyclePolicy.self, Envelope.self, EnvelopePlan.self, Obligation.self, InstallmentItem.self, Category.self, CategoryLimit.self, MerchantRule.self, ZakatProfile.self, Book.self, ReadingSession.self, Highlight.self, NotebookNote.self, HadithProgress.self, UserWord.self, Habit.self, HabitPolicy.self, HabitPause.self, HabitLog.self, HabitEvent.self, WidgetConfig.self]
    public static let deviceTypes: [any PersistentModel.Type] = [DeviceSetting.self, NotificationLedger.self, CommandReceipt.self, PageSchedule.self, SessionDraft.self, ProcessingJob.self]
    public static let syncedNames: [String] = ["Setting", "LayoutState", "Preset", "Trip", "UpcomingDay", "ImportBatch", "ImportLink", "PrayerLog", "QadaItem", "QiyamNight", "HifzPlan", "HifzSession", "PageGrade", "MistakeSpot", "MistakeEvent", "QuranDayState", "QuranAllotment", "RecoveryPlan", "DayPage", "Niyya", "Entry", "HiddenAutoLine", "MarginNote", "Letter", "Project", "Media", "Account", "Card", "Statement", "CashbackEntry", "MoneyTransaction", "Allocation", "Reconciliation", "BankMessage", "Cycle", "CyclePolicy", "Envelope", "EnvelopePlan", "Obligation", "InstallmentItem", "Category", "CategoryLimit", "MerchantRule", "ZakatProfile", "Book", "ReadingSession", "Highlight", "NotebookNote", "HadithProgress", "UserWord", "Habit", "HabitPolicy", "HabitPause", "HabitLog", "HabitEvent", "WidgetConfig"]
    public static var schema: Schema { Schema(versionedSchema: Self.self) }
}

/// V2–V7 Entry shape, frozen for lightweight migration and old undo/backup records.
public enum MadarFrozenDiaryV7 {
    @Model public final class Entry {
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
        public var text: String = ""
        public var textFormat: String = "plain"
        public var ink: String = "normal"
        public var mediaID: UUID? = nil
        public var attachmentMediaIDs: [UUID] = []
        public var projectID: UUID? = nil
        public var place: String? = nil
        public var lat: Double? = nil
        public var lon: Double? = nil
        public var source: String = "native"
        public var sourceID: String? = nil
        public var sourceJournal: String? = nil
        public var sourceTimeZone: String? = nil
        public var sourceModifiedAt: Date? = nil
        public var sourceHash: String? = nil
        public var importBatchID: UUID? = nil
        public var pinnedEventKind: String? = nil
        public var pinnedEventID: UUID? = nil
        public var sourceBranch: String = ""
        public init() {}
    }
}

extension MadarFrozenDiaryV7.Entry: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Entry", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "eventAt": JSONValue.encode(eventAt),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
            "text": JSONValue.encode(text),
            "textFormat": JSONValue.encode(textFormat),
            "ink": JSONValue.encode(ink),
            "mediaID": JSONValue.encode(mediaID),
            "attachmentMediaIDs": JSONValue.encode(attachmentMediaIDs),
            "projectID": JSONValue.encode(projectID),
            "place": JSONValue.encode(place),
            "lat": JSONValue.encode(lat),
            "lon": JSONValue.encode(lon),
            "source": JSONValue.encode(source),
            "sourceID": JSONValue.encode(sourceID),
            "sourceJournal": JSONValue.encode(sourceJournal),
            "sourceTimeZone": JSONValue.encode(sourceTimeZone),
            "sourceModifiedAt": JSONValue.encode(sourceModifiedAt),
            "sourceHash": JSONValue.encode(sourceHash),
            "importBatchID": JSONValue.encode(importBatchID),
            "pinnedEventKind": JSONValue.encode(pinnedEventKind),
            "pinnedEventID": JSONValue.encode(pinnedEventID),
            "sourceBranch": JSONValue.encode(sourceBranch),
        ])
    }
    public func apply(_ record: DataRecord) throws {
        id = try record.decode("id", as: UUID.self)
        createdAt = try record.decode("createdAt", as: Date.self)
        updatedAt = try record.decode("updatedAt", as: Date.self)
        deletedAt = try record.decode("deletedAt", as: Date?.self)
        writerID = try record.decode("writerID", as: String.self)
        mergedInto = try record.decode("mergedInto", as: UUID?.self)
        deletionBarrierAt = try record.decode("deletionBarrierAt", as: Date?.self)
        restoredAt = try record.decode("restoredAt", as: Date?.self)
        dayKey = try record.decode("dayKey", as: String.self)
        eventAt = try record.decode("eventAt", as: Date.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
        text = try record.decode("text", as: String.self)
        textFormat = try record.decode("textFormat", as: String.self)
        ink = try record.decode("ink", as: String.self)
        mediaID = try record.decode("mediaID", as: UUID?.self)
        attachmentMediaIDs = try record.decode("attachmentMediaIDs", as: [UUID].self)
        projectID = try record.decode("projectID", as: UUID?.self)
        place = try record.decode("place", as: String?.self)
        lat = try record.decode("lat", as: Double?.self)
        lon = try record.decode("lon", as: Double?.self)
        source = try record.decode("source", as: String.self)
        sourceID = try record.decode("sourceID", as: String?.self)
        sourceJournal = try record.decode("sourceJournal", as: String?.self)
        sourceTimeZone = try record.decode("sourceTimeZone", as: String?.self)
        sourceModifiedAt = try record.decode("sourceModifiedAt", as: Date?.self)
        sourceHash = try record.decode("sourceHash", as: String?.self)
        importBatchID = try record.decode("importBatchID", as: UUID?.self)
        pinnedEventKind = try record.decode("pinnedEventKind", as: String?.self)
        pinnedEventID = try record.decode("pinnedEventID", as: UUID?.self)
        sourceBranch = try record.decode("sourceBranch", as: String.self)
    }
}
