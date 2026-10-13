import Foundation
import MadarCore

public enum PrayerDomainError: Error, Equatable { case beforeTrackingStart, futurePrayer, prayerWindowOpen, unavailablePrayerTimes, invalidShortening, invalidPair, noActiveTrip, invalidNight, invalidRakaat, trackingAlreadyEdited, invalidTrackingStart, staleUndo, invalidRecord, explicitRestoreRequired }
public enum PrayerDisplayStatus: String, Codable, Sendable { case jamaah, alone, qada, missed, unrecordedHistory, unconfirmed, excused, pending, future }
public struct PrayerCell: Equatable, Identifiable, Sendable {
    public let reference: PrayerReference
    public var id: PrayerReference { reference }
    public let status: PrayerDisplayStatus
    public let heart: PrayerHeart?
    public let time: Date?
    /// The calculated prayer time, even after the prayer is logged (`time` then holds the log's eventAt).
    public let prayerTime: Date?
    public let shortened: Bool
    public let fridayKind: FridayPrayerKind?
    public let pairID: UUID?
    public let isFriday: Bool
    public let canLog: Bool
    public let canMarkMissed: Bool
    public let canMakeUp: Bool
}
public struct PrayerDaySummary: Equatable, Sendable {
    public let day: GregorianDay
    public let cells: [PrayerCell]
}
public struct PrayerStatistics: Equatable, Sendable {
    public let onTime: Int
    public let denominator: Int
    public let madeUp: Int
    public let owed: Int
    public let prayerStreak: Int
    public let congregationStreak: Int
    public let completionStreak: Int
    public let heartDistribution: [PrayerHeart: Int]
    public let last25: [PrayerCell]
    public let commitment: [Prayer: (jamaah: Int, alone: Int, denominator: Int)]
    public var percentage: Int? { denominator == 0 ? nil : Int((Double(onTime) / Double(denominator) * 100).rounded()) }
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.onTime == rhs.onTime && lhs.denominator == rhs.denominator && lhs.madeUp == rhs.madeUp && lhs.owed == rhs.owed && lhs.prayerStreak == rhs.prayerStreak && lhs.congregationStreak == rhs.congregationStreak && lhs.completionStreak == rhs.completionStreak && lhs.heartDistribution == rhs.heartDistribution && lhs.last25 == rhs.last25 && Prayer.allCases.allSatisfy { lhs.commitment[$0]?.jamaah == rhs.commitment[$0]?.jamaah && lhs.commitment[$0]?.alone == rhs.commitment[$0]?.alone && lhs.commitment[$0]?.denominator == rhs.commitment[$0]?.denominator }
    }
}
public struct PrayerQada: Equatable, Identifiable, Sendable {
    public let id: UUID
    public let reference: PrayerReference
    public let madeUpAt: Date?
    public let fridayKind: FridayPrayerKind?
    public let isFriday: Bool
}
public struct PrayerNight: Equatable, Sendable {
    public let night: GregorianDay
    public let rakaat: Int
    public let witr: Bool
    public let quranSessionID: UUID?
}
public struct PrayerTrip: Equatable, Sendable {
    public let id: UUID
    public let city: String
    public let place: ActivePlace
    public let start: Date
    public let end: Date?
}
public struct PrayerOccurrence: Equatable, Sendable {
    public let reference: PrayerReference
    public let time: Date
    public let place: ActivePlace
    public let tripID: UUID?
}
public struct PrayerTracking: Equatable, Sendable {
    public let day: GregorianDay
    public let firstRun: GregorianDay
    public let editAnchor: GregorianDay?
    public let edits: Int
}
public struct PrayerSnapshot: Equatable, Sendable {
    public let today: PrayerDaySummary
    public let history: [PrayerDaySummary]
    public let tracking: PrayerTracking
    public let pending: [PrayerReference]
    public let unconfirmed: [PrayerReference]
    public let unconfirmedFridayNoon: Set<PrayerReference>
    public let pendingHeart: [PrayerReference]
    public let statistics: PrayerStatistics
    public let qada: [PrayerQada]
    public let nights: [PrayerNight]
    public let nightDefault: GregorianDay
    public let activeTrip: PrayerTrip?
    public let next: PrayerOccurrence?
    public let estimated: Bool
    public let placeName: String
    public let hasTimes: Bool
}
