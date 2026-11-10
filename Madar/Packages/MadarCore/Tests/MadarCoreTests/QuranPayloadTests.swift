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
    func testBuiltQiyamRouteKeepsAvailabilityGate() throws {
        let day=try GregorianDay("2026-10-15"),url=URL(string:"madar://quran/session/qiyam")!
        let built=RouteContext(trackingStart:day,today:day,settingsKeys:[],availability:.init(builtRooms:[.core,.quran]))
        XCTAssertEqual(try RouteRegistry.parse(url,context:built).path,["session","qiyam"])
        let absent=RouteContext(trackingStart:day,today:day,settingsKeys:[],availability:.m0)
        XCTAssertThrowsError(try RouteRegistry.parse(url,context:absent))
    }
}
