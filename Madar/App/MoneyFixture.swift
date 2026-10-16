#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData

extension AppSession {
    /// Named synthetic stores only. Never reads or writes the owner's store.
    func prepareMoneyFixture(group: URL) throws {
        guard let variant = ProcessInfo.processInfo.environment["MADAR_UI_MONEY_FIXTURE"], ["showcase", "empty", "hidden", "zero"].contains(variant), group.deletingLastPathComponent().lastPathComponent == "UITestStores" else { return }
        let c = ModelContext(container)
        guard !(try c.fetch(FetchDescriptor<DeviceSetting>())).contains(where: { $0.key == "sys.moneyFixture" }) else { return }
        for key in ["sys.moneyFixture", "sys.onboardingCompleted"] { let marker = DeviceSetting(); marker.key = key; marker.valueJSON = Data("true".utf8); c.insert(marker) }
        _ = try SettingsStore(context: c).stage(["core.dayStart": .string("midnight"), "core.faceIDLock": .string("none"), "core.hideMoneyUntilTouch": .bool(variant == "hidden")])
        guard variant != "empty" else { try c.save(); return }
        let zone = ActivePlace.riyadh.timeZone, now = prayerNow(), today = GregorianDay.containing(prayerNow(), in: ActivePlace.riyadh.timeZone)
        let start = today.adding(days: -5), end = start.adding(days: 30)
        let account = Account(); account.name = "الحساب الجاري"; account.balanceMinor = 12_850_000; account.balanceAt = now; c.insert(account)
        let cycle = Cycle(); cycle.start = start.date(in: zone); cycle.expectedEnd = end.date(in: zone); cycle.incomeMinor = 1_500_000; cycle.dailyAllowanceMinor = variant == "zero" ? 0 : 41_300; cycle.createdAt = cycle.start; c.insert(cycle)
        let policy = CyclePolicy(); policy.cycleID = cycle.id; policy.effectiveFromDayKey = start.description; policy.allowanceMinor = cycle.dailyAllowanceMinor; policy.dailyRateMinor = cycle.dailyAllowanceMinor; c.insert(policy)
        func allocation(_ amount: Int, _ target: String, id: UUID? = nil, tx: UUID? = nil, kind: String = "fund") {
            let a = Allocation(); a.amountMinor = amount; a.target = target; a.targetID = id; a.transactionID = tx; a.cycleID = cycle.id; a.kind = kind; a.idempotencyKey = UUID().uuidString; c.insert(a)
        }
        for (role, title, balance) in [("reserve", "الاحتياطي", 10_000_000), ("surplus", "الفائض", 260_000)] { let e = Envelope(); e.role = role; e.name = title; c.insert(e); allocation(balance, role) }
        for (index, title, balance, target) in [(0, "الإيجار", -90_000, 180_000), (1, "رحلة الشتاء", -40_000, 200_000), (2, "الطوارئ", 120_000, 180_000), (3, "هدية", 46_000, 60_000)] {
            let e = Envelope(); e.name = title; e.role = "goal"; e.targetMinor = target; e.due = end.adding(days: index * 10).date(in: zone); e.createdAt = now.addingTimeInterval(Double(index)); c.insert(e); allocation(balance, "envelope", id: e.id)
        }
        let planEnvelope = try c.fetch(FetchDescriptor<Envelope>()).first { $0.name == "رحلة الشتاء" }!
        let plan = EnvelopePlan(); plan.envelopeID = planEnvelope.id; plan.source = "daily"; plan.period = "perDay"; plan.perPaycheckMinor = variant == "zero" ? 0 : 1300; plan.startDayKey = start.description; c.insert(plan)
        var categories: [MadarData.Category] = []
        for (index, title) in ["مطاعم", "بقالة", "بنزين", "أخرى"].enumerated() { let category = MadarData.Category(); category.name = title; category.order = index; c.insert(category); categories.append(category); let limit = CategoryLimit(); limit.categoryID = category.id; limit.limitMinor = [300_000, 400_000, 200_000, 500_000][index]; c.insert(limit) }
        for (index, spent) in [30_000, 12_000, 15_000, 22_000, 11_000, 14_000].enumerated() {
            let tx = MoneyTransaction(); tx.dayKey = start.adding(days: index).description; tx.eventAt = start.adding(days: index).date(in: zone).addingTimeInterval(9 * 3600); tx.cycleID = cycle.id; tx.fromAccountID = account.id; tx.amountMinor = spent; tx.homeAmountMinor = spent; tx.categoryID = categories[index % categories.count].id; tx.method = "transfer"; tx.source = "manual"; tx.reviewState = "ok"; tx.tzID = zone.identifier; tx.dayPolicy = "midnight@1"; c.insert(tx); allocation(-spent, "daily", tx: tx.id, kind: "spend")
        }
        for (index, title, amount) in [(0, "قسط القرض", 285_000), (1, "الكهرباء", 22_000), (2, "الاتصال", 19_000)] {
            let o = Obligation(); o.name = title; o.kind = index == 0 ? "loan" : "bill"; o.amountMinor = amount; o.dueDay = min(28, today.day + index + 2); c.insert(o)
            if index == 0 { let item = InstallmentItem(); item.obligationID = o.id; item.amountMinor = amount; item.dueDate = today.adding(days: 2).date(in: zone); c.insert(item) }
        }
        let m = BankMessage(); m.text = "شراء اصطناعي ينتظر التوزيع"; m.kind = "purchase"; m.status = "needsLook"; m.receivedAt = now; c.insert(m)
        try c.save()
    }
}
#endif
