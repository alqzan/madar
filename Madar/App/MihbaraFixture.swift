#if DEBUG
import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData
import MadarCommands

extension AppSession {
    func prepareMihbaraFixture(group: URL) throws {
        guard let variant = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_FIXTURE"], ["home","empty","reader","bindings","missingFile"].contains(variant), group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let c = ModelContext(container)
        guard !(try c.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.mihbaraFixture" }) else { return }
        for key in ["sys.mihbaraFixture","sys.onboardingCompleted"] { let r = DeviceSetting(); r.key = key; r.valueJSON = Data("true".utf8); c.insert(r) }
        _ = try SettingsStore(context: c).stage(["core.dayStart":.string("midnight"),"core.faceIDLock":.string("none")])
        let now = prayerNow()
        if variant == "missingFile" {
            let book = Book(); book.id = StableIdentity.uuid(for: "mihbara-missing-file-fixture-book")
            book.title = "كتاب بلا ملف"; book.author = "نص اختباري"; book.kind = "file"; book.format = "epub"; book.shelf = "reading"
            if let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_IMPORT_PDF"],
               let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count < 1024 * 1024 {
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let media = Media(); media.id = StableIdentity.uuid(for: "mihbara-missing-file-fixture-media")
                media.kind = "doc"; media.contentType = "com.adobe.pdf"; media.state = "missing"
                media.sizeBytes = bytes.count; media.sha256 = hash; c.insert(media)
                // M6-PK: a PDF that is on the device, to draw on.
                if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_PDF_READY"] == "1" { media.state = "ok"; media.data = bytes; book.title = "كتاب للرسم" }
                book.format = "pdf"; book.mediaID = media.id; book.fileHash = hash; book.pages = 1; book.currentPage = 1
                book.createdAt = now; book.updatedAt = now
            } else if let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_EPUB_BASE64"],
                      let bytes = Data(base64Encoded: encoded), !bytes.isEmpty, bytes.count < 2 * 1024 * 1024 {
                let hash = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
                let media = Media(); media.id = StableIdentity.uuid(for: "mihbara-missing-file-fixture-media")
                media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.state = "missing"
                media.sizeBytes = bytes.count; media.sha256 = hash; c.insert(media)
                book.mediaID = media.id; book.fileHash = hash
                book.createdAt = now; book.updatedAt = now
            }
            c.insert(book)
        }
        if variant == "home" {
            let r = Book(); r.id = StableIdentity.uuid(for: "mihbara-fixture-book"); r.title = "رحلة القراءة"; r.author = "من مكتبتك"; r.pages = 250; r.currentPage = 147; r.locatorJSON = try JSONEncoder().encode(PaperBookPosition(page: 147)); r.shelf = "reading"; r.updatedAt = now; c.insert(r)
            let want = Book(); want.title = "كتاب ينتظر"; want.author = "من مكتبتك"; want.shelf = "want"; want.pages = 180; c.insert(want)
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_FILE_ROW"] == "1" {
                let nearEnd = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_FILE_NEAR_END"] == "1"
                let file = Book(); file.id = StableIdentity.uuid(for: "mihbara-fixture-editable-file")
                file.title = "ملف قابل للتعديل"; file.author = "نص اختباري"; file.kind = "file"; file.format = "epub"; file.shelf = "reading"
                file.pages = nearEnd ? 200 : 90
                if nearEnd {
                    file.mediaID = StableIdentity.uuid(for: "mihbara-fixture-near-end-media")
                    file.fileHash = String(repeating: "a", count: 64)
                    file.locatorJSON = try JSONSerialization.data(withJSONObject: ["locations": ["totalProgression": 0.995]])
                }
                file.updatedAt = now.addingTimeInterval(nearEnd ? 60 : 0)
                c.insert(file)
                if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_MARGIN_NOTE"] == "1" {
                    let margin = NotebookNote(); margin.id = StableIdentity.uuid(for: "mihbara-fixture-margin-note"); margin.link = "page"; margin.isPrivate = false
                    margin.targetID = file.id; margin.page = 12; margin.text = "فكرة تستحق أن أرجع لها."; margin.updatedAt = now
                    margin.locatorJSON = try JSONSerialization.data(withJSONObject: ["href": "ch1.xhtml", "type": "application/xhtml+xml", "locations": ["progression": 0.2], "text": ["highlight": "العلم صيد والكتابة قيده، قيّد صيودك بالحبال الواثقة."]])
                    c.insert(margin)
                }
            }
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_READING_DAYS"] == "1" {
                // Reading goal (owner, 30 Oct): a week of evening sessions after Isha, today's still short of 15 minutes.
                // The book has a twelve-chapter outline, so a «فصول» goal can be measured.
                r.tocJSON = try JSONSerialization.data(withJSONObject: (0..<12).map { ["title": "الفصل \($0 + 1)", "page": 1 + $0 * 21] as [String: Any] })
                for (back, minutes, pages) in [(6, 22, 9), (5, 0, 0), (4, 18, 7), (3, 31, 12), (2, 9, 3), (1, 16, 6), (0, 8, 3)] where minutes > 0 {
                    let day = try GregorianDay("2026-10-17").adding(days: -back), row = ReadingSession()
                    row.bookID = r.id; row.dayKey = day.description; row.tzID = "Asia/Riyadh"; row.activeSeconds = minutes * 60; row.pagesCounted = pages
                    row.start = day.date(in: TimeZone(identifier: "Asia/Riyadh")!).addingTimeInterval(back == 0 ? 10 * 3600 : 21 * 3600); row.end = row.start.addingTimeInterval(Double(minutes * 60))
                    c.insert(row)
                }
            }
            let old = Book(); old.title = "قراءة قديمة"; old.author = "من مكتبتك"; old.shelf = "old"; old.finishedAt = ISO8601DateFormatter().date(from: "2016-10-01T12:00:00Z"); c.insert(old)
            let note = NotebookNote(); note.id = StableIdentity.uuid(for: "mihbara-fixture-private-note"); note.text = "سر لا يظهر قبل المصادقة"; note.isPrivate = true; note.link = "general"; note.updatedAt = now; c.insert(note)
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_MULTIPLE_NOTES"] == "1" {
                let second = NotebookNote(); second.id = StableIdentity.uuid(for: "mihbara-fixture-second-private-note")
                second.text = "ملاحظة ثانية لاختبار اختيارها"; second.isPrivate = true; second.link = "general"; second.updatedAt = now.addingTimeInterval(-1); c.insert(second)
            }
            let pageNote = NotebookNote(); pageNote.id = StableIdentity.uuid(for: "mihbara-fixture-page-note"); pageNote.text = "أكمل من هذا الموضع على مهل."; pageNote.isPrivate = true; pageNote.link = "page"; pageNote.targetID = r.id; pageNote.page = 147; pageNote.updatedAt = now; c.insert(pageNote)
            if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_SECOND_READING"] == "1" {
                // OR-32: a second book in hand, read an hour before the one on the stand.
                let other = Book(); other.id = StableIdentity.uuid(for: "mihbara-fixture-second-reading"); other.title = "الأدب الصغير"; other.author = "ابن المقفع"; other.pages = 200; other.currentPage = 60; other.locatorJSON = try JSONEncoder().encode(PaperBookPosition(page: 60)); other.shelf = "reading"; other.updatedAt = now.addingTimeInterval(-3600); c.insert(other)
            }
            for n in 1...12 { let h = HadithProgress(); h.id = StableIdentity.uuid(for: "hadith:nawawi40:\(n)"); h.collectionID = "nawawi40"; h.editionID = "wikisource-ar-500107"; h.number = n; h.readAt = now.addingTimeInterval(-86400); h.understood = true; c.insert(h) }
        }
        if variant == "bindings" {
            // Owner, 22 Oct 2026: one book per binding, sets and single books, to see all twenty on the shelf.
            for (k, item) in Self.bindingShelf.enumerated() {
                var seed = 0, id = StableIdentity.uuid(for: "binding-\(k)-0")
                while BookBindings.indices(for: [id])[id] != k { seed += 1; id = StableIdentity.uuid(for: "binding-\(k)-\(seed)") }
                let b = Book(); b.id = id; b.title = item.title; b.author = item.author; b.pages = item.pages; b.shelf = k < 14 ? "want" : k < 18 ? "finished" : "old"
                if k >= 14 { b.finishedAt = now.addingTimeInterval(-Double(k) * 86400 * 30) }
                b.updatedAt = now.addingTimeInterval(-Double(k) * 60); c.insert(b)
            }
        }
        if variant == "reader", let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_EPUB_BASE64"], let data = Data(base64Encoded: encoded) {
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), mediaID = StableIdentity.uuid(for: "mihbara-reader-fixture-media")
            let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = data; media.sizeBytes = data.count; media.sha256 = hash; c.insert(media)
            let book = Book(); book.id = StableIdentity.uuid(for: "mihbara-reader-fixture-book"); book.title = "كتاب اختبار القارئ"; book.author = "نص اختباري أصلي"; book.kind = "file"; book.format = "epub"; book.shelf = "reading"; book.locatorJSON = nil; book.mediaID = mediaID; book.fileHash = hash; book.updatedAt = now; c.insert(book)
        }
        try c.save()
    }

    /// Title, author, printed pages per volume and volumes, for the bindings fixture.
    static let bindingShelf: [(title: String, author: String, pages: Int, volumes: Int)] = [
        ("زاد المعاد في هدي خير العباد", "ابن قيم الجوزية", 2400, 5), ("رياض الصالحين", "النووي", 560, 1),
        ("فتح الباري شرح صحيح البخاري", "ابن حجر", 6400, 4), ("الأربعون النووية", "النووي", 120, 1),
        ("مدارج السالكين", "ابن قيم الجوزية", 1500, 3), ("الرحيق المختوم", "المباركفوري", 480, 1),
        ("سير أعلام النبلاء", "الذهبي", 3200, 4), ("الفوائد", "ابن قيم الجوزية", 300, 1),
        ("تفسير القرآن العظيم", "ابن كثير", 3600, 4), ("صيد الخاطر", "ابن الجوزي", 520, 1),
        ("البداية والنهاية", "ابن كثير", 2800, 4), ("الداء والدواء", "ابن قيم الجوزية", 380, 1),
        ("إحياء علوم الدين", "الغزالي", 2600, 4), ("حلية طالب العلم", "بكر أبو زيد", 90, 1),
        ("الموافقات", "الشاطبي", 1800, 3), ("بلوغ المرام", "ابن حجر", 420, 1),
        ("الأدب المفرد", "البخاري", 350, 1), ("كتاب التوحيد", "محمد بن عبد الوهاب", 160, 1),
        ("لا تحزن", "عائض القرني", 440, 1), ("مختصر منهاج القاصدين", "ابن قدامة", 400, 1),
    ]
}
#endif
