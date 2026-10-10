import Foundation

public enum PrayerStoredStatus: String, Codable, Sendable { case jamaah, alone, qada, missed, unrecordedHistory }
public enum PrayerHeart: String, Codable, CaseIterable, Sendable { case distracted, present, khashi }
public enum PrayerPair: String, Codable, Sendable {
    case dhuhrAsr, maghribIsha
    public var prayers: [Prayer] { self == .dhuhrAsr ? [.dhuhr, .asr] : [.maghrib, .isha] }
}
public enum PrayerPairMode: String, Codable, Sendable { case taqdim, takhir }
public struct PrayerReference: Codable, Hashable, Sendable {
    public let day: GregorianDay
    public let prayer: Prayer
    public init(day: GregorianDay, prayer: Prayer) { self.day = day; self.prayer = prayer }
    public var naturalKey: String { day.description + "." + prayer.rawValue }
}
public enum PrayerMutation: Codable, Equatable, Sendable {
    case record(PrayerReference, status: PrayerStoredStatus, heart: PrayerHeart?, shortened: Bool?)
    case makeUp(PrayerReference)
    case addOldMissed(PrayerReference)
    case markUnrecorded([PrayerReference])
    case answerHeart(PrayerReference, PrayerHeart?)
    case logPair(day: GregorianDay, pair: PrayerPair, status: PrayerStoredStatus, shortened: Bool, mode: PrayerPairMode)
    case logQiyam(night: GregorianDay, rakaat: Int, witr: Bool)
    case agePending
    case editTrackingStart(GregorianDay)
    case initializeTracking
    case startTrip(city: String, country: String, place: ActivePlace, homeKm: Double?)
    case endTrip(UUID)
    case clear(PrayerReference)
}

extension PrayerMutation {
    static func parse(name: String, payload: [String: JSONValue]) throws -> (Self, String?) {
        func string(_ key: String) throws -> String { guard case .string(let value) = payload[key] else { throw CoreError.invalidCommand }; return value }
        func ref(_ object: [String: JSONValue]) throws -> PrayerReference {
            guard Set(object.keys) == ["dayKey", "prayer"], case .string(let day) = object["dayKey"], case .string(let p) = object["prayer"], let prayer = Prayer(rawValue: p) else { throw CoreError.invalidCommand }
            return try .init(day: GregorianDay(day), prayer: prayer)
        }
        switch name {
        case "prayer.startTrip":
            guard Set(payload.keys).isSubset(of: ["city", "country", "lat", "lon", "tzID", "homeKm"]), case .number(let lat) = payload["lat"], case .number(let lon) = payload["lon"] else { throw CoreError.invalidCommand }
            let city = try string("city"), country = try string("country")
            guard !city.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, city.count <= 100, country.count == 2, country.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { throw CoreError.invalidCommand }
            var distance: Double?
            if let value = payload["homeKm"] { guard case .number(let km) = value, km.isFinite, km >= 0 else { throw CoreError.invalidCommand }; distance = km }
            return (.startTrip(city: city, country: country, place: try ActivePlace(latitude: lat, longitude: lon, timeZoneID: string("tzID")), homeKm: distance), nil)
        case "prayer.endTrip":
            guard Set(payload.keys) == ["tripID"], let id = UUID(uuidString: try string("tripID")) else { throw CoreError.invalidCommand }
            return (.endTrip(id), "trip." + id.uuidString)
        case "prayer.makeUp", "prayer.addOldMissed", "prayer.clear":
            let value = try ref(payload)
            let command: Self = name == "prayer.makeUp" ? .makeUp(value) : (name == "prayer.clear" ? .clear(value) : .addOldMissed(value))
            return (command, "prayer." + value.naturalKey)
        case "prayer.answerHeart":
            guard Set(payload.keys) == ["dayKey", "prayer", "heart"] else { throw CoreError.invalidCommand }
            let value = try ref(payload.filter { $0.key != "heart" }); let heart: PrayerHeart?
            if payload["heart"] == .null { heart = nil }
            else { guard let parsed = PrayerHeart(rawValue: try string("heart")) else { throw CoreError.invalidCommand }; heart = parsed }
            return (.answerHeart(value, heart), "prayer.heart." + value.naturalKey)
        case "prayer.markUnrecorded":
            guard Set(payload.keys) == ["prayers"], case .array(let values) = payload["prayers"], !values.isEmpty, values.count <= 70 else { throw CoreError.invalidCommand }
            let refs = try values.map { value in guard case .object(let object) = value else { throw CoreError.invalidCommand }; return try ref(object) }
            guard Set(refs).count == refs.count else { throw CoreError.invalidCommand }
            return (.markUnrecorded(refs), nil)
        case "prayer.logPair":
            guard Set(payload.keys) == ["dayKey", "pair", "status", "shortened", "mode"], let pair = PrayerPair(rawValue: try string("pair")), let status = PrayerStoredStatus(rawValue: try string("status")), [.jamaah, .alone].contains(status), case .bool(let shortened) = payload["shortened"], let mode = PrayerPairMode(rawValue: try string("mode")) else { throw CoreError.invalidCommand }
            let day = try GregorianDay(string("dayKey"))
            return (.logPair(day: day, pair: pair, status: status, shortened: shortened, mode: mode), "prayer.pair." + day.description + "." + pair.rawValue)
        case "prayer.logQiyam":
            guard Set(payload.keys) == ["nightKey", "rakaat", "witr"], case .number(let rakaat) = payload["rakaat"], rakaat.isFinite, rakaat.rounded() == rakaat, (0...1000).contains(rakaat), case .bool(let witr) = payload["witr"] else { throw CoreError.invalidCommand }
            let day = try GregorianDay(string("nightKey"))
            return (.logQiyam(night: day, rakaat: Int(rakaat), witr: witr), "prayer.qiyam." + day.description)
        case "prayer.editTrackingStart":
            guard Set(payload.keys) == ["dayKey"] else { throw CoreError.invalidCommand }
            return (.editTrackingStart(try GregorianDay(string("dayKey"))), "salah.trackingStart")
        case "prayer.agePending", "prayer.initializeTracking":
            guard payload.isEmpty else { throw CoreError.invalidCommand }
            return (name == "prayer.agePending" ? .agePending : .initializeTracking, nil)
        default: throw CoreError.invalidCommand
        }
    }
}
