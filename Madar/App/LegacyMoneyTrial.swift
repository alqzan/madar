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
        func count(_ key: String) { counts[key, default: 0] += 1 }
        do {
            let context = ModelContext(container)
            let existing = try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil }
                .map { LegacyMoneyImport.Category(id: $0.id, name: $0.name, order: $0.order) }
            let zone = TimeZone(identifier: "Asia/Riyadh")!
            let plan = try LegacyMoneyImport.plan(backup: Data(contentsOf: URL(fileURLWithPath: path)), existing: existing, timeZone: zone, uuid: StableIdentity.uuid(for:))
            counts = plan.counts
            // No command creates a category in v1; the owner's own categories are inserted as data, with stable ids.
            let now = Date()
            for item in plan.createCategories {
                let row = MadarData.Category(); row.id = item.id; row.name = item.name; row.order = item.order
                row.createdAt = now; row.updatedAt = now; row.writerID = "madar.app.trial"; context.insert(row)
            }
            try context.save()
            func run(_ name: String, _ payload: [String: MadarCore.JSONValue], _ id: UUID, _ key: String) async -> String {
                let status: String
                do { status = try await executeTrialCommand(name, payload: payload, id: id) } catch { status = "error." + String(describing: error).prefix(60) }
                count(key + "." + status); return status
            }
            func arabic(_ digits: String) -> String { String(digits.map { c in c.wholeNumberValue.map { Character(UnicodeScalar(0x0660 + $0)!) } ?? c }) }
            var cycleExpected: [String: MadarCore.JSONValue] = [:]
            if let settings = plan.cycleSettings {
                // Archive source configuration, including unsupported carry/start/income/window fields, before
                // applying the exact native settings. It is local to this DEBUG UI-test store, never a new import UI.
                if try context.fetch(FetchDescriptor<ImportLink>()).contains(where: { $0.id == settings.archiveID }) {
                    count("settings.archiveExisting")
                } else {
                    let link = ImportLink(); link.id = settings.archiveID; link.source = "myDream"; link.sourceModel = "MoneyCycleSettings"
                    link.sourceID = settings.archiveID.uuidString; link.targetModel = "Setting"; link.unmappedJSON = settings.archive
                    link.createdAt = now; link.updatedAt = now; link.importedAt = now; link.writerID = "madar.app.trial"
                    context.insert(link); try context.save(); count("settings.archiveCreated")
                }
                if let daily = settings.daily {
                    cycleExpected["mal.dailyAllowance"] = .object(["mode": .string(daily.mode),
                        "amountMinor": daily.amountMinor.map { .number(Double($0)) } ?? .null,
                        "percentBp": daily.percentBp.map { .number(Double($0)) } ?? .null])
                }
                if let day = settings.salaryDay { cycleExpected["mal.salaryDay"] = .number(Double(day)) }
                if settings.gregorian { cycleExpected["mal.cycleCalendar"] = .string("gregorian") }
                if !cycleExpected.isEmpty {
                    _ = await run("settings.set", ["settings": .object(cycleExpected)], settings.command, "cycleSettings")
                }
            }
            for step in plan.steps {
                switch step {
                case let .saveAccount(command, id, kind, bank, last4, at):
                    let shownBank = bank.map { $0.uppercased() }
                    var p: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "kind": .string("current"), "ownership": .string("mine"), "currency": .string("SAR"),
                        "name": .string(kind == "earlier" ? "بطاقة غير معروفة — رسائلها غير محفوظة" : kind == "unidentified" ? "حساب بطاقة مدى — رقمه غير معروف" : "حساب " + (shownBank ?? "") + (last4.map { " " + arabic($0) } ?? "")),
                        "balanceMinor": .string("0"), "balanceAt": .string(ISO8601DateFormatter().string(from: at)), "tracked": .bool(true)]
                    if let shownBank { p["bank"] = .string(shownBank); p["senderIDs"] = .array([.string(bank!)]) }
                    if let last4 { p["last4"] = .string(last4) }
                    _ = await run("money.saveAccount", p, command, "account")
                case let .saveCard(command, id, last4, bank, kind, account):
                    var p: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "name": .string("بطاقة " + arabic(last4)), "bank": .string(bank.uppercased()),
                                                           "last4": .string(last4), "kind": .string(kind), "aliases": .array([.string(bank)])]
                    if let account { p["accountID"] = .string(account.uuidString) }
                    _ = await run("money.saveCard", p, command, "card")
                case let .saveRule(command, merchant, category):
                    _ = await run("money.saveMerchantRule", ["merchant": .string(merchant), "categoryID": .string(category.uuidString), "ignore": .bool(false)], command, "rule")
                case let .logExpense(command, amount, merchant, category, at, account):
                    var p: [String: MadarCore.JSONValue] = ["amountMinor": .string(String(amount)), "currency": .string("SAR"), "method": .string("transfer"),
                                                           "fromAccountID": .string(account.uuidString), "showInDiary": .bool(false),
                                                  "eventAt": .string(ISO8601DateFormatter().string(from: at))]
                    if let merchant { p["merchant"] = .string(merchant) }
                    if let category { p["categoryID"] = .string(category.uuidString) }
                    _ = await run("money.logExpense", p, command, "earlier")
                    // Owner, 22 Oct: these rows came from an automatic source, never typed by hand. The shipped command
                    // can only write «manual», so the trial marks the row automatic, without message text.
                    let fresh = ModelContext(container)
                    if let row = try fresh.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == command }), row.source == "manual" {
                        row.source = "bank"; row.updatedAt = Date(); try fresh.save(); count("earlier.automatic")
                    }
                    // The old rows have no card digits. Only an unambiguous merchant match supplies a card.
                    if let cardID = plan.earlierCards[command] {
                        let patch = ModelContext(container)
                        if let row = try patch.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == command }),
                           let card = try patch.fetch(FetchDescriptor<Card>()).first(where: { $0.id == cardID }), card.kind == "credit" || card.accountID != nil {
                            let account = card.kind == "credit" ? nil : card.accountID
                            if row.cardID != card.id || row.method != "card" || row.fromAccountID != account {
                                row.cardID = card.id; row.method = "card"; row.fromAccountID = account
                                row.updatedAt = now; try patch.save(); count("earlier.cardLinked")
                            }
                        }
                    }
                case let .ingest(command, text, sender, at, transaction, category):
                    _ = await run(MoneyCommandPayload.intakeName, ["text": .string(text), "sender": .string(sender), "receivedAt": .string(ISO8601DateFormatter().string(from: at))], command, "message")
                    let fresh = ModelContext(container)
                    guard let row = try fresh.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == transaction }) else { count("message.noMovement"); continue }
                    count("message.state." + row.reviewState)
                    // A possible duplicate is never confirmed for the owner; it waits in review like any other.
                    guard row.reviewState != "ok", row.reviewState != "possibleDuplicate" else { continue }
                    if let category, row.categoryID != category {
                        _ = await run("money.categorize", ["id": .string(transaction.uuidString), "categoryID": .string(category.uuidString), "remember": .bool(false)],
                                      StableIdentity.uuid(for: "LegacyCategorize:" + transaction.uuidString), "categorize")
                    }
                    _ = await run("money.confirmTransaction", ["id": .string(transaction.uuidString)], StableIdentity.uuid(for: "LegacyConfirm:" + transaction.uuidString), "confirm")
                }
            }
            // Establish each checkpoint after intake/confirmation, so possible duplicates never enter its arithmetic.
            // This DEBUG hook runs only in the isolated trial store. No real store or owner data is migrated here.
            let balances = ModelContext(container)
            let movements = try MoneyRepository(context: balances).confirmedTransactions()
            let creditIDs = Set(try balances.fetch(FetchDescriptor<Card>()).filter { $0.kind == "credit" }.map(\.id))
            for account in try balances.fetch(FetchDescriptor<Account>()) where account.deletedAt == nil {
                guard let evidence = plan.balanceEvidence[account.id], movements.contains(where: { $0.id == evidence.transactionID }) else {
                    account.balanceAt = nil; account.balanceMinor = 0; count("balance.unknown"); continue
                }
                let deltas = movements.filter { $0.eventAt <= evidence.at }.compactMap { row -> Int? in
                    if row.cardID.map(creditIDs.contains) == true && ["expense", "fee", "refund", "cashback"].contains(row.kind) { return nil }
                    let amount = row.currency == account.currency ? row.amountMinor : row.homeCurrency == account.currency ? row.homeAmountMinor : nil
                    guard let amount else { return nil }
                    return (row.toAccountID == account.id ? amount : 0) - (row.fromAccountID == account.id ? amount : 0)
                }
                guard let opening = LegacyMoneyImport.openingBalance(printed: evidence.amountMinor, signedMovements: deltas) else { throw MoneyCommandError.invalidAmount }
                account.balanceMinor = opening
                account.balanceAt = movements.map(\.eventAt).min()?.addingTimeInterval(-1) ?? evidence.at
                count("balance.known")
            }
            try balances.save()
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
