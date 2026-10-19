import Foundation
import Testing
@testable import MadarMoney

/// M5-E03: parser classes (RM6) and dedupe (F08 + RM8), card identity and statements (F07).
/// Every message here is synthetic, written from the spec's class list; no real bank message was read.
/// The ≥95% accuracy target (RM6) waits for the owner's anonymised corpus.
@Suite struct BankMessageTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    static let samples: [(text: String, kind: BankMessageKind)] = [
        ("شراء عبر مدى\nبطاقة: 1111*\nمبلغ: 42.00 SAR\nلدى: مطعم الريف\nفي: 2026-10-15 13:05", .purchase),
        ("شراء Apple Pay\nمدى *2222\nبـ ١٨٫٥٠ ر.س\nلدى: Coffee Corner\n15/10/26 08:10", .purchase),
        ("شراء بطاقة ائتمانية *3333\nمبلغ: USD 12.34\nلدى: STORE ONLINE\n2026-10-15 22:40", .purchase),
        ("سحب صراف\nمن: 4444*\nمبلغ: 500 SAR\n2026-10-14 19:00", .withdrawal),
        ("حوالة صادرة\nمن: 5555*\nإلى: سالم\nمبلغ: 300.00 SAR\nالرصيد: 9,700.00 SAR", .transferOut),
        ("حوالة واردة\nإلى: 6666*\nمن: سالم\nمبلغ: 120 SAR", .transferIn),
        ("إيداع راتب\nإلى: 5555*\nمبلغ: 15,000.00 SAR\n2026-10-27 02:10", .salary),
        ("إيداع\nإلى: 5555*\nمبلغ: 800 SAR", .income),
        ("سداد بطاقة ائتمانية *3333\nمبلغ: 700 SAR", .cardPayment),
        ("كشف حساب البطاقة *3333\nالمبلغ المستحق: 6,800.00 SAR\nالحد الأدنى: 340.00 SAR\nتاريخ الاستحقاق: 2026-11-05", .statement),
        ("استرداد مبلغ\nبطاقة *3333\nمبلغ: 40 SAR\nمن: STORE ONLINE", .refund),
        ("استرداد نقدي\nبطاقة مدى *3333\nمبلغ: 35 SAR\n2026-10-15 14:00", .cashback),
        ("عملية مرفوضة\nبطاقة *1111\nمبلغ: 90 SAR\nالسبب: رصيد غير كاف", .declined),
        ("عكس عملية\nبطاقة *1111\nمبلغ: 90 SAR", .reversal),
        ("سداد فاتورة\nالمفوتر: شركة الكهرباء\nمبلغ: 410 SAR\nمن: 5555*", .billPayment),
        ("رسوم إصدار كشف\nمبلغ: 25 SAR\nحساب: 5555*", .fee),
        ("تمارا: تم خصم القسط ٤٠٫٠٠ ر.س من بطاقتك *1111", .bnplInstalment),
        ("Tabby: instalment of SAR 40.00 was paid", .bnplInstalment),
        ("رمز التحقق: 482913 لا تشاركه مع أحد", .otp),
        ("عرض خاص! خصم حصري على البطاقات. لإلغاء الاشتراك أرسل 1", .marketing),
        ("مرحبًا بك في خدماتنا", .unknown),
    ]

    @Test func everyClassInTheRM6ListIsRecognised() {
        for sample in Self.samples { #expect(BankMessageParser.classify(sample.text) == sample.kind, "\(sample.text)") }
        // The sample set covers every class.
        #expect(Set(Self.samples.map(\.kind)) == Set(BankMessageKind.allCases))
    }

    @Test func madaAndApplePayAreDebitAndCreditIsCredit() {
        let mada = BankMessageParser.parse(Self.samples[0].text, timeZone: riyadh)
        #expect(mada.cardKind == .debit)
        #expect(mada.amountMinor == 4_200)
        #expect(mada.merchant == "مطعم الريف")
        #expect(mada.last4 == "1111")
        let applePay = BankMessageParser.parse(Self.samples[1].text, timeZone: riyadh)
        // Arabic-Indic digits and «٫»: 18.50 SAR → 1850.
        #expect(applePay.amountMinor == 1_850)
        #expect(applePay.cardKind == .debit)
        #expect(applePay.kind == .purchase)
        let credit = BankMessageParser.parse(Self.samples[2].text, timeZone: riyadh)
        #expect(credit.cardKind == .credit)
        #expect(credit.currency == "USD")
        #expect(credit.amountMinor == 1_234)
        let cashback = BankMessageParser.parse(Self.samples[11].text, timeZone: riyadh)
        #expect(cashback.kind == .cashback)
        #expect(cashback.cardKind == .debit)
        #expect(cashback.last4 == "3333")
    }

    @Test func eventAtComesFromTheTextWhenItCarriesATime() {
        #expect(BankMessageParser.parse(Self.samples[0].text, timeZone: riyadh).eventAt == at(2026, 10, 15, 13, 5))
        #expect(BankMessageParser.parse(Self.samples[1].text, timeZone: riyadh).eventAt == at(2026, 10, 15, 8, 10))
        // A salary at 02:10, before Fajr: the time printed is kept (RM9: the cycle starts at this instant).
        #expect(BankMessageParser.parse(Self.samples[6].text, timeZone: riyadh).eventAt == at(2026, 10, 27, 2, 10))
        #expect(BankMessageParser.parse(Self.samples[7].text, timeZone: riyadh).eventAt == nil)
    }

    @Test func statementKeepsDueMinimumAndDueDate() {
        let s = BankMessageParser.parse(Self.samples[9].text, timeZone: riyadh)
        #expect(s.statementDueMinor == 680_000)
        #expect(s.minimumDueMinor == 34_000)
        #expect(s.dueDate == at(2026, 11, 5, 12, 0))
    }

    @Test func amountIsTheMovementNotTheBalance() {
        let s = BankMessageParser.parse(Self.samples[4].text, timeZone: riyadh)
        #expect(s.amountMinor == 30_000)
        #expect(s.balanceMinor == 970_000)
        #expect(s.counterparty == "سالم")
    }

    @Test func salaryThousandsAndBillerAndProvider() {
        #expect(BankMessageParser.parse(Self.samples[6].text, timeZone: riyadh).amountMinor == 1_500_000)
        #expect(BankMessageParser.parse(Self.samples[14].text, timeZone: riyadh).biller == "شركة الكهرباء")
        #expect(BankMessageParser.parse(Self.samples[16].text, timeZone: riyadh).provider == "Tamara")
        #expect(BankMessageParser.parse(Self.samples[16].text, timeZone: riyadh).amountMinor == 4_000)
        #expect(BankMessageParser.parse(Self.samples[17].text, timeZone: riyadh).provider == "Tabby")
    }

    @Test func otpTextIsNeverKeptAndMarketingIsDropped() {
        #expect(BankIntake.decision(.otp) == .discardWithoutText)
        #expect(BankIntake.decision(.marketing) == .discard)
        #expect(BankIntake.decision(.unknown) == .needsLook)
        #expect(BankIntake.decision(.purchase) == .record)
        // The parser reads nothing out of an OTP message.
        let otp = BankMessageParser.parse(Self.samples[18].text, timeZone: riyadh)
        #expect(otp == ParsedBankMessage(kind: .otp))
    }

    @Test func minorUnitsFollowTheCurrencyExponent() {
        #expect(BankMessageParser.minorUnits("1500", exponent: 0) == 1_500)
        #expect(BankMessageParser.minorUnits("1.250", exponent: 3) == 1_250)
        #expect(BankMessageParser.minorUnits("12.5", exponent: 2) == 1_250)
        #expect(BankMessageParser.minorUnits("12.345", exponent: 2) == nil)
    }

    // MARK: Dedupe (F08 + RM8)

    @Test func rm8FingerprintIgnoresWhenTheMessageArrivedAndSpacing() {
        let a = BankDedupe.fingerprint(sender: "BANK", text: "شراء  42.00 SAR\nلدى: X")
        let b = BankDedupe.fingerprint(sender: "bank", text: "شراء ٤٢٫٠٠ SAR لدى: X")
        #expect(a == b)
        #expect(a.count == 64)
    }

    @Test func shortcutThenPasteIsOneRow() {
        // A text with its own time: pasted after the Shortcut stored it → nothing new.
        let fp = BankDedupe.fingerprint(sender: "BANK", text: Self.samples[0].text), t = at(2026, 10, 15, 13, 5)
        guard case .insert(let occ, false) = BankDedupe.live(fp, at: t, existing: []) else { Issue.record("live should insert"); return }
        let stored = [BankDedupe.Stored(key: .init(fingerprint: fp, occurrence: occ), at: t)]
        #expect(BankDedupe.bulk([.init(fingerprint: fp, hasOwnTime: true, at: t)], existing: stored) == [.alreadyThere])
    }

    @Test func pastedFileWithTwoIdenticalPurchasesTwiceIsTwoRowsNotFour() {
        let fp = BankDedupe.fingerprint(sender: "BANK", text: "شراء 15 SAR لدى: كافتيريا 2026-10-15 09:00"), t = at(2026, 10, 15, 9, 0)
        var stored: [BankDedupe.Stored] = []
        for _ in 0..<2 {
            for placement in BankDedupe.bulk([.init(fingerprint: fp, hasOwnTime: true, at: t), .init(fingerprint: fp, hasOwnTime: true, at: t)], existing: stored) {
                if case .insert(let occ, _) = placement { stored.append(.init(key: .init(fingerprint: fp, occurrence: occ), at: t)) }
            }
        }
        #expect(stored.count == 2)
    }

    @Test func timelessPastedMessageIsPreviewedNearbyAndNeverSkipped() {
        // Review fix: RM8 removed the time from the fingerprint, so a timeless coffee on the 3rd and another on the 20th
        // share it. The paste must not drop the second; within ±3 days it asks «قد تكون موجودة».
        let fp = BankDedupe.fingerprint(sender: "BANK", text: "شراء 15 SAR لدى: كافتيريا")
        let stored = [BankDedupe.Stored(key: .init(fingerprint: fp, occurrence: 1), at: at(2026, 10, 3, 9, 0))]
        #expect(BankDedupe.bulk([.init(fingerprint: fp, hasOwnTime: false, at: at(2026, 10, 20, 9, 0))], existing: stored) == [.insert(occurrence: 2, possibleDuplicate: false)])
        #expect(BankDedupe.bulk([.init(fingerprint: fp, hasOwnTime: false, at: at(2026, 10, 4, 18, 0))], existing: stored) == [.mayExist(occurrence: 2)])
    }

    @Test func twoIdenticalShortcutMessagesAreTwoRowsAndTheSecondIsFlagged() {
        let fp = BankDedupe.fingerprint(sender: "BANK", text: "شراء 15 SAR لدى: كافتيريا"), t = at(2026, 10, 15, 9, 0)
        #expect(BankDedupe.live(fp, at: t, existing: []) == .insert(occurrence: 1, possibleDuplicate: false))
        let first = [BankDedupe.Stored(key: .init(fingerprint: fp, occurrence: 1), at: t)]
        #expect(BankDedupe.live(fp, at: t.addingTimeInterval(30), existing: first) == .insert(occurrence: 2, possibleDuplicate: true))
        // The same timeless text the next day is a new purchase, not a question.
        #expect(BankDedupe.live(fp, at: t.addingTimeInterval(86_400), existing: first) == .insert(occurrence: 2, possibleDuplicate: false))
    }

    @Test func transferThatMentionsItsFeeIsStillTheTransfer() {
        let text = "حوالة صادرة\nمن: 5555*\nإلى: سالم\nمبلغ: 300.00 SAR\nالرسوم: 0.50 SAR"
        #expect(BankMessageParser.classify(text) == .transferOut)
        #expect(BankMessageParser.parse(text, timeZone: riyadh).amountMinor == 30_000)
    }

    @Test func rm8NearDuplicateAsksWithinTenMinutes() {
        let t = at(2026, 10, 15, 13, 5)
        let old = BankDedupe.Movement(accountKey: "1111", amountMinor: 4_200, merchant: "مطعم الريف", at: t, fingerprint: "a")
        #expect(BankDedupe.nearDuplicate(.init(accountKey: "1111", amountMinor: 4_200, merchant: "مطعم الريف", at: t.addingTimeInterval(60), fingerprint: "b"), among: [old]))
        #expect(!BankDedupe.nearDuplicate(.init(accountKey: "1111", amountMinor: 4_200, merchant: "مطعم الريف", at: t.addingTimeInterval(11 * 60), fingerprint: "b"), among: [old]))
        #expect(!BankDedupe.nearDuplicate(.init(accountKey: "1111", amountMinor: 4_300, merchant: "مطعم الريف", at: t, fingerprint: "b"), among: [old]))
    }

    // MARK: F07

    @Test func unknownLast4AsksInsteadOfCreatingACard() {
        let cards = [CardStatements.KnownCard(id: "c1", bank: "BANK", last4: "3333", aliases: ["BANK-CC"])]
        #expect(CardStatements.identify(sender: "bank-cc", last4: "3333", cards: cards) == .known("c1"))
        #expect(CardStatements.identify(sender: "BANK", last4: "9999", cards: cards) == .newCardQuestion)
    }

    @Test func secondStatementNearAnEstimatedCloseIsTheSameOrAsked() {
        let close = at(2026, 10, 20, 12, 0)
        let stored = [CardStatements.StoredStatement(closeDate: close, statementMinor: 680_000, estimated: true)]
        #expect(CardStatements.place(closeDate: close.addingTimeInterval(3 * 86_400), statementMinor: 680_000, existing: stored) == .sameStatement(index: 0))
        #expect(CardStatements.place(closeDate: close.addingTimeInterval(3 * 86_400), statementMinor: 690_000, existing: stored) == .needsLook(index: 0))
        #expect(CardStatements.place(closeDate: close.addingTimeInterval(25 * 86_400), statementMinor: 680_000, existing: stored) == .new)
    }

    @Test func nextCloseIsPredictedAfterTwoStatementsOnTheSameDay() {
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        #expect(CardStatements.predictNextClose([at(2026, 8, 20, 12, 0), at(2026, 9, 20, 12, 0)], calendar: c) == at(2026, 10, 20, 12, 0))
        #expect(CardStatements.predictNextClose([at(2026, 9, 20, 12, 0)], calendar: c) == nil)
    }
}

