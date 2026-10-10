import Foundation
import Security
import CryptoKit

/// Derived key and salt only. The passphrase is never persisted.
public struct BackupCredential: Codable, Sendable, Equatable {
    public let salt: Data; public let keyData: Data; public var nextNonceCounter: UInt64
    public static func derive(passphrase: String) throws -> BackupCredential {
        guard passphrase.count >= 10 else { throw DataError.invalidValue("backup passphrase requires at least 10 characters") }
        let salt = BackupCodec.random(count:16); let key = try BackupCodec.derive(passphrase:passphrase,salt:salt,iterations:600000)
        let data = key.withUnsafeBytes { Data($0) }
        return .init(salt:salt,keyData:data,nextNonceCounter:UInt64(UInt32.random(in:0...(UInt32.max-1_000_000))))
    }
    mutating func reserveNoncePrefix() throws -> Data {
        guard salt.count == 16, keyData.count == 32, nextNonceCounter <= UInt64(UInt32.max) else { throw BackupOperationError.nonceExhausted }
        let prefix = BackupCodec.integer(nextNonceCounter,bytes:4); nextNonceCounter += 1; return prefix
    }
}
public protocol BackupKeyStore: Sendable { func load() throws -> BackupCredential?; func save(_ credential: BackupCredential) throws; func remove() throws }
/// Explicit local test dependency. Does not access the system Keychain.
public final class MemoryBackupKeyStore: BackupKeyStore, @unchecked Sendable {
    private let lock = NSLock(); private var credential: BackupCredential?
    public init() {}
    public func load() throws -> BackupCredential? { lock.lock(); defer { lock.unlock() }; return credential }
    public func save(_ credential: BackupCredential) throws { lock.lock(); defer { lock.unlock() }; self.credential = credential }
    public func remove() throws { lock.lock(); defer { lock.unlock() }; credential = nil }
}
public final class KeychainBackupKeyStore: BackupKeyStore, Sendable {
    private let service: String; private let account: String
    public init(service: String = "app.madar.backup",account: String = "derived-backup-key-v1") { self.service = service; self.account = account }
    private var query: [String:Any] { [kSecClass as String:kSecClassGenericPassword,kSecAttrService as String:service,kSecAttrAccount as String:account,kSecAttrSynchronizable as String:false] }
    public func load() throws -> BackupCredential? {
        var attributes = query; attributes[kSecReturnData as String] = true; attributes[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?; let status = SecItemCopyMatching(attributes as CFDictionary,&result)
        if status == errSecItemNotFound { return nil }; guard status == errSecSuccess, let data = result as? Data else { throw DataError.invalidValue("backup key unavailable (\(status))") }
        let credential = try JSONDecoder().decode(BackupCredential.self,from:data)
        guard credential.keyData.count == 32, credential.salt.count == 16 else { throw DataError.invalidBackup }; return credential
    }
    public func save(_ credential: BackupCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let update: [String:Any] = [kSecValueData as String:data,kSecAttrAccessible as String:kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly]
        let result = SecItemUpdate(query as CFDictionary,update as CFDictionary)
        if result == errSecItemNotFound {
            var insert = query; for (key,value) in update { insert[key] = value }
            let status = SecItemAdd(insert as CFDictionary,nil); guard status == errSecSuccess else { throw DataError.invalidValue("backup key write unavailable (\(status))") }
        } else if result != errSecSuccess { throw DataError.invalidValue("backup key write unavailable (\(result))") }
    }
    public func remove() throws { let status = SecItemDelete(query as CFDictionary); guard status == errSecSuccess || status == errSecItemNotFound else { throw DataError.invalidValue("backup key deletion unavailable (\(status))") } }
}
