import XCTest
@testable import MadarCore
final class QuranPayloadTests:XCTestCase {
    func testPartialConfirmationRequiresBooleanAndKnownFields() {
        let id=UUID().uuidString
        XCTAssertTrue(QuranCommandPayload.validate(name:"quran.commitSession",payload:["draftID":.string(id),"partial":.bool(true)]))
        XCTAssertTrue(QuranCommandPayload.validate(name:"quran.commitSession",payload:["draftID":.string(id)]))
        XCTAssertFalse(QuranCommandPayload.validate(name:"quran.commitSession",payload:["draftID":.string(id),"partial":.number(1)]))
        XCTAssertFalse(QuranCommandPayload.validate(name:"quran.discardDraft",payload:["draftID":.string(id),"partial":.bool(true)]))
        XCTAssertTrue(QuranCommandPayload.validate(name:"quran.discardUnreadableDrafts",payload:[:]))
        XCTAssertFalse(QuranCommandPayload.validate(name:"quran.discardUnreadableDrafts",payload:["draftID":.string(id)]))
    }
    /// The wird notification's «أتممته» opens the grade question through this route (14 Nov 2026): it must parse once Quran is built, and take no extra path.
    func testFinishWholeRouteParsesAndRejectsExtraPath() throws {
        let day=try GregorianDay("2026-10-15"),built=RouteContext(trackingStart:day,today:day,settingsKeys:[],availability:.init(builtRooms:[.core,.quran]))
        XCTAssertEqual(try RouteRegistry.parse(URL(string:"madar://quran/finish-whole")!,context:built).path,["finish-whole"])
        XCTAssertThrowsError(try RouteRegistry.parse(URL(string:"madar://quran/finish-whole/extra")!,context:built))
    }
    func testBuiltQiyamRouteKeepsAvailabilityGate() throws {
        let day=try GregorianDay("2026-10-15"),url=URL(string:"madar://quran/session/qiyam")!
        let built=RouteContext(trackingStart:day,today:day,settingsKeys:[],availability:.init(builtRooms:[.core,.quran]))
        XCTAssertEqual(try RouteRegistry.parse(url,context:built).path,["session","qiyam"])
        let absent=RouteContext(trackingStart:day,today:day,settingsKeys:[],availability:.m0)
        XCTAssertThrowsError(try RouteRegistry.parse(url,context:absent))
    }
}
