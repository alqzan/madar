import Foundation
import Testing
@testable import MadarData

/// Review T14 item 16. The documented ceiling is 512 MiB (536 870 912 bytes) for a backup file and for a portable export:
/// one byte over is refused before any parsing, exactly at the limit is not refused for size.
struct BackupSizeLimitTests {
    private static let limit = 512 * 1024 * 1024
    @Test func portableDecodeRefusesOneByteOverTheLimit() {
        let over = Data(count: Self.limit + 1)
        #expect(throws: DataError.invalidBackup) { _ = try PortableZIP.decode(over) }
    }
    @Test func encryptedBackupOpenRefusesOneByteOverTheLimit() {
        let over = Data(count: Self.limit + 1)
        #expect(throws: DataError.invalidBackup) { _ = try BackupCodec.openArchive(over, passphrase: "x") }
    }
}
