import Foundation

public enum HabitCommand: Codable, Equatable, Sendable {
    case save(id: UUID, name: String, source: String?, rule: HabitRule, homeOnly: Bool, reminder: String)
    case complete(id: UUID, delta: Int, periodKey: String?)
    case pause(id: UUID, from: GregorianDay, until: GregorianDay?, trip: Bool)
    case health(id: UUID, unit: String, values: [String:Int])
    case resume(UUID)
    case archive(id: UUID, archived: Bool)
    case deleteArchived(UUID)
    public static let names: Set<String> = ["habit.save", "habit.complete", "habit.pause", "habit.resume", "habit.archive", "habit.refreshHealth", "habit.deleteArchived"]
    public static func parse(_ name: String, _ value: [String: JSONValue]) -> Self? {
        guard let id = (value["id"] ?? value["habitID"])?.string.flatMap(UUID.init(uuidString:)) else { return nil }
        switch name {
        case "habit.save":
            guard Set(value.keys).isSubset(of: ["id","name","source","rule","homeOnly","reminder"]), let text = value["name"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !text.isEmpty, text.count <= 80,
                  let json = value["rule"], let data = try? json.canonicalData(), let rule = try? JSONDecoder().decode(HabitRule.self, from: data), (try? rule.validate()) != nil else { return nil }
            let source = value["source"]?.string
            guard value["source"] == nil || source.map({ ["jamaah","review","diaryLine","walking"].contains($0) }) == true else { return nil }
            if source == "jamaah", rule.target > 5 { return nil }
            if source == "walking" { guard rule.measure == .health, ["steps","exerciseMinutes"].contains(rule.unit ?? "") else {return nil} }
            else if let source {
                guard rule.measure == .count, rule.unit == ["jamaah":"صلاة","review":"وجه","diaryLine":"سطر"][source] else { return nil }
            }
            let reminder = value["reminder"]?.string ?? "dot"
            guard ["dot","push","none"].contains(reminder), value["homeOnly"] == nil || value["homeOnly"]?.bool != nil else { return nil }
            return .save(id: id, name: text, source: source, rule: rule, homeOnly: value["homeOnly"]?.bool ?? false, reminder: reminder)
        case "habit.complete":
            guard Set(value.keys).isSubset(of: ["id","habitID","delta","periodKey"]) else { return nil }
            guard value["id"] == nil || value["habitID"] == nil, value["delta"] == nil || value["delta"]?.number != nil, value["periodKey"] == nil || value["periodKey"]?.string != nil else {return nil}
            let n = value["delta"]?.number ?? 1
            guard n > 0, n <= 100000, n.rounded() == n else { return nil }
            return .complete(id: id, delta: Int(n), periodKey: value["periodKey"]?.string)
        case "habit.pause":
            guard Set(value.keys).isSubset(of: ["id","from","until","trip"]), let from = value["from"]?.string.flatMap({ try? GregorianDay($0) }) else { return nil }
            let until = value["until"]?.string.flatMap { try? GregorianDay($0) }
            guard value["until"] == nil || until.map({ $0 > from }) == true else { return nil }
            guard value["trip"] == nil || value["trip"]?.bool != nil else { return nil }
            return .pause(id: id, from: from, until: until, trip: value["trip"]?.bool ?? false)
        case "habit.deleteArchived": return Set(value.keys) == ["id"] ? .deleteArchived(id) : nil
        case "habit.refreshHealth":
            guard Set(value.keys) == ["id","unit","values"], let unit=value["unit"]?.string, ["steps","exerciseMinutes"].contains(unit), case .object(let raw)=value["values"], raw.count<=7 else{return nil}
            var values:[String:Int]=[:]
            for (day,number) in raw {guard (try? GregorianDay(day)) != nil, let n=number.number, n>=0,n<=1000000,n.rounded()==n else{return nil};values[day]=Int(n)}
            return .health(id:id,unit:unit,values:values)
        case "habit.resume": return Set(value.keys) == ["id"] ? .resume(id) : nil
        case "habit.archive": guard Set(value.keys) == ["id","archived"], let flag = value["archived"]?.bool else { return nil }; return .archive(id: id, archived: flag)
        default: return nil
        }
    }
}
private extension JSONValue {
    var string: String? { if case .string(let s) = self { s } else { nil } }
    var number: Double? { if case .number(let n) = self { n } else { nil } }
    var bool: Bool? { if case .bool(let b) = self { b } else { nil } }
}
