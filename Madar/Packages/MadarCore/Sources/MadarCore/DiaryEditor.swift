import Foundation

public enum DiaryEditorCommand: Codable, Equatable, Sendable {
    case saveDraft(id: UUID, text: String, day: String, target: String?, writingDay: String)
    case commitDraft(UUID)
    case appendMedia(file: UUID, kind: String, type: String, caption: String, day: String, writingDay: String, duration: Int?)
    case transcript(entry: UUID, text: String)
    public static let names: Set<String> = ["diary.saveDraft", "diary.commitDraft", "diary.appendMedia", "diary.setTranscript"]
    public static func parse(_ name: String, _ value: [String: JSONValue]) -> Self? {
        func uuid(_ key: String) -> UUID? { value[key]?.string.flatMap(UUID.init(uuidString:)) }
        switch name {
        case "diary.saveDraft":
            guard Set(value.keys).isSubset(of: ["id", "text", "day", "targetDayKey", "writingDayKey"]), let id = uuid("id"), let text = value["text"]?.string, let day = value["day"]?.string, ["today", "yesterday"].contains(day) else { return nil }
            guard let writingDay = value["writingDayKey"]?.string, (try? GregorianDay(writingDay)) != nil else { return nil }
            let target = value["targetDayKey"]?.string
            guard value["targetDayKey"] == nil || target.flatMap({ try? GregorianDay($0) }) != nil else { return nil }
            return .saveDraft(id: id, text: text, day: day, target: target, writingDay: writingDay)
        case "diary.commitDraft":
            guard Set(value.keys) == ["id"], let id = uuid("id") else { return nil }; return .commitDraft(id)
        case "diary.appendMedia":
            guard Set(value.keys).isSubset(of: ["fileID", "kind", "contentType", "caption", "day", "durationS", "writingDayKey"]), let id = uuid("fileID"), let kind = value["kind"]?.string, ["photo", "audio", "video", "document"].contains(kind),
                let type = value["contentType"]?.string, !type.isEmpty, let caption = value["caption"]?.string, let day = value["day"]?.string, ["today", "yesterday"].contains(day) else { return nil }
            guard let writingDay = value["writingDayKey"]?.string, (try? GregorianDay(writingDay)) != nil else { return nil }
            let duration = value["durationS"]?.number
            guard value["durationS"] == nil || duration.map({ $0 >= 0 && $0 < Double(Int.max) && $0.rounded() == $0 }) == true else { return nil }
            return .appendMedia(file: id, kind: kind, type: type, caption: caption, day: day, writingDay: writingDay, duration: duration.map(Int.init))
        case "diary.setTranscript":
            guard Set(value.keys) == ["entryID", "text"], let id = uuid("entryID"), let text = value["text"]?.string else { return nil }; return .transcript(entry: id, text: text)
        default: return nil
        }
    }
}

public enum DiarySpeechRoute: Equatable, Sendable { case transcriber, recognizerOnDevice, appleServer, needsConsent, audioOnly }
public enum DiarySpeechPolicy {
    public static func route(authorized: Bool, transcriberInstalled: Bool, recognizerAvailable: Bool, recognizerOnDevice: Bool, serverConsent: Bool) -> DiarySpeechRoute {
        guard authorized else { return .audioOnly }
        if transcriberInstalled { return .transcriber }
        guard recognizerAvailable else { return .audioOnly }
        if recognizerOnDevice { return .recognizerOnDevice }
        return serverConsent ? .appleServer : .needsConsent
    }
}

private extension JSONValue {
    var string: String? { if case .string(let value) = self { value } else { nil } }
    var number: Double? { if case .number(let value) = self { value } else { nil } }
}
