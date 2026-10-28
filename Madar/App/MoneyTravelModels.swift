import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyTripMovement: Identifiable {
    var id: UUID
    var day: GregorianDay
    var eventAt: Date
    var name: String
    var homeMinor: Int
    var originalMinor: Int
    var currency: String
    var isRefund: Bool
}
struct MoneyTravelReading {
    var id: UUID
    var city: String
    var homeCity: String
    var mode: String
    var distanceKm: Int?
    var currency: String?
    var rate: String?
    var rateAt: Date?
    var start: GregorianDay
    var today: GregorianDay
    var due: GregorianDay?
    var targetMinor: Int?
    var balanceMinor: Int
    var dailyMinor: Int?
    var todaySpentMinor: Int
    var movements: [MoneyTripMovement]
    var reserveMinor: Int
    var surplusMinor: Int
    var hasEnvelope: Bool
    /// OR-09: the journey's cities in order; one city for a single-country trip.
    var legCities: [String] = []
    var days: [GregorianDay] {
        let first = max(start, today.adding(days: -30)), last = min(due ?? today.adding(days: 3), today.adding(days: 30))
        return (0...max(0, MadarCalendarDays.distance(from: first, to: last))).map { first.adding(days: $0) }
    }
}
extension AppMoneyService {
    func loadTravel() throws -> MoneyTravelReading? {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        let context = ModelContext(app.container), repo = MoneyRepository(context: context), now = app.prayerNow()
        guard let trip = try repo.trip(at: now), let began = trip.start else { return nil }
        let today = try DiaryLineRenderer.today(context: context, now: now)
        // OR-09: one journey = every leg; spending, today and the budget sum all of them, each leg keeps its own currency.
        let legs = try repo.journeyLegs(of: trip), legIDs = Set(legs.map(\.id)), key = trip.journeyKey
        // The one journey budget belongs to its first leg. Moving west must not turn its
        // saved start/due midnight into the previous civil date in the current country's zone.
        let budgetZone = TimeZone(identifier: legs.first?.tzID ?? trip.tzID) ?? app.activePlace.timeZone
        let start = GregorianDay.containing(legs.first?.start ?? began, in: budgetZone), envelope = try repo.tripEnvelope(trip)
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let all = try repo.confirmedTransactions()
        let rows = all.filter { $0.tripID.map(legIDs.contains) == true && $0.eventAt <= now && ["expense", "fee", "refund", "transfer", "withdrawal"].contains($0.kind) }.compactMap { tx -> MoneyTripMovement? in
            guard let day = try? GregorianDay(tx.dayKey) else { return nil }
            return .init(id: tx.id, day: day, eventAt: tx.eventAt, name: tx.merchant ?? tx.counterparty ?? (tx.kind == "refund" ? "مبلغ مسترد" : "مصروف"), homeMinor: tx.homeAmountMinor, originalMinor: tx.amountMinor, currency: tx.currency, isRefund: tx.kind == "refund")
        }.sorted { $0.eventAt == $1.eventAt ? $0.id.uuidString < $1.id.uuidString : $0.eventAt < $1.eventAt }
        let todayIDs = Set(all.filter { tx in
            guard tx.tripID.map(legIDs.contains) == true else { return false }
            let key = tx.kind == "refund" ? all.first(where: { $0.id == tx.relatedTransactionID })?.dayKey ?? tx.dayKey : tx.dayKey
            return key == today.description
        }.map(\.id))
        let spent = -allocations.filter { $0.targetID == key && $0.transactionID.map(todayIDs.contains) == true && ["spend", "refund"].contains($0.kind) }.reduce(0) { $0 + $1.amountMinor }
        let due = envelope?.due.map { GregorianDay.containing($0, in: budgetZone) }
        let target = envelope?.targetMinor
        let planned = due.flatMap { end in target.flatMap { TravelBudget.dailyMinor(targetMinor: $0, durationDays: MadarCalendarDays.distance(from: start, to: end) + 1, day: MadarCalendarDays.distance(from: start, to: today) + 1) } }
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        func role(_ name: String) -> Int { let ids = Set(envelopes.filter { $0.role == name }.map(\.id)); return allocations.filter { ($0.target == name && $0.targetID == nil) || $0.targetID.map(ids.contains) == true }.reduce(0) { $0 + $1.amountMinor } }
        return .init(id: trip.id, city: trip.city, homeCity: app.values["core.homeCity"]?.object?["name"]?.string ?? "مدينتك", mode: trip.mode, distanceKm: trip.homeKm.map { Int($0.rounded()) }, currency: trip.currency, rate: trip.fxRateToHome, rateAt: trip.fxSetAt,
            start: start, today: today, due: due, targetMinor: target, balanceMinor: allocations.filter { $0.targetID == key }.reduce(0) { $0 + $1.amountMinor }, dailyMinor: planned, todaySpentMinor: spent, movements: rows,
            reserveMinor: role("reserve"), surplusMinor: role("surplus"), hasEnvelope: envelope != nil, legCities: legs.map(\.city))
    }
    func currencyName(_ code: String) -> String { Locale(identifier: "ar").localizedString(forCurrencyCode: code) ?? code }
    func localizedRate(_ raw: String) -> String {
        guard app.string("core.numerals") != "western" else { return raw }
        let digits = Array("٠١٢٣٤٥٦٧٨٩")
        return raw.map { c in c.wholeNumberValue.map { String(digits[$0]) } ?? (c == "." ? "٫" : String(c)) }.joined()
    }
}
