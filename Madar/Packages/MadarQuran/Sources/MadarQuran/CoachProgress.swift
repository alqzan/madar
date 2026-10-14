import Foundation

public enum QuranLearningMethod: String, CaseIterable, Codable, Sendable {
    case coach, completeAyah, next, gradual, link
    public var title: String {
        switch self { case .coach: "المدرّب الموجّه"; case .completeAyah: "أكمل الآية"; case .next: "ما بعدها؟"; case .gradual: "إخفاء تدريجي"; case .link: "وصل الصفحات" }
    }
}

/// Device-local progress. The existing draft owns the stage, ayah and page; no duplicated cursor.
public struct QuranCoachProgress: Codable, Equatable, Sendable {
    public var repetitions: Int
    public var bridgeAyahs: [Int]
    public var bridgePending: Bool
    public var learningHints: Int
    public let intensity: QuranReviewIntensity
    public init(bridgeAyahs: [Int] = [], intensity: QuranReviewIntensity = .balanced) {
        repetitions = 0; self.bridgeAyahs = bridgeAyahs; bridgePending = !bridgeAyahs.isEmpty; learningHints = 0
        self.intensity = intensity
    }
    private enum CodingKeys: String, CodingKey { case repetitions, bridgeAyahs, bridgePending, learningHints, intensity }
    public init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        repetitions = try values.decodeIfPresent(Int.self, forKey: .repetitions) ?? 0
        bridgeAyahs = try values.decodeIfPresent([Int].self, forKey: .bridgeAyahs) ?? []
        bridgePending = try values.decodeIfPresent(Bool.self, forKey: .bridgePending) ?? false
        learningHints = try values.decodeIfPresent(Int.self, forKey: .learningHints) ?? 0
        intensity = try values.decodeIfPresent(QuranReviewIntensity.self, forKey: .intensity) ?? .balanced
    }
    public static func repetitionTarget(_ intensity: QuranReviewIntensity) -> Int {
        switch intensity { case .light: 3; case .balanced: 5; case .intense: 7 }
    }
    public static func hiddenWordIndices(ayahID: Int, wordCount: Int, step: Int) -> Set<Int> {
        guard wordCount > 0 else { return [] }
        let count = Int(ceil(Double(wordCount) * Double(min(4, max(1, step + 1))) / 4))
        let stableOrder = (0..<wordCount).sorted {
            let left = (($0 + 1) * 37 + ayahID * 11) % 97
            let right = (($1 + 1) * 37 + ayahID * 11) % 97
            return left == right ? $0 < $1 : left < right
        }
        return Set(stableOrder.prefix(count))
    }
    public mutating func advanceLearning(stage: inout HifzCoachStage, ayahID: inout Int,
                                         pageAyahs: [Int], intensity: QuranReviewIntensity,
                                         method: QuranLearningMethod) {
        guard pageAyahs.contains(ayahID) else { return }
        switch stage {
        case .repetition:
            repetitions += 1
            let target = method == .coach ? Self.repetitionTarget(intensity) : method == .gradual ? 4 : 1
            if repetitions >= target {
                if method == .link { ayahID = pageAyahs[0]; repetitions = 0; stage = .blindRecitation }
                else if method == .coach { stage = .lineStarts }
                else { nextAyah(stage: &stage, ayahID: &ayahID, pageAyahs: pageAyahs) }
            }
        case .lineStarts: stage = .promptedRecall
        case .promptedRecall: nextAyah(stage: &stage, ayahID: &ayahID, pageAyahs: pageAyahs)
        default: break
        }
    }
    private mutating func nextAyah(stage: inout HifzCoachStage, ayahID: inout Int, pageAyahs: [Int]) {
        repetitions = 0
        if let index = pageAyahs.firstIndex(of: ayahID), pageAyahs.indices.contains(index + 1) {
            ayahID = pageAyahs[index + 1]; stage = .repetition
        } else { ayahID = pageAyahs[0]; stage = .blindRecitation }
    }
}
