#if DEBUG
import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData

extension AppSession {
    func prepareMihbaraFixture(group: URL) throws {
        guard let variant = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_FIXTURE"], ["home","empty","reader"].contains(variant), group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let c = ModelContext(container)
        guard !(try c.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.mihbaraFixture" }) else { return }
        for key in ["sys.mihbaraFixture","sys.onboardingCompleted"] { let r = DeviceSetting(); r.key = key; r.valueJSON = Data("true".utf8); c.insert(r) }
        _ = try SettingsStore(context: c).stage(["core.dayStart":.string("midnight"),"core.faceIDLock":.string("none")])
        let now = prayerNow()
        if variant == "home" {
            let r = Book(); r.id = StableIdentity.uuid(for: "mihbara-fixture-book"); r.title = "رحلة القراءة"; r.author = "من مكتبتك"; r.pages = 250; r.currentPage = 147; r.locatorJSON = try JSONEncoder().encode(PaperBookPosition(page: 147)); r.shelf = "reading"; r.updatedAt = now; c.insert(r)
            let want = Book(); want.title = "كتاب ينتظر"; want.author = "من مكتبتك"; want.shelf = "want"; want.pages = 180; c.insert(want)
            let old = Book(); old.title = "قراءة قديمة"; old.author = "من مكتبتك"; old.shelf = "old"; old.finishedAt = ISO8601DateFormatter().date(from: "2016-10-01T12:00:00Z"); c.insert(old)
            let note = NotebookNote(); note.id = StableIdentity.uuid(for: "mihbara-fixture-private-note"); note.text = "سر لا يظهر قبل المصادقة"; note.isPrivate = true; note.link = "general"; note.updatedAt = now; c.insert(note)
            let pageNote = NotebookNote(); pageNote.id = StableIdentity.uuid(for: "mihbara-fixture-page-note"); pageNote.text = "أكمل من هذا الموضع على مهل."; pageNote.isPrivate = true; pageNote.link = "page"; pageNote.targetID = r.id; pageNote.page = 147; pageNote.updatedAt = now; c.insert(pageNote)
            for n in 1...12 { let h = HadithProgress(); h.id = StableIdentity.uuid(for: "hadith:nawawi40:\(n)"); h.collectionID = "nawawi40"; h.editionID = "wikisource-ar-500107"; h.number = n; h.readAt = now.addingTimeInterval(-86400); h.understood = true; c.insert(h) }
        }
        if variant == "reader", let encoded = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_EPUB_BASE64"], let data = Data(base64Encoded: encoded) {
            let hash = SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined(), mediaID = StableIdentity.uuid(for: "mihbara-reader-fixture-media")
            let media = Media(); media.id = mediaID; media.kind = "doc"; media.contentType = "org.idpf.epub-container"; media.data = data; media.sizeBytes = data.count; media.sha256 = hash; c.insert(media)
            let book = Book(); book.id = StableIdentity.uuid(for: "mihbara-reader-fixture-book"); book.title = "كتاب اختبار القارئ"; book.author = "نص اختباري أصلي"; book.kind = "file"; book.format = "epub"; book.shelf = "reading"; book.locatorJSON = nil; book.mediaID = mediaID; book.fileHash = hash; book.updatedAt = now; c.insert(book)
        }
        try c.save()
    }
}
#endif
