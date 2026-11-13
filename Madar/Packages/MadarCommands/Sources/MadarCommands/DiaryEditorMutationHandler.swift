import Foundation
import SwiftData
import CryptoKit
import MadarCore
import MadarData

@MainActor enum DiaryEditorMutationHandler {
    static func stage(_ command: DiaryEditorCommand, id: UUID, root: URL, context: ModelContext, now: Date, writer: String) throws -> Data? {
        switch command {
        case .saveDraft(let id, let text, let day, let target, let writingDay):
            let existing = try context.fetch(FetchDescriptor<SessionDraft>()).first { $0.id == id && $0.mergedInto == nil }
            guard existing == nil || existing?.kind.hasPrefix("diary.") == true else { throw DataError.invalidValue("diary draft required") }
            guard existing?.deletedAt == nil else { throw DataError.invalidValue("draft already completed") }
            if existing == nil && text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return nil }
            let row = existing ?? SessionDraft(); row.id = id; row.kind = target.map { "diary.margin." + $0 } ?? "diary.text"
            if existing == nil { row.dayKey = writingDay }
            guard try GregorianDay(writingDay) <= DiaryLineRenderer.today(context: context, now: now) else { throw DataError.invalidValue("future diary day") }
            row.portionJSON = try JSONEncoder().encode(["day": day, "targetDayKey": target ?? "", "writingDayKey": writingDay])
            row.provisionalJSON = try JSONEncoder().encode(text); row.updatedAt = StableIdentity.monotonic(now: now, previous: row.updatedAt); row.writerID = writer
            if existing == nil { row.startedAt = now; row.createdAt = now; context.insert(row) }
            return nil
        case .commitDraft(let draftID, let at):
            guard let draft = try context.fetch(FetchDescriptor<SessionDraft>()).first(where: { $0.id == draftID && $0.kind.hasPrefix("diary.") && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("missing diary draft") }
            let text = try JSONDecoder().decode(String.self, from: draft.provisionalJSON), target = try JSONDecoder().decode([String: String].self, from: draft.portionJSON)
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw DataError.invalidValue("اكتب سطرًا أولًا") }
            let inverse = try DiaryMutationHandler.stage(text: text, day: target["day"] ?? "today", targetDay: target["targetDayKey"].flatMap { $0.isEmpty ? nil : $0 }, id: id, context: context, now: now, writer: writer, storedDay: try GregorianDay(target["writingDayKey"] ?? draft.dayKey), eventAt: try at.map { value in
                let moment = Date(timeIntervalSince1970: value)
                guard moment <= now else { throw DataError.invalidValue("future diary time") }
                return moment
            })
            draft.deletedAt = now; draft.deletionBarrierAt = now; draft.updatedAt = StableIdentity.monotonic(now: now, previous: draft.updatedAt); draft.writerID = writer
            guard let inverse else { return nil }
            var revived = try JSONDecoder().decode(DiaryInverse.self, from: inverse)
            revived.restoredDraftID = draftID
            return try JSONEncoder().encode(revived)
        case .appendMedia(let file, let kind, let type, let caption, let day, let writingDay, let duration, let asset, let at):
            guard try context.fetchCount(FetchDescriptor<Media>(predicate: #Predicate { $0.id == file })) == 0 else { throw DataError.invalidValue("media already exists") }
            let url = root.appending(path: file.uuidString + (kind == "audio" ? ".m4a" : ".blob"))
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DataError.invalidValue("invalid staged media") }
            let data = try Data(contentsOf: url, options: .mappedIfSafe); guard !data.isEmpty else { throw DataError.invalidValue("ملف فارغ") }
            let media = Media(); media.id = file; media.kind = kind; media.contentType = type; media.data = data; media.sizeBytes = data.count
            media.sha256 = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(); media.durationS = duration
            // A linked photo: `data` is the small copy and the natural key is the library asset (Media.naturalKeyRule).
            media.sourceID = asset.map { DiaryPhotoLink.prefix + $0 }
            media.createdAt = now; media.updatedAt = now; media.writerID = writer; context.insert(media)
            return try DiaryMutationHandler.stage(text: caption, day: day, targetDay: nil, id: id, context: context, now: now, writer: writer, mediaIDs: kind == "audio" ? [] : [file], audioID: kind == "audio" ? file : nil, storedDay: try GregorianDay(writingDay), eventAt: try at.map { value in
                let moment = Date(timeIntervalSince1970: value)
                guard moment <= now else { throw DataError.invalidValue("future diary time") }
                return moment
            })
        case .intention(let id,let day,let text): return try DiaryMutationHandler.setIntention(id:id,day:day,text:text,context:context,now:now,writer:writer)
        case .intentionResult(let id,let result): return try DiaryMutationHandler.setIntentionResult(id:id,result:result,context:context,now:now,writer:writer)
        case .intentionReview(let id, let period, let text): return try DiaryMutationHandler.setIntentionReview(id: id, period: period, text: text, context: context, now: now, writer: writer)
        case .deleteIntention(let id): return try DiaryMutationHandler.deleteIntention(id:id,context:context,now:now,writer:writer)
        case .sealLetter(let letter, let text, let trigger, let value, let target): return try DiaryLetterHandler.seal(id: letter, text: text, trigger: trigger, value: value, target: target, context: context, now: now, writer: writer)
        case .refreshLetters: try DiaryLetterHandler.refresh(context: context, now: now, writer: writer); return nil
        case .openLetter(let letter): try DiaryLetterHandler.open(letter, context: context, now: now, writer: writer); return nil
        case .rescheduleLetter(let letter, let day): return try DiaryLetterHandler.reschedule(letter, day: day, context: context, now: now, writer: writer)
        case .saveUpcomingDay(let id, let title, let calendar, let year, let month, let day, let repeats, let from, let countUp):
            return try BahwUpcomingHandler.save(id, title: title, calendar: calendar, year: year, month: month, day: day, repeats: repeats, countFrom: from, countUpAfter: countUp, context: context, now: now, writer: writer)
        case .saveWidget(let id, let name, let family, let items, let style):
            return try WidgetConfigMutation.save(id, name: name, family: family, items: items, style: style, context: context, now: now, writer: writer)
        case .deleteWidget(let id): return try WidgetConfigMutation.delete(id, context: context, now: now, writer: writer)
        case .deleteUpcomingDay(let id): return try BahwUpcomingHandler.delete(id, context: context, now: now, writer: writer)
        case .edit(let entry, let revision, let text): return try DiaryMutationHandler.edit(entry: entry, revision: revision, text: text, context: context, now: now, writer: writer)
        case .deleteEntry(let entry): return try DiaryMutationHandler.deleteEntry(entry, context: context, now: now, writer: writer)
        case .transcript(let entry, let text): return try DiaryMutationHandler.setTranscript(entry: entry, text: text, context: context, now: now, writer: writer)
        case .audioInsights(let media, let title, let levels): return try DiaryMutationHandler.setAudioInsights(media: media, title: title, levels: levels, context: context, now: now, writer: writer)
        }
    }
}
