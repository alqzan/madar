import AppIntents
import Foundation

enum QuranIntentStep: String, AppEnum {
    case hifz, review, drill
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "الخطوة")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.hifz: "الورد", .review: "المراجعة", .drill: "مواضع الخطأ"]
}
struct StartQuranSessionIntent: AppIntent {
    static let title: LocalizedStringResource = "ابدأ جلسة القرآن"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "الخطوة", default: .review) var step: QuranIntentStep
    init() {}
    init(step: QuranIntentStep) { self.step = step }
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(URL(string: "madar://quran/session/" + step.rawValue)!))
    }
}
