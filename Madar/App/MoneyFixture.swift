#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands

private struct UITestBankCorpusLine: Decodable {
    let sender: String
    let date: String
    let text: String
}

extension AppSession {
    /// Named synthetic stores only. Never reads or writes the owner's store.
    func prepareMoneyFixture(group: URL) throws {
        let environment = ProcessInfo.processInfo.environment
        guard let variant = environment["MADAR_UI_MONEY_FIXTURE"], ["funding", "goal", "zakat", "zakatHidden", "travel", "travelDupTRY", "travelDupSAR", "travelMissing", "travelHidden", "travelMultiLeg", "travelMultiLegHidden", "accounts", "expense", "showcase", "empty", "hidden", "zero", "shortfall", "messages", "salarySourceFlow", "bankCorpus", "since", "rules", "salary", "budget", "cards", "cardsHidden", "analysis", "analysisHidden", "reconcile", "reconcileHidden", "bankInsights", "phase3", "cashback", "cashbackHidden", "subscriptions", "subscriptionsHidden"].contains(variant), group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let c = ModelContext(container)
        guard !(try c.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.moneyFixture" }) else { return }
        for key in ["sys.moneyFixture", "sys.onboardingCompleted"] { let marker = DeviceSetting(); marker.key = key; marker.valueJSON = Data("true".utf8); c.insert(marker) }
        let settings = try SettingsStore(context: c)
        let homeCurrencyOverride = environment["MADAR_UI_MONEY_CURRENCY"] == "USD" && ["cashback", "showcase"].contains(variant) ? "USD" : nil
        var seed: [String: MadarData.JSONValue] = ["core.dayStart": .string("midnight"), "core.hideMoneyUntilTouch": .bool(["zakatHidden", "travelHidden", "travelMultiLegHidden", "hidden", "cardsHidden", "analysisHidden", "reconcileHidden", "cashbackHidden", "subscriptionsHidden"].contains(variant))]
        if let homeCurrencyOverride {
            var home = try settings.value(for: "core.homeCity").object ?? [:]
            home["currency"] = .string(homeCurrencyOverride)
            seed["core.currency"] = .string(homeCurrencyOverride)
            seed["core.homeCity"] = .object(home)
        }
        _ = try settings.stage(seed)
        if ProcessInfo.processInfo.environment["MADAR_UI_MONEY_BLOCK_SIZE"] == "4x4" {
            let store = try SettingsStore(context: c)
            var layout = try store.value(for: "bahw.layout").object ?? [:], sizes = layout["sizes"]?.object ?? [:]
            sizes["mal"] = .string("4x4"); layout["sizes"] = .object(sizes); _ = try store.stage(["bahw.layout": .object(layout)])
        }
        guard variant != "empty" else { try c.save(); return }
        let zone = ActivePlace.riyadh.timeZone, now = prayerNow(), today = GregorianDay.containing(prayerNow(), in: ActivePlace.riyadh.timeZone)
        // «نزل الراتب» arrives at the end of a full cycle; the other variants sit five days into theirs.
        // «التحليل» sits 23 days into its cycle, after a full earlier cycle it can be compared with.
        let analysis = variant.hasPrefix("analysis")
        let start = today.adding(days: variant == "salary" ? -31 : analysis ? -23 : -5), end = start.adding(days: variant == "salary" ? 31 : 30)
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
            let e = Envelope(); if variant == "showcase", let id = UUID(uuidString: ["66666666-6666-4666-8666-666666666661", "66666666-6666-4666-8666-666666666662", "66666666-6666-4666-8666-666666666663", "66666666-6666-4666-8666-666666666664"][index]) { e.id = id }; e.name = title; e.role = "goal"; e.targetMinor = target; e.due = end.adding(days: index * 10).date(in: zone); e.createdAt = now.addingTimeInterval(Double(index)); c.insert(e); allocation(balance, "envelope", id: e.id)
        }
        let planEnvelope = try c.fetch(FetchDescriptor<Envelope>()).first { $0.name == "رحلة الشتاء" }!
        let plan = EnvelopePlan(); plan.envelopeID = planEnvelope.id; plan.source = "daily"; plan.period = "perDay"; plan.perPaycheckMinor = variant == "zero" ? 0 : 1300; plan.startDayKey = start.description; c.insert(plan)
        if variant == "funding" {
            let goals = try c.fetch(FetchDescriptor<Envelope>())
            if let gift = goals.first(where: { $0.name == "هدية" }) {
                let p = EnvelopePlan(); p.envelopeID = gift.id; p.source = "salary"; p.perPaycheckMinor = 14_000
                p.untilDate = end.date(in: zone); c.insert(p)
            }
            if let emergency = goals.first(where: { $0.name == "الطوارئ" }) {
                let p = EnvelopePlan(); p.envelopeID = emergency.id; p.source = "surplus"; p.perPaycheckMinor = 50_000; c.insert(p)
            }
        }
        var categories: [MadarData.Category] = []
        for (index, title) in ["مطاعم", "بقالة", "بنزين", "أخرى"].enumerated() { let category = MadarData.Category(); category.name = title; category.order = index; c.insert(category); categories.append(category); let limit = CategoryLimit(); limit.categoryID = category.id; limit.limitMinor = [300_000, 400_000, 200_000, 500_000][index]; c.insert(limit) }
        for (index, spent) in [30_000, 12_000, 15_000, variant == "cards" ? 52_000 : 22_000, 11_000, 14_000].enumerated() { // «cards»: day 4 passes the 413 limit so the log shows a red arch
            let tx = MoneyTransaction(); tx.dayKey = start.adding(days: index).description; tx.eventAt = start.adding(days: index).date(in: zone).addingTimeInterval(9 * 3600); tx.cycleID = cycle.id; tx.fromAccountID = account.id; tx.amountMinor = spent; tx.homeAmountMinor = spent; tx.categoryID = categories[index % categories.count].id; tx.method = "transfer"; tx.source = "manual"; tx.reviewState = "ok"; tx.tzID = zone.identifier; tx.dayPolicy = "midnight@1"; c.insert(tx); allocation(-spent, "daily", tx: tx.id, kind: "spend")
        }
        for (index, title, amount) in [(0, "قسط القرض", 285_000), (1, "الكهرباء", 22_000), (2, "الاتصال", 19_000)] {
            let o = Obligation(); o.name = title; o.kind = index == 0 ? "loan" : "bill"; o.amountMinor = amount; o.dueDay = min(28, today.day + index + 2); c.insert(o)
            if index == 0 { let item = InstallmentItem(); item.obligationID = o.id; item.amountMinor = amount; item.dueDate = today.adding(days: 2).date(in: zone); c.insert(item) }
        }
        if !["messages", "salarySourceFlow", "bankCorpus"].contains(variant) { let m = BankMessage(); m.text = "شراء اصطناعي ينتظر التوزيع"; m.kind = "purchase"; m.status = "needsLook"; m.receivedAt = now; c.insert(m) }
        account.bank = "بنك الاختبار"; account.senderIDs = ["بنك الاختبار"]; account.last4 = "5512"; account.ownership = "mine"
        if variant == "bankCorpus" {
            for name in ["Barq", "STC Pay", "STC Bank", "Tiqmo", "Drahim", "D360", "Tweeq", "urpay", "Alinma Investment", "Sukuk"] {
                let wallet = Account(); wallet.name = name; wallet.bank = name; wallet.kind = "wallet"; wallet.ownership = "mine"; wallet.tracked = true; c.insert(wallet)
            }
        }
        let debit = Card(); debit.name = "بطاقة مدى"; debit.kind = "debit"; debit.bank = "بنك الاختبار"; debit.last4 = "3317"; debit.accountID = account.id; c.insert(debit)
        let card = Card(); if variant == "cards", let id = UUID(uuidString: "55555555-5555-4555-8555-555555555551") { card.id = id }; card.name = "بطاقة المشتريات"; card.kind = "credit"; card.bank = "بنك الاختبار"; card.last4 = "8844"; card.accountID = account.id; c.insert(card)
        let statement = Statement(); statement.cardID = card.id; statement.statementMinor = 680000; statement.closeDate = start.date(in: zone).addingTimeInterval(-86400); statement.dueDate = today.adding(days: 4).date(in: zone); statement.closeDateSource = "estimated"; c.insert(statement)
        let unbilled = MoneyTransaction(); unbilled.cardID = card.id; unbilled.method = "card"; unbilled.amountMinor = 180000; unbilled.homeAmountMinor = 180000; unbilled.dayKey = today.description; unbilled.eventAt = now; unbilled.ignoredFromBudget = true; c.insert(unbilled)
        let bnpl = Obligation(); bnpl.name = "أقساط الشراء"; bnpl.provider = "Tamara"; bnpl.kind = "installment"; bnpl.totalMinor = 120000; c.insert(bnpl)
        for index in 1...3 { let item = InstallmentItem(); item.obligationID = bnpl.id; item.seq = index; item.amountMinor = 40000; item.dueDate = today.adding(days: index * 20).date(in: zone); c.insert(item) }
        try c.save()
        let cashback = variant.hasPrefix("cashback")
        if variant == "cards" || variant == "cardsHidden" || variant == "accounts" || cashback {
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
            let second = Card(); if variant == "cards", let id = UUID(uuidString: "55555555-5555-4555-8555-555555555552") { second.id = id }; second.name = "بطاقة السفر"; second.bank = "بنك الاختبار"; second.last4 = "7722"; second.kind = "credit"; second.accountID = account.id; second.limitMinor = 1_000_000; second.cashbackBp = 150; second.network = "Mastercard"
            second.fieldSourcesJSON = try JSONSerialization.data(withJSONObject: ["limitMinor": "entered", "cashbackBp": "entered"]); c.insert(second)
            for offset in [-1, 0] {
                let s = Statement(); s.cardID = second.id; s.closeDate = calendar.date(byAdding: .month, value: offset, to: today.adding(days: -2).date(in: zone))!; s.periodStart = calendar.date(byAdding: .month, value: -1, to: s.closeDate); s.dueDate = calendar.date(byAdding: .month, value: offset, to: today.adding(days: 16).date(in: zone)); s.statementMinor = 180_000; s.minimumDueMinor = 9_000; s.closeDateSource = "message"; c.insert(s)
            }
            let message = BankMessage(); message.sender = "بنك الاختبار"; message.status = "ok"; message.text = "كشف تجريبي مجهّل: المبلغ المستحق 6800 SAR، الحد الأدنى 213 SAR"; message.kind = "statement"; message.receivedAt = statement.closeDate; c.insert(message); statement.messageID = message.id
            try c.save()
        }
        if cashback, let travel = try c.fetch(FetchDescriptor<Card>()).first(where: { $0.name == "بطاقة السفر" }) {
            // About four months of card purchases: everyday shops on the 0.5% card, online and travel on the 1.5% one, two
            // purchases on the debit card whose rate is unknown, one linked refund, one landed cashback (a movement with its
            // redeemed row, counted once) and one month the bank recorded as earned.
            func buy(_ card: Card, _ merchant: String, _ category: MadarData.Category?, _ daysAgo: Int, _ amount: Int, kind: String = "expense", related: UUID? = nil) -> MoneyTransaction {
                let day = today.adding(days: -daysAgo), tx = MoneyTransaction(); tx.kind = kind; tx.cardID = card.id; tx.method = "card"; tx.merchant = merchant; tx.categoryID = category?.id
                tx.amountMinor = amount; tx.homeAmountMinor = amount; tx.dayKey = day.description; tx.eventAt = day.date(in: zone).addingTimeInterval(13 * 3600); tx.tzID = zone.identifier
                tx.dayPolicy = "midnight@1"; tx.source = "bank"; tx.ignoredFromBudget = true; tx.relatedTransactionID = related; c.insert(tx); return tx
            }
            for n in 0..<30 {
                let ago = 118 - n * 4
                _ = buy(card, ["سوق الحي", "مطعم الريف", "محطة الشمال", "سوق المدينة"][n % 4], categories[[1, 0, 2, 1][n % 4]], ago, [42_000, 18_500, 14_000, 61_000][n % 4] + (n % 5) * 1_500)
                if n % 3 == 0 { _ = buy(travel, ["متجر إلكتروني", "حجز فندق", "تذاكر الطيران"][n % 9 / 3], categories[3], ago - 1, [38_000, 96_000, 152_000][n % 9 / 3]) }
            }
            let returned = buy(card, "متجر الأجهزة", categories[3], 60, 90_000)
            _ = buy(card, "متجر الأجهزة", categories[3], 52, 30_000, kind: "refund", related: returned.id)
            _ = buy(debit, "مخبز الحي", categories[1], 20, 4_500); _ = buy(debit, "مقهى الزاوية", categories[0], 9, 2_300)
            // «cashbackHidden» keeps the owner's realistic state: rates and purchases, nothing landed yet.
            if variant == "cashback" {
            let landed = MoneyTransaction(); landed.kind = "cashback"; landed.cardID = card.id; landed.method = "card"; landed.merchant = "استرداد نقدي"; landed.amountMinor = 3_500; landed.homeAmountMinor = 3_500
            landed.dayKey = today.adding(days: -34).description; landed.eventAt = today.adding(days: -34).date(in: zone).addingTimeInterval(10 * 3600); landed.tzID = zone.identifier; landed.dayPolicy = "midnight@1"; landed.source = "bank"; c.insert(landed)
            let redeemed = CashbackEntry(); redeemed.cardID = card.id; redeemed.kind = "redeemed"; redeemed.amountMinor = 3_500; redeemed.eventAt = landed.eventAt; redeemed.transactionID = landed.id; c.insert(redeemed)
            }
            let recorded = CashbackEntry(); recorded.cardID = travel.id; recorded.kind = "earned"; recorded.amountMinor = 4_200; recorded.eventAt = today.adding(days: -100).date(in: zone).addingTimeInterval(9 * 3600); c.insert(recorded)
            let destination = Envelope(); destination.name = "رحلة قادمة"; destination.role = "goal"; destination.targetMinor = 500_000; c.insert(destination)
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
        if analysis {
            // The earlier cycle (start − 30 … start − 1) gets its policy and expected end; spending is synthetic and daily-only.
            guard let previous = try c.fetch(FetchDescriptor<Cycle>()).first(where: { $0.closedAt != nil && $0.end == start.date(in: zone) }) else { try c.save(); return }
            previous.expectedEnd = previous.end; previous.incomeMinor = 1_500_000
            let earlier = CyclePolicy(); earlier.cycleID = previous.id; earlier.effectiveFromDayKey = start.adding(days: -30).description; earlier.allowanceMinor = 40_000; earlier.dailyRateMinor = 40_000; c.insert(earlier)
            func spend(_ merchant: String, _ category: MadarData.Category, _ day: GregorianDay, _ amount: Int, cycle owner: Cycle, hour: Int) {
                let tx = MoneyTransaction(); tx.merchant = merchant; tx.categoryID = category.id; tx.reviewState = "ok"; tx.source = "bank"; tx.method = "transfer"; tx.fromAccountID = account.id
                tx.amountMinor = amount; tx.homeAmountMinor = amount; tx.cycleID = owner.id; tx.dayKey = day.description; tx.eventAt = day.date(in: zone).addingTimeInterval(Double(hour * 3600))
                tx.tzID = zone.identifier; tx.dayPolicy = "midnight@1"; c.insert(tx)
                let a = Allocation(); a.amountMinor = -amount; a.target = "daily"; a.transactionID = tx.id; a.cycleID = owner.id; a.kind = "spend"; a.idempotencyKey = UUID().uuidString; c.insert(a)
            }
            let shops: [(String, Int)] = [("بقالة الحي", 1), ("محطة الشمال", 2), ("مطعم الريف", 0), ("سوق المدينة", 3), ("بقالة الحي", 1), ("متجر الكتب", 3), ("مخبز الحي", 1)]
            // The base fixture's six purchases (days 0–5) take merchants; days 6–23 follow, a coffee most days plus one shop.
            for (index, tx) in try c.fetch(FetchDescriptor<MoneyTransaction>()).filter({ $0.cycleID == cycle.id }).sorted(by: { $0.dayKey < $1.dayKey }).enumerated() {
                tx.merchant = shops[index % shops.count].0; tx.categoryID = categories[shops[index % shops.count].1].id; tx.source = "bank"
            }
            let current = [38_000, 26_000, 61_000, 33_000, 29_000, 45_000, 18_000, 34_000, 72_000, 31_000, 25_000, 39_000, 28_000, 36_000, 52_000, 30_000, 24_000, 18_000]
            for (offset, total) in current.enumerated() {
                let day = start.adding(days: 6 + offset), coffee = offset % 3 == 2 ? 0 : 2_200 + (offset % 4) * 300
                if coffee > 0 { spend("مقهى الزاوية", categories[0], day, coffee, cycle: cycle, hour: 8) }
                let shop = shops[offset % shops.count]; spend(shop.0, categories[shop.1], day, total - coffee, cycle: cycle, hour: 17)
            }
            let earlierDays = [42_000, 38_000, 30_000, 51_000, 36_000, 40_000, 29_000, 47_000, 39_000, 33_000]
            for index in 0..<30 {
                let day = start.adding(days: index - 30), total = earlierDays[index % earlierDays.count] + (index % 3) * 1_000
                spend("مقهى الزاوية", categories[0], day, 2_500, cycle: previous, hour: 8)
                let shop = shops[(index + 2) % shops.count]; spend(shop.0, categories[shop.1], day, total - 2_500, cycle: previous, hour: 18)
            }
            try c.save()
        }
        if variant.hasPrefix("reconcile") {
            // «المطابقة»: the account was last reconciled 40 days ago; the newest bank message printed a balance 320 below
            // Madar's book, and a 320 draft still waits. A wallet and a second credit card complete the record.
            let checked = today.adding(days: -40).date(in: zone).addingTimeInterval(10 * 3600)
            account.balanceAt = checked; account.balanceMinor = 12_995_000
            let last = Reconciliation(); last.accountID = account.id; last.at = checked; last.expectedMinor = 12_995_000; last.observedMinor = 12_995_000; last.resolution = "adjust"; c.insert(last)
            let message = BankMessage(); message.sender = "بنك الاختبار"; message.kind = "purchase"; message.status = "ok"; message.receivedAt = now.addingTimeInterval(-3600)
            message.text = "شراء مدى اصطناعي\nبطاقة *3317\n90.00 SAR\nلدى: مخبز الحي\nالرصيد: 128500.00 SAR"
            message.parsedJSON = try JSONSerialization.data(withJSONObject: ["v": 1, "kind": "purchase", "amountMinor": 9_000, "balanceMinor": 12_850_000]); c.insert(message)
            let bread = MoneyTransaction(); bread.merchant = "مخبز الحي"; bread.messageID = message.id; bread.cardID = debit.id; bread.fromAccountID = account.id; bread.method = "card"; bread.source = "bank"; bread.reviewState = "ok"
            bread.amountMinor = 9_000; bread.homeAmountMinor = 9_000; bread.cycleID = cycle.id; bread.dayKey = today.description; bread.eventAt = now.addingTimeInterval(-3600); bread.tzID = zone.identifier; bread.dayPolicy = "midnight@1"; c.insert(bread)
            allocation(-9_000, "daily", tx: bread.id, kind: "spend")
            let waiting = MoneyTransaction(); waiting.merchant = "صيدلية الحي"; waiting.fromAccountID = account.id; waiting.method = "transfer"; waiting.source = "bank"; waiting.reviewState = "needsLook"
            waiting.amountMinor = 32_000; waiting.homeAmountMinor = 32_000; waiting.dayKey = today.adding(days: -1).description; waiting.eventAt = today.adding(days: -1).date(in: zone).addingTimeInterval(17 * 3600); waiting.tzID = zone.identifier; waiting.dayPolicy = "midnight@1"; c.insert(waiting)
            let wallet = Account(); wallet.name = "المحفظة الرقمية"; wallet.kind = "wallet"; wallet.ownership = "mine"; wallet.bank = "محفظة الاختبار"; wallet.balanceMinor = 134_000; wallet.balanceAt = today.adding(days: -12).date(in: zone); c.insert(wallet)
            let travel = Card(); travel.name = "بطاقة السفر"; travel.kind = "credit"; travel.bank = "بنك الاختبار"; travel.last4 = "7722"; travel.accountID = account.id; c.insert(travel)
            let travelStatement = Statement(); travelStatement.cardID = travel.id; travelStatement.statementMinor = 115_000; travelStatement.closeDate = today.adding(days: -3).date(in: zone); travelStatement.dueDate = today.adding(days: 18).date(in: zone); c.insert(travelStatement)
            try c.save()
        }
        if variant == "messages" || variant == "salarySourceFlow" { seedMoneyMessages(today: today, zone: zone, salarySourceFlow: variant == "salarySourceFlow") }
        if variant == "bankCorpus" { seedCorpusBankMessages() }
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
        if variant == "accounts" {
            if ProcessInfo.processInfo.environment["MADAR_UI_UNKNOWN_BALANCE"] == "1" { account.balanceAt = nil; account.balanceMinor = 0 }
            let wallet = Account(); wallet.name = "المحفظة الرقمية"; wallet.kind = "wallet"; wallet.balanceAt = cycle.start; c.insert(wallet)
            let other = Account(); other.name = "حساب آخر"; other.bank = "بنك الاختبار"; other.last4 = "9999"; other.ownership = "notMine"; other.balanceMinor = 1_420_000; other.balanceAt = cycle.start; c.insert(other); try c.save()
            if ProcessInfo.processInfo.environment["MADAR_UI_WRAPPED_ACCOUNTS"] == "1" {
                for index in 1...7 {
                    let extra = Account()
                    extra.name = "حساب الادخار للأهداف البعيدة " + String(index)
                    extra.bank = "مصرف الاختبار"; extra.last4 = String(7000 + index)
                    extra.balanceAt = cycle.start; extra.balanceMinor = index * 10_000
                    c.insert(extra)
                }
                try c.save()
            }
        }
        if variant == "expense" {
            let cash = Account(); cash.name = "محفظة النقد"; cash.kind = "cash"; cash.balanceMinor = 30_000; cash.balanceAt = cycle.start; c.insert(cash)
            for (index, name) in ["مقهى الزاوية", "متجر الحي", "محطة الشمال"].enumerated() {
                let row = MoneyTransaction(); row.source = "manual"; row.reviewState = "ok"; row.method = "card"; row.cardID = debit.id; row.fromAccountID = account.id; row.merchant = name; row.categoryID = categories[index].id; row.amountMinor = 2_000; row.homeAmountMinor = 2_000; row.dayKey = today.adding(days: -1).description; row.eventAt = now.addingTimeInterval(-86_400 - Double(index)); c.insert(row)
            }
            try c.save()
        }
        if variant.hasPrefix("zakat") {
            let profile = ZakatProfile(); profile.goldPricePerGramMinor = 40000; profile.goldPriceSetAt = now.addingTimeInterval(-40*86400); profile.debtsPolicy = "none"; profile.hawlStartHijri = "h:1447-09-01"; c.insert(profile); try c.save()
        }
        if variant.hasPrefix("travel") {
            let multiLeg = variant.hasPrefix("travelMultiLeg")
            let trip = Trip(); trip.city = "إسطنبول"; trip.country = "تركيا"; trip.currency = variant == "travelMissing" ? nil : "TRY"; trip.fxRateToHome = variant == "travelMissing" ? nil : "0.1"; trip.fxSetAt = now.addingTimeInterval(-86400); trip.lat = 41.0082; trip.lon = 28.9784; trip.tzID = "Europe/Istanbul"; trip.start = today.adding(days: -3).date(in: zone); trip.mode = "auto"; trip.homeKm = 2450; c.insert(trip)
            let e = Envelope(); e.id = trip.id; e.role = "trip"; e.name = "رحلة إسطنبول"; e.targetMinor = 500_000; e.due = today.adding(days: 3).date(in: zone); c.insert(e); allocation(500_000, "envelope", id: e.id)
            for (index, foreignAmount, name) in [(0, 77000, "فطور"), (1, 27500, "قهوة"), (2, 126500, "زيارة البرج")] {
                let tx = MoneyTransaction(); tx.tripID = trip.id; tx.currency = "TRY"; tx.amountMinor = foreignAmount; tx.homeAmountMinor = foreignAmount / 10; tx.rateAtTime = "0.1"; tx.rateSource = "trip"; tx.dayKey = today.description; tx.eventAt = now.addingTimeInterval(Double(-3600 * (index+1))); tx.tzID = trip.tzID; tx.dayPolicy = "midnight@1"; tx.merchant = name; tx.cardID = card.id; tx.method = "card"; tx.reviewState = "ok"; tx.cycleID = cycle.id; c.insert(tx); allocation(-tx.homeAmountMinor, "envelope", id: e.id, tx: tx.id, kind: "spend")
                if multiLeg {
                    tx.dayKey = today.adding(days: -1).description
                    tx.eventAt = today.adding(days: -1).date(in: zone).addingTimeInterval(Double(3600 * (index + 12)))
                }
            }
            if variant == "travelDupTRY" || variant == "travelDupSAR" {
                let inTripCurrency = variant == "travelDupTRY"
                let duplicate = MoneyTransaction(); duplicate.kind = "expense"; duplicate.source = "manual"; duplicate.reviewState = "ok"
                duplicate.tripID = inTripCurrency ? trip.id : nil; duplicate.currency = inTripCurrency ? "TRY" : "SAR"; duplicate.homeCurrency = "SAR"
                duplicate.amountMinor = 42_500; duplicate.homeAmountMinor = inTripCurrency ? 4_250 : 42_500
                if inTripCurrency { duplicate.rateAtTime = "0.1"; duplicate.rateSource = "trip" }
                duplicate.dayKey = today.description; duplicate.eventAt = now.addingTimeInterval(-300); duplicate.tzID = trip.tzID; duplicate.dayPolicy = "midnight@1"
                duplicate.merchant = "TripTest"; duplicate.cardID = card.id; duplicate.method = "card"; duplicate.cycleID = cycle.id; c.insert(duplicate)
            }
            if multiLeg {
                let next = Trip(); next.journeyID = trip.id; next.city = "باريس"; next.country = "فرنسا"
                next.lat = 48.8566; next.lon = 2.3522; next.tzID = "Europe/Paris"; next.start = now.addingTimeInterval(-3600)
                next.currency = "EUR"; next.fxRateToHome = "4"; next.fxSetAt = next.start; next.mode = "auto"
                trip.end = next.start; c.insert(next)
                // Explicit synthetic rates: TRY 2,310 → SAR 231; EUR 25 → SAR 100.
                // One SAR 5,000 envelope therefore has SAR 4,669 left across both legs.
                let tx = MoneyTransaction(); tx.tripID = next.id; tx.currency = "EUR"; tx.amountMinor = 2500
                tx.homeAmountMinor = 10000; tx.rateAtTime = "4"; tx.rateSource = "trip"; tx.dayKey = today.description
                tx.eventAt = now.addingTimeInterval(-1800); tx.tzID = next.tzID; tx.dayPolicy = "midnight@1"
                tx.merchant = "متحف باريس"; tx.cardID = card.id; tx.method = "card"; tx.reviewState = "ok"; tx.cycleID = cycle.id
                c.insert(tx); allocation(-10000, "envelope", id: e.id, tx: tx.id, kind: "spend")
            }
            try c.save()
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
        if variant == "bankInsights" {
            // Owner, 11 Nov 2026: a bank message printed a balance 320 below the book, and a bill is due in two days.
            account.balanceAt = now.addingTimeInterval(-2 * 86_400)
            let printed = BankReading(); printed.accountID = account.id; printed.balanceAt = now.addingTimeInterval(-3600)
            printed.balanceMinor = account.balanceMinor - 32_000; c.insert(printed)
            let bill = UpcomingDue(); bill.payee = "فاتورة الاختبار"; bill.kind = "bill"; bill.amountMinor = 21_500; bill.currency = "SAR"
            bill.dueAt = today.adding(days: 2).date(in: zone).addingTimeInterval(12 * 3600); c.insert(bill)
            try c.save()
        }
        if variant == "phase3" {
            // Owner, 11 Nov 2026, phase 3 (invented data): a salary and two subscriptions repeating monthly (one with a price rise, one late),
            // an instalment and a card statement among the dues, a refund that two purchases could explain, and a foreign purchase with fees.
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            func at(_ days: Int, months: Int = 0) -> Date { calendar.date(byAdding: .month, value: months, to: today.adding(days: days).date(in: zone))!.addingTimeInterval(12 * 3600) }
            func movement(_ kind: String, _ merchant: String, _ amount: Int, _ date: Date) -> MoneyTransaction {
                let row = MoneyTransaction(); row.kind = kind; row.source = "bank"; row.reviewState = "ok"; row.method = "transfer"
                row.fromAccountID = kind == "salary" ? nil : account.id; row.toAccountID = kind == "salary" ? account.id : nil
                if kind == "salary" { row.counterparty = merchant } else { row.merchant = merchant }
                row.amountMinor = amount; row.homeAmountMinor = amount; row.currency = "SAR"; row.homeCurrency = "SAR"
                row.eventAt = date; row.dayKey = GregorianDay.containing(date, in: zone).description; row.tzID = zone.identifier; row.dayPolicy = "midnight@1"; c.insert(row); return row
            }
            for months in [-3, -2, -1] { _ = movement("salary", "جهة العمل", 1_500_000, at(-1, months: months + 1)) }
            for (index, months) in [-2, -1, 0].enumerated() { _ = movement("expense", "منصة شاهد", index == 2 ? 49_900 : 39_900, at(5, months: months - 1)) }
            for months in [-3, -2, -1] { _ = movement("expense", "نادي الاختبار", 15_000, at(-2, months: months)) }
            var messageCount = 0
            func message(_ kind: String, _ fields: [String: Any]) -> BankMessage {
                messageCount += 1
                let m = BankMessage(); m.id = UUID(); m.sender = "بنك الاختبار"; m.kind = kind; m.status = "ok"; m.receivedAt = now.addingTimeInterval(-Double(messageCount) * 3600 - 7200); m.text = "رسالة اختبار مجهّلة رقم \(messageCount) من نوع " + kind
                m.parsedJSON = try? JSONSerialization.data(withJSONObject: fields.merging(["v": 1, "kind": kind]) { a, _ in a }); c.insert(m); return m
            }
            let plan = message("bnplInstalment", ["merchant": "متجر الأدوات", "provider": "Tamara", "instalmentNumber": 2, "instalmentCount": 4, "remainingMinor": 80_000])
            let instalment = UpcomingDue(); instalment.payee = "Tamara"; instalment.kind = "bnpl"; instalment.amountMinor = 40_000; instalment.currency = "SAR"
            instalment.dueAt = at(6); instalment.sourceMessageID = plan.id; c.insert(instalment)
            let statementMessage = message("statement", ["last4": "8844", "minimumDueMinor": 21_300]); statementMessage.kind = "statement"
            let statementDue = UpcomingDue(); statementDue.payee = "بطاقة المشتريات"; statementDue.kind = "bill"; statementDue.amountMinor = 425_000; statementDue.currency = "SAR"
            statementDue.dueAt = at(9); statementDue.sourceMessageID = statementMessage.id; c.insert(statementDue)
            for days in [-9, -4] { _ = movement("expense", "متجر الأدوات", 23_000, at(days)) }
            let refund = movement("refund", "متجر الأدوات", 23_000, now.addingTimeInterval(-1800)); refund.reviewState = "needsLook"; refund.fromAccountID = nil; refund.toAccountID = account.id
            refund.messageID = message("refund", ["merchant": "متجر الأدوات"]).id
            let foreign = movement("expense", "متجر خارجي", 10_000, now.addingTimeInterval(-7200)); foreign.currency = "USD"; foreign.homeAmountMinor = 37_500; foreign.rateAtTime = "3.75"
            foreign.categoryID = categories[0].id; foreign.cycleID = cycle.id; foreign.messageID = message("purchase", ["feeMinor": 500, "vatMinor": 75, "foreignFeeMinor": 1_125, "exchangeRate": "3.75"]).id
            allocation(-37_500, "daily", tx: foreign.id, kind: "spend")
            try c.save()
        }
        if variant == "subscriptions" || variant == "subscriptionsHidden" {
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            for month in [7, 8, 9] {
                guard let eventAt = calendar.date(from: DateComponents(year: 2026, month: month, day: 18, hour: 12)) else { continue }
                let row = MoneyTransaction(); row.kind = "expense"; row.source = "bank"; row.reviewState = "ok"
                row.method = "transfer"; row.fromAccountID = account.id; row.merchant = "منصة شاهد"
                row.amountMinor = 39_900; row.homeAmountMinor = 39_900; row.currency = "SAR"; row.homeCurrency = "SAR"
                row.eventAt = eventAt; row.dayKey = GregorianDay.containing(eventAt, in: zone).description
                row.tzID = zone.identifier; row.dayPolicy = "midnight@1"; c.insert(row)
            }
            try c.save()
        }
        if ProcessInfo.processInfo.environment["MADAR_UI_ALL_BALANCES_UNKNOWN"] == "1" {
            for row in try c.fetch(FetchDescriptor<Account>()) where row.ownership == "mine" && row.tracked { row.balanceAt = nil }
            try c.save()
        }
        if let homeCurrencyOverride {
            // USD and SAR both use two minor-unit digits. Keep this named synthetic fixture internally coherent
            // so the money home can load without inventing an exchange rate for its accounts or obligations.
            for account in try c.fetch(FetchDescriptor<Account>()) where account.ownership == "mine" && account.currency == "SAR" {
                account.currency = homeCurrencyOverride
            }
            for movement in try c.fetch(FetchDescriptor<MoneyTransaction>()) {
                if movement.currency == "SAR" { movement.currency = homeCurrencyOverride }
                movement.homeCurrency = homeCurrencyOverride
            }
            for obligation in try c.fetch(FetchDescriptor<Obligation>()) where obligation.currency == "SAR" {
                obligation.currency = homeCurrencyOverride
            }
            try c.save()
        }
    }

    /// Synthetic texts through the real intake (parser, dedupe, duplicate flag), as the Shortcut would send them.
    private func seedMoneyMessages(today: GregorianDay, zone: TimeZone, salarySourceFlow: Bool = false) {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
        let day = f.string(from: today.date(in: zone)), due = f.string(from: today.adding(days: 12).date(in: zone))
        var texts = [
            "مرحبًا بك في خدماتنا",
            "كشف حساب البطاقة *8844\nالمبلغ المستحق: 4,250.00 SAR\nالحد الأدنى: 213.00 SAR\nتاريخ الاستحقاق: \(due)",
            salarySourceFlow ? "حوالة واردة\nإلى: 5512*\nمن: شركة المدار\nمبلغ: 15000 SAR\n\(day) 11:40" : "حوالة واردة\nإلى: 5512*\nمن: سالم\nمبلغ: 120 SAR\n\(day) 11:40",
            "شراء مدى Apple Pay\nبطاقة *3317\n18.50 SAR\nلدى: مخبز الحي\n\(day) 10:20",
            "شراء مدى Apple Pay\nبطاقة *3317\n42.00 SAR\nلدى: مقهى الزاوية\n\(day) 09:05",
            "شراء مدى Apple Pay\nبطاقة *3317\n42.00 SAR\nلدى: مقهى الزاوية\n\(day) 09:05",
        ]
        if salarySourceFlow { texts.insert("حوالة واردة\nإلى: 5512*\nمن: شركة المدار\nمبلغ: 18000 SAR\n\(day) 12:40", at: 3) }
        Task { @MainActor in
            for (index, text) in texts.enumerated() {
                let at = today.date(in: zone).addingTimeInterval(Double(9 * 3600 + index * 60))
                await executeFixtureCommand(.init(name: MoneyCommandPayload.intakeName, payload: .object(["text": .string(text), "sender": .string("بنك الاختبار"), "receivedAt": .string(ISO8601DateFormatter().string(from: at))]), source: .shortcut, issuedAt: at))
            }
            try? reload()
        }
    }

    /// Local UI trial only: the XCTest host supplies corpus lines in the test-store launch environment.
    private func seedCorpusBankMessages() {
        let environment = ProcessInfo.processInfo.environment
        let data: Data?
        if let serialized = environment["MADAR_UI_BANK_CORPUS_LZFSE"], let packed = Data(base64Encoded: serialized),
           let expanded = try? (packed as NSData).decompressed(using: .lzfse) {
            data = expanded as Data
        } else if let serialized = environment["MADAR_UI_BANK_CORPUS"], let decoded = serialized.data(using: .utf8) {
            data = decoded
        } else {
            data = nil
        }
        guard let data,
              let lines = try? JSONDecoder().decode([UITestBankCorpusLine].self, from: data), !lines.isEmpty else { return }
        let messages: [MadarCore.JSONValue] = lines.map { line in
            .object(["text": .string(line.text), "sender": .string(line.sender), "receivedAt": .string(line.date)])
        }
        Task { @MainActor in
            // The real paste command accepts at most 500 rows per batch.
            for start in stride(from: 0, to: messages.count, by: 500) {
                let end = min(start + 500, messages.count)
                let batch = Array(messages[start..<end])
                guard await executeFixtureCommand(.init(name: "money.pasteBankMessages", payload: .object(["messages": .array(batch)]), source: .app, issuedAt: prayerNow())) else { return }
                bankCorpusImportedInputCount += batch.count
            }
            try? reload()
        }
    }
}
#endif
