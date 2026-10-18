import Foundation

public enum RecordValidator {
    private struct Dictionary: Decodable { let commonFields: [Field]; let models: [Model] }
    private struct Model: Decodable { let name: String; let fields: [Field] }
    private struct Field: Decodable { let name: String; let type: String; let optional: Bool; let range: [Double?]?; let values: [String]?
        enum CodingKeys: String,CodingKey { case name,type,optional,range,values = "enum" }
    }
    public static func validate(_ records: [DataRecord]) throws {
        guard let url = Bundle.module.url(forResource:"data-dictionary",withExtension:"json") else { throw DataError.invalidBackup }
        let spec = try JSONDecoder().decode(Dictionary.self,from:Data(contentsOf:url))
        for record in records {
            guard let model = spec.models.first(where: { $0.name == record.model }) else { throw DataError.unknownModel(record.model) }
            let fields = spec.commonFields + model.fields
            guard Set(record.fields.keys) == Set(fields.map(\.name)) else { throw DataError.invalidValue("\(record.model) fields") }
            for field in fields {
                guard let value = record.fields[field.name] else { throw DataError.invalidValue(field.name) }
                if value == .null { guard field.optional else { throw DataError.invalidValue(field.name) }; continue }
                if let range = field.range, let number = value.number, (range[0].map { number < $0 } ?? false) || (range[1].map { number > $0 } ?? false) { throw DataError.invalidValue(field.name) }
                if let values = field.values, !values.contains(value.string ?? "") { throw DataError.invalidValue(field.name) }
                if field.type == "String" || field.type == "String?" { guard value.string != nil else { throw DataError.invalidValue(field.name) } }
                if field.type == "[String]" || field.type == "[String]?" { guard value.array?.allSatisfy({ $0.string != nil }) == true else { throw DataError.invalidValue(field.name) } }
                if field.type == "Int" || field.type == "Int?" { guard let n = value.number, n.isFinite, n.rounded() == n, n >= Double(Int.min), n < Double(Int.max) else { throw DataError.invalidValue(field.name) } }
                if field.type == "UUID" || field.type == "UUID?" { guard UUID(uuidString:value.string ?? "") != nil else { throw DataError.invalidValue(field.name) } }
                if field.name == "dayKey", let text = value.string, !text.isEmpty, text.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) == nil { throw DataError.invalidValue(field.name) }
            }
            if record.model == "HifzSession", (record.fields["fromAyah"]?.number ?? 0) > (record.fields["toAyah"]?.number ?? 0) { throw DataError.invalidValue("HifzSession range") }
        }
    }
}
