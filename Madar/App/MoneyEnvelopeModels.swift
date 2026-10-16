import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands
import MadarMoney

struct MoneySurplusPoint: Identifiable {
    var id: String
    var date: GregorianDay?
    var deltaMinor: Int
    var balanceMinor: Int
}
struct MoneyEnvelopesReading {
    var home: MoneyHomeReading
    var reserveTargetMinor: Int?
    var reserve: ReserveReading
    var totalMinor: Int
    var waterfall: [MoneySurplusPoint]
}

extension AppMoneyService {
    func loadEnvelopes() throws -> MoneyEnvelopesReading {
        let now = app.prayerNow(), home = try load(at: now), context = ModelContext(app.container)
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let reserves = envelopes.filter { $0.role == "reserve" }
        let surplusIDs = Set(envelopes.filter { $0.role == "surplus" }.map(\.id))
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && ($0.target == "surplus" || $0.targetID.map(surplusIDs.contains) == true) }
        let cycles = try context.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let grouped = Dictionary(grouping: allocations, by: \.cycleID).sorted { a, b in
            let left = cycles.first { $0.id == a.key }?.start ?? .distantPast
            let right = cycles.first { $0.id == b.key }?.start ?? .distantPast
            return left == right ? (a.key?.uuidString ?? "") < (b.key?.uuidString ?? "") : left < right
        }
        var total = 0, points: [MoneySurplusPoint] = []
        for (id, rows) in grouped {
            let change = rows.reduce(0) { $0 + $1.amountMinor }; total += change
            let cycle = cycles.first { $0.id == id }
            points.append(.init(id: id?.uuidString ?? "opening", date: cycle.map { .containing($0.closedAt ?? $0.start, in: app.activePlace.timeZone) }, deltaMinor: change, balanceMinor: total))
        }
        let reserve = ReserveEngine.read(balanceMinor: home.reserveMinor, dailyMinor: home.cycle?.headline.todayAllowanceMinor,
            cycleLengthDays: home.cycle?.input.expectedLengthDays ?? 30, obligationsPerCycleMinor: home.obligationsPerCycleMinor)
        return .init(home: home, reserveTargetMinor: reserves.count == 1 ? reserves.first?.targetMinor : nil, reserve: reserve,
            totalMinor: home.reserveMinor + home.surplusMinor + home.envelopes.reduce(0) { $0 + $1.balanceMinor }, waterfall: Array(points.suffix(3)))
    }
}
