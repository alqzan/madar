import Foundation

enum SchemaCompatibility {
    static func modelNames(version: Int) throws -> [String] {
        switch version {
        case 1: MadarSchemaV1.syncedNames
        case MadarSchema.version: MadarSchema.syncedNames
        default: throw version > MadarSchema.version ? DataError.newerStore : DataError.unsupportedBackup
        }
    }
    /// Called only after the source's schema, original manifest and every original byte hash pass.
    static func currentRecords(_ records: [DataRecord], from version: Int) throws -> [DataRecord] {
        _ = try modelNames(version:version)
        guard version == 1 else { return records }
        return records.map { original in
            var row = original
            if row.model == "Transaction" { row.model = "MoneyTransaction" }
            // These are model-name discriminators. sourceModel is provenance and must stay unchanged.
            for key in ["targetModel","pinnedEventKind","eventKind"] where row.fields[key] == .string("Transaction") { row.fields[key] = .string("MoneyTransaction") }
            return row
        }
    }
}
