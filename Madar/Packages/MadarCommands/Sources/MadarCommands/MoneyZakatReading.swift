import Foundation
import CryptoKit
import SwiftData
import MadarCore
import MadarData
import MadarMoney

public struct MoneyZakatReading {
    public struct AccountLine: Identifiable {
        public var id: UUID
        public var name: String
        public var homeMinor: Int
        public var included: Bool
    }
    public var input: ZakatInput
    public var signature: String
    public var hasProfile: Bool
    public var accounts: [AccountLine]
}
extension MoneyRepository {
    public func zakat(at now: Date) throws -> MoneyZakatReading {
        let profile = try context.fetch(FetchDescriptor<ZakatProfile>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.sorted { $0.id.uuidString < $1.id.uuidString }.first
        let accounts = try homeAccountBalances(at: now)
        let basis = try basis(at: now), cards = try cardDebts(at: now)
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let home = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR", rates = try manualRates(at: now)
        func converted(_ n: Int, code: String) throws -> Int {
            if code == home { return n }; guard let rate = rates[code] else { throw MoneyCommandError.missingRate }
            return try FX.homeAmount(amountMinor: n, currency: code, rate: rate, home: home)
        }
        var loans = 0, due = cards.filter { $0.dueDate.map { $0 <= now } == true }.reduce(0) { $0 + $1.statementLeftMinor }
        for item in items {
            guard let obligation = obligations.first(where: { $0.id == item.obligationID }) else { continue }
            let remaining = try converted(max(0, item.amountMinor - item.paidMinor), code: obligation.currency)
            if obligation.kind == "loan" { loans += remaining }
            if item.dueDate <= now { due += remaining }
        }
        let input = ZakatInput(accounts: accounts.map { .init(balanceMinor: $0.homeMinor, include: $0.account.zakatInclude) },
            otherAssetsMinor: profile?.otherAssetsMinor ?? 0, debtsPolicy: ZakatDebtsPolicy(rawValue: profile?.debtsPolicy ?? "unset") ?? .unset,
            owedAllMinor: basis.owedMinor, dueNowMinor: due, loanRemainingMinor: loans,
            nisabBasis: NisabBasis(rawValue: profile?.nisabBasis ?? "gold") ?? .gold,
            goldPricePerGramMinor: profile?.goldPricePerGramMinor, goldPriceSetAt: profile?.goldPriceSetAt, nisabMg: profile?.nisabMg ?? 85000,
            silverPricePerGramMinor: profile?.silverPricePerGramMinor, silverPriceSetAt: profile?.silverPriceSetAt, nisabSilverMg: profile?.nisabSilverMg ?? 595000,
            hawlStartHijri: profile?.hawlStartHijri)
        return .init(input: input, signature: try Self.zakatSignature(profile), hasProfile: profile != nil,
            accounts: accounts.map { .init(id: $0.account.id, name: $0.account.name, homeMinor: $0.homeMinor, included: $0.account.zakatInclude) })
    }
    public static func zakatSignature(_ profile: ZakatProfile?) throws -> String {
        guard let profile else { return "none" }
        let e = JSONEncoder(); e.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return SHA256.hash(data: try e.encode(profile.record())).map { String(format: "%02x", $0) }.joined()
    }
}
