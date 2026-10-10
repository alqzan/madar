import Foundation
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct DataTests {
    @Test func schemaAndDefaultContainer() throws {
        #expect(MadarSchema.syncedTypes.count == 55); #expect(MadarSchema.deviceTypes.count == 6)
        let container = try MadarContainerFactory.makeInMemory(); try fixture(container.mainContext)
        #expect(try Set(RecordBridge.all(container.mainContext).map(\.model)).count == 55)
    }
    @Test func diskPersistenceAndNewerVersionGuard() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MadarDataTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at:url) }
        func write() throws { let c = try MadarContainerFactory.makeLocal(at:url); let store = try SettingsStore(context:c.mainContext); try store.set(.string("western"),for:"core.numerals") }
        try write()
        let c = try MadarContainerFactory.makeLocal(at:url); let store = try SettingsStore(context:c.mainContext)
        #expect(try store.value(for:"core.numerals") == .string("western"))
        try JSONEncoder().encode(99).write(to:url.appendingPathComponent("SchemaVersion.json"))
        #expect(throws:DataError.newerStore) { try MadarContainerFactory.makeLocal(at:url) }
    }
    @Test func stickyDeletionAndExplicitRestore() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let deleted = PrayerLog(); deleted.dayKey = "2026-10-10"; deleted.deletedAt = Date(timeIntervalSince1970:100); deleted.updatedAt = Date(timeIntervalSince1970:100)
        let stale = PrayerLog(); stale.dayKey = deleted.dayKey; stale.updatedAt = Date(timeIntervalSince1970:900)
        context.insert(deleted); context.insert(stale); try context.save()
        let merger = RowMerger(context:context); #expect(try merger.run() > 0)
        let winner = try context.fetch(FetchDescriptor<PrayerLog>()).first { $0.mergedInto == nil }!
        #expect(winner.deletedAt != nil); #expect(try merger.run() == 0)
        try merger.restore(model:"PrayerLog",id:winner.id,now:Date(timeIntervalSince1970:1000))
        #expect(winner.deletedAt == nil); #expect(winner.deletionBarrierAt != nil); #expect(winner.restoredAt != nil)
        let laterStale = PrayerLog(); laterStale.dayKey = deleted.dayKey; laterStale.updatedAt = Date(timeIntervalSince1970:5000); context.insert(laterStale); try context.save(); try merger.run()
        #expect(try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.mergedInto == nil && $0.deletedAt == nil }.count == 1)
    }
    @Test func deterministicWinnerAndAliasForeignKey() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let a = HifzSession(); let b = HifzSession(); let commit = UUID(); a.commitID = commit; b.commitID = commit; a.updatedAt = Date(timeIntervalSince1970:10); b.updatedAt = a.updatedAt; a.writerID = "A"; b.writerID = "B"
        let grade = PageGrade(); grade.sessionID = a.id; context.insert(a); context.insert(b); context.insert(grade); try context.save(); try RowMerger(context:context).run()
        #expect(a.mergedInto == b.id); #expect(grade.sessionID == b.id)
        let late = PageGrade(); late.sessionID = a.id; late.page = 2; context.insert(late); try context.save(); try RowMerger(context:context).run(); #expect(late.sessionID == b.id)
    }
    @Test func test_M0S1_RD2_entryDeletionRetainsMarginsAndSharedMedia() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let media = Media(); let entry = Entry(); let other = Entry(); entry.mediaID = media.id; other.mediaID = media.id
        let note = MarginNote(); note.targetEntryID = entry.id; note.targetDayKey = "2020-01-01"; note.writtenDayKey = "2026-10-10"; note.text = "هامش محفوظ"; entry.deletedAt = Date()
        let before = try note.record()
        for row in [media as any PersistentModel,entry,other,note] { context.insert(row) }; try context.save(); try RowMerger(context:context).run()
        #expect(try note.record() == before); #expect(media.deletedAt == nil)
        #expect(try RowMerger(context:context).run() == 0)
    }
    @Test func test_M0S1_RD2_bookDeletionRetainsHistoryTitleAndFile() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let media = Media(); media.data = Data([1,2,3])
        let book = Book(); book.title = "كتاب محفوظ"; book.mediaID = media.id; book.deletedAt = Date(timeIntervalSince1970:100)
        let session = ReadingSession(); session.bookID = book.id; session.dayKey = "2026-10-09"; session.activeSeconds = 60; session.pagesCounted = 2
        let highlight = Highlight(); highlight.bookID = book.id
        let sessionBefore = try session.record(), highlightBefore = try highlight.record(), mediaBefore = try media.record()
        for row in [media as any PersistentModel,book,session,highlight] { context.insert(row) }; try context.save()
        let merger = RowMerger(context:context); try merger.run()
        #expect(book.title == "كتاب محفوظ"); #expect(book.deletedAt != nil)
        #expect(try session.record() == sessionBefore); #expect(try highlight.record() == highlightBefore); #expect(try media.record() == mediaBefore)
        #expect(try merger.run() == 0)
    }
    @Test func test_M0S1_RD2_oldCascadeChildrenRequireExplicitRestore() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let deletion = Date(timeIntervalSince1970:100)
        let entry = Entry(); entry.deletedAt = deletion
        let book = Book(); book.deletedAt = deletion; book.title = "عنوان محذوف"
        let note = MarginNote(); note.targetEntryID = entry.id; note.deletedAt = deletion; note.deletionBarrierAt = deletion
        let session = ReadingSession(); session.bookID = book.id; session.deletedAt = deletion; session.deletionBarrierAt = deletion
        let highlight = Highlight(); highlight.bookID = book.id; highlight.deletedAt = deletion; highlight.deletionBarrierAt = deletion
        for row in [entry as any PersistentModel,book,note,session,highlight] { context.insert(row) }; try context.save()
        let merger = RowMerger(context:context); try merger.run()
        try merger.restore(model:"Entry",id:entry.id,now:deletion.addingTimeInterval(10))
        try merger.restore(model:"Book",id:book.id,now:deletion.addingTimeInterval(10))
        // A later ordinary write/import cannot revive old cascade tombstones.
        note.deletedAt = nil; session.deletedAt = nil; highlight.deletedAt = nil
        note.updatedAt = deletion.addingTimeInterval(100); session.updatedAt = note.updatedAt; highlight.updatedAt = note.updatedAt
        try context.save(); try merger.run()
        #expect(note.deletedAt == deletion); #expect(session.deletedAt == deletion); #expect(highlight.deletedAt == deletion)
        #expect(note.restoredAt == nil && session.restoredAt == nil && highlight.restoredAt == nil)
        #expect(try merger.run() == 0)
        try merger.restore(model:"MarginNote",id:note.id,now:deletion.addingTimeInterval(200))
        #expect(note.deletedAt == nil); #expect(session.deletedAt == deletion && highlight.deletedAt == deletion)
    }
    @Test func fieldExceptionsAndMoneyIdentity() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let h = UUID(); let a = HabitLog(); a.habitID = h; a.periodKey = "2026-10-10"; a.value = 7
        let b = HabitLog(); b.habitID = h; b.periodKey = a.periodKey; b.value = 2; b.updatedAt = a.updatedAt.addingTimeInterval(10)
        let t1 = Transaction(); let t2 = Transaction(); context.insert(a); context.insert(b); context.insert(t1); context.insert(t2); try context.save(); try RowMerger(context:context).run()
        #expect(b.value == 7); #expect(t1.mergedInto == nil && t2.mergedInto == nil)
    }
    @Test func dayOneBranchStableAndKeepBoth() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let canonical = Data("incoming version two".utf8); let branch = StableIdentity.dayOneBranch(canonicalSource:canonical)
        let primary = Entry(); primary.source = "dayOne"; primary.sourceID = "source-1"; primary.text = "local edit"
        let imported = Entry(); imported.source = "dayOne"; imported.sourceID = "source-1"; imported.sourceBranch = branch; imported.text = "incoming version two"
        let again = Entry(); again.source = "dayOne"; again.sourceID = "source-1"; again.sourceBranch = StableIdentity.dayOneBranch(canonicalSource:canonical)
        context.insert(primary); context.insert(imported); context.insert(again); try context.save(); try RowMerger(context:context).run()
        #expect(try context.fetch(FetchDescriptor<Entry>()).filter { $0.mergedInto == nil && $0.deletedAt == nil }.count == 2); #expect(try RowMerger(context:context).run() == 0)
    }
    @Test func settingsDefaultsPersistenceAndInvalidRejection() throws {
        let c = try MadarContainerFactory.makeInMemory(); let store = try SettingsStore(context:c.mainContext)
        #expect(store.schema.settings.count == 127); #expect(try store.value(for:"core.firstCalendar") == .string("hijri"))
        #expect(throws:DataError.invalidValue("core.hijriOffset")) { try store.set(.number(9),for:"core.hijriOffset") }
        let undo = try store.set(.number(1),for:"core.hijriOffset"); #expect(try store.value(for:"core.hijriOffset") == .number(1)); try store.undo(undo); #expect(try store.value(for:"core.hijriOffset") == .number(0))
        let bad = Setting(); bad.key = "core.firstCalendar"; bad.valueJSON = Data("\"garbage\"".utf8); c.mainContext.insert(bad); try c.mainContext.save(); #expect(try store.value(for:bad.key) == .string("hijri"))
    }
    @Test func presetImmediateUndoAndExactDeadlineAndReceiptLifetime() throws {
        let c = try MadarContainerFactory.makeInMemory(); let store = try SettingsStore(context:c.mainContext); let now = Date(timeIntervalSince1970:100000)
        let token = try store.applyPreset(settings:["core.numerals":.string("western")],now:now)
        #expect(token.expiresAt == now.addingTimeInterval(60)); let receipt = try c.mainContext.fetch(FetchDescriptor<CommandReceipt>()).first!; #expect(receipt.expiresAt == now.addingTimeInterval(7*86400))
        try store.undo(token,now:now.addingTimeInterval(1)); #expect(try store.value(for:"core.numerals") == .string("arabicIndic"))
        let second = try store.applyPreset(settings:["core.numerals":.string("western")],now:now)
        #expect(throws:DataError.undoExpired) { try store.undo(second,now:now.addingTimeInterval(60)) }
    }
    @Test func presetInvalidIsAtomicAndDeviceSettingSeparate() throws {
        let c = try MadarContainerFactory.makeInMemory(); let store = try SettingsStore(context:c.mainContext)
        #expect(throws:(any Error).self) { try store.applyPreset(settings:["core.numerals":.string("western"),"core.dayStart":.string("midnight")]) }
        #expect(try store.value(for:"core.numerals") == .string("arabicIndic"))
        try store.set(.string("dark"),for:"core.theme")
        #expect(try c.mainContext.fetchCount(FetchDescriptor<DeviceSetting>()) == 2); #expect(try RecordBridge.all(c.mainContext).allSatisfy { $0.model != "DeviceSetting" })
    }
    @Test func batchDependentSettingsAndUndoAreAtomic() throws {
        let c = try MadarContainerFactory.makeInMemory(); let store = try SettingsStore(context:c.mainContext)
        let token = try store.applyPreset(settings:["tabbar.items":.array([.string("salah"),.string("notes")]),"tabbar.searchTab":.bool(true)])
        #expect(try store.value(for:"tabbar.searchTab") == .bool(true)); try store.undo(token)
        #expect(try store.value(for:"tabbar.searchTab") == .bool(false)); #expect(try store.value(for:"tabbar.items").array?.count == 4)
    }
    @Test func backupAllModelsMediaAndRepeatedMerge() throws {
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext)
        let records = try RecordBridge.all(source.mainContext)
        let data = try BackupCodec.export(records:records,passphrase:"correct long password")
        let backup = try BackupCodec.validate(data,passphrase:"correct long password")
        #expect(Set(backup.records) == Set(records)); #expect(backup.manifest.counts.count == 55)
        let target = try MadarContainerFactory.makeInMemory(); #expect(try BackupRestore.merge(backup,into:target.mainContext) == records.count)
        #expect(try BackupRestore.merge(backup,into:target.mainContext) == 0)
    }
    @Test func backupCorruptionRejectedWithoutDestinationWrites() throws {
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext)
        let data = try BackupCodec.export(records:RecordBridge.all(source.mainContext),passphrase:"correct long password")
        let target = try MadarContainerFactory.makeInMemory(); let original = try RecordBridge.all(target.mainContext)
        #expect(throws:(any Error).self) { try BackupCodec.validate(data,passphrase:"wrong password") }
        #expect(throws:(any Error).self) { try BackupCodec.validate(Data(data.dropLast()),passphrase:"correct long password") }
        var flipped = data; flipped[flipped.count-30] ^= 0xff
        #expect(throws:(any Error).self) { try BackupCodec.validate(flipped,passphrase:"correct long password") }
        #expect(try RecordBridge.all(target.mainContext) == original)
    }
    @Test func identicalUUIDSeedsReconcileWithoutSelfAliasWinner() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let a = Envelope(); let b = Envelope(); a.role = "reserve"; b.role = "reserve"; a.id = StableIdentity.uuid(for:"Envelope:reserve"); b.id = a.id; a.writerID = "A"; b.writerID = "B"; a.updatedAt = Date(timeIntervalSince1970:10); b.updatedAt = a.updatedAt
        context.insert(a); context.insert(b); try context.save(); try RowMerger(context:context).run()
        #expect(a.mergedInto == b.id); #expect(b.mergedInto == nil); #expect(try RowMerger(context:context).run() == 0)
        #expect(try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.count == 1)
    }
    @Test func sameUUIDLaterStaleEditKeepsDeletion() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let a = Entry(); let b = Entry(); b.id = a.id; a.updatedAt = Date(timeIntervalSince1970:20); a.deletedAt = a.updatedAt; b.updatedAt = Date(timeIntervalSince1970:100)
        context.insert(a); context.insert(b); try context.save(); try RowMerger(context:context).run()
        #expect(b.mergedInto == nil); #expect(b.deletedAt != nil); #expect(a.mergedInto == b.id); #expect(try RowMerger(context:context).run() == 0)
    }
    @Test func importLinkTargetMergePreservesDeletionAndRemapsChildren() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let a = Entry(); let b = Entry(); a.deletedAt = Date(timeIntervalSince1970:20); a.updatedAt = a.deletedAt!; b.updatedAt = Date(timeIntervalSince1970:100)
        let la = ImportLink(); let lb = ImportLink(); la.sourceID = "legacy-1"; lb.sourceID = la.sourceID; la.targetModel = "Entry"; lb.targetModel = "Entry"; la.targetID = a.id; lb.targetID = b.id; lb.updatedAt = la.updatedAt.addingTimeInterval(1)
        let note = MarginNote(); note.targetEntryID = a.id
        context.insert(a); context.insert(b); context.insert(la); context.insert(lb); context.insert(note); try context.save(); try RowMerger(context:context).run()
        #expect(a.mergedInto == b.id); #expect(b.deletedAt != nil); #expect(note.targetEntryID == b.id); #expect(note.deletedAt == nil); #expect(try RowMerger(context:context).run() == 0)
    }
    @Test func singletonBarrierNormalizesAndRestoreCannotBeOrdinaryWrite() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let row = Entry(); row.deletionBarrierAt = Date(timeIntervalSince1970:100); row.updatedAt = Date(timeIntervalSince1970:500); row.deletedAt = nil; context.insert(row); try context.save()
        #expect(try RowMerger(context:context).run() == 1); #expect(row.deletedAt == row.deletionBarrierAt); #expect(try RowMerger(context:context).run() == 0)
    }
    @Test func computedNaturalKeysDoNotCollapseDifferentDatesOrWords() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let a = Cycle(); let b = Cycle(); a.start = Date(timeIntervalSince1970:100000); b.start = a.start.addingTimeInterval(86400)
        let w1 = UserWord(); let w2 = UserWord(); w1.word = "كتاب"; w2.word = "قلم"
        context.insert(a); context.insert(b); context.insert(w1); context.insert(w2); try context.save(); try RowMerger(context:context).run()
        #expect(a.mergedInto == nil && b.mergedInto == nil); #expect(w1.mergedInto == nil && w2.mergedInto == nil)
    }
    @Test func rejectedBackupLeavesDiskStoreByteIdentical() throws {
        let source = try MadarContainerFactory.makeInMemory(); try fixture(source.mainContext)
        let backup = try BackupCodec.export(records:RecordBridge.all(source.mainContext),passphrase:"correct long password")
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MadarBackupLiveTest-\(UUID())"); defer { try? FileManager.default.removeItem(at:url) }
        let live = try MadarContainerFactory.makeLocal(at:url); try fixture(live.mainContext)
        func diskBytes() throws -> [String:Data] { try Dictionary(uniqueKeysWithValues:FileManager.default.contentsOfDirectory(at:url,includingPropertiesForKeys:nil).filter { !$0.hasDirectoryPath }.map { ($0.lastPathComponent,try Data(contentsOf:$0)) }) }
        let before = try diskBytes()
        #expect(throws:(any Error).self) { try BackupCodec.validate(backup,passphrase:"bad-password") }
        #expect(throws:(any Error).self) { try BackupCodec.validate(Data(backup.dropLast(10)),passphrase:"correct long password") }
        var newer = backup
        let length = Int(newer.prefix(4).reduce(UInt64(0)) { ($0 << 8) | UInt64($1) })
        var header = String(data:newer.subdata(in:4..<4+length),encoding:.utf8)!
        header = header.replacingOccurrences(of:"\"storeSchemaVersion\":1",with:"\"storeSchemaVersion\":9")
        newer.replaceSubrange(4..<4+length,with:Data(header.utf8))
        #expect(throws:DataError.newerStore) { try BackupCodec.validate(newer,passphrase:"correct long password") }
        #expect(try diskBytes() == before)
    }
    @Test func multichunkReorderAndMissingMediaExportAreRejected() throws {
        let c = try MadarContainerFactory.makeInMemory(); try fixture(c.mainContext)
        let media = try c.mainContext.fetch(FetchDescriptor<Media>()).first!
        media.data = Data(repeating:0x58,count:2*1024*1024); media.sizeBytes = media.data!.count; media.sha256 = StableIdentity.dayOneBranch(canonicalSource:media.data!); try c.mainContext.save()
        let data = try BackupCodec.export(records:RecordBridge.all(c.mainContext),passphrase:"correct long password")
        #expect(try BackupCodec.validate(data,passphrase:"correct long password").records.count > 55)
        let headerLength = Int(data.prefix(4).reduce(UInt64(0)) { ($0<<8)|UInt64($1) })
        let start = 4+headerLength; let firstSize = Int(data.subdata(in:start..<start+4).reduce(UInt64(0)) { ($0<<8)|UInt64($1) })
        let second = start+4+firstSize; let secondSize = Int(data.subdata(in:second..<second+4).reduce(UInt64(0)) { ($0<<8)|UInt64($1) })
        var swapped = data.prefix(start); swapped.append(data.subdata(in:second..<second+4+secondSize)); swapped.append(data.subdata(in:start..<second)); swapped.append(data.suffix(from:second+4+secondSize))
        #expect(throws:DataError.authenticationFailed) { try BackupCodec.validate(Data(swapped),passphrase:"correct long password") }
        media.data = nil; try c.mainContext.save()
        #expect(throws:DataError.invalidBackup) { try BackupCodec.export(records:RecordBridge.all(c.mainContext),passphrase:"correct long password") }
    }
    @Test func writerIdentityPersistsAndEveryPreparedSettingUsesIt() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("MadarWriterTest-\(UUID())"); defer { try? FileManager.default.removeItem(at:url) }
        func write() throws -> String {
            let container = try MadarContainerFactory.makeLocal(at:url); let store = try SettingsStore(context:container.mainContext)
            #expect(!container.mainContext.hasChanges); _ = try store.value(for:"core.theme"); #expect(!container.mainContext.hasChanges)
            let identifier = try store.writerIDForWrite()
            var layout = try store.schema.definition(for:"bahw.layout").defaultValue.object!; layout["hidden"] = .array([.string("mal")])
            _ = try store.stage(["core.numerals":.string("western"),"core.theme":.string("dark"),"bahw.layout":.object(layout)])
            try container.mainContext.save()
            #expect(try container.mainContext.fetch(FetchDescriptor<Setting>()).allSatisfy { $0.writerID == identifier })
            #expect(try container.mainContext.fetch(FetchDescriptor<DeviceSetting>()).allSatisfy { $0.writerID == identifier })
            #expect(try container.mainContext.fetch(FetchDescriptor<LayoutState>()).allSatisfy { $0.writerID == identifier })
            return identifier
        }
        let original = try write(); let container = try MadarContainerFactory.makeLocal(at:url); let store = try SettingsStore(context:container.mainContext)
        #expect(try store.writerIDForWrite() == original); #expect(!container.mainContext.hasChanges)
    }
    @Test func invalidStageAndReadsNeverCreateWriterIdentity() throws {
        let container = try MadarContainerFactory.makeInMemory(); let store = try SettingsStore(context:container.mainContext)
        _ = try store.value(for:"core.numerals")
        #expect(throws:(any Error).self) { try store.stage(["core.theme":.string("dark"),"core.hijriOffset":.number(50)]) }
        #expect(!container.mainContext.hasChanges)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<DeviceSetting>()) == 0)
        #expect(try container.mainContext.fetchCount(FetchDescriptor<Setting>()) == 0)
    }
    @Test func monotonicClockAndSeedIdentity() { let previous = Date(timeIntervalSince1970:10000); #expect(StableIdentity.monotonic(now:previous.addingTimeInterval(-3600),previous:previous) > previous); #expect(StableIdentity.uuid(for:"Envelope:reserve") == StableIdentity.uuid(for:"Envelope:reserve")) }
}
