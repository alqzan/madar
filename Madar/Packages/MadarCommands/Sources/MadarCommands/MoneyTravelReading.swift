import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney

extension MoneyRepository {
    public func trip(at instant: Date) throws -> Trip? {
        try context.fetch(FetchDescriptor<Trip>()).filter {
            $0.deletedAt == nil && $0.mergedInto == nil && !$0.dismissed && $0.start.map { $0 <= instant } == true && ($0.end == nil || instant < $0.end!)
        }.max { ($0.start ?? .distantPast) < ($1.start ?? .distantPast) }
    }
    /// Latest explicit rate by currency, including returned trips; the date is always visible at the editor.
    /// No market rate is fetched or guessed. An explicit caller override takes precedence.
    public func manualRates(at instant: Date) throws -> [String: String] {
        let trips = try context.fetch(FetchDescriptor<Trip>()).filter {
            $0.deletedAt == nil && $0.mergedInto == nil && !$0.dismissed && $0.start.map { $0 <= instant } == true && ($0.fxSetAt ?? .distantPast) <= instant
        }.sorted { ($0.fxSetAt ?? .distantPast, $0.id.uuidString) < ($1.fxSetAt ?? .distantPast, $1.id.uuidString) }
        var rates: [String: String] = [:]
        for trip in trips { if let code = trip.currency, let rate = trip.fxRateToHome, (try? FX.parseRate(rate)) != nil { rates[code] = rate } }
        return rates
    }
    public func tripEnvelope(_ trip: Trip) throws -> Envelope? {
        try context.fetch(FetchDescriptor<Envelope>()).first { $0.id == trip.id && $0.role == "trip" && $0.deletedAt == nil && $0.mergedInto == nil }
    }
}
