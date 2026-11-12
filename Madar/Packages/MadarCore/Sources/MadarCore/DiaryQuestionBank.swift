import Foundation

/// A curated bank of gentle Arabic questions (owner, 12 Nov 2026): the on-device model never writes Arabic for the diary.
/// It may only choose which bank questions fit the recent writing; the question shown is always the bank's own text.
public enum DiaryQuestionGroup: String, CaseIterable, Sendable { case aboutDiary, reflective }

public struct DiaryQuestion: Equatable, Sendable {
    public let arabic: String
    /// A few English words for the model's choice only; never shown.
    public let topic: String
}

public enum DiaryQuestionBank {
    public static func questions(_ group: DiaryQuestionGroup) -> [DiaryQuestion] {
        switch group { case .aboutDiary: aboutDiary; case .reflective: reflective }
    }

    /// Three distinct bank indices: the model's valid, distinct choices first (in its order), then a day-based rotation fills the rest.
    /// A nil, short or out-of-range model answer therefore still yields three questions, and nothing is ever invented.
    public static func selection(group: DiaryQuestionGroup, modelIndices: [Int]?, seed: Int, count: Int = 3) -> [Int] {
        let size = questions(group).count
        guard size > 0 else { return [] }
        var chosen: [Int] = []
        for index in modelIndices ?? [] where (0..<size).contains(index) && !chosen.contains(index) && chosen.count < count {
            chosen.append(index)
        }
        let start = ((seed % size) + size) % size
        var step = 0
        while chosen.count < min(count, size) {
            let candidate = (start * count + step) % size
            if !chosen.contains(candidate) { chosen.append(candidate) }
            step += 1
        }
        return chosen
    }

    private static let aboutDiary: [DiaryQuestion] = [
        .init(arabic: "ما أكثر شيء تكرّر في كتابتك هذه الأيام؟", topic: "recurring themes"),
        .init(arabic: "من الشخص الذي ذكرته أكثر من غيره مؤخرًا، وماذا يعني لك؟", topic: "a person mentioned often"),
        .init(arabic: "ما الأمر الذي بدأت الكتابة عنه ولم تُكمله؟", topic: "something left unfinished"),
        .init(arabic: "كيف كان شعورك حين كتبت آخر سطر؟", topic: "feelings while writing"),
        .init(arabic: "ما الشيء الصغير الذي كتبته وربما كان أكبر مما بدا؟", topic: "a small thing that mattered"),
        .init(arabic: "متى كتبت آخر مرة وأنت مرتاح؟", topic: "a moment of ease"),
        .init(arabic: "ما الذي تتمنى لو أنك كتبت عنه أكثر؟", topic: "what is left unwritten"),
        .init(arabic: "أي يوم من الأيام الماضية تودّ أن تعود إليه، وماذا فيه؟", topic: "a day worth returning to"),
        .init(arabic: "ما الذي تغيّر في طريقة كتابتك عن نفسك؟", topic: "change in how one writes"),
        .init(arabic: "ما الأمر الذي ظل معلّقًا في بالك طوال هذه الأيام؟", topic: "a lingering worry or thought"),
        .init(arabic: "ما أجمل لحظة كتبت عنها مؤخرًا، وما الذي جعلها كذلك؟", topic: "a beautiful moment"),
        .init(arabic: "ما الذي كتبته وتودّ أن يقرأه أحد يحبك؟", topic: "wanting to be understood"),
        .init(arabic: "ما الذي ما زال ينتظر قرارًا منك مما ذكرته؟", topic: "a pending decision"),
        .init(arabic: "أين كنت حين كتبت آخر سطر مهم، وماذا كان حولك؟", topic: "place and surroundings"),
        .init(arabic: "ما الذي تلمّح إليه كثيرًا دون أن تقوله صراحة؟", topic: "things hinted but unsaid"),
        .init(arabic: "كيف تبدو الأيام التي تكتب فيها أكثر مقارنة بالتي تكتب فيها أقل؟", topic: "busy versus quiet days"),
        .init(arabic: "ما الأمر الذي كان يقلقك في أول الشهر وصار أخف؟", topic: "a worry that eased"),
        .init(arabic: "من كان معك في أفضل أوقاتك مؤخرًا؟", topic: "company in good times"),
        .init(arabic: "ما الذي عرفته عن نفسك من سطورك الأخيرة؟", topic: "self-knowledge"),
        .init(arabic: "ماذا تحب أن تقول لنفسك التي كتبت قبل أسبوع؟", topic: "a note to one's earlier self"),
    ]

    private static let reflective: [DiaryQuestion] = [
        .init(arabic: "ما الذي يمنح أيامك معناها هذه الفترة؟", topic: "meaning"),
        .init(arabic: "كيف تقضي الوقت الذي لا يطلبه منك أحد؟", topic: "free time"),
        .init(arabic: "ما الذي تحتاج أن تصبر عليه أكثر؟", topic: "patience"),
        .init(arabic: "ما النعمة التي تمرّ بها كل يوم دون أن تنتبه لها؟", topic: "gratitude"),
        .init(arabic: "إلى أين تحب أن تكون قد وصلت بعد سنة من الآن؟", topic: "direction and future"),
        .init(arabic: "ما الذي تودّ أن تتركه خلفك بهدوء؟", topic: "letting go"),
        .init(arabic: "متى شعرت آخر مرة أن وقتك كان في مكانه الصحيح؟", topic: "time well spent"),
        .init(arabic: "ما الذي تحمله منذ زمن وقد حان وقت وضعه؟", topic: "a long burden"),
        .init(arabic: "من الذي تدين له بكلمة شكر لم تقلها؟", topic: "thanks owed to someone"),
        .init(arabic: "ما الذي يُشعرك بالطمأنينة حين تقلق؟", topic: "comfort in anxiety"),
        .init(arabic: "كيف تحب أن يتذكرك المقرّبون منك؟", topic: "legacy among loved ones"),
        .init(arabic: "ما الذي كنت تظنه مهمًا قبل سنوات ولم يعد كذلك؟", topic: "changed priorities"),
        .init(arabic: "ما العادة الصغيرة التي لو ثبتّ عليها لتغيّرت أيامك؟", topic: "small habits"),
        .init(arabic: "ما الذي تخشى أن يفوتك؟", topic: "fear of missing out on what matters"),
        .init(arabic: "أي نعمة صرت تراها أعظم مما كنت ترى؟", topic: "appreciating blessings"),
        .init(arabic: "كيف تتعامل مع الانتظار حين يطول؟", topic: "waiting"),
        .init(arabic: "ما الذي يجعلك تشعر أنك على الطريق الصحيح؟", topic: "being on the right path"),
        .init(arabic: "ماذا تعلّمك الأيام الثقيلة عادةً؟", topic: "lessons from hard days"),
        .init(arabic: "ما الذي تتمنى أن يعرفه عنك من لا يعرفك جيدًا؟", topic: "being known"),
        .init(arabic: "أين تجد راحتك حين يثقل عليك كل شيء؟", topic: "rest when overwhelmed"),
    ]
}
