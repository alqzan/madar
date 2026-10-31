import XCTest
import MadarQuran
import MadarCommands
@testable import Madar

@MainActor
final class QuranWirdReferenceIntegrationTests: XCTestCase {
    func testExternalSearchUsesNormalizedVerseOpeningWithoutMushafEndGlyph() throws {
        let catalog = try QuranResources.catalog()
        let ayah = try XCTUnwrap(catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 1 })

        XCTAssertTrue(ayah.uthmaniText.contains("ﰀ"), "The regression fixture includes the printed ayah-end glyph.")
        XCTAssertEqual(ayah.searchText, "الم")

        let url = try XCTUnwrap(QuranWirdReferenceSearch.url(for: ayah))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.host, "shamela.ws")
        XCTAssertEqual(components.path, "/search")
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value, "\"الم\"")
        XCTAssertFalse(url.absoluteString.contains("ﰀ"))
    }

    func testExternalSearchIsLimitedToTheFirstTwelveNormalizedWords() throws {
        let catalog = try QuranResources.catalog()
        let ayah = try XCTUnwrap(catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 255 })
        let phrase = try XCTUnwrap(URLComponents(url: XCTUnwrap(QuranWirdReferenceSearch.url(for: ayah)), resolvingAgainstBaseURL: false))
            .queryItems?.first(where: { $0.name == "q" })?.value
        let words = try XCTUnwrap(phrase).trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            .split(whereSeparator: \.isWhitespace)

        XCTAssertEqual(words.count, QuranWirdReferenceSearch.wordLimit)
        XCTAssertEqual(words.joined(separator: " "), ayah.searchText.split(whereSeparator: \.isWhitespace).prefix(QuranWirdReferenceSearch.wordLimit).joined(separator: " "))
    }

    func testCuratedExcerptsMapToTheirExactVersesAndVerifiedCitations() throws {
        let catalog = try QuranResources.catalog()
        let expected: [(id: String, surah: Int, number: Int, kind: QuranWirdReferenceKind, quote: String, citation: String, url: String)] = [
            ("tabari-1-2", 1, 2, .tafsir, "الشكرُ للَّهِ خالصًا دونَ سائرِ ما يُعْبَدُ مِن دونِه", "١/ ١٣٥", "https://shamela.ws/book/7798/315"),
            ("qurtubi-1-3-in-ibn-kathir", 1, 3, .tafsir, "ليكون من باب قرن الترغيب بعد الترهيب", "١/ ٢٠٢", "https://shamela.ws/book/1503/257"),
            ("ibn-kathir-1-4", 1, 4, .tafsir, "وكلاهما صحيح متواتر في السبع", "١/ ٢٠٢", "https://shamela.ws/book/1503/257"),
            ("ibn-kathir-1-5", 1, 5, .tafsir, "وفي الشرع عبارة عما يجمع كمال المحبة والخضوع والخوف", "١/ ٢٠٥", "https://shamela.ws/book/1503/260"),
            ("saadi-2-183", 2, 183, .tafsir, "فإن الصيام من أكبر أسباب التقوى", "ص ٨٦", "https://shamela.ws/book/42/123"),
            ("ibn-kathir-2-184", 2, 184, .tafsir, "لئلا يشق على النفوس", "٢/ ٥٣", "https://shamela.ws/book/1503/758"),
            ("ibn-kathir-2-185", 2, 185, .tafsir, "يمدح تعالى شهر الصيام من بين سائر الشهور بأن اختاره من بينهن لإنزال القرآن العظيم", "٢/ ٥٧", "https://shamela.ws/book/1503/762"),
            ("ibn-ashur-2-186", 2, 186, .tafsir, "وَجُعِلَ هَذَا الْخَيْرُ مُرَتَّبًا عَلَى تَقْدِيرِ سُؤَالِهِمْ", "٢/ ١٧٨", "https://shamela.ws/book/9776/945"),
            ("ibn-kathir-2-187", 2, 187, .tafsir, "هذه رخصة من الله تعالى للمسلمين، ورفع لما كان عليه الأمر في ابتداء الإسلام…", "٢/ ٦٧", "https://shamela.ws/book/1503/772"),
            ("bukhari-2-187", 2, 187, .asbab, "فَلَمَّا انْتَصَفَ النَّهَارُ غُشِيَ عَلَيْهِ، فَذُكِرَ ذَلِكَ لِلنَّبِيِّ ﷺ فَنَزَلَتْ هَذِهِ الْآيَةُ…", "٢/ ٦٧٦", "https://shamela.ws/book/735/3072"),
            ("maathur-2-188", 2, 188, .asbab, "وأراد امرؤُ القيس أن يحلف؛ ففيه نزلت: ﴿ولا تأكلوا أموالكم بينكم بالباطل﴾", "٣/ ٤٢٣", "https://shamela.ws/book/639/1698"),
            ("ibn-kathir-2-188", 2, 188, .tafsir, "أي: تعلمون بطلان ما تدعونه وتروجونه في كلامكم…", "٢/ ٧٩", "https://shamela.ws/book/1503/784"),
            ("saadi-2-189", 2, 189, .context, "فلو كان الحساب بالسنة الشمسية، لم يعرفه إلا النادر من الناس", "ص ٨٨", "https://shamela.ws/book/42/127"),
            ("ibn-kathir-2-255", 2, 255, .tafsir, "هذه آية الكرسي، ولها شأن عظيم", "٢/ ٢٣٩", "https://shamela.ws/book/1503/944"),
            ("saadi-2-286", 2, 286, .tafsir, "بل هي غذاء للأرواح ودواء للأبدان", "ص ١٢٠", "https://shamela.ws/book/42/195"),
            ("saadi-3-190", 3, 190, .tafsir, "وخص الله بالآيات أولي الألباب، وهم أهل العقول؛ لأنهم هم المنتفعون بها، الناظرون إليها بعقولهم لا بأبصارهم.", "ص ١٦١", "https://shamela.ws/book/42/284"),
            ("maathur-3-190-context", 3, 190, .context, "ولِمَ لا أفعل وقد أنزل علي هذه الليلة", "٥/ ٧٦٢", "https://shamela.ws/book/639/3482"),
        ]

        XCTAssertEqual(QuranWirdReferenceExcerpt.verified.count, expected.count)
        for item in expected {
            let excerpt = try XCTUnwrap(QuranWirdReferenceExcerpt.verified.first { $0.id == item.id })
            let ayah = try XCTUnwrap(catalog.ayah(id: excerpt.ayahID))
            XCTAssertEqual(ayah.surahID, item.surah, item.id)
            XCTAssertEqual(ayah.ayahNumber, item.number, item.id)
            XCTAssertEqual(excerpt.kind, item.kind, item.id)
            XCTAssertEqual(excerpt.text, item.quote, item.id)
            XCTAssertEqual(excerpt.citation, item.citation, item.id)
            XCTAssertEqual(excerpt.sourceURL.absoluteString, item.url, item.id)
        }
        let qurtubi = try XCTUnwrap(QuranWirdReferenceExcerpt.verified.first { $0.id == "qurtubi-1-3-in-ibn-kathir" })
        XCTAssertEqual(qurtubi.author, "القرطبي (نقلًا عن ابن كثير)")
        XCTAssertTrue(qurtubi.sourceNote?.contains("ينقل ابن كثير") == true)
        let qiraat = try XCTUnwrap(QuranWirdReferenceExcerpt.verified.first { $0.id == "ibn-kathir-1-4" })
        XCTAssertTrue(qiraat.sourceNote?.contains("مَلِكِ") == true && qiraat.sourceNote?.contains("مَالِكِ") == true)
        let context = try XCTUnwrap(QuranWirdReferenceExcerpt.verified.first { $0.id == "maathur-3-190-context" })
        XCTAssertTrue(context.sourceNote?.contains("لا يذكر حادثةً سبقت نزولها") == true)
    }
}
