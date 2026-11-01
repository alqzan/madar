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

    func testExternalSearchForUncoveredWirdAyahUsesItsExactNormalizedOpening() throws {
        let catalog = try QuranResources.catalog()
        let ayah = try XCTUnwrap(catalog.ayahs.first { $0.surahID == 2 && $0.ayahNumber == 177 })
        XCTAssertEqual(ayah.id, 184)
        XCTAssertEqual(ayah.searchText, "ليس البر أن تولوا وجوهكم قبل المشرق والمغرب ولكن البر من آمن بالله واليوم الآخر والملائكة والكتاب والنبيين وآتى المال على حبه ذوي القربى واليتامى والمساكين وابن السبيل والسائلين وفي الرقاب وأقام الصلاة وآتى الزكاة والموفون بعهدهم إذا عاهدوا والصابرين في البأساء والضراء وحين البأس أولئك الذين صدقوا وأولئك هم المتقون")

        let url = try XCTUnwrap(QuranWirdReferenceSearch.url(for: ayah))
        let components = try XCTUnwrap(URLComponents(url: url, resolvingAgainstBaseURL: false))
        XCTAssertEqual(components.queryItems?.first(where: { $0.name == "q" })?.value,
                       "\"ليس البر أن تولوا وجوهكم قبل المشرق والمغرب ولكن البر من آمن\"")
        XCTAssertFalse(url.absoluteString.contains("ﰀ"))
    }

    func testCuratedExcerptsMapToTheirExactVersesAndVerifiedCitations() throws {
        let catalog = try QuranResources.catalog()
        let expected: [(id: String, surah: Int, number: Int, kind: QuranWirdReferenceKind, quote: String, citation: String, url: String)] = [
            ("tabari-1-2", 1, 2, .tafsir, "الشكرُ للَّهِ خالصًا دونَ سائرِ ما يُعْبَدُ مِن دونِه", "١/ ١٣٥", "https://shamela.ws/book/7798/315"),
            ("saadi-1-2", 1, 2, .tafsir, "الثناء على الله بصفات الكمال، وبأفعاله الدائرة بين الفضل والعدل", "ص ٣٩", "https://shamela.ws/book/42/30"),
            ("qurtubi-1-3-in-ibn-kathir", 1, 3, .tafsir, "ليكون من باب قرن الترغيب بعد الترهيب", "١/ ٢٠٢", "https://shamela.ws/book/1503/257"),
            ("ibn-kathir-1-4", 1, 4, .tafsir, "وكلاهما صحيح متواتر في السبع", "١/ ٢٠٢", "https://shamela.ws/book/1503/257"),
            ("saadi-1-4", 1, 4, .tafsir, "من آثارها أنه يأمر وينهى، ويثيب ويعاقب", "ص ٣٩", "https://shamela.ws/book/42/30"),
            ("saadi-1-5", 1, 5, .tafsir, "لأن تقديم المعمول يفيد الحصر، وهو إثبات الحكم للمذكور، ونفيه عما عداه", "ص ٣٩", "https://shamela.ws/book/42/30"),
            ("ibn-kathir-1-5", 1, 5, .tafsir, "وفي الشرع عبارة عما يجمع كمال المحبة والخضوع والخوف", "١/ ٢٠٥", "https://shamela.ws/book/1503/260"),
            ("ibn-kathir-2-178-context", 2, 178, .context, "كانت بنو النضير قد غزت قريظة في الجاهلية وقهروهم", "٢/ ٤٤", "https://shamela.ws/book/1503/749"),
            ("saadi-2-178", 2, 178, .tafsir, "إقامة للعدل والقسط بين العباد", "ص ٨٤", "https://shamela.ws/book/42/120"),
            ("tabari-2-179", 2, 179, .tafsir, "فكان لكم في حكمِي بينَكم بذلك حياةٌ", "٣/ ١٢٠", "https://shamela.ws/book/7798/1771"),
            ("saadi-2-179", 2, 179, .tafsir, "لأن من عرف أنه مقتول إذا قتل، لا يكاد يصدر منه القتل", "ص ٨٥", "https://shamela.ws/book/42/120"),
            ("tabari-2-180", 2, 180, .tafsir, "والخيرُ المالُ", "٣/ ١٢٣", "https://shamela.ws/book/7798/1774"),
            ("saadi-2-180", 2, 180, .tafsir, "بل يرتبهم على القرب والحاجة", "ص ٨٥", "https://shamela.ws/book/42/121"),
            ("tabari-2-181", 2, 181, .tafsir, "فإنما إثمُ التبديلِ على من بدَّلَ وصيَّتَه", "٣/ ١٣٩", "https://shamela.ws/book/7798/1790"),
            ("saadi-2-182", 2, 182, .tafsir, "ينبغي لمن حضر الموصي وقت الوصية بها، أن ينصحه بما هو الأحسن والأعدل", "ص ٨٥", "https://shamela.ws/book/42/122"),
            ("saadi-2-183", 2, 183, .tafsir, "فإن الصيام من أكبر أسباب التقوى", "ص ٨٦", "https://shamela.ws/book/42/123"),
            ("ibn-kathir-2-183", 2, 183, .tafsir, "فلهم فيه أسوة، وليجتهد هؤلاء في أداء هذا الفرض أكمل مما فعله أولئك", "٢/ ٥٣", "https://shamela.ws/book/1503/758"),
            ("ibn-kathir-2-184", 2, 184, .tafsir, "لئلا يشق على النفوس", "٢/ ٥٣", "https://shamela.ws/book/1503/758"),
            ("saadi-2-184", 2, 184, .tafsir, "أن يقضي أياما قصيرة باردة، عن أيام طويلة حارة كالعكس", "ص ٨٦", "https://shamela.ws/book/42/123"),
            ("ibn-kathir-2-185", 2, 185, .tafsir, "يمدح تعالى شهر الصيام من بين سائر الشهور بأن اختاره من بينهن لإنزال القرآن العظيم", "٢/ ٥٧", "https://shamela.ws/book/1503/762"),
            ("saadi-2-185", 2, 185, .tafsir, "يريد الله تعالى أن ييسر عليكم الطرق الموصلة إلى رضوانه", "ص ٨٦", "https://shamela.ws/book/42/123"),
            ("ibn-ashur-2-186", 2, 186, .tafsir, "وَجُعِلَ هَذَا الْخَيْرُ مُرَتَّبًا عَلَى تَقْدِيرِ سُؤَالِهِمْ", "٢/ ١٧٨", "https://shamela.ws/book/9776/945"),
            ("saadi-2-186", 2, 186, .tafsir, "فهو قريب أيضا من داعيه، بالإجابة", "ص ٨٧", "https://shamela.ws/book/42/124"),
            ("ibn-kathir-2-187", 2, 187, .tafsir, "هذه رخصة من الله تعالى للمسلمين، ورفع لما كان عليه الأمر في ابتداء الإسلام…", "٢/ ٦٧", "https://shamela.ws/book/1503/772"),
            ("bukhari-2-187", 2, 187, .asbab, "فَلَمَّا انْتَصَفَ النَّهَارُ غُشِيَ عَلَيْهِ، فَذُكِرَ ذَلِكَ لِلنَّبِيِّ ﷺ فَنَزَلَتْ هَذِهِ الْآيَةُ…", "٢/ ٦٧٦", "https://shamela.ws/book/735/3072"),
            ("maathur-2-188", 2, 188, .asbab, "وأراد امرؤُ القيس أن يحلف؛ ففيه نزلت: ﴿ولا تأكلوا أموالكم بينكم بالباطل﴾", "٣/ ٤٢٣", "https://shamela.ws/book/639/1698"),
            ("ibn-kathir-2-188", 2, 188, .tafsir, "أي: تعلمون بطلان ما تدعونه وتروجونه في كلامكم…", "٢/ ٧٩", "https://shamela.ws/book/1503/784"),
            ("saadi-2-189", 2, 189, .context, "فلو كان الحساب بالسنة الشمسية، لم يعرفه إلا النادر من الناس", "ص ٨٨", "https://shamela.ws/book/42/127"),
            ("ibn-ashur-2-189-context", 2, 189, .context, "لأن الآيات خطاب للمسلمين وهم الذين سألوا عن الأهلة، والنسيء من أحوال أهل الجاهلية", "٢/ ١٩٩", "https://shamela.ws/book/9776/966"),
            ("saadi-2-190", 2, 190, .tafsir, "والنهي عن الاعتداء، يشمل أنواع الاعتداء كلها", "ص ٨٩", "https://shamela.ws/book/42/128"),
            ("tabari-2-191", 2, 191, .tafsir, "والشركُ باللهِ أشدُّ مِن القتلِ", "٣/ ٢٩٣", "https://shamela.ws/book/7798/1944"),
            ("ibn-kathir-2-192", 2, 192, .tafsir, "فإن تركوا القتال في الحرم وأنابوا إلى الإسلام والتوبة", "٢/ ٨٤", "https://shamela.ws/book/1503/789"),
            ("ibn-kathir-2-193", 2, 193, .tafsir, "فإن انتهوا عما هم فيه من الشرك وقتال المؤمنين فكفوا عنهم", "٢/ ٨٥", "https://shamela.ws/book/1503/790"),
            ("saadi-2-194", 2, 194, .tafsir, "هذا تفسير لصفة المقاصة، وأنها هي المماثلة في مقابلة المعتدي", "ص ٨٩", "https://shamela.ws/book/42/130"),
            ("saadi-2-195", 2, 195, .tafsir, "فالجهاد في سبيل الله لا يقوم إلا على ساق النفقة", "ص ٩٠", "https://shamela.ws/book/42/131"),
            ("saadi-2-196", 2, 196, .tafsir, "الأمر بإتقانهما وإحسانهما", "ص ٩٠", "https://shamela.ws/book/42/132"),
            ("saadi-2-197", 2, 197, .tafsir, "والمراد بالأشهر المعلومات عند جمهور العلماء: شوال، وذو القعدة، وعشر من ذي الحجة", "ص ٩١", "https://shamela.ws/book/42/133"),
            ("saadi-2-198", 2, 198, .tafsir, "ابتغاء فضل الله بالتكسب في مواسم الحج وغيره، ليس فيه حرج", "ص ٩٢", "https://shamela.ws/book/42/134"),
            ("saadi-2-199", 2, 199, .tafsir, "أمر تعالى عند الفراغ منها باستغفاره والإكثار من ذكره", "ص ٩٢", "https://shamela.ws/book/42/134"),
            ("saadi-2-200", 2, 200, .tafsir, "يسأله من مطالب الدنيا ما هو من شهواته", "ص ٩٣", "https://shamela.ws/book/42/134"),
            ("saadi-2-201", 2, 201, .tafsir, "ومنهم من يدعو الله لمصلحة الدارين، ويفتقر إليه في مهمات دينه ودنياه", "ص ٩٣", "https://shamela.ws/book/42/134"),
            ("saadi-2-202", 2, 202, .tafsir, "لهم نصيب من كسبهم وعملهم", "ص ٩٣", "https://shamela.ws/book/42/134"),
            ("saadi-2-203", 2, 203, .tafsir, "وهي أيام التشريق الثلاثة بعد العيد", "ص ٩٣", "https://shamela.ws/book/42/135"),
            ("saadi-2-204", 2, 204, .tafsir, "لأنه يخالف قوله فعله", "ص ٩٣", "https://shamela.ws/book/42/136"),
            ("saadi-2-205", 2, 205, .tafsir, "يجتهد على أعمال المعاصي، التي هي إفساد في الأرض", "ص ٩٣", "https://shamela.ws/book/42/136"),
            ("saadi-2-206", 2, 206, .tafsir, "إذا أمر بتقوى الله تكبر وأنف", "ص ٩٤", "https://shamela.ws/book/42/136"),
            ("saadi-2-208", 2, 208, .tafsir, "في جميع شرائع الدين، ولا يتركوا منها شيئا", "ص ٩٤", "https://shamela.ws/book/42/138"),
            ("saadi-2-209", 2, 209, .tafsir, "على علم ويقين", "ص ٩٤", "https://shamela.ws/book/42/138"),
            ("saadi-2-211", 2, 211, .tafsir, "كفروا بها وبدلوا نعمة الله كفرا", "ص ٩٥", "https://shamela.ws/book/42/140"),
            ("saadi-2-212", 2, 212, .tafsir, "فيخفف الله عنه بإيمانه وصبره ما لا يكون لغيره", "ص ٩٥", "https://shamela.ws/book/42/141"),
            ("saadi-2-213", 2, 213, .tafsir, "فكل ما اشتملت عليه الكتب، فهو حق", "ص ٩٥", "https://shamela.ws/book/42/142"),
            ("saadi-2-214", 2, 214, .tafsir, "الفرج عند الشدة، وكلما ضاق الأمر اتسع", "ص ٩٦", "https://shamela.ws/book/42/143"),
            ("saadi-2-215", 2, 215, .tafsir, "على حسب القرب والحاجة", "ص ٩٦", "https://shamela.ws/book/42/144"),
            ("saadi-2-219", 2, 219, .tafsir, "أكبر مما يظنونه من نفعهما", "ص ٩٨", "https://shamela.ws/book/42/148"),
            ("saadi-2-220", 2, 220, .tafsir, "إصلاح أموال اليتامى، بحفظها وصيانتها، والاتجار فيها", "ص ٩٩", "https://shamela.ws/book/42/150"),
            ("ibn-kathir-2-255", 2, 255, .tafsir, "هذه آية الكرسي، ولها شأن عظيم", "٢/ ٢٣٩", "https://shamela.ws/book/1503/944"),
            ("ibn-ashur-2-255-context", 2, 255, .context, "وَجُعِلَتْ هَذِهِ الْآيَةُ ابْتِدَاءً لِآيَاتِ تَقْرِيرِ الْوَحْدَانِيَّةِ وَالْبَعْثِ", "٣/ ١٧", "https://shamela.ws/book/9776/1273"),
            ("saadi-2-286", 2, 286, .tafsir, "بل هي غذاء للأرواح ودواء للأبدان", "ص ١٢٠", "https://shamela.ws/book/42/195"),
            ("tabari-2-286", 2, 286, .tafsir, "فلا يُضَيِّقُ عليها ولا يَجْهَدُها", "٥/ ١٥٣", "https://shamela.ws/book/7798/3270"),
            ("saadi-3-190", 3, 190, .tafsir, "وخص الله بالآيات أولي الألباب، وهم أهل العقول؛ لأنهم هم المنتفعون بها، الناظرون إليها بعقولهم لا بأبصارهم.", "ص ١٦١", "https://shamela.ws/book/42/284"),
            ("saadi-3-191", 3, 191, .tafsir, "التفكر عبادة من صفات أولياء الله العارفين", "ص ١٦١", "https://shamela.ws/book/42/284"),
            ("saadi-3-192", 3, 192, .tafsir, "لحصوله على السخط من الله، ومن ملائكته، وأوليائه", "ص ١٦١", "https://shamela.ws/book/42/284"),
            ("saadi-3-193", 3, 193, .tafsir, "أجبناه مبادرة، وسارعنا إليه", "ص ١٦١", "https://shamela.ws/book/42/284"),
            ("saadi-3-194", 3, 194, .tafsir, "سألوه الثواب على ذلك", "ص ١٦١", "https://shamela.ws/book/42/284"),
            ("saadi-3-195", 3, 195, .tafsir, "الجميع سيلقون ثواب أعمالهم كاملا موفرا", "ص ١٦٢", "https://shamela.ws/book/42/285"),
            ("saadi-3-198", 3, 198, .tafsir, "فأثابهم البر الرحيم من بره أجرا عظيما", "ص ١٦٢", "https://shamela.ws/book/42/286"),
            ("saadi-3-199", 3, 199, .tafsir, "طائفة موفقة للخير", "ص ١٦٢", "https://shamela.ws/book/42/287"),
            ("saadi-3-200", 3, 200, .tafsir, "الطريق الموصل إلى ذلك لزوم الصبر", "ص ١٦٢", "https://shamela.ws/book/42/287"),
            ("saadi-4-36-neighbor", 4, 36, .tafsir, "كلما كان الجار أقرب بابا كان آكد حقا", "ص ١٧٧", "https://shamela.ws/book/42/316"),
            ("maathur-3-190-context", 3, 190, .context, "ولِمَ لا أفعل وقد أنزل علي هذه الليلة", "٥/ ٧٦٢", "https://shamela.ws/book/639/3482"),
        ]

        XCTAssertEqual(QuranWirdReferenceExcerpt.verified.count, expected.count)
        XCTAssertEqual(Set(QuranWirdReferenceExcerpt.verified.map(\.id)).count, expected.count, "Every excerpt needs a unique accessibility and ForEach identity.")
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
        let qisasContext = try XCTUnwrap(QuranWirdReferenceExcerpt.verified.first { $0.id == "ibn-kathir-2-178-context" })
        XCTAssertTrue(qisasContext.sourceNote?.contains("لا يصوغه خبرًا صريحًا عن سبب النزول") == true)
    }
}
