import Foundation
import SwiftData
import MadarCore
import MadarData

private struct PrayerInverse: Codable {
    let version: Int
    let before: [DataRecord]
    let after: [DataRecord]
}
/// Stages only. The caller owns the shared cross-process lease and commits the
/// mutation, inverse and durable CommandReceipt together. No save/suspension here.
@MainActor public enum PrayerMutationHandler {
    public static func stage(operation: PrayerMutation, in context: ModelContext, now: Date, writer: String, source: CommandSource = .app) throws -> Data? {
        let repository = try PrayerRepository(context: context)
        var before: [String: DataRecord] = [:], after: [String: DataRecord] = [:]
        var captured: Set<String> = []
        func key(_ row: DataRecord) -> String { row.model + ":" + row.id.uuidString }
        func capture<T: MadarRecordModel>(_ row: T) throws {
            let record = try row.record(), id = key(record)
            if captured.insert(id).inserted { before[id] = record }
        }
        func registerNew<T: MadarRecordModel>(_ row: T) throws { captured.insert(key(try row.record())) }
        var logIndex: [PrayerReference: PrayerLog] = [:], qadaIndex: [PrayerReference: QadaItem] = [:]
        for row in repository.logs { if let day = try? GregorianDay(row.dayKey), let prayer = Prayer(rawValue: row.prayer) { let ref = PrayerReference(day: day, prayer: prayer); if logIndex[ref].map({ $0.updatedAt < row.updatedAt }) ?? true { logIndex[ref] = row } } }
        for row in repository.qadaRows { if let day = try? GregorianDay(row.originalDayKey), let prayer = Prayer(rawValue: row.prayer) { let ref = PrayerReference(day: day, prayer: prayer); if qadaIndex[ref].map({ $0.updatedAt < row.updatedAt }) ?? true { qadaIndex[ref] = row } } }
        let track = try repository.tracking(at: now)
        let current = repository.prayerDay(at: now)
        func touch<T: MadarRecordModel>(_ row: T, restoringDebt: Bool = false) throws {
            var record = try row.record()
            guard record.deletedAt == nil || restoringDebt else { throw PrayerDomainError.explicitRestoreRequired }
            let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast)
            try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID")
            if record.deletedAt != nil { try record.set(max(stamp, (record.date("deletionBarrierAt") ?? .distantPast).addingTimeInterval(0.001)), for: "restoredAt"); try record.set(Optional<Date>.none, for: "deletedAt") }
            try row.apply(record)
            after[key(record)] = record
        }
        func remove<T: MadarRecordModel>(_ row: T) throws {
            try capture(row)
            var record = try row.record(); let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast)
            try record.set(stamp, for: "updatedAt"); try record.set(stamp, for: "deletedAt"); try record.set(stamp, for: "deletionBarrierAt"); try record.set(writer, for: "writerID"); try row.apply(record); after[key(record)] = record
        }
        func validate(_ ref: PrayerReference, oldAllowed: Bool = false, early: Bool = false) throws -> PrayerOccurrence? {
            guard oldAllowed || ref.day >= track.day else { throw PrayerDomainError.beforeTrackingStart }
            guard ref.day <= current else { throw PrayerDomainError.futurePrayer }
            let occurrence = repository.occurrence(ref)
            if let occurrence, occurrence.time > now && !early { throw PrayerDomainError.futurePrayer }
            return occurrence
        }
        func logRow(_ ref: PrayerReference, restoring: Bool = false) throws -> PrayerLog {
            if let old = logIndex[ref] { guard old.deletedAt == nil || restoring else { throw PrayerDomainError.explicitRestoreRequired }; try capture(old); return old }
            let row = PrayerLog(); row.id = StableIdentity.uuid(for: "PrayerLog:\(ref.day):\(ref.prayer.rawValue)"); row.dayKey = ref.day.description; row.prayer = ref.prayer.rawValue; row.createdAt = now; row.updatedAt = now; context.insert(row); try registerNew(row); logIndex[ref] = row; return row
        }
        func qadaRow(_ ref: PrayerReference) throws -> QadaItem {
            if let old = qadaIndex[ref] { try capture(old); return old }
            let row = QadaItem(); row.id = StableIdentity.uuid(for: "QadaItem:\(ref.day):\(ref.prayer.rawValue)"); row.originalDayKey = ref.day.description; row.prayer = ref.prayer.rawValue; row.createdAt = now; row.updatedAt = now; context.insert(row); try registerNew(row); qadaIndex[ref] = row; return row
        }
        func unlinkPair(_ row: PrayerLog) throws {
            guard let pairID = row.pairID else { return }
            for partner in logIndex.values where partner.pairID == pairID && partner.deletedAt == nil { try capture(partner); partner.pairID = nil; try touch(partner) }
        }
        func setLog(_ ref: PrayerReference, status: PrayerStoredStatus, heart: PrayerHeart? = nil, shortened: Bool? = nil, fridayKind: FridayPrayerKind? = nil, oldAllowed: Bool = false, early: Bool = false, recordSource: String? = nil, restoring: Bool = false) throws {
            let occurrence = try validate(ref, oldAllowed: oldAllowed, early: early)
            if status == .missed || status == .qada {
                if let windowEnd = repository.missedWindowEnd(ref) {
                    guard now >= windowEnd else { throw PrayerDomainError.prayerWindowOpen }
                } else {
                    guard status == .qada, repository.qada(ref)?.madeUpAt == nil else { throw PrayerDomainError.unavailablePrayerTimes }
                }
            }
            if shortened == true && ![.dhuhr, .asr, .isha].contains(ref.prayer) { throw PrayerDomainError.invalidShortening }
            let zone = occurrence?.place.timeZone ?? repository.place(at: now).timeZone
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            let isFridayNoon = ref.prayer == .dhuhr && calendar.component(.weekday, from: ref.day.date(in: zone)) == 6
            let existingKind = repository.log(ref)?.fridayKind.flatMap(FridayPrayerKind.init(rawValue:))
            let resolvedFridayKind = fridayKind ?? existingKind
            guard isFridayNoon || fridayKind == nil else { throw PrayerDomainError.invalidRecord }
            guard !isFridayNoon || [.unrecordedHistory, .excused].contains(status) || resolvedFridayKind != nil else { throw PrayerDomainError.invalidRecord }
            guard resolvedFridayKind != .jumuah || [.jamaah, .missed, .qada].contains(status) else { throw PrayerDomainError.invalidRecord }
            let row = try logRow(ref, restoring: restoring); try unlinkPair(row)
            row.status = status.rawValue
            if let heart { row.heart = heart.rawValue }
            if let shortened { row.shortened = shortened }
            row.fridayKind = isFridayNoon && status != .unrecordedHistory ? resolvedFridayKind?.rawValue : nil
            if status == .missed || status == .unrecordedHistory || status == .excused { row.heart = nil; row.shortened = nil }
            if row.loggedAt == nil { row.eventAt = occurrence?.time ?? now; row.tzID = occurrence?.place.timeZoneID ?? repository.place(at: now).timeZoneID; row.dayPolicy = "prayerDay@1"; row.tripID = occurrence?.tripID }
            row.loggedAt = now; row.source = recordSource ?? source.rawValue; try touch(row, restoringDebt: restoring)
            if status == .missed { let qada = try qadaRow(ref); qada.madeUpAt = nil; try touch(qada, restoringDebt: restoring) }
            else if status == .jamaah || status == .alone || status == .unrecordedHistory || status == .excused { if let qada = repository.qada(ref) { try remove(qada) } }
        }
        func makeUp(_ ref: PrayerReference, at eventAt: Date? = nil, fridayKind: FridayPrayerKind? = nil) throws {
            if repository.qada(ref)?.madeUpAt != nil { return }
            let madeUpAt = eventAt ?? now
            guard madeUpAt <= now else { throw PrayerDomainError.invalidRecord }
            let oldAllowed = repository.qada(ref) != nil
            _ = try validate(ref, oldAllowed: oldAllowed)
            try setLog(ref, status: .qada, fridayKind: fridayKind, oldAllowed: oldAllowed)
            let qada = try qadaRow(ref); qada.madeUpAt = madeUpAt; try touch(qada, restoringDebt: true)
        }
        switch operation {
        case .initializeTracking:
            let value = try repository.settings.value(for: "salah.trackingStart").object ?? [:]
            if value["dayKey"]?.string == nil {
                if let old = try context.fetch(FetchDescriptor<Setting>()).first(where: { $0.key == "salah.trackingStart" && $0.mergedInto == nil }) { guard old.deletedAt == nil else { throw PrayerDomainError.explicitRestoreRequired }; try capture(old) }
                try repository.settings.prepare(.object(["dayKey": .string(current.description), "edits": .number(0)]), for: "salah.trackingStart", now: now)
                if let row = try context.fetch(FetchDescriptor<Setting>()).first(where: { $0.key == "salah.trackingStart" && $0.mergedInto == nil }) { row.createdAt = now; row.updatedAt = now; row.writerID = writer; after[key(try row.record())] = try row.record() }
            }
        case .editTrackingStart(let start):
            guard track.edits == 0 else { throw PrayerDomainError.trackingAlreadyEdited }
            guard start >= track.firstRun.adding(days: -30), start <= track.firstRun else { throw PrayerDomainError.invalidTrackingStart }
            guard let old = try context.fetch(FetchDescriptor<Setting>()).first(where: { $0.key == "salah.trackingStart" && $0.mergedInto == nil && $0.deletedAt == nil }) else { throw PrayerDomainError.invalidTrackingStart }
            try capture(old)
            try repository.settings.prepare(.object(["dayKey": .string(start.description), "edits": .number(1)]), for: "salah.trackingStart", now: now)
            after[key(try old.record())] = try old.record()
        case .record(let ref, let status, let heart, let shortened, let fridayKind):
            guard status != .unrecordedHistory && status != .excused else { throw PrayerDomainError.invalidRecord }
            if status == .qada { try makeUp(ref, fridayKind: fridayKind); if let heart { let row = try logRow(ref); if row.heart != heart.rawValue { row.heart = heart.rawValue; try touch(row) } } }
            else {
                if let row = repository.log(ref), row.status == status.rawValue, heart == nil || row.heart == heart?.rawValue, shortened == nil || row.shortened == shortened, fridayKind == nil || row.fridayKind == fridayKind?.rawValue { break }
                try setLog(ref, status: status, heart: heart, shortened: shortened, fridayKind: fridayKind)
            }
        case .makeUp(let ref, let at, let fridayKind): try makeUp(ref, at: at, fridayKind: fridayKind)
        case .addOldMissed(let ref, let fridayKind), .restoreOldMissed(let ref, let fridayKind):
            let restoring: Bool
            if case .restoreOldMissed = operation { restoring = true } else { restoring = false }
            guard ref.day < track.day else { throw PrayerDomainError.invalidRecord }
            let needsRestore = repository.oldMissedRequiresRestore(ref)
            guard !needsRestore || restoring else { throw PrayerDomainError.explicitRestoreRequired }
            if repository.qada(ref) == nil || needsRestore { try setLog(ref, status: .missed, fridayKind: fridayKind, oldAllowed: true, restoring: restoring) }
        case .answerHeart(let ref, let heart):
            guard let row = repository.log(ref), ["jamaah", "alone", "qada"].contains(row.status) else { throw PrayerDomainError.invalidRecord }
            if row.heart != heart?.rawValue { try capture(row); row.heart = heart?.rawValue; try touch(row) }
        case .markUnrecorded(let refs):
            guard !refs.isEmpty, Set(refs).count == refs.count else { throw PrayerDomainError.invalidRecord }
            for ref in refs { if repository.log(ref)?.status != "unrecordedHistory" { try setLog(ref, status: .unrecordedHistory) } }
        case .resolveGap(let resolutions):
            guard !resolutions.isEmpty, Set(resolutions.map(\.reference)).count == resolutions.count,
                  resolutions.allSatisfy({ [.jamaah, .alone, .missed, .unrecordedHistory, .excused].contains($0.status) }) else { throw PrayerDomainError.invalidRecord }
            for resolution in resolutions {
                let ref = resolution.reference
                let row = repository.log(ref), debt = repository.qada(ref)
                let hasCurrentDebt = debt != nil && debt?.madeUpAt == nil
                let alreadyResolved = row?.status == resolution.status.rawValue && row?.fridayKind == resolution.fridayKind?.rawValue && row?.heart == nil && row?.shortened != true && (resolution.status != .missed || hasCurrentDebt) && (resolution.status == .missed || debt == nil)
                if alreadyResolved { continue }
                try setLog(ref, status: resolution.status, fridayKind: resolution.fridayKind)
            }
        case .clear(let ref):
            if let row = repository.log(ref) { try unlinkPair(row); try remove(row) }
            if let row = repository.qada(ref) { try remove(row) }
        case .agePending:
            // RP1: legacy commands remain decodable, but time passing never records
            // a religious status or debt on the user's behalf.
            return nil
        case .logPair(let day, let pair, let status, let shortened, let mode):
            guard [.jamaah, .alone].contains(status), try repository.settings.value(for: "salah.travelShortenCombine") == .bool(true), let trip = repository.activeTrip(at: now) else { throw PrayerDomainError.noActiveTrip }
            let first = PrayerReference(day: day, prayer: pair.prayers[0]), second = PrayerReference(day: day, prayer: pair.prayers[1])
            guard let times = PrayerTimesEngine.calculate(day: day, place: trip.place, options: repository.tripOptions), day == current, now >= times.time(for: mode == .taqdim ? first.prayer : second.prayer) else { throw PrayerDomainError.invalidPair }
            if let a = repository.log(first), let b = repository.log(second), a.pairID != nil, a.pairID == b.pairID, a.status == status.rawValue, b.status == status.rawValue, a.shortened == (shortened && first.prayer != .maghrib), b.shortened == shortened { break }
            let pairID = StableIdentity.uuid(for: "PrayerPair:\(day):\(pair.rawValue)")
            for ref in [first, second] {
                // Only the second of an approved taqdim pair can precede its time.
                try setLog(ref, status: status, shortened: shortened && ref.prayer != .maghrib, early: true)
                let row = try logRow(ref); row.pairID = pairID; row.tripID = trip.id; row.eventAt = times.time(for: ref.prayer); row.tzID = trip.place.timeZoneID; try touch(row)
            }
        case .logQiyam(let night, let rakaat, let witr), .restoreQiyam(let night, let rakaat, let witr):
            let restoring: Bool
            if case .restoreQiyam = operation { restoring = true } else { restoring = false }
            let latest = repository.defaultNight(at: now)
            guard night <= latest, night >= latest.adding(days: -6) else { throw PrayerDomainError.invalidNight }
            guard (0...99).contains(rakaat) else { throw PrayerDomainError.invalidRakaat }
            let old = repository.nightRows.filter { $0.nightKey == night.description }.max { $0.updatedAt < $1.updatedAt }
            if let old { guard old.deletedAt == nil || restoring else { throw PrayerDomainError.explicitRestoreRequired }; try capture(old) }
            if old?.deletedAt == nil, old?.rakaat == rakaat, old?.witr == witr { break }
            let row = old ?? QiyamNight(); if old == nil { row.id = StableIdentity.uuid(for: "QiyamNight:\(night)"); row.createdAt = now; row.updatedAt = now; context.insert(row); try registerNew(row) }
            row.nightKey = night.description; row.rakaat = rakaat; row.witr = witr
            if old == nil { row.tzID = repository.place(at: now).timeZoneID; row.dayPolicy = "prayerDay@1" }
            try touch(row, restoringDebt: restoring) // Explicit restoration retains the barrier; QuranSessionID stays untouched.
        case .startTrip(let city, let country, let place, let homeKm):
            guard repository.activeTrip(at: now) == nil else { throw PrayerDomainError.invalidRecord }
            let row = Trip(); row.city = city; row.country = country; row.lat = place.latitude; row.lon = place.longitude; row.tzID = place.timeZoneID; row.mode = "manual"; row.start = now; row.homeKm = homeKm; row.createdAt = now; row.updatedAt = now; context.insert(row); try registerNew(row); try touch(row)
        case .endTrip(let id):
            guard let row = repository.trips.first(where: { $0.id == id }) else { throw PrayerDomainError.noActiveTrip }
            if row.end == nil { try capture(row); row.end = now; try touch(row) }
        }
        let changed = after.values.filter { before[key($0)] != $0 }
        guard !changed.isEmpty else { return nil }
        let keys = Set(changed.map { $0.model + ":" + $0.id.uuidString })
        return try JSONEncoder().encode(PrayerInverse(version: 1, before: before.values.filter { keys.contains(key($0)) }.sorted { key($0) < key($1) }, after: changed.sorted { key($0) < key($1) }))
    }
    public static func undo(_ inverseData: Data, in context: ModelContext, now: Date, writer: String) throws {
        let inverse = try JSONDecoder().decode(PrayerInverse.self, from: inverseData)
        guard inverse.version == 1 else { throw PrayerDomainError.staleUndo }
        let current = try records(context)
        for expected in inverse.after {
            guard current.first(where: { $0.model == expected.model && $0.id == expected.id }) == expected else { throw PrayerDomainError.staleUndo }
        }
        for after in inverse.after {
            var restored = inverse.before.first { $0.model == after.model && $0.id == after.id } ?? after
            let stamp = StableIdentity.monotonic(now: now, previous: after.date("updatedAt") ?? now)
            try restored.set(stamp, for: "updatedAt"); try restored.set(writer, for: "writerID")
            if !inverse.before.contains(where: { $0.model == after.model && $0.id == after.id }) {
                try restored.set(stamp, for: "deletedAt"); try restored.set(stamp, for: "deletionBarrierAt")
            } else if restored.isLive, after.deletedAt != nil {
                try restored.set(after.date("deletionBarrierAt"), for: "deletionBarrierAt"); try restored.set(stamp, for: "restoredAt")
            }
            try RecordBridge.upsert(restored, in: context)
        }
    }
    private static func records(_ context: ModelContext) throws -> [DataRecord] {
        try context.fetch(FetchDescriptor<PrayerLog>()).map { try $0.record() } + context.fetch(FetchDescriptor<QadaItem>()).map { try $0.record() } + context.fetch(FetchDescriptor<QiyamNight>()).map { try $0.record() } + context.fetch(FetchDescriptor<Setting>()).filter { $0.key == "salah.trackingStart" }.map { try $0.record() } + context.fetch(FetchDescriptor<Trip>()).map { try $0.record() }
    }
}
