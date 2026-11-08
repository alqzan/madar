import Foundation
import SwiftData
import MadarData
import MadarCore
import MadarSnapshots

extension AppSession {
    /// Financial values are omitted at construction, before the App Group JSON is encoded.
    func moneyWidgetPayload(hidden: Bool, locked: Bool = false, at now: Date) -> RoomWidgetSnapshot {
        let today = AppBahwService(session: self, evaluationDate: now).today, dates = dateLabels(today)
        var snapshot = RoomWidgetSnapshot(datePrimary: dates.primary, dateSecondary: dates.secondary, heading: "يومك", emptyTitle: "ابدأ صفحة مالك", locked: locked)
        if locked { return snapshot }
        if hidden {
            let accounts = (try? ModelContext(container).fetch(FetchDescriptor<Account>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil }))) ?? []
            guard !accounts.isEmpty else { return snapshot }
            snapshot.rows = ["لك الآن", "يومك", "صافي رصيدك", "المحجوز", "الاحتياطي", "دخل الدورة", "المظاريف", "حدود الصرف"].enumerated().map { .init(id: ["now", "daily", "basis", "reserved", "reserve", "salary", "env-hidden", "limit-hidden"][$0.offset], title: $0.element, value: "•••", route: "madar://mal") }
            return snapshot
        }
        let service = AppMoneyService(app: self)
        guard let reading = try? service.load(at: now) else { snapshot.emptyTitle = "افتح المال للتحديث"; return snapshot }
        guard reading.hasAccounts || reading.cycle != nil else { return snapshot }
        if let cycle = reading.cycle {
            snapshot.rows += [.init(id: "salary", title: "دخل الدورة", value: service.amount(cycle.incomeMinor), route: "madar://mal"), .init(id: "now", title: "لك الآن", value: service.amount(cycle.headline.availableNowMinor), route: "madar://mal"), .init(id: "daily", title: "يومك", value: service.amount(cycle.headline.todayAllowanceMinor), detail: service.amount(cycle.headline.todaySpentMinor), share: cycle.headline.todayAllowanceMinor > 0 ? Double(cycle.headline.todaySpentMinor) / Double(cycle.headline.todayAllowanceMinor) : (cycle.headline.todaySpentMinor > 0 ? 1.01 : 0), route: "madar://mal")]
            let actual = cycle.curve.filter { $0.day <= cycle.elapsedDays }
            let high = max(1, actual.map { abs($0.accruedMinor + cycle.input.carryMinor - $0.spentMinor) }.max() ?? 1)
            snapshot.periods = actual.map { .init(id: String($0.day), title: "", value: "", share: Double($0.accruedMinor + cycle.input.carryMinor - $0.spentMinor) / Double(high), route: "madar://mal") }
        }
        snapshot.rows += [.init(id: "basis", title: "صافي رصيدك", value: service.amount(reading.basis.netMinor), route: "madar://mal"), .init(id: "reserved", title: "المحجوز", value: service.amount(reading.basis.reservedMinor), route: "madar://mal"), .init(id: "reserve", title: "الاحتياطي", value: service.amount(reading.reserveMinor), route: "madar://mal")]
        snapshot.rows += reading.envelopes.prefix(2).map { .init(id: "env-" + $0.id.uuidString, title: $0.name, value: service.amount($0.balanceMinor), route: "madar://mal") }
        let limits = reading.limits.filter { $0.limitMinor > 0 }.sorted { Double($0.spentMinor) / Double($0.limitMinor) > Double($1.spentMinor) / Double($1.limitMinor) }
        snapshot.rows += limits.prefix(2).map { .init(id: "limit-" + $0.id.uuidString, title: $0.title, value: service.amount($0.spentMinor) + " من " + service.amount($0.limitMinor), route: "madar://mal") }
        return snapshot
    }
}
