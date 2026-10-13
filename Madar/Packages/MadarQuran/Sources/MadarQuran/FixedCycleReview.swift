import Foundation
import MadarCore

public enum QuranReviewScheduleMode: String, Codable, CaseIterable, Sendable {
    case spaced
    case fixedJuzDaily
    case fixedManzilWeekly
}

public struct QuranAyahRange: Codable, Hashable, Sendable {
    public let first: Int
    public let last: Int

    public init(first: Int, last: Int) throws {
        guard (1...6_236).contains(first), (1...6_236).contains(last), first <= last else {
            throw QuranReviewError.invalidAyahRange
        }
        self.first = first
        self.last = last
    }

    private enum CodingKeys: String, CodingKey { case first, last }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        try self.init(first: container.decode(Int.self, forKey: .first), last: container.decode(Int.self, forKey: .last))
    }
}

public enum QuranCycleUnit: String, Codable, Sendable {
    case juz
    case manzil
}

public struct QuranCycleSegment: Equatable, Sendable {
    public let number: Int
    public let ayahs: QuranAyahRange

    public init(number: Int, ayahs: QuranAyahRange) {
        self.number = number
        self.ayahs = ayahs
    }
}

public struct QuranReviewCycleTarget: Equatable, Sendable {
    public let unit: QuranCycleUnit
    public let segmentNumber: Int
    public let ayahs: QuranAyahRange
}

public enum QuranFixedCycleEngine {
    public static func target(
        mode: QuranReviewScheduleMode,
        cycleStartDayKey: GregorianDay,
        todayDayKey: GregorianDay,
        juzSegments: [QuranCycleSegment],
        manzilSegments: [QuranCycleSegment]
    ) -> QuranReviewCycleTarget? {
        let offset = dayOffset(from: cycleStartDayKey, through: todayDayKey)
        guard offset >= 0 else { return nil }

        switch mode {
        case .spaced:
            return nil
        case .fixedJuzDaily:
            guard isCompleteMap(juzSegments, count: 30) else { return nil }
            let number = offset % 30 + 1
            guard let segment = juzSegments.first(where: { $0.number == number }) else { return nil }
            return QuranReviewCycleTarget(unit: .juz, segmentNumber: number, ayahs: segment.ayahs)
        case .fixedManzilWeekly:
            guard isCompleteMap(manzilSegments, count: 7) else { return nil }
            let number = offset % 7 + 1
            guard let segment = manzilSegments.first(where: { $0.number == number }) else { return nil }
            return QuranReviewCycleTarget(unit: .manzil, segmentNumber: number, ayahs: segment.ayahs)
        }
    }

    private static func dayOffset(from start: GregorianDay, through today: GregorianDay) -> Int {
        Int((today.date(in: .gmt).timeIntervalSince1970 - start.date(in: .gmt).timeIntervalSince1970) / 86_400)
    }

    private static func isCompleteMap(_ segments: [QuranCycleSegment], count: Int) -> Bool {
        guard segments.count == count,
              Set(segments.map(\.number)) == Set(1...count) else { return false }
        let ordered = segments.sorted { $0.ayahs.first < $1.ayahs.first }
        var nextAyah = 1
        for segment in ordered {
            guard segment.ayahs.first == nextAyah else { return false }
            nextAyah = segment.ayahs.last + 1
        }
        return nextAyah == 6_237
    }
}
