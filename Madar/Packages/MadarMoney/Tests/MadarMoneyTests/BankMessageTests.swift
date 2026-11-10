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
        // A bare «دينار» names no country: no amount is read rather than guessing one.
        #expect(BankMessageParser.amounts("مبلغ: 5.000 دينار", exponents).isEmpty)
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

    @Test func walletDebitWithoutAnEndpointStaysReviewable() {
        let parsed = BankMessageParser.parse("Wallet operations\nWallet: stc pay\nDebit via wallet transfer\nAmount: SAR 45.00", timeZone: riyadh, sender: "stcpay")
        #expect(parsed.kind == .unknown)
        #expect(BankIntake.decision(parsed.kind) == .needsLook)
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

        let rajhiLayout = BankMessageParser.parse("شراء انترنت\nعبر:1493;مدى-ابل باي\nمن:9004\nبـSAR 5\nلـTEST DONATION\n17/1/26 06:09",
            timeZone: riyadh, receivedAt: ISO8601DateFormatter().date(from: "2026-01-17T06:09:00+03:00"), sender: "AlRajhiBank")
        #expect(rajhiLayout.kind == .purchase)
        #expect(rajhiLayout.amountMinor == 500)
        #expect(rajhiLayout.last4 == "1493")
        #expect(rajhiLayout.merchant == "TEST DONATION")

        let bsfLayout = BankMessageParser.parse("شراء عبر نقاط البيع\nلدى:TEST CAFE\nمبلغ: 39 SAR\n17/1/26 06:09",
            timeZone: riyadh, receivedAt: ISO8601DateFormatter().date(from: "2026-01-17T06:09:00+03:00"), sender: "BSF")
        #expect(bsfLayout.kind == .purchase)
        #expect(bsfLayout.amountMinor == 3_900)
        #expect(bsfLayout.merchant == "TEST CAFE")
    }
}
