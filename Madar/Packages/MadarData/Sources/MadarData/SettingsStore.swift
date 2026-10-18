import Foundation
import SwiftData
import OSLog

public struct SettingOption: Decodable, Sendable { public let value: JSONValue; public let label: String; public let availability: String? }
public struct SettingDefinition: Decodable, Sendable {
    public let key: String; public let title: String; public let type: String; public let scope: String; public let owner: String; public let preset: Bool; public let defaultValue: JSONValue; public let options: [SettingOption]; public let range: [Double]?; public let contract: [String: JSONValue]?
    enum CodingKeys: String, CodingKey { case key,title,type,scope,owner,preset,defaultValue = "default",options,range,contract }
    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        key = try c.decode(String.self, forKey: .key); title = try c.decode(String.self, forKey: .title); type = try c.decode(String.self, forKey: .type); scope = try c.decode(String.self, forKey: .scope); owner = try c.decode(String.self, forKey: .owner); preset = try c.decode(Bool.self, forKey: .preset); defaultValue = try c.decode(JSONValue.self, forKey: .defaultValue); options = try c.decodeIfPresent([SettingOption].self, forKey: .options) ?? []; range = try c.decodeIfPresent([Double].self, forKey: .range); contract = try c.decodeIfPresent([String:JSONValue].self, forKey: .contract)
    }
}
public struct SettingsSchema: Decodable, Sendable {
    public let settings: [SettingDefinition]
    public static func bundled() throws -> SettingsSchema { guard let url = Bundle.module.url(forResource: "settings-schema", withExtension: "json") else { throw DataError.invalidValue("settings schema") }; return try JSONDecoder().decode(Self.self, from: Data(contentsOf: url)) }
    public func definition(for key: String) throws -> SettingDefinition { guard let d = settings.first(where: { $0.key == key }) else { throw DataError.invalidValue("unknown setting \(key)") }; return d }
    public func validate(_ value: JSONValue, for key: String) throws {
        let d = try definition(for: key)
        func reject() throws -> Never { throw DataError.invalidValue(key) }
        func inRange(_ number: Double, _ range: [Double]?) -> Bool { number.isFinite && number.rounded() == number && (range == nil || (range!.count == 2 && number >= range![0] && number <= range![1])) }
        switch d.type {
        case "bool": guard case .bool = value else { try reject() }
        case "choice": guard d.options.contains(where: { $0.value == value && $0.availability != "v2" && $0.availability != "deferred" }) else { try reject() }
        case "int", "money": guard let number = value.number, inRange(number, d.range ?? d.contract?["range"]?.array?.compactMap(\.number)) else { try reject() }
        case "string": guard let s = value.string, Locale.Currency.isoCurrencies.map(\.identifier).contains(s) else { try reject() }
        case "time": guard let s = value.string, s.range(of: "^(?:[01][0-9]|2[0-3]):[0-5][0-9]$", options: .regularExpression) != nil else { try reject() }
        case "place":
            guard let o = value.object, Set(o.keys) == Set(["name","country","lat","lon","tz","currency"]), let name = o["name"]?.string, (1...80).contains(name.count), let country = o["country"]?.string, Locale.Region.isoRegions.map(\.identifier).contains(country), let lat = o["lat"]?.number, (-90...90).contains(lat), let lon = o["lon"]?.number, (-180...180).contains(lon), let tz = o["tz"]?.string, TimeZone(identifier:tz) != nil, let currency = o["currency"]?.string, Locale.Currency.isoCurrencies.map(\.identifier).contains(currency) else { try reject() }
        case "list":
            guard let array = value.array, array.allSatisfy({ $0.string != nil }), let c = d.contract else { try reject() }
            if c["unique"] == .bool(true), Set(array).count != array.count { try reject() }
            if let min = c["minItems"]?.number, Double(array.count) < min { try reject() }; if let max = c["maxItems"]?.number, Double(array.count) > max { try reject() }; if let exact = c["exactItems"]?.number, Double(array.count) != exact { try reject() }
            if let items = c["items"]?.array, !Set(array).isSubset(of:Set(items)) { try reject() }
            if let permutation = c["permutationOf"]?.array, Set(array) != Set(permutation) || array.count != permutation.count { try reject() }
            if let pattern = c["itemPattern"]?.string, array.contains(where: { $0.string!.range(of:pattern, options:.regularExpression) == nil }) { try reject() }
            if c["ascending"] == .bool(true) {
                let distances = array.map { item -> Int in let text = item.string!; return (Int(text.dropLast()) ?? 0) * (text.last == "w" ? 7 : text.last == "m" ? 30 : 365) }
                guard zip(distances, distances.dropFirst()).allSatisfy({ $0 < $1 }) else { try reject() }
            }
        case "map":
            guard let object = value.object, let c = d.contract, let keys = c["keys"]?.array?.compactMap(\.string), Set(object.keys) == Set(keys) else { try reject() }
            if c["value"]?.string == "Bool" { guard object.values.allSatisfy({ if case .bool = $0 { true } else { false } }) else { try reject() } }
            else { guard object.values.allSatisfy({ v in v.number.map { inRange($0,c["range"]?.array?.compactMap(\.number)) } ?? false }) else { try reject() } }
        case "layout": try validateLayout(value, definition: d)
        case "object":
            guard let object = value.object, let defaults = d.defaultValue.object, Set(object.keys) == Set(defaults.keys) else { try reject() }
            switch key {
            case "mal.dailyAllowance":
                guard ["fixed","percent"].contains(object["mode"]?.string ?? "") else { try reject() }
                for field in ["amountMinor","percentBp"] where object[field] != .null { guard let n = object[field]?.number, inRange(n,field == "percentBp" ? [0,10000] : [0,1e13]) else { try reject() } }
                guard object[object["mode"] == .string("fixed") ? "amountMinor" : "percentBp"] != .null else { try reject() }
            case "mal.salarySchedule":
                guard case .bool = object["enabled"], let unit = object["unit"]?.string,
                      let maximum = ["day": 365.0, "week": 104.0, "month": 120.0, "year": 10.0][unit],
                      let n = object["every"]?.number, inRange(n, [1, maximum]) else { try reject() }
                if object["firstDayKey"] != .null {
                    guard let raw = object["firstDayKey"]?.string, raw.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { try reject() }
                    let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.calendar = Calendar(identifier: .gregorian); f.timeZone = .gmt; f.dateFormat = "yyyy-MM-dd"; f.isLenient = false
                    guard let date = f.date(from: raw), f.string(from: date) == raw else { try reject() }
                } else if object["enabled"] == .bool(true) { try reject() }
            case "salah.trackingStart": guard let edits = object["edits"]?.number, inRange(edits,[0,1]), object["dayKey"] == .null || object["dayKey"]?.string?.range(of:"^[0-9]{4}-[0-9]{2}-[0-9]{2}$",options:.regularExpression) != nil else { try reject() }
            case "mihbara.readerAr", "mihbara.readerEn":
                guard let size = object["size"]?.number, inRange(size,[1,7]), ["auto","paper","warm","calm","night","black"].contains(object["theme"]?.string ?? ""), ["pages","scroll","focus"].contains(object["mode"]?.string ?? "") else { try reject() }
                let ar = key.hasSuffix("Ar")
                guard (ar ? ["amiri","notoNaskh","system","thmanyahSerif","thmanyahSans"] : ["literata","system","georgia"]).contains(object["font"]?.string ?? ""), ["tap","inline","hidden"].contains(object[ar ? "footnotes" : "arabicHints"]?.string ?? "") || (!ar && ["hard","all","none"].contains(object["arabicHints"]?.string ?? "")) else { try reject() }
                guard case .bool = object[ar ? "tashkil" : "hyphenation"] else { try reject() }
            default: try reject()
            }
        default: try reject()
        }
    }
    private func validateLayout(_ value: JSONValue, definition: SettingDefinition) throws {
        guard let o = value.object, let blocks = o["blocks"]?.array?.compactMap(\.string), let pinned = o["pinned"]?.array?.compactMap(\.string), let hidden = o["hidden"]?.array?.compactMap(\.string), let sizes = o["sizes"]?.object, let ids = definition.contract?["blockIds"]?.array?.compactMap(\.string), Set(o.keys).isSubset(of:Set(["v","blocks","pinned","hidden","sizes"])), Set(blocks).count == blocks.count, Set(blocks).isSubset(of:Set(ids)), Set(pinned).isSubset(of:Set(blocks)), Set(hidden).isSubset(of:Set(ids)), Set(hidden).isDisjoint(with:Set(pinned)), Set(sizes.keys).isSubset(of:Set(ids)) else { throw DataError.invalidValue(definition.key) }
        let allowedSizes = definition.contract?["sizes"]?.array ?? []
        guard sizes.values.allSatisfy({ allowedSizes.contains($0) }) else { throw DataError.invalidValue(definition.key) }
    }
}
public struct SettingsUndoToken: Codable, Sendable, Hashable { public let id: UUID; public let expiresAt: Date }
private struct UndoChange: Codable { let key: String; let before: JSONValue; let after: JSONValue }
@MainActor public final class SettingsStore {
    public let schema: SettingsSchema
    public let context: ModelContext
    private var invalidReads = Set<String>()
    private let logger = Logger(subsystem:"app.madar.data",category:"settings")
    public init(context: ModelContext, schema: SettingsSchema) { self.context = context; self.schema = schema }
    public convenience init(context: ModelContext) throws { try self.init(context: context, schema: SettingsSchema.bundled()) }
    public func value(for key: String) throws -> JSONValue {
        let d = try schema.definition(for:key)
        let data: Data?
        if d.type == "layout" { data = try context.fetch(FetchDescriptor<LayoutState>()).filter { $0.room == d.owner && $0.deletedAt == nil && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }?.blocksJSON }
        else if d.scope == "device" { data = try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key == key && $0.deletedAt == nil && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }?.valueJSON }
        else { data = try context.fetch(FetchDescriptor<Setting>()).filter { $0.key == key && $0.deletedAt == nil && $0.mergedInto == nil }.max { $0.updatedAt < $1.updatedAt }?.valueJSON }
        guard let data else { return d.defaultValue }
        // Compatibility read only; preserve the stored bytes and all owner records.
        if key == "core.faceIDLock", (try? JSONDecoder().decode(JSONValue.self, from: data)) == .string("notesOnly") { return .string("none") }
        guard let value = try? JSONDecoder().decode(JSONValue.self,from:data), value == d.defaultValue || (try? schema.validate(value,for:key)) != nil else { if invalidReads.insert(key).inserted { logger.error("Invalid stored setting; using default for \(key,privacy:.public)") }; return d.defaultValue }
        return value
    }
    /// Creates the per-install identity only as part of an actual write transaction; never saves.
    /// Reading settings or initializing this facade does not create system rows.
    public func writerIDForWrite(now: Date = Date()) throws -> String {
        let rows = try context.fetch(FetchDescriptor<DeviceSetting>()).filter { $0.key == "sys.writerID" && $0.mergedInto == nil }
        let existing = rows.max { lhs,rhs in lhs.updatedAt == rhs.updatedAt ? lhs.id.uuidString < rhs.id.uuidString : lhs.updatedAt < rhs.updatedAt }
        if let existing, existing.deletedAt == nil,
           let value = try? JSONDecoder().decode(String.self,from:existing.valueJSON), UUID(uuidString:value) != nil { return value }
        let identity = UUID().uuidString
        let row = existing ?? DeviceSetting()
        if row.modelContext == nil { row.id = StableIdentity.uuid(for:"DeviceSetting:sys.writerID"); context.insert(row) }
        row.key = "sys.writerID"; row.valueJSON = try JSONEncoder().encode(identity); row.writerID = identity
        row.updatedAt = StableIdentity.monotonic(now:now,previous:row.updatedAt); row.restoredAt = max(row.updatedAt,(row.deletionBarrierAt ?? .distantPast).addingTimeInterval(0.001)); row.deletedAt = nil
        return identity
    }
    /// Stage a validated write. The command adapter saves it with its receipt in one transaction.
    public func prepare(_ value: JSONValue, for key: String, now: Date = Date(), validateDependencies: Bool = true) throws {
        let d = try schema.definition(for:key)
        // A reset may restore a schema null default that is deliberately not a user-entered value.
        if value != d.defaultValue { try schema.validate(value,for:key) }
        if validateDependencies, key == "tabbar.items", value.array?.count ?? 0 > 3, try self.value(for:"tabbar.searchTab") == .bool(true) { throw DataError.invalidValue(key) }
        if validateDependencies, key == "tabbar.searchTab", value == .bool(true), try self.value(for:"tabbar.items").array?.count ?? 0 > 3 { throw DataError.invalidValue(key) }
        let data = try value.canonicalData()
        let writer = try writerIDForWrite(now:now)
        if d.type == "layout" {
            let row = try context.fetch(FetchDescriptor<LayoutState>()).first { $0.room == d.owner && $0.mergedInto == nil } ?? LayoutState()
            if row.modelContext == nil { row.id = StableIdentity.uuid(for:"LayoutState:\(d.owner)"); context.insert(row) }
            row.writerID = writer; row.room = d.owner; row.blocksJSON = data; row.updatedAt = StableIdentity.monotonic(now:now,previous:row.updatedAt); row.restoredAt = row.updatedAt; row.deletedAt = nil
        } else if d.scope == "device" {
            let row = try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == key && $0.mergedInto == nil } ?? DeviceSetting()
            if row.modelContext == nil { row.id = StableIdentity.uuid(for:"DeviceSetting:\(key)"); context.insert(row) }
            row.writerID = writer; row.key = key; row.valueJSON = data; row.updatedAt = StableIdentity.monotonic(now:now,previous:row.updatedAt); row.restoredAt = row.updatedAt; row.deletedAt = nil
        } else {
            let row = try context.fetch(FetchDescriptor<Setting>()).first { $0.key == key && $0.mergedInto == nil } ?? Setting()
            if row.modelContext == nil { row.id = StableIdentity.uuid(for:"Setting:\(key)"); context.insert(row) }
            row.writerID = writer; row.key = key; row.valueJSON = data; row.updatedAt = StableIdentity.monotonic(now:now,previous:row.updatedAt)
            if value == d.defaultValue { row.deletedAt = row.updatedAt; row.deletionBarrierAt = row.updatedAt }
            else { row.restoredAt = max(row.updatedAt,(row.deletionBarrierAt ?? .distantPast).addingTimeInterval(0.001)); row.deletedAt = nil }
        }
    }
    public func stage(_ values: [String:JSONValue], presetOnly: Bool = false, now: Date = Date()) throws -> [String:JSONValue] {
        var inverse: [String:JSONValue] = [:]
        for (key,value) in values {
            let d = try schema.definition(for:key)
            if presetOnly && !d.preset { throw DataError.invalidValue("non-preset \(key)") }
            if value != d.defaultValue { try schema.validate(value,for:key) }
            inverse[key] = try self.value(for:key)
        }
        let prospectiveSearch = try values["tabbar.searchTab"] ?? self.value(for:"tabbar.searchTab")
        let prospectiveItems = try values["tabbar.items"] ?? self.value(for:"tabbar.items")
        if prospectiveSearch == .bool(true), (prospectiveItems.array?.count ?? 0) > 3 { throw DataError.invalidValue("tabbar.items") }
        for (key,value) in values.sorted(by: { $0.key < $1.key }) where inverse[key] != value { try prepare(value,for:key,now:now,validateDependencies:false) }
        return inverse
    }
    @discardableResult public func resetMany(keys: [String], now: Date = Date()) throws -> SettingsUndoToken {
        var values: [String:JSONValue] = [:]
        for key in keys { values[key] = try schema.definition(for:key).defaultValue }
        return try perform(changes:values,name:"ResetSettings",window:600,now:now)
    }
    @discardableResult public func set(_ value: JSONValue, for key: String, now: Date = Date()) throws -> SettingsUndoToken { try perform(changes:[key:value],name:"SetSetting",window:600,now:now) }
    @discardableResult public func reset(_ key: String, now: Date = Date()) throws -> SettingsUndoToken { try set(schema.definition(for:key).defaultValue,for:key,now:now) }
    @discardableResult public func applyPreset(settings: [String:JSONValue], layouts: [String:JSONValue] = [:], now: Date = Date()) throws -> SettingsUndoToken {
        var changes = settings
        for key in settings.keys where try !schema.definition(for:key).preset { throw DataError.invalidValue("non-preset \(key)") }
        for (room,layout) in layouts { let key = room + ".layout"; try schema.validate(layout,for:key); changes[key] = layout }
        return try perform(changes:changes,name:"ApplyPreset",window:60,now:now)
    }
    private func perform(changes: [String:JSONValue], name: String, window: TimeInterval, now: Date) throws -> SettingsUndoToken {
        let undo = try changes.sorted { $0.key < $1.key }.map { UndoChange(key:$0.key,before:try value(for:$0.key),after:$0.value) }
        let token = SettingsUndoToken(id:UUID(),expiresAt:now.addingTimeInterval(window))
        do {
            _ = try stage(changes,now:now)
            let receipt = CommandReceipt(); receipt.writerID = try writerIDForWrite(now:now); receipt.commandID = token.id; receipt.name = name; receipt.issuedAt = now; receipt.undoExpiresAt = token.expiresAt; receipt.expiresAt = now.addingTimeInterval(7*86400); receipt.undoJSON = try JSONEncoder().encode(undo); context.insert(receipt)
            try context.save(); return token
        } catch { context.rollback(); throw error }
    }
    public func undo(_ token: SettingsUndoToken, now: Date = Date()) throws {
        guard now < token.expiresAt, let receipt = try context.fetch(FetchDescriptor<CommandReceipt>()).first(where: { $0.commandID == token.id && $0.status == "applied" }), let deadline = receipt.undoExpiresAt, now < deadline, let data = receipt.undoJSON else { throw DataError.undoExpired }
        let changes = try JSONDecoder().decode([UndoChange].self,from:data)
        guard try changes.allSatisfy({ try value(for:$0.key) == $0.after }) else { throw DataError.invalidValue("undo superseded by later edit") }
        do { _ = try stage(Dictionary(uniqueKeysWithValues:changes.map { ($0.key,$0.before) }),now:now); receipt.status = "undone"; receipt.writerID = try writerIDForWrite(now:now); receipt.updatedAt = StableIdentity.monotonic(now:now,previous:receipt.updatedAt); receipt.undoJSON = nil; try context.save() } catch { context.rollback(); throw error }
    }
}
