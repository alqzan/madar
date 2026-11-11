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

    @Test func aPurchaseWhoseDigitsSitInsideTheBalanceKeepsItsAmount() {
        // «50.00 SAR» is a substring of «150.00 SAR»; the balance is excluded by position, not by text.
        let lines = BankMessageParser.parse("شراء عبر مدى\nبطاقة: 1111*\nمبلغ: 50.00 SAR\nلدى: مطعم الريف\nالرصيد: 150.00 SAR", timeZone: riyadh)
        #expect(lines.amountMinor == 5_000)
        #expect(lines.balanceMinor == 15_000)
        let oneLine = BankMessageParser.parse("شراء عبر مدى بطاقة: 1111* مبلغ: 50.00 SAR لدى: مطعم الريف الرصيد: 150.00 SAR", timeZone: riyadh)
        #expect(oneLine.amountMinor == 5_000)
    }

    @Test func gulfCurrencyNamesAreNotReadAsRiyals() {
        let exponents = CurrencyExponents.specified
        let cases: [(String, Int, String)] = [("مبلغ: 12.500 ريال عماني", 12_500, "OMR"), ("مبلغ: 40.00 ريال قطري", 4_000, "QAR"),
                                              ("مبلغ: 75.00 درهم", 7_500, "AED"), ("مبلغ: 3.250 دينار كويتي", 3_250, "KWD"),
                                              ("مبلغ: 2.500 دينار بحريني", 2_500, "BHD"), ("مبلغ: 18.50 ريال", 1_850, "SAR"),
                                              ("مبلغ: 18.50 ريال سعودي", 1_850, "SAR")]
        for (text, minor, code) in cases {
            let found = BankMessageParser.amounts(text, exponents).first
            #expect(found?.minor == minor && found?.currency == code, "\(text)")
        }
        // Extra spaces between the words of a name do not turn it into a plain riyal.
        let spaced = BankMessageParser.amounts("مبلغ: 12.500 ريال   عماني", exponents).first
        #expect(spaced?.minor == 12_500 && spaced?.currency == "OMR")
        // A bare «دينار» names no country: no amount is read rather than guessing one.
        #expect(BankMessageParser.amounts("مبلغ: 5.000 دينار", exponents).isEmpty)
    }

    @Test func nationalityAdjectivesPickTheirOwnCurrencyOrNone() {
        let exponents = CurrencyExponents.specified
        let cases: [(String, Int, String)] = [("مبلغ: 50.00 ريال يمني", 5_000, "YER"), ("مبلغ: 50.00 ريال إيراني", 5_000, "IRR"),
                                              ("مبلغ: 5.250 دينار أردني", 5_250, "JOD"), ("مبلغ: 5.250 دينار عراقي", 5_250, "IQD"),
                                              ("مبلغ: 5.25 دينار جزائري", 525, "DZD"), ("مبلغ: 5.250 دينار تونسي", 5_250, "TND"),
                                              ("مبلغ: 5.250 دينار ليبي", 5_250, "LYD"), ("مبلغ: 75.00 جنيه مصري", 7_500, "EGP"),
                                              ("مبلغ: 75.00 جنيه إسترليني", 7_500, "GBP"), ("مبلغ: 75.00 ليرة تركية", 7_500, "TRY"),
                                              ("مبلغ: 75.00 درهم مغربي", 7_500, "MAD"), ("مبلغ: 75.00 درهم إماراتي", 7_500, "AED"),
                                              ("مبلغ: 75.00 درهم", 7_500, "AED"), ("مبلغ: 75.00 دولار أمريكي", 7_500, "USD"),
                                              ("مبلغ: 75.00 دولار", 7_500, "USD"), ("مبلغ: 75.00 درهم   مغربي", 7_500, "MAD"),
                                              ("مبلغ: 15.00 ريال لدى مطعم", 1_500, "SAR"), ("مبلغ: 15.00 ريال في مطعم", 1_500, "SAR"),
                                              ("مبلغ: 50.00 ريال الراجحي", 5_000, "SAR"), ("مبلغ: 100.00 ريال فوري", 10_000, "SAR"),
                                              ("مبلغ: 75.00 ريال محلي", 7_500, "SAR"), ("مبلغ: 75.00 ريال دولي", 7_500, "SAR"),
                                              ("مبلغ: 75.00 ريال إضافي", 7_500, "SAR")]
        for (text, minor, code) in cases {
            let found = BankMessageParser.amounts(text, exponents).first
            #expect(found?.minor == minor && found?.currency == code, "\(text)")
        }
        // An adjective the table does not know is never dropped to the bare word's currency.
        for text in ["مبلغ: 50.00 ريال سوداني", "مبلغ: 5.00 درهم ليبي", "مبلغ: 5.00 دولار كندي", "مبلغ: 5.00 ريال   سوداني"] {
            #expect(BankMessageParser.amounts(text, exponents).isEmpty, "\(text)")
        }
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

    @Test func explicitTransferDirectionAfterAmountIsRecognised() {
        let toRecipient = BankMessageParser.parse("تحويل 235.50 ريال إلى مستفيد تجريبي", timeZone: riyadh)
        #expect(toRecipient.kind == .transferOut)
        #expect(toRecipient.amountMinor == 23_550)
        #expect(toRecipient.counterparty == "مستفيد تجريبي")

        let toRecipientWithParticle = BankMessageParser.parse("حوالة 120 ريال ل مستفيد تجريبي", timeZone: riyadh)
        #expect(toRecipientWithParticle.kind == .transferOut)
        #expect(toRecipientWithParticle.amountMinor == 12_000)
        #expect(toRecipientWithParticle.counterparty == "مستفيد تجريبي")

        let outgoingIPS = BankMessageParser.parse("Outgoing IPS local transfer from: Own account\nAmount: SAR 40.00", timeZone: riyadh)
        #expect(outgoingIPS.kind == .transferOut)
        #expect(outgoingIPS.amountMinor == 4_000)
        // The source account is not a destination/counterparty.
        #expect(outgoingIPS.counterparty == nil)
    }

    @Test func walletDebitWithoutAnEndpointIsAnOutgoingTransfer() {
        // Owner, 11 Nov: «Debit via wallet transfer» is money out of the wallet; it still goes to review like every message.
        let parsed = BankMessageParser.parse("Wallet operations\nWallet: stc pay\nDebit via wallet transfer\nAmount: SAR 45.00", timeZone: riyadh, sender: "stcpay")
        #expect(parsed.kind == .transferOut); #expect(parsed.amountMinor == 4_500); #expect(parsed.counterparty == nil)
        #expect(BankIntake.decision(parsed.kind) == .record)
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

@Suite struct BankMessageDateOrderTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    @Test func yearFirstTwoDigitDateReadsByReceiveTime() {
        let p = BankMessageParser.parse("خصم SAR 12.00 من حسابك *1234 في 25-10-19 14:30 - تحويل", timeZone: riyadh, receivedAt: at(2025, 10, 19, 14, 31))
        #expect(p.eventAt == at(2025, 10, 19, 14, 30)); #expect(p.kind == .transferOut); #expect(p.amountMinor == 1200)
    }
    @Test func dayFirstTwoDigitDateReadsByReceiveTime() {
        let p = BankMessageParser.parse("شراء عبر نقاط البيع\nبطاقة:4321;مدى\nمبلغ:30 SAR\nلدى:Sample Shop\n19-10-25 08:05", timeZone: riyadh, receivedAt: at(2025, 10, 19, 8, 6))
        #expect(p.eventAt == at(2025, 10, 19, 8, 5))
    }
    @Test func srIsRiyal() {
        #expect(BankMessageParser.parse("شراء انترنت بـSR 15.5 \nبطاقة:4321;مدى\nلـSAMPLE", timeZone: riyadh).amountMinor == 1550)
    }
}

@Suite struct CharityReceiptTests {
    @Test func charityThankYouIsDiscardedTheBankDebitRecords() {
        let receipt = "عطاؤك الدائم\nوصل تبرعك اليومي إلى المنصة\nالمبلغ: 1.00\nEhsan.sa"
        #expect(BankMessageParser.classify(receipt) == .marketing)
        #expect(BankIntake.decision(BankMessageParser.classify(receipt)) == .discard)
    }
}

@Suite struct CreditCardPaymentShapeTests {
    @Test func alRajhiCreditCardSettlementIsACardPaymentNotABill() {
        #expect(BankMessageParser.classify("بطاقة ائتمانية:سداد\nبطاقة:*1234 ;فيزا\nمبلغ:SAR 500.00\nفي:25-10-19 10:00") == .cardPayment)
        #expect(BankMessageParser.classify("سداد فاتورة\nالمفوتر: شركة الكهرباء\nمبلغ: 120 SAR") == .billPayment)
    }
}

/// Notices that move no money, from the owner's earlier My-dream analysis; texts invented.
@Suite struct NoticeShapeTests {
    @Test func holdsBillNoticesAndAccountAlertsAreNotMovements() {
        for text in ["حجز مؤقت على بطاقتك *1234 بمبلغ 50 SAR", "عزيزي المشترك، تم إصدار فاتورتك للحساب بمبلغ 120 ريال",
                     "تمت إضافة المستفيد بنجاح", "تم تسجيل الدخول إلى حسابك", "Current balance: 3.50 SAR. Recharge now"] {
            #expect(BankMessageParser.classify(text) == .marketing, "\(text)")
        }
    }
    @Test func aGreetingWithAPurchaseIsStillAPurchase() {
        #expect(BankMessageParser.classify("عزيزي العميل\nشراء عبر نقاط البيع\nمبلغ: 20 SAR\nلدى: متجر") == .purchase)
    }
}

/// The owner's special-case rules (19 Oct), with invented text and numbers.
@Suite struct OwnerSpecialRuleTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    @Test func walletTopUpIsATransferNotAPurchase() {
        #expect(BankMessageParser.parse("شراء إنترنت\nبطاقة:1234 ;فيزا\nمبلغ:200.00 SAR\nلدى:barq\nفي:19-10-2025 10:00", timeZone: riyadh, trackedWallets: ["barq"]).kind == .transferOut)
    }
    @Test func tamaraAsBankMerchantIsAPurchaseButAPlanConfirmationIsNot() {
        #expect(BankMessageParser.classify("شراء إنترنت\nبطاقة:1234 ;فيزا\nمبلغ:40.00 SAR\nلدى:Tamara") == .purchase)
        #expect(BankMessageParser.classify("تأكيد دفعة مقسمة إلى 4\nالمتجر: shop.example\nالطلب: 160.00 SAR") == .marketing)
    }
    @Test func purchaseTotalDueIsNotAStatementAndBracketRiyalIsHome() {
        let p = BankMessageParser.parse("شراء انترنت\nبطاقة:1234 ;فيزا\nمبلغ: 10 USD(37.60 ريال)\nلدى:SAMPLE\nرسوم وضريبة: 0.90 SAR\nاجمالي المبلغ المستحق: 38.50 SAR", timeZone: riyadh)
        #expect(p.kind == .purchase); #expect(p.currency == "USD"); #expect(p.statedHomeMinor == 3760)
    }
    @Test func visaSettlementSharedBillShareAndInternalTransferIn() {
        #expect(BankMessageParser.classify("بطاقة فيزا:سداد بـSR 900.00\nعبر1234;فيزا") == .cardPayment)
        #expect(BankMessageParser.classify("استلام قطة\nمبلغ:25.00 ر.س\nمن:شخص") == .refund)
        #expect(BankMessageParser.classify("حوالة داخلية\nمبلغ:SAR 500\nالى:1234\nمن:SampleWallet") == .transferIn)
    }
}

