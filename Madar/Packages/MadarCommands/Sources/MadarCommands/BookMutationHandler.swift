import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData
import MadarPrayer

private struct BookUndo: Codable {
    struct Change: Codable { var before: DataRecord?; var after: DataRecord }
    var changes: [Change]
    var importedMediaIDs: [UUID]? = nil
}
@MainActor enum BookMutationHandler {
    static func stage(_ command: BookCommand, context: ModelContext, now: Date, writer: String, stagingDirectory: URL? = nil) throws -> Data {
        let books = try context.fetch(FetchDescriptor<Book>())
        var changes: [BookUndo.Change] = []
        var importedMediaIDs: [UUID] = []
        func touch(_ row: any MadarRecordModel, before: DataRecord?) throws {
            var record = try row.record()
            try record.set(StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? .distantPast), for: "updatedAt")
            try record.set(writer, for: "writerID"); try row.apply(record)
            changes.append(.init(before: before, after: record))
        }
        func book(_ id: UUID) throws -> Book {
            guard let row = books.first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("الكتاب غير موجود") }; return row
        }
        func fileBook(_ id: UUID) throws -> Book {
            let row = try book(id)
            guard row.kind == "file", ["epub", "pdf", "pdfScanned"].contains(row.format ?? ""), let mediaID = row.mediaID,
                  let fileHash = row.fileHash, !fileHash.isEmpty else { throw DataError.invalidValue("هذا الكتاب لا يملك ملفًا صالحًا للقراءة") }
            let mediaRows = try context.fetch(FetchDescriptor<Media>())
            guard let media = mediaRows.first(where: { $0.id == mediaID && $0.deletedAt == nil && $0.mergedInto == nil }),
                  media.kind == "doc", media.state == "ok", let data = media.data,
                  data.count == media.sizeBytes, media.sha256 == fileHash else { throw DataError.invalidValue("ملف الكتاب مفقود أو تغيّرت بصمته") }
            return row
        }
        func slot(_ id: UUID, replacing: UUID? = nil) throws {
            let reading = Set(books.filter { $0.shelf == "reading" && $0.deletedAt == nil && $0.mergedInto == nil }.map(\.id))
            guard MihbaraReading.canRead(id: id, reading: reading, replacing: replacing) else { throw DataError.invalidValue("على الرف ثلاثة كتب؛ اختر كتابًا تعيده إلى أبي أقرأها") }
            if let replacing, reading.count >= 3, !reading.contains(id) {
                let old = try book(replacing), before = try old.record(); old.shelf = "want"; try touch(old, before: before)
            }
        }
        switch command {
        case .importPDF(let id, let fileID, let sha256, let title, let author, let language):
            guard let stagingDirectory else { throw DataError.invalidValue("ملف المعاينة غير موجود.") }
            guard !books.contains(where: { $0.id == id }) else { throw DataError.invalidValue("هذا الكتاب موجود بالفعل.") }
            guard !books.contains(where: { $0.fileHash == sha256 && $0.mergedInto == nil }) else { throw DataError.invalidValue("هذا الكتاب عندك بالفعل، أو أُزيل سابقًا؛ لن يُضاف مكررًا.") }
            let inspection = try PDFBookFiles.inspect(id: fileID, root: stagingDirectory)
            guard inspection.sha256 == sha256 else { throw DataError.invalidValue("تغيّر الملف بعد معاينته؛ اختره مرة أخرى.") }
            guard try context.fetch(FetchDescriptor<Media>()).allSatisfy({ $0.id != fileID }) else { throw DataError.invalidValue("معرّف الملف مستخدم بالفعل.") }
            let data = try Data(contentsOf: PDFBookFiles.stagedURL(id: fileID, root: stagingDirectory), options: .mappedIfSafe)
            guard data.count == inspection.sizeBytes, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { throw DataError.invalidValue("تغيّر الملف بعد المعاينة.") }
            let media = Media(); media.id = fileID; media.kind = "doc"; media.contentType = "com.adobe.pdf"
            media.data = data; media.sha256 = sha256; media.sizeBytes = data.count
            media.createdAt = now; media.updatedAt = now; media.writerID = writer; context.insert(media)
            importedMediaIDs.append(fileID)
            let row = Book(); row.id = id; row.title = title; row.author = author; row.language = language
            row.kind = "file"; row.format = inspection.scanned ? "pdfScanned" : "pdf"; row.pages = inspection.pages
            row.shelf = "want"; row.mediaID = fileID; row.fileHash = sha256; row.createdAt = now
            if !inspection.outline.isEmpty { row.tocJSON = try JSONEncoder().encode(inspection.outline) }
            context.insert(row); try touch(row, before: nil)
        case .importEPUB(let id, let fileID, let sha256, let title, let author, let language, let shelf, let turathID):
            guard let stagingDirectory else { throw DataError.invalidValue("ملف المعاينة غير موجود.") }
            guard !books.contains(where: { $0.id == id }) else { throw DataError.invalidValue("هذا الكتاب موجود بالفعل.") }
            guard !books.contains(where: { $0.fileHash == sha256 && $0.mergedInto == nil }) else { throw DataError.invalidValue("هذا الكتاب عندك بالفعل، أو أُزيل سابقًا؛ لن يُضاف مكررًا.") }
            let inspection = try EPUBBookFiles.inspect(id: fileID, root: stagingDirectory)
            guard inspection.sha256 == sha256 else { throw DataError.invalidValue("تغيّر الملف بعد معاينته؛ اختره مرة أخرى.") }
            guard try context.fetch(FetchDescriptor<Media>()).allSatisfy({ $0.id != fileID }) else { throw DataError.invalidValue("معرّف الملف مستخدم بالفعل.") }
            if shelf == "reading" { try slot(id) }
            let data = try Data(contentsOf: EPUBBookFiles.stagedURL(id: fileID, root: stagingDirectory), options: .mappedIfSafe)
            guard data.count == inspection.sizeBytes, SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined() == sha256 else { throw DataError.invalidValue("تغيّر الملف بعد المعاينة.") }
            let media = Media(); media.id = fileID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"
            media.data = data; media.sha256 = sha256; media.sizeBytes = data.count
            media.createdAt = now; media.updatedAt = now; media.writerID = writer; context.insert(media)
            importedMediaIDs.append(fileID)
            let row = Book(); row.id = id; row.title = title; row.author = author; row.language = language
            row.kind = "file"; row.format = "epub"; row.shelf = shelf; row.mediaID = fileID; row.fileHash = sha256; row.turathID = turathID; row.createdAt = now
            if shelf == "finished" { row.finishedAt = now; row.readCount = 1 }
            if !inspection.outline.isEmpty { row.tocJSON = try JSONEncoder().encode(inspection.outline) }
            context.insert(row); try touch(row, before: nil)
        case .savePaper(let id, let title, let author, let pages, let shelf, let replacing, let isbn13, let tocJSON):
            guard !books.contains(where: { $0.id == id }) else { throw DataError.invalidValue("الكتاب موجود؛ عدّله من بطاقته") }
            if shelf == "reading" { try slot(id, replacing: replacing) }
            let row = Book(); row.id = id; row.title = title; row.author = author; row.pages = pages; row.shelf = shelf; row.isbn13 = isbn13; row.tocJSON = tocJSON; row.createdAt = now
            // An explicitly finished book gets an honest date; other shelves do not invent one.
            if shelf == "finished" { row.finishedAt = now; row.readCount = 1 }
            context.insert(row); try touch(row, before: nil)
        case .updatePaper(let id, let title, let author, let pages, let position, let isbn13, let tocJSON):
            let row = try book(id)
            guard row.kind == "paper" else { throw DataError.invalidValue("لا يمكن تعديل الفهرس إلا لكتاب ورقي") }
            guard pages.map({ position <= $0 }) ?? true else { throw DataError.invalidValue("عدد الصفحات أقل من موضعك المحفوظ") }
            let before = try row.record()
            row.title = title; row.author = author; row.pages = pages; row.isbn13 = isbn13; row.tocJSON = tocJSON
            row.currentPage = position; row.locatorJSON = try JSONEncoder().encode(PaperBookPosition(page: position))
            try touch(row, before: before)
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
        case .readerLocator(let id, let locatorJSON):
            let row = try fileBook(id), before = try row.record()
            row.locatorJSON = locatorJSON
            try touch(row, before: before)
        case .readingSession(let id, let bookID, let start, let end, let activeSeconds, let fromPage, let toPage, let startLocatorJSON, let endLocatorJSON, let startProgression, let endProgression, let pagesCounted):
            _ = try fileBook(bookID)
            guard end >= start, activeSeconds >= 60, fromPage <= toPage, pagesCounted >= 0,
                  (0...1).contains(startProgression), (0...1).contains(endProgression) else { throw DataError.invalidValue("بيانات جلسة القراءة غير صالحة") }
            let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
            let row: ReadingSession
            let isNew: Bool
            if let existing = sessions.first(where: { $0.id == id }) {
                guard existing.deletedAt == nil, existing.mergedInto == nil, existing.bookID == bookID else { throw DataError.invalidValue("جلسة القراءة موجودة لكتاب آخر أو محذوفة") }
                row = existing
                isNew = false
            } else {
                row = ReadingSession(); row.id = id; row.createdAt = now; context.insert(row)
                isNew = true
            }
            row.bookID = bookID; row.start = start; row.end = end; row.activeSeconds = activeSeconds
            row.fromPage = fromPage; row.toPage = toPage; row.startLocatorJSON = startLocatorJSON; row.endLocatorJSON = endLocatorJSON
            row.startProgression = startProgression; row.endProgression = endProgression; row.pagesCounted = pagesCounted; row.source = "reader"
            if isNew {
                let prayers = try PrayerRepository(context: context), place = prayers.place(at: end)
                let settings = try SettingsStore(context: context)
                let boundary = DayBoundary(rawValue: try settings.value(for: "core.dayStart").string ?? "") ?? .fajr
                row.dayKey = try DiaryLineRenderer.today(context: context, now: end).description
                row.tzID = place.timeZoneID; row.dayPolicy = boundary.rawValue + "@1"
            }
            try touch(row, before: nil)
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
        case .saveHighlight(let id, let bookID, let locatorJSON, let color, let pageLabel):
            let owner = try book(bookID)
            guard owner.kind == "file" else { throw DataError.invalidValue("التظليل لكتب الملفات") }
            let rows = try context.fetch(FetchDescriptor<Highlight>())
            if let row = rows.filter({ $0.id == id && $0.mergedInto == nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
                guard row.bookID == bookID else { throw DataError.invalidValue("هذا التظليل لكتاب آخر") }
                let before = try row.record()
                if row.deletedAt != nil {
                    let barrier = row.deletionBarrierAt ?? row.deletedAt ?? .distantPast
                    row.restoredAt = max(now, barrier.addingTimeInterval(0.001)); row.deletedAt = nil
                }
                row.locatorJSON = locatorJSON; row.color = color; row.pageLabel = pageLabel
                try touch(row, before: before)
            } else {
                let row = Highlight(); row.id = id; row.createdAt = now; row.bookID = bookID
                row.locatorJSON = locatorJSON; row.color = color; row.pageLabel = pageLabel
                context.insert(row); try touch(row, before: nil)
            }
        case .deleteHighlight(let id):
            let rows = try context.fetch(FetchDescriptor<Highlight>())
            guard let row = rows.first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("التظليل غير موجود") }
            let before = try row.record(); row.deletedAt = now; row.deletionBarrierAt = now
            try touch(row, before: before)
        case .savePageNote(let id, let bookID, let text, let locatorJSON, let page):
            _ = try book(bookID)
            let notes = try context.fetch(FetchDescriptor<NotebookNote>())
            if let row = notes.filter({ $0.id == id && $0.mergedInto == nil }).max(by: { $0.updatedAt < $1.updatedAt }) {
                guard row.link == "page", row.targetID == bookID, !row.isPrivate else { throw DataError.invalidValue("هذه الملاحظة مرتبطة بمكان آخر") }
                let before = try row.record()
                if row.deletedAt != nil {
                    let barrier = row.deletionBarrierAt ?? row.deletedAt ?? .distantPast
                    row.restoredAt = max(now, barrier.addingTimeInterval(0.001)); row.deletedAt = nil
                }
                row.text = text; row.locatorJSON = locatorJSON; row.page = page
                try touch(row, before: before)
            } else {
                let row = NotebookNote(); row.id = id; row.createdAt = now; row.link = "page"; row.targetID = bookID
                row.isPrivate = false; row.text = text; row.locatorJSON = locatorJSON; row.page = page
                context.insert(row); try touch(row, before: nil)
            }
        case .saveUserWord(let id, let word, let language, let bookID, let bookTitle, let locatorJSON, let contextText):
            let owner = try book(bookID)
            guard owner.kind == "file", owner.format == "epub" else { throw DataError.invalidValue("أضف الكلمات من كتاب EPUB") }
            let words = try context.fetch(FetchDescriptor<UserWord>())
            let identity = UserWordIdentity.key(language: language, word: word)
            if let row = words.filter({ $0.mergedInto == nil && UserWordIdentity.key(language: $0.language, word: $0.word) == identity }).max(by: { $0.updatedAt < $1.updatedAt }) {
                let before = try row.record()
                if row.deletedAt != nil {
                    let barrier = row.deletionBarrierAt ?? row.deletedAt ?? .distantPast
                    row.restoredAt = max(now, barrier.addingTimeInterval(0.001)); row.deletedAt = nil
                }
                row.word = word; row.language = language; row.bookID = bookID; row.bookTitle = bookTitle
                row.locatorJSON = locatorJSON; row.context = contextText; row.savedAt = now
                try touch(row, before: before)
            } else {
                guard !words.contains(where: { $0.id == id }) else { throw DataError.invalidValue("معرّف الكلمة مستخدم بالفعل") }
                let row = UserWord(); row.id = id; row.createdAt = now; row.word = word; row.language = language
                row.bookID = bookID; row.bookTitle = bookTitle; row.locatorJSON = locatorJSON
                row.context = contextText; row.savedAt = now
                context.insert(row); try touch(row, before: nil)
            }
        }
        return command.isUndoable ? try JSONEncoder().encode(BookUndo(changes: changes, importedMediaIDs: importedMediaIDs.isEmpty ? nil : importedMediaIDs)) : Data()
    }
    static func undo(_ data: Data, context: ModelContext, now: Date, writer: String) throws {
        let state = try JSONDecoder().decode(BookUndo.self, from: data)
        // Book undo never needs binary Media records or other rooms' data.
        var records = try context.fetch(FetchDescriptor<Book>()).map { try $0.record() }
        records += try context.fetch(FetchDescriptor<HadithProgress>()).map { try $0.record() }
        records += try context.fetch(FetchDescriptor<NotebookNote>()).map { try $0.record() }
        records += try context.fetch(FetchDescriptor<Highlight>()).map { try $0.record() }
        records += try context.fetch(FetchDescriptor<UserWord>()).map { try $0.record() }
        for change in state.changes { guard records.contains(change.after) else { throw DataError.invalidValue("تغيّر الكتاب بعد هذا الإجراء") } }
        for id in state.importedMediaIDs ?? [] {
            let rows = try context.fetch(FetchDescriptor<Media>())
            guard let media = rows.first(where: { $0.id == id && $0.deletedAt == nil && $0.mergedInto == nil }) else { throw DataError.invalidValue("تغيّر ملف الكتاب بعد إضافته.") }
            media.deletedAt = now; media.deletionBarrierAt = now
            media.data = nil
            media.updatedAt = StableIdentity.monotonic(now: now, previous: media.updatedAt); media.writerID = writer
        }
        for change in state.changes.reversed() {
            var row = change.before ?? change.after
            if change.before == nil { try row.set(now, for: "deletedAt"); try row.set(now, for: "deletionBarrierAt") }
            try row.set(StableIdentity.monotonic(now: now, previous: change.after.date("updatedAt") ?? .distantPast), for: "updatedAt")
            try row.set(writer, for: "writerID"); try RecordBridge.upsert(row, in: context)
        }
    }
}
