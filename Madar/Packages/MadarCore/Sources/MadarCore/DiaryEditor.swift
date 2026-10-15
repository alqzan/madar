import Foundation

public enum DiaryEditorCommand: Codable, Equatable, Sendable {
    case saveDraft(id: UUID, text: String, day: String, target: String?, writingDay: String)
    case commitDraft(UUID)
    case appendMedia(file: UUID, kind: String, type: String, caption: String, day: String, writingDay: String, duration: Int?)
    case transcript(entry: UUID, text: String)
    case intention(id: UUID, day: String, text: String)
    case intentionResult(id: UUID, result: String?)
    case edit(entry: UUID, revision: UUID, text: String)
    // §7.3 N04 letters and projects.
    case sealLetter(id: UUID, text: String, trigger: DiaryLetterTrigger, value: String?, target: UUID?)
    case refreshLetters
    case openLetter(UUID)
    case rescheduleLetter(id: UUID, day: String)
    case saveProject(id: UUID, name: String, intention: String, keyword: String?)
    case finishProject(id: UUID, reflection: String?)
    case deleteProject(UUID)
    case linkEntry(entry: UUID, project: UUID?)
    public static let names: Set<String> = ["diary.saveDraft", "diary.commitDraft", "diary.appendMedia", "diary.setTranscript", "diary.setIntention", "diary.setIntentionResult", "diary.editEntry", "diary.sealLetter", "diary.refreshLetters", "diary.openLetter", "diary.rescheduleLetter", "diary.saveProject", "diary.finishProject", "diary.deleteProject", "diary.linkEntry"]
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
        case "diary.setIntention":
            guard Set(value.keys) == ["id","dayKey","text"],let id=uuid("id"),let day=value["dayKey"]?.string,(try? GregorianDay(day)) != nil,let text=value["text"]?.string,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
            return .intention(id:id,day:day,text:text)
        case "diary.setIntentionResult":
            guard Set(value.keys) == ["id","result"],let id=uuid("id"),value["result"] == .null || value["result"]?.string.map({["done","partial","notEasy"].contains($0)}) == true else{return nil}
            return .intentionResult(id:id,result:value["result"]?.string)
        case "diary.editEntry":
            guard Set(value.keys) == ["entryID", "revisionID", "text"], let id = uuid("entryID"), let revision = uuid("revisionID"), revision != id, let text = value["text"]?.string,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .edit(entry: id, revision: revision, text: text)
        case "diary.sealLetter":
            guard Set(value.keys).isSubset(of: ["id", "text", "trigger", "value", "targetID"]), let id = uuid("id"), let text = value["text"]?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let trigger = value["trigger"]?.string.flatMap(DiaryLetterTrigger.init(rawValue:)) else { return nil }
            let raw = value["value"]?.string, target = uuid("targetID")
            guard value["targetID"] == nil || target != nil else { return nil }
            switch trigger {
            case .date: guard let raw, (try? GregorianDay(raw)) != nil else { return nil }
            case .hijriDate: guard let raw, raw.range(of: #"^\d{4}-\d{2}-\d{2}$"#, options: .regularExpression) != nil else { return nil }
            case .projectFinished: guard target != nil, raw == nil else { return nil }
            case .tripStart, .tripEnd, .ramadanStart: guard raw == nil else { return nil }
            }
            return .sealLetter(id: id, text: text, trigger: trigger, value: raw, target: target)
        case "diary.refreshLetters": return value.isEmpty ? .refreshLetters : nil
        case "diary.openLetter": guard Set(value.keys) == ["id"], let id = uuid("id") else { return nil }; return .openLetter(id)
        case "diary.rescheduleLetter":
            guard Set(value.keys) == ["id", "dayKey"], let id = uuid("id"), let day = value["dayKey"]?.string, (try? GregorianDay(day)) != nil else { return nil }
            return .rescheduleLetter(id: id, day: day)
        case "diary.saveProject":
            guard Set(value.keys).isSubset(of: ["id", "name", "intention", "keyword"]), let id = uuid("id"), let name = value["name"]?.string, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
                  let intention = value["intention"]?.string else { return nil }
            let keyword = value["keyword"]?.string.map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            return .saveProject(id: id, name: name, intention: intention, keyword: keyword?.isEmpty == true ? nil : keyword)
        case "diary.finishProject":
            guard Set(value.keys).isSubset(of: ["id", "reflection"]), let id = uuid("id") else { return nil }; return .finishProject(id: id, reflection: value["reflection"]?.string)
        case "diary.deleteProject": guard Set(value.keys) == ["id"], let id = uuid("id") else { return nil }; return .deleteProject(id)
        case "diary.linkEntry":
            guard Set(value.keys) == ["entryID", "projectID"], let entry = uuid("entryID"), value["projectID"] == .null || uuid("projectID") != nil else { return nil }
            return .linkEntry(entry: entry, project: uuid("projectID"))
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
