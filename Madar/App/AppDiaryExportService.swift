import Foundation
import SwiftData
import UIKit
import CoreText
import CryptoKit
import UniformTypeIdentifiers
import MadarCore
import MadarData
import MadarCommands

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
        let context=ModelContext(app.container),index=try searchIndex()
        let snapshots=try context.fetch(FetchDescriptor<DeviceSetting>(predicate:#Predicate{$0.deletedAt == nil && $0.mergedInto == nil})).filter{$0.key.hasPrefix("sys.diaryAutoLines.")}
        var frozen:[String:[DiaryDisplayLine]]=[:]
        for row in snapshots {frozen[String(row.key.dropFirst("sys.diaryAutoLines.".count))]=try JSONDecoder().decode([DiaryDisplayLine].self,from:row.valueJSON)}
        var keys=Set(try archive().days.map(\.day.description)+index.documents.map(\.day.description)+Array(frozen.keys))
        if options.sources {
            keys.formUnion(try context.fetch(FetchDescriptor<PrayerLog>(predicate:#Predicate{$0.deletedAt == nil && $0.mergedInto == nil})).map(\.dayKey))
            keys.formUnion(try context.fetch(FetchDescriptor<HifzSession>(predicate:#Predicate{$0.deletedAt == nil && $0.mergedInto == nil})).map(\.dayKey))
        }
        let today=try currentDay()
        return try keys.compactMap{try? GregorianDay($0)}.filter{$0<=today && (options.year==nil || $0.year==options.year) && (options.month==nil || $0.month==options.month)}.sorted().compactMap { date in
            let page=try day(date)
            var lines=page.lines.filter{["normal","late","ghad"].contains($0.kind) || (options.margins && $0.kind=="margin")}
            if options.sources {lines += try frozen[date.description] ?? DiaryLineRenderer.live(day:date,context:context)}
            for doc in index.documents where doc.day==date && (["letter","intention"].contains(doc.kind) || doc.id.hasSuffix("answer")) {
                lines.append(.init(id:doc.id,at:date.date(in:app.activePlace.timeZone),text:doc.text,kind:doc.kind))
            }
            var media=page.media
            let key=date.description
            if let id=try context.fetch(FetchDescriptor<DayPage>(predicate:#Predicate{$0.dayKey == key && $0.deletedAt == nil && $0.mergedInto == nil})).first?.photoMediaID,!media.contains(where:{$0.id==id}),let row=try context.fetch(FetchDescriptor<Media>(predicate:#Predicate{$0.id == id && $0.deletedAt == nil && $0.mergedInto == nil})).first,let data=row.data {media.append(.init(id:id,entryID:"page",kind:"photo",contentType:row.contentType,data:data,duration:nil))}
            lines=lines.filter{!$0.text.trimmingCharacters(in:.whitespacesAndNewlines).isEmpty}
            guard !lines.isEmpty || !media.isEmpty else{return nil}
            return .init(day:date,title:dateTitle(date,calendar:FirstCalendar(rawValue:app.string("core.firstCalendar")) ?? .hijri),lines:lines.sorted{$0.at == $1.at ? $0.id<$1.id : $0.at<$1.at},media:media)
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
    static func render(_ pages:[DiaryExportPage],digits:MadarNumberFormatter,coverYear:Int?=nil,index:Bool=false)->Data {
        let bounds=CGRect(x:0,y:0,width:595,height:842),paper=UIColor(red:0.96,green:0.94,blue:0.89,alpha:1),ink=UIColor(red:0.16,green:0.14,blue:0.11,alpha:1)
        var number=0
        return UIGraphicsPDFRenderer(bounds:bounds).pdfData { renderer in
            func begin(){renderer.beginPage();number+=1;paper.setFill();renderer.cgContext.fill(bounds);UIColor(white:0.5,alpha:0.14).setStroke();let path=UIBezierPath();for y in stride(from:CGFloat(80),through:780,by:28){path.move(to:CGPoint(x:40,y:y));path.addLine(to:CGPoint(x:555,y:y))};path.lineWidth=0.5;path.stroke();(digits.string(number) as NSString).draw(at:CGPoint(x:290,y:805),withAttributes:[.font:UIFont.systemFont(ofSize:10),.foregroundColor:ink])}
            if let coverYear {
                begin();UIColor(red:0.369,green:0.169,blue:0.106,alpha:1).setFill();renderer.cgContext.fill(bounds)
                let style=NSMutableParagraphStyle();style.alignment = .center;style.baseWritingDirection = .rightToLeft
                ("مذكرات\n"+digits.string(coverYear) as NSString).draw(in:CGRect(x:60,y:260,width:475,height:240),withAttributes:[.font:UIFont(name:"thmanyahserifdisplay-Bold",size:44) ?? UIFont.boldSystemFont(ofSize:44),.foregroundColor:UIColor(red:0.949,green:0.902,blue:0.827,alpha:1),.paragraphStyle:style])
            }
            var indexLines:[String]=[]
            for page in pages {
                indexLines.append(page.title+" — "+digits.string(number+1))
                let paragraph=NSMutableParagraphStyle();paragraph.baseWritingDirection = .rightToLeft;paragraph.alignment = .right;paragraph.minimumLineHeight=28;paragraph.paragraphSpacing=10
                let text=NSMutableAttributedString(string:page.title+"\n\n",attributes:[.font:UIFont(name:"thmanyahserifdisplay-Bold",size:25) ?? UIFont.boldSystemFont(ofSize:25),.foregroundColor:ink,.paragraphStyle:paragraph])
                for line in page.lines {text.append(NSAttributedString(string:AppDiaryService.exportLabel(line.kind)+line.text+"\n\n",attributes:[.font:UIFont(name:"thmanyahseriftext-Regular",size:17) ?? UIFont.systemFont(ofSize:17),.foregroundColor:line.kind=="margin" ? UIColor(red:0.18,green:0.32,blue:0.39,alpha:1):ink,.paragraphStyle:paragraph]))}
                for item in page.media where item.kind != "photo" {
                    let label=item.kind=="audio" ? "تسجيل صوتي محفوظ في هذا اليوم" : "مرفق محفوظ في هذا اليوم"
                    text.append(NSAttributedString(string:label+"\n\n",attributes:[.font:UIFont.systemFont(ofSize:14),.foregroundColor:ink,.paragraphStyle:paragraph]))
                }
                let setter=CTFramesetterCreateWithAttributedString(text);var cursor=0
                while cursor<text.length {
                    begin();let path=CGPath(rect:CGRect(x:40,y:50,width:515,height:742),transform:nil),frame=CTFramesetterCreateFrame(setter,CFRange(location:cursor,length:0),path,nil),visible=CTFrameGetVisibleStringRange(frame)
                    guard visible.length>0 else{break};let cg=renderer.cgContext;cg.saveGState();cg.translateBy(x:0,y:842);cg.scaleBy(x:1,y:-1);CTFrameDraw(frame,cg);cg.restoreGState();cursor+=visible.length
                }
                for item in page.media where item.kind=="photo" {if let image=UIImage(data:item.data){begin();(page.title as NSString).draw(in:CGRect(x:40,y:36,width:515,height:40),withAttributes:[.font:UIFont.systemFont(ofSize:18),.foregroundColor:ink,.paragraphStyle:paragraph]);let scale=min(515/image.size.width,690/image.size.height),size=CGSize(width:image.size.width*scale,height:image.size.height*scale);image.draw(in:CGRect(x:(595-size.width)/2,y:90,width:size.width,height:size.height))}}
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
