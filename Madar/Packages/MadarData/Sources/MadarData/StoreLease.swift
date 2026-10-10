import Foundation
import Darwin

/// The app and every writable extension use the same caller-supplied CommandBus.lock.
public final class StoreLease: @unchecked Sendable {
    public let lockURL: URL
    private var descriptor: Int32 = -1
    public init(lockURL: URL) { self.lockURL = lockURL }
    public static func maintenanceURL(lockURL: URL) -> URL { lockURL.deletingLastPathComponent().appendingPathComponent("StoreMaintenance.json") }
    public static func checkMaintenance(lockURL: URL) throws {
        if FileManager.default.fileExists(atPath:maintenanceURL(lockURL:lockURL).path) { throw BackupOperationError.busy }
    }
    public func acquire(nonBlocking: Bool = true, failIfMaintenance: Bool = true) throws {
        guard descriptor == -1 else { throw BackupOperationError.busy }
        if failIfMaintenance { try Self.checkMaintenance(lockURL:lockURL) }
        try FileManager.default.createDirectory(at:lockURL.deletingLastPathComponent(),withIntermediateDirectories:true)
        let fd = open(lockURL.path,O_CREAT|O_RDWR,0o600); guard fd >= 0 else { throw BackupOperationError.busy }
        if flock(fd,LOCK_EX | (nonBlocking ? LOCK_NB : 0)) != 0 { close(fd); throw BackupOperationError.busy }
        if failIfMaintenance, FileManager.default.fileExists(atPath:Self.maintenanceURL(lockURL:lockURL).path) { flock(fd,LOCK_UN); close(fd); throw BackupOperationError.busy }
        descriptor = fd
    }
    func beginMaintenance(operationID: UUID) throws {
        guard descriptor >= 0 else { throw BackupOperationError.busy }
        let data = try JSONSerialization.data(withJSONObject:["operationID":operationID.uuidString,"pid":getpid()],options:.sortedKeys)
        try DurableFiles.write(data,to:Self.maintenanceURL(lockURL:lockURL))
    }
    func endMaintenance() throws { if FileManager.default.fileExists(atPath:Self.maintenanceURL(lockURL:lockURL).path) { try FileManager.default.removeItem(at:Self.maintenanceURL(lockURL:lockURL)) } }
    public func release() { if descriptor >= 0 { flock(descriptor,LOCK_UN); close(descriptor); descriptor = -1 } }
    deinit { release() }
}
enum DurableFiles {
    static func write(_ data: Data,to destination: URL) throws {
        try FileManager.default.createDirectory(at:destination.deletingLastPathComponent(),withIntermediateDirectories:true)
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".\(destination.lastPathComponent).\(UUID()).partial")
        defer { try? FileManager.default.removeItem(at:temporary) }
        guard FileManager.default.createFile(atPath:temporary.path,contents:nil,attributes:[.posixPermissions:0o600]) else { throw BackupOperationError.invalidManagedStore }
        let handle = try FileHandle(forWritingTo:temporary); do { try handle.write(contentsOf:data); try handle.synchronize(); try handle.close() } catch { try? handle.close(); throw error }
        guard rename(temporary.path,destination.path) == 0 else { throw BackupOperationError.invalidManagedStore }
        let fd = open(destination.deletingLastPathComponent().path,O_RDONLY); if fd >= 0 { _ = fsync(fd); close(fd) }
    }
    static func encode<T: Encodable>(_ value: T,to destination: URL) throws { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]; try write(encoder.encode(value),to:destination) }
}
