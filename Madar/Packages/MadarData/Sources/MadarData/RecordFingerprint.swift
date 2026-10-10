import Foundation

enum RecordFingerprint {
    static func key(_ record: DataRecord) -> String { "\(record.model):\(record.id.uuidString):\(record.fields["mergedInto"]?.string ?? "")" }
    static func hash(_ records: [DataRecord]) throws -> String {
        let values = try records.map { record in try JSONValue.object(["model":.string(record.model),"fields":.object(record.fields)]).canonicalData() }
        let sorted = values.sorted { $0.lexicographicallyPrecedes($1) }
        var data = Data(); for value in sorted { data.append(value); data.append(0x0a) }; return BackupCodec.hash(data)
    }
}
