import Foundation
import SwiftData
import Darwin

@MainActor public final class BackupCoordinator {
    public let store: ManagedDataStore; public let backupDirectory: URL
    private let deriveCredential: @Sendable (String) async throws -> BackupCredential
    private let keyStore: any BackupKeyStore; private let lifecycle: BackupLifecycle; private let localOnly: Bool
    private var catalogURL: URL { backupDirectory.appendingPathComponent("BackupCatalog.json") }
    private var statusURL: URL { backupDirectory.appendingPathComponent("BackupStatus.json") }
    enum Checkpoint: String { case afterJournal, afterStagingSave, afterReady, afterPointer, afterHooks }
    var interruption: Checkpoint?
    /// RD4 archive budget; tests lower it to exercise book exclusion without large files.
    var bookBudget = BackupBookFiles.budget
    public init(store: ManagedDataStore, backupDirectory: URL, keyStore: any BackupKeyStore, lifecycle: BackupLifecycle = BackupLifecycle(), localOnly: Bool = true,
                deriveCredential: @escaping @Sendable (String) async throws -> BackupCredential = { passphrase in
                    try await Task.detached(priority: .userInitiated) { try BackupCredential.derive(passphrase: passphrase) }.value
                }) {
        self.store = store; self.backupDirectory = backupDirectory; self.keyStore = keyStore; self.lifecycle = lifecycle; self.localOnly = localOnly; self.deriveCredential = deriveCredential
    }
    public func hasConfiguredKey() throws -> Bool { try keyStore.exists() }
    public func configurePassphrase(_ passphrase: String, validation: @MainActor () throws -> Void = {}) async throws {
        let credential = try await deriveCredential(passphrase)
        try Task.checkCancellation(); try validation()
        try keyStore.save(credential)
    }
    /// T04: a new passphrase replaces the stored key. New backups open with it; older ones still need the passphrase they were made with.
    public func replacePassphrase(_ passphrase: String, validation: @MainActor () throws -> Void = {}) async throws {
        try await configurePassphrase(passphrase, validation: validation)
    }
    public func catalog() throws -> [BackupReceipt] {
        guard FileManager.default.fileExists(atPath:catalogURL.path) else { return [] }
        return try JSONDecoder().decode([BackupReceipt].self,from:Data(contentsOf:catalogURL)).sorted { a,b in a.createdAt == b.createdAt ? a.id.uuidString > b.id.uuidString : a.createdAt > b.createdAt }
    }
    /// RD4: the plaintext size a backup of the current data would have, shown before the user schedules one.
    public func estimatedBytes() throws -> Int { BackupBookFiles.estimatedBytes(try currentRecords()) }
    public func status() throws -> BackupStatus {
        guard FileManager.default.fileExists(atPath:statusURL.path) else { return .init(lastSuccessAt:nil,lastResult:"never",localOnly:localOnly) }
        return try JSONDecoder().decode(BackupStatus.self,from:Data(contentsOf:statusURL))
    }
    public func export(kind: BackupKind = .manual, passphrase: String? = nil, progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }, cancellation: BackupCancellation = BackupCancellation(), now: Date = Date(), authorization: @MainActor () async throws -> Void = {}) async throws -> BackupReceipt {
        let lease = try await beginOperation()
        defer { finishOperation(lease:lease) }
        do { try await authorization(); try cancellation.check(); return try await exportUnderLease(kind:kind,passphrase:passphrase,progress:progress,cancellation:cancellation,now:now) }
        catch { try? recordFailure(error); throw error }
    }
    /// Captures logical rows under the same app writer barrier as encrypted backups.
    /// The share URL points to a dedicated ZIP, never to a live managed generation.
    public func exportPlain(progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }, cancellation: BackupCancellation = BackupCancellation(), now: Date = Date(), authorization: @MainActor () async throws -> Void = {}) async throws -> URL {
        let lease = try await beginOperation()
        defer { finishOperation(lease: lease) }
        try await authorization()
        try cancellation.check()
        let rows = try currentRecords()
        try RecordValidator.validate(rows); try BackupCodec.validateTypedRows(rows)
        let exports = backupDirectory.appendingPathComponent("PlainExports")
        let directory = exports.appendingPathComponent(UUID().uuidString)
        return try await background(cancellation) {
            let bytes = try PortableExportCodec.export(records: rows, now: now, cancellation: cancellation)
            _ = try PortableExportCodec.validateContents(bytes, cancellation: cancellation)
            let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
            let destination = directory.appendingPathComponent("Madar-\(formatter.string(from: now))-plain.zip")
            let partial = directory.appendingPathComponent("Export.partial")
            var completed = false
            defer { if !completed { try? FileManager.default.removeItem(at: directory) } }
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var attributes: [FileAttributeKey: Any] = [.posixPermissions: 0o600]
            #if os(iOS)
            attributes[.protectionKey] = FileProtectionType.complete
            #endif
            guard FileManager.default.createFile(atPath: partial.path, contents: nil, attributes: attributes) else { throw DataError.invalidBackup }
            let handle = try FileHandle(forWritingTo: partial)
            do {
                var offset = 0
                while offset < bytes.count {
                    try cancellation.check()
                    let end = min(offset + 64 * 1024, bytes.count)
                    try handle.write(contentsOf: bytes.subdata(in: offset..<end)); offset = end
                    progress(.init(phase: .writing, completedUnits: Int64(offset), totalUnits: Int64(bytes.count)))
                }
                try handle.synchronize(); try handle.close(); try cancellation.check()
                guard rename(partial.path, destination.path) == 0 else { throw DataError.invalidBackup }
            } catch { try? handle.close(); throw error }
            completed = true
            // An unencrypted export lives only until the next one succeeds: earlier copies (shared, closed or left by a quit) go.
            for old in (try? FileManager.default.contentsOfDirectory(at: exports, includingPropertiesForKeys: nil)) ?? [] where old.lastPathComponent != directory.lastPathComponent {
                try? FileManager.default.removeItem(at: old)
            }
            progress(.init(phase: .completed, completedUnits: 1, totalUnits: 1))
            return destination
        }
    }
    public func preview(file: URL, passphrase: String? = nil, progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }, cancellation: BackupCancellation = BackupCancellation()) async throws -> RestorePreview {
        // T04: without a typed passphrase the key kept on this device (Keychain, this device only) opens this device's backups.
        let storedCredential = passphrase == nil ? try keyStore.load() : nil
        guard passphrase != nil || storedCredential != nil else { throw BackupOperationError.backupNotConfigured }
        let value = try await background(cancellation) {
            try cancellation.check()
            let validated = try BackupArtifact.validateContents(file: file, passphrase: passphrase, credential: storedCredential, cancellation: cancellation, progress: progress)
            return (validated, try BackupArtifact.fingerprint(file: file))
        }
        try cancellation.check(); try BackupCodec.validateTypedRows(value.0.records)
        let lease = StoreLease(lockURL:store.commandLockURL); try lease.acquire(); defer { lease.release() }
        try store.refreshIfNeeded()
        let records = try currentRecords()
        let existingKeys = Set(records.map(RecordFingerprint.key)); let backupKeys = Set(value.0.records.map(RecordFingerprint.key))
        let updates = value.0.records.filter { incoming in records.contains { current in RecordFingerprint.key(current) == RecordFingerprint.key(incoming) && current != incoming } }.count
        let dates = value.0.records.filter(\.isLive).compactMap { row in ["eventAt","endedAt","writtenAt","at","start","createdAt"].compactMap { row.date($0) }.first }
        var warnings = ["تتضمن الأعداد سجلات الحذف والأسماء البديلة.","عند الاستبدال: سيتغيّر هذا على كل أجهزتك بعد تفعيل المزامنة؛ السجلات الحالية الغائبة تصبح محذوفة."]
        if Self.hasMissingBookFiles(value.0.records) {
            warnings.append("النسخة لا تتضمن ملفات بعض الكتب. يحتفظ الاسترجاع بالملفات المطابقة الموجودة على هذا الجهاز؛ وإلا فأعد استيرادها.")
        }
        if store.isCloudBacked { warnings.append("الاستعادة إلى مخزن مرتبط بالسحاب غير متاحة حتى تُثبت المصالحة وانتشار الحذف.") }
        return .init(id:UUID(),fileURL:file,fileName:file.lastPathComponent,createdAt:value.0.manifest.createdAt,counts:Self.counts(value.0.records),currentCounts:Self.counts(records),additions:value.0.records.filter { !existingKeys.contains(RecordFingerprint.key($0)) }.count,updates:updates,deletions:records.filter { $0.isLive && !backupKeys.contains(RecordFingerprint.key($0)) }.count,earliestDate:dates.min(),latestDate:dates.max(),skippedCount:0,warnings:warnings,validated:value.0,fileHash:value.1,generationID:store.binding.generationID,currentFingerprint:try RecordFingerprint.hash(records))
    }
    public func restore(preview: RestorePreview, mode: RestoreMode, passphrase: String? = nil, progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }, cancellation: BackupCancellation = BackupCancellation(), now: Date = Date(), authorization: @MainActor () async throws -> Void = {}, validation: @MainActor () throws -> Void = {}) async throws -> RestoreResult {
        guard !store.isCloudBacked else { throw BackupOperationError.cloudRestoreUnsupported }
        let lease = try await beginOperation()
        var preserveRecovery = false; var stagedGeneration: UUID?
        defer { finishOperation(lease:lease,preserveRecovery:preserveRecovery) }
        do {
            guard !store.isCloudBacked else { throw BackupOperationError.cloudRestoreUnsupported }
            try await authorization(); try validation(); try cancellation.check()
            let fileHash = try await background(cancellation) { try BackupArtifact.fingerprint(file: preview.fileURL) }
            try validation(); try cancellation.check()
            guard fileHash == preview.fileHash, preview.generationID == store.binding.generationID else { throw BackupOperationError.stalePreview }
            let current = try currentRecords(); guard try RecordFingerprint.hash(current) == preview.currentFingerprint else { throw BackupOperationError.stalePreview }
            if let passphrase { let verified = try await background(cancellation) { try BackupArtifact.validateContents(file: preview.fileURL,passphrase:passphrase,cancellation:cancellation,progress:progress) }; guard try RecordFingerprint.hash(verified.records) == RecordFingerprint.hash(preview.validated.records) else { throw BackupOperationError.stalePreview } }
            try validation(); try cancellation.check()
            guard try hasConfiguredKey() else { throw BackupOperationError.backupNotConfigured }
            progress(.init(phase:.automaticBackup,completedUnits:0,totalUnits:1))
            let safety = try await exportUnderLease(kind:.automatic,passphrase:nil,progress:progress,cancellation:cancellation,now:now)
            progress(.init(phase:.automaticBackup,completedUnits:1,totalUnits:1)); try validation(); try cancellation.check()
            let writerContext = ModelContext(store.container); writerContext.autosaveEnabled = false
            let writer = try SettingsStore(context:writerContext).writerIDForWrite(now:now); try writerContext.save()
            let planned = try Self.plan(existing:current,incoming:preview.validated.records,mode:mode,now:now,writerID:writer)
            let id = UUID(); stagedGeneration = id
            var journal = RestoreJournal(operationID:UUID(),oldGenerationID:store.binding.generationID,newGenerationID:id,phase:.preparing,hooksPending:true)
            try DurableFiles.encode(journal,to:store.journalURL); try checkpoint(.afterJournal)
            try await stage(records:planned,id:id,cancellation:cancellation,progress:progress,now:now)
            try checkpoint(.afterStagingSave); try validation(); try cancellation.check()
            journal.phase = .ready; try DurableFiles.encode(journal,to:store.journalURL); try checkpoint(.afterReady)
            // Cancellation is accepted until the commit point. After promotion the result is committed.
            try validation(); try cancellation.check(); progress(.init(phase:.promoting,completedUnits:0,totalUnits:1))
            try store.promote(id); try checkpoint(.afterPointer)
            journal.phase = .promoted; try DurableFiles.encode(journal,to:store.journalURL)
            lifecycle.bindContainer(store.container)
            let warnings = await finishHooks(generationID:id)
            try checkpoint(.afterHooks)
            if warnings.isEmpty { try FileManager.default.removeItem(at:store.journalURL) }
            progress(.init(phase:.completed,completedUnits:1,totalUnits:1))
            return .init(generationID:id,restoredCount:planned.count,skippedCount:0,automaticBackup:safety,warnings:warnings,container:store.container)
        } catch {
            if case BackupOperationError.simulatedInterruption = error { preserveRecovery = true }
            else if let journal = store.journal(), store.binding.generationID == journal.newGenerationID { preserveRecovery = true }
            if !preserveRecovery {
                if let id = stagedGeneration { try? FileManager.default.removeItem(at:store.generationDirectory(id)) }
                if FileManager.default.fileExists(atPath:store.journalURL.path) { try? FileManager.default.removeItem(at:store.journalURL) }
            }
            throw error
        }
    }
    /// Resume snapshot/history invalidation after a committed restore interrupted before the lifecycle hooks completed.
    public func completeRecovery() async throws -> [String] {
        let lease = try await beginOperation(); defer { finishOperation(lease:lease) }
        guard let journal = store.journal(), journal.phase == .promoted else { return [] }
        lifecycle.bindContainer(store.container); let warnings = await finishHooks(generationID:store.binding.generationID)
        if warnings.isEmpty { try FileManager.default.removeItem(at:store.journalURL) }; return warnings
    }
    @discardableResult public func recoverPendingLifecycle() async throws -> [String] { try await completeRecovery() }
    public func performScheduledBackupIfDue(schedule: BackupSchedule, now: Date = Date(), progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }, cancellation: BackupCancellation = BackupCancellation()) async throws -> BackupReceipt? {
        guard schedule.isDue(lastSuccess:try status().lastSuccessAt,now:now) else { return nil }
        return try await export(kind:.automatic,progress:progress,cancellation:cancellation,now:now)
    }
    /// Local account partitioning only; CloudKit rotations are refused until delete propagation is verified.
    public func rotateLocalStore(accountHash: String?, preservingCurrentRows: Bool, progress: @escaping @Sendable (BackupProgress) -> Void = { _ in }, cancellation: BackupCancellation = BackupCancellation(), now: Date = Date()) async throws -> RestoreResult {
        guard !store.isCloudBacked else { throw BackupOperationError.cloudRestoreUnsupported }
        let lease = try await beginOperation(); var preserveRecovery = false; let id = UUID()
        defer { finishOperation(lease:lease,preserveRecovery:preserveRecovery) }
        do {
            guard !store.isCloudBacked else { throw BackupOperationError.cloudRestoreUnsupported }
            guard try hasConfiguredKey() else { throw BackupOperationError.backupNotConfigured }
            let safety = try await exportUnderLease(kind:.automatic,passphrase:nil,progress:progress,cancellation:cancellation,now:now)
            let records = preservingCurrentRows ? try currentRecords() : []
            var journal = RestoreJournal(operationID:UUID(),oldGenerationID:store.binding.generationID,newGenerationID:id,phase:.preparing,hooksPending:true)
            try DurableFiles.encode(journal,to:store.journalURL); try checkpoint(.afterJournal)
            try await stage(records:records,id:id,cancellation:cancellation,progress:progress,now:now); try checkpoint(.afterStagingSave)
            journal.phase = .ready; try DurableFiles.encode(journal,to:store.journalURL); try cancellation.check(); try checkpoint(.afterReady)
            try store.promote(id,accountHash:accountHash); try checkpoint(.afterPointer); journal.phase = .promoted; try DurableFiles.encode(journal,to:store.journalURL)
            lifecycle.bindContainer(store.container); let warnings = await finishHooks(generationID:id)
            if warnings.isEmpty { try FileManager.default.removeItem(at:store.journalURL) }
            return .init(generationID:id,restoredCount:records.count,skippedCount:0,automaticBackup:safety,warnings:warnings,container:store.container)
        } catch {
            if case BackupOperationError.simulatedInterruption = error { preserveRecovery = true }
            else if store.binding.generationID == id { preserveRecovery = true }
            if !preserveRecovery { try? FileManager.default.removeItem(at:store.generationDirectory(id)); try? FileManager.default.removeItem(at:store.journalURL) }; throw error
        }
    }
    private func beginOperation() async throws -> StoreLease {
        guard !store.isBusy else { throw BackupOperationError.busy }; store.setBusy(true)
        do {
            try await lifecycle.quiesce()
            let lease = StoreLease(lockURL:store.commandLockURL); try lease.acquire(); try store.refreshIfNeeded(); try lease.beginMaintenance(operationID:UUID()); return lease
        } catch { store.setBusy(false); lifecycle.resume(); throw error }
    }
    private func finishOperation(lease: StoreLease,preserveRecovery: Bool = false) {
        if !preserveRecovery { try? lease.endMaintenance() }
        lease.release(); store.setBusy(false); if !preserveRecovery { lifecycle.resume() }
    }
    private func currentRecords() throws -> [DataRecord] { let context = ModelContext(store.container); context.autosaveEnabled = false; return try RecordBridge.all(context) }
    private func exportUnderLease(kind: BackupKind, passphrase: String?, progress: @escaping @Sendable (BackupProgress) -> Void, cancellation: BackupCancellation, now: Date) async throws -> BackupReceipt {
        try cancellation.check(); let rows = try currentRecords()
        // Typed validation does not need the media bytes (their hash and size are checked when the archive is written): validate a copy without them.
        try RecordValidator.validate(rows.map { row in var copy = row; if copy.model == "Media", copy.fields["data"] != nil { copy.fields["data"] = .null }; return copy })
        let fitted = BackupBookFiles.fitting(rows,budget:bookBudget); let archived = fitted.records
        let incremental = kind == .automatic && archived.contains { $0.model == "Media" && $0.fields["data"] != .null }
        let credential: BackupCredential; let prefixes: [Data]
        let count = incremental ? BackupArtifact.envelopeCount(records: archived) : 1
        if let passphrase {
            var fresh = try await background(cancellation) { try BackupCredential.derive(passphrase:passphrase) }
            prefixes = try (0..<count).map { _ in try fresh.reserveNoncePrefix() }; credential = fresh
        } else {
            guard var stored = try keyStore.load() else { throw BackupOperationError.backupNotConfigured }
            prefixes = try (0..<count).map { _ in try stored.reserveNoncePrefix() }
            try keyStore.save(stored); credential = stored
        }
        let prefix = prefixes[0]
        let directory = backupDirectory; let id = UUID(); let generationID = store.binding.generationID
        let previous = incremental ? try catalog().first(where: { $0.fileURL.pathExtension == "madarbackupset" })?.fileURL : nil
        let receipt: BackupReceipt
        if incremental {
            receipt = try await background(cancellation) {
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]
                let destination = directory.appendingPathComponent("Madar-\(formatter.string(from: now))-\(id.uuidString).madarbackupset")
                let partial = destination.appendingPathExtension("partial")
                defer { try? FileManager.default.removeItem(at: partial) }
                try BackupArtifact.writePackage(records: archived, to: partial, previous: previous, credential: credential,
                                                prefixes: prefixes, now: now, cancellation: cancellation, progress: progress)
                let hash = try BackupArtifact.fingerprint(file: partial)
                try cancellation.check()
                guard rename(partial.path, destination.path) == 0 else { throw DataError.invalidBackup }
                let fd = open(directory.path, O_RDONLY); if fd >= 0 { _ = fsync(fd); close(fd) }
                return BackupReceipt(id: id, fileURL: destination, createdAt: now, kind: kind, generationID: generationID,
                                     sha256: hash, counts: Self.counts(rows))
            }
        } else {
            receipt = try await background(cancellation) {
                let archive = try BackupCodec.archive(records:archived,now:now); try cancellation.check()
                let encrypted = try BackupCodec.seal(archive:archive,credential:credential,noncePrefix:prefix,now:now,cancellation:cancellation,progress:progress)
                // Verify bytes before making a finished file visible or pruning previous automatic backups.
                _ = try BackupCodec.validateContents(encrypted,credential:credential,cancellation:cancellation)
                try FileManager.default.createDirectory(at:directory,withIntermediateDirectories:true,attributes:[.posixPermissions:0o700])
                let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withFullDate]; let name = "Madar-\(formatter.string(from:now))-\(id.uuidString).madarbackup"
                let destination = directory.appendingPathComponent(name); let partial = directory.appendingPathComponent(name+".partial")
                defer { try? FileManager.default.removeItem(at:partial) }
                guard FileManager.default.createFile(atPath:partial.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw DataError.invalidBackup }
                let handle = try FileHandle(forWritingTo:partial)
                do {
                    let size = 64*1024; var offset = 0
                    while offset < encrypted.count { try cancellation.check(); let end = min(offset+size,encrypted.count); try handle.write(contentsOf:encrypted.subdata(in:offset..<end)); offset = end; progress(.init(phase:.writing,completedUnits:Int64(offset),totalUnits:Int64(encrypted.count))) }
                    try handle.synchronize(); try handle.close(); try cancellation.check()
                    guard rename(partial.path,destination.path) == 0 else { throw DataError.invalidBackup }
                    let fd = open(directory.path,O_RDONLY); if fd >= 0 { _ = fsync(fd); close(fd) }
                } catch { try? handle.close(); throw error }
                return BackupReceipt(id:id,fileURL:destination,createdAt:now,kind:kind,generationID:generationID,sha256:BackupCodec.hash(encrypted),counts:Self.counts(rows))
            }
        }
        var entries = try catalog(); entries.append(receipt)
        try DurableFiles.encode(entries,to:catalogURL)
        try DurableFiles.encode(BackupStatus(lastSuccessAt:now,lastResult:"success",localOnly:localOnly,excludedBooks:fitted.excluded),to:statusURL)
        try persistDeviceBackupStatus(at:now,result:"success")
        try prune(entries)
        progress(.init(phase:.completed,completedUnits:1,totalUnits:1)); return receipt
    }
    private func prune(_ entries: [BackupReceipt]) throws {
        let automatic = entries.filter { $0.kind == .automatic }.sorted { a,b in a.createdAt == b.createdAt ? a.id.uuidString > b.id.uuidString : a.createdAt > b.createdAt }
        let removed = automatic.dropFirst(4)
        let allowedParent = backupDirectory.standardizedFileURL.path
        for receipt in removed where receipt.fileURL.deletingLastPathComponent().standardizedFileURL.path == allowedParent {
            if FileManager.default.fileExists(atPath:receipt.fileURL.path) { try FileManager.default.removeItem(at:receipt.fileURL) }
        }
        let ids = Set(removed.map(\.id)); try DurableFiles.encode(entries.filter { !ids.contains($0.id) },to:catalogURL)
    }
    private func recordFailure(_ error: any Error) throws {
        let previous = try status(); let result = error is CancellationError || (error as? BackupOperationError) == .cancelled ? "cancelled" : "failed"
        try DurableFiles.encode(BackupStatus(lastSuccessAt:previous.lastSuccessAt,lastResult:result,localOnly:localOnly,excludedBooks:previous.excludedBooks),to:statusURL)
    }
    private func persistDeviceBackupStatus(at date: Date,result: String) throws {
        let context = ModelContext(store.container); context.autosaveEnabled = false; let writer = try SettingsStore(context:context).writerIDForWrite(now:date)
        for (key,value) in ["sys.lastBackupAt":try JSONValue.encode(date),"sys.lastBackupResult":JSONValue.string(result)] {
            let row = try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == key } ?? DeviceSetting()
            if row.modelContext == nil { row.id = StableIdentity.uuid(for:"DeviceSetting:\(key)"); context.insert(row) }
            row.key = key; row.valueJSON = try value.canonicalData(); row.writerID = writer; row.updatedAt = StableIdentity.monotonic(now:date,previous:row.updatedAt)
        }
        try context.save()
    }
    private func stage(records: [DataRecord], id: UUID, cancellation: BackupCancellation, progress: @Sendable (BackupProgress) -> Void, now: Date) async throws {
        try RecordValidator.validate(records); let directory = store.generationDirectory(id)
        let staging = try MadarContainerFactory.makeSyncedStaging(at:directory); let context = ModelContext(staging); context.autosaveEnabled = false
        for (index,row) in records.enumerated() {
            try cancellation.check(); try RecordBridge.insert(row,in:context); progress(.init(phase:.staging,completedUnits:Int64(index+1),totalUnits:Int64(records.count)))
            if index % 64 == 63 { await Task.yield(); try cancellation.check() }
        }
        try cancellation.check(); try context.save()
        let copied = try RecordBridge.all(context); guard copied.count == records.count, try RecordFingerprint.hash(copied) == RecordFingerprint.hash(records) else { throw BackupOperationError.invalidManagedStore }
        try DurableFiles.encode(GenerationReady(version:1,generationID:id,recordsHash:try RecordFingerprint.hash(copied),createdAt:now),to:directory.appendingPathComponent("GenerationReady.json"))
    }
    private func checkpoint(_ point: Checkpoint) throws { if interruption == point { throw BackupOperationError.simulatedInterruption(point.rawValue) } }
    private func finishHooks(generationID: UUID) async -> [String] {
        var warnings: [String] = []
        do {
            let context = ModelContext(store.container); context.autosaveEnabled = false
            // Restore changes facts. A model-name conversion preserves every fact and local row.
            if store.journal()?.preserveDeviceRows != true {
                for row in try context.fetch(FetchDescriptor<PageSchedule>()) { context.delete(row) }
                for row in try context.fetch(FetchDescriptor<SessionDraft>()) { context.delete(row) }
                for row in try context.fetch(FetchDescriptor<ProcessingJob>()) { context.delete(row) }
            }
            if context.hasChanges { try context.save() }
        } catch { warnings.append("تعذّر إبطال الجدولة والمسودات والمهام؛ ستُعاد المحاولة عند الفتح.") }
        do { try await lifecycle.rebuildSnapshots(store.container) } catch { warnings.append("تعذّر تحديث اللقطات؛ ستُعاد المحاولة عند الفتح.") }
        do { try await lifecycle.resetHistory(generationID) } catch { warnings.append("تعذّر إعادة ضبط سجل المزامنة؛ ستُعاد المحاولة عند الفتح.") }
        return warnings
    }
    private func background<T: Sendable>(_ cancellation: BackupCancellation, operation: @escaping @Sendable () throws -> T) async throws -> T {
        try await withTaskCancellationHandler { try await Task.detached(priority:.userInitiated,operation:operation).value } onCancel: { cancellation.cancel() }
    }
    nonisolated private static func readBounded(_ url: URL) throws -> Data {
        let size = try url.resourceValues(forKeys:[.fileSizeKey]).fileSize ?? 0; guard size > 0, size <= 512*1024*1024 else { throw DataError.invalidBackup }; return try Data(contentsOf:url,options:.mappedIfSafe)
    }
    nonisolated private static func counts(_ records: [DataRecord]) -> [String:Int] { Dictionary(uniqueKeysWithValues:MadarSchema.syncedNames.map { name in (name,records.filter { $0.model == name }.count) }) }
    nonisolated private static func hasMissingBookFiles(_ records: [DataRecord]) -> Bool {
        let bookMediaIDs = Set(records.lazy
            .filter { $0.model == "Book" && $0.isLive }
            .compactMap { record -> UUID? in
                guard let rawID = record.fields["mediaID"]?.string else { return nil }
                return UUID(uuidString: rawID)
            })
        return records.contains { row in
            row.model == "Media" && row.isLive && bookMediaIDs.contains(row.id)
                && row.fields["kind"] == .string("doc")
                && row.fields["state"] == .string("missing")
                && (row.fields["data"] == nil || row.fields["data"] == .null)
        }
    }
    static func plan(existing: [DataRecord], incoming: [DataRecord], mode: RestoreMode, now: Date, writerID: String) throws -> [DataRecord] {
        if existing.isEmpty { return incoming } // Clean restore preserves every timestamp, alias, tombstone and media byte.
        return BackupBookFiles.retainingLocalFiles(try planned(existing:existing,incoming:incoming,mode:mode,now:now,writerID:writerID),existing:existing)
    }
    private static func planned(existing: [DataRecord], incoming: [DataRecord], mode: RestoreMode, now: Date, writerID: String) throws -> [DataRecord] {
        if mode == .merge {
            var rows = existing
            for record in incoming {
                if let index = rows.firstIndex(where: { RecordFingerprint.key($0) == RecordFingerprint.key(record) }) { rows[index] = try RowMerger.mergeVersions(rows[index],record) }
                else { rows.append(record) }
            }
            return try RowMerger.reconciled(rows)
        }
        let keys = Set(incoming.map(RecordFingerprint.key)); var rows = incoming
        for i in rows.indices {
            let current = existing.first { RecordFingerprint.key($0) == RecordFingerprint.key(rows[i]) }
            let previous = max(rows[i].date("updatedAt") ?? .distantPast,current?.date("updatedAt") ?? .distantPast)
            let stamp = StableIdentity.monotonic(now:now,previous:previous)
            let barrier = [rows[i].deletedAt,rows[i].date("deletionBarrierAt"),current?.deletedAt,current?.date("deletionBarrierAt")].compactMap { $0 }.max()
            try rows[i].set(stamp,for:"updatedAt"); try rows[i].set(writerID,for:"writerID"); try rows[i].set(barrier,for:"deletionBarrierAt")
            if rows[i].isLive { try rows[i].set(max(stamp,(barrier ?? .distantPast).addingTimeInterval(0.001)),for:"restoredAt") }
        }
        for var absent in existing where !keys.contains(RecordFingerprint.key(absent)) {
            let stamp = StableIdentity.monotonic(now:now,previous:absent.date("updatedAt") ?? .distantPast)
            try absent.set(stamp,for:"updatedAt"); try absent.set(stamp,for:"deletedAt"); try absent.set(stamp,for:"deletionBarrierAt"); try absent.set(writerID,for:"writerID")
            if absent.model == "Media" { absent.fields["data"] = .null }; rows.append(absent)
        }
        return try RowMerger.reconciled(rows)
    }
}
