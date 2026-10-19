import Foundation
import SwiftData
// Generated from Specification/data-dictionary.json (schema V9). UUID foreign keys intentionally avoid ownership relationships.
@MainActor public protocol MadarRecordModel: PersistentModel { var id: UUID { get set }; func record() throws -> DataRecord; func apply(_ record: DataRecord) throws }
@Model public final class Setting {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var key: String = ""
    public var valueJSON: Data = Data()
    public init() {}
}
extension Setting: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Setting", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "key": JSONValue.encode(key),
            "valueJSON": JSONValue.encode(valueJSON),
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
        key = try record.decode("key", as: String.self)
        valueJSON = try record.decode("valueJSON", as: Data.self)
    }
}
@Model public final class LayoutState {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var room: String = ""
    public var blocksJSON: Data = Data()
    public init() {}
}
extension LayoutState: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "LayoutState", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "room": JSONValue.encode(room),
            "blocksJSON": JSONValue.encode(blocksJSON),
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
        room = try record.decode("room", as: String.self)
        blocksJSON = try record.decode("blocksJSON", as: Data.self)
    }
}
@Model public final class Preset {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var name: String = ""
    public var payloadJSON: Data = Data()
    public var locked: Bool = false
    public init() {}
}
extension Preset: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Preset", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "payloadJSON": JSONValue.encode(payloadJSON),
            "locked": JSONValue.encode(locked),
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
        name = try record.decode("name", as: String.self)
        payloadJSON = try record.decode("payloadJSON", as: Data.self)
        locked = try record.decode("locked", as: Bool.self)
    }
}
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
    public init() {}
}
extension Trip: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Trip", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "city": JSONValue.encode(city),
            "country": JSONValue.encode(country),
            "currency": JSONValue.encode(currency),
            "lat": JSONValue.encode(lat),
            "lon": JSONValue.encode(lon),
            "tzID": JSONValue.encode(tzID),
            "fxRateToHome": JSONValue.encode(fxRateToHome),
            "fxSetAt": JSONValue.encode(fxSetAt),
            "mode": JSONValue.encode(mode),
            "dismissed": JSONValue.encode(dismissed),
            "start": JSONValue.encode(start),
            "end": JSONValue.encode(end),
            "homeKm": JSONValue.encode(homeKm),
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
        city = try record.decode("city", as: String.self)
        country = try record.decode("country", as: String.self)
        currency = try record.decode("currency", as: String?.self)
        lat = try record.decode("lat", as: Double.self)
        lon = try record.decode("lon", as: Double.self)
        tzID = try record.decode("tzID", as: String.self)
        fxRateToHome = try record.decode("fxRateToHome", as: String?.self)
        fxSetAt = try record.decode("fxSetAt", as: Date?.self)
        mode = try record.decode("mode", as: String.self)
        dismissed = try record.decode("dismissed", as: Bool.self)
        start = try record.decode("start", as: Date?.self)
        end = try record.decode("end", as: Date?.self)
        homeKm = try record.decode("homeKm", as: Double?.self)
    }
}
@Model public final class UpcomingDay {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var title: String = ""
    public var calendar: String = "hijri"
    public var year: Int? = nil
    public var month: Int = 1
    public var day: Int = 1
    public var repeats: String = "none"
    public var countFromDayKey: String = ""
    public init() {}
}
extension UpcomingDay: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "UpcomingDay", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "title": JSONValue.encode(title),
            "calendar": JSONValue.encode(calendar),
            "year": JSONValue.encode(year),
            "month": JSONValue.encode(month),
            "day": JSONValue.encode(day),
            "repeats": JSONValue.encode(repeats),
            "countFromDayKey": JSONValue.encode(countFromDayKey),
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
        title = try record.decode("title", as: String.self)
        calendar = try record.decode("calendar", as: String.self)
        year = try record.decode("year", as: Int?.self)
        month = try record.decode("month", as: Int.self)
        day = try record.decode("day", as: Int.self)
        repeats = try record.decode("repeats", as: String.self)
        countFromDayKey = try record.decode("countFromDayKey", as: String.self)
    }
}
@Model public final class ImportBatch {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var kind: String = "dayOne"
    public var fileName: String = ""
    public var fileHash: String = ""
    public var startedAt: Date = Date()
    public var finishedAt: Date? = nil
    public var status: String = "running"
    public var summaryJSON: Data = Data()
    public var optionsJSON: Data = Data()
    public init() {}
}
extension ImportBatch: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "ImportBatch", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "kind": JSONValue.encode(kind),
            "fileName": JSONValue.encode(fileName),
            "fileHash": JSONValue.encode(fileHash),
            "startedAt": JSONValue.encode(startedAt),
            "finishedAt": JSONValue.encode(finishedAt),
            "status": JSONValue.encode(status),
            "summaryJSON": JSONValue.encode(summaryJSON),
            "optionsJSON": JSONValue.encode(optionsJSON),
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
        kind = try record.decode("kind", as: String.self)
        fileName = try record.decode("fileName", as: String.self)
        fileHash = try record.decode("fileHash", as: String.self)
        startedAt = try record.decode("startedAt", as: Date.self)
        finishedAt = try record.decode("finishedAt", as: Date?.self)
        status = try record.decode("status", as: String.self)
        summaryJSON = try record.decode("summaryJSON", as: Data.self)
        optionsJSON = try record.decode("optionsJSON", as: Data.self)
    }
}
@Model public final class ImportLink {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var source: String = "myDream"
    public var sourceModel: String = ""
    public var sourceID: String = ""
    public var targetModel: String = ""
    public var targetID: UUID? = nil
    public var importBatchID: UUID? = nil
    public var unmappedJSON: Data? = nil
    public var importedAt: Date = Date()
    public init() {}
}
extension ImportLink: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "ImportLink", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "source": JSONValue.encode(source),
            "sourceModel": JSONValue.encode(sourceModel),
            "sourceID": JSONValue.encode(sourceID),
            "targetModel": JSONValue.encode(targetModel),
            "targetID": JSONValue.encode(targetID),
            "importBatchID": JSONValue.encode(importBatchID),
            "unmappedJSON": JSONValue.encode(unmappedJSON),
            "importedAt": JSONValue.encode(importedAt),
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
        source = try record.decode("source", as: String.self)
        sourceModel = try record.decode("sourceModel", as: String.self)
        sourceID = try record.decode("sourceID", as: String.self)
        targetModel = try record.decode("targetModel", as: String.self)
        targetID = try record.decode("targetID", as: UUID?.self)
        importBatchID = try record.decode("importBatchID", as: UUID?.self)
        unmappedJSON = try record.decode("unmappedJSON", as: Data?.self)
        importedAt = try record.decode("importedAt", as: Date.self)
    }
}
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
    public var fridayKind: String? = nil
    public init() {}
}
extension PrayerLog: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "PrayerLog", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "prayer": JSONValue.encode(prayer),
            "status": JSONValue.encode(status),
            "heart": JSONValue.encode(heart),
            "eventAt": JSONValue.encode(eventAt),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
            "loggedAt": JSONValue.encode(loggedAt),
            "source": JSONValue.encode(source),
            "tripID": JSONValue.encode(tripID),
            "pairID": JSONValue.encode(pairID),
            "shortened": JSONValue.encode(shortened),
            "fridayKind": JSONValue.encode(fridayKind),
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
        prayer = try record.decode("prayer", as: String.self)
        status = try record.decode("status", as: String.self)
        heart = try record.decode("heart", as: String?.self)
        eventAt = try record.decode("eventAt", as: Date.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
        loggedAt = try record.decode("loggedAt", as: Date?.self)
        source = try record.decode("source", as: String.self)
        tripID = try record.decode("tripID", as: UUID?.self)
        pairID = try record.decode("pairID", as: UUID?.self)
        shortened = try record.decode("shortened", as: Bool?.self)
        fridayKind = try record.fields["fridayKind"]?.decode(String?.self)
    }
}
@Model public final class QadaItem {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var prayer: String = "fajr"
    public var originalDayKey: String = ""
    public var madeUpAt: Date? = nil
    public init() {}
}
extension QadaItem: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "QadaItem", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "prayer": JSONValue.encode(prayer),
            "originalDayKey": JSONValue.encode(originalDayKey),
            "madeUpAt": JSONValue.encode(madeUpAt),
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
        prayer = try record.decode("prayer", as: String.self)
        originalDayKey = try record.decode("originalDayKey", as: String.self)
        madeUpAt = try record.decode("madeUpAt", as: Date?.self)
    }
}
@Model public final class QiyamNight {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var nightKey: String = ""
    public var rakaat: Int = 0
    public var witr: Bool = false
    public var quranSessionID: UUID? = nil
    public var tzID: String = ""
    public var dayPolicy: String = ""
    public init() {}
}
extension QiyamNight: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "QiyamNight", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "nightKey": JSONValue.encode(nightKey),
            "rakaat": JSONValue.encode(rakaat),
            "witr": JSONValue.encode(witr),
            "quranSessionID": JSONValue.encode(quranSessionID),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
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
        nightKey = try record.decode("nightKey", as: String.self)
        rakaat = try record.decode("rakaat", as: Int.self)
        witr = try record.decode("witr", as: Bool.self)
        quranSessionID = try record.decode("quranSessionID", as: UUID?.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
    }
}
@Model public final class HifzPlan {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var version: Int = 1
    public var direction: String = "forward"
    public var startAyah: Int = 1
    public var unit: String = "page"
    public var amount: Double = 1.0
    public var rhythm: String = "balanced"
    public var missPolicy: String = "ask"
    public var frontierAyah: Int? = nil
    public var activeFrom: Date = Date()
    public var supersededAt: Date? = nil
    public init() {}
}
extension HifzPlan: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HifzPlan", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "version": JSONValue.encode(version),
            "direction": JSONValue.encode(direction),
            "startAyah": JSONValue.encode(startAyah),
            "unit": JSONValue.encode(unit),
            "amount": JSONValue.encode(amount),
            "rhythm": JSONValue.encode(rhythm),
            "missPolicy": JSONValue.encode(missPolicy),
            "frontierAyah": JSONValue.encode(frontierAyah),
            "activeFrom": JSONValue.encode(activeFrom),
            "supersededAt": JSONValue.encode(supersededAt),
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
        version = try record.decode("version", as: Int.self)
        direction = try record.decode("direction", as: String.self)
        startAyah = try record.decode("startAyah", as: Int.self)
        unit = try record.decode("unit", as: String.self)
        amount = try record.decode("amount", as: Double.self)
        rhythm = try record.decode("rhythm", as: String.self)
        missPolicy = try record.decode("missPolicy", as: String.self)
        frontierAyah = try record.decode("frontierAyah", as: Int?.self)
        activeFrom = try record.decode("activeFrom", as: Date.self)
        supersededAt = try record.decode("supersededAt", as: Date?.self)
    }
}
@Model public final class HifzSession {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var planID: UUID? = nil
    public var dayKey: String = ""
    public var endedAt: Date = Date()
    public var tzID: String = ""
    public var dayPolicy: String = ""
    public var kind: String = "hifz"
    public var fromAyah: Int = 1
    public var toAyah: Int = 1
    public var pages: [Int] = []
    public var mistakes: Int = 0
    public var method: String = "coach"
    public var source: String = "app"
    public var commitID: UUID? = nil
    public var nightKey: String? = nil
    public init() {}
}
extension HifzSession: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HifzSession", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "planID": JSONValue.encode(planID),
            "dayKey": JSONValue.encode(dayKey),
            "endedAt": JSONValue.encode(endedAt),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
            "kind": JSONValue.encode(kind),
            "fromAyah": JSONValue.encode(fromAyah),
            "toAyah": JSONValue.encode(toAyah),
            "pages": JSONValue.encode(pages),
            "mistakes": JSONValue.encode(mistakes),
            "method": JSONValue.encode(method),
            "source": JSONValue.encode(source),
            "commitID": JSONValue.encode(commitID),
            "nightKey": JSONValue.encode(nightKey),
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
        planID = try record.decode("planID", as: UUID?.self)
        dayKey = try record.decode("dayKey", as: String.self)
        endedAt = try record.decode("endedAt", as: Date.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
        kind = try record.decode("kind", as: String.self)
        fromAyah = try record.decode("fromAyah", as: Int.self)
        toAyah = try record.decode("toAyah", as: Int.self)
        pages = try record.decode("pages", as: [Int].self)
        mistakes = try record.decode("mistakes", as: Int.self)
        method = try record.decode("method", as: String.self)
        source = try record.decode("source", as: String.self)
        commitID = try record.decode("commitID", as: UUID?.self)
        nightKey = try record.decode("nightKey", as: String?.self)
    }
}
@Model public final class PageGrade {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var sessionID: UUID? = nil
    public var page: Int = 1
    public var grade: String = "good"
    public var role: String = "regular"
    public init() {}
}
extension PageGrade: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "PageGrade", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "sessionID": JSONValue.encode(sessionID),
            "page": JSONValue.encode(page),
            "grade": JSONValue.encode(grade),
            "role": JSONValue.encode(role),
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
        sessionID = try record.decode("sessionID", as: UUID?.self)
        page = try record.decode("page", as: Int.self)
        grade = try record.decode("grade", as: String.self)
        role = try record.decode("role", as: String.self)
    }
}
@Model public final class MistakeSpot {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var ayahId: Int = 1
    public var wordIndex: Int? = nil
    public var legacyHits: Int = 0
    public var legacyLastDrillAt: Date? = nil
    public var legacyStreak: Int = 0
    public init() {}
}
extension MistakeSpot: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "MistakeSpot", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "ayahId": JSONValue.encode(ayahId),
            "wordIndex": JSONValue.encode(wordIndex),
            "legacyHits": JSONValue.encode(legacyHits),
            "legacyLastDrillAt": JSONValue.encode(legacyLastDrillAt),
            "legacyStreak": JSONValue.encode(legacyStreak),
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
        ayahId = try record.decode("ayahId", as: Int.self)
        wordIndex = try record.decode("wordIndex", as: Int?.self)
        legacyHits = try record.decode("legacyHits", as: Int.self)
        legacyLastDrillAt = try record.decode("legacyLastDrillAt", as: Date?.self)
        legacyStreak = try record.decode("legacyStreak", as: Int.self)
    }
}
@Model public final class MistakeEvent {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var ayahId: Int = 1
    public var wordIndex: Int? = nil
    public var sessionID: UUID? = nil
    public var at: Date = Date()
    public var kind: String = "mistake"
    public init() {}
}
extension MistakeEvent: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "MistakeEvent", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "ayahId": JSONValue.encode(ayahId),
            "wordIndex": JSONValue.encode(wordIndex),
            "sessionID": JSONValue.encode(sessionID),
            "at": JSONValue.encode(at),
            "kind": JSONValue.encode(kind),
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
        ayahId = try record.decode("ayahId", as: Int.self)
        wordIndex = try record.decode("wordIndex", as: Int?.self)
        sessionID = try record.decode("sessionID", as: UUID?.self)
        at = try record.decode("at", as: Date.self)
        kind = try record.decode("kind", as: String.self)
    }
}
@Model public final class QuranDayState {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var dayKey: String = ""
    public var hifzLevel: String? = nil
    public var reviewLevel: String? = nil
    public var forceNewHifz: Bool = false
    public var testPages: [Int] = []
    public init() {}
}
extension QuranDayState: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "QuranDayState", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "hifzLevel": JSONValue.encode(hifzLevel),
            "reviewLevel": JSONValue.encode(reviewLevel),
            "forceNewHifz": JSONValue.encode(forceNewHifz),
            "testPages": JSONValue.encode(testPages),
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
        hifzLevel = try record.decode("hifzLevel", as: String?.self)
        reviewLevel = try record.decode("reviewLevel", as: String?.self)
        forceNewHifz = try record.decode("forceNewHifz", as: Bool.self)
        testPages = try record.decode("testPages", as: [Int].self)
    }
}
@Model public final class QuranAllotment {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var dayKey: String = ""
    public var kind: String = "hifzExtra"
    public var amount: Double = 0.0
    public var pages: [Int] = []
    public var origin: String = "missPolicy"
    public var originDayKey: String = ""
    public init() {}
}
extension QuranAllotment: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "QuranAllotment", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "kind": JSONValue.encode(kind),
            "amount": JSONValue.encode(amount),
            "pages": JSONValue.encode(pages),
            "origin": JSONValue.encode(origin),
            "originDayKey": JSONValue.encode(originDayKey),
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
        kind = try record.decode("kind", as: String.self)
        amount = try record.decode("amount", as: Double.self)
        pages = try record.decode("pages", as: [Int].self)
        origin = try record.decode("origin", as: String.self)
        originDayKey = try record.decode("originDayKey", as: String.self)
    }
}
@Model public final class RecoveryPlan {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var startDayKey: String = ""
    public var days: Int = 7
    public var pages: [Int] = []
    public var cancelledAt: Date? = nil
    public init() {}
}
extension RecoveryPlan: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "RecoveryPlan", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "startDayKey": JSONValue.encode(startDayKey),
            "days": JSONValue.encode(days),
            "pages": JSONValue.encode(pages),
            "cancelledAt": JSONValue.encode(cancelledAt),
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
        startDayKey = try record.decode("startDayKey", as: String.self)
        days = try record.decode("days", as: Int.self)
        pages = try record.decode("pages", as: [Int].self)
        cancelledAt = try record.decode("cancelledAt", as: Date?.self)
    }
}
@Model public final class DayPage {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var dayKey: String = ""
    public var questionAnswer: String? = nil
    public var photoMediaID: UUID? = nil
    public var origin: String = "native"
    public var hiddenFromMemories: Bool = false
    public init() {}
}
extension DayPage: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "DayPage", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "questionAnswer": JSONValue.encode(questionAnswer),
            "photoMediaID": JSONValue.encode(photoMediaID),
            "origin": JSONValue.encode(origin),
            "hiddenFromMemories": JSONValue.encode(hiddenFromMemories),
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
        questionAnswer = try record.decode("questionAnswer", as: String?.self)
        photoMediaID = try record.decode("photoMediaID", as: UUID?.self)
        origin = try record.decode("origin", as: String.self)
        hiddenFromMemories = try record.decode("hiddenFromMemories", as: Bool.self)
    }
}
@Model public final class Niyya {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var dayKey: String = ""
    public var order: Int = 0
    public var text: String = ""
    public var result: String? = nil
    public init() {}
}
extension Niyya: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Niyya", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "order": JSONValue.encode(order),
            "text": JSONValue.encode(text),
            "result": JSONValue.encode(result),
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
        order = try record.decode("order", as: Int.self)
        text = try record.decode("text", as: String.self)
        result = try record.decode("result", as: String?.self)
    }
}
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
    public var tags: [String]? = nil
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
extension Entry: MadarRecordModel {
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
            "tags": JSONValue.encode(tags),
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
        tags = try record.fields["tags"]?.decode([String]?.self)
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
@Model public final class HiddenAutoLine {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var eventKind: String = ""
    public var eventID: UUID? = nil
    public var dayKey: String = ""
    public init() {}
}
extension HiddenAutoLine: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HiddenAutoLine", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "eventKind": JSONValue.encode(eventKind),
            "eventID": JSONValue.encode(eventID),
            "dayKey": JSONValue.encode(dayKey),
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
        eventKind = try record.decode("eventKind", as: String.self)
        eventID = try record.decode("eventID", as: UUID?.self)
        dayKey = try record.decode("dayKey", as: String.self)
    }
}
@Model public final class MarginNote {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var targetDayKey: String = ""
    public var targetEntryID: UUID? = nil
    public var text: String = ""
    public var writtenAt: Date = Date()
    public var writtenDayKey: String = ""
    public var tzID: String = ""
    public var dayPolicy: String = ""
    public init() {}
}
extension MarginNote: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "MarginNote", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "targetDayKey": JSONValue.encode(targetDayKey),
            "targetEntryID": JSONValue.encode(targetEntryID),
            "text": JSONValue.encode(text),
            "writtenAt": JSONValue.encode(writtenAt),
            "writtenDayKey": JSONValue.encode(writtenDayKey),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
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
        targetDayKey = try record.decode("targetDayKey", as: String.self)
        targetEntryID = try record.decode("targetEntryID", as: UUID?.self)
        text = try record.decode("text", as: String.self)
        writtenAt = try record.decode("writtenAt", as: Date.self)
        writtenDayKey = try record.decode("writtenDayKey", as: String.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
    }
}
@Model public final class Letter {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var text: String = ""
    public var openAt: Date? = nil
    public var triggerKind: String = "date"
    public var triggerTargetID: UUID? = nil
    public var triggerValue: String? = nil
    public var state: String = "sealed"
    public var eligibleAt: Date? = nil
    public var openedAt: Date? = nil
    public init() {}
}
extension Letter: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Letter", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "text": JSONValue.encode(text),
            "openAt": JSONValue.encode(openAt),
            "triggerKind": JSONValue.encode(triggerKind),
            "triggerTargetID": JSONValue.encode(triggerTargetID),
            "triggerValue": JSONValue.encode(triggerValue),
            "state": JSONValue.encode(state),
            "eligibleAt": JSONValue.encode(eligibleAt),
            "openedAt": JSONValue.encode(openedAt),
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
        text = try record.decode("text", as: String.self)
        openAt = try record.decode("openAt", as: Date?.self)
        triggerKind = try record.decode("triggerKind", as: String.self)
        triggerTargetID = try record.decode("triggerTargetID", as: UUID?.self)
        triggerValue = try record.decode("triggerValue", as: String?.self)
        state = try record.decode("state", as: String.self)
        eligibleAt = try record.decode("eligibleAt", as: Date?.self)
        openedAt = try record.decode("openedAt", as: Date?.self)
    }
}
@Model public final class Project {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var name: String = ""
    public var intention: String = ""
    public var keyword: String? = nil
    public var finishedAt: Date? = nil
    public var reflection: String? = nil
    public init() {}
}
extension Project: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Project", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "intention": JSONValue.encode(intention),
            "keyword": JSONValue.encode(keyword),
            "finishedAt": JSONValue.encode(finishedAt),
            "reflection": JSONValue.encode(reflection),
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
        name = try record.decode("name", as: String.self)
        intention = try record.decode("intention", as: String.self)
        keyword = try record.decode("keyword", as: String?.self)
        finishedAt = try record.decode("finishedAt", as: Date?.self)
        reflection = try record.decode("reflection", as: String?.self)
    }
}
@Model public final class Media {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var kind: String = "photo"
    public var contentType: String = ""
    @Attribute(.externalStorage) public var data: Data? = nil
    public var sizeBytes: Int = 0
    public var sha256: String = ""
    public var durationS: Int? = nil
    public var sourceID: String? = nil
    public var state: String = "ok"
    public var importBatchID: UUID? = nil
    public init() {}
}
extension Media: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Media", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "kind": JSONValue.encode(kind),
            "contentType": JSONValue.encode(contentType),
            "data": JSONValue.encode(data),
            "sizeBytes": JSONValue.encode(sizeBytes),
            "sha256": JSONValue.encode(sha256),
            "durationS": JSONValue.encode(durationS),
            "sourceID": JSONValue.encode(sourceID),
            "state": JSONValue.encode(state),
            "importBatchID": JSONValue.encode(importBatchID),
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
        kind = try record.decode("kind", as: String.self)
        contentType = try record.decode("contentType", as: String.self)
        data = try record.decode("data", as: Data?.self)
        sizeBytes = try record.decode("sizeBytes", as: Int.self)
        sha256 = try record.decode("sha256", as: String.self)
        durationS = try record.decode("durationS", as: Int?.self)
        sourceID = try record.decode("sourceID", as: String?.self)
        state = try record.decode("state", as: String.self)
        importBatchID = try record.decode("importBatchID", as: UUID?.self)
    }
}
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
    public var last4: String? = nil
    public var tracked: Bool = true
    public init() {}
}
extension Account: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Account", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "bank": JSONValue.encode(bank),
            "kind": JSONValue.encode(kind),
            "ownerName": JSONValue.encode(ownerName),
            "ownership": JSONValue.encode(ownership),
            "zakatInclude": JSONValue.encode(zakatInclude),
            "currency": JSONValue.encode(currency),
            "balanceMinor": JSONValue.encode(balanceMinor),
            "balanceAt": JSONValue.encode(balanceAt),
            "parentID": JSONValue.encode(parentID),
            "senderIDs": JSONValue.encode(senderIDs),
            "last4": JSONValue.encode(last4),
            "tracked": JSONValue.encode(tracked),
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
        name = try record.decode("name", as: String.self)
        bank = try record.decode("bank", as: String.self)
        kind = try record.decode("kind", as: String.self)
        ownerName = try record.decode("ownerName", as: String?.self)
        ownership = try record.decode("ownership", as: String.self)
        zakatInclude = try record.decode("zakatInclude", as: Bool.self)
        currency = try record.decode("currency", as: String.self)
        balanceMinor = try record.decode("balanceMinor", as: Int.self)
        balanceAt = try record.decode("balanceAt", as: Date?.self)
        parentID = try record.decode("parentID", as: UUID?.self)
        senderIDs = try record.decode("senderIDs", as: [String].self)
        last4 = try record.fields["last4"]?.decode(String?.self)
        tracked = try record.fields["tracked"]?.decode(Bool.self) ?? true
    }
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
    public var kind: String = "credit"
    public init() {}
}
extension Card: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Card", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "bank": JSONValue.encode(bank),
            "last4": JSONValue.encode(last4),
            "aliases": JSONValue.encode(aliases),
            "holderName": JSONValue.encode(holderName),
            "network": JSONValue.encode(network),
            "limitMinor": JSONValue.encode(limitMinor),
            "cashbackBp": JSONValue.encode(cashbackBp),
            "aprBp": JSONValue.encode(aprBp),
            "accountID": JSONValue.encode(accountID),
            "fieldSourcesJSON": JSONValue.encode(fieldSourcesJSON),
            "kind": JSONValue.encode(kind),
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
        name = try record.decode("name", as: String.self)
        bank = try record.decode("bank", as: String.self)
        last4 = try record.decode("last4", as: String.self)
        aliases = try record.decode("aliases", as: [String].self)
        holderName = try record.decode("holderName", as: String?.self)
        network = try record.decode("network", as: String.self)
        limitMinor = try record.decode("limitMinor", as: Int?.self)
        cashbackBp = try record.decode("cashbackBp", as: Int?.self)
        aprBp = try record.decode("aprBp", as: Int?.self)
        accountID = try record.decode("accountID", as: UUID?.self)
        fieldSourcesJSON = try record.decode("fieldSourcesJSON", as: Data.self)
        kind = try record.fields["kind"]?.decode(String.self) ?? "credit"
    }
}
@Model public final class Statement {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var cardID: UUID? = nil
    public var closeDate: Date = Date()
    public var closeDateSource: String = "estimated"
    public var periodStart: Date? = nil
    public var dueDate: Date? = nil
    public var statementMinor: Int = 0
    public var minimumDueMinor: Int = 0
    public var messageID: UUID? = nil
    public init() {}
}
extension Statement: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Statement", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "cardID": JSONValue.encode(cardID),
            "closeDate": JSONValue.encode(closeDate),
            "closeDateSource": JSONValue.encode(closeDateSource),
            "periodStart": JSONValue.encode(periodStart),
            "dueDate": JSONValue.encode(dueDate),
            "statementMinor": JSONValue.encode(statementMinor),
            "minimumDueMinor": JSONValue.encode(minimumDueMinor),
            "messageID": JSONValue.encode(messageID),
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
        cardID = try record.decode("cardID", as: UUID?.self)
        closeDate = try record.decode("closeDate", as: Date.self)
        closeDateSource = try record.decode("closeDateSource", as: String.self)
        periodStart = try record.decode("periodStart", as: Date?.self)
        dueDate = try record.decode("dueDate", as: Date?.self)
        statementMinor = try record.decode("statementMinor", as: Int.self)
        minimumDueMinor = try record.decode("minimumDueMinor", as: Int.self)
        messageID = try record.decode("messageID", as: UUID?.self)
    }
}
@Model public final class CashbackEntry {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var cardID: UUID? = nil
    public var eventAt: Date = Date()
    public var amountMinor: Int = 0
    public var kind: String = "earned"
    public var transactionID: UUID? = nil
    public init() {}
}
extension CashbackEntry: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "CashbackEntry", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "cardID": JSONValue.encode(cardID),
            "eventAt": JSONValue.encode(eventAt),
            "amountMinor": JSONValue.encode(amountMinor),
            "kind": JSONValue.encode(kind),
            "transactionID": JSONValue.encode(transactionID),
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
        cardID = try record.decode("cardID", as: UUID?.self)
        eventAt = try record.decode("eventAt", as: Date.self)
        amountMinor = try record.decode("amountMinor", as: Int.self)
        kind = try record.decode("kind", as: String.self)
        transactionID = try record.decode("transactionID", as: UUID?.self)
    }
}
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
    public var budgetIgnoreReason: String? = nil
    public init() {}
}
extension MoneyTransaction: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "MoneyTransaction", fields: [
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
            "kind": JSONValue.encode(kind),
            "amountMinor": JSONValue.encode(amountMinor),
            "currency": JSONValue.encode(currency),
            "homeAmountMinor": JSONValue.encode(homeAmountMinor),
            "homeCurrency": JSONValue.encode(homeCurrency),
            "rateAtTime": JSONValue.encode(rateAtTime),
            "rateSource": JSONValue.encode(rateSource),
            "merchant": JSONValue.encode(merchant),
            "counterparty": JSONValue.encode(counterparty),
            "categoryID": JSONValue.encode(categoryID),
            "method": JSONValue.encode(method),
            "fromAccountID": JSONValue.encode(fromAccountID),
            "toAccountID": JSONValue.encode(toAccountID),
            "cardID": JSONValue.encode(cardID),
            "relatedTransactionID": JSONValue.encode(relatedTransactionID),
            "obligationID": JSONValue.encode(obligationID),
            "installmentID": JSONValue.encode(installmentID),
            "cycleID": JSONValue.encode(cycleID),
            "ignoredFromBudget": JSONValue.encode(ignoredFromBudget),
            "source": JSONValue.encode(source),
            "messageID": JSONValue.encode(messageID),
            "tripID": JSONValue.encode(tripID),
            "showInDiary": JSONValue.encode(showInDiary),
            "reviewState": JSONValue.encode(reviewState),
            "budgetIgnoreReason": JSONValue.encode(budgetIgnoreReason),
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
        kind = try record.decode("kind", as: String.self)
        amountMinor = try record.decode("amountMinor", as: Int.self)
        currency = try record.decode("currency", as: String.self)
        homeAmountMinor = try record.decode("homeAmountMinor", as: Int.self)
        homeCurrency = try record.decode("homeCurrency", as: String.self)
        rateAtTime = try record.decode("rateAtTime", as: String?.self)
        rateSource = try record.decode("rateSource", as: String?.self)
        merchant = try record.decode("merchant", as: String?.self)
        counterparty = try record.decode("counterparty", as: String?.self)
        categoryID = try record.decode("categoryID", as: UUID?.self)
        method = try record.decode("method", as: String.self)
        fromAccountID = try record.decode("fromAccountID", as: UUID?.self)
        toAccountID = try record.decode("toAccountID", as: UUID?.self)
        cardID = try record.decode("cardID", as: UUID?.self)
        relatedTransactionID = try record.decode("relatedTransactionID", as: UUID?.self)
        obligationID = try record.decode("obligationID", as: UUID?.self)
        installmentID = try record.decode("installmentID", as: UUID?.self)
        cycleID = try record.decode("cycleID", as: UUID?.self)
        ignoredFromBudget = try record.decode("ignoredFromBudget", as: Bool.self)
        source = try record.decode("source", as: String.self)
        messageID = try record.decode("messageID", as: UUID?.self)
        tripID = try record.decode("tripID", as: UUID?.self)
        showInDiary = try record.decode("showInDiary", as: Bool.self)
        reviewState = try record.decode("reviewState", as: String.self)
        budgetIgnoreReason = try record.fields["budgetIgnoreReason"]?.decode(String?.self)
    }
}
@Model public final class Allocation {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var transactionID: UUID? = nil
    public var groupID: UUID? = nil
    public var target: String = "daily"
    public var targetID: UUID? = nil
    public var amountMinor: Int = 0
    public var kind: String = "spend"
    public var cycleID: UUID? = nil
    public var idempotencyKey: String = ""
    public init() {}
}
extension Allocation: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Allocation", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "transactionID": JSONValue.encode(transactionID),
            "groupID": JSONValue.encode(groupID),
            "target": JSONValue.encode(target),
            "targetID": JSONValue.encode(targetID),
            "amountMinor": JSONValue.encode(amountMinor),
            "kind": JSONValue.encode(kind),
            "cycleID": JSONValue.encode(cycleID),
            "idempotencyKey": JSONValue.encode(idempotencyKey),
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
        transactionID = try record.decode("transactionID", as: UUID?.self)
        groupID = try record.decode("groupID", as: UUID?.self)
        target = try record.decode("target", as: String.self)
        targetID = try record.decode("targetID", as: UUID?.self)
        amountMinor = try record.decode("amountMinor", as: Int.self)
        kind = try record.decode("kind", as: String.self)
        cycleID = try record.decode("cycleID", as: UUID?.self)
        idempotencyKey = try record.decode("idempotencyKey", as: String.self)
    }
}
@Model public final class Reconciliation {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var accountID: UUID? = nil
    public var cardID: UUID? = nil
    public var obligationID: UUID? = nil
    public var at: Date = Date()
    public var expectedMinor: Int = 0
    public var observedMinor: Int = 0
    public var deltaMinor: Int = 0
    public var resolution: String = "adjust"
    public var adjustmentTransactionID: UUID? = nil
    public var beforeJSON: Data = Data()
    public var note: String? = nil
    public init() {}
}
extension Reconciliation: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Reconciliation", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "accountID": JSONValue.encode(accountID),
            "cardID": JSONValue.encode(cardID),
            "obligationID": JSONValue.encode(obligationID),
            "at": JSONValue.encode(at),
            "expectedMinor": JSONValue.encode(expectedMinor),
            "observedMinor": JSONValue.encode(observedMinor),
            "deltaMinor": JSONValue.encode(deltaMinor),
            "resolution": JSONValue.encode(resolution),
            "adjustmentTransactionID": JSONValue.encode(adjustmentTransactionID),
            "beforeJSON": JSONValue.encode(beforeJSON),
            "note": JSONValue.encode(note),
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
        accountID = try record.decode("accountID", as: UUID?.self)
        cardID = try record.decode("cardID", as: UUID?.self)
        obligationID = try record.fields["obligationID"]?.decode(UUID?.self)
        at = try record.decode("at", as: Date.self)
        expectedMinor = try record.decode("expectedMinor", as: Int.self)
        observedMinor = try record.decode("observedMinor", as: Int.self)
        deltaMinor = try record.decode("deltaMinor", as: Int.self)
        resolution = try record.decode("resolution", as: String.self)
        adjustmentTransactionID = try record.decode("adjustmentTransactionID", as: UUID?.self)
        beforeJSON = try record.decode("beforeJSON", as: Data.self)
        note = try record.decode("note", as: String?.self)
    }
}
@Model public final class BankMessage {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var sender: String = ""
    public var text: String = ""
    public var normalizedText: String = ""
    public var receivedAt: Date = Date()
    public var receivedAtSource: String = "device"
    public var fingerprint: String = ""
    public var occurrence: Int = 1
    public var channel: String = "shortcut"
    public var importBatchID: UUID? = nil
    public var kind: String = ""
    public var parsedJSON: Data? = nil
    public var parseVersion: Int = 1
    public var status: String = "ok"
    public init() {}
}
extension BankMessage: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "BankMessage", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "sender": JSONValue.encode(sender),
            "text": JSONValue.encode(text),
            "normalizedText": JSONValue.encode(normalizedText),
            "receivedAt": JSONValue.encode(receivedAt),
            "receivedAtSource": JSONValue.encode(receivedAtSource),
            "fingerprint": JSONValue.encode(fingerprint),
            "occurrence": JSONValue.encode(occurrence),
            "channel": JSONValue.encode(channel),
            "importBatchID": JSONValue.encode(importBatchID),
            "kind": JSONValue.encode(kind),
            "parsedJSON": JSONValue.encode(parsedJSON),
            "parseVersion": JSONValue.encode(parseVersion),
            "status": JSONValue.encode(status),
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
        sender = try record.decode("sender", as: String.self)
        text = try record.decode("text", as: String.self)
        normalizedText = try record.decode("normalizedText", as: String.self)
        receivedAt = try record.decode("receivedAt", as: Date.self)
        receivedAtSource = try record.decode("receivedAtSource", as: String.self)
        fingerprint = try record.decode("fingerprint", as: String.self)
        occurrence = try record.decode("occurrence", as: Int.self)
        channel = try record.decode("channel", as: String.self)
        importBatchID = try record.decode("importBatchID", as: UUID?.self)
        kind = try record.decode("kind", as: String.self)
        parsedJSON = try record.decode("parsedJSON", as: Data?.self)
        parseVersion = try record.decode("parseVersion", as: Int.self)
        status = try record.decode("status", as: String.self)
    }
}
@Model public final class Cycle {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var start: Date = Date()
    public var end: Date? = nil
    public var expectedEnd: Date? = nil
    public var closedAt: Date? = nil
    public var salaryTransactionID: UUID? = nil
    public var incomeMinor: Int = 0
    public var mode: String = "fixed"
    public var percentBp: Int? = nil
    public var dailyAllowanceMinor: Int = 0
    public var carryAdjustMinor: Int = 0
    public var closedReportJSON: Data? = nil
    public var reportVersion: Int = 0
    public init() {}
}
extension Cycle: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Cycle", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "start": JSONValue.encode(start),
            "end": JSONValue.encode(end),
            "expectedEnd": JSONValue.encode(expectedEnd),
            "closedAt": JSONValue.encode(closedAt),
            "salaryTransactionID": JSONValue.encode(salaryTransactionID),
            "incomeMinor": JSONValue.encode(incomeMinor),
            "mode": JSONValue.encode(mode),
            "percentBp": JSONValue.encode(percentBp),
            "dailyAllowanceMinor": JSONValue.encode(dailyAllowanceMinor),
            "carryAdjustMinor": JSONValue.encode(carryAdjustMinor),
            "closedReportJSON": JSONValue.encode(closedReportJSON),
            "reportVersion": JSONValue.encode(reportVersion),
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
        start = try record.decode("start", as: Date.self)
        end = try record.decode("end", as: Date?.self)
        expectedEnd = try record.decode("expectedEnd", as: Date?.self)
        closedAt = try record.decode("closedAt", as: Date?.self)
        salaryTransactionID = try record.decode("salaryTransactionID", as: UUID?.self)
        incomeMinor = try record.decode("incomeMinor", as: Int.self)
        mode = try record.decode("mode", as: String.self)
        percentBp = try record.decode("percentBp", as: Int?.self)
        dailyAllowanceMinor = try record.decode("dailyAllowanceMinor", as: Int.self)
        carryAdjustMinor = try record.decode("carryAdjustMinor", as: Int.self)
        closedReportJSON = try record.decode("closedReportJSON", as: Data?.self)
        reportVersion = try record.decode("reportVersion", as: Int.self)
    }
}
@Model public final class CyclePolicy {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var cycleID: UUID? = nil
    public var effectiveFromDayKey: String = ""
    public var mode: String = "fixed"
    public var allowanceMinor: Int = 0
    public var percentBp: Int? = nil
    public var dailyRateMinor: Int = 0
    public var lastDayRemainderMinor: Int = 0
    public init() {}
}
extension CyclePolicy: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "CyclePolicy", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "cycleID": JSONValue.encode(cycleID),
            "effectiveFromDayKey": JSONValue.encode(effectiveFromDayKey),
            "mode": JSONValue.encode(mode),
            "allowanceMinor": JSONValue.encode(allowanceMinor),
            "percentBp": JSONValue.encode(percentBp),
            "dailyRateMinor": JSONValue.encode(dailyRateMinor),
            "lastDayRemainderMinor": JSONValue.encode(lastDayRemainderMinor),
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
        cycleID = try record.decode("cycleID", as: UUID?.self)
        effectiveFromDayKey = try record.decode("effectiveFromDayKey", as: String.self)
        mode = try record.decode("mode", as: String.self)
        allowanceMinor = try record.decode("allowanceMinor", as: Int.self)
        percentBp = try record.decode("percentBp", as: Int?.self)
        dailyRateMinor = try record.decode("dailyRateMinor", as: Int.self)
        lastDayRemainderMinor = try record.decode("lastDayRemainderMinor", as: Int.self)
    }
}
@Model public final class Envelope {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var name: String = ""
    public var role: String = "general"
    public var balanceMinor: Int = 0
    public var targetMinor: Int? = nil
    public var due: Date? = nil
    public init() {}
}
extension Envelope: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Envelope", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "role": JSONValue.encode(role),
            "balanceMinor": JSONValue.encode(balanceMinor),
            "targetMinor": JSONValue.encode(targetMinor),
            "due": JSONValue.encode(due),
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
        name = try record.decode("name", as: String.self)
        role = try record.decode("role", as: String.self)
        balanceMinor = try record.decode("balanceMinor", as: Int.self)
        targetMinor = try record.decode("targetMinor", as: Int?.self)
        due = try record.decode("due", as: Date?.self)
    }
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
    public var period: String = "perCycle"
    public var startDayKey: String? = nil
    public var repaymentTotalMinor: Int? = nil
    public var repaymentPaychecks: Int? = nil
    public init() {}
}
extension EnvelopePlan: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "EnvelopePlan", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "envelopeID": JSONValue.encode(envelopeID),
            "kind": JSONValue.encode(kind),
            "source": JSONValue.encode(source),
            "perPaycheckMinor": JSONValue.encode(perPaycheckMinor),
            "untilDate": JSONValue.encode(untilDate),
            "period": JSONValue.encode(period),
            "startDayKey": JSONValue.encode(startDayKey),
            "repaymentTotalMinor": JSONValue.encode(repaymentTotalMinor),
            "repaymentPaychecks": JSONValue.encode(repaymentPaychecks),
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
        envelopeID = try record.decode("envelopeID", as: UUID?.self)
        kind = try record.decode("kind", as: String.self)
        source = try record.decode("source", as: String.self)
        perPaycheckMinor = try record.decode("perPaycheckMinor", as: Int.self)
        untilDate = try record.decode("untilDate", as: Date?.self)
        period = try record.fields["period"]?.decode(String.self) ?? "perCycle"
        startDayKey = try record.fields["startDayKey"]?.decode(String?.self)
        repaymentTotalMinor = try record.fields["repaymentTotalMinor"]?.decode(Int?.self)
        repaymentPaychecks = try record.fields["repaymentPaychecks"]?.decode(Int?.self)
    }
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
    public var repeatEvery: Int? = nil
    public var repeatUnit: String? = nil
    public var firstDueDayKey: String? = nil
    public init() {}
}
extension Obligation: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Obligation", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "kind": JSONValue.encode(kind),
            "name": JSONValue.encode(name),
            "provider": JSONValue.encode(provider),
            "amountMinor": JSONValue.encode(amountMinor),
            "totalMinor": JSONValue.encode(totalMinor),
            "currency": JSONValue.encode(currency),
            "dueDay": JSONValue.encode(dueDay),
            "remainingCount": JSONValue.encode(remainingCount),
            "purchaseTransactionID": JSONValue.encode(purchaseTransactionID),
            "sourceMessageID": JSONValue.encode(sourceMessageID),
            "repeatEvery": JSONValue.encode(repeatEvery),
            "repeatUnit": JSONValue.encode(repeatUnit),
            "firstDueDayKey": JSONValue.encode(firstDueDayKey),
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
        kind = try record.decode("kind", as: String.self)
        name = try record.decode("name", as: String.self)
        provider = try record.decode("provider", as: String?.self)
        amountMinor = try record.decode("amountMinor", as: Int.self)
        totalMinor = try record.decode("totalMinor", as: Int.self)
        currency = try record.decode("currency", as: String.self)
        dueDay = try record.decode("dueDay", as: Int?.self)
        remainingCount = try record.decode("remainingCount", as: Int?.self)
        purchaseTransactionID = try record.decode("purchaseTransactionID", as: UUID?.self)
        sourceMessageID = try record.decode("sourceMessageID", as: UUID?.self)
        repeatEvery = try record.fields["repeatEvery"]?.decode(Int?.self)
        repeatUnit = try record.fields["repeatUnit"]?.decode(String?.self)
        firstDueDayKey = try record.fields["firstDueDayKey"]?.decode(String?.self)
    }
}
@Model public final class InstallmentItem {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var obligationID: UUID? = nil
    public var seq: Int = 1
    public var dueDate: Date = Date()
    public var amountMinor: Int = 0
    public var paidMinor: Int = 0
    public var paidTransactionID: UUID? = nil
    public var paidAt: Date? = nil
    public init() {}
}
extension InstallmentItem: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "InstallmentItem", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "obligationID": JSONValue.encode(obligationID),
            "seq": JSONValue.encode(seq),
            "dueDate": JSONValue.encode(dueDate),
            "amountMinor": JSONValue.encode(amountMinor),
            "paidMinor": JSONValue.encode(paidMinor),
            "paidTransactionID": JSONValue.encode(paidTransactionID),
            "paidAt": JSONValue.encode(paidAt),
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
        obligationID = try record.decode("obligationID", as: UUID?.self)
        seq = try record.decode("seq", as: Int.self)
        dueDate = try record.decode("dueDate", as: Date.self)
        amountMinor = try record.decode("amountMinor", as: Int.self)
        paidMinor = try record.decode("paidMinor", as: Int.self)
        paidTransactionID = try record.decode("paidTransactionID", as: UUID?.self)
        paidAt = try record.decode("paidAt", as: Date?.self)
    }
}
@Model public final class Category {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var name: String = ""
    public var icon: String = ""
    public var color: String = ""
    public var order: Int = 0
    public init() {}
}
extension Category: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Category", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "icon": JSONValue.encode(icon),
            "color": JSONValue.encode(color),
            "order": JSONValue.encode(order),
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
        name = try record.decode("name", as: String.self)
        icon = try record.decode("icon", as: String.self)
        color = try record.decode("color", as: String.self)
        order = try record.decode("order", as: Int.self)
    }
}
@Model public final class CategoryLimit {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var categoryID: UUID? = nil
    public var mode: String = "fixed"
    public var limitMinor: Int = 0
    public var percentBp: Int? = nil
    public var base: String = "income"
    public var alert80CycleID: UUID? = nil
    public init() {}
}
extension CategoryLimit: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "CategoryLimit", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "categoryID": JSONValue.encode(categoryID),
            "mode": JSONValue.encode(mode),
            "limitMinor": JSONValue.encode(limitMinor),
            "percentBp": JSONValue.encode(percentBp),
            "base": JSONValue.encode(base),
            "alert80CycleID": JSONValue.encode(alert80CycleID),
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
        categoryID = try record.decode("categoryID", as: UUID?.self)
        mode = try record.decode("mode", as: String.self)
        limitMinor = try record.decode("limitMinor", as: Int.self)
        percentBp = try record.decode("percentBp", as: Int?.self)
        base = try record.decode("base", as: String.self)
        alert80CycleID = try record.decode("alert80CycleID", as: UUID?.self)
    }
}
@Model public final class MerchantRule {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var pattern: String = ""
    public var categoryID: UUID? = nil
    public var ignore: Bool = false
    public init() {}
}
extension MerchantRule: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "MerchantRule", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "pattern": JSONValue.encode(pattern),
            "categoryID": JSONValue.encode(categoryID),
            "ignore": JSONValue.encode(ignore),
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
        pattern = try record.decode("pattern", as: String.self)
        categoryID = try record.decode("categoryID", as: UUID?.self)
        ignore = try record.decode("ignore", as: Bool.self)
    }
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
    public var nisabBasis: String = "gold"
    public var nisabSilverMg: Int = 595000
    public var silverPricePerGramMinor: Int? = nil
    public var silverPriceSetAt: Date? = nil
    public init() {}
}
extension ZakatProfile: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "ZakatProfile", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "hawlStartHijri": JSONValue.encode(hawlStartHijri),
            "goldPricePerGramMinor": JSONValue.encode(goldPricePerGramMinor),
            "goldPriceSetAt": JSONValue.encode(goldPriceSetAt),
            "nisabMg": JSONValue.encode(nisabMg),
            "debtsPolicy": JSONValue.encode(debtsPolicy),
            "otherAssetsMinor": JSONValue.encode(otherAssetsMinor),
            "lastPaidAt": JSONValue.encode(lastPaidAt),
            "nisabBasis": JSONValue.encode(nisabBasis),
            "nisabSilverMg": JSONValue.encode(nisabSilverMg),
            "silverPricePerGramMinor": JSONValue.encode(silverPricePerGramMinor),
            "silverPriceSetAt": JSONValue.encode(silverPriceSetAt),
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
        hawlStartHijri = try record.decode("hawlStartHijri", as: String.self)
        goldPricePerGramMinor = try record.decode("goldPricePerGramMinor", as: Int?.self)
        goldPriceSetAt = try record.decode("goldPriceSetAt", as: Date?.self)
        nisabMg = try record.decode("nisabMg", as: Int.self)
        debtsPolicy = try record.decode("debtsPolicy", as: String.self)
        otherAssetsMinor = try record.decode("otherAssetsMinor", as: Int.self)
        lastPaidAt = try record.decode("lastPaidAt", as: Date?.self)
        nisabBasis = try record.fields["nisabBasis"]?.decode(String.self) ?? "gold"
        nisabSilverMg = try record.fields["nisabSilverMg"]?.decode(Int.self) ?? 595000
        silverPricePerGramMinor = try record.fields["silverPricePerGramMinor"]?.decode(Int?.self)
        silverPriceSetAt = try record.fields["silverPriceSetAt"]?.decode(Date?.self)
    }
}
@Model public final class Book {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var title: String = ""
    public var author: String = ""
    public var editor: String? = nil
    public var edition: String? = nil
    public var kind: String = "paper"
    public var format: String? = nil
    public var shelf: String = "want"
    public var pages: Int? = nil
    public var locatorJSON: Data? = nil
    public var currentPage: Int? = nil
    public var tocJSON: Data? = nil
    public var language: String = "ar"
    public var mediaID: UUID? = nil
    public var fileHash: String? = nil
    public var isbn13: String? = nil
    public var sourceGoodreadsID: String? = nil
    public var importBatchID: UUID? = nil
    public var turathID: Int? = nil
    public var finishedAt: Date? = nil
    public var rating: Int? = nil
    public var review: String? = nil
    public var readCount: Int = 0
    public init() {}
}
extension Book: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Book", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "title": JSONValue.encode(title),
            "author": JSONValue.encode(author),
            "editor": JSONValue.encode(editor),
            "edition": JSONValue.encode(edition),
            "kind": JSONValue.encode(kind),
            "format": JSONValue.encode(format),
            "shelf": JSONValue.encode(shelf),
            "pages": JSONValue.encode(pages),
            "locatorJSON": JSONValue.encode(locatorJSON),
            "currentPage": JSONValue.encode(currentPage),
            "tocJSON": JSONValue.encode(tocJSON),
            "language": JSONValue.encode(language),
            "mediaID": JSONValue.encode(mediaID),
            "fileHash": JSONValue.encode(fileHash),
            "isbn13": JSONValue.encode(isbn13),
            "sourceGoodreadsID": JSONValue.encode(sourceGoodreadsID),
            "importBatchID": JSONValue.encode(importBatchID),
            "turathID": JSONValue.encode(turathID),
            "finishedAt": JSONValue.encode(finishedAt),
            "rating": JSONValue.encode(rating),
            "review": JSONValue.encode(review),
            "readCount": JSONValue.encode(readCount),
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
        title = try record.decode("title", as: String.self)
        author = try record.decode("author", as: String.self)
        editor = try record.decode("editor", as: String?.self)
        edition = try record.decode("edition", as: String?.self)
        kind = try record.decode("kind", as: String.self)
        format = try record.decode("format", as: String?.self)
        shelf = try record.decode("shelf", as: String.self)
        pages = try record.decode("pages", as: Int?.self)
        locatorJSON = try record.decode("locatorJSON", as: Data?.self)
        currentPage = try record.decode("currentPage", as: Int?.self)
        tocJSON = try record.decode("tocJSON", as: Data?.self)
        language = try record.decode("language", as: String.self)
        mediaID = try record.decode("mediaID", as: UUID?.self)
        fileHash = try record.decode("fileHash", as: String?.self)
        isbn13 = try record.decode("isbn13", as: String?.self)
        sourceGoodreadsID = try record.decode("sourceGoodreadsID", as: String?.self)
        importBatchID = try record.decode("importBatchID", as: UUID?.self)
        turathID = try record.decode("turathID", as: Int?.self)
        finishedAt = try record.decode("finishedAt", as: Date?.self)
        rating = try record.decode("rating", as: Int?.self)
        review = try record.decode("review", as: String?.self)
        readCount = try record.decode("readCount", as: Int.self)
    }
}
@Model public final class ReadingSession {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var bookID: UUID? = nil
    public var start: Date = Date()
    public var end: Date? = nil
    public var activeSeconds: Int = 0
    public var fromPage: Int = 0
    public var toPage: Int = 0
    public var startLocatorJSON: Data? = nil
    public var endLocatorJSON: Data? = nil
    public var startProgression: Double = 0.0
    public var endProgression: Double = 0.0
    public var pagesCounted: Int = 0
    public var source: String = "reader"
    public var dayKey: String = ""
    public var tzID: String = ""
    public var dayPolicy: String = ""
    public init() {}
}
extension ReadingSession: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "ReadingSession", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "bookID": JSONValue.encode(bookID),
            "start": JSONValue.encode(start),
            "end": JSONValue.encode(end),
            "activeSeconds": JSONValue.encode(activeSeconds),
            "fromPage": JSONValue.encode(fromPage),
            "toPage": JSONValue.encode(toPage),
            "startLocatorJSON": JSONValue.encode(startLocatorJSON),
            "endLocatorJSON": JSONValue.encode(endLocatorJSON),
            "startProgression": JSONValue.encode(startProgression),
            "endProgression": JSONValue.encode(endProgression),
            "pagesCounted": JSONValue.encode(pagesCounted),
            "source": JSONValue.encode(source),
            "dayKey": JSONValue.encode(dayKey),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
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
        bookID = try record.decode("bookID", as: UUID?.self)
        start = try record.decode("start", as: Date.self)
        end = try record.decode("end", as: Date?.self)
        activeSeconds = try record.decode("activeSeconds", as: Int.self)
        fromPage = try record.decode("fromPage", as: Int.self)
        toPage = try record.decode("toPage", as: Int.self)
        startLocatorJSON = try record.decode("startLocatorJSON", as: Data?.self)
        endLocatorJSON = try record.decode("endLocatorJSON", as: Data?.self)
        startProgression = try record.decode("startProgression", as: Double.self)
        endProgression = try record.decode("endProgression", as: Double.self)
        pagesCounted = try record.decode("pagesCounted", as: Int.self)
        source = try record.decode("source", as: String.self)
        dayKey = try record.decode("dayKey", as: String.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
    }
}
@Model public final class Highlight {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var bookID: UUID? = nil
    public var locatorJSON: Data = Data()
    public var pageLabel: String? = nil
    public var color: String = ""
    public var note: String? = nil
    public init() {}
}
extension Highlight: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Highlight", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "bookID": JSONValue.encode(bookID),
            "locatorJSON": JSONValue.encode(locatorJSON),
            "pageLabel": JSONValue.encode(pageLabel),
            "color": JSONValue.encode(color),
            "note": JSONValue.encode(note),
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
        bookID = try record.decode("bookID", as: UUID?.self)
        locatorJSON = try record.decode("locatorJSON", as: Data.self)
        pageLabel = try record.decode("pageLabel", as: String?.self)
        color = try record.decode("color", as: String.self)
        note = try record.decode("note", as: String?.self)
    }
}
@Model public final class NotebookNote {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var text: String = ""
    public var link: String = "general"
    public var targetID: UUID? = nil
    public var page: Int? = nil
    public var locatorJSON: Data? = nil
    public var isPrivate: Bool = false
    public init() {}
}
extension NotebookNote: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "NotebookNote", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "text": JSONValue.encode(text),
            "link": JSONValue.encode(link),
            "targetID": JSONValue.encode(targetID),
            "page": JSONValue.encode(page),
            "locatorJSON": JSONValue.encode(locatorJSON),
            "isPrivate": JSONValue.encode(isPrivate),
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
        text = try record.decode("text", as: String.self)
        link = try record.decode("link", as: String.self)
        targetID = try record.decode("targetID", as: UUID?.self)
        page = try record.decode("page", as: Int?.self)
        locatorJSON = try record.decode("locatorJSON", as: Data?.self)
        isPrivate = try record.decode("isPrivate", as: Bool.self)
    }
}
@Model public final class HadithProgress {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var collectionID: String = ""
    public var number: Int = 0
    public var editionID: String = ""
    public var readAt: Date? = nil
    public var understood: Bool = false
    public var understoodDayKey: String? = nil
    public var returnTo: Bool = false
    public var layersOpened: [String] = []
    public init() {}
}
extension HadithProgress: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HadithProgress", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "collectionID": JSONValue.encode(collectionID),
            "number": JSONValue.encode(number),
            "editionID": JSONValue.encode(editionID),
            "readAt": JSONValue.encode(readAt),
            "understood": JSONValue.encode(understood),
            "understoodDayKey": JSONValue.encode(understoodDayKey),
            "returnTo": JSONValue.encode(returnTo),
            "layersOpened": JSONValue.encode(layersOpened),
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
        collectionID = try record.decode("collectionID", as: String.self)
        number = try record.decode("number", as: Int.self)
        editionID = try record.decode("editionID", as: String.self)
        readAt = try record.decode("readAt", as: Date?.self)
        understood = try record.decode("understood", as: Bool.self)
        understoodDayKey = try record.decode("understoodDayKey", as: String?.self)
        returnTo = try record.decode("returnTo", as: Bool.self)
        layersOpened = try record.decode("layersOpened", as: [String].self)
    }
}
@Model public final class UserWord {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var word: String = ""
    public var language: String = "ar"
    public var meaning: String? = nil
    public var meaningSource: String = "none"
    public var bookID: UUID? = nil
    public var bookTitle: String = ""
    public var locatorJSON: Data? = nil
    public var context: String = ""
    public var savedAt: Date = Date()
    public init() {}
}
extension UserWord: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "UserWord", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "word": JSONValue.encode(word),
            "language": JSONValue.encode(language),
            "meaning": JSONValue.encode(meaning),
            "meaningSource": JSONValue.encode(meaningSource),
            "bookID": JSONValue.encode(bookID),
            "bookTitle": JSONValue.encode(bookTitle),
            "locatorJSON": JSONValue.encode(locatorJSON),
            "context": JSONValue.encode(context),
            "savedAt": JSONValue.encode(savedAt),
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
        word = try record.decode("word", as: String.self)
        language = try record.decode("language", as: String.self)
        meaning = try record.decode("meaning", as: String?.self)
        meaningSource = try record.decode("meaningSource", as: String.self)
        bookID = try record.decode("bookID", as: UUID?.self)
        bookTitle = try record.decode("bookTitle", as: String.self)
        locatorJSON = try record.decode("locatorJSON", as: Data?.self)
        context = try record.decode("context", as: String.self)
        savedAt = try record.decode("savedAt", as: Date.self)
    }
}
@Model public final class Habit {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var name: String = ""
    public var icon: String = ""
    public var color: String = ""
    public var kind: String = "custom"
    public var linkedSource: String? = nil
    public var reminder: String = "dot"
    public var homeOnly: Bool = false
    public var startDate: Date = Date()
    public var order: Int = 0
    public var archivedAt: Date? = nil
    public init() {}
}
extension Habit: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "Habit", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "icon": JSONValue.encode(icon),
            "color": JSONValue.encode(color),
            "kind": JSONValue.encode(kind),
            "linkedSource": JSONValue.encode(linkedSource),
            "reminder": JSONValue.encode(reminder),
            "homeOnly": JSONValue.encode(homeOnly),
            "startDate": JSONValue.encode(startDate),
            "order": JSONValue.encode(order),
            "archivedAt": JSONValue.encode(archivedAt),
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
        name = try record.decode("name", as: String.self)
        icon = try record.decode("icon", as: String.self)
        color = try record.decode("color", as: String.self)
        kind = try record.decode("kind", as: String.self)
        linkedSource = try record.decode("linkedSource", as: String?.self)
        reminder = try record.decode("reminder", as: String.self)
        homeOnly = try record.decode("homeOnly", as: Bool.self)
        startDate = try record.decode("startDate", as: Date.self)
        order = try record.decode("order", as: Int.self)
        archivedAt = try record.decode("archivedAt", as: Date?.self)
    }
}
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
extension HabitPolicy: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HabitPolicy", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "habitID": JSONValue.encode(habitID),
            "effectiveFrom": JSONValue.encode(effectiveFrom),
            "frequency": JSONValue.encode(frequency),
            "weekdays": JSONValue.encode(weekdays),
            "monthDays": JSONValue.encode(monthDays),
            "monthCalendar": JSONValue.encode(monthCalendar),
            "yearMonth": JSONValue.encode(yearMonth),
            "yearDay": JSONValue.encode(yearDay),
            "measure": JSONValue.encode(measure),
            "unit": JSONValue.encode(unit),
            "target": JSONValue.encode(target),
            "minimum": JSONValue.encode(minimum),
            "restWeekdays": JSONValue.encode(restWeekdays),
            "windowAnchor": JSONValue.encode(windowAnchor),
            "windowStartMin": JSONValue.encode(windowStartMin),
            "windowEndMin": JSONValue.encode(windowEndMin),
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
        habitID = try record.decode("habitID", as: UUID?.self)
        effectiveFrom = try record.decode("effectiveFrom", as: String.self)
        frequency = try record.decode("frequency", as: String.self)
        weekdays = try record.decode("weekdays", as: [String]?.self)
        monthDays = try record.decode("monthDays", as: [Int]?.self)
        monthCalendar = try record.decode("monthCalendar", as: String?.self)
        yearMonth = try record.decode("yearMonth", as: Int?.self)
        yearDay = try record.decode("yearDay", as: Int?.self)
        measure = try record.decode("measure", as: String.self)
        unit = try record.decode("unit", as: String?.self)
        target = try record.decode("target", as: Int?.self)
        minimum = try record.decode("minimum", as: Int?.self)
        restWeekdays = try record.decode("restWeekdays", as: [String]?.self)
        windowAnchor = try record.decode("windowAnchor", as: String?.self)
        windowStartMin = try record.decode("windowStartMin", as: Int?.self)
        windowEndMin = try record.decode("windowEndMin", as: Int?.self)
    }
}
@Model public final class HabitPause {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var habitID: UUID? = nil
    public var fromDayKey: String = ""
    public var toDayKey: String? = nil
    public var reason: String = "freeze"
    public var tripID: UUID? = nil
    public init() {}
}
extension HabitPause: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HabitPause", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "habitID": JSONValue.encode(habitID),
            "fromDayKey": JSONValue.encode(fromDayKey),
            "toDayKey": JSONValue.encode(toDayKey),
            "reason": JSONValue.encode(reason),
            "tripID": JSONValue.encode(tripID),
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
        habitID = try record.decode("habitID", as: UUID?.self)
        fromDayKey = try record.decode("fromDayKey", as: String.self)
        toDayKey = try record.decode("toDayKey", as: String?.self)
        reason = try record.decode("reason", as: String.self)
        tripID = try record.decode("tripID", as: UUID?.self)
    }
}
@Model public final class HabitLog {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var habitID: UUID? = nil
    public var periodKey: String = ""
    public var value: Int = 0
    public var eventAt: Date = Date()
    public var tzID: String = ""
    public var dayPolicy: String = ""
    public init() {}
}
extension HabitLog: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HabitLog", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "habitID": JSONValue.encode(habitID),
            "periodKey": JSONValue.encode(periodKey),
            "value": JSONValue.encode(value),
            "eventAt": JSONValue.encode(eventAt),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
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
        habitID = try record.decode("habitID", as: UUID?.self)
        periodKey = try record.decode("periodKey", as: String.self)
        value = try record.decode("value", as: Int.self)
        eventAt = try record.decode("eventAt", as: Date.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
    }
}
@Model public final class HabitEvent {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var habitID: UUID? = nil
    public var periodKey: String = ""
    public var eventAt: Date = Date()
    public var tzID: String = ""
    public var dayPolicy: String = ""
    public var delta: Int = 0
    public var dayKey: String = ""
    public var unit: String? = nil
    public var calendarSource: String? = nil
    public var calendarOffset: Int? = nil
    public var weekStart: String? = nil
    public init() {}
}
extension HabitEvent: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "HabitEvent", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "habitID": JSONValue.encode(habitID),
            "periodKey": JSONValue.encode(periodKey),
            "eventAt": JSONValue.encode(eventAt),
            "tzID": JSONValue.encode(tzID),
            "dayPolicy": JSONValue.encode(dayPolicy),
            "delta": JSONValue.encode(delta),
            "dayKey": JSONValue.encode(dayKey),
            "unit": JSONValue.encode(unit),
            "calendarSource": JSONValue.encode(calendarSource),
            "calendarOffset": JSONValue.encode(calendarOffset),
            "weekStart": JSONValue.encode(weekStart),
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
        habitID = try record.decode("habitID", as: UUID?.self)
        periodKey = try record.decode("periodKey", as: String.self)
        eventAt = try record.decode("eventAt", as: Date.self)
        tzID = try record.decode("tzID", as: String.self)
        dayPolicy = try record.decode("dayPolicy", as: String.self)
        delta = try record.decode("delta", as: Int.self)
        dayKey = try record.decode("dayKey", as: String.self)
        unit = try record.decode("unit", as: String?.self)
        calendarSource = try record.decode("calendarSource", as: String?.self)
        calendarOffset = try record.decode("calendarOffset", as: Int?.self)
        weekStart = try record.decode("weekStart", as: String?.self)
    }
}
@Model public final class WidgetConfig {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var name: String = ""
    public var familyID: String? = nil
    public var items: [String] = []
    public var styleJSON: Data = Data()
    public init() {}
}
extension WidgetConfig: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "WidgetConfig", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "name": JSONValue.encode(name),
            "familyID": JSONValue.encode(familyID),
            "items": JSONValue.encode(items),
            "styleJSON": JSONValue.encode(styleJSON),
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
        name = try record.decode("name", as: String.self)
        familyID = try record.decode("familyID", as: String?.self)
        items = try record.decode("items", as: [String].self)
        styleJSON = try record.decode("styleJSON", as: Data.self)
    }
}
@Model public final class DeviceSetting {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var key: String = ""
    public var valueJSON: Data = Data()
    public init() {}
}
extension DeviceSetting: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "DeviceSetting", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "key": JSONValue.encode(key),
            "valueJSON": JSONValue.encode(valueJSON),
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
        key = try record.decode("key", as: String.self)
        valueJSON = try record.decode("valueJSON", as: Data.self)
    }
}
@Model public final class NotificationLedger {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var dayKey: String = ""
    public var requestID: String = ""
    public var room: String = ""
    public var kind: String = ""
    public var requestClass: String = ""
    public var scheduledFor: Date = Date()
    public var state: String = "submitted"
    public var reason: String? = nil
    public init() {}
}
extension NotificationLedger: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "NotificationLedger", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "dayKey": JSONValue.encode(dayKey),
            "requestID": JSONValue.encode(requestID),
            "room": JSONValue.encode(room),
            "kind": JSONValue.encode(kind),
            "requestClass": JSONValue.encode(requestClass),
            "scheduledFor": JSONValue.encode(scheduledFor),
            "state": JSONValue.encode(state),
            "reason": JSONValue.encode(reason),
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
        requestID = try record.decode("requestID", as: String.self)
        room = try record.decode("room", as: String.self)
        kind = try record.decode("kind", as: String.self)
        requestClass = try record.decode("requestClass", as: String.self)
        scheduledFor = try record.decode("scheduledFor", as: Date.self)
        state = try record.decode("state", as: String.self)
        reason = try record.decode("reason", as: String?.self)
    }
}
@Model public final class CommandReceipt {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var commandID: UUID? = nil
    public var name: String = ""
    public var payloadHash: String = ""
    public var source: String = "app"
    public var issuedAt: Date = Date()
    public var status: String = "applied"
    public var undoJSON: Data? = nil
    public var expiresAt: Date = Date()
    public var undoExpiresAt: Date? = nil
    public init() {}
}
extension CommandReceipt: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "CommandReceipt", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "commandID": JSONValue.encode(commandID),
            "name": JSONValue.encode(name),
            "payloadHash": JSONValue.encode(payloadHash),
            "source": JSONValue.encode(source),
            "issuedAt": JSONValue.encode(issuedAt),
            "status": JSONValue.encode(status),
            "undoJSON": JSONValue.encode(undoJSON),
            "expiresAt": JSONValue.encode(expiresAt),
            "undoExpiresAt": JSONValue.encode(undoExpiresAt),
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
        commandID = try record.decode("commandID", as: UUID?.self)
        name = try record.decode("name", as: String.self)
        payloadHash = try record.decode("payloadHash", as: String.self)
        source = try record.decode("source", as: String.self)
        issuedAt = try record.decode("issuedAt", as: Date.self)
        status = try record.decode("status", as: String.self)
        undoJSON = try record.decode("undoJSON", as: Data?.self)
        expiresAt = try record.decode("expiresAt", as: Date.self)
        undoExpiresAt = try record.decode("undoExpiresAt", as: Date?.self)
    }
}
@Model public final class PageSchedule {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var page: Int = 1
    public var memorizedAt: Date? = nil
    public var stage: Int = 0
    public var ease: Double = 1.0
    public var nextDue: String? = nil
    public var lastReviewedAt: Date? = nil
    public var lastGrade: String? = nil
    public var scheduleVersion: Int = 0
    public init() {}
}
extension PageSchedule: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "PageSchedule", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "page": JSONValue.encode(page),
            "memorizedAt": JSONValue.encode(memorizedAt),
            "stage": JSONValue.encode(stage),
            "ease": JSONValue.encode(ease),
            "nextDue": JSONValue.encode(nextDue),
            "lastReviewedAt": JSONValue.encode(lastReviewedAt),
            "lastGrade": JSONValue.encode(lastGrade),
            "scheduleVersion": JSONValue.encode(scheduleVersion),
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
        page = try record.decode("page", as: Int.self)
        memorizedAt = try record.decode("memorizedAt", as: Date?.self)
        stage = try record.decode("stage", as: Int.self)
        ease = try record.decode("ease", as: Double.self)
        nextDue = try record.decode("nextDue", as: String?.self)
        lastReviewedAt = try record.decode("lastReviewedAt", as: Date?.self)
        lastGrade = try record.decode("lastGrade", as: String?.self)
        scheduleVersion = try record.decode("scheduleVersion", as: Int.self)
    }
}
@Model public final class SessionDraft {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var kind: String = "hifz"
    public var dayKey: String = ""
    public var startedAt: Date = Date()
    public var portionJSON: Data = Data()
    public var cursorJSON: Data = Data()
    public var provisionalJSON: Data = Data()
    public init() {}
}
extension SessionDraft: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "SessionDraft", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "kind": JSONValue.encode(kind),
            "dayKey": JSONValue.encode(dayKey),
            "startedAt": JSONValue.encode(startedAt),
            "portionJSON": JSONValue.encode(portionJSON),
            "cursorJSON": JSONValue.encode(cursorJSON),
            "provisionalJSON": JSONValue.encode(provisionalJSON),
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
        kind = try record.decode("kind", as: String.self)
        dayKey = try record.decode("dayKey", as: String.self)
        startedAt = try record.decode("startedAt", as: Date.self)
        portionJSON = try record.decode("portionJSON", as: Data.self)
        cursorJSON = try record.decode("cursorJSON", as: Data.self)
        provisionalJSON = try record.decode("provisionalJSON", as: Data.self)
    }
}
@Model public final class ProcessingJob {
    public var id: UUID = UUID()
    public var createdAt: Date = Date()
    public var updatedAt: Date = Date()
    public var deletedAt: Date? = nil
    public var writerID: String = ""
    public var mergedInto: UUID? = nil
    public var deletionBarrierAt: Date? = nil
    public var restoredAt: Date? = nil
    public var bookID: UUID? = nil
    public var kind: String = "ocr"
    public var state: String = "queued"
    public var totalPages: Int = 0
    public var donePages: Int = 0
    public var checkpoint: Int = 0
    public var engine: String = ""
    public var error: String? = nil
    public init() {}
}
extension ProcessingJob: MadarRecordModel {
    public func record() throws -> DataRecord {
        try DataRecord(model: "ProcessingJob", fields: [
            "id": JSONValue.encode(id),
            "createdAt": JSONValue.encode(createdAt),
            "updatedAt": JSONValue.encode(updatedAt),
            "deletedAt": JSONValue.encode(deletedAt),
            "writerID": JSONValue.encode(writerID),
            "mergedInto": JSONValue.encode(mergedInto),
            "deletionBarrierAt": JSONValue.encode(deletionBarrierAt),
            "restoredAt": JSONValue.encode(restoredAt),
            "bookID": JSONValue.encode(bookID),
            "kind": JSONValue.encode(kind),
            "state": JSONValue.encode(state),
            "totalPages": JSONValue.encode(totalPages),
            "donePages": JSONValue.encode(donePages),
            "checkpoint": JSONValue.encode(checkpoint),
            "engine": JSONValue.encode(engine),
            "error": JSONValue.encode(error),
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
        bookID = try record.decode("bookID", as: UUID?.self)
        kind = try record.decode("kind", as: String.self)
        state = try record.decode("state", as: String.self)
        totalPages = try record.decode("totalPages", as: Int.self)
        donePages = try record.decode("donePages", as: Int.self)
        checkpoint = try record.decode("checkpoint", as: Int.self)
        engine = try record.decode("engine", as: String.self)
        error = try record.decode("error", as: String?.self)
    }
}
