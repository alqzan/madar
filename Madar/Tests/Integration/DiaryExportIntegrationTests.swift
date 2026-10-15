import XCTest
import SwiftData
import UIKit
import PDFKit
import MadarCore
import MadarData
import MadarCommands
@testable import Madar
@MainActor final class DiaryExportIntegrationTests:XCTestCase {
    func testFrozenSourcesMediaSealedExclusionAndOutputFormats() async throws {
        let root=FileManager.default.temporaryDirectory.appending(path:"DiaryExportTest-\(UUID())");defer{try? FileManager.default.removeItem(at:root)}
        let container=try MadarContainerFactory.makeLocal(at:root.appending(path:"Data")),app=try AppSession(container:container,groupDirectory:root),service=AppDiaryService(app:app)
        XCTAssertThrowsError(try service.exportPages(.init()));app.authorizeProtectedData()
        let context=ModelContext(container),entry=Entry(),photo=Media(),audio=Media(),sealed=Letter(),note=MarginNote(),frozen=DeviceSetting(),prayer=PrayerLog()
        entry.dayKey="2024-03-11";entry.text=String(repeating:"سطر محفوظ بالنص العربي. ",count:800)+" LAST-PARAGRAPH";context.insert(entry)
        photo.kind="photo";photo.contentType="image/jpeg";photo.data=UIGraphicsImageRenderer(size:CGSize(width:80,height:80)).jpegData(withCompressionQuality:1){renderer in UIColor.orange.setFill();renderer.fill(CGRect(x:0,y:0,width:80,height:80))};context.insert(photo)
        audio.kind="audio";audio.contentType="audio/mp4";audio.data=Data([7,8,9,10]);context.insert(audio);entry.attachmentMediaIDs=[photo.id];entry.mediaID=audio.id
        sealed.text="DO-NOT-EXPORT-SEALED";context.insert(sealed)
        note.targetDayKey=entry.dayKey;note.writtenDayKey="2024-03-12";note.text="هامش تاريخي";context.insert(note)
        prayer.dayKey=entry.dayKey;prayer.prayer="fajr";prayer.status="alone";context.insert(prayer)
        frozen.key="sys.diaryAutoLines."+entry.dayKey;frozen.valueJSON=try JSONEncoder().encode([DiaryAutoLine(id:"frozen",at:entry.eventAt,text:"صلّيت الفجر جماعة",kind:"salah")]);context.insert(frozen);try context.save()
        var options=DiaryExportOptions();options.year=2024;options.month=3
        let standalone=DayPage();standalone.dayKey="2024-03-12";standalone.photoMediaID=photo.id;context.insert(standalone);try context.save()
        try await app.applySettingsAndWait(["notes.showPhoto":.bool(false)])
        let pages=try service.exportPages(options);XCTAssertEqual(pages.first{$0.day.description=="2024-03-12"}?.media.map(\.id),[photo.id]);XCTAssertTrue(pages.flatMap(\.lines).contains{$0.text=="صلّيت الفجر جماعة"});XCTAssertFalse(pages.flatMap(\.lines).contains{$0.text.contains("وحدي") || $0.text.contains("DO-NOT")})
        let pdf=try service.exportDiary(options);defer{try? FileManager.default.removeItem(at:pdf.url.deletingLastPathComponent())}
        let document=try XCTUnwrap(PDFDocument(url:pdf.url));XCTAssertGreaterThan(document.pageCount,3);XCTAssertTrue(document.string?.contains("LAST-PARAGRAPH")==true)
        options.format="markdown";let md=try service.exportDiary(options);defer{try? FileManager.default.removeItem(at:md.url.deletingLastPathComponent())}
        let files=try DiaryExportArchive.files(Data(contentsOf:md.url));XCTAssertEqual(files["media/"+audio.id.uuidString+".mp4"],audio.data);XCTAssertEqual(files["media/"+photo.id.uuidString+".jpeg"],photo.data)
        let text=String(data:try XCTUnwrap(files["days/2024-03-11.md"]),encoding:.utf8)!;XCTAssertTrue(text.contains("هامش تاريخي"));XCTAssertTrue(text.contains("صلّيت الفجر جماعة"));XCTAssertFalse(text.contains("DO-NOT"))
        options.format="json";let json=try service.exportDiary(options);defer{try? FileManager.default.removeItem(at:json.url.deletingLastPathComponent())}
        let jsonFiles=try DiaryExportArchive.files(Data(contentsOf:json.url)),object=try XCTUnwrap(JSONSerialization.jsonObject(with:try XCTUnwrap(jsonFiles["Journal.json"])) as? [String:Any]),rows=try XCTUnwrap(object["entries"] as? [[String:Any]])
        XCTAssertEqual((object["metadata"] as? [String:String])?["version"],"1.0");let row=try XCTUnwrap(rows.first);XCTAssertEqual((row["uuid"] as? String)?.count,32);XCTAssertTrue((row["text"] as? String)?.contains("dayone-moment://")==true);XCTAssertEqual((row["photos"] as? [[String:Any]])?.count,1)
        XCTAssertFalse(String(data:try XCTUnwrap(jsonFiles["Journal.json"]),encoding:.utf8)!.contains("DO-NOT"))
        options.sources=false;options.margins=false;XCTAssertFalse(try service.exportPages(options).flatMap(\.lines).contains{["margin","salah"].contains($0.kind)})
        options.year=2020;XCTAssertThrowsError(try service.exportDiary(options))
    }
}
