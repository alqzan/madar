import Foundation

public enum DiaryEditorCommand: Codable, Equatable, Sendable {
    case saveDraft(id: UUID, text: String, day: String, target: String?, writingDay: String)
    /// `at` places the new line at a chosen moment between two lines of the same day (never in the future).
    case commitDraft(UUID, at: Double? = nil)
    case appendMedia(file: UUID, kind: String, type: String, caption: String, day: String, writingDay: String, duration: Int?, asset: String? = nil, at: Double? = nil)
    case transcript(entry: UUID, text: String)
    case audioInsights(media: UUID, title: String?, levels: [Double])
    case intention(id: UUID, day: String, text: String)
    case intentionResult(id: UUID, result: String?)
    case intentionReview(id: UUID, period: String, text: String)
    case deleteIntention(UUID)
    case edit(entry: UUID, revision: UUID, text: String)
    case deleteEntry(UUID)
    // §7.3 N04 letters. (Project commands were removed on 11 Nov 2026; old queued ones are rejected as unknown.)
    case sealLetter(id: UUID, text: String, trigger: DiaryLetterTrigger, value: String?, target: UUID?)
    case refreshLetters
    case openLetter(UUID)
    case rescheduleLetter(id: UUID, day: String)
    // §7.1 B03 «يوم تنتظره»: the row stores the rule; occurrences are derived.
    case saveUpcomingDay(id: UUID, title: String, calendar: String, year: Int?, month: Int, day: Int, repeats: String, countFrom: String, countUpAfter: Bool)
    case deleteUpcomingDay(UUID)
    case saveWidget(id: UUID, name: String, familyID: String, items: [String], style: WidgetMakerStyle)
    case deleteWidget(UUID)
    public static let names: Set<String> = ["diary.saveDraft", "diary.commitDraft", "diary.appendMedia", "diary.setTranscript", "diary.setAudioInsights", "diary.setIntention", "diary.setIntentionResult", "diary.setIntentionReview", "diary.deleteIntention", "diary.editEntry", "diary.deleteEntry", "diary.sealLetter", "diary.refreshLetters", "diary.openLetter", "diary.rescheduleLetter", "bahw.saveUpcomingDay", "bahw.deleteUpcomingDay", "widget.save", "widget.delete"]
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
            guard Set(value.keys).isSubset(of: ["id", "at"]), let id = uuid("id") else { return nil }
            if value["at"] != nil { guard let at = value["at"]?.number, at.isFinite, at > 0 else { return nil }; return .commitDraft(id, at: at) }
            return .commitDraft(id)
        case "diary.appendMedia":
            guard Set(value.keys).isSubset(of: ["fileID", "kind", "contentType", "caption", "day", "durationS", "writingDayKey", "assetID", "at"]), let id = uuid("fileID"), let kind = value["kind"]?.string, ["photo", "audio", "video", "document"].contains(kind),
                let type = value["contentType"]?.string, !type.isEmpty, let caption = value["caption"]?.string, let day = value["day"]?.string, ["today", "yesterday"].contains(day) else { return nil }
            guard let writingDay = value["writingDayKey"]?.string, (try? GregorianDay(writingDay)) != nil else { return nil }
            let duration = value["durationS"]?.number
            guard value["durationS"] == nil || duration.map({ $0 >= 0 && $0 < Double(Int.max) && $0.rounded() == $0 }) == true else { return nil }
            // Owner, 24 Oct 2026: a photo can stay in the Photos library; Madar keeps its identifier and a small copy.
            let asset = value["assetID"]?.string
            guard value["assetID"] == nil || (kind == "photo" && asset.map { !$0.isEmpty && $0.count <= 200 } == true) else { return nil }
            // D8 (owner, 11 Nov 2026): «اكتب بعده» gives a photo the time between its two lines, as a written line gets.
            let at = value["at"]?.number
            guard value["at"] == nil || at.map({ $0.isFinite && $0 > 0 }) == true else { return nil }
            return .appendMedia(file: id, kind: kind, type: type, caption: caption, day: day, writingDay: writingDay, duration: duration.map(Int.init), asset: asset, at: at)
        case "diary.setIntention":
            guard Set(value.keys) == ["id","dayKey","text"],let id=uuid("id"),let day=value["dayKey"]?.string,(try? GregorianDay(day)) != nil,let text=value["text"]?.string,!text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty else{return nil}
            return .intention(id:id,day:day,text:text)
        case "diary.deleteIntention":
            guard Set(value.keys) == ["id"],let id=uuid("id") else{return nil}
            return .deleteIntention(id)
        case "diary.setIntentionResult":
            guard Set(value.keys) == ["id","result"],let id=uuid("id"),value["result"] == .null || value["result"]?.string.map({["done","partial","notEasy"].contains($0)}) == true else{return nil}
            return .intentionResult(id:id,result:value["result"]?.string)
        case "diary.setIntentionReview":
            guard Set(value.keys) == ["id", "period", "text"], let id = uuid("id"),
                  let period = value["period"]?.string, ["weekly", "monthly"].contains(period),
                  let text = value["text"]?.string, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2_000 else { return nil }
            return .intentionReview(id: id, period: period, text: text)
        case "diary.editEntry":
            guard Set(value.keys) == ["entryID", "revisionID", "text"], let id = uuid("entryID"), let revision = uuid("revisionID"), revision != id, let text = value["text"]?.string,
                !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return .edit(entry: id, revision: revision, text: text)
        case "diary.deleteEntry":
            guard Set(value.keys) == ["entryID"], let id = uuid("entryID") else { return nil }
            return .deleteEntry(id)
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
        case "bahw.saveUpcomingDay":
            guard Set(value.keys).isSubset(of: ["id", "title", "calendar", "year", "month", "day", "repeats", "countFromDayKey", "countUpAfter"]), let id = uuid("id"),
                  let title = value["title"]?.string?.trimmingCharacters(in: .whitespacesAndNewlines), !title.isEmpty, title.count <= 80,
                  let calendar = value["calendar"]?.string, ["hijri", "greg"].contains(calendar), let repeats = value["repeats"]?.string, ["none", "yearly", "monthly"].contains(repeats),
                  case .number(let m) = value["month"], case .number(let d) = value["day"], (1...12).contains(Int(m)), (1...(calendar == "hijri" ? 30 : 31)).contains(Int(d)),
                  let from = value["countFromDayKey"]?.string, (try? GregorianDay(from)) != nil else { return nil }
            var year: Int? = nil
            if case .number(let y) = value["year"] { year = Int(y) } else if value["year"] != nil && value["year"] != .null { return nil }
            guard repeats != "none" || year != nil else { return nil }
            // Owner, 25 Oct: only a one-time day may keep counting after it passes.
            var countUp = false
            if case .bool(let flag) = value["countUpAfter"] { countUp = flag } else if value["countUpAfter"] != nil && value["countUpAfter"] != .null { return nil }
            guard !countUp || repeats == "none" else { return nil }
            return .saveUpcomingDay(id: id, title: title, calendar: calendar, year: year, month: Int(m), day: Int(d), repeats: repeats, countFrom: from, countUpAfter: countUp)
        case "widget.save":
            guard Set(value.keys) == ["id", "name", "familyID", "items", "style"], let id = uuid("id"),
                  let rawName = value["name"]?.string,
                  let family = value["familyID"]?.string, WidgetMakerStyle.familyIDs.contains(family),
                  case .array(let values) = value["items"], !values.isEmpty, values.count <= 20,
                  let rawStyle = value["style"],
                  let style = try? JSONDecoder().decode(WidgetMakerStyle.self, from: JSONEncoder().encode(rawStyle)), style.isValid else { return nil }
            let title = rawName.trimmingCharacters(in: .whitespacesAndNewlines)
            let items = values.compactMap(\.string)
            guard !title.isEmpty, title.count <= 80, items.count == values.count,
                  Set(items).count == items.count, items.allSatisfy(WidgetMakerStyle.validItem) else { return nil }
            return .saveWidget(id: id, name: title, familyID: family, items: items, style: style)
        case "widget.delete":
            guard Set(value.keys) == ["id"], let id = uuid("id") else { return nil }
            return .deleteWidget(id)
        case "bahw.deleteUpcomingDay": guard Set(value.keys) == ["id"], let id = uuid("id") else { return nil }; return .deleteUpcomingDay(id)
        case "diary.setTranscript":
            guard Set(value.keys) == ["entryID", "text"], let id = uuid("entryID"), let text = value["text"]?.string else { return nil }; return .transcript(entry: id, text: text)
        case "diary.setAudioInsights":
            let keys = Set(value.keys), currentKeys: Set<String> = ["mediaID", "title", "audioLevels"]
            let legacyKeys = currentKeys.union(["voiceTone"])
            guard keys == currentKeys || keys == legacyKeys, let id = uuid("mediaID"),
                  let levelValues = value["audioLevels"]?.array, levelValues.count <= 36_000 else { return nil }
            let title = value["title"]?.string
            guard value["title"] == .null || title.map({ !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && $0.count <= 80 }) == true else { return nil }
            let tones = ["calm", "joyful", "sad", "concerned", "grateful", "hopeful", "tired", "mixed", "unclear"]
            if keys.contains("voiceTone"), value["voiceTone"] != .null, value["voiceTone"]?.string.map(tones.contains) != true { return nil }
            let levels = levelValues.compactMap(\.number)
            guard levels.count == levelValues.count, levels.allSatisfy({ (0...1).contains($0) }) else { return nil }
            return .audioInsights(media: id, title: title, levels: levels)
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
    var array: [JSONValue]? { if case .array(let value) = self { value } else { nil } }
}

/// Owner, 24 Oct 2026: a diary photo linked to the Photos library stores `Media.sourceID = "photos:<local identifier>"`
/// and only a small copy in `Media.data`, so the day still shows it if the original is deleted or on another device.
public enum DiaryPhotoLink {
    public static let prefix = "photos:"
    public static func assetID(sourceID: String?) -> String? {
        guard let sourceID, sourceID.hasPrefix(prefix) else { return nil }
        return String(sourceID.dropFirst(prefix.count))
    }
}
