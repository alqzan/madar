import AppIntents
import Foundation

struct OpenDiaryWriterIntent:AppIntent {
    static let title:LocalizedStringResource="اكتب سطرًا سريعًا"
    static let supportedModes:IntentModes = .foreground
    func perform() async throws->some IntentResult & OpensIntent {
        .result(opensIntent:OpenURLIntent(URL(string:"madar://notes/write")!))
    }
}
struct OpenHabitsRoomIntent:AppIntent {
    static let title:LocalizedStringResource="افتح عاداتك"
    static let supportedModes:IntentModes = .foreground
    func perform() async throws->some IntentResult & OpensIntent {
        .result(opensIntent:OpenURLIntent(URL(string:"madar://bahw/habits")!))
    }
}

/// §9 OpenRoomIntent(room): built rooms only (including Mihbara after M6).
enum MadarRoomDestination: String, AppEnum {
    case lobby, salah, quran, notes, habits, year, money, mihbara
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "الغرفة")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .money: "المال", .lobby: "البهو", .salah: "الصلاة", .quran: "القرآن", .notes: "المذكرات", .habits: "العادات", .year: "السنة وما يهمّك", .mihbara: "المحبرة"
    ]
    var url: URL {
        switch self {
        case .money: URL(string: "madar://mal")!
        case .lobby: URL(string: "madar://bahw")!
        case .salah: URL(string: "madar://salah")!
        case .quran: URL(string: "madar://quran")!
        case .notes: URL(string: "madar://notes/today")!
        case .habits: URL(string: "madar://bahw/habits")!
        case .year: URL(string: "madar://bahw/year")!
        case .mihbara: URL(string: "madar://mihbara")!
        }
    }
}
struct OpenRoomIntent: AppIntent {
    static let title: LocalizedStringResource = "افتح غرفة في مدار"
    static let supportedModes: IntentModes = .foreground
    @Parameter(title: "الغرفة") var room: MadarRoomDestination
    init() {}
    init(room: MadarRoomDestination) { self.room = room }
    static var parameterSummary: some ParameterSummary { Summary("افتح \(\.$room)") }
    func perform() async throws -> some IntentResult & OpensIntent {
        .result(opensIntent: OpenURLIntent(room.url))
    }
}

/// Owner, 30 Oct: «أكمل القراءة» opens the book on the stand at the saved place. The intent runs outside the store, so it asks the app for `madar://mihbara/continue` and the room picks the book.
struct ContinueReadingIntent: AppIntent {
    static let title: LocalizedStringResource = "أكمل القراءة"
    static let supportedModes: IntentModes = .foreground
    func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "madar://mihbara/continue")!)) }
}

struct OpenMoneyExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل مصروفًا"
    static let supportedModes: IntentModes = .foreground
    func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "madar://mal/add")!)) }
}
