#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands

extension AppSession {
    /// Named synthetic stores only. Never reads or writes the owner's store.
    func prepareMoneyFixture(group: URL) throws {
        guard let variant = ProcessInfo.processInfo.environment["MADAR_UI_MONEY_FIXTURE"], ["showcase", "empty", "hidden", "zero", "shortfall", "messages", "since", "rules", "salary", "budget", "cards", "cardsHidden"].contains(variant), group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let c = ModelContext(container)
        guard !(try c.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.moneyFixture" }) else { return }
        for key in ["sys.moneyFixture", "sys.onboardingCompleted"] { let marker = DeviceSetting(); marker.key = key; marker.valueJSON = Data("true".utf8); c.insert(marker) }
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "core.faceIDLock": .string("none"), "core.hideMoneyUntilTouch": .bool(variant == "hidden" || variant == "cardsHidden")])
        guard variant != "empty" else { try c.save(); return }
        let zone = ActivePlace.riyadh.timeZone, now = prayerNow(), today = GregorianDay.containing(prayerNow(), in: ActivePlace.riyadh.timeZone)
        // «نزل الراتب» arrives at the end of a full cycle; the other variants sit five days into theirs.
        let start = today.adding(days: variant == "salary" ? -31 : -5), end = start.adding(days: variant == "salary" ? 31 : 30)
        let account = Account(); account.name = "الحساب الجاري"; account.balanceMinor = variant == "shortfall" ? 50000 : 12_850_000; account.balanceAt = now; c.insert(account)
        let cycle = Cycle(); cycle.start = start.date(in: zone); cycle.expectedEnd = end.date(in: zone); cycle.incomeMinor = 1_500_000; cycle.dailyAllowanceMinor = variant == "zero" ? 0 : 41_300; cycle.createdAt = cycle.start; c.insert(cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = start.description; policy.allowanceMinor = cycle.dailyAllowanceMinor; policy.dailyRateMinor = cycle.dailyAllowanceMinor; c.insert(policy)
        func allocation(_ amount: Int, _ target: String, id: UUID? = nil, tx: UUID? = nil, kind: String = "fund") {
            let a = Allocation(); a.amountMinor = amount; a.target = target; a.targetID = id; a.transactionID = tx; a.cycleID = cycle.id; a.kind = kind; a.idempotencyKey = UUID().uuidString; c.insert(a)
        }
        for (role, title, balance) in [("reserve", "الاحتياطي", 10_000_000), ("surplus", "الفائض", 260_000)] { let e = Envelope(); e.role = role; e.name = title; c.insert(e); if role == "reserve" { allocation(balance, role) }
            else {
                for (index, delta) in [50000, 100000, -40000, 150000].enumerated() {
                    let old = Cycle(); old.start = start.adding(days: -(4 - index) * 30).date(in: zone); old.end = start.adding(days: -(3 - index) * 30).date(in: zone); old.closedAt = old.end; c.insert(old)
                    let a = Allocation(); a.target = "surplus"; a.amountMinor = delta; a.kind = delta < 0 ? "offset" : "fund"; a.cycleID = old.id; a.createdAt = old.start; a.idempotencyKey = UUID().uuidString; c.insert(a)
                }
            }
        }
        for (index, title, balance, target) in [(0, "الإيجار", -90_000, 180_000), (1, "رحلة الشتاء", -40_000, 200_000), (2, "الطوارئ", 120_000, 180_000), (3, "هدية", 46_000, 60_000)] {
            let e = Envelope(); e.name = title; e.role = "goal"; e.targetMinor = target; e.due = end.adding(days: index * 10).date(in: zone); e.createdAt = now.addingTimeInterval(Double(index)); c.insert(e); allocation(balance, "envelope", id: e.id)
        }
        let planEnvelope = try c.fetch(FetchDescriptor<Envelope>()).first { $0.name == "رحلة الشتاء" }!
        let plan = EnvelopePlan(); plan.envelopeID = planEnvelope.id; plan.source = "daily"; plan.period = "perDay"; plan.perPaycheckMinor = variant == "zero" ? 0 : 1300; plan.startDayKey = start.description; c.insert(plan)
        var categories: [MadarData.Category] = []
        for (index, title) in ["مطاعم", "بقالة", "بنزين", "أخرى"].enumerated() { let category = MadarData.Category(); category.name = title; category.order = index; c.insert(category); categories.append(category); let limit = CategoryLimit(); limit.categoryID = category.id; limit.limitMinor = [300_000, 400_000, 200_000, 500_000][index]; c.insert(limit) }
        for (index, spent) in [30_000, 12_000, 15_000, variant == "cards" ? 52_000 : 22_000, 11_000, 14_000].enumerated() { // «cards»: day 4 passes the 413 limit so the log shows a red arch
            let tx = MoneyTransaction(); tx.dayKey = start.adding(days: index).description; tx.eventAt = start.adding(days: index).date(in: zone).addingTimeInterval(9 * 3600); tx.cycleID = cycle.id; tx.fromAccountID = account.id; tx.amountMinor = spent; tx.homeAmountMinor = spent; tx.categoryID = categories[index % categories.count].id; tx.method = "transfer"; tx.source = "manual"; tx.reviewState = "ok"; tx.tzID = zone.identifier; tx.dayPolicy = "midnight@1"; c.insert(tx); allocation(-spent, "daily", tx: tx.id, kind: "spend")
        }
        for (index, title, amount) in [(0, "قسط القرض", 285_000), (1, "الكهرباء", 22_000), (2, "الاتصال", 19_000)] {
            let o = Obligation(); o.name = title; o.kind = index == 0 ? "loan" : "bill"; o.amountMinor = amount; o.dueDay = min(28, today.day + index + 2); c.insert(o)
            if index == 0 { let item = InstallmentItem(); item.obligationID = o.id; item.amountMinor = amount; item.dueDate = today.adding(days: 2).date(in: zone); c.insert(item) }
        }
        if variant != "messages" { let m = BankMessage(); m.text = "شراء اصطناعي ينتظر التوزيع"; m.kind = "purchase"; m.status = "needsLook"; m.receivedAt = now; c.insert(m) }
        account.bank = "بنك الاختبار"; account.senderIDs = ["بنك الاختبار"]; account.last4 = "5512"; account.ownership = "mine"
        let debit = Card(); debit.name = "بطاقة مدى"; debit.kind = "debit"; debit.bank = "بنك الاختبار"; debit.last4 = "3317"; debit.accountID = account.id; c.insert(debit)
        let card = Card(); card.name = "بطاقة المشتريات"; card.kind = "credit"; card.bank = "بنك الاختبار"; card.last4 = "8844"; card.accountID = account.id; c.insert(card)
        let statement = Statement(); statement.cardID = card.id; statement.statementMinor = 680000; statement.closeDate = start.date(in: zone).addingTimeInterval(-86400); statement.dueDate = today.adding(days: 4).date(in: zone); statement.closeDateSource = "estimated"; c.insert(statement)
        let unbilled = MoneyTransaction(); unbilled.cardID = card.id; unbilled.method = "card"; unbilled.amountMinor = 180000; unbilled.homeAmountMinor = 180000; unbilled.dayKey = today.description; unbilled.eventAt = now; unbilled.ignoredFromBudget = true; c.insert(unbilled)
        let bnpl = Obligation(); bnpl.name = "أقساط الشراء"; bnpl.provider = "Tamara"; bnpl.kind = "installment"; bnpl.totalMinor = 120000; c.insert(bnpl)
        for index in 1...3 { let item = InstallmentItem(); item.obligationID = bnpl.id; item.seq = index; item.amountMinor = 40000; item.dueDate = today.adding(days: index * 20).date(in: zone); c.insert(item) }
        try c.save()
        if variant == "cards" || variant == "cardsHidden" {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            card.name = "البطاقة الأساسية"; card.limitMinor = 2_000_000; card.cashbackBp = 50; card.aprBp = 2_400; card.network = "Visa"
            card.fieldSourcesJSON = try JSONSerialization.data(withJSONObject: ["limitMinor": "entered", "cashbackBp": "entered", "aprBp": "entered"])
            statement.minimumDueMinor = 21_300; statement.periodStart = calendar.date(byAdding: .month, value: -1, to: statement.closeDate)
            let old = Statement(); old.cardID = card.id; old.closeDate = statement.periodStart!; old.periodStart = calendar.date(byAdding: .month, value: -1, to: old.closeDate); old.dueDate = today.adding(days: -26).date(in: zone); old.statementMinor = 425_000; old.minimumDueMinor = 21_300; c.insert(old)
            let payment = MoneyTransaction(); payment.kind = "cardPayment"; payment.cardID = card.id; payment.fromAccountID = account.id; payment.amountMinor = 425_000; payment.homeAmountMinor = 425_000; payment.eventAt = old.closeDate.addingTimeInterval(86400); payment.dayKey = GregorianDay.containing(payment.eventAt, in: zone).description; payment.tzID = zone.identifier; payment.dayPolicy = "midnight@1"; c.insert(payment)
            for (index, item) in [("متجر الأدوات", 230_000), ("مطعم الحي", 12_000), ("متجر الكتب", 98_000), ("محطة الشمال", 85_000)].enumerated() {
                let row = MoneyTransaction(); row.cardID = card.id; row.method = "card"; row.merchant = item.0; row.amountMinor = item.1; row.homeAmountMinor = item.1
                row.eventAt = old.closeDate.addingTimeInterval(-Double((index + 1) * 86400)); row.dayKey = GregorianDay.containing(row.eventAt, in: zone).description; row.tzID = zone.identifier; row.dayPolicy = "midnight@1"; c.insert(row)
            }
            unbilled.merchant = "متجر الأجهزة"
            let second = Card(); second.name = "بطاقة السفر"; second.bank = "بنك الاختبار"; second.last4 = "7722"; second.kind = "credit"; second.accountID = account.id; second.limitMinor = 1_000_000; second.cashbackBp = 150; second.network = "Mastercard"
            second.fieldSourcesJSON = try JSONSerialization.data(withJSONObject: ["limitMinor": "entered", "cashbackBp": "entered"]); c.insert(second)
            for offset in [-1, 0] {
                let s = Statement(); s.cardID = second.id; s.closeDate = calendar.date(byAdding: .month, value: offset, to: today.adding(days: -2).date(in: zone))!; s.periodStart = calendar.date(byAdding: .month, value: -1, to: s.closeDate); s.dueDate = calendar.date(byAdding: .month, value: offset, to: today.adding(days: 16).date(in: zone)); s.statementMinor = 180_000; s.minimumDueMinor = 9_000; s.closeDateSource = "message"; c.insert(s)
            }
            let message = BankMessage(); message.sender = "بنك الاختبار"; message.status = "ok"; message.text = "كشف تجريبي مجهّل: المبلغ المستحق 6800 SAR، الحد الأدنى 213 SAR"; message.kind = "statement"; message.receivedAt = statement.closeDate; c.insert(message); statement.messageID = message.id
            try c.save()
        }
        if variant == "budget" {
            let purchases = try c.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.cycleID == cycle.id }.sorted { $0.eventAt < $1.eventAt }
            for (index, tx) in purchases.enumerated() {
                tx.merchant = ["مطعم الريف", "سوق الحي", "محطة الشمال", "متجر الكتب", "مقهى الزاوية", "مخبز الحي"][index % 6]; tx.source = "bank"
                tx.dayKey = today.adding(days: index < 3 ? -1 : 0).description
                tx.eventAt = today.adding(days: index < 3 ? -1 : 0).date(in: zone).addingTimeInterval(Double(9 * 3600 + index * 1800))
            }
            let tx = MoneyTransaction(); tx.merchant = "متجر الأدوات"; tx.categoryID = categories[3].id; tx.fromAccountID = account.id
            tx.amountMinor = 120_000; tx.homeAmountMinor = 120_000; tx.cycleID = cycle.id; tx.method = "transfer"; tx.reviewState = "ok"; tx.ignoredFromBudget = true
            tx.dayKey = today.description; tx.eventAt = now.addingTimeInterval(-1200); tx.tzID = zone.identifier; tx.dayPolicy = "midnight@1"; c.insert(tx)
            try c.save()
        }
        if variant == "messages" { seedMoneyMessages(today: today, zone: zone) }
        if variant == "rules" {
            // Merchants the user already filed: rules, their movements, and one merchant filed two ways.
            func spend(_ merchant: String, _ category: MadarData.Category, _ days: Int, _ amount: Int) {
                let tx = MoneyTransaction(); tx.merchant = merchant; tx.categoryID = category.id; tx.reviewState = "ok"; tx.source = "bank"; tx.method = "transfer"; tx.fromAccountID = account.id
                tx.amountMinor = amount; tx.homeAmountMinor = amount; tx.dayKey = today.adding(days: -days).description; tx.eventAt = today.adding(days: -days).date(in: zone).addingTimeInterval(10 * 3600); tx.tzID = zone.identifier; tx.dayPolicy = "midnight@1"; tx.createdAt = tx.eventAt; c.insert(tx)
            }
            for (merchant, index, times) in [("مقهى الزاوية", 0, 9), ("مخبز الحي", 0, 6), ("مطعم الريف", 0, 4), ("سوق الحي", 1, 7), ("محطة الشمال", 2, 3)] {
                let rule = MerchantRule(); rule.pattern = merchant; rule.categoryID = categories[index].id; rule.createdAt = today.adding(days: -40).date(in: zone); rule.updatedAt = rule.createdAt; c.insert(rule)
                for n in 0..<times { spend(merchant, categories[index], n % 12, 1500 + n * 300) }
            }
            for n in 0..<5 { spend("متجر الكتب", categories[n < 3 ? 3 : 1], n, 4000) }
        }
        if variant == "salary" {
            // Earlier closes carry their reports (Figure 1); salary plans fill «مظاريف هذه الدورة»; the salary arrives through the intake.
            for (index, old) in try c.fetch(FetchDescriptor<Cycle>()).filter({ $0.closedAt != nil }).sorted(by: { $0.start < $1.start }).enumerated() {
                let carried = [48_000, 124_000, -40_000, 128_000][index % 4]
                old.closedReportJSON = try JSONEncoder().encode(SalaryCloseReport(start: old.start, end: old.end ?? old.start, carriedMinor: carried, offsetMinor: max(0, -carried), carryMinor: 0,
                    toSurplusMinor: max(0, carried), toReserveMinor: 0, nextIncomeMinor: 4_000_000)); old.reportVersion = 1
            }
            for (name, amount) in [("الإيجار", 115_000), ("رحلة الشتاء", 195_000), ("الطوارئ", 40_000)] {
                guard let envelope = try c.fetch(FetchDescriptor<Envelope>()).first(where: { $0.name == name }) else { continue }
                let plan = EnvelopePlan(); plan.envelopeID = envelope.id; plan.source = "salary"; plan.kind = "fund"; plan.period = "perCycle"; plan.perPaycheckMinor = amount; plan.createdAt = now.addingTimeInterval(Double(amount)); c.insert(plan)
            }
            try c.save()
            let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
            let at = today.date(in: zone).addingTimeInterval(60)
            Task { @MainActor in
                await executeFixtureCommand(.init(name: MoneyCommandPayload.intakeName, payload: .object(["text": .string("راتب\n*5512\n40000.00 SAR\n\(f.string(from: today.date(in: zone))) 00:01"), "sender": .string("بنك الاختبار"), "receivedAt": .string(ISO8601DateFormatter().string(from: at))]), source: .shortcut, issuedAt: at))
                try? reload()
            }
        }
        if variant == "since" {
            // Away since the evening before the salary: «منذ آخر زيارة» opens first.
            let visit = DeviceSetting(); visit.key = "sys.moneyLastVisit"; visit.valueJSON = Data(("\"" + ISO8601DateFormatter().string(from: start.adding(days: -1).date(in: zone).addingTimeInterval(21 * 3600)) + "\"").utf8); c.insert(visit)
            let salary = MoneyTransaction(); salary.kind = "salary"; salary.source = "bank"; salary.reviewState = "ok"; salary.toAccountID = account.id; salary.amountMinor = 1_500_000; salary.homeAmountMinor = 1_500_000
            salary.dayKey = start.description; salary.eventAt = start.date(in: zone).addingTimeInterval(2 * 3600); salary.tzID = zone.identifier; salary.dayPolicy = "midnight@1"; salary.cycleID = cycle.id; c.insert(salary)
            let old = BankMessage(); old.sender = "بنك الاختبار"; old.channel = "shortcut"; old.kind = "purchase"; old.status = "ok"; old.receivedAt = today.adding(days: -4).date(in: zone).addingTimeInterval(13 * 3600); c.insert(old)
            let statement = BankMessage(); statement.sender = "بنك الاختبار"; statement.channel = "shortcut"; statement.kind = "statement"; statement.status = "needsLook"; statement.receivedAt = today.adding(days: -3).date(in: zone).addingTimeInterval(9 * 3600)
            statement.parsedJSON = try JSONSerialization.data(withJSONObject: ["v": 1, "kind": "statement", "last4": "8844", "statementDueMinor": 425_000, "minimumDueMinor": 21_300, "dueDate": today.adding(days: 9).date(in: zone).timeIntervalSinceReferenceDate]); c.insert(statement)
            try c.save()
        }
    }

    /// Synthetic texts through the real intake (parser, dedupe, duplicate flag), as the Shortcut would send them.
    private func seedMoneyMessages(today: GregorianDay, zone: TimeZone) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: today.date(in: zone)), due = f.string(from: today.adding(days: 12).date(in: zone))
        let texts = [
            "مرحبًا بك في خدماتنا",
            "كشف حساب البطاقة *8844\nالمبلغ المستحق: 4,250.00 SAR\nالحد الأدنى: 213.00 SAR\nتاريخ الاستحقاق: \(due)",
            "حوالة واردة\nإلى: 5512*\nمن: سالم\nمبلغ: 120 SAR\n\(day) 11:40",
            "شراء مدى Apple Pay\nبطاقة *3317\n18.50 SAR\nلدى: مخبز الحي\n\(day) 10:20",
            "شراء مدى Apple Pay\nبطاقة *3317\n42.00 SAR\nلدى: مقهى الزاوية\n\(day) 09:05",
            "شراء مدى Apple Pay\nبطاقة *3317\n42.00 SAR\nلدى: مقهى الزاوية\n\(day) 09:05",
        ]
        Task { @MainActor in
            for (index, text) in texts.enumerated() {
                let at = today.date(in: zone).addingTimeInterval(Double(9 * 3600 + index * 60))
                await executeFixtureCommand(.init(name: MoneyCommandPayload.intakeName, payload: .object(["text": .string(text), "sender": .string("بنك الاختبار"), "receivedAt": .string(ISO8601DateFormatter().string(from: at))]), source: .shortcut, issuedAt: at))
            }
            try? reload()
        }
    }
}
#endif
