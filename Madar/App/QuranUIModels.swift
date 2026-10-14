import Foundation

// This projection contains domain results and validated read-only resources.
// UI never invents coverage, a grade, a verse, a draft position or a resource license.
enum QuranUILevel: String, CaseIterable, Identifiable, Sendable {
    case simple, medium, deep, max
    var id: String { rawValue }
    var title: String { switch self { case .simple: "بسيط"; case .medium: "متوسط"; case .deep: "عميق"; case .max: "مُحكَم" } }
}
enum QuranUIKind: String, Sendable { case bridge, hifz, review, free, qiyam, drill }
enum QuranUIGrade: String, CaseIterable, Identifiable, Sendable {
    case mastered, good, needs
    var id: String { rawValue }
    var title: String { switch self { case .mastered: "متقن"; case .good: "جيد"; case .needs: "يحتاج إتقانًا" } }
}
enum QuranUIUnit: String, CaseIterable, Identifiable, Sendable {
    case ayah, quarter, half, page
    var id: String { rawValue }
    var title: String { switch self { case .ayah: "آيات"; case .quarter: "ربع وجه"; case .half: "نصف وجه"; case .page: "وجه" } }
}
enum QuranUIRhythm: String, CaseIterable, Identifiable, Sendable {
    case light, balanced, intense
    var id: String { rawValue }
    var title: String { switch self { case .light: "خفيف"; case .balanced: "متوازن"; case .intense: "مكثّف" } }
}
enum QuranUIMissChoice: String, CaseIterable, Identifiable, Sendable {
    case spread, double, skip
    var id: String { rawValue }
    var title: String { switch self { case .spread: "وزّعه على ثلاثة أيام"; case .double: "ضاعف اليوم"; case .skip: "تجاوزه" } }
}
struct QuranUIRange: Sendable { var fromPage: Int; var toPage: Int }
struct QuranUISurah: Identifiable, Sendable { var id: Int; var title: String; var firstAyah: Int; var ayahCount: Int }
struct QuranUIPlanInput: Sendable { var startAyah: Int; var unit: QuranUIUnit; var amount: Double; var rhythm: QuranUIRhythm; var restDay: String; var missPolicy: String }
struct QuranUIForecast: Sendable { var title: String; var assumptions: String; var warning: String?; var portions: [String] }
struct QuranUIPlan: Sendable { var title: String; var input: QuranUIPlanInput; var forecast: QuranUIForecast; var nextAyah: Int; var versionLabel: String }
struct QuranUIStep: Identifiable, Sendable { var id: String; var title: String; var detail: String; var kind: QuranUIKind; var completed: Bool; var available: Bool; var range: QuranUIRange? }
struct QuranUIHeatDay: Identifiable, Sendable { var id: String; var title: String; var hifzFraction: Double; var reviewFraction: Double; var accessibilityLabel: String }
struct QuranUIDraft: Identifiable, Sendable { var id: UUID; var title: String; var isPastDay: Bool }
struct QuranUIHistorySession: Identifiable, Sendable { var id: UUID; var title: String; var dateLabel: String; var detail: String; var grades: [QuranUIPageGrade]; var warning: String? }
struct QuranUIPageGrade: Identifiable, Sendable { var page: Int; var title: String; var grade: QuranUIGrade; var explanation: String; var id: Int { page } }
struct QuranUIHistory: Sendable { var weekSummary: [String]; var yearSummary: [String]; var allSummary: [String]; var days: [QuranUIHeatDay]; var coverage: [QuranUIIndexItem]; var sessions: [QuranUIHistorySession] }
enum QuranUIIndexUnit: String, CaseIterable, Identifiable, Sendable {
    case surah, ayah, juz, hizb, page
    var id: String { rawValue }
    var title: String { switch self { case .surah: "السور"; case .ayah: "الآيات"; case .juz: "الأجزاء"; case .hizb: "الأحزاب"; case .page: "الأوجه" } }
    var icon: String { switch self { case .surah: "line.3.horizontal.decrease"; case .ayah: "rosette"; case .juz: "square.grid.2x2"; case .hizb: "square.grid.3x3"; case .page: "doc" } }
}
struct QuranUIIndexItem: Identifiable, Sendable { var id: String; var title: String; var subtitle: String; var firstPage: Int; var fraction: Double; var memorized: Bool; var reviewed: Bool; var due: Bool; var isToday: Bool }
struct QuranUIStrength: Identifiable, Sendable { var id: Int; var title: String; var value: Int?; var pageDetails: [String]; var canRaise: Bool; var reviewRange: QuranUIRange? }
struct QuranUIRecovery: Sendable { var distantLabel: String; var activeTitle: String?; var canCreate: Bool; var previews: [Int: QuranUIForecast] }
struct QuranUIQiyamPreview: Sendable { var rakaat: Int; var nightKey: String; var title: String; var assignments: [String]; var canBegin: Bool }
struct QuranUIErrorSpot: Identifiable, Sendable { var id: String; var title: String; var detail: String; var isToday: Bool; var closed: Bool; var canDrill: Bool }
struct QuranRoomState: Sendable {
    var coverageTitle: String
    var coverageFraction: Double
    var percentageLabel: String
    var streakLabel: String
    var balanceTitle: String
    var balanceExplanation: String
    var hifzLevel: QuranUILevel
    var reviewLevel: QuranUILevel
    var steps: [QuranUIStep]
    var recentDays: [QuranUIHeatDay]
    var plan: QuranUIPlan?
    var surahs: [QuranUISurah]
    var draft: QuranUIDraft?
    var missedDayKey: String?
    var missedDayTitle: String?
    var summary: [String]
    var history: QuranUIHistory
    var strengthTitle: String
    var strength: [QuranUIStrength]
    var recovery: QuranUIRecovery
    var errors: [QuranUIErrorSpot]
    var toolsOrder: [String]
    var availableTools: Set<String>
    var blockOrder: [String]
    var hiddenBlocks: Set<String>
    var sessionUnavailableReason: String?
    var readerUnavailableReason: String?
    var numeralLocale: String
}
enum QuranUICommand: Sendable {
    case setTodayLevel(kind: QuranUIKind, level: QuranUILevel)
    case forceNewHifz
    case savePlan(QuranUIPlanInput)
    case resolveMissed(dayKey: String, choice: QuranUIMissChoice)
    case editSessionGrade(sessionID: UUID, page: Int, grade: QuranUIGrade)
    case deleteSession(UUID)
    case createRecovery(days: Int)
    case cancelRecovery
    case raisePages(juz: Int)
}
struct QuranUILine: Identifiable, Sendable { var id: Int; var glyphs: String; var semanticText: String }
struct QuranUIPage: Sendable {
    var page: Int
    var title: String
    var postScriptName: String // registered official Hafs 2.0 font; text and 1439 logical layout verified
    var lines: [QuranUILine]
    var semanticAyat: [QuranUIVerse]
}
struct QuranUIVerse: Identifiable, Sendable { var id: Int; var title: String; var text: String; var hidden: Bool; var canReveal: Bool }
struct QuranUIAnswer: Identifiable, Sendable { var id: String; var text: String }
struct QuranUISimilar: Sendable { var title: String; var left: String; var right: String; var explanation: String }
enum QuranUISessionStage: String, Sendable { case repetition, lineStarts, recall, covered, grading, review, drill, qiyam }
enum QuranUISessionAction: Sendable {
    case advance
    case reveal(ayahID: Int, wordIndex: Int?)
    case mistake(ayahID: Int, wordIndex: Int?)
    case chooseAnswer(String)
    case grade(page: Int, grade: QuranUIGrade)
    case changeMethod(String)
    case commit, commitPartial, discard, saveProgress
}
struct QuranUISessionState: Identifiable, Sendable {
    var id: UUID
    var title: String
    var segmentTitle: String
    var stage: QuranUISessionStage
    var progress: Double
    var prompt: String
    var verses: [QuranUIVerse]
    var page: QuranUIPage?
    var answers: [QuranUIAnswer]
    var grades: [QuranUIPageGrade]
    var primaryTitle: String
    var primaryAction: QuranUISessionAction
    var canAdvance: Bool
    var mistakeAyahID: Int?
    var method: String
    var availableMethods: [String: String]
    var similar: QuranUISimilar?
    var resourceError: String?
}
enum QuranUISessionResult: Sendable { case active(QuranUISessionState), completed(summary: [String]), discarded }
@MainActor protocol QuranUIService: AnyObject {
    func load() async throws -> QuranRoomState
    func perform(_ command: QuranUICommand) async throws
    func previewPlan(_ input: QuranUIPlanInput) async throws -> QuranUIForecast
    func index(_ unit: QuranUIIndexUnit) async throws -> [QuranUIIndexItem]
    func page(_ page: Int) async throws -> QuranUIPage
    func qiyamPreview(rakaat: Int) async throws -> QuranUIQiyamPreview
    func start(kind: QuranUIKind, stepID: String?, range: QuranUIRange?, rakaat: Int?, spotID: String?) async throws -> QuranUISessionState
    func resume(draftID: UUID) async throws -> QuranUISessionState
    // Every action saves SessionDraft before returning. Commit checks commitID and is atomic.
    func session(draftID: UUID, action: QuranUISessionAction) async throws -> QuranUISessionResult
}
