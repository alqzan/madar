import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarPrayer
import MadarQuran
import MadarCommands

/// The move from the old Madar (item 24, owner's go 25 Oct 2026). One room at a time from the old app's backup file
/// into the live store. Ids derive from the old ids, so a second move adds nothing. Where the owner already keeps the
/// same thing natively (a prayer on the same day, the same bank account or card, a Quran plan), the native row wins and
/// the old one is archived in its ImportLink only. The DEBUG trials call these same functions.
extension AppSession {
    static let legacyMoveWriter = "madar.app.legacyMove"

    func importLegacyPrayer(_ backup: Data, writer: String = AppSession.legacyMoveWriter, now: Date) throws -> [String: Int] {
        let home = activePlace
        let plan = try LegacyPrayerImport.plan(backup: backup, home: home, uuid: StableIdentity.uuid(for:))
        var counts = plan.counts
        let context = ModelContext(container)
        let logs = try context.fetch(FetchDescriptor<PrayerLog>())
        let qadas = try context.fetch(FetchDescriptor<QadaItem>())
        let logIDs = Set(logs.map(\.id)), qadaIDs = Set(qadas.map(\.id))
        let native = Set(logs.filter { $0.deletedAt == nil }.map { $0.dayKey + "|" + $0.prayer })
        let nativeQada = Set(qadas.filter { $0.deletedAt == nil }.map { $0.originalDayKey + "|" + $0.prayer })
        let linkIDs = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
        for log in plan.logs where !logIDs.contains(log.id) {
            guard !native.contains(log.dayKey + "|" + log.prayer.rawValue) else { counts["logs.keptNative", default: 0] += 1; continue }
            let row = PrayerLog(); row.id = log.id; row.dayKey = log.dayKey; row.prayer = log.prayer.rawValue; row.status = log.status.rawValue
            row.heart = log.heart?.rawValue; row.eventAt = log.eventAt; row.loggedAt = log.loggedAt; row.fridayKind = log.fridayKind?.rawValue
            row.tzID = home.timeZoneID; row.dayPolicy = "legacy@0"; row.source = "import"
            row.createdAt = log.loggedAt ?? log.eventAt; row.updatedAt = row.createdAt; row.writerID = writer; context.insert(row)
            counts["logs.created", default: 0] += 1
        }
        for item in plan.qada where !qadaIDs.contains(item.id) {
            // A prayer the owner logged here, or a qada they already keep for it, is never owed twice (RP1).
            let natural = item.dayKey + "|" + item.prayer.rawValue
            guard !native.contains(natural), !nativeQada.contains(natural) else { counts["qada.keptNative", default: 0] += 1; continue }
            let row = QadaItem(); row.id = item.id; row.prayer = item.prayer.rawValue; row.originalDayKey = item.dayKey; row.madeUpAt = item.madeUpAt
            row.createdAt = item.madeUpAt ?? now; row.updatedAt = row.createdAt; row.writerID = writer; context.insert(row)
            counts["qada.created", default: 0] += 1
        }
        for archive in plan.archives {
            let id = StableIdentity.uuid(for: "myDream:ImportLink:PrayerDay:\(archive.dayKey)")
            guard !linkIDs.contains(id) else { continue }
            let link = ImportLink(); link.id = id; link.source = "myDream"; link.sourceModel = "PrayerLog"; link.sourceID = archive.dayKey
            link.targetModel = "PrayerLog"; link.unmappedJSON = archive.json
            link.createdAt = now; link.updatedAt = now; link.importedAt = now; link.writerID = writer; context.insert(link)
        }
        // Tracking starts at the first old day so the history counts, but never later than the owner's own start.
        if let start = plan.trackingStart {
            let settings = SettingsStore(context: context, schema: schema)
            let current = (try? settings.value(for: "salah.trackingStart"))?.object?["dayKey"]?.string
            if current.map({ start.description < $0 }) ?? true {
                try settings.prepare(.object(["dayKey": .string(start.description), "edits": .number(0)]), for: "salah.trackingStart")
                counts["trackingStart.moved"] = 1
            }
        }
        try context.save()
        return counts
    }

