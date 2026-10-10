import Foundation

public enum Room: String, Codable, CaseIterable, Sendable { case bahw, salah, quran, notes, mal, mihbara, habits, year, core }
public struct FeatureAvailability: Sendable {
    public let builtRooms: Set<Room>
    public init(builtRooms: Set<Room>) { self.builtRooms = builtRooms }
    public static let m0 = Self(builtRooms: [.core])
    public func isAvailable(_ room: Room) -> Bool { builtRooms.contains(room) }
}
public struct DayEvent: Codable, Equatable, Sendable {
    public let kind: String
    public let eventID: UUID
    public let dayKey: String
    public init(kind: String, eventID: UUID, dayKey: String) { self.kind = kind; self.eventID = eventID; self.dayKey = dayKey }
}
/// M0 wiring only: subscriber ownership exists, but publishing cannot synthesize diary rows.
public struct DayEventBus: Sendable {
    public let subscriberRooms: Set<Room>
    public init(subscriberRooms: Set<Room> = [.notes]) { self.subscriberRooms = subscriberRooms }
    public func publish(_ event: DayEvent) -> [DayEvent] { [] }
}
