import Foundation
import MadarCore
import MadarData

extension AppDiaryService {
    func yearbookPages(year:Int,margins:Bool,sources:Bool,photos:Bool) throws -> [DiaryExportPage] {
        var options=DiaryExportOptions();options.year=year;options.margins=margins;options.sources=sources
        return try exportPages(options).compactMap{page in
            let media=page.media.filter{photos || $0.kind != "photo"}
            guard !page.lines.isEmpty || !media.isEmpty else{return nil}
            return .init(day:page.day,title:page.title,lines:page.lines,media:media)
        }
    }
    func exportYearbook(pages:[DiaryExportPage],year:Int,index:Bool) throws -> DiaryExportArtifact {
        try authorizeRead();guard !pages.isEmpty,pages.allSatisfy({$0.day.year==year}) else{throw DataError.invalidValue("لا توجد صفحات لهذه السنة")}
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryExport/"+UUID().uuidString,directoryHint:.isDirectory)
        try FileManager.default.createDirectory(at:root,withIntermediateDirectories:true,attributes:[.protectionKey:FileProtectionType.complete])
        do {let url=root.appending(path:"كتاب-"+String(year)+".pdf");try DiaryPDF.render(pages,digits:digits,coverYear:year,index:index,coverDates:app.yearLabels(year)).write(to:url,options:[.atomic,.completeFileProtection]);try authorizeRead();return .init(url:url,dayCount:pages.count)}catch{try? FileManager.default.removeItem(at:root);throw error}
    }
}
