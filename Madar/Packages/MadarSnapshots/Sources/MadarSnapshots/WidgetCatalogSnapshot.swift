import Foundation

/// A saved widget and its already-redacted, app-owned values. No extension reads WidgetConfig or SwiftData.
public struct WidgetCatalogSnapshot: Codable, Sendable, Equatable {
    public static let name = "widgetCatalog"
    public static let valuesName = "widgetValues"
    public struct Row: Codable, Sendable, Equatable, Identifiable {
        public var id: String
        public var title: String
        public var value: String
        public var detail: String
        public var secondDate: String
        public var glyph: String
        public var route: String
        public var share: Double?
        public var targetDate: Date?
        public var money: Bool
        public var preferredFrom: Date? = nil
        public var preferredUntil: Date? = nil
        public var habitID: UUID?
        public init(id: String, title: String, value: String, detail: String = "", secondDate: String = "", glyph: String, route: String, share: Double? = nil, targetDate: Date? = nil, money: Bool = false, habitID: UUID? = nil) {
            self.id = id; self.title = title; self.value = value; self.detail = detail; self.secondDate = secondDate
            self.glyph = glyph; self.route = route; self.share = share; self.targetDate = targetDate; self.money = money; self.habitID = habitID
        }
    }
    public struct Config: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var name: String
        public var familyID: String?
        public var styleJSON: Data
        public var rows: [Row]
        public init(id: UUID, name: String, familyID: String?, styleJSON: Data, rows: [Row]) {
            self.id = id; self.name = name; self.familyID = familyID; self.styleJSON = styleJSON; self.rows = rows
        }
    }
    public var datePrimary: String
    public var dateSecondary: String
    public var configs: [Config]
    public var locked: Bool
    public init(datePrimary: String, dateSecondary: String, configs: [Config], locked: Bool) {
        self.datePrimary = datePrimary; self.dateSecondary = dateSecondary; self.configs = configs; self.locked = locked
    }

    /// A queued completion owns the tap until the app drains it and republishes current data.
    public mutating func hideHabitActions(for habitIDs: Set<UUID>) {
        guard !habitIDs.isEmpty else { return }
        for configIndex in configs.indices {
            for rowIndex in configs[configIndex].rows.indices {
                guard let id = configs[configIndex].rows[rowIndex].habitID, habitIDs.contains(id) else { continue }
                configs[configIndex].rows[rowIndex].habitID = nil
            }
        }
    }
}


extension WidgetCatalogSnapshot.Config {
    /// Timed suggestions move into focus only during their app-derived window; ties keep saved priority.
    public func visibleRows(at date: Date, capacity: Int, smart: Bool) -> [WidgetCatalogSnapshot.Row] {
        guard smart else { return Array(rows.prefix(max(0, capacity))) }
        func rank(_ row: WidgetCatalogSnapshot.Row) -> Int {
            if let start = row.preferredFrom, let end = row.preferredUntil, date >= start && date < end { return 0 }
            return row.targetDate.map { $0 > date ? 1 : 2 } ?? 2
        }
        return Array(rows.enumerated().sorted { a, b in
            let x = rank(a.element), y = rank(b.element)
            if x != y { return x < y }
            if x == 1, let x = a.element.targetDate, let y = b.element.targetDate, x != y { return x < y }
            return a.offset < b.offset
        }.prefix(max(0, capacity)).map(\.element))
    }
}
