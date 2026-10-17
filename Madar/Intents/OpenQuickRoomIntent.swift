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

/// §9 OpenRoomIntent(room): built rooms only (no money or Mihbara before M5/M6).
enum MadarRoomDestination: String, AppEnum {
    case lobby, salah, quran, notes, habits, year, money
    static let typeDisplayRepresentation = TypeDisplayRepresentation(name: "الغرفة")
    static let caseDisplayRepresentations: [Self: DisplayRepresentation] = [
        .money: "المال", .lobby: "البهو", .salah: "الصلاة", .quran: "القرآن", .notes: "المذكرات", .habits: "العادات", .year: "السنة وما يهمّك"
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

struct OpenMoneyExpenseIntent: AppIntent {
    static let title: LocalizedStringResource = "سجّل مصروفًا"
    static let supportedModes: IntentModes = .foreground
    func perform() async throws -> some IntentResult & OpensIntent { .result(opensIntent: OpenURLIntent(URL(string: "madar://mal/add")!)) }
}
