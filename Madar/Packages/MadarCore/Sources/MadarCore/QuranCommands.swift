import Foundation

/// App-only commands for the existing Quran schema. Typed engine validation happens under the store lease.
public enum QuranCommandPayload {
    public static let names: Set<String> = ["quran.saveDraft", "quran.discardDraft", "quran.discardUnreadableDrafts", "quran.commitSession", "quran.savePlan",
        "quran.setTodayLevel", "quran.forceNewHifz", "quran.resolveMissedDay", "quran.createRecovery", "quran.cancelRecovery",
        "quran.raisePages", "quran.editSessionGrade", "quran.deleteSession", "quran.freezeTest", "quran.saveBookmark", "quran.deleteBookmark"]
    public static func validate(name: String, payload: [String: JSONValue]) -> Bool {
        func string(_ key: String) -> String? { if case .string(let value) = payload[key] { value } else { nil } }
        func number(_ key: String) -> Double? { if case .number(let value) = payload[key] { value } else { nil } }
        func keys(_ names: Set<String>) -> Bool { Set(payload.keys) == names }
        func uuid(_ key: String) -> Bool { string(key).flatMap(UUID.init(uuidString:)) != nil }
        switch name {
        case "quran.saveDraft": return keys(["draft"]) && (string("draft")?.utf8.count ?? 0) > 0 && (string("draft")?.utf8.count ?? 0) <= 4_000_000
        case "quran.discardDraft": return keys(["draftID"]) && uuid("draftID")
        case "quran.discardUnreadableDrafts": return payload.isEmpty
        // D8 (owner, 11 Nov 2026): a named Mushaf bookmark; saving an existing id renames or moves it.
        case "quran.saveBookmark":
            let name = string("name")?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return keys(["id", "page", "name"]) && uuid("id") && number("page").map { $0 == $0.rounded() && (1...604).contains($0) } == true && (1...40).contains(name.count)
        case "quran.deleteBookmark": return keys(["id"]) && uuid("id")
        case "quran.commitSession":
            guard uuid("draftID") else { return false }
            if keys(["draftID"]) { return true }
            if keys(["draftID", "partial"]), case .bool = payload["partial"] { return true }
            return false
        case "quran.deleteSession": return keys(["sessionID"]) && uuid("sessionID")
        case "quran.savePlan":
            guard keys(["startAyah", "unit", "amount", "rhythm", "restDay", "missPolicy"]),
                  let start = number("startAyah"), start.rounded() == start, (1...6236).contains(start),
                  let amount = number("amount"), amount.isFinite, amount > 0 else { return false }
            return ["ayah", "quarter", "half", "page"].contains(string("unit") ?? "") && ["light", "balanced", "intense"].contains(string("rhythm") ?? "")
                && ["sunday", "monday", "tuesday", "wednesday", "thursday", "friday", "saturday", "none"].contains(string("restDay") ?? "") && ["ask", "spread", "double", "skip"].contains(string("missPolicy") ?? "")
        case "quran.setTodayLevel": return keys(["kind", "level"]) && ["hifz", "review"].contains(string("kind") ?? "") && ["simple", "medium", "deep", "max"].contains(string("level") ?? "")
        case "quran.forceNewHifz", "quran.cancelRecovery", "quran.freezeTest": return payload.isEmpty
        case "quran.resolveMissedDay": return keys(["dayKey", "choice"]) && string("dayKey").flatMap { try? GregorianDay($0) } != nil && ["spread", "double", "skip", "postpone"].contains(string("choice") ?? "")
        case "quran.createRecovery": return keys(["days"]) && [5.0, 7.0, 14.0].contains(number("days") ?? 0)
        case "quran.raisePages": return keys(["juz"]) && number("juz").map { $0.rounded() == $0 && (1...30).contains($0) } == true
        case "quran.editSessionGrade": return keys(["sessionID", "page", "grade"]) && uuid("sessionID") && number("page").map { $0.rounded() == $0 && (1...604).contains($0) } == true && ["mastered", "good", "needs"].contains(string("grade") ?? "")
        default: return false
        }
    }
}