@Suite struct OwnerSenderRuleTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    @Test func telecomStcIsIgnoredButStcPayIsRead() {
        #expect(BankMessageParser.parse("تم خصم 30 ريال من رصيدك", timeZone: riyadh, sender: "stc").kind == .marketing)
        #expect(BankMessageParser.parse("مشتريات إنترنت\nمبلغ: 30 SAR\nلدى: Sample", timeZone: riyadh, sender: "stcpay").kind == .purchase)
    }
    @Test func investmentAndSavingsWalletsAreTransfers() {
        #expect(BankMessageParser.parse("شراء إنترنت\nبطاقة:1234 ;فيزا\nمبلغ:100.00 SAR\nلدى:Drahim", timeZone: riyadh, trackedWallets: ["دراهم"]).kind == .transferOut)
    }
}

/// My-dream follow-on rules, adapted to Madar's existing transfer kinds and tracked-account setting.
@Suite struct BankMessageFollowOnTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!

    @Test func addFundsPhrasesAreIncomingTransfersRatherThanIncome() {
        let messages = [
            "Money added to wallet\nAmount: 25.00 SAR",
            "Add funds to your account\nAmount: 18.00 SAR",
            "Top-up completed\nAmount: 12.50 SAR",
            "تمت إضافة أموال إلى المحفظة\nالمبلغ: 25.00 SAR",
            "تغذية محفظة\nمبلغ: 18.00 SAR"
        ]
        for text in messages {
            let parsed = BankMessageParser.parse(text, timeZone: riyadh)
            #expect(parsed.kind == .transferIn, "\(text)")
            #expect(parsed.amountMinor != nil)
        }
    }

    @Test func trackedWalletTopUpIsNeutralButUntrackedWalletTopUpRemainsSpending() {
        let text = "شراء إنترنت\nبطاقة:1234 ;فيزا\nمبلغ:200.00 SAR\nلدى:barq\nفي:2026-10-16 10:00"
        let tracked = BankMessageParser.parse(text, timeZone: riyadh, trackedWallets: ["محفظتي برق", "برق"])
        let untracked = BankMessageParser.parse(text, timeZone: riyadh)
        #expect(tracked.kind == .transferOut)
        #expect(tracked.counterparty == "barq")
        #expect(tracked.amountMinor == 20_000)
        #expect(untracked.kind == .purchase)
    }

    @Test func walletAndInvestmentCounterpartiesMatchTheirArabicAndEnglishAliases() {
        #expect(BankWalletIdentity.matches("Drahim", trackedWallets: ["دراهم"]))
        #expect(BankWalletIdentity.matches("الإنماء للاستثمار", trackedWallets: ["Alinma Investment"]))
        #expect(!BankWalletIdentity.matches("Barq Store", trackedWallets: ["Barq" ]))
    }

    @Test func knownBankSenderAliasesMatchButUnknownContactsDoNot() {
        #expect(BankMessageIdentity.matches("مصرف الراجحي", "AlRajhiBank"))
        #expect(BankMessageIdentity.matches("البنك السعودي البريطاني", "SABB"))
        #expect(!BankMessageIdentity.matches("مصرف الراجحي", "900"))
        #expect(!BankMessageIdentity.matches("مصرف الراجحي", "AlinmaBank"))

        let cards = [CardStatements.KnownCard(id: "rajhi-4321", bank: "مصرف الراجحي", last4: "4321")]
        #expect(CardStatements.identify(sender: "AlRajhiBank", last4: "4321", cards: cards) == .known("rajhi-4321"))
    }

    @Test func ownerAccountMovesAndBankSpecificLayoutsStayConservative() {
        let ownAccounts = BankMessageParser.parse("تحويل بين حساباتي\nمبلغ: 40 SAR", timeZone: riyadh)
        #expect(ownAccounts.kind == .transferOut)
        #expect(ownAccounts.counterparty == nil)

        let internalFromWallet = BankMessageParser.parse("حوالة داخلية\nمن:Drahim\nمبلغ: SAR 40", timeZone: riyadh, trackedWallets: ["Drahim"])
        #expect(internalFromWallet.kind == .transferIn)
        #expect(internalFromWallet.counterparty == "Drahim")

        let rajhiLayout = BankMessageParser.parse("شراء انترنت\nعبر:7413;مدى-ابل باي\nمن:7746\nبـSAR 5\nلـTEST DONATION\n17/1/26 06:09",
            timeZone: riyadh, receivedAt: ISO8601DateFormatter().date(from: "2026-01-17T06:09:00+03:00"), sender: "AlRajhiBank")
        #expect(rajhiLayout.kind == .purchase)
        #expect(rajhiLayout.amountMinor == 500)
        #expect(rajhiLayout.last4 == "7413")
        #expect(rajhiLayout.merchant == "TEST DONATION")

        let bsfLayout = BankMessageParser.parse("شراء عبر نقاط البيع\nلدى:TEST CAFE\nمبلغ: 39 SAR\n17/1/26 06:09",
            timeZone: riyadh, receivedAt: ISO8601DateFormatter().date(from: "2026-01-17T06:09:00+03:00"), sender: "BSF")
        #expect(bsfLayout.kind == .purchase)
        #expect(bsfLayout.amountMinor == 3_900)
        #expect(bsfLayout.merchant == "TEST CAFE")
    }
}