    func importLegacyQuran(_ backup: Data, fileName: String, writer: String = AppSession.legacyMoveWriter, now: Date) throws -> [String: Int] {
        let catalog = try QuranResources.catalog(), zone = activePlace.timeZone
        let plan = try LegacyQuranImport.plan(backup: backup, timeZone: zone, catalog: catalog, uuid: StableIdentity.uuid(for:))
        var counts = plan.counts
        let context = ModelContext(container)
        var links = Set(try context.fetch(FetchDescriptor<ImportLink>()).map(\.id))
        let batchID = StableIdentity.uuid(for: "myDream:ImportBatch:quran")
        func link(_ model: String, _ sourceID: String, target: String, _ targetID: UUID?, _ json: Data?) {
            let id = StableIdentity.uuid(for: "myDream:ImportLink:\(model):\(sourceID)")
            guard links.insert(id).inserted else { counts["replay.existing", default: 0] += 1; return }
            let row = ImportLink(); row.id = id; row.source = "myDream"; row.sourceModel = model; row.sourceID = sourceID
            row.targetModel = target; row.targetID = targetID; row.importBatchID = batchID; row.unmappedJSON = json
            row.createdAt = now; row.updatedAt = now; row.importedAt = now; row.writerID = writer; context.insert(row)
            counts["links.created", default: 0] += 1
        }
        if !(try context.fetch(FetchDescriptor<ImportBatch>()).contains { $0.id == batchID }) {
            let batch = ImportBatch(); batch.id = batchID; batch.kind = "migration"; batch.fileName = fileName
            batch.startedAt = now; batch.finishedAt = now; batch.status = "done"
            batch.summaryJSON = (try? JSONEncoder().encode(plan.counts)) ?? Data()
            batch.createdAt = now; batch.updatedAt = now; batch.writerID = writer; context.insert(batch)
        }
        let plans = try context.fetch(FetchDescriptor<HifzPlan>())
        // A plan the owner already keeps natively stays the plan. Old sessions stay outside it (no planID), so they never
        // move the native frontier; they still count as reviewed history.
        let nativePlan = plans.first { $0.deletedAt == nil && $0.id != plan.plan?.id }
        var planID = plan.plan?.id
        if nativePlan != nil { planID = nil; counts["plan.keptNative"] = 1 }
        else if let p = plan.plan, !plans.contains(where: { $0.id == p.id }) {
            let row = HifzPlan(); row.id = p.id; row.version = 1; row.startAyah = p.startAyah; row.unit = p.unit; row.amount = p.amount
            row.rhythm = p.rhythm; row.frontierAyah = p.frontierAyah; row.activeFrom = p.activeFrom
            row.createdAt = p.activeFrom; row.updatedAt = p.updatedAt; row.writerID = writer; context.insert(row)
            link("HifzPlan.v1", p.sourceID, target: "HifzPlan", p.id, nil)
        }
        let sessionIDs = Set(try context.fetch(FetchDescriptor<HifzSession>()).map(\.id))
        for s in plan.sessions where !sessionIDs.contains(s.id) {
            let row = HifzSession(); row.id = s.id; row.planID = planID; row.dayKey = s.dayKey; row.endedAt = s.endedAt
            row.tzID = zone.identifier; row.dayPolicy = "legacy@0"; row.kind = s.kind; row.fromAyah = s.fromAyah; row.toAyah = s.toAyah
            row.pages = s.pages; row.source = "import"; row.createdAt = s.endedAt; row.updatedAt = s.updatedAt; row.writerID = writer
            context.insert(row); link(s.sourceModel, s.sourceID, target: "HifzSession", s.id, s.raw)
            counts["sessions.created", default: 0] += 1
        }
        let gradeIDs = Set(try context.fetch(FetchDescriptor<PageGrade>()).map(\.id))
        let ended = Dictionary(uniqueKeysWithValues: plan.sessions.map { ($0.id, $0.endedAt) })
        for g in plan.grades where !gradeIDs.contains(g.id) {
            let row = PageGrade(); row.id = g.id; row.sessionID = g.sessionID; row.page = g.page; row.grade = g.grade; row.role = "regular"
            row.createdAt = ended[g.sessionID] ?? now; row.updatedAt = row.createdAt; row.writerID = writer; context.insert(row)
        }
        let spotIDs = Set(try context.fetch(FetchDescriptor<MistakeSpot>()).map(\.id))
        for m in plan.spots where !spotIDs.contains(m.id) {
            let row = MistakeSpot(); row.id = m.id; row.ayahId = m.ayahId; row.wordIndex = m.wordIndex; row.legacyHits = m.legacyHits
            row.legacyLastDrillAt = m.legacyLastDrillAt; row.legacyStreak = m.legacyStreak
            row.createdAt = m.updatedAt; row.updatedAt = m.updatedAt; row.writerID = writer
            context.insert(row); link("HifzMistake", m.sourceID, target: "MistakeSpot", m.id, m.raw)
            counts["spots.created", default: 0] += 1
        }
        for a in plan.archives { link(a.sourceModel, a.sourceID, target: "", nil, a.json) }
        // The snapshot is the acceptance oracle: it throws on a completed face without hifz provenance.
        let repository = try QuranRepository(context: context, catalog: catalog)
        try QuranMutationHandler.rebuildCache(repository, at: now, writer: writer)
        try context.save()
        return counts
    }

