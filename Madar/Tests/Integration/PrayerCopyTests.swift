import XCTest
import MadarCore
@testable import Madar

/// M1-V01 · RU3: prayer home counts use String Catalog plural categories.
/// Expected phrases are hand-written Arabic grammar, not catalog output.
final class PrayerCopyTests: XCTestCase {
    private let hindi = MadarNumberFormatter(style: .hindi)
    private func plain(_ text: String) -> String { text.filter { $0 != "\u{2068}" && $0 != "\u{2069}" } }

    func test_M1V01_RU3_PrayerHomePluralCategories() {
        let days: [(Int, String)] = [(0, "لم تبدأ بعد"), (1, "يوم واحد"), (2, "يومان"), (3, "٣ أيام"), (8, "٨ أيام"), (11, "١١ يومًا"), (100, "١٠٠ يوم")]
        for (count, expected) in days { XCTAssertEqual(plain(PrayerCopy.days(count, digits: hindi)), expected) }
        let remaining: [(Int, String)] = [(0, "اكتمل تسجيل اليوم"), (1, "بقيت صلاة واحدة"), (2, "بقيت صلاتان"), (3, "بقيت ٣ صلوات")]
        for (count, expected) in remaining { XCTAssertEqual(plain(PrayerCopy.remaining(count, digits: hindi)), expected) }
        let owed: [(Int, String)] = [(1, "فائتة عليك، لم تُقضَ بعد"), (2, "فائتتان عليك، لم تُقضيا بعد"), (3, "فوائت عليك، لم تُقضَ بعد"), (12, "فائتةً عليك، لم تُقضَ بعد")]
        for (count, expected) in owed { XCTAssertEqual(PrayerCopy.owed(count), expected) }
        XCTAssertEqual(plain(PrayerCopy.rakaat(8, digits: hindi)), "٨ ركعات")
        XCTAssertEqual(plain(PrayerCopy.rakaat(2, digits: hindi)), "ركعتان")
        XCTAssertEqual(plain(PrayerCopy.pending(3, digits: hindi)), "٣ صلوات لم تُسجَّل")
    }

    func test_M1V01_CountdownWordsAndTwoFieldFormat() {
        XCTAssertEqual(plain(PrayerCopy.after(seconds: 74 * 60, digits: hindi)), "بعد ساعة و١٤ دقيقة")
        XCTAssertEqual(plain(PrayerCopy.after(seconds: 120 * 60, digits: hindi)), "بعد ساعتين")
        XCTAssertEqual(plain(PrayerCopy.after(seconds: 40 * 60, digits: hindi)), "بعد ٤٠ دقيقة")
        XCTAssertEqual(plain(PrayerCopy.after(seconds: 3 * 3600 + 120, digits: hindi)), "بعد ٣ ساعات ودقيقتين")
        let now = Date(timeIntervalSince1970: 0)
        // RL7: two fields, never seconds.
        XCTAssertEqual(PrayerCopy.countdown(until: now.addingTimeInterval(74 * 60), now: now, digits: hindi), "بعد ١:١٤")
        XCTAssertEqual(PrayerCopy.countdown(until: now.addingTimeInterval(65 * 60), now: now, digits: hindi), "بعد ١:٠٥")
        XCTAssertNil(PrayerCopy.countdown(until: now, now: now, digits: hindi))
    }
}
