#if DEBUG
import Foundation
import UIKit
import SwiftData
import MadarCore
import MadarData

extension AppSession {
    func prepareDiaryHomeFixture(group: URL) throws {
        let env = ProcessInfo.processInfo.environment
        guard let variant = env["MADAR_UI_DIARY_FIXTURE"], ["home", "empty"].contains(variant), let id = env["MADAR_UI_STORE_ID"],
              group.lastPathComponent == id, group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        selectedTab = "notes"
        let context = ModelContext(container)
        guard !(try context.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.diaryFixture" }) else { return }
        let settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight")])
        for key in ["sys.onboardingCompleted", "sys.diaryFixture"] { let row = DeviceSetting(); row.key = key; row.valueJSON = Data("true".utf8); context.insert(row) }
        if variant == "home" {
            let today = GregorianDay.containing(prayerUITestClock(.now), in: .riyadh)
            func append(_ day: GregorianDay, _ text: String, hour: Int, imported: Bool = false) {
                let row = Entry(); row.dayKey = day.description; row.text = text; row.eventAt = day.date(in: .riyadh).addingTimeInterval(Double(hour) * 3600)
                row.tzID = "Asia/Riyadh"; row.dayPolicy = "midnight@1"; row.place = "الرياض"; row.source = imported ? "dayOne" : "native"; context.insert(row)
            }
            for age in 1...3 {
                let day = try GregorianDay(year: today.year - age, month: today.month, day: today.day)
                let page = DayPage(); page.dayKey = day.description; page.origin = "dayOne"
                let media = Media(); media.kind = "photo"; media.contentType = "image/jpeg"; media.data = Self.diaryFixturePhoto(variant: age)
                media.sizeBytes = media.data?.count ?? 0; context.insert(media); page.photoMediaID = media.id; context.insert(page)
                append(day, age == 1 ? "عشاء عند أهلي، وأمي سوّت المرقوق. ضحكنا على صور العيد القديمة." : age == 2 ? "مشينا بعد المغرب، والجو صار يحتمل." : "اتصلت على خالي، وطال الحديث.", hour: 20, imported: true)
                if age == 1 {
                    let prayer = PrayerLog(); prayer.dayKey = day.description; prayer.prayer = "fajr"; prayer.status = "jamaah"; prayer.eventAt = day.date(in: .riyadh).addingTimeInterval(5*3600); context.insert(prayer)
                    let review = HifzSession(); review.dayKey = day.description; review.kind = "review"; review.fromAyah = 1; review.toAyah = 7; review.pages = [1]; review.endedAt = day.date(in: .riyadh).addingTimeInterval(16*3600); context.insert(review)
                }
            }
            for n in 1...5 {
                let day = today.adding(days: -n), page = DayPage(); page.dayKey = day.description; context.insert(page)
                append(day, ["دوام طويل. وصلت البيت قبل العشاء بدقائق.", "مشيت بعد المغرب، والجو صار يحتمل.", "اتصلت على خالي، وطال الحديث.", "صمت. الإفطار عند أخي.", "بداية أسبوع هادئة."][n-1], hour: 18)
            }
            append(today, "ما زال في اليوم متّسع.", hour: 12)
        }
        try context.save()
    }
    private static func diaryFixturePhoto(variant: Int) -> Data? {
        let renderer = UIGraphicsImageRenderer(size: CGSize(width: 720, height: 800))
        return renderer.jpegData(withCompressionQuality: 0.8) { surface in
            let c = surface.cgContext, colors = [UIColor(red: 0.22, green: 0.12, blue: 0.07, alpha: 1).cgColor, UIColor(red: 0.62, green: 0.37, blue: 0.16, alpha: 1).cgColor, UIColor(red: 0.15, green: 0.08, blue: 0.04, alpha: 1).cgColor]
            c.drawLinearGradient(CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: colors as CFArray, locations: [0,0.4,1])!, start: .zero, end: .init(x: 550, y: 800), options: [.drawsBeforeStartLocation, .drawsAfterEndLocation])
            for (x,y,r) in [(140.0,240.0,24.0),(500,160,32),(330,300,46),(600,360,28),(250,110,18)] {
                let glow = CGGradient(colorsSpace: CGColorSpaceCreateDeviceRGB(), colors: [UIColor(red: 1, green: 0.82, blue: 0.5, alpha: 0.8).cgColor, UIColor.clear.cgColor] as CFArray, locations: [0.7,1])!
                c.drawRadialGradient(glow, startCenter: .init(x: x, y: y), startRadius: 0, endCenter: .init(x: x, y: y), endRadius: r + Double(variant)*3, options: [])
            }
        }
    }
}
private extension TimeZone { static let riyadh = TimeZone(identifier: "Asia/Riyadh")! }
#endif
