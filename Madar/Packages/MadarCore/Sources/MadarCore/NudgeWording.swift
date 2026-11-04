import Foundation

/// Varied wording for the gentle pushes (owner, 4 Nov 2026): the same moment reads differently from day to day, never the same
/// sentence two days running, and never blames («لا لوم» is a rule, not a style). The pick depends only on the moment and the day key,
/// so a rescheduled request keeps its wording and a test can name the expected sentence from the rule.
public enum NudgeWording {
    public enum Moment: String, CaseIterable, Sendable {
        case habitFirstStep, habitKeepStreak, quranWird, quranReview, diaryNiyya, diaryLine
    }

    public static func variants(_ moment: Moment) -> [String] {
        switch moment {
        case .habitFirstStep:
            ["بدأ وقتها، وخطوة صغيرة اليوم تبدأ سلسلتك", "وقتها الآن؛ أصغر خطوة تكفي لتبدأ", "حين تتيسّر لك، خطوة واحدة تفتح السلسلة", "اليوم فرصة جديدة؛ ابدأ بأقل ما تقدر عليه"]
        case .habitKeepStreak:
            ["بدأ وقتها، وأقلّ القليل يحفظ سلسلتك", "وقتها الآن؛ خطوة خفيفة تُبقي سلسلتك ممتدة", "سلسلتك تمشي معك؛ خطوة صغيرة اليوم تكفيها", "حين تتيسّر لك، أقلّ القليل يحفظ ما بنيته"]
        case .quranWird:
            ["دقائق مع القرآن تكفي، تابع من حيث توقفت", "وردك جاهز من الموضع الذي وقفت عنده", "صفحة هادئة اليوم تكفي لتبقى معه", "افتح من حيث توقفت؛ لا تحتاج أكثر من وقت قصير"]
        case .quranReview:
            ["أوجه تنتظر مراجعتك قبل أن تبعد عنك", "مراجعة قصيرة اليوم تُبقي ما حفظته قريبًا", "بضع صفحات من مراجعتك تنتظرك متى تيسّر", "مراجعة خفيفة الآن أيسر من مراجعتها لاحقًا"]
        case .diaryNiyya:
            ["ما نيّتك لهذا اليوم؟ سطر واحد يكفي", "بماذا تبدأ يومك؟ اكتب نيّته في سطر", "سطر عن نيّتك يضبط بوصلة اليوم", "قبل أن ينشغل اليوم: ما الذي تقصده منه؟"]
        case .diaryLine:
            ["كيف كان يومك؟ سطر واحد يكفي", "ما الذي تودّ أن تتذكره من اليوم؟ سطر واحد", "قبل أن ينتهي اليوم: لحظة واحدة تستحق سطرًا؟", "ماذا بقي في قلبك من اليوم؟ اكتبه في سطر"]
        }
    }

    /// Stable across launches (no `hashValue`, which Swift seeds per process). The day number walks the list by a step that is
    /// never 0 and never shares a factor with its length, so the next day always reads differently and every variant comes round.
    public static func body(_ moment: Moment, dayKey: String) -> String {
        let all = variants(moment)
        let count = all.count
        let start = fnv(moment.rawValue)
        guard let day = try? GregorianDay(dayKey) else { return all[Int(fnv(moment.rawValue + "|" + dayKey) % UInt64(count))] }
        let steps = (1..<count).filter { gcd($0, count) == 1 }
        let step = steps[Int((start >> 8) % UInt64(steps.count))]
        let ordinal = Int(day.date(in: .gmt).timeIntervalSince1970 / 86_400)
        return all[(Int(start % UInt64(count)) + step * ordinal % count + count) % count]
    }

    private static func fnv(_ text: String) -> UInt64 {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in text.utf8 { hash = (hash ^ UInt64(byte)) &* 0x100000001b3 }
        return hash
    }

    private static func gcd(_ a: Int, _ b: Int) -> Int { b == 0 ? a : gcd(b, a % b) }
}
