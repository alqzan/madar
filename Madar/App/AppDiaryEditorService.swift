import Foundation
import SwiftData
import MadarCore
import MadarData

struct DiaryTextDraft {
    let id: UUID
    let text: String
    let day: String
    let writingDay: GregorianDay
}
struct DiaryDisplayMedia: Identifiable, Sendable {
    let id: UUID
    let entryID: String
    let kind: String
    let contentType: String
    let data: Data
    let duration: Int?
    var assetID: String? = nil
    var title: String? = nil
    var voiceTone: String? = nil
    var levelSamples: [Double] = []
}
extension AppDiaryService {
    func draft(margin: GregorianDay?) throws -> DiaryTextDraft? {
        try authorizeRead()
        let kind = margin.map { "diary.margin." + $0.description } ?? "diary.text"
        let context = ModelContext(app.container)
        guard let row = try context.fetch(FetchDescriptor<SessionDraft>(predicate: #Predicate { $0.kind == kind && $0.deletedAt == nil && $0.mergedInto == nil })).max(by: { $0.updatedAt < $1.updatedAt }) else { return nil }
        let metadata = try JSONDecoder().decode([String:String].self, from: row.portionJSON)
        return try .init(id: row.id, text: JSONDecoder().decode(String.self, from: row.provisionalJSON), day: metadata["day"] ?? "today", writingDay: GregorianDay(metadata["writingDayKey"] ?? row.dayKey))
    }
    func saveDraft(id: UUID, text: String, day: String, margin: GregorianDay?, writingDay: GregorianDay) async throws {
        var payload: [String:MadarCore.JSONValue] = ["id": .string(id.uuidString), "text": .string(text), "day": .string(day), "writingDayKey": .string(writingDay.description)]
        if let margin { payload["targetDayKey"] = .string(margin.description) }
        try await app.executeDiaryCommand("diary.saveDraft", payload: payload, updatesPresentation: false)
    }
    @discardableResult func appendMedia(data: Data, kind: String, contentType: String, caption: String = "", day: String, writingDay: GregorianDay, duration: Int? = nil, assetID: String? = nil, id: UUID = UUID()) async throws -> UUID {
        try authorizeRead()
        let root = app.diaryStagingDirectory
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.protectionKey: FileProtectionType.complete])
        let file = root.appending(path: id.uuidString + (kind == "audio" ? ".m4a" : ".blob"))
        try data.write(to: file, options: [.atomic, .completeFileProtection])
        var payload: [String:MadarCore.JSONValue] = ["fileID": .string(id.uuidString), "kind": .string(kind), "contentType": .string(contentType), "caption": .string(caption), "day": .string(day), "writingDayKey": .string(writingDay.description)]
        if let duration { payload["durationS"] = .number(Double(duration)) }
        if let assetID { payload["assetID"] = .string(assetID) }
        try await app.executeDiaryCommand("diary.appendMedia", payload: payload, id: id)
        try? FileManager.default.removeItem(at: file)
        return id
    }
}
