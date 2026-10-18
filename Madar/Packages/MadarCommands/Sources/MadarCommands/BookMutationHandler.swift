import Foundation
import SwiftData
import MadarCore
import MadarData

private struct BookUndo: Codable {
    struct Change: Codable { var before: DataRecord?; var after: DataRecord }
    var changes: [Change]
}
@MainActor enum BookMutationHandler {
    static func stage(_ command: BookCommand, context: ModelContext, now: Date, writer: String) throws -> Data {
        let books = try context.fetch(FetchDescriptor<Book>())
        var changes: [BookUndo.Change] = []
        func touch(_ row: any MadarRecordModel, before: DataRecord?) throws {
            var record = try row.record()
            try record.set(StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast), for: "updatedAt")
            try record.set(writer, for: "writerID"); try row.apply(record)
            changes.append(.init(before: before, after: record))
        }
        func book(_ id: UUID) throws -> Book {
            guard let row = books.first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("الكتاب غير موجود") }; return row
        }
        func slot(_ id: UUID, replacing: UUID? = nil) throws {
            let reading = Set(books.filter { $0.shelf == "reading" && $0.deletedAt == nil && $0.mergedInto == nil }.map(\.id))
            guard MihbaraReading.canRead(id: id, reading: reading, replacing: replacing) else { throw DataError.invalidValue("على الرف ثلاثة كتب؛ اختر كتابًا تعيده إلى أبي أقرأها") }
            if let replacing, reading.count >= 3, !reading.contains(id) {
                let old = try book(replacing), before = try old.record(); old.shelf = "want"; try touch(old, before: before)
            }
        }
        switch command {
        case .savePaper(let id, let title, let author, let pages, let shelf, let replacing):
            guard !books.contains(where: { $0.id == id }) else { throw DataError.invalidValue("الكتاب موجود؛ عدّله من بطاقته") }
            if shelf == "reading" { try slot(id, replacing: replacing) }
            let row = Book(); row.id = id; row.title = title; row.author = author; row.pages = pages; row.shelf = shelf; row.createdAt = now
            // An explicitly finished book gets an honest date; other shelves do not invent one.
            if shelf == "finished" { row.finishedAt = now; row.readCount = 1 }
            context.insert(row); try touch(row, before: nil)
        case .shelf(let id, let shelf, let replacing):
            let row = try book(id), before = try row.record()
            if shelf == "reading" { try slot(id, replacing: replacing) }
            if shelf == "finished", row.shelf != "finished" { row.finishedAt = now; row.readCount += 1 }
            row.shelf = shelf; try touch(row, before: before)
        case .position(let id, let page, let finished):
            let row = try book(id), before = try row.record()
            guard row.kind == "paper", row.pages.map({ page <= $0 }) ?? true else { throw DataError.invalidValue("الموضع خارج صفحات الكتاب") }
            row.locatorJSON = try JSONEncoder().encode(PaperBookPosition(page: page)); row.currentPage = page
            if finished, row.shelf != "finished" { row.shelf = "finished"; row.finishedAt = now; row.readCount += 1 }
            try touch(row, before: before)
        case .hadith(let number, let edition, let understood, let day):
            guard day == (try DiaryLineRenderer.today(context: context, now: now)) else { throw DataError.invalidValue("تغيّر اليوم؛ افتح ورد اليوم مجددًا") }
            let rows = try context.fetch(FetchDescriptor<HadithProgress>())
            let old = rows.first { $0.collectionID == "nawawi40" && $0.number == number && $0.mergedInto == nil }
            let before = try old?.record(), row = old ?? HadithProgress()
            if old == nil { row.id = StableIdentity.uuid(for: "hadith:nawawi40:\(number)"); row.createdAt = now; context.insert(row) }
            else if row.deletedAt != nil {
                // Pressing either hadith action again is an explicit restore of this stable hadith identity.
                let barrier = row.deletionBarrierAt ?? row.deletedAt ?? .distantPast
                row.restoredAt = max(now, barrier.addingTimeInterval(0.001))
                row.deletedAt = nil
            }
            row.collectionID = "nawawi40"; row.number = number; row.editionID = edition
            row.readAt = row.readAt ?? now; row.understood = understood; row.returnTo = !understood; row.understoodDayKey = understood ? day.description : nil
            try touch(row, before: before)
        case .savePrivateNote(let id, let text):
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, text.count <= 2000 else { throw DataError.invalidValue("نص الملاحظة غير صالح") }
            let notes = try context.fetch(FetchDescriptor<NotebookNote>())
            if let row = notes.filter({ $0.id == id && $0.mergedInto == nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
                guard row.isPrivate, row.link == "general", row.targetID == nil else { throw DataError.invalidValue("هذه الملاحظة مرتبطة بمكان آخر") }
                let before = try row.record()
                if row.deletedAt != nil {
                    let barrier = row.deletionBarrierAt ?? row.deletedAt ?? .distantPast
                    row.restoredAt = max(now, barrier.addingTimeInterval(0.001)); row.deletedAt = nil
                }
                row.text = text
                try touch(row, before: before)
            } else {
                let row = NotebookNote(); row.id = id; row.createdAt = now; row.link = "general"; row.isPrivate = true; row.text = text
                context.insert(row); try touch(row, before: nil)
            }
        case .deletePrivateNote(let id):
            let notes = try context.fetch(FetchDescriptor<NotebookNote>())
            guard let row = notes.first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil && $0.isPrivate && $0.link == "general" && $0.targetID == nil }) else { throw DataError.invalidValue("الملاحظة الخاصة غير موجودة") }
            let before = try row.record(); row.deletedAt = now; row.deletionBarrierAt = now
            try touch(row, before: before)
        }
        return try JSONEncoder().encode(BookUndo(changes: changes))
    }
    static func undo(_ data: Data, context: ModelContext, now: Date, writer: String) throws {
        let state = try JSONDecoder().decode(BookUndo.self, from: data), records = try RecordBridge.all(context)
        for change in state.changes { guard records.contains(change.after) else { throw DataError.invalidValue("تغيّر الكتاب بعد هذا الإجراء") } }
        for change in state.changes.reversed() {
            var row = change.before ?? change.after
            if change.before == nil { try row.set(now, for: "deletedAt"); try row.set(now, for: "deletionBarrierAt") }
            try row.set(StableIdentity.monotonic(now: now, previous: change.after.date("updatedAt") ?? .distantPast), for: "updatedAt")
            try row.set(writer, for: "writerID"); try RecordBridge.upsert(row, in: context)
        }
    }
}
