import Foundation
import Testing
@testable import MadarData

/// Review T14 item 16 (the reviewer asks for «نسخ احتياطي يتجاوز 512 م.ب»): 512 MiB = 536 870 912 bytes by hand. A file of zeros is not a valid
/// archive either way, so these two only prove that an oversized input ends in the specific `invalidBackup` error and never crashes or hangs.
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
