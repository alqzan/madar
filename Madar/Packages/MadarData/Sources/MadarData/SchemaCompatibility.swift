import Foundation

enum SchemaCompatibility {
    static func validateDeviceVersion(at directory: URL) throws {
        let stamp = directory.appendingPathComponent("DeviceSchemaVersion.json")
        guard FileManager.default.fileExists(atPath: stamp.path) else { return }
        let version = try JSONDecoder().decode(Int.self, from: Data(contentsOf: stamp))
        guard (1...MadarSchema.version).contains(version) else {
            throw version > MadarSchema.version ? DataError.newerStore : DataError.invalidValue("device store version")
        }
    }
    static func modelNames(version: Int) throws -> [String] {
        switch version {
        case 1: MadarSchemaV1.syncedNames
        case 2: MadarSchemaV2.syncedNames
        case 3: MadarSchemaV3.syncedNames
        case MadarSchema.version: MadarSchema.syncedNames
        default: throw version > MadarSchema.version ? DataError.newerStore : DataError.unsupportedBackup
        }
    }
    /// Called only after the source's schema, original manifest and every original byte hash pass.
    static func currentRecords(_ records: [DataRecord], from version: Int) throws -> [DataRecord] {
        _ = try modelNames(version:version)
        return records.map { original in
            var row = original
            if version == 1 {
                if row.model == "Transaction" { row.model = "MoneyTransaction" }
                // These are model-name discriminators. sourceModel is provenance and must stay unchanged.
                for key in ["targetModel","pinnedEventKind","eventKind"] where row.fields[key] == .string("Transaction") { row.fields[key] = .string("MoneyTransaction") }
            }
            if version < 3, row.model == "PrayerLog" {
                row.fields["fridayKind"] = .null
            }
            return row
        }
    }
}
