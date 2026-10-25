#if DEBUG
import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// Owner money trial (item 17, 23 Oct 2026). Runs only in a DEBUG build, only in an isolated UI-test store, and only
/// when MADAR_TRIAL_MONEY names the old backup on this Mac. Never a registered command, URL or Shortcut. Writes a
/// counts-only report next to the backup (the git-ignored owner-data folder).
extension AppSession {
    func runLegacyMoneyTrialIfRequested() async {
        let env = ProcessInfo.processInfo.environment
        guard env["MADAR_UI_STORE_ID"] != nil, let path = env["MADAR_TRIAL_MONEY"], !path.isEmpty else { return }
        var counts: [String: Int] = [:]
        do {
            let zone = activePlace.timeZone
            let plan = try LegacyMoneyImport.plan(backup: Data(contentsOf: URL(fileURLWithPath: path)), existing: [], timeZone: zone, uuid: StableIdentity.uuid(for:))
            counts = try await importLegacyMoney(Data(contentsOf: URL(fileURLWithPath: path)), now: Date())
            var cycleExpected: [String: MadarCore.JSONValue] = [:]
            if let settings = plan.cycleSettings {
                if let daily = settings.daily {
                    cycleExpected["mal.dailyAllowance"] = .object(["mode": .string(daily.mode),
                        "amountMinor": daily.amountMinor.map { .number(Double($0)) } ?? .null,
                        "percentBp": daily.percentBp.map { .number(Double($0)) } ?? .null])
                }
                if let day = settings.salaryDay { cycleExpected["mal.salaryDay"] = .number(Double(day)) }
                if settings.gregorian { cycleExpected["mal.cycleCalendar"] = .string("gregorian") }
            }
            try reload(); try publishSnapshot()
            let check = ModelContext(container)
            counts["store.transactions"] = try check.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil }.count
            counts["store.categories"] = try check.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil }.count
            // The stored day follows core.dayStart (a message before Fajr belongs to the previous day); count every row
            // whose day differs from the old app's date so the owner sees the difference instead of a silent shift.
            let oldDays = plan.steps.reduce(into: [UUID: String]()) { days, step in
                let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.timeZone = zone; f.dateFormat = "yyyy-MM-dd"
                switch step { case let .ingest(_, _, _, at, id, _): days[id] = f.string(from: at); case let .logExpense(command, _, _, _, at, _): days[command] = f.string(from: at); default: break }
            }
            for row in try check.fetch(FetchDescriptor<MoneyTransaction>()) where row.deletedAt == nil {
                guard let old = oldDays[row.id] else { continue }
                counts[row.dayKey == old ? "day.same" : "day.shifted", default: 0] += 1
            }
            counts["store.unconfirmed"] = try check.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.reviewState != "ok" }.count
            counts["store.possibleDuplicates"] = try check.fetch(FetchDescriptor<MoneyTransaction>()).filter { $0.deletedAt == nil && $0.reviewState == "possibleDuplicate" }.count
            counts["store.cycles"] = try check.fetch(FetchDescriptor<Cycle>()).filter { $0.deletedAt == nil }.count
            let accounts = try check.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            counts["store.knownBalances"] = accounts.filter { $0.balanceAt != nil }.count
            counts["store.unknownBalances"] = accounts.filter { $0.balanceAt == nil }.count
            counts["store.settings"] = try check.fetch(FetchDescriptor<Setting>()).filter { $0.deletedAt == nil }.count
            counts["store.importLinks"] = try check.fetch(FetchDescriptor<ImportLink>()).filter { $0.deletedAt == nil }.count
            counts["settings.mapped"] = cycleExpected.count
            let storedSettings = try SettingsStore(context: check)
            counts["settings.persisted"] = try cycleExpected.allSatisfy { key, value in
                try storedSettings.value(for: key) == JSONDecoder().decode(MadarData.JSONValue.self, from: JSONEncoder().encode(value))
            } ? 1 : 0
            if let settings = plan.cycleSettings {
                counts["settings.archiveMatches"] = try check.fetch(FetchDescriptor<ImportLink>()).contains { $0.id == settings.archiveID && $0.deletedAt == nil && $0.unmappedJSON == settings.archive } ? 1 : 0
            }
        } catch { counts["failed"] = 1; counts["failed." + String(describing: type(of: error))] = 1 }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let stamp = env["MADAR_TRIAL_RUN"] ?? "run"
        try? encoder.encode(counts).write(to: URL(fileURLWithPath: path).deletingLastPathComponent().appendingPathComponent("money-import-\(stamp).json"))
    }
}
#endif