/// Layouts seen in a real corpus (shapes only; every merchant, name, number and amount below is invented).
@Suite struct RealCorpusLayoutTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: Layouts seen in a real corpus (shapes only; every merchant, name, number and amount below is invented)

    private func parse(_ text: String, sender: String? = nil) -> ParsedBankMessage {
        BankMessageParser.parse(text, timeZone: riyadh, receivedAt: at(2026, 10, 15, 13, 0), sender: sender,
                                trackedWallets: ["STC Pay", "STC Bank", "Sukuk", "Alinma Investment"])
    }

    @Test func tamaraDueNoticesAndPaymentConfirmationsAreInstalments() {
        let upcoming = parse("دفعة قادمة بقيمة 123.45 SAR لطلبك من متجر وهمي مستحقة خلال يومين. سددها الحين: https://tmra.pe/abc", sender: "Tamara")
        // Owner review, 11 Nov: a reminder of a payment still to come moves no money, so it is a notice that keeps its figure.
        #expect(upcoming.kind == .marketing)
        #expect(upcoming.statementDueMinor == 12_345); #expect(upcoming.amountMinor == nil)
        #expect(upcoming.provider == "Tamara")
        let today = parse("دفعتك بقيمة 80.00 SAR لطلبك من متجر وهمي مستحقة اليوم، تجنب التأثير على سجلك الائتماني وادفع الحين https://tmra.pe/abc", sender: "Tamara")
        #expect(today.kind == .marketing)
        #expect(today.statementDueMinor == 8_000); #expect(today.amountMinor == nil)
        let confirmed = parse("تأكيد الدفع\r\nمن: Example Store\r\nبقيمة: 2,347.18 SAR\r\nفي: 17/12/2025", sender: "Tamara")
        #expect(confirmed.kind == .bnplInstalment)
        #expect(confirmed.amountMinor == 234_718)
        #expect(confirmed.provider == "Tamara")
    }

    @Test func alRajhiAccountDebitsDeclinedMerchantAndTransferRecipient() {
        let sawa = parse("خصم SAR 25.00 من حسابك *1111 في 26-10-15 13:05 - مدفوعات سوا", sender: "alrajhibank")
        #expect(sawa.kind == .billPayment)
        #expect(sawa.amountMinor == 2_500)
        let bills = parse("خصم SAR 1200.50 من حسابك *1111 في 26-10-15 13:05 - فواتير", sender: "alrajhibank")
        #expect(bills.kind == .billPayment)
        #expect(bills.amountMinor == 120_050)
        let unlabelled = parse("خصم SAR 7.00 من حسابك *1111 في 26-10-15 13:05 -", sender: "alrajhibank")
        #expect(unlabelled.kind == .withdrawal)
        #expect(unlabelled.amountMinor == 700)
        #expect(unlabelled.last4 == "1111")
        let declined = parse("إشعار: عملية مرفوضة لعدم وجود رصيد كاف\nالعملية : شراء\nبطاقة : 1111\nمبلغ : 9.50 SAR\nعلى : EXAMPLE.COM\nفي :15-10-2026 13:05", sender: "alrajhibank")
        #expect(declined.kind == .declined)
        #expect(declined.merchant == "EXAMPLE.COM")
        #expect(declined.amountMinor == 950)
        let transfer = parse("تحويل SAR 60.00 للحساب *1111 26-10-15 13:05 فلان الفلاني", sender: "alrajhibank")
        #expect(transfer.kind == .transferOut)
        #expect(transfer.amountMinor == 6_000)
        #expect(transfer.counterparty == "فلان الفلاني")
    }

    @Test func stcPayDeclinedPurchaseMerchantsAndWalletOperations() {
        let declined = parse("Notification: Declined due to Insufficient balance\nTransaction: POS Purchase\nCard: ***1111\nAmount: SAR 45.25\nDate: 2026-10-15 13:05:00", sender: "stcpay")
        #expect(declined.kind == .declined)
        #expect(declined.amountMinor == 4_525)
        let declinedAbroad = parse("Notification: Declined due to Insufficient balance\nTransaction: Online Purchase\nCard: ***1111\nAmount: INR 99.00\nAt: Example Store RIYADH SA\nDate: 2026-10-15 13:05:00", sender: "stcpay")
        #expect(declinedAbroad.amountMinor == 9_900)
        #expect(declinedAbroad.merchant == "Example Store RIYADH SA")
        let online = parse("مشتريات إنترنت\nالبطاقة: ***1111؛ ApplePay\nالمبلغ: SAR 32.00\nفي: samplefood RIYADH SA\nبتاريخ: 2026-10-15 13:05:00", sender: "stcpay")
        #expect(online.kind == .purchase)
        #expect(online.merchant == "samplefood")
        let recharge = parse("عمليات محفظة\nمحفظة: stc pay\nشحن رصيد سوا\nالمبلغ: 30.00 ر.س\nبتاريخ: 2026-10-15 13:05:00", sender: "stcpay")
        #expect(recharge.kind == .billPayment)
        #expect(recharge.amountMinor == 3_000)
        let rechargeEnglish = parse("Wallet operations\nWallet name: stc pay\nsawa recharge\nAmount: SAR 30.00\nDate: 2026-10-15 13:05:00", sender: "stcpay")
        #expect(rechargeEnglish.kind == .billPayment)
    }

    @Test func snbSalaryDepositAndAutomaticSettlement() {
        let salary = parse("ايداع رواتب\nمبلغ SAR 8000\nحساب111*222\nفي 15/10/2026 13:05", sender: "snb-alahli")
        #expect(salary.kind == .income)
        #expect(salary.amountMinor == 800_000)
        let settlement = parse("تسديد آلي\nبطاقة **1111\nمبلغ 250.75 ريال\nفي 15/10 13:05\nالصرف المتبقي 4000.00 ريال", sender: "snb-alahli")
        #expect(settlement.kind == .cardPayment)
        #expect(settlement.amountMinor == 25_075)
        #expect(settlement.last4 == "1111")
    }

    @Test func sukukDepositsWithoutCurrencyAndInvestmentOperations() {
        let deposit = parse("إيداع إلى حساب استثماري\nرقم: 1111\nالمبلغ: 5,000\nفي: 15-10-2026 13:05:00", sender: "SUKUK")
        #expect(deposit.kind == .income)
        #expect(deposit.amountMinor == 500_000)
        #expect(deposit.currency == "SAR")
        let decimal = parse("إيداع إلى حساب استثماري\nرقم: 1111\nالمبلغ: 1,250.50\nفي: 15-10-2026 13:05:00", sender: "SUKUK")
        #expect(decimal.amountMinor == 125_050)
        let invest = parse("عملية استثمارية\nمن حساب: 1111\nفي: مشروع وهمي 7\nعدد: 2\nالمبلغ: SAR 2,000.00\nفي: 15-10-2026 13:05:00", sender: "SUKUK")
        #expect(invest.kind == .transferOut)
        #expect(invest.amountMinor == 200_000)
        #expect(invest.counterparty == "مشروع وهمي 7")
        let withdraw = parse("سحب من حساب استثماري\nرقم: 1111\nإلى حساب: 2222\nالمبلغ: SAR 900\nفي: 15-10-2026 13:05:00", sender: "SUKUK")
        #expect(withdraw.kind == .withdrawal)
        #expect(withdraw.amountMinor == 90_000)
    }

    @Test func stcBankSharedBillInternetOperationAndInsufficientBalanceMerchant() {
        let share = parse("دفع قطة\nمبلغ:45.00 ر.س\nإلى:EXAMPLE PERSON\nفي:15/10/26 13:05", sender: "STC_Bank")
        #expect(share.kind == .transferOut)
        #expect(share.amountMinor == 4_500)
        #expect(share.counterparty == "EXAMPLE PERSON")
        let internet = parse("عملية انترنت\nب: 150 SAR\nمن:Example Shop \nبطاقة:*1111\nفي:15/10/26 13:05", sender: "STC_Bank")
        #expect(internet.kind == .purchase)
        #expect(internet.amountMinor == 15_000)
        #expect(internet.merchant == "Example Shop")
        #expect(internet.last4 == "1111")
        let declined = parse("رصيد غير كافي\n120.00 ر.س\nFAT*Example \n15/10/26 13:05\nرصيدك 30", sender: "STC_Bank")
        #expect(declined.kind == .declined)
        #expect(declined.amountMinor == 12_000)
        #expect(declined.merchant == "FAT*Example")
    }

    @Test func alinmaIpoRefundDebitPurchaseMerchantAndInvestmentTransfer() {
        let refund = parse("تم رد فائض اكتتاب بقيمة 1,500 ريال الى الحساب **1111", sender: "alinmabank")
        #expect(refund.kind == .refund)
        #expect(refund.amountMinor == 150_000)
        let debit = parse("خصم 2000 ريال عمليات الاكتتاب من حسابك **1111 في 2026-10-15 13:05", sender: "alinmabank")
        #expect(debit.kind == .transferOut)
        #expect(debit.amountMinor == 200_000)
        #expect(debit.counterparty != nil)
        let purchase = parse("شراء 35 ريال (مدى أثير) ببطاقة 1111* من Example Mart 2026-10-15 13:05", sender: "alinmabank")
        #expect(purchase.kind == .purchase)
        #expect(purchase.amountMinor == 3_500)
        #expect(purchase.merchant == "Example Mart")
        #expect(purchase.last4 == "1111")
        let fromInvestment = parse("تحويل 400.00 ريال من الحساب الإستثماري المنتهي ب ***111 في 15-10-2026 13:05:00", sender: "alrajhicptl")
        #expect(fromInvestment.kind == .transferIn)
        #expect(fromInvestment.amountMinor == 40_000)
        #expect(fromInvestment.counterparty?.hasPrefix("الحساب") == true)
    }

    @Test func statementsTakeTheTotalDueAmount() {
        let bsf = parse("تم إصدار كشف حساب بطاقة ائتمانية 1111**\nالرصيد القائم 900.00 SAR حتى تاريخه\nالمبلغ المستحق 450.25 SAR\nتاريخ الاستحقاق 05-11-2026", sender: "BSF")
        #expect(bsf.kind == .statement)
        #expect(bsf.statementDueMinor == 45_025)
        #expect(bsf.last4 == "1111")
        let alinma = parse("إصدار كشف حساب\nتفاصيل البطاقة **1111\nإجمالي المبلغ المستحق: SAR 1,200.00\nالحد الأدنى للسداد: SAR 100\nتاريخ الاستحقاق: 2026-11-05", sender: "alinma")
        #expect(alinma.kind == .statement)
        #expect(alinma.statementDueMinor == 120_000)
        #expect(alinma.minimumDueMinor == 10_000)
        let snb = parse("تم اصدار الكشف الإلكتروني لبطاقتك الائتمانية **1111 \nمبلغ كشف الحساب 300.00 ريال\nالمبلغ المستحق 150.00 ريال \nتاريخ الاستحقاق 05/11/2026", sender: "snb-alahli")
        #expect(snb.kind == .statement)
        #expect(snb.statementDueMinor == 15_000)
    }

    @Test func mobilyPayReceivedAmountIsIncoming() {
        let received = parse("You have received amount : 75.00 SAR \nFrom: EXAMPLE PERSON 0500000000 \nOn: 15/10/2026 13:05:00 \nDownload Mobily Pay App to collect the amount\n\nلقد تلقيت مبلغ: SAR 75.00 \nمن: EXAMPLE PERSON 0500000000 \nفي: 15/10/2026 13:05:00", sender: "Mobily_Pay")
        #expect(received.kind == .transferIn)
        #expect(received.amountMinor == 7_500)
        #expect(received.counterparty?.hasPrefix("EXAMPLE PERSON") == true)
    }
}

