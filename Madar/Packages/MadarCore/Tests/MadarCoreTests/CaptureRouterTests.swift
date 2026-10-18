import Testing
@testable import MadarCore

/// Expected routes come from §9 «الالتقاط الواحد» (its three examples, routing before M5/M6)
/// and §16 («لا معامل لميزة غير v1»), never from the router's own output.
@Suite struct CaptureRouterTests {
    @Test func spokenPrayerReportLogsThePrayer() {
        // §9: «صليت العصر جماعة» ← الصلاة.
        #expect(CaptureRouter.route("صليت العصر جماعة") == .logPrayer(prayer: .asr, status: "jamaah", shortened: nil, fridayKind: nil))
        #expect(CaptureRouter.route("صلّيتُ العصرَ جماعةً") == .logPrayer(prayer: .asr, status: "jamaah", shortened: nil, fridayKind: nil))
        #expect(CaptureRouter.route("صليت الفجر في المسجد") == .logPrayer(prayer: .fajr, status: "jamaah", shortened: nil, fridayKind: nil))
        #expect(CaptureRouter.route("صليت العشاء وحدي") == .logPrayer(prayer: .isha, status: "alone", shortened: nil, fridayKind: nil))
        #expect(CaptureRouter.route("صليت الظهر قصرا وحدي") == .logPrayer(prayer: .dhuhr, status: "alone", shortened: true, fridayKind: nil))
    }

    @Test func jumuahIsCongregationalAndNeverShortened() {
        #expect(CaptureRouter.route("صليت الجمعة") == .logPrayer(prayer: .dhuhr, status: "jamaah", shortened: nil, fridayKind: .jumuah))
        #expect(CaptureRouter.route("صليت الجمعة وحدي") == .diaryLine(text: "صليت الجمعة وحدي", kind: .line))
    }

    @Test func prayerWithoutAStateIsNeverGuessed() {
        #expect(CaptureRouter.route("صليت المغرب") == .choosePrayerStatus(prayer: .maghrib, fridayKind: nil))
        #expect(CaptureRouter.route("صليت العصر الحمد لله") == .choosePrayerStatus(prayer: .asr, fridayKind: nil))
    }

    @Test func richerSentencesAndContradictionsStayDiaryLines() {
        #expect(CaptureRouter.route("صليت العصر جماعة مع أبي") == .diaryLine(text: "صليت العصر جماعة مع أبي", kind: .line))
        #expect(CaptureRouter.route("صليت العصر جماعة وحدي") == .diaryLine(text: "صليت العصر جماعة وحدي", kind: .line))
        // Fajr and Maghrib are never shortened (same rule as prayer.log).
        #expect(CaptureRouter.route("صليت المغرب قصرا جماعة") == .diaryLine(text: "صليت المغرب قصرا جماعة", kind: .line))
    }

    @Test func moneyOpensItsRoomAndMihbaraIdeasLeaveTheDiary() {
        // §9: «قهوة ١٨» goes to Money and, once M6 is built, «فكرة:» goes to Mihbara.
        #expect(CaptureRouter.route("قهوة ١٨") == .moneyExpense(amount: "١٨", merchant: "قهوة"))
        #expect(CaptureRouter.route("مصروف: مكتبة الحي ١٨٫٥٠") == .moneyExpense(amount: "١٨٫٥٠", merchant: "مكتبة الحي"))
        #expect(CaptureRouter.route("قرأت صفحة ١٨") == .diaryLine(text: "قرأت صفحة ١٨", kind: .line))
        #expect(CaptureRouter.route("  فكرة: كتاب عن الجيران ") == .mihbaraIdea(text: "كتاب عن الجيران"))
        #expect(CaptureRouter.route("فِكرة : عنوانٌ مهم") == .mihbaraIdea(text: "عنوانٌ مهم"))
        #expect(CaptureRouter.route("فكرة:") == .empty)
        #expect(CaptureRouter.route("اتصلت بخالتي") == .diaryLine(text: "اتصلت بخالتي", kind: .line))
    }

    @Test func emptyAndOversizeTextAreRefused() {
        #expect(CaptureRouter.route(" \n ") == .empty)
        #expect(CaptureRouter.route(String(repeating: "ا", count: 2001)) == .tooLong)
        #expect(CaptureRouter.route(String(repeating: "ا", count: 2000)) == .diaryLine(text: String(repeating: "ا", count: 2000), kind: .line))
    }
}
