#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData

extension AppSession {
    func prepareMihbaraFixture(group: URL) throws {
        guard let variant = ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_FIXTURE"], ["home","empty"].contains(variant), group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let c = ModelContext(container)
        guard !(try c.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.mihbaraFixture" }) else { return }
        for key in ["sys.mihbaraFixture","sys.onboardingCompleted"] { let r = DeviceSetting(); r.key = key; r.valueJSON = Data("true".utf8); c.insert(r) }
        _ = try SettingsStore(context: c).stage(["core.dayStart":.string("midnight"),"core.faceIDLock":.string("none")])
        if variant == "home" {
            let now = prayerNow()
            let r = Book(); r.id = StableIdentity.uuid(for: "mihbara-fixture-book"); r.title = "رحلة القراءة"; r.author = "من مكتبتك"; r.pages = 250; r.currentPage = 147; r.locatorJSON = try JSONEncoder().encode(PaperBookPosition(page: 147)); r.shelf = "reading"; r.updatedAt = now; c.insert(r)
            let want = Book(); want.title = "كتاب ينتظر"; want.author = "من مكتبتك"; want.shelf = "want"; want.pages = 180; c.insert(want)
            let old = Book(); old.title = "قراءة قديمة"; old.author = "من مكتبتك"; old.shelf = "old"; old.finishedAt = ISO8601DateFormatter().date(from: "2016-10-01T12:00:00Z"); c.insert(old)
            for n in 1...12 { let h = HadithProgress(); h.id = StableIdentity.uuid(for: "hadith:nawawi40:\(n)"); h.collectionID = "nawawi40"; h.editionID = "wikisource-ar-500107"; h.number = n; h.readAt = now.addingTimeInterval(-86400); h.understood = true; c.insert(h) }
        }
        try c.save()
    }
}
#endif