/// RM6 corpus shapes (19 Oct): layouts seen in the owner's local messages, rewritten with invented merchants and numbers.
@Suite struct BankMessageShapeTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    @Test func bsfMerchantOnItsOwnLineAfterMin() {
        let p = BankMessageParser.parse("شراء عبر نقاط البيع بـ SAR 23.50 \nرسوم العملية:0.00 \nمن Sample Cafe\nبطاقة مدى 7788\nفي 15/10/26 08:10", timeZone: riyadh)
        #expect(p.kind == .purchase); #expect(p.amountMinor == 2350); #expect(p.merchant == "Sample Cafe")
    }
    @Test func alinmaMerchantAfterMinWithColonNotTheAccount() {
        let p = BankMessageParser.parse("شراء عبر نقاط البيع\nعبر تطبيق: Apple Pay\nمبلغ: 45 SAR\nبطاقة مدى: 1234*\nحساب: **9876\nمن: Test Bakery\nفي: 15/10/26 09:00", timeZone: riyadh)
        #expect(p.merchant == "Test Bakery"); #expect(p.last4 == "1234"); #expect(p.amountMinor == 4500)
    }
    @Test func alRajhiCardDigitsBeforeSemicolonAndLamMerchant() {
        let p = BankMessageParser.parse("شراء انترنت\nعبر:4321;مدى\nمن:5566\nبـSAR 10 \nلـSAMPLE CHARITY\n15/10/26 21:30", timeZone: riyadh)
        #expect(p.kind == .purchase); #expect(p.last4 == "4321"); #expect(p.merchant == "SAMPLE CHARITY"); #expect(p.amountMinor == 1000)
    }
    @Test func snbPosMerchantAfterMin() {
        let p = BankMessageParser.parse("شراء-POS\nبـ120.00 SAR\nمن Fuel Station 3\nإئتمانية **2468 (Apple Pay)\nفي 15/10/26 07:45", timeZone: riyadh)
        #expect(p.merchant == "Fuel Station 3"); #expect(p.last4 == "2468"); #expect(p.cardKind == .credit)
    }
}
