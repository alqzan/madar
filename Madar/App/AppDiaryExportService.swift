import Foundation
import SwiftData
import UIKit
import CoreText
import CryptoKit
import UniformTypeIdentifiers
import MadarCore
import MadarData
import MadarCommands
import MadarDesign

struct DiaryExportOptions {
    var format = "pdf"
    var year: Int?
    var month: Int?
    var margins = true
    var sources = true
}
struct DiaryExportPage {
    let day: GregorianDay
    let title: String
    let lines: [DiaryDisplayLine]
    let media: [DiaryDisplayMedia]
}
struct DiaryExportArtifact: Identifiable {
    let id=UUID()
    let url:URL
    let dayCount:Int
}
extension AppDiaryService {
    func exportPages(_ options:DiaryExportOptions) throws -> [DiaryExportPage] {
        try authorizeRead()
        let context = ModelContext(app.container)
        // Read each diary table once. Calling day() for every exported date made
        // a large imported diary repeatedly scan its store.
        let entries = Self.visible(try context.fetch(FetchDescriptor<Entry>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }, sortBy: [SortDescriptor(\.eventAt)])))
        let pages = try context.fetch(FetchDescriptor<DayPage>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        let margins = try context.fetch(FetchDescriptor<MarginNote>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        let intentions = try context.fetch(FetchDescriptor<Niyya>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))
        // Fetch only opened letters: sealed and eligible letters never enter an export.
        let letters = try context.fetch(FetchDescriptor<Letter>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil && $0.state == "opened" }))
        let entriesByDay = Dictionary(grouping: entries, by: \.dayKey)
        let pagesByDay = Dictionary(grouping: pages, by: \.dayKey)
        let intentionsByDay = Dictionary(grouping: intentions, by: \.dayKey)
        let lettersByDay = Dictionary(grouping: letters) { GregorianDay.containing($0.openedAt ?? $0.createdAt, in: app.activePlace.timeZone).description }
        var marginsByDay: [String: [MarginNote]] = [:]
        for margin in margins {
            marginsByDay[margin.targetDayKey, default: []].append(margin)
            if margin.writtenDayKey != margin.targetDayKey { marginsByDay[margin.writtenDayKey, default: []].append(margin) }
        }
        let snapshots=try context.fetch(FetchDescriptor<DeviceSetting>(predicate:#Predicate{$0.deletedAt == nil && $0.mergedInto == nil})).filter{$0.key.hasPrefix("sys.diaryAutoLines.")}
        var frozen:[String:[DiaryDisplayLine]]=[:]
        for row in snapshots {frozen[String(row.key.dropFirst("sys.diaryAutoLines.".count))]=try JSONDecoder().decode([DiaryDisplayLine].self,from:row.valueJSON)}
        var keys = Set(entriesByDay.keys)
        keys.formUnion(pages.filter { $0.photoMediaID != nil || $0.questionAnswer != nil }.map(\.dayKey))
        keys.formUnion(margins.map(\.writtenDayKey))
        keys.formUnion(intentionsByDay.keys)
        keys.formUnion(lettersByDay.keys)
        keys.formUnion(frozen.keys)
        if options.sources {
            keys.formUnion(try context.fetch(FetchDescriptor<PrayerLog>(predicate:#Predicate{$0.deletedAt == nil && $0.mergedInto == nil})).map(\.dayKey))
            keys.formUnion(try context.fetch(FetchDescriptor<HifzSession>(predicate:#Predicate{$0.deletedAt == nil && $0.mergedInto == nil})).map(\.dayKey))
        }
        let today=try currentDay()
        let dates = keys.compactMap{try? GregorianDay($0)}.filter{$0<=today && (options.year==nil || $0.year==options.year) && (options.month==nil || $0.month==options.month)}.sorted()
        let selectedKeys = Set(dates.map(\.description))
        let liveKeys = selectedKeys.subtracting(frozen.keys)
        let live = options.sources ? try DiaryLineRenderer.live(days: liveKeys, context: context) : [:]
        var mediaIDs = Set(entries.filter { selectedKeys.contains($0.dayKey) }.flatMap { $0.attachmentMediaIDs + ($0.mediaID.map { [$0] } ?? []) })
        mediaIDs.formUnion(pages.filter { selectedKeys.contains($0.dayKey) }.compactMap(\.photoMediaID))
        // Fetch referenced media in bounded batches; unrelated photo bytes stay out of memory.
        var mediaByID: [UUID: Media] = [:]
        let ids = Array(mediaIDs)
        for start in stride(from: 0, to: ids.count, by: 400) {
            let batch = Array(ids[start..<min(start + 400, ids.count)])
            for row in try context.fetch(FetchDescriptor<Media>(predicate: #Predicate { batch.contains($0.id) && $0.deletedAt == nil && $0.mergedInto == nil })) where mediaByID[row.id] == nil {
                mediaByID[row.id] = row
            }
        }
        return try dates.compactMap { date in
            let key = date.description, written = entriesByDay[key] ?? []
            var lines: [DiaryDisplayLine] = written.filter { ["normal", "late", "ghad"].contains($0.ink) }.map { row in
                let markdown = row.textFormat == "markdown"
                return .init(id: row.id.uuidString, at: row.eventAt, text: markdown ? DayOneMarkdown.readable(row.text) : row.text, kind: row.ink,
                             tzID: row.source == "dayOne" && !row.tzID.isEmpty ? row.tzID : nil, markdown: markdown ? true : nil)
            }
            if options.margins {
                for margin in marginsByDay[key] ?? [] {
                    let text = margin.targetDayKey == key ? margin.text : "كتبت في هامش " + bothDates(try GregorianDay(margin.targetDayKey), calendar: .gregorian) + ": " + margin.text
                    lines.append(.init(id: "margin." + margin.id.uuidString, at: margin.writtenAt, text: text, kind: "margin"))
                }
            }
            // Frozen lines (including an empty snapshot) replace live lines. Export
            // source selection is independent of the home screen's auto-line toggles.
            if options.sources { lines += frozen[key] ?? live[key] ?? [] }
            let at = date.date(in: app.activePlace.timeZone)
            for row in intentionsByDay[key] ?? [] { lines.append(.init(id: row.id.uuidString, at: at, text: row.text, kind: "intention")) }
            for row in lettersByDay[key] ?? [] { lines.append(.init(id: row.id.uuidString, at: at, text: row.text, kind: "letter")) }
            for row in pagesByDay[key] ?? [] {
                if let answer = row.questionAnswer, !answer.isEmpty { lines.append(.init(id: row.id.uuidString + "answer", at: at, text: answer, kind: "writing")) }
            }
            var media: [DiaryDisplayMedia] = []
            for entry in written {
                for id in entry.attachmentMediaIDs + (entry.mediaID.map { [$0] } ?? []) {
                    guard let row = mediaByID[id] else { continue }
                    if let data = row.data { media.append(.init(id: id, entryID: entry.id.uuidString, kind: row.kind, contentType: row.contentType, data: data, duration: row.durationS)) }
                    else if row.state == "missing" { media.append(.init(id: id, entryID: entry.id.uuidString, kind: "missing", contentType: row.kind, data: Data(), duration: nil)) }
                }
            }
            // A standalone page photo is exported even when hidden on the home screen.
            let page = pagesByDay[key]?.max { $0.updatedAt < $1.updatedAt }
            if let id = page?.photoMediaID, !media.contains(where: { $0.id == id }), let row = mediaByID[id], let data = row.data {
                media.append(.init(id: id, entryID: "page", kind: "photo", contentType: row.contentType, data: data, duration: nil))
            }
            lines=lines.filter{!$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
            guard !lines.isEmpty || !media.isEmpty else{return nil}
            return .init(day:date,title:bothDates(date,calendar:FirstCalendar(rawValue:app.string("core.firstCalendar")) ?? .hijri),lines:lines.sorted{$0.at == $1.at ? $0.id<$1.id : $0.at<$1.at},media:media)
        }
    }
    func exportDiary(_ options:DiaryExportOptions) throws -> DiaryExportArtifact {
        try authorizeRead()
        let pages=try exportPages(options)
        guard !pages.isEmpty else{throw DataError.invalidValue("لا توجد كتابة في الفترة المختارة")}
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryExport/"+UUID().uuidString,directoryHint:.isDirectory)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        do {
            let file:URL,bytes:Data
            if options.format=="pdf" {file=root.appending(path:"المذكرات.pdf");bytes=DiaryPDF.render(pages,digits:digits)}
            else {
                var files:[String:Data]=[:],entries:[[String:Any]]=[]
                let iso=ISO8601DateFormatter()
                for page in pages {
                    var markdown="# "+page.title+"\n\n"+page.lines.map{ time($0.at)+" — "+Self.exportLabel($0.kind)+$0.text }.joined(separator:"\n\n")
                    var jsonText=markdown,photos:[[String:Any]]=[]
                    for (order,item) in page.media.enumerated() {
                        let ext=(UTType(mimeType:item.contentType) ?? UTType(item.contentType))?.preferredFilenameExtension ?? "bin",path="media/"+item.id.uuidString+"."+ext
                        files[path]=item.data
                        markdown += "\n\n["+(item.kind=="photo" ? "صورة" : item.kind=="audio" ? "تسجيل صوتي" : "مرفق")+"](../"+path+")"
                        if item.kind=="photo",let image=UIImage(data:item.data),let jpeg=image.jpegData(compressionQuality:0.95) {
                            let hash=Insecure.MD5.hash(data:jpeg).map{String(format:"%02x",$0)}.joined(),id=item.id.uuidString.replacingOccurrences(of:"-",with:"")
                            files["photos/"+hash+".jpeg"]=jpeg
                            photos.append(["identifier":id,"md5":hash,"type":"jpeg","orderInEntry":order,"width":Int(image.size.width*image.scale),"height":Int(image.size.height*image.scale)])
                            jsonText += "\n\n![](dayone-moment://"+id+")"
                        } else {jsonText += "\n\n[مرفق]("+path+")"}
                    }
                    files["days/"+page.day.description+".md"]=Data(markdown.utf8)
                    let at=page.day.date(in:app.activePlace.timeZone).addingTimeInterval(12*3600)
                    // Stable synthetic day identity, no UUID generated on repeated exports.
                    let hash=SHA256.hash(data:Data(("madar.diary.day."+page.day.description).utf8)).prefix(16).map{String(format:"%02X",$0)}.joined()
                    entries.append(["uuid":hash,"creationDate":iso.string(from:at),"modifiedDate":iso.string(from:at),"timeZone":app.activePlace.timeZone.identifier,"text":jsonText,"photos":photos,"starred":false,"tags":[]])
                }
                if options.format=="json" {files["Journal.json"]=try JSONSerialization.data(withJSONObject:["metadata":["version":"1.0"],"entries":entries],options:[.sortedKeys,.prettyPrinted])}
                file=root.appending(path:options.format=="json" ? "المذكرات-JSON.zip":"المذكرات-Markdown.zip");bytes=try DiaryExportArchive.encode(files)
            }
            try bytes.write(to:file,options:[.atomic,.completeFileProtection]);try authorizeRead()
            return .init(url:file,dayCount:pages.count)
        } catch {try? FileManager.default.removeItem(at:root);throw error}
    }
    static func exportLabel(_ kind:String)->String {switch kind{case "margin":"هامش: ";case "salah":"الصلاة: ";case "quran":"القرآن: ";case "intention":"نيّة: ";case "letter":"رسالة مفتوحة: ";case "ghad":"لِغد: ";case "late":"كُتبت لاحقًا: ";default:""}}
    func shareDiary(_ artifact:DiaryExportArtifact) async throws {
        try authorizeRead()
        guard let controller=app.lockController,let presenter=app.privacyPresenter else{throw PrivacyAuthorizationError.stale}
        let ticket=try await controller.authorize([.notes]);try controller.validate(ticket);try presenter.present(file:artifact.url,authorization:ticket)
    }
}

@MainActor enum DiaryPDF {
    static func render(_ pages:[DiaryExportPage],digits:MadarNumberFormatter,coverYear:Int?=nil,index:Bool=false,coverDates:MadarDateLabels?=nil)->Data {
        let bounds=CGRect(x:0,y:0,width:595,height:842),notes=RoomTheme(room:"notes")
        let paper=UIColor(notes.background),ink=UIColor(notes.ink)
        let coverLeather=UIColor(MadarToken.colors["rooms.notes.lockCover.leather"] ?? notes.accent)
        let coverInk=UIColor(MadarToken.colors["rooms.notes.lockCover.text"] ?? notes.background)
        let marginInk=UIColor(notes.color("pencil"))
        let rulingInk=UIColor(notes.line).withAlphaComponent(0.72)
        var number=0
        return UIGraphicsPDFRenderer(bounds:bounds).pdfData { renderer in
            func begin(){renderer.beginPage();number+=1;paper.setFill();renderer.cgContext.fill(bounds);rulingInk.setStroke();let path=UIBezierPath();for y in stride(from:CGFloat(80),through:780,by:28){path.move(to:CGPoint(x:40,y:y));path.addLine(to:CGPoint(x:555,y:y))};path.lineWidth=0.5;path.stroke();(digits.string(number) as NSString).draw(at:CGPoint(x:290,y:805),withAttributes:[.font:UIFont.systemFont(ofSize:11),.foregroundColor:ink])}
            if let coverYear {
                begin();coverLeather.setFill();renderer.cgContext.fill(bounds)
                let style=NSMutableParagraphStyle();style.alignment = .center;style.baseWritingDirection = .rightToLeft
                ("مذكرات\n"+(coverDates?.primary ?? digits.string(coverYear)) as NSString).draw(in:CGRect(x:60,y:260,width:475,height:240),withAttributes:[.font:UIFont(name:"thmanyahserifdisplay-Bold",size:44) ?? UIFont.boldSystemFont(ofSize:44),.foregroundColor:coverInk,.paragraphStyle:style])
            }
                if let secondary = coverDates?.secondary {
                    let style = NSMutableParagraphStyle(); style.alignment = .center
                    (secondary as NSString).draw(in: CGRect(x:60,y:500,width:475,height:60), withAttributes:[.font:UIFont.systemFont(ofSize:18),.foregroundColor:coverInk,.paragraphStyle:style])
                }
            var indexLines:[String]=[]
            for page in pages {
                indexLines.append(page.title+" — "+digits.string(number+1))
                let paragraph=NSMutableParagraphStyle();paragraph.baseWritingDirection = .rightToLeft;paragraph.alignment = .right;paragraph.minimumLineHeight=28;paragraph.paragraphSpacing=10
                let headerParts = page.title.components(separatedBy: "، ")
                let text=NSMutableAttributedString(string:(headerParts.first ?? page.title)+"\n",attributes:[.font:UIFont(name:"thmanyahserifdisplay-Bold",size:25) ?? UIFont.boldSystemFont(ofSize:25),.foregroundColor:ink,.paragraphStyle:paragraph])
                if headerParts.count > 1 { text.append(NSAttributedString(string:headerParts.dropFirst().joined(separator: "، ")+"\n\n",attributes:[.font:UIFont.systemFont(ofSize:13),.foregroundColor:ink,.paragraphStyle:paragraph])) }
                for line in page.lines {text.append(NSAttributedString(string:AppDiaryService.exportLabel(line.kind)+(line.markdown == true ? DayOneMarkdown.plain(line.text) : line.text)+"\n\n",attributes:[.font:UIFont(name:"thmanyahseriftext-Regular",size:17) ?? UIFont.systemFont(ofSize:17),.foregroundColor:line.kind=="margin" ? marginInk:ink,.paragraphStyle:paragraph]))}
                for item in page.media where item.kind != "photo" {
                    let label=item.kind=="audio" ? "تسجيل صوتي محفوظ في هذا اليوم" : "مرفق محفوظ في هذا اليوم"
                    text.append(NSAttributedString(string:label+"\n\n",attributes:[.font:UIFont.systemFont(ofSize:14),.foregroundColor:ink,.paragraphStyle:paragraph]))
                }
                let setter=CTFramesetterCreateWithAttributedString(text);var cursor=0
                while cursor<text.length {
                    begin();let path=CGPath(rect:CGRect(x:40,y:50,width:515,height:742),transform:nil),frame=CTFramesetterCreateFrame(setter,CFRange(location:cursor,length:0),path,nil),visible=CTFrameGetVisibleStringRange(frame)
                    guard visible.length>0 else{break};let cg=renderer.cgContext;cg.saveGState();cg.translateBy(x:0,y:842);cg.scaleBy(x:1,y:-1);CTFrameDraw(frame,cg);cg.restoreGState();cursor+=visible.length
                }
                for item in page.media where item.kind=="photo" {if let image=UIImage(data:item.data){begin();(page.title as NSString).draw(in:CGRect(x:40,y:36,width:515,height:65),withAttributes:[.font:UIFont.systemFont(ofSize:18),.foregroundColor:ink,.paragraphStyle:paragraph]);let scale=min(515/image.size.width,665/image.size.height),size=CGSize(width:image.size.width*scale,height:image.size.height*scale);image.draw(in:CGRect(x:(595-size.width)/2,y:115,width:size.width,height:size.height))}}
            }
            if index {
                let paragraph=NSMutableParagraphStyle();paragraph.alignment = .right;paragraph.baseWritingDirection = .rightToLeft;paragraph.minimumLineHeight=28
                let text=NSAttributedString(string:"فهرس الأيام\n\n"+indexLines.joined(separator:"\n"),attributes:[.font:UIFont(name:"thmanyahseriftext-Regular",size:16) ?? UIFont.systemFont(ofSize:16),.foregroundColor:ink,.paragraphStyle:paragraph])
                let setter=CTFramesetterCreateWithAttributedString(text);var cursor=0
                while cursor<text.length {begin();let path=CGPath(rect:CGRect(x:40,y:50,width:515,height:742),transform:nil),frame=CTFramesetterCreateFrame(setter,CFRange(location:cursor,length:0),path,nil),visible=CTFrameGetVisibleStringRange(frame);guard visible.length>0 else{break};let cg=renderer.cgContext;cg.saveGState();cg.translateBy(x:0,y:842);cg.scaleBy(x:1,y:-1);CTFrameDraw(frame,cg);cg.restoreGState();cursor+=visible.length}
            }
        }
    }
}