    /// Money goes through the command bus, so intake, review and duplicate detection behave as for a new message.
    func importLegacyMoney(_ backup: Data, now: Date, progress: @escaping @MainActor (Int, Int) -> Void = { _, _ in }) async throws -> [String: Int] {
        var counts: [String: Int] = [:]
        func count(_ key: String) { counts[key, default: 0] += 1 }
        let context = ModelContext(container)
        let storedCategories = try context.fetch(FetchDescriptor<MadarData.Category>())
        let existing = storedCategories.filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .map { LegacyMoneyImport.Category(id: $0.id, name: $0.name, order: $0.order) }
        let zone = activePlace.timeZone
        let plan = try LegacyMoneyImport.plan(backup: backup, existing: existing, timeZone: zone, uuid: StableIdentity.uuid(for:))
        counts = plan.counts
        // No command creates a category in v1; the old categories are inserted as data, with stable ids.
        let categoryIDs = Set(try context.fetch(FetchDescriptor<MadarData.Category>()).map(\.id))
        for item in plan.createCategories where !categoryIDs.contains(item.id) {
            let row = MadarData.Category(); row.id = item.id; row.name = item.name; row.order = item.order
            row.createdAt = now; row.updatedAt = now; row.writerID = Self.legacyMoveWriter; context.insert(row)
        }
        try context.save()
        // The same bank account or card the owner already added natively is reused, never duplicated.
        let storedAccounts = try context.fetch(FetchDescriptor<Account>())
        let storedCards = try context.fetch(FetchDescriptor<Card>())
        let liveAccounts = storedAccounts.filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let liveCards = storedCards.filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let identityRows = try storedAccounts.map { try $0.record() } + storedCards.map { try $0.record() } + storedCategories.map { try $0.record() }
        // Device receipts are deliberately absent after restore. Stable source identities (including tombstones)
        // still prove that a row arrived before: replay must not rename it, reset its balance or resurrect it.
        let accountIDs = Set(storedAccounts.map(\.id)), cardIDs = Set(storedCards.map(\.id))
        let storedMovements = try context.fetch(FetchDescriptor<MoneyTransaction>())
        let movementIDs = Set(storedMovements.map(\.id))
        let movementStates = Dictionary(storedMovements.filter { $0.deletedAt == nil && $0.mergedInto == nil }.map { ($0.id, $0.reviewState) }, uniquingKeysWith: { first, _ in first })
        let rulePatterns = Set(try context.fetch(FetchDescriptor<MerchantRule>()).map(\.pattern))
        var accountMap: [UUID: UUID] = [:], cardMap: [UUID: UUID] = [:], createdAccounts: Set<UUID> = []
        for case let .saveAccount(_, id, _, bank, last4, _) in plan.steps {
            let resolved = RowMerger.resolve(id: id, model: "Account", rows: identityRows)
            if resolved != id { accountMap[id] = resolved; continue }
            guard let bank, let last4, !liveAccounts.contains(where: { $0.id == id }),
                  let native = liveAccounts.first(where: { $0.bank.uppercased() == bank.uppercased() && $0.last4 == last4 }) else { continue }
            accountMap[id] = native.id
        }
        for case let .saveCard(_, id, last4, bank, _, _) in plan.steps {
            let resolved = RowMerger.resolve(id: id, model: "Card", rows: identityRows)
            if resolved != id { cardMap[id] = resolved; continue }
            guard !liveCards.contains(where: { $0.id == id }),
                  let native = liveCards.first(where: { $0.last4 == last4 && $0.bank.uppercased() == bank.uppercased() }) else { continue }
            cardMap[id] = native.id
        }
        func account(_ id: UUID) -> UUID { RowMerger.resolve(id: accountMap[id] ?? id, model: "Account", rows: identityRows) }
        func category(_ id: UUID) -> UUID { RowMerger.resolve(id: id, model: "Category", rows: identityRows) }
        func run(_ name: String, _ payload: [String: MadarCore.JSONValue], _ id: UUID, _ key: String) async -> String {
            let status: String
            do { status = try await executeImportCommand(name, payload: payload, id: id) } catch { status = "error." + String(describing: error).prefix(60) }
            count(key + "." + status); return status
        }
        func arabic(_ digits: String) -> String { String(digits.map { c in c.wholeNumberValue.map { Character(UnicodeScalar(0x0660 + $0)!) } ?? c }) }
        var cycleExpected: [String: MadarCore.JSONValue] = [:]
        if let settings = plan.cycleSettings {
            // Archive the old configuration, including fields v1 cannot use, before applying the native settings.
            if try context.fetch(FetchDescriptor<ImportLink>()).contains(where: { $0.id == settings.archiveID }) {
                count("settings.archiveExisting")
            } else {
                let link = ImportLink(); link.id = settings.archiveID; link.source = "myDream"; link.sourceModel = "MoneyCycleSettings"
                link.sourceID = settings.archiveID.uuidString; link.targetModel = "Setting"; link.unmappedJSON = settings.archive
                link.createdAt = now; link.updatedAt = now; link.importedAt = now; link.writerID = Self.legacyMoveWriter
                context.insert(link); try context.save(); count("settings.archiveCreated")
            }
            if let daily = settings.daily {
                cycleExpected["mal.dailyAllowance"] = .object(["mode": .string(daily.mode),
                    "amountMinor": daily.amountMinor.map { .number(Double($0)) } ?? .null,
                    "percentBp": daily.percentBp.map { .number(Double($0)) } ?? .null])
            }
            if let day = settings.salaryDay { cycleExpected["mal.salaryDay"] = .number(Double(day)) }
            if settings.gregorian { cycleExpected["mal.cycleCalendar"] = .string("gregorian") }
            // The owner's own cycle settings win; only keys still at their agreed default take the old values.
            let store = SettingsStore(context: ModelContext(container), schema: schema)
            for key in cycleExpected.keys {
                guard let definition = schema.settings.first(where: { $0.key == key }), let current = try? store.value(for: key) else { continue }
                if let expected = cycleExpected[key], try current.canonicalData() == expected.canonicalData() {
                    cycleExpected[key] = nil; count("settings.alreadyMatched")
                } else if current != definition.defaultValue { cycleExpected[key] = nil; count("settings.keptNative") }
            }
            if !cycleExpected.isEmpty {
                _ = await run("settings.set", ["settings": .object(cycleExpected)], settings.command, "cycleSettings")
            }
        }
        let movementTotal = plan.steps.filter { step in
            switch step { case .logExpense, .ingest: true; default: false }
        }.count
        var reviewed = 0
        for step in plan.steps {
            let isMovement: Bool
            switch step { case .logExpense, .ingest: isMovement = true; default: isMovement = false }
            // The previous batch's progress can paint before the next batch starts; no command transaction is open.
            if isMovement && reviewed > 0 && reviewed.isMultiple(of: 10) { await Task.yield() }
            defer {
                if isMovement {
                    reviewed += 1
                    if reviewed == 1 || reviewed.isMultiple(of: 10) || reviewed == movementTotal { progress(reviewed, movementTotal) }
                }
            }
            switch step {
            case let .saveAccount(command, id, kind, bank, last4, at):
                guard accountMap[id] == nil, !accountIDs.contains(id) else { count("account.keptNative"); continue }
                let shownBank = bank.map { $0.uppercased() }
                var p: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "kind": .string("current"), "ownership": .string("mine"), "currency": .string("SAR"),
                    "name": .string(kind == "earlier" ? "بطاقة غير معروفة — رسائلها غير محفوظة" : kind == "unidentified" ? "حساب بطاقة مدى — رقمه غير معروف" : "حساب " + (shownBank ?? "") + (last4.map { " " + arabic($0) } ?? "")),
                    "balanceMinor": .string("0"), "balanceAt": .string(ISO8601DateFormatter().string(from: at)), "tracked": .bool(true)]
                if let shownBank, let bank { p["bank"] = .string(shownBank); p["senderIDs"] = .array([.string(bank)]) }
                if let last4 { p["last4"] = .string(last4) }
                if await run("money.saveAccount", p, command, "account") == "applied" { createdAccounts.insert(id) }
            case let .saveCard(command, id, last4, bank, kind, linked):
                guard cardMap[id] == nil, !cardIDs.contains(id) else { count("card.keptNative"); continue }
                var p: [String: MadarCore.JSONValue] = ["id": .string(id.uuidString), "name": .string((kind == "credit" ? "بطاقة ائتمانية " : "بطاقة مدى ") + bank.uppercased() + " ‹" + arabic(last4) + "›"), "bank": .string(bank.uppercased()),
                                                       "last4": .string(last4), "kind": .string(kind), "aliases": .array([.string(bank)])]
                if let linked { p["accountID"] = .string(account(linked).uuidString) }
                _ = await run("money.saveCard", p, command, "card")
            case let .saveRule(command, merchant, sourceCategory):
                guard !rulePatterns.contains(BankDedupe.normalize(merchant)) else { count("rule.keptNative"); continue }
                _ = await run("money.saveMerchantRule", ["merchant": .string(merchant), "categoryID": .string(category(sourceCategory).uuidString), "ignore": .bool(false)], command, "rule")
            case let .logExpense(command, amount, merchant, sourceCategory, at, from):
                guard !movementIDs.contains(command) else { count("earlier.keptNative"); continue }
                var p: [String: MadarCore.JSONValue] = ["amountMinor": .string(String(amount)), "currency": .string("SAR"), "method": .string("transfer"),
                                                       "fromAccountID": .string(account(from).uuidString), "showInDiary": .bool(false),
                                                       "eventAt": .string(ISO8601DateFormatter().string(from: at))]
                if let merchant { p["merchant"] = .string(merchant) }
                if let sourceCategory { p["categoryID"] = .string(category(sourceCategory).uuidString) }
                _ = await run("money.logExpense", p, command, "earlier")
                // Owner, 22 Oct: these rows came from an automatic source, never typed by hand. The shipped command
                // can only write «manual», so the move marks the row automatic, without message text.
                let fresh = ModelContext(container)
                if let row = try fresh.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == command }), row.source == "manual" {
                    row.source = "bank"; row.updatedAt = now; try fresh.save(); count("earlier.automatic")
                }
                // The old rows have no card digits. Only an unambiguous merchant match supplies a card.
                if let planned = plan.earlierCards[command] {
                    let cardID = RowMerger.resolve(id: cardMap[planned] ?? planned, model: "Card", rows: identityRows)
                    let patch = ModelContext(container)
                    if let row = try patch.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == command }),
                       let card = try patch.fetch(FetchDescriptor<Card>()).first(where: { $0.id == cardID }), card.kind == "credit" || card.accountID != nil {
                        let linked = card.kind == "credit" ? nil : card.accountID
                        if row.cardID != card.id || row.method != "card" || row.fromAccountID != linked {
                            row.cardID = card.id; row.method = "card"; row.fromAccountID = linked
                            row.updatedAt = now; try patch.save(); count("earlier.cardLinked")
                        }
                    }
                }
            case let .ingest(command, text, sender, at, transaction, sourceCategory):
                guard !movementIDs.contains(transaction) else {
                    count("message.keptNative")
                    if let state = movementStates[transaction] { count("message.state." + state) }
                    continue
                }
                _ = await run(MoneyCommandPayload.intakeName, ["text": .string(text), "sender": .string(sender), "receivedAt": .string(ISO8601DateFormatter().string(from: at))], command, "message")
                let fresh = ModelContext(container)
                guard let row = try fresh.fetch(FetchDescriptor<MoneyTransaction>()).first(where: { $0.id == transaction }) else { count("message.noMovement"); continue }
                count("message.state." + row.reviewState)
                // A possible duplicate is never confirmed for the owner; it waits in review like any other.
                guard row.reviewState != "ok", row.reviewState != "possibleDuplicate" else { continue }
                if let sourceCategory, row.categoryID != category(sourceCategory) {
                    _ = await run("money.categorize", ["id": .string(transaction.uuidString), "categoryID": .string(category(sourceCategory).uuidString), "categorySource": .string("rule")],
                                  StableIdentity.uuid(for: "LegacyCategorize:" + transaction.uuidString), "categorize")
                }
                _ = await run("money.confirmTransaction", ["id": .string(transaction.uuidString)], StableIdentity.uuid(for: "LegacyConfirm:" + transaction.uuidString), "confirm")
            }
        }
        // Each checkpoint is set after intake and confirmation, so possible duplicates never enter its arithmetic.
        // Only accounts this run created get one; an account the owner already keeps, or one an earlier move created
        // and the owner may have corrected since, keeps its own balance.
        let balances = ModelContext(container)
        let movements = try MoneyRepository(context: balances).confirmedTransactions()
        let creditIDs = Set(try balances.fetch(FetchDescriptor<Card>()).filter { $0.kind == "credit" }.map(\.id))
        for account in try balances.fetch(FetchDescriptor<Account>()) where account.deletedAt == nil && createdAccounts.contains(account.id) {
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
        counts["settings.mapped"] = cycleExpected.count
        return counts
    }

}
