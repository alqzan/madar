#if DEBUG
import Foundation
import UIKit
import AVFoundation
import SwiftData
import MadarCore
import MadarData

extension AppSession {
    func prepareDiaryHomeFixture(group: URL) throws {
        let env = ProcessInfo.processInfo.environment
        guard let variant = env["MADAR_UI_DIARY_FIXTURE"], ["home", "empty", "echoes", "margin", "welcome", "today", "editor", "return", "travel", "letters"].contains(variant), let id = env["MADAR_UI_STORE_ID"],
              group.lastPathComponent == id, group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        selectedTab = "notes"
        let context = ModelContext(container)
        guard !(try context.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.diaryFixture" }) else { return }
        let settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.faceIDLock": .string("none"), "core.dayStart": .string("midnight")])
        for key in ["sys.onboardingCompleted", "sys.diaryFixture"] { let row = DeviceSetting(); row.key = key; row.valueJSON = Data("true".utf8); context.insert(row) }
        if variant != "welcome" { let marker = DeviceSetting(); marker.key = "sys.diaryWelcomeSeen"; marker.valueJSON = Data("true".utf8); context.insert(marker) }
        if variant == "echoes" || variant == "margin" { _ = try settings.stage(["notes.homeShape": .string(variant)]) }
        if variant == "letters" {
            // N04: one letter due since yesterday, one sealed today, and a project whose keyword today's line mentions.
            let now=prayerUITestClock(.now),today=GregorianDay.containing(now,in:.riyadh)
            let due=Letter();due.text="أرجو أن تكون أخفّ مما كنت يوم كتبتها.";due.triggerKind="date";due.triggerValue=today.adding(days:-1).description;due.openAt=today.adding(days:-1).date(in:.riyadh);due.createdAt=now.addingTimeInterval(-40*86400);context.insert(due)
            let sealed=Letter();sealed.text="لا تُقرأ قبل وقتها";sealed.triggerKind="date";sealed.triggerValue=today.adding(days:60).description;sealed.createdAt=now.addingTimeInterval(-3600);context.insert(sealed)
            let project=Project();project.name="ترتيب البيت";project.intention="بيت أهدأ قبل رمضان";project.keyword="البيت";context.insert(project)
            let row=Entry();row.dayKey=today.description;row.text="دهنّا غرفة البيت الصغيرة.";row.eventAt=now.addingTimeInterval(-2*3600);row.tzID="Asia/Riyadh";row.dayPolicy="midnight@1";context.insert(row)
            try context.save();return
        }
        if variant == "travel" {
            // A shared Trip as Prayer's explicit arrival would store it: Istanbul since yesterday; no homeKm, so distance is derived.
            let now=prayerUITestClock(.now),istanbul=TimeZone(identifier:"Europe/Istanbul")!,trip=Trip()
            trip.city="إسطنبول";trip.country="TR";trip.lat=41.0082;trip.lon=28.9784;trip.tzID="Europe/Istanbul";trip.mode="manual";trip.start=now.addingTimeInterval(-26*3600);context.insert(trip)
            // A past trip already returned from: five nights in Cairo, so the calendar frames them and the return day folds the envelope.
            let cairo=Trip();cairo.city="القاهرة";cairo.country="EG";cairo.lat=30.0444;cairo.lon=31.2357;cairo.tzID="Africa/Cairo";cairo.mode="manual"
            cairo.start=now.addingTimeInterval(-20*86400);cairo.end=now.addingTimeInterval(-15*86400);context.insert(cairo)
            let today=GregorianDay.containing(now,in:istanbul),base=today.date(in:istanbul)
            let prayer=PrayerLog();prayer.dayKey=today.description;prayer.prayer="fajr";prayer.status="jamaah";prayer.eventAt=base.addingTimeInterval(5*3600+52*60);prayer.tzID="Europe/Istanbul";context.insert(prayer)
            for (minutes,text) in [(370,"أول فجر في إسطنبول. الأذان من ثلاثة مساجد في وقت واحد."),(840,"الجو بارد، والشاي في كل زاوية. تعبنا من المشي وجلسنا عند البحر.")] {
                let row=Entry();row.dayKey=today.description;row.text=text;row.eventAt=base.addingTimeInterval(Double(minutes)*60);row.tzID="Europe/Istanbul";row.dayPolicy="midnight@1";context.insert(row)
            }
            let media=Media();media.kind="photo";media.contentType="image/jpeg";media.data=Self.diaryFixturePhoto(variant:2);media.sizeBytes=media.data?.count ?? 0;context.insert(media)
            let photo=Entry();photo.dayKey=today.description;photo.text="البحر من جسر غلطة.";photo.attachmentMediaIDs=[media.id];photo.eventAt=base.addingTimeInterval(870*60);photo.tzID="Europe/Istanbul";photo.dayPolicy="midnight@1";context.insert(photo)
            try context.save();return
        }
        if variant == "return" {
            let day=GregorianDay.containing(prayerUITestClock(.now),in:.riyadh).adding(days:-5),row=Entry();row.dayKey=day.description;row.text="آخر سطر محفوظ قبل الانقطاع";row.tzID="Asia/Riyadh";row.eventAt=day.date(in:.riyadh).addingTimeInterval(12*3600);context.insert(row);try context.save();return
        }
        if variant != "empty" && variant != "welcome" {
            let today = GregorianDay.containing(prayerUITestClock(.now), in: .riyadh)
            func append(_ day: GregorianDay, _ text: String, hour: Int, imported: Bool = false) {
                let row = Entry(); row.dayKey = day.description; row.text = text; row.eventAt = day.date(in: .riyadh).addingTimeInterval(Double(hour) * 3600)
                row.tzID = "Asia/Riyadh"; row.dayPolicy = "midnight@1"; row.place = "الرياض"; row.source = imported ? "dayOne" : "native"; context.insert(row)
            }
            for age in 1...3 {
                let day = try GregorianDay(year: today.year - age, month: today.month, day: today.day)
                let page = DayPage(); page.dayKey = day.description; page.origin = variant == "margin" ? "native" : "dayOne"
                let media = Media(); media.kind = "photo"; media.contentType = "image/jpeg"; media.data = Self.diaryFixturePhoto(variant: age)
                media.sizeBytes = media.data?.count ?? 0; context.insert(media); page.photoMediaID = media.id; context.insert(page)
                append(day, age == 1 ? "عشاء عند أهلي، وأمي سوّت المرقوق. ضحكنا على صور العيد القديمة." : age == 2 ? "مشينا بعد المغرب، والجو صار يحتمل." : "اتصلت على خالي، وطال الحديث.", hour: 20, imported: variant != "margin")
                if age == 1 {
                    let prayer = PrayerLog(); prayer.dayKey = day.description; prayer.prayer = "fajr"; prayer.status = "jamaah"; prayer.eventAt = day.date(in: .riyadh).addingTimeInterval(5*3600); context.insert(prayer)
                    let review = HifzSession(); review.dayKey = day.description; review.kind = "review"; review.fromAyah = 1; review.toAyah = 7; review.pages = [1]; review.endedAt = day.date(in: .riyadh).addingTimeInterval(16*3600); context.insert(review)
                }
            }
            for n in 1...5 {
                let day = today.adding(days: -n), page = DayPage(); page.dayKey = day.description; context.insert(page)
                append(day, ["دوام طويل. وصلت البيت قبل العشاء بدقائق.", "مشيت بعد المغرب، والجو صار يحتمل.", "اتصلت على خالي، وطال الحديث.", "صمت. الإفطار عند أخي.", "بداية أسبوع هادئة."][n-1], hour: 18)
            }
            if variant == "echoes" {
                for (n, offset) in [7, 30, 92, 183].enumerated() {
                    let day = today.adding(days: -offset), page = DayPage(); page.dayKey = day.description
                    let media = Media(); media.kind = "photo"; media.contentType = "image/jpeg"; media.data = Self.diaryFixturePhoto(variant: n+1); media.sizeBytes = media.data?.count ?? 0
                    context.insert(media); page.photoMediaID = media.id; context.insert(page)
                    append(day, ["جلست بعد الفجر حتى الشروق.", "قهوة وحديث طويل مع أخي.", "قرأت ثم مشيت قليلًا.", "يوم هادئ جمعنا في البيت."][n], hour: 18)
                }
            }
            append(today, "ما زال في اليوم متّسع.", hour: 12)
            if variant == "editor" {
                func attach(id: String, kind: String, type: String, data: Data, text: String, hour: Int) {
                    let media = Media(); media.id = UUID(uuidString: id)!; media.kind = kind; media.contentType = type; media.data = data; media.sizeBytes = data.count; if kind == "audio" { media.durationS = 1 }; context.insert(media)
                    let row = Entry(); row.dayKey = today.description; row.eventAt = today.date(in: .riyadh).addingTimeInterval(Double(hour)*3600); row.text = text
                    if kind == "audio" { row.mediaID = media.id } else { row.attachmentMediaIDs = [media.id] }; context.insert(row)
                }
                attach(id: "33333333-3333-4333-8333-333333330001", kind: "photo", type: "image/jpeg", data: Self.diaryFixturePhoto(variant: 1)!, text: "صورة احتفظت بها اليوم.", hour: 8)
                attach(id: "33333333-3333-4333-8333-333333330002", kind: "audio", type: "audio/mp4", data: try Self.diaryFixtureAudio(), text: "نص تسجيل محفوظ.", hour: 9)
                let pdf = UIGraphicsPDFRenderer(bounds: CGRect(x: 0, y: 0, width: 400, height: 500)).pdfData { canvas in canvas.beginPage(); ("مرفق تجريبي محفوظ" as NSString).draw(at: CGPoint(x: 40, y: 80), withAttributes: [.font: UIFont.systemFont(ofSize: 24)]) }
                attach(id: "33333333-3333-4333-8333-333333330003", kind: "document", type: "application/pdf", data: pdf, text: "ورقة.pdf", hour: 10)
            }

            if variant == "today" {
                let page = DayPage(); page.dayKey = today.description
                let media = Media(); media.kind = "photo"; media.contentType = "image/jpeg"; media.data = Self.diaryFixturePhoto(variant: 1); media.sizeBytes = media.data?.count ?? 0
                context.insert(media); page.photoMediaID = media.id; context.insert(page)
                let prayer = PrayerLog(); prayer.dayKey = today.description; prayer.prayer = "fajr"; prayer.status = "jamaah"; prayer.eventAt = today.date(in: .riyadh).addingTimeInterval(5*3600); context.insert(prayer)
                for (n, text) in ["الهواء أول مرة فيه برودة خفيفة.", "قهوة على الشرفة قبل ما أفتح الجوال.", "اجتماع طويل، ثم رجعت للمكتب.", "مشيت قليلًا بعد الظهر.", "كتبت فكرة أريد أن أتذكرها.", "اتصلت بأمي واطمأننت عليها.", "قرأت قليلًا قبل الغداء.", "وصلت إلى آخر ما كتبت اليوم."].enumerated() { append(today, text, hour: 6+n) }
            }

        }
        try context.save()
    }
    private static func diaryFixtureAudio() throws -> Data {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString + ".m4a")
        defer { try? FileManager.default.removeItem(at: url) }
        let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 44_100, channels: 1, interleaved: false)!
        let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: 44_100)!; buffer.frameLength = 44_100
        buffer.floatChannelData![0].initialize(repeating: 0, count: 44_100)
        do { let file = try AVAudioFile(forWriting: url, settings: [AVFormatIDKey: kAudioFormatMPEG4AAC, AVSampleRateKey: 44_100, AVNumberOfChannelsKey: 1]); try file.write(from: buffer) }
        return try Data(contentsOf: url)
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