/// Layout classes added by the 99% accuracy pass (RM6). Every name, number and amount is invented; expected values come from
/// what each message means, not from the parser's output.
@Suite struct AccuracyPassLayoutTests {
    let riyadh = TimeZone(identifier: "Asia/Riyadh")!
    func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int) -> Date {
        var c = Calendar(identifier: .gregorian); c.timeZone = riyadh
        return c.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }
    private func parse(_ text: String, sender: String? = nil, received: Date? = nil) -> ParsedBankMessage {
        BankMessageParser.parse(text, timeZone: riyadh, receivedAt: received ?? at(2026, 10, 15, 13, 0), sender: sender,
                                trackedWallets: ["STC Pay", "Drahim"])
    }

    // MARK: Dates

    @Test func windowsLineEndingsSplitIntoLines() {
        let p = parse("Online Purchase:\r\nCard: ***1234; VISA\r\nAmount: SAR 12.00\r\nAt: Example Shop RIYADH SA\r\nDate: 2026-10-15 12:30:00")
        #expect(p.kind == .purchase)
        #expect(p.merchant == "Example Shop")
        #expect(p.eventAt == at(2026, 10, 15, 12, 30))
    }

    @Test func oneDigitDayAndBackslashDatesRead() {
        #expect(parse("شراء انترنت\nبطاقة:0123;مدى\nمبلغ:SAR 5\nلدى:EXAMPLE\nفي:26-10-5 05:27").eventAt == at(2026, 10, 5, 5, 27))
        #expect(parse("شراء انترنت\nبطاقة:0123;مدى\nمبلغ:SAR 5\nلدى:EXAMPLE\n\u{061C}15\\10\\26 6:07").eventAt == at(2026, 10, 15, 6, 7))
    }

    @Test func timeBeforeDateAndMonthFirstDatesRead() {
        let timeFirst = parse("حوالة واردة محلية\nمبلغ 1,000 SAR\nمن اسم تجريبي\nحساب *1234\nفي 09:29 2026-10-14")
        #expect(timeFirst.eventAt == at(2026, 10, 14, 9, 29))
        // «2/5/2026 7:25 PM» is February 5 (month first); the day-first reading is eight months from the receive time.
        let usStyle = parse("إضافة أموال لحسابك\nبـ:500 ر.س\nفي:2/5/2026 7:25\u{00A0}PM", received: at(2026, 2, 5, 19, 26))
        #expect(usStyle.eventAt == at(2026, 2, 5, 19, 25))
        // «09/05 09:54» with no year: month first when the day-first reading is months away.
        let noYear = parse("تسديد آلي\nبطاقة **1234\nمبلغ 100.00 ريال\nفي 09/05 09:54", received: at(2026, 9, 5, 10, 0))
        #expect(noYear.eventAt == at(2026, 9, 5, 9, 54))
        // A day-first reading near the receive time stays day first.
        #expect(parse("Money received\nOn: 02/10/2026 08:00:01", received: at(2026, 10, 2, 8, 1)).eventAt == at(2026, 10, 2, 8, 0))
    }

    @Test func arabicMonthTradeAndSplitLineViolationDatesRead() {
        let trade = parse("تنفيذ بيع شركة مثال لمحفظتك 111111-1 في\nSAR الثلاثاء 15 يونيو 2021 2:5:0 م بسعر 10.5 SAR لعدد 2 سهم بقيمة إجمالية 21.00 عمولة 0.05 ضريبة 0.01", received: at(2021, 6, 15, 14, 6))
        #expect(trade.eventAt == at(2021, 6, 15, 14, 5))
        let violation = parse("تم قيد مخالفة:\nتجاوز السرعة\nالتاريخ:\n2026-10-13\nالوقت:\n13:38\nالقيمة:\n113 ريال", sender: "MOI")
        #expect(violation.eventAt == at(2026, 10, 13, 13, 38))
        #expect(violation.amountMinor == 11_300)
    }

    @Test func dateWithoutTimeIsKeptApartFromEventAt() {
        let p = parse("حوالة مالية صادرة مقبولة\nمن: *1234\nالى: اسم تجريبي\nالمبلغ: 40 SAR\nفي: 14/10/2026")
        #expect(p.eventAt == nil)
        #expect(p.eventDateOnly == at(2026, 10, 14, 12, 0))
    }

    // MARK: Classes

    @Test func cashDepositsAndCardPaymentsAndCardTransfers() {
        let atm = parse("ايداع:صراف آلي\nالى:*1234\nمبلغ:SAR 175.00\nفي:26-10-14 10:00")
        #expect(atm.kind == .income); #expect(atm.amountMinor == 17_500); #expect(atm.accountLast4 == "1234")
        let pay = parse("بطاقة ائتمانية:تسديد\nبطاقة:*4321 ;فيزا\nمبلغ:SAR 135.00\nمن:*1234\nفي:26-10-14 10:00")
        #expect(pay.kind == .cardPayment); #expect(pay.last4 == "4321"); #expect(pay.accountLast4 == "1234")
        let cash = parse("بطاقة ائتمانية:تحويل\nمن بطاقة:*4321;فيزا\nالى حساب:*1234\nمبلغ:SAR 90.00\nفي:26-10-14 10:00")
        #expect(cash.kind == .transferOut); #expect(cash.amountMinor == 9_000); #expect(cash.last4 == "4321")
    }

    @Test func reversalKeepsTheOriginalMerchantAmountAndCard() {
        let p = parse("عكس  عملية\nبطاقة:*4321 ;فيزا\nمبلغ:SAR 7.50\nلدى:EXAMPLE SHOP\nرصيد:SAR 80.00\nفي:26-10-14 10:00")
        #expect(p.kind == .reversal)
        #expect(p.amountMinor == 750); #expect(p.merchant == "EXAMPLE SHOP"); #expect(p.last4 == "4321"); #expect(p.balanceMinor == 8_000)
    }

    @Test func refundsFromRefundLayouts() {
        let credit = parse("تم اضافة مبلغ بقيمة SAR 20.00 الى بطاقة *4321 من EXAMPLE SHOP في 26-10-14 10:00 والحد المتبقي SAR 900.00 ريال")
        #expect(credit.kind == .refund); #expect(credit.amountMinor == 2_000); #expect(credit.merchant == "EXAMPLE SHOP"); #expect(credit.remainingLimitMinor == 90_000)
        let back = parse("استرجاع عملية\nبطاقة: 4321; فيزا\nمبلغ: 15.00 SAR\nالتاجر: example.shop\nفي: 14-10-2026 10:00")
        #expect(back.kind == .refund); #expect(back.merchant == "example.shop"); #expect(back.amountMinor == 1_500)
        let wallet = parse("عملية استرجاع\nبطاقة فيزا **4321\nمبلغ: 3.00 EUR (12.50 SAR)\nلدى :EXAMPLE EU\n2026-10-14 10:00")
        #expect(wallet.kind == .refund); #expect(wallet.currency == "EUR"); #expect(wallet.statedHomeMinor == 1_250)
    }

    @Test func requestAcknowledgementsAreNotMovements() {
        #expect(parse("عزيزي العميل\nلقد تم استلام طلب استرداد التكاليف الطبية الخاص بك").kind == .marketing)
        #expect(parse("تمت الموافقة على طلب بطاقة الائتمانية بحد ائتماني SAR 5,000.").kind == .marketing)
    }

    @Test func governmentBillAndWalletTransfers() {
        let fine = parse("مدفوعات وزارة الداخلية-المخالفات المرورية\nمن:1234\nمبلغ:SR 150\nرقم الفاتورة:1000000001\n26/10/14 10:00")
        #expect(fine.kind == .billPayment); #expect(fine.amountMinor == 15_000); #expect(fine.accountLast4 == "1234")
        let toWallet = parse("تحويل الى حساب دراهم\nمن:1234\nمبلغ:SAR 500\nالى:محفظة تجريبية\n26/10/14 10:00")
        #expect(toWallet.kind == .transferOut); #expect(toWallet.counterparty == "محفظة تجريبية"); #expect(toWallet.accountLast4 == "1234")
    }

    @Test func alinmaLineTransferAndSnbEnglishTransfer() {
        let incoming = parse("حوالة 120 ريال لحساب **1234 من اسم تجريبي 2026-10-14 10:30", sender: "alinmabank")
        #expect(incoming.kind == .transferIn); #expect(incoming.amountMinor == 12_000); #expect(incoming.counterparty == "اسم تجريبي")
        let english = parse("Outgoing IPS local transfer from *1234 To EXAMPLE CO Amount 2000 SAR By EXAMPLE BANK IBAN *5678 On 14/10/26 15:21", sender: "snb")
        #expect(english.kind == .transferOut); #expect(english.counterparty == "EXAMPLE CO"); #expect(english.amountMinor == 200_000)
    }

    @Test func counterpartyLayouts() {
        let out = parse("حوالة صادرة:داخلية\nمن:*1234\nمبلغ:SAR 27.00\nالى:جمعية تجريبية\nالى حساب:*7788\nفي:26-10-14 23:20")
        #expect(out.counterparty == "جمعية تجريبية"); #expect(out.accountLast4 == "1234")
        let stcBank = parse("حوالة صادرة (سريع)\n160.00 ر.س\nإلى اسم تجريبي\nإلى مصرف تجريبي\nحساب *7410\nرسوم 1.00 ر.س\n03/10/26 09:07")
        #expect(stcBank.counterparty == "اسم تجريبي"); #expect(stcBank.feeMinor == 100)
        let incoming = parse("حوالة واردة محلية\n50.00 ر.س\nمن اسم تجريبي\nمن بنك مصرف تجريبي\nحساب *7410\n01/10/26 02:00")
        #expect(incoming.counterparty == "اسم تجريبي"); #expect(incoming.accountLast4 == "7410")
        let beneficiary = parse("تأكيد إيداع حوالة صادرة محلية (سريع)\nإلى المستفيد: اسم تجريبي\nإلى حساب: **5566\nالمبلغ: 131.40 SAR\nالرسوم: 0.45 SAR\nمن حساب: **7391\nفي: 2026-10-14 08:25")
        #expect(beneficiary.counterparty == "اسم تجريبي"); #expect(beneficiary.accountLast4 == "7391"); #expect(beneficiary.feeMinor == 45)
    }

    @Test func declinedAndInternationalCardLayouts() {
        let limit = parse("Rejected transaction: Daily limit exceeded\nCard: **1234\nAmount: 100.00 SAR\nAt: EXAMPLE PAY\nOn: 2026-10-14 10:00", sender: "barq_app")
        #expect(limit.kind == .declined); #expect(limit.declineReason == .limitExceeded); #expect(limit.merchant == "EXAMPLE PAY")
        let funds = parse("تم رفض العملية: الرصيد غير كافٍ.\nالعملية: شراء انترنت\nالبطاقة: 1234\nالمبلغ: SAR 50\nالحساب: EXAMPLE.SITE\nالتاريخ: 14/10/26 10:00")
        #expect(funds.declineReason == .insufficientBalance); #expect(funds.merchant == "EXAMPLE.SITE"); #expect(funds.last4 == "1234")
        let other = parse("حوالة مالية صادرة مرفوضة\nالسبب: [DS99] لا يمكن تنفيذ العملية\nالمبلغ: SAR 10")
        #expect(other.kind == .declined); #expect(other.declineReason == .other)
        let blocked = parse("Declined transaction: card is blocked\nAmount: SAR 10")
        #expect(blocked.declineReason == .cardBlocked)
    }

    @Test func foreignPurchaseKeepsRateAndFeesApart() {
        let p = parse("POS International Purchases:\nVisa card: **1234 (Apple Pay)\nAmount: 10.00 EUR (45.00 SAR)\nExchange Rate ≈ 4.5000\nFX Markup: 1.20 SAR\nWallet balance: 800.50\nAt: EXAMPLE SHOP\nCountry: FRA\nOn: 2026-10-14 10:00", sender: "barq_app")
        #expect(p.kind == .purchase); #expect(p.amountMinor == 1_000); #expect(p.currency == "EUR"); #expect(p.statedHomeMinor == 4_500)
        #expect(p.exchangeRate == "4.5000"); #expect(p.foreignFeeMinor == 120); #expect(p.balanceMinor == 80_050); #expect(p.feeMinor == nil)
    }

    @Test func feeVatBalanceAndLimitsAreSeparateFields() {
        let bsf = parse("شراء عبر نقاط البيع بـ SAR 100.00\nرسوم العملية:2.50\nمن EXAMPLE SHOP\nبطاقة ائتمانية 4321* من EXAMPLE BANK\nالمبلغ الإجمالي المستحق SAR 102.50\nالرصيد المتوفر: SAR 900.00\nفي26-10-14 10:00", sender: "BSF")
        // «الرصيد المتوفر» after the total-due line of a credit card is the available credit, not a balance.
        #expect(bsf.amountMinor == 10_000); #expect(bsf.feeMinor == 250); #expect(bsf.balanceMinor == nil); #expect(bsf.availableLimitMinor == 90_000)
        let snb = parse("شراء-POS\nبـ21.30 SAR\nمن EXAMPLE SHOP\nإئتمانية **4321 (Apple Pay)\nفي 14/10/26 19:02\nالصرف المتبقي 2712.60 SAR")
        #expect(snb.remainingLimitMinor == 271_260); #expect(snb.balanceMinor == nil)
        let combined = parse("سحب صراف\nبطاقة:*4321 ;فيزا\nمبلغ:SAR 200\nرسوم وضريبة: 5.75 SAR\nفي:26-10-14 10:00")
        #expect(combined.feeMinor == 575); #expect(combined.vatMinor == nil)
        let limit = parse("شراء\nمبلغ 10.00 SAR\nبطاقة *4321\nالحد المتاح 1,200.00 SAR\nفي 14-10-2026 10:00")
        #expect(limit.availableLimitMinor == 120_000); #expect(limit.balanceMinor == nil)
    }

    @Test func bareBalanceIsReadOnlyWhereLabelled() {
        let wallet = parse("Online Purchases:\nMada card: **1234\nAmount: 25.00 SAR\nBalance: 100.25\nAt: EXAMPLE SHOP\nA/C: **6789\nOn: 2026-10-14 10:00", sender: "barq_app")
        #expect(wallet.balanceMinor == 10_025); #expect(wallet.accountLast4 == "6789"); #expect(wallet.last4 == "1234")
        #expect(parse("بطاقة ائتمانية:سداد\nبطاقة:*4321;فيزا\nمبلغ:SAR 10.00").balanceMinor == nil)
    }

    @Test func shareTradesUseTheTotalNotThePerShareAndKeepFeeAndVat() {
        let sale = parse("تنفيذ بيع شركة مثال لمحفظتك 111111-1 في\nSAR الخميس 17 يونيو 2021 2:15:0 م بسعر 27.70 SAR لعدد 12 سهم بقيمة إجمالية 332.40 عمولة 0.52 ضريبة 0.06", received: at(2021, 6, 17, 14, 16))
        #expect(sale.kind == .transferIn); #expect(sale.counterparty == "Alinma Investment"); #expect(sale.amountMinor == 33_240); #expect(sale.merchant == "شركة مثال")
        #expect(sale.feeMinor == 52); #expect(sale.vatMinor == 6)
        let buy = parse("تنفيذ شراء شركة مثال لمحفظتك 111111-1 في\nSAR الخميس 17 يونيو 2021 2:15:0 م بسعر 27.70 SAR لعدد 2 سهم بقيمة إجمالية 55.40 عمولة 0.10 ضريبة 0.01", received: at(2021, 6, 17, 14, 16))
        #expect(buy.kind == .transferOut); #expect(buy.counterparty == "Alinma Investment"); #expect(buy.amountMinor == 5_540)
    }

    @Test func tamaraDueDaysArePrintedRelatively() {
        let p = parse("دفعة قادمة بقيمة 123.45 SAR لطلبك من متجر وهمي مستحقة خلال يومين. سددها الحين: https://tmra.pe/abc", sender: "Tamara")
        #expect(p.dueDate == at(2026, 10, 17, 13, 0))
    }

    @Test func latinCurrencyCodesNeedWordBoundaries() {
        // «mada» is the Saudi debit network, not the Moroccan dirham «MAD»; the amount is the SAR figure.
        let p = parse("POS Purchase\nBy: ***7531 mada Prepaid\nAmount: SAR 17.00\nAt: EXAMPLE SHOP\nDate: 2026/10/14 13:43", sender: "samba")
        #expect(p.amountMinor == 1_700); #expect(p.currency == "SAR"); #expect(p.last4 == "7531"); #expect(p.merchant == "EXAMPLE SHOP")
    }

    @Test func electricityPaymentThanksUseTheHomeCurrencyForItsSender() {
        let p = parse("عزيزي المشترك نشكرك على سداد فاتورة الحساب 1000000001 بمبلغ 187.65", sender: "alkahraba")
        #expect(p.kind == .billPayment); #expect(p.amountMinor == 18_765); #expect(p.currency == "SAR")
        #expect(parse("عزيزي المشترك نشكرك على سداد فاتورة الحساب 1000000001 بمبلغ 187.65", sender: "other").amountMinor == nil)
    }

    @Test func tamaraNoticesNameTheirStore() {
        #expect(parse("دفعة قادمة بقيمة 50.00 SAR لطلبك من متجر وهمي مستحقة اليوم. سددها الحين", sender: "Tamara").merchant == "متجر وهمي")
        #expect(parse("تأكيد الدفع\nمن: example.store/\nبقيمة: 142.70 SAR\nفي: 16/10/2026", sender: "Tamara").merchant == "example.store/")
    }

    @Test func otherSideAccountTailIsKeptApartFromTheOwnersAccount() {
        let own = parse("تحويل بين حساباتي\nبـ:100.00 ر.س\nمن: ***3579\nإلى: ***2461\nفي:10/10/26 13:09")
        #expect(own.accountLast4 == "3579"); #expect(own.counterpartyAccountLast4 == "2461")
        let incoming = parse("حوالة محلية واردة\nمبلغ:SAR 300\nالى:2468\nمن:اسم تجريبي\nمن:1357\nفي:26-10-14 10:59")
        #expect(incoming.accountLast4 == "2468"); #expect(incoming.counterpartyAccountLast4 == "1357"); #expect(incoming.counterparty == "اسم تجريبي")
    }

    @Test func feeLabelNeedsAWordBoundaryAndAColon() {
        #expect(parse("Online Purchase:\nCard: ***1234; VISA\nAmount: SAR 12.00\nAt: Joe Coffee 24\nDate: 2026-10-15 12:30:00").feeMinor == nil)
        #expect(parse("Online Purchase:\nCard: ***1234; VISA\nAmount: SAR 12.00\nAt: Fee Shop 24\nDate: 2026-10-15 12:30:00").feeMinor == nil)
        #expect(parse("Online Purchase:\nCard: ***1234; VISA\nAmount: SAR 12.00\nFee: SAR 1.50\nAt: Example Shop\nDate: 2026-10-15 12:30:00").feeMinor == 150)
    }

    @Test func dayFirstDateIsNotSwappedWithoutADeliveryTimeOrNearReceipt() {
        let november = parse("شراء\nمبلغ 10.00 SAR\nبطاقة *1234\nفي: 10-09-2026 10:00", received: at(2026, 11, 5, 9, 0))
        #expect(november.eventAt == at(2026, 9, 10, 10, 0))
        let pasted = BankMessageParser.parse("Money received\nOn: 02/07/2026 19:26:32", timeZone: riyadh, receivedAt: nil)
        #expect(pasted.eventAt == at(2026, 7, 2, 19, 26))
        // A month above 12 can only be day first.
        #expect(parse("شراء\nمبلغ 10.00 SAR\nبطاقة *1234\nفي: 25/10/2026 10:00").eventAt == at(2026, 10, 25, 10, 0))
    }

    @Test func amountLessMovementKindsAreNotRecordable() {
        let promo = parse("حصرياً استمتع بـ 15% استرداد نقدي لدى متجر وهمي مع بطاقات المصرف. يسري العرض حتى 30 ديسمبر")
        #expect(promo.kind == .marketing); #expect(BankIntake.decision(promo.kind) == .discard)
        #expect(parse("عزيزي العميل، سيتم تحديث رسوم التعرفة البنكية للمنتجات ابتداءً من 1/1/2027. للتفاصيل زر موقعنا.").kind == .marketing)
        #expect(parse("تم إلغاء (اختبار تجريبي) لعدم السداد").kind == .marketing)
        let odd = parse("تم إيداع الأرباح لحسابك الادخاري")
        #expect(odd.kind == .unknown); #expect(BankIntake.decision(odd.kind) == .needsLook)
    }

    @Test func recipientNameLabelAndTabbyEnglishMerchant() {
        let out = parse("حوالة صادرة\nمبلغ: SAR 80.00\nاسم المستلم: اسم تجريبي\nفي: 2026-10-14 10:00")
        #expect(out.kind == .transferOut); #expect(out.counterparty == "اسم تجريبي")
        let tabby = parse("Your SAR 120.00 purchase at EXAMPLE STORE is confirmed. Track your upcoming payments with the Tabby app: https://tabby.sa/x", sender: "Tabby")
        #expect(tabby.kind == .bnplInstalment); #expect(tabby.amountMinor == 12_000); #expect(tabby.merchant == "EXAMPLE STORE")
        let due = parse("Your EXAMPLE STORE payment of SAR 45 will be charged to your card tomorrow. If you need more time, extend at https://s.tabby.sa/x", sender: "Tabby")
        #expect(due.merchant == "EXAMPLE STORE")
    }

    @Test func cardTailAfterTheNetworkWordAndNegativeBalanceKeepsItsSign() {
        let pay = parse("بطاقة ائتمانية:سداد\nبطاقة:فيزا 4321\nمبلغ:SAR 150.00\nرصيد:80.00 SAR\nفي:16-10-2026 15:21")
        #expect(pay.kind == .cardPayment); #expect(pay.last4 == "4321"); #expect(pay.balanceMinor == 8_000)
        let negative = parse("شراء انترنت\nبطاقة:*4321 ;فيزا\nمبلغ:SAR 120.00\nلدى:EXAMPLE\nرصيد:SAR -5.25\nفي:20-11-16 10:00")
        #expect(negative.balanceMinor == -525); #expect(negative.amountMinor == 12_000)
    }

    @Test func newAlRajhiTransferLayoutKeepsNameAndBothTails() {
        let incoming = parse("حوالة داخلية واردة\nبـSAR 400\nلـ2468\nمن1357;اسم تجريبي\n26/10/1 16:47")
        #expect(incoming.kind == .transferIn); #expect(incoming.accountLast4 == "2468")
        #expect(incoming.counterparty == "اسم تجريبي"); #expect(incoming.counterpartyAccountLast4 == "1357")
        let outgoing = parse("حوالة داخلية صادرة\nمن3579\nبـSAR 400\nلـ2461;اسم تجريبي\n26/10/1 13:16")
        #expect(outgoing.kind == .transferOut); #expect(outgoing.accountLast4 == "3579")
        #expect(outgoing.counterparty == "اسم تجريبي"); #expect(outgoing.counterpartyAccountLast4 == "2461")
    }

    @Test func foreignCardDebitWithBalanceOnTheSameLine() {
        let p = parse("خصم USD 7.50 من حساب 004*321 للبطاقة *4321 في 21-04-25 03:51 والرصيد USD 12.00 ريال")
        #expect(p.kind == .purchase); #expect(p.amountMinor == 750); #expect(p.currency == "USD")
        #expect(p.last4 == "4321"); #expect(p.accountLast4 == "321"); #expect(p.balanceMinor == 1_200)
    }

    @Test func investmentTransferInStopsTheNameBeforeTailAndDate() {
        let p = parse("تحويل 100.50 ريال من الحساب الإستثماري المنتهي ب ***321 في 09-06-2021 15:48:47", sender: "alrajhicptl")
        #expect(p.kind == .transferIn); #expect(p.counterparty == "الحساب الإستثماري"); #expect(p.counterpartyAccountLast4 == "321")
        #expect(p.amountMinor == 10_050)
    }

    @Test func snbStarredAccountTail() {
        let salary = parse("ايداع رواتب\nمبلغ SAR 500\nحساب706*321\nفي 30/01/2022 09:41")
        #expect(salary.kind == .income); #expect(salary.accountLast4 == "321")
        let purchase = parse("شراء عبر نقاط البيع  (Apple Pay)\nمبلغ 50 SAR\nبطاقة مدى *4321\nحساب 706*321\nمن example shop\nفي 30/01/2022 18:51")
        #expect(purchase.accountLast4 == "321"); #expect(purchase.last4 == "4321")
    }

    @Test func transferBetweenOwnAccountsKeepsItsDestinationTail() {
        let p = parse("حوالة بين حساباتك\nمبلغ: SAR 700\nالى: 2468\nفي: 25-12-23 23:10")
        #expect(p.kind == .transferOut); #expect(p.counterpartyAccountLast4 == "2468")
    }

    @Test func tabbyChargeReminderIsANotice() {
        let p = parse("Your EXAMPLE STORE payment of SAR 45 will be charged to your card tomorrow. If you need more time, extend at https://s.tabby.sa/x", sender: "Tabby")
        #expect(p.kind == .marketing); #expect(p.statementDueMinor == 4_500); #expect(BankIntake.decision(p.kind) == .discard)
    }

    @Test func fullStopEndsTheNameAndBillerLabelWithoutArticle() {
        let p = parse("شريكنا العزيز\nتم  تحويل مبلغ 120.00SAR إلى EXAMPLE PERSON.\nشكراً لاستخدامك التطبيق", sender: "alinma_inv.")
        #expect(p.kind == .transferOut); #expect(p.counterparty == "EXAMPLE PERSON")
        let bill = parse("سداد فاتورة\nرقم: 100000000001\nالمبلغ: 90.00 ريال\nمفوتر: شركة تجريبية\nمن البطاقة الائتمانية: 7391\nفي: 26-02-16 18:10\nالرصيد المتاح: 1,000.00 ريال")
        #expect(bill.biller == "شركة تجريبية"); #expect(bill.last4 == "7391"); #expect(bill.balanceMinor == 100_000)
    }

    @Test func reverseOperationIsAReversalAndTailsComeFromEveryShape() {
        let rev = parse("عملية عكسية\nبطاقة فيزا: **7391 (Apple Pay)\nمبلغ: 10.00 EUR (45.00 SAR)\nر.ح: **318\nلدى: Example Hotel\nفي: 2026-10-14 10:00")
        #expect(rev.kind == .reversal); #expect(rev.last4 == "7391"); #expect(rev.accountLast4 == "318"); #expect(rev.merchant == "Example Hotel")
        let snbCard = parse("سداد بطاقة ائتمانية\nمن حساب *2468\nالى بطاقة **7391\nمبلغ SAR 500.00\nفي 14/10/26 10:00")
        #expect(snbCard.kind == .cardPayment); #expect(snbCard.last4 == "7391"); #expect(snbCard.accountLast4 == "2468")
        let d360 = parse("حوالة مالية صادرة مقبولة\nخصمت من حساب: ****2468\nالقيمة: SAR 100.00\nإلى: ABC\nرقم الحساب: ****1357 - EXAMPLE BANK\nفي: 2026-10-14 10:00")
        #expect(d360.accountLast4 == "2468"); #expect(d360.counterpartyAccountLast4 == "1357")
        let incoming = parse("حوالة واردة:محلية\nعبر:EXAMPLE BANK\nمبلغ:SAR 100.00\nالى:*2468\nمن:اسم تجريبي\nمن ايبان:*1357\nفي:26-10-14 10:00")
        #expect(incoming.accountLast4 == "2468"); #expect(incoming.counterpartyAccountLast4 == "1357")
        let atm = parse("ايداع:صراف آلي\nبطاقة:*7391;مدى(أثير)\nمبلغ:SAR 100.00\nالى:*2468EXAMPLE BANK\nفي:26-10-14 10:00")
        #expect(atm.accountLast4 == "2468"); #expect(atm.last4 == "7391")
        let visaCard = parse("بطاقة فيزا:سداد بـSR 100\nعبر7391;فيزا\nرصيد:50.00 SR\n1/10/26 11:06")
        #expect(visaCard.last4 == "7391")
    }

    @Test func alRajhiPurchaseAtAWalletMerchantStaysATransferOut() {
        let p = parse("شراء انترنت\nبطاقة:*7391;مدى\nمن:*7746\nلدى:STC Pay\nمبلغ:SAR 22.00\nفي:20-10-08 20:27")
        #expect(p.kind == .transferOut); #expect(p.counterparty == "STC Pay"); #expect(p.amountMinor == 2_200)
    }

    @Test func billIssuedAndReminderNoticesKeepTheirDueFigures() {
        let bill = parse("عزيزي المشترك، تم إصدار فاتورتك للحساب رقم 100000000001 والمبلغ المطلوب 187.65 ريال.\nللاطلاع اضغط https://example.test/b", sender: "alkahraba")
        #expect(bill.kind == .marketing); #expect(bill.statementDueMinor == 18_765); #expect(bill.currency == "SAR"); #expect(BankIntake.decision(bill.kind) == .discard)
        let dated = parse("تم إصدار فاتورتك والمبلغ المطلوب 50.00 ريال\nتاريخ الاستحقاق: 2026-11-20")
        #expect(dated.statementDueMinor == 5_000); #expect(dated.dueDate != nil)
        let tamara = parse("دفعة قادمة بقيمة 90.00 SAR لطلبك من متجر وهمي مستحقة خلال يومين. سددها الحين: https://tmra.pe/x", sender: "Tamara")
        #expect(tamara.kind == .marketing); #expect(tamara.statementDueMinor == 9_000); #expect(tamara.dueDate == at(2026, 10, 17, 13, 0))
    }
}
