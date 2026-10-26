import AppIntents
import Foundation
import MadarCore

/// §9 single capture. Runs in the app process (RA2) through an in-process handoff, never a public
/// link, and lands with the room's own confirmation and 10-minute undo. Money opens its confirmation sheet; before M6 «فكرة: …» becomes a diary line. The dialog never repeats the text (§14).
struct CaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "التقط في مدار"
    static let description = IntentDescription("جملة واحدة تذهب إلى غرفتها: «صليت العصر جماعة» إلى الصلاة، «قهوة ١٨» إلى تأكيد المصروف، «فكرة: …» إلى دفتر المحبرة، وغيرها إلى صفحة اليوم.")
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "النص", inputOptions: .init(multiline: true)) var text: String

    init() {}
    init(text: String) { self.text = text }

    static var parameterSummary: some ParameterSummary { Summary("التقط \(\.$text)") }
    /// Unclassified capture waits behind the diary gate; an explicit idea waits for Mihbara.
    static let heldDialog: IntentDialog = "افتح المذكرات ليُضاف السطر."

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let route = CaptureRouter.route(text)
        let handled = await MadarIntentHandoff.shared.submit(.capture(text: text, id: UUID()))
        return .result(dialog: CaptureIntentResponse.make(route: route, handled: handled).dialog)
    }
}

enum CaptureIntentResponse: Equatable {
    case added
    case reviewExpense
    case heldExpense
    case savedIdea
    case heldIdea
    case heldDiary
    case choosePrayerStatus
    case prayerRequestSent
    case heldPrayer
    case empty
    case tooLong

    var dialog: IntentDialog {
        switch self {
        case .added: "أُضيف."
        case .reviewExpense: "راجع المصروف واعتمده في مدار."
        case .heldExpense: "افتح المال وأكمل تأكيد المصروف."
        case .savedIdea: "حُفظت الفكرة في دفتر المحبرة."
        case .heldIdea: "افتح المحبرة ليُضاف السطر إلى الدفتر."
        case .heldDiary: CaptureIntent.heldDialog
        case .choosePrayerStatus: "اختر حالة الصلاة في مدار لإكمال تسجيلها."
        case .prayerRequestSent: "وصل طلب تسجيل الصلاة إلى مدار."
        case .heldPrayer: "افتح الصلاة وأكمل تسجيلها في مدار."
        case .empty: "اكتب شيئًا لالتقاطه في مدار."
        case .tooLong: "النص أطول من سطر واحد في صفحة اليوم."
        }
    }

    static func make(route: CaptureRoute, handled: Bool) -> Self {
        switch route {
        case .moneyExpense: handled ? .reviewExpense : .heldExpense
        case .mihbaraIdea: handled ? .savedIdea : .heldIdea
        case .empty: .empty
        case .tooLong: .tooLong
        case .logPrayer: handled ? .prayerRequestSent : .heldPrayer
        case .choosePrayerStatus: handled ? .choosePrayerStatus : .heldPrayer
        case .diaryLine(_, kind: .idea): handled ? .savedIdea : .heldIdea
        case .diaryLine: handled ? .added : .heldDiary
        }
    }
}

enum DiaryIntentDay: String, AppEnum {
    case today, yesterday
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "اليوم")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [.today: "اليوم", .yesterday: "أمس"]
}

/// §9 AddDiaryLineIntent: «blindWrite + deviceUnlock». Confirms «أُضيف» without reading back any diary text (§14).
struct AddDiaryLineIntent: AppIntent {
    static let title: LocalizedStringResource = "أضف سطرًا إلى المذكرات"
    static let description = IntentDescription("يضيف سطرًا إلى صفحة اليوم أو أمس.")
    static let supportedModes: IntentModes = .foreground
    static let authenticationPolicy: IntentAuthenticationPolicy = .requiresAuthentication

    @Parameter(title: "السطر", inputOptions: .init(multiline: true)) var text: String
    @Parameter(title: "اليوم", default: .today) var day: DiaryIntentDay

    init() {}
    init(text: String, day: DiaryIntentDay = .today) { self.text = text; self.day = day }

    static var parameterSummary: some ParameterSummary { Summary("أضف \(\.$text) إلى صفحة \(\.$day)") }

    func perform() async throws -> some IntentResult & ProvidesDialog {
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !line.isEmpty, line.count <= 2000 else { throw AddDiaryLineIntentError.invalidLength }
        let applied = await MadarIntentHandoff.shared.submit(.diaryLine(text: line, day: day.rawValue, id: UUID()))
        return .result(dialog: applied ? "أُضيف." : CaptureIntent.heldDialog)
    }
}

private enum AddDiaryLineIntentError: LocalizedError {
    case invalidLength
    var errorDescription: String? { "اكتب سطرًا من حرف إلى ٢٠٠٠ حرف." }
}
