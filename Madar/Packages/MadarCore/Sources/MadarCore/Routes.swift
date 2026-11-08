import Foundation

public enum RouteMode: String, Sendable { case read, prefill }
public enum RouteLock: Sendable { case none, notesOnly, app }
public struct Route: Equatable, Sendable {
    public let room: Room
    public let path: [String]
    public let parameters: [String: String]
    public let mode: RouteMode
    public let requiresUnlock: Bool
}
public struct RouteContext: Sendable {
    public let trackingStart: GregorianDay
    public let today: GregorianDay
    public let settingsKeys: Set<String>
    public let unavailableSettings: Set<String>
    public let lock: RouteLock
    public let unlocked: Bool
    public let availability: FeatureAvailability
    public init(trackingStart: GregorianDay, today: GregorianDay, settingsKeys: Set<String>, unavailableSettings: Set<String> = [], lock: RouteLock = .none, unlocked: Bool = false, availability: FeatureAvailability = .m0) { self.trackingStart = trackingStart; self.today = today; self.settingsKeys = settingsKeys; self.unavailableSettings = unavailableSettings; self.lock = lock; self.unlocked = unlocked; self.availability = availability }
}
public enum RouteRegistry {
    public static func parse(_ url: URL, context: RouteContext) throws -> Route {
        guard let c = URLComponents(url: url, resolvingAgainstBaseURL: false), c.scheme == "madar", let host = c.host,
              c.user == nil, c.password == nil, c.port == nil, c.fragment == nil else { throw CoreError.invalidRoute }
        let path = c.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard !c.path.contains("//"), !path.contains(where: { $0 == "." || $0 == ".." || $0.contains("/") }) else { throw CoreError.invalidRoute }
        var p: [String: String] = [:]
        for item in c.queryItems ?? [] { guard p[item.name] == nil, let value = item.value else { throw CoreError.invalidRoute }; p[item.name] = value }
        var room: Room; var mode: RouteMode = .read; var allowed = Set<String>()
        func uuid(_ value: String) throws { guard UUID(uuidString: value) != nil else { throw CoreError.invalidRoute } }
        func date(_ value: String) throws { let d = try GregorianDay(value); guard d >= context.trackingStart, d <= context.today.adding(days: 366) else { throw CoreError.invalidRoute } }
        func integer(_ value: String, range: ClosedRange<Int>) throws { guard value.utf8.allSatisfy({ (48...57).contains($0) }), let n = Int(value), range.contains(n) else { throw CoreError.invalidRoute } }
        if host == "settings" {
            let key = path.last ?? ""
            guard path.count == 2, let r = Room(rawValue: path[0]),
                  key.utf8.count <= 128,
                  key.range(of: "^[A-Za-z0-9_]+(?:\\.[A-Za-z0-9_-]+)+$", options: .regularExpression) != nil,
                  (context.settingsKeys.contains(key) || !context.unavailableSettings.contains(key)) else { throw CoreError.invalidRoute }
            room = r
        } else if host == "search" {
            guard path.isEmpty else { throw CoreError.invalidRoute }; room = .core; allowed = ["q", "room"]
            if let r = p["room"], Room(rawValue: r) == nil { throw CoreError.invalidRoute }
        } else {
            guard let r = Room(rawValue: host), r != .core, r != .habits, r != .year else { throw CoreError.invalidRoute }; room = r
            if path.isEmpty {} else {
                switch (r, path[0], path.count) {
                case (.bahw, "habits", 1): room = .habits; allowed = ["habit"]; if let value = p["habit"] { try uuid(value) }
                case (.bahw, "habits", 2): room = .habits; try uuid(path[1])
                case (.bahw, "year", 1): room = .year
                case (.bahw, "year", 3): guard path[1] == "day" else { throw CoreError.invalidRoute }; room = .year; try uuid(path[2])
                case (.bahw, "widget-maker", 1): allowed = ["template"]; if let t = p["template"], Room(rawValue: t) == nil { throw CoreError.invalidRoute }
                case (.salah, "day", 2), (.salah, "qiyam", 2), (.notes, "day", 2): try date(path[1])
                case (.salah, "hali", 1), (.notes, "today", 1), (.notes, "letters", 1), (.quran, "fihris", 1), (.mal, "now", 1), (.mal, "messages", 1), (.mal, "categories", 1), (.mal, "reconcile", 1), (.mal, "zakat", 1), (.mihbara, "desk", 1), (.mihbara, "continue", 1): break
                case (.salah, "log", 1):
                    allowed = ["prayer", "day", "status", "heart"]; mode = .prefill
                    guard let value = p["prayer"], Prayer(rawValue: value) != nil else { throw CoreError.invalidRoute }
                    if let day = p["day"] { try date(day) }
                    if let status = p["status"], !["jamaah", "alone", "qada"].contains(status) { throw CoreError.invalidRoute }
                    if let heart = p["heart"], !["distracted", "present", "khashi"].contains(heart) { throw CoreError.invalidRoute }
                case (.notes, "write", 1): allowed = ["day"]; mode = .prefill; if let day = p["day"], !["today", "yesterday"].contains(day) { throw CoreError.invalidRoute }
                case (.notes, "entry", 2), (.notes, "letter", 2), (.notes, "project", 2), (.quran, "history", 2), (.mal, "tx", 2), (.mal, "envelope", 2), (.mihbara, "notebook", 2): try uuid(path[1])
                case (.quran, "page", 2): try integer(path[1], range: 1...604)
                case (.quran, "juz", 2): try integer(path[1], range: 1...30)
                case (.quran, "session", 2): guard ["hifz", "review", "drill", "bridge", "wird", "qiyam"].contains(path[1]) else { throw CoreError.invalidRoute }; mode = .prefill
                case (.mal, "card", 2): try uuid(path[1]); allowed = ["tab"]; if let tab = p["tab"], !["overview", "cash", "calendar", "match"].contains(tab) { throw CoreError.invalidRoute }
                case (.mal, "add", 1):
                    mode = .prefill; allowed = ["amount", "merchant", "method"]
                    if let amount = p["amount"] { try integer(amount, range: 1...Int.max) }
                case (.mihbara, "book", 2): try uuid(path[1]); allowed = ["loc"]; if let loc = p["loc"], loc.isEmpty || loc.utf8.count > 2048 { throw CoreError.invalidRoute }
                case (.mihbara, "hadith", 2): guard path[1] == "today" else { throw CoreError.invalidRoute }
                case (.mihbara, "hadith", 3): guard !path[1].isEmpty, path[1].utf8.count <= 64 else { throw CoreError.invalidRoute }; try integer(path[2], range: 1...Int.max)
                default: throw CoreError.invalidRoute
                }
            }
        }
        guard Set(p.keys).isSubset(of: allowed), p.values.allSatisfy({ $0.utf8.count <= 4096 }) else { throw CoreError.invalidRoute }
        guard context.availability.isAvailable(room) else { throw CoreError.unavailableFeature }
        let protected = context.lock == .app
        return .init(room: room, path: path, parameters: p, mode: mode, requiresUnlock: protected && !context.unlocked)
    }
}
