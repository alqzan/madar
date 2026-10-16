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
