import Foundation
import CryptoKit
import SwiftData
import Testing
@testable import MadarData

@Suite(.serialized) @MainActor struct SchemaCompatibilityTests {
    @Test func schemaV3UpgradeRetainsEveryExistingFieldAndAddsOnlyHabitEvents() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV4-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV3.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV3.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV3.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let prayer = PrayerLog(); prayer.dayKey = "2026-10-09"; prayer.prayer = "dhuhr"; prayer.fridayKind = "jumuah"
            let entry = MadarFrozenDiaryV7.Entry(); entry.dayKey = "2026-10-08"; entry.text = "synthetic untouched diary"
            let habit = Habit(); habit.name = "synthetic habit"
            let log = HabitLog(); log.habitID = habit.id; log.periodKey = "2026-10-08"; log.value = 2
            for row in [prayer as any MadarRecordModel, entry, habit, log] { old.mainContext.insert(row); before.append(try row.record()) }
            let schedule = PageSchedule(); schedule.page = 2; schedule.stage = 7; old.mainContext.insert(schedule)
            try old.mainContext.save()
        }
        try DurableFiles.encode(3, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let expected = try SchemaCompatibility.currentRecords(before, from: 3)
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext)) == RecordFingerprint.hash(expected))
        #expect(try upgraded.container.mainContext.fetch(FetchDescriptor<PageSchedule>()).first?.stage == 7)
        #expect(try upgraded.container.mainContext.fetchCount(FetchDescriptor<HabitEvent>()) == 0)
        #expect(expected.first { $0.model == "Entry" }?.fields["tags"] == .null)
        let first = HabitEvent(); first.habitID = before.first { $0.model == "Habit" }!.id; first.dayKey = "2026-10-09"; first.periodKey = "2026-10-09"; first.delta = 1
        let second = HabitEvent(); second.habitID = first.habitID; second.dayKey = first.dayKey; second.periodKey = first.periodKey; second.delta = 1
        upgraded.container.mainContext.insert(first); upgraded.container.mainContext.insert(second); try upgraded.container.mainContext.save()
        try RecordValidator.validate(RecordBridge.all(upgraded.container.mainContext))
        try RowMerger(context: upgraded.container.mainContext).run()
        #expect(try upgraded.container.mainContext.fetch(FetchDescriptor<HabitEvent>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.reduce(0) { $0 + $1.delta } == 2)
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try reopened.container.mainContext.fetchCount(FetchDescriptor<HabitEvent>()) == 2)
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<PrayerLog>()).first?.fridayKind == "jumuah")
    }
    /// M5-D01 (owner go, 16 Oct): V4 → V5 adds only defaulted or optional money fields. Synthetic store only.
    @Test func schemaV4UpgradeKeepsEveryMoneyValueAndDefaultsOnlyTheNewFields() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV5-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let accountID = UUID(), cardID = UUID(), planID = UUID(), zakatID = UUID()
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV4.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV4.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV4.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let account = MadarFrozenMoneyV4.Account(); account.id = accountID; account.name = "synthetic current"; account.kind = "savings"; account.balanceMinor = 1_285_000; account.senderIDs = ["BANK"]
            let card = MadarFrozenMoneyV4.Card(); card.id = cardID; card.bank = "BANK"; card.last4 = "3333"; card.limitMinor = 2_000_000; card.accountID = accountID
            let plan = MadarFrozenMoneyV4.EnvelopePlan(); plan.id = planID; plan.kind = "repay"; plan.source = "surplus"; plan.perPaycheckMinor = 50_000
            let zakat = MadarFrozenMoneyV4.ZakatProfile(); zakat.id = zakatID; zakat.goldPricePerGramMinor = 40_000; zakat.debtsPolicy = "allOwed"; zakat.otherAssetsMinor = 12
            for row in [account as any PersistentModel, card, plan, zakat] { old.mainContext.insert(row) }
            // V7 pinned MoneyTransaction's V2–V6 shape; the expected row is the same values read through the current model.
            let money = MadarFrozenMoneyV6.MoneyTransaction(); money.amountMinor = 4_200; money.kind = "expense"; money.cardID = cardID
            old.mainContext.insert(money)
            let expected = MoneyTransaction(); expected.id = money.id; expected.createdAt = money.createdAt; expected.updatedAt = money.updatedAt; expected.eventAt = money.eventAt
            expected.amountMinor = 4_200; expected.kind = "expense"; expected.cardID = cardID; before.append(try expected.record())
            let entry = MadarFrozenDiaryV7.Entry(); entry.dayKey = "2026-10-08"; entry.text = "synthetic untouched diary"
            for row in [entry as any MadarRecordModel] { old.mainContext.insert(row); before.append(try row.record()) }
            try old.mainContext.save()
        }
        try DurableFiles.encode(4, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let context = upgraded.container.mainContext
        let account = try #require(context.fetch(FetchDescriptor<Account>()).first)
        #expect(account.id == accountID && account.name == "synthetic current" && account.kind == "savings" && account.balanceMinor == 1_285_000 && account.senderIDs == ["BANK"])
        #expect(account.last4 == nil && account.tracked)
        let card = try #require(context.fetch(FetchDescriptor<Card>()).first)
        #expect(card.id == cardID && card.last4 == "3333" && card.limitMinor == 2_000_000 && card.accountID == accountID)
        #expect(card.kind == "credit")
        let plan = try #require(context.fetch(FetchDescriptor<EnvelopePlan>()).first)
        #expect(plan.id == planID && plan.kind == "repay" && plan.source == "surplus" && plan.perPaycheckMinor == 50_000)
        #expect(plan.period == "perCycle" && plan.startDayKey == nil)
        let zakat = try #require(context.fetch(FetchDescriptor<ZakatProfile>()).first)
        #expect(zakat.id == zakatID && zakat.goldPricePerGramMinor == 40_000 && zakat.debtsPolicy == "allOwed" && zakat.otherAssetsMinor == 12 && zakat.nisabMg == 85_000)
        #expect(zakat.nisabBasis == "gold" && zakat.nisabSilverMg == 595_000 && zakat.silverPricePerGramMinor == nil)
        let unchanged = try RecordBridge.all(context).filter { ["MoneyTransaction", "Entry"].contains($0.model) }
        let expectedBefore = try SchemaCompatibility.currentRecords(before, from: 4)
        #expect(try RecordFingerprint.hash(unchanged) == RecordFingerprint.hash(expectedBefore))
        // A V4 backup row decodes into V5 with the same defaults.
        let rows = try RecordBridge.all(context).filter { ["Account", "Card", "EnvelopePlan", "ZakatProfile"].contains($0.model) }
        let v4Rows = rows.map { row -> DataRecord in
            var old = row
            for key in ["last4", "tracked", "kind", "period", "startDayKey", "nisabBasis", "nisabSilverMg", "silverPricePerGramMinor", "silverPriceSetAt"]
                where !(row.model == "Account" && key == "kind") && !(row.model == "EnvelopePlan" && key == "kind") && !(row.model == "Card" && key == "last4") { old.fields[key] = nil }
            return old
        }
        #expect(try SchemaCompatibility.currentRecords(v4Rows, from: 4) == rows)
        // An undo receipt written before V5 applies without the new keys (the fridayKind precedent).
        let fromReceipt = Card(); try fromReceipt.apply(try #require(v4Rows.first { $0.model == "Card" }))
        #expect(fromReceipt.kind == "credit" && fromReceipt.last4 == "3333")
        let zakatReceipt = ZakatProfile(); try zakatReceipt.apply(try #require(v4Rows.first { $0.model == "ZakatProfile" }))
        #expect(zakatReceipt.nisabBasis == "gold" && zakatReceipt.nisabSilverMg == 595_000 && zakatReceipt.debtsPolicy == "allOwed")
        try RecordValidator.validate(RecordBridge.all(context))
        card.kind = "debit"; try context.save()
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<Card>()).first?.kind == "debit")
    }
    /// M5-V04 (owner go, 16 Oct): V5 → V6 adds only the optional repayment total and salary count. Synthetic store only.
    @Test func schemaV5UpgradeKeepsEveryPlanValueAndLeavesTheRepaymentFieldsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV6-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let fundID = UUID(), repayID = UUID(), envelopeID = UUID(), until = Date(timeIntervalSince1970: 1_900_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV5.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV5.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV5.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let fund = MadarFrozenMoneyV5.EnvelopePlan(); fund.id = fundID; fund.envelopeID = envelopeID; fund.perPaycheckMinor = 50_000; fund.period = "perDay"; fund.startDayKey = "2026-10-01"
            let repay = MadarFrozenMoneyV5.EnvelopePlan(); repay.id = repayID; repay.envelopeID = envelopeID; repay.kind = "repay"; repay.source = "reserve"; repay.perPaycheckMinor = 33_334; repay.untilDate = until
            old.mainContext.insert(fund); old.mainContext.insert(repay)
            let envelope = Envelope(); envelope.id = envelopeID; envelope.name = "synthetic trip"
            let allocation = Allocation(); allocation.targetID = envelopeID; allocation.amountMinor = -100_000; allocation.idempotencyKey = "synthetic:spend"
            for row in [envelope as any MadarRecordModel, allocation] { old.mainContext.insert(row); before.append(try row.record()) }
            try old.mainContext.save()
        }
        try DurableFiles.encode(5, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let context = upgraded.container.mainContext
        let plans = try context.fetch(FetchDescriptor<EnvelopePlan>())
        let fund = try #require(plans.first { $0.id == fundID }), repay = try #require(plans.first { $0.id == repayID })
        #expect(fund.envelopeID == envelopeID && fund.kind == "fund" && fund.source == "salary" && fund.perPaycheckMinor == 50_000 && fund.period == "perDay" && fund.startDayKey == "2026-10-01" && fund.untilDate == nil)
        #expect(repay.envelopeID == envelopeID && repay.kind == "repay" && repay.source == "reserve" && repay.perPaycheckMinor == 33_334 && repay.untilDate == until && repay.period == "perCycle")
        #expect(plans.allSatisfy { $0.repaymentTotalMinor == nil && $0.repaymentPaychecks == nil })
        let unchanged = try RecordBridge.all(context).filter { ["Envelope", "Allocation"].contains($0.model) }
        #expect(try RecordFingerprint.hash(unchanged) == RecordFingerprint.hash(before))
        // A V5 backup row and a pre-V6 undo receipt decode without the new keys.
        let rows = try RecordBridge.all(context).filter { $0.model == "EnvelopePlan" }
        let v5Rows = rows.map { row -> DataRecord in var old = row; old.fields["repaymentTotalMinor"] = nil; old.fields["repaymentPaychecks"] = nil; return old }
        #expect(try SchemaCompatibility.currentRecords(v5Rows, from: 5) == rows)
        let fromReceipt = EnvelopePlan(); try fromReceipt.apply(try #require(v5Rows.first { $0.id == repayID }))
        #expect(fromReceipt.kind == "repay" && fromReceipt.perPaycheckMinor == 33_334 && fromReceipt.repaymentTotalMinor == nil && fromReceipt.repaymentPaychecks == nil)
        try RecordValidator.validate(RecordBridge.all(context))
        repay.repaymentTotalMinor = 100_000; repay.repaymentPaychecks = 3; try context.save()
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        let stored = try #require(reopened.container.mainContext.fetch(FetchDescriptor<EnvelopePlan>()).first { $0.id == repayID })
        #expect(stored.repaymentTotalMinor == 100_000 && stored.repaymentPaychecks == 3)
    }
    /// M5-X00 (owner go, 16 Oct): V6 → V7 adds only Obligation's free interval and first due day and the stamp's reason.
    /// Synthetic store only; every old value stays and the new fields stay empty.
    @Test func schemaV6UpgradeKeepsEveryObligationAndMovementValueAndLeavesTheNewFieldsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV7-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let billID = UUID(), loanID = UUID(), movementID = UUID(), purchaseID = UUID(), eventAt = Date(timeIntervalSince1970: 1_800_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV6.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV6.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV6.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let bill = MadarFrozenMoneyV6.Obligation(); bill.id = billID; bill.kind = "bill"; bill.name = "synthetic power"; bill.amountMinor = 22_000; bill.totalMinor = 22_000; bill.dueDay = 25; bill.provider = "001"
            let loan = MadarFrozenMoneyV6.Obligation(); loan.id = loanID; loan.kind = "loan"; loan.name = "synthetic loan"; loan.amountMinor = 95_000; loan.totalMinor = 855_000; loan.dueDay = 27; loan.remainingCount = 9
            let movement = MadarFrozenMoneyV6.MoneyTransaction(); movement.id = movementID; movement.kind = "expense"; movement.amountMinor = 4_550; movement.homeAmountMinor = 4_550
            movement.dayKey = "2027-01-15"; movement.eventAt = eventAt; movement.ignoredFromBudget = true; movement.merchant = "synthetic shop"; movement.obligationID = nil; movement.relatedTransactionID = purchaseID
            old.mainContext.insert(bill); old.mainContext.insert(loan); old.mainContext.insert(movement)
            let item = InstallmentItem(); item.obligationID = loanID; item.seq = 1; item.amountMinor = 95_000; item.dueDate = eventAt
            let envelope = Envelope(); envelope.name = "synthetic trip"
            for row in [item as any MadarRecordModel, envelope] { old.mainContext.insert(row); before.append(try row.record()) }
            try old.mainContext.save()
        }
        try DurableFiles.encode(6, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let context = upgraded.container.mainContext
        let obligations = try context.fetch(FetchDescriptor<Obligation>())
        let bill = try #require(obligations.first { $0.id == billID }), loan = try #require(obligations.first { $0.id == loanID })
        #expect(bill.kind == "bill" && bill.name == "synthetic power" && bill.amountMinor == 22_000 && bill.totalMinor == 22_000 && bill.dueDay == 25 && bill.provider == "001" && bill.remainingCount == nil)
        #expect(loan.kind == "loan" && loan.amountMinor == 95_000 && loan.totalMinor == 855_000 && loan.dueDay == 27 && loan.remainingCount == 9)
        #expect(obligations.allSatisfy { $0.repeatEvery == nil && $0.repeatUnit == nil && $0.firstDueDayKey == nil })
        let movement = try #require(context.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == movementID })
        #expect(movement.kind == "expense" && movement.amountMinor == 4_550 && movement.homeAmountMinor == 4_550 && movement.dayKey == "2027-01-15" && movement.eventAt == eventAt)
        #expect(movement.ignoredFromBudget && movement.merchant == "synthetic shop" && movement.relatedTransactionID == purchaseID && movement.budgetIgnoreReason == nil)
        let unchanged = try RecordBridge.all(context).filter { ["Envelope", "InstallmentItem"].contains($0.model) }
        #expect(try RecordFingerprint.hash(unchanged) == RecordFingerprint.hash(before))
        // A V6 backup row and a pre-V7 undo receipt decode without the new keys.
        let rows = try RecordBridge.all(context).filter { ["Obligation", "MoneyTransaction"].contains($0.model) }
        let v6Rows = rows.map { row -> DataRecord in
            var old = row
            for key in ["repeatEvery", "repeatUnit", "firstDueDayKey", "budgetIgnoreReason"] { old.fields[key] = nil }
            return old
        }
        #expect(try SchemaCompatibility.currentRecords(v6Rows, from: 6) == rows)
        let fromReceipt = Obligation(); try fromReceipt.apply(try #require(v6Rows.first { $0.id == billID }))
        #expect(fromReceipt.dueDay == 25 && fromReceipt.amountMinor == 22_000 && fromReceipt.repeatEvery == nil && fromReceipt.firstDueDayKey == nil)
        let movementReceipt = MoneyTransaction(); try movementReceipt.apply(try #require(v6Rows.first { $0.id == movementID }))
        #expect(movementReceipt.ignoredFromBudget && movementReceipt.budgetIgnoreReason == nil)
        try RecordValidator.validate(RecordBridge.all(context))
        // The new values persist across a reopen and pass the dictionary's enum and range.
        bill.kind = "subscription"; bill.repeatEvery = 6; bill.repeatUnit = "month"; bill.firstDueDayKey = "2027-02-18"; bill.dueDay = nil
        movement.budgetIgnoreReason = "synthetic gift"; try context.save()
        try RecordValidator.validate(RecordBridge.all(context))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        let stored = try #require(reopened.container.mainContext.fetch(FetchDescriptor<Obligation>()).first { $0.id == billID })
        #expect(stored.kind == "subscription" && stored.repeatEvery == 6 && stored.repeatUnit == "month" && stored.firstDueDayKey == "2027-02-18")
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == movementID }?.budgetIgnoreReason == "synthetic gift")
        var bad = try #require(RecordBridge.all(reopened.container.mainContext).first { $0.id == billID })
        bad.fields["repeatUnit"] = .string("fortnight")
        #expect(throws: (any Error).self) { try RecordValidator.validate([bad]) }
    }
    private struct ReceiptScope: Codable { let version: Int; let generationID: UUID }
    private var resources: URL { Bundle.module.resourceURL!.appendingPathComponent("Resources/LegacyV1") }
    private func fixtureDirectory() throws -> URL {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MadarSchemaV1Test-\(UUID())")
        try FileManager.default.createDirectory(at:base,withIntermediateDirectories:true)
        let process = Process(); process.executableURL = URL(fileURLWithPath:"/usr/bin/ditto")
        process.arguments = ["-x","-k",resources.appendingPathComponent("flat.zip").path,base.appendingPathComponent("Flat").path]
        try process.run(); process.waitUntilExit(); #expect(process.terminationStatus == 0)
        return base
    }
    private func expectedRows() throws -> [DataRecord] {
        let schemaTwo = try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:resources.appendingPathComponent("expected-v2-records.json")))
        return try SchemaCompatibility.currentRecords(schemaTwo, from: 2)
    }
    @Test func originalGlobalTypesSQLiteOpensWithFrozenV1Reader() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let flat = base.appendingPathComponent("Flat")
        let rows = try LegacyV1Reader.read(syncedDirectory:flat,deviceStoreURL:flat.appendingPathComponent("Device.store"),copiedTo:base.appendingPathComponent("ReadCopy"))
        let old = try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:resources.appendingPathComponent("records.json")))
        #expect(try RecordFingerprint.hash(rows) == RecordFingerprint.hash(old))
    }
    @Test func test_M0S1_RA4_originalV1ArchiveMapsOnlyAfterAuthentication() throws {
        let bytes = try Data(contentsOf:resources.appendingPathComponent("source-v1.madarbackup"))
        let backup = try BackupCodec.validate(bytes,passphrase:"legacy fixture password")
        #expect(MadarSchema.version == 17)
        #expect(backup.records.contains { $0.model == "MoneyTransaction" })
        #expect(!backup.records.contains { $0.model == "Transaction" })
        let expected = try expectedRows().filter { MadarSchema.syncedNames.contains($0.model) }
        #expect(try RecordFingerprint.hash(backup.records) == RecordFingerprint.hash(expected))
        let money = try #require(backup.records.first { $0.model == "MoneyTransaction" && $0.fields["mergedInto"] == .null })
        #expect(money.fields["amountMinor"] == .number(12345)); #expect(money.fields["currency"] == .string("KWD"))
        #expect(money.fields["restoredAt"] == .number(-978307025))
        #expect(money.fields["homeAmountMinor"] == .number(151234)); #expect(money.fields["dayKey"] == .string("2026-02-03"))
        #expect(throws:DataError.authenticationFailed) { try BackupCodec.validate(bytes,passphrase:"wrong fixture password") }
        var corrupt = bytes; corrupt[corrupt.count-20] ^= 1
        #expect(throws:DataError.authenticationFailed) { try BackupCodec.validate(corrupt,passphrase:"legacy fixture password") }
        let target = try MadarContainerFactory.makeInMemory()
        for row in backup.records { try RecordBridge.insert(row,in:target.mainContext) }; try target.mainContext.save()
        #expect(try RecordFingerprint.hash(RecordBridge.all(target.mainContext)) == RecordFingerprint.hash(expected))
        let newBytes = try BackupCodec.export(records:backup.records,passphrase:"new fixture password")
        let current = try BackupCodec.validate(newBytes,passphrase:"new fixture password")
        #expect(current.manifest.storeSchemaVersion == MadarSchema.version)
        #expect(current.manifest.counts["MoneyTransaction"] == 2 && current.manifest.counts["Transaction"] == nil)
    }
    @Test func test_M0S1_RA4_originalSQLiteIsAdoptedWithoutLosingAnyRow() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let managed = try ManagedDataStore.adoptLegacy(from:base.appendingPathComponent("Flat"),at:base.appendingPathComponent("Managed"))
        #expect(MadarSchema.version == 17)
        #expect(try RecordFingerprint.hash(RecordBridge.all(managed.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
        #expect(try managed.container.mainContext.fetchCount(FetchDescriptor<DeviceSetting>()) == 2)
        #expect(try managed.container.mainContext.fetchCount(FetchDescriptor<CommandReceipt>()) == 1)
        let reopened = try ManagedDataStore(root:managed.root)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
    }
    @Test func schemaV2ManagedGenerationMigratesCopyOnWriteAndRetainsPrayerLog() throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MadarSchemaV2Migration-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let (root, oldID, generation, oldRow) = try schemaV2ManagedFixture(base)
        let originalFiles = try stableGenerationHashes(generation)

        let migrated = try ManagedDataStore(root: root)
        #expect(migrated.binding.generationID != oldID)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: migrated.binding.syncedDirectory) == MadarSchema.version)
        #expect(try stableGenerationHashes(generation) == originalFiles)
        let migratedRows = try RecordBridge.all(migrated.container.mainContext)
        let expected = try SchemaCompatibility.currentRecords([oldRow], from: 2)
        #expect(migratedRows.count == 1)
        #expect(try RecordFingerprint.hash(migratedRows) == RecordFingerprint.hash(expected))
        let saved = try #require(migrated.container.mainContext.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(saved.fridayKind == nil)
        try assertReceiptScope(in: migrated.container.mainContext, generationID: migrated.binding.generationID)

        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == migrated.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext)) == RecordFingerprint.hash(expected))
        try assertReceiptScope(in: reopened.container.mainContext, generationID: reopened.binding.generationID)
    }
    @Test(arguments: [LegacyGenerationMigration.Checkpoint.afterCopy, .afterStaging, .afterHooksJournal, .afterPointer])
    func schemaV2ManagedGenerationRecoversAfterEveryInterruption(_ checkpoint: LegacyGenerationMigration.Checkpoint) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("MadarSchemaV2Recovery-\(UUID())")
        defer { try? FileManager.default.removeItem(at: base) }
        let (root, oldID, generation, oldRow) = try schemaV2ManagedFixture(base)
        let sourceHashes = try stableGenerationHashes(generation)
        let pointerURL = root.appendingPathComponent("ActiveGeneration.json")
        let pointerBytes = try Data(contentsOf: pointerURL)

        #expect(throws: BackupOperationError.simulatedInterruption("schema-2 migration \(checkpoint.rawValue)")) {
            try ManagedDataStore(root: root, migrationInterruption: checkpoint)
        }
        let afterInterruption = try stableGenerationHashes(generation)
        #expect(afterInterruption == sourceHashes)
        if checkpoint != .afterPointer { #expect(try Data(contentsOf: pointerURL) == pointerBytes) }

        let recovered = try ManagedDataStore(root: root)
        #expect(recovered.binding.generationID != oldID)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: recovered.binding.syncedDirectory) == MadarSchema.version)
        let afterRecovery = try stableGenerationHashes(generation)
        #expect(afterRecovery == sourceHashes)
        let expected = try SchemaCompatibility.currentRecords([oldRow], from: 2)
        #expect(try RecordFingerprint.hash(RecordBridge.all(recovered.container.mainContext)) == RecordFingerprint.hash(expected))
        let prayer = try #require(recovered.container.mainContext.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(prayer.fridayKind == nil)
        try assertReceiptScope(in: recovered.container.mainContext, generationID: recovered.binding.generationID)
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == recovered.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext)) == RecordFingerprint.hash(expected))
        try assertReceiptScope(in: reopened.container.mainContext, generationID: reopened.binding.generationID)
    }
    @Test func schemaV7UpgradePreservesImportedDiaryAndDefaultsOnlyItsNewTagsField() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV8-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV7.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV7.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV7.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let entry = MadarFrozenDiaryV7.Entry()
            entry.dayKey = "2025-07-14"; entry.text = "synthetic Day One memory"; entry.source = "dayOne"
            entry.sourceID = "synthetic-day-one-id"; entry.sourceHash = String(repeating: "a", count: 64)
            entry.projectID = UUID(); entry.attachmentMediaIDs = [UUID()]
            old.mainContext.insert(entry); before.append(try entry.record())
            try old.mainContext.save()
        }
        try DurableFiles.encode(7, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: upgraded.binding.syncedDirectory) == MadarSchema.version)
        let context = upgraded.container.mainContext
        let entry = try #require(context.fetch(FetchDescriptor<Entry>()).first)
        #expect(entry.dayKey == "2025-07-14" && entry.text == "synthetic Day One memory" && entry.source == "dayOne")
        #expect(entry.sourceID == "synthetic-day-one-id" && entry.sourceHash == String(repeating: "a", count: 64))
        #expect(entry.projectID?.uuidString == before[0].fields["projectID"]?.string)
        #expect(entry.attachmentMediaIDs == (try before[0].decode("attachmentMediaIDs", as: [UUID].self)))
        #expect(entry.tags == nil)
        let expected = try SchemaCompatibility.currentRecords(before, from: 7)
        #expect(expected.first?.fields["tags"] == .null)
        #expect(try RecordFingerprint.hash(RecordBridge.all(context)) == RecordFingerprint.hash(expected))
        let oldReceipt = Entry(); try oldReceipt.apply(before[0])
        #expect(oldReceipt.tags == nil && oldReceipt.sourceID == "synthetic-day-one-id")
        try RecordValidator.validate(RecordBridge.all(context))
    }

    /// M5-V15: V8→V9 adds a nullable provider link; old reconciliation, account, obligation and installment data survives.
    @Test func schemaV8UpgradeAddsOnlyOptionalInstallmentReconciliationLink() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV9-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let accountID = UUID(), obligationID = UUID(), reconciliationID = UUID(), eventAt = Date(timeIntervalSince1970: 1_797_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV8.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV8.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV8.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let account = Account(); account.id = accountID; account.name = "synthetic current"; account.balanceMinor = 128_500; account.balanceAt = eventAt
            let obligation = Obligation(); obligation.id = obligationID; obligation.kind = "installment"; obligation.name = "synthetic purchase"; obligation.provider = "Tamara"; obligation.totalMinor = 120_000
            let installment = InstallmentItem(); installment.obligationID = obligationID; installment.seq = 1; installment.amountMinor = 40_000; installment.paidMinor = 10_000; installment.dueDate = eventAt
            let oldReconciliation = MadarFrozenReconciliationV8.Reconciliation(); oldReconciliation.id = reconciliationID; oldReconciliation.accountID = accountID
            oldReconciliation.at = eventAt; oldReconciliation.expectedMinor = 128_500; oldReconciliation.observedMinor = 128_000
            oldReconciliation.deltaMinor = -500; oldReconciliation.resolution = "leave"; oldReconciliation.beforeJSON = Data("synthetic snapshot".utf8)
            oldReconciliation.note = "synthetic note"
            for row in [account as any PersistentModel, obligation, installment, oldReconciliation] { old.mainContext.insert(row) }
            let currentShape = Reconciliation(); currentShape.id = reconciliationID; currentShape.accountID = accountID
            currentShape.at = eventAt; currentShape.expectedMinor = 128_500; currentShape.observedMinor = 128_000
            currentShape.deltaMinor = -500; currentShape.resolution = "leave"; currentShape.beforeJSON = Data("synthetic snapshot".utf8)
            currentShape.note = "synthetic note"; currentShape.createdAt = oldReconciliation.createdAt; currentShape.updatedAt = oldReconciliation.updatedAt
            before = [try account.record(), try obligation.record(), try installment.record(), try currentShape.record()]
            before[3].fields.removeValue(forKey: "obligationID")
            try old.mainContext.save()
        }
        try DurableFiles.encode(8, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: upgraded.binding.syncedDirectory) == MadarSchema.version)

        let context = upgraded.container.mainContext
        let record = try #require(context.fetch(FetchDescriptor<Reconciliation>()).first { $0.id == reconciliationID })
        #expect(record.accountID == accountID && record.cardID == nil && record.obligationID == nil)
        #expect(record.at == eventAt && record.expectedMinor == 128_500 && record.observedMinor == 128_000 && record.deltaMinor == -500)
        #expect(record.resolution == "leave" && record.adjustmentTransactionID == nil && record.beforeJSON == Data("synthetic snapshot".utf8) && record.note == "synthetic note")
        let storedObligation = try #require(context.fetch(FetchDescriptor<Obligation>()).first { $0.id == obligationID })
        #expect(storedObligation.kind == "installment" && storedObligation.totalMinor == 120_000 && storedObligation.provider == "Tamara")
        let storedItem = try #require(context.fetch(FetchDescriptor<InstallmentItem>()).first { $0.obligationID == obligationID })
        #expect(storedItem.amountMinor == 40_000 && storedItem.paidMinor == 10_000)
        let expected = try SchemaCompatibility.currentRecords(before, from: 8)
        #expect(expected.first { $0.model == "Reconciliation" }?.fields["obligationID"] == .null)
        #expect(try RecordFingerprint.hash(RecordBridge.all(context)) == RecordFingerprint.hash(expected))
        let oldReceipt = Reconciliation(); try oldReceipt.apply(try #require(before.first { $0.model == "Reconciliation" }))
        #expect(oldReceipt.obligationID == nil && oldReceipt.deltaMinor == -500 && oldReceipt.beforeJSON == Data("synthetic snapshot".utf8))
        try RecordValidator.validate(RecordBridge.all(context))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<Reconciliation>()).first { $0.id == reconciliationID }?.obligationID == nil)
    }

    /// M5-V16: V9→V10 adds a nullable preferred-card foreign key; category identity and data remain unchanged.
    @Test func schemaV9UpgradeDefaultsOnlyPreferredCardWithoutChangingSourceGeneration() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV10-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let categoryID = UUID(), categoryName = "تصنيف اصطناعي", icon = "basket", color = "accent", eventAt = Date(timeIntervalSince1970: 1_797_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV9.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV9.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV9.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let category = MadarFrozenCategoryV9.Category()
            category.id = categoryID; category.name = categoryName; category.icon = icon; category.color = color; category.order = 7
            category.createdAt = eventAt; category.updatedAt = eventAt; category.writerID = "synthetic-v9"
            old.mainContext.insert(category)
            let currentShape = MadarData.Category()
            currentShape.id = categoryID; currentShape.name = categoryName; currentShape.icon = icon; currentShape.color = color; currentShape.order = 7
            currentShape.createdAt = eventAt; currentShape.updatedAt = eventAt; currentShape.writerID = "synthetic-v9"
            before = [try currentShape.record()]
            before[0].fields.removeValue(forKey: "preferredCardID")
            try old.mainContext.save()
        }
        try DurableFiles.encode(9, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: Date()), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: upgraded.binding.syncedDirectory) == MadarSchema.version)

        let context = upgraded.container.mainContext
        let category = try #require(context.fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == categoryID })
        #expect(category.name == categoryName && category.icon == icon && category.color == color && category.order == 7)
        #expect(category.createdAt == eventAt && category.updatedAt == eventAt && category.writerID == "synthetic-v9")
        #expect(category.preferredCardID == nil)
        var oldReceipt = before[0]; oldReceipt.fields["preferredCardID"] = nil
        let expected = try SchemaCompatibility.currentRecords([oldReceipt], from: 9)
        #expect(expected.first?.fields["preferredCardID"] == .null)
        #expect(try RecordFingerprint.hash(RecordBridge.all(context)) == RecordFingerprint.hash(expected))
        try RecordValidator.validate(RecordBridge.all(context))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try reopened.container.mainContext.fetch(FetchDescriptor<MadarData.Category>()).first { $0.id == categoryID }?.preferredCardID == nil)
    }

    /// Owner-approved count-up field defaults false; the source V10 generation is immutable.
    @Test func schemaV10UpgradeDefaultsCountUpAndPreservesDatesTombstonesAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV11-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let liveID = UUID(), deadID = UUID(), stamp = Date(timeIntervalSince1970: 1_797_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV10.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV10.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV10.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            for id in [liveID, deadID] {
                let row = MadarFrozenUpcomingDayV10.UpcomingDay()
                row.id = id; row.title = id == liveID ? "موعد محفوظ" : "موعد محذوف"; row.calendar = "greg"
                row.year = 2030; row.month = 11; row.day = 19; row.repeats = "none"; row.countFromDayKey = "2026-10-25"
                row.createdAt = stamp; row.updatedAt = stamp; row.writerID = "synthetic-v10"
                if id == deadID { row.deletedAt = stamp; row.deletionBarrierAt = stamp }
                old.mainContext.insert(row)
                let shape = UpcomingDay(); shape.id = row.id; shape.title = row.title; shape.calendar = row.calendar
                shape.year = row.year; shape.month = row.month; shape.day = row.day; shape.repeats = row.repeats; shape.countFromDayKey = row.countFromDayKey
                shape.createdAt = stamp; shape.updatedAt = stamp; shape.writerID = row.writerID
                shape.deletedAt = row.deletedAt; shape.deletionBarrierAt = row.deletionBarrierAt
                var record = try shape.record(); record.fields.removeValue(forKey: "countUpAfter"); before.append(record)
            }
            try old.mainContext.save()
        }
        try DurableFiles.encode(10, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: upgraded.binding.syncedDirectory) == MadarSchema.version)
        let rows = try upgraded.container.mainContext.fetch(FetchDescriptor<UpcomingDay>())
        #expect(rows.count == 2 && rows.allSatisfy { !$0.countUpAfter })
        #expect(rows.first { $0.id == liveID }?.title == "موعد محفوظ")
        #expect(rows.first { $0.id == deadID }?.deletionBarrierAt == stamp)
        let expected = try SchemaCompatibility.currentRecords(before, from: 10)
        #expect(expected.allSatisfy { $0.fields["countUpAfter"] == .bool(false) })
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        let live = try #require(reopened.container.mainContext.fetch(FetchDescriptor<UpcomingDay>()).first { $0.id == liveID })
        #expect(live.year == 2030 && live.month == 11 && live.day == 19 && live.countFromDayKey == "2026-10-25")
        live.countUpAfter = true; try reopened.container.mainContext.save()
        let sealed = try BackupCodec.export(records: RecordBridge.all(reopened.container.mainContext), passphrase: "synthetic count-up password")
        let checked = try BackupCodec.validate(sealed, passphrase: "synthetic count-up password")
        #expect(checked.records.first { $0.id == liveID }?.fields["countUpAfter"] == .bool(true))
        #expect(try stableGenerationHashes(generation) == sourceHash)
    }

    /// Owner-approved 25 Oct: V12 adds an optional diary link to HabitEvent; V11 habit times keep every field and get none.
    /// Owner-approved 26 Oct (OR-09): V13 adds optional Trip.journeyID; every V12 trip keeps its fields and stays its own journey.
    @Test func schemaV12UpgradeKeepsTripsAsSingleJourneysAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV13-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let openID = UUID(), closedID = UUID(), stamp = Date(timeIntervalSince1970: 1_797_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV12.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV12.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV12.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            for id in [openID, closedID] {
                let row = MadarFrozenTripV12.Trip()
                row.id = id; row.city = id == openID ? "Istanbul" : "Cairo"; row.country = id == openID ? "TR" : "EG"
                row.currency = id == openID ? "TRY" : "EGP"; row.fxRateToHome = "0.1"; row.lat = 41.0; row.lon = 29.0; row.tzID = "Europe/Istanbul"
                row.mode = "manual"; row.start = stamp; row.end = id == closedID ? stamp.addingTimeInterval(86_400) : nil; row.homeKm = 2_100
                row.createdAt = stamp; row.updatedAt = stamp; row.writerID = "synthetic-v12"
                old.mainContext.insert(row)
                let shape = Trip(); shape.id = id; shape.city = row.city; shape.country = row.country; shape.currency = row.currency
                shape.fxRateToHome = row.fxRateToHome; shape.lat = row.lat; shape.lon = row.lon; shape.tzID = row.tzID; shape.mode = row.mode
                shape.start = row.start; shape.end = row.end; shape.homeKm = row.homeKm
                shape.createdAt = stamp; shape.updatedAt = stamp; shape.writerID = row.writerID
                var record = try shape.record(); record.fields.removeValue(forKey: "journeyID"); before.append(record)
            }
            let movement = MadarFrozenMoneyTransactionV13.MoneyTransaction()
            movement.id = UUID(); movement.createdAt = stamp; movement.updatedAt = stamp; movement.writerID = "synthetic-v12"
            movement.dayKey = "2026-10-30"; movement.eventAt = stamp; movement.tzID = "Asia/Riyadh"; movement.dayPolicy = "fajr@1"
            movement.kind = "expense"; movement.amountMinor = 2_100; movement.currency = "SAR"
            movement.homeAmountMinor = 2_100; movement.homeCurrency = "SAR"; movement.merchant = "synthetic migration purchase"
            movement.method = "cash"; movement.source = "manual"; movement.reviewState = "ok"
            old.mainContext.insert(movement)
            let projectedMovement = MoneyTransaction()
            projectedMovement.id = movement.id; projectedMovement.createdAt = stamp; projectedMovement.updatedAt = stamp
            projectedMovement.writerID = movement.writerID; projectedMovement.dayKey = movement.dayKey
            projectedMovement.eventAt = movement.eventAt; projectedMovement.tzID = movement.tzID; projectedMovement.dayPolicy = movement.dayPolicy
            projectedMovement.kind = movement.kind; projectedMovement.amountMinor = movement.amountMinor
            projectedMovement.currency = movement.currency; projectedMovement.homeAmountMinor = movement.homeAmountMinor
            projectedMovement.homeCurrency = movement.homeCurrency; projectedMovement.merchant = movement.merchant
            projectedMovement.method = movement.method; projectedMovement.source = movement.source
            projectedMovement.reviewState = movement.reviewState
            var movementRecord = try projectedMovement.record(); movementRecord.fields.removeValue(forKey: "categorySource")
            before.append(movementRecord)
            before.append(contentsOf: try seedAllRoomMigrationRecords(in: old.mainContext, stamp: stamp))
            try old.mainContext.save()
        }
        try DurableFiles.encode(12, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        do {
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: upgraded.binding.syncedDirectory) == MadarSchema.version)
        let rows = try upgraded.container.mainContext.fetch(FetchDescriptor<Trip>())
        #expect(rows.count == 2 && rows.allSatisfy { $0.journeyID == nil && $0.fxRateToHome == "0.1" && $0.homeKm == 2_100 })
        #expect(rows.first { $0.id == openID }?.end == nil && rows.first { $0.id == closedID }?.currency == "EGP")
        let expected = try SchemaCompatibility.currentRecords(before, from: 12)
        try RecordValidator.validate(expected)
        #expect(Set(before.map(\.model)).isSuperset(of: ["PrayerLog", "HifzSession", "Entry", "Habit", "HabitLog", "Account", "Category", "MoneyTransaction", "Book", "ReadingSession", "Setting", "WidgetConfig", "DeviceSetting", "PageSchedule", "Trip"]))
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let leg = try #require(reopened.container.mainContext.fetch(FetchDescriptor<Trip>()).first { $0.id == openID })
        leg.journeyID = closedID; try reopened.container.mainContext.save()
        let sealed = try BackupCodec.export(records: RecordBridge.all(reopened.container.mainContext), passphrase: "synthetic journey password")
        let checked = try BackupCodec.validate(sealed, passphrase: "synthetic journey password")
        #expect(checked.records.first { $0.id == openID }?.fields["journeyID"] == .string(closedID.uuidString))
        #expect(checked.records.first { $0.id == closedID }?.fields["journeyID"] == .null)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        }
    }
    /// V14 adds optional category provenance; a V13 category survives unchanged and remains ineligible for learning.
    @Test func schemaV13UpgradePreservesPurchaseAndLeavesOldCategorySourceNil() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV14-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let rowID = UUID(), categoryID = UUID(), stamp = Date(timeIntervalSince1970: 1_797_000_000)
        let dayKey = "2026-11-01", tzID = "Asia/Riyadh", dayPolicy = "fajr@1"
        let source = MadarFrozenMoneyTransactionV13.MoneyTransaction()
        source.id = rowID; source.createdAt = stamp; source.updatedAt = stamp; source.writerID = "synthetic-v13"
        source.dayKey = dayKey; source.eventAt = stamp; source.tzID = tzID; source.dayPolicy = dayPolicy
        source.kind = "expense"; source.amountMinor = 4_200; source.currency = "SAR"; source.homeAmountMinor = 4_200
        source.homeCurrency = "SAR"; source.merchant = "مقهى تجريبي"; source.categoryID = categoryID
        source.reviewState = "ok"; source.source = "bank"
        var before: [DataRecord] = []
        do {
            let oldContainer = try ModelContainer(for: MadarSchemaV13.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV13.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV13.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            oldContainer.mainContext.autosaveEnabled = false
            oldContainer.mainContext.insert(source)
            before.append(contentsOf: try seedAllRoomMigrationRecords(in: oldContainer.mainContext, stamp: stamp))
            try oldContainer.mainContext.save()
        }

        let projected = MoneyTransaction(); projected.id = rowID; projected.createdAt = stamp; projected.updatedAt = stamp
        projected.writerID = "synthetic-v13"; projected.dayKey = dayKey; projected.eventAt = stamp
        projected.tzID = tzID; projected.dayPolicy = dayPolicy; projected.kind = "expense"
        projected.amountMinor = 4_200; projected.currency = "SAR"; projected.homeAmountMinor = 4_200
        projected.homeCurrency = "SAR"; projected.merchant = "مقهى تجريبي"; projected.categoryID = categoryID
        projected.reviewState = "ok"; projected.source = "bank"
        var projectedRecord = try projected.record(); projectedRecord.fields.removeValue(forKey: "categorySource")
        before.append(projectedRecord)
        let records = before
        try DurableFiles.encode(13, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID,
            recordsHash: try RecordFingerprint.hash(records), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil,
            accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        do {
        let upgraded = try ManagedDataStore(root: root)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let movement = try #require(upgraded.container.mainContext.fetch(FetchDescriptor<MoneyTransaction>()).first { $0.id == rowID })
        #expect(movement.amountMinor == 4_200 && movement.categoryID == categoryID && movement.categorySource == nil)
        let expected = try SchemaCompatibility.currentRecords(records, from: 13)
        #expect(expected.first { $0.model == "MoneyTransaction" }?.fields["categorySource"] == .null)
        try RecordValidator.validate(expected)
        #expect(Set(records.map(\.model)).isSuperset(of: ["PrayerLog", "HifzSession", "Entry", "Habit", "HabitLog", "Account", "Category", "MoneyTransaction", "Book", "ReadingSession", "Setting", "WidgetConfig", "DeviceSetting", "PageSchedule"]))
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        #expect(try stableGenerationHashes(generation) == sourceHash)
        }
    }

    /// V15 (FB-39, owner 6 Nov) adds optional HabitPolicy.intervalDays; a V14 weekly policy keeps every field and gets no interval.
    @Test func schemaV14UpgradeKeepsHabitPolicyAndLeavesIntervalNil() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV15-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let policyID = UUID(), habitID = UUID(), stamp = Date(timeIntervalSince1970: 1_797_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV14.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV14.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV14.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let row = MadarFrozenHabitPolicyV14.HabitPolicy()
            row.id = policyID; row.habitID = habitID; row.effectiveFrom = "2026-10-01"; row.frequency = "weekly"
            row.measure = "count"; row.unit = "pages"; row.target = 10; row.minimum = 4
            row.createdAt = stamp; row.updatedAt = stamp; row.writerID = "synthetic-v14"
            old.mainContext.insert(row)
            let shape = HabitPolicy(); shape.id = policyID; shape.habitID = habitID; shape.effectiveFrom = row.effectiveFrom
            shape.frequency = row.frequency; shape.measure = row.measure; shape.unit = row.unit
            shape.target = row.target; shape.minimum = row.minimum; shape.createdAt = stamp; shape.updatedAt = stamp; shape.writerID = row.writerID
            var record = try shape.record(); record.fields.removeValue(forKey: "intervalDays"); before.append(record)
            before.append(contentsOf: try seedAllRoomMigrationRecords(in: old.mainContext, stamp: stamp))
            try old.mainContext.save()
        }
        try DurableFiles.encode(14, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        do {
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let policy = try #require(upgraded.container.mainContext.fetch(FetchDescriptor<HabitPolicy>()).first { $0.id == policyID })
        #expect(policy.intervalDays == nil && policy.frequency == "weekly" && policy.target == 10 && policy.minimum == 4 && policy.habitID == habitID)
        let expected = try SchemaCompatibility.currentRecords(before, from: 14)
        #expect(expected.first { $0.model == "HabitPolicy" }?.fields["intervalDays"] == .null)
        try RecordValidator.validate(expected)
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let fresh = try #require(reopened.container.mainContext.fetch(FetchDescriptor<HabitPolicy>()).first { $0.id == policyID })
        fresh.frequency = "interval"; fresh.intervalDays = 3; try reopened.container.mainContext.save()
        let sealed = try BackupCodec.export(records: RecordBridge.all(reopened.container.mainContext), passphrase: "synthetic interval password")
        let checked = try BackupCodec.validate(sealed, passphrase: "synthetic interval password")
        #expect(checked.records.first { $0.id == policyID }?.fields["intervalDays"] == .number(3))
        #expect(try stableGenerationHashes(generation) == sourceHash)
        }
    }

    /// V16 adds optional metadata only. Existing voice bytes, transcripts, and daily intention outcomes survive unchanged.
    @Test func schemaV15UpgradeKeepsDiaryDataAndLeavesNewInsightsEmpty() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV16-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let intentionID = UUID(), mediaID = UUID(), stamp = Date(timeIntervalSince1970: 1_797_000_000)
        let audio = Data([0, 1, 2, 3, 250, 251, 252])
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV15.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV15.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV15.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false

            let intention = MadarFrozenDiaryV15.Niyya()
            intention.id = intentionID; intention.dayKey = "2026-10-01"; intention.order = 0
            intention.text = "أُنهي ما بدأت"; intention.result = "partial"
            intention.createdAt = stamp; intention.updatedAt = stamp; intention.writerID = "synthetic-v15"
            old.mainContext.insert(intention)
            let intentionShape = Niyya(); intentionShape.id = intentionID; intentionShape.dayKey = intention.dayKey
            intentionShape.order = intention.order; intentionShape.text = intention.text; intentionShape.result = intention.result
            intentionShape.createdAt = stamp; intentionShape.updatedAt = stamp; intentionShape.writerID = intention.writerID
            var intentionRecord = try intentionShape.record()
            intentionRecord.fields.removeValue(forKey: "weeklyReview"); intentionRecord.fields.removeValue(forKey: "monthlyReview")
            before.append(intentionRecord)

            let media = MadarFrozenDiaryV15.Media()
            media.id = mediaID; media.kind = "audio"; media.contentType = "audio/mp4"; media.data = audio
            media.sizeBytes = audio.count; media.sha256 = BackupCodec.hash(audio); media.durationS = 122
            media.createdAt = stamp; media.updatedAt = stamp; media.writerID = "synthetic-v15"
            old.mainContext.insert(media)
            let mediaShape = Media(); mediaShape.id = mediaID; mediaShape.kind = media.kind
            mediaShape.contentType = media.contentType; mediaShape.data = audio; mediaShape.sizeBytes = audio.count
            mediaShape.sha256 = media.sha256; mediaShape.durationS = media.durationS
            mediaShape.createdAt = stamp; mediaShape.updatedAt = stamp; mediaShape.writerID = media.writerID
            var mediaRecord = try mediaShape.record()
            mediaRecord.fields.removeValue(forKey: "title"); mediaRecord.fields.removeValue(forKey: "voiceTone")
            mediaRecord.fields.removeValue(forKey: "audioLevelsJSON"); before.append(mediaRecord)
            before.append(contentsOf: try seedAllRoomMigrationRecords(in: old.mainContext, stamp: stamp))
            try old.mainContext.save()
        }
        try DurableFiles.encode(15, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let loadedIntention = try #require(upgraded.container.mainContext.fetch(FetchDescriptor<Niyya>()).first { $0.id == intentionID })
        #expect(loadedIntention.text == "أُنهي ما بدأت" && loadedIntention.result == "partial")
        #expect(loadedIntention.weeklyReview == nil && loadedIntention.monthlyReview == nil)
        let loadedMedia = try #require(upgraded.container.mainContext.fetch(FetchDescriptor<Media>()).first { $0.id == mediaID })
        #expect(loadedMedia.data == audio && loadedMedia.durationS == 122)
        #expect(loadedMedia.title == nil && loadedMedia.voiceTone == nil && loadedMedia.audioLevelsJSON == nil)
        let expected = try SchemaCompatibility.currentRecords(before, from: 15)
        #expect(expected.first { $0.model == "Niyya" }?.fields["weeklyReview"] == .null)
        #expect(expected.first { $0.model == "Media" }?.fields["title"] == .null)
        try RecordValidator.validate(expected)
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expected))
        #expect(try stableGenerationHashes(generation) == sourceHash)
    }

    /// V17 only adds `AccountTail`, `BankReading` and `UpcomingDue`: every stored V16 row survives byte for byte and the new tables start empty.
    @Test func schemaV16UpgradeKeepsMoneyRowsAndStartsWithNoBankReadingsTailsOrDues() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV17-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let stamp = Date(timeIntervalSince1970: 1_797_000_000), accountID = UUID(), messageID = UUID()
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV16.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV16.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV16.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            let account = Account(); account.id = accountID; account.name = "synthetic account"; account.last4 = "1234"; account.balanceMinor = 50_000
            account.createdAt = stamp; account.updatedAt = stamp; account.writerID = "synthetic-v16"
            old.mainContext.insert(account); before.append(try account.record())
            let message = BankMessage(); message.id = messageID; message.text = "synthetic"; message.receivedAt = stamp
            message.createdAt = stamp; message.updatedAt = stamp; message.writerID = "synthetic-v16"
            old.mainContext.insert(message); before.append(try message.record())
            try old.mainContext.save()
        }
        try DurableFiles.encode(16, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        let context = upgraded.container.mainContext
        #expect(try context.fetch(FetchDescriptor<Account>()).first { $0.id == accountID }?.balanceMinor == 50_000)
        #expect(try context.fetch(FetchDescriptor<BankMessage>()).contains { $0.id == messageID })
        #expect(try context.fetchCount(FetchDescriptor<AccountTail>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<BankReading>()) == 0)
        #expect(try context.fetchCount(FetchDescriptor<UpcomingDue>()) == 0)
        let expected = try SchemaCompatibility.currentRecords(before, from: 16)
        #expect(expected == before)
        #expect(try RecordFingerprint.hash(RecordBridge.all(context, syncedOnly: false)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
    }

    @Test func schemaV11UpgradeKeepsHabitTimesWithoutADiaryLinkAndReopen() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarV12-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let oldID = UUID(), generation = root.appendingPathComponent("Generations/\(oldID.uuidString)")
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let liveID = UUID(), deadID = UUID(), habitID = UUID(), stamp = Date(timeIntervalSince1970: 1_797_000_000)
        var before: [DataRecord] = []
        do {
            let old = try ModelContainer(for: MadarSchemaV11.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV11.syncedTypes), url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV11.deviceTypes), url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)])
            old.mainContext.autosaveEnabled = false
            for id in [liveID, deadID] {
                let row = MadarFrozenHabitEventV11.HabitEvent()
                row.id = id; row.habitID = habitID; row.dayKey = id == liveID ? "2026-02-23" : "2026-03-01"; row.periodKey = row.dayKey
                row.delta = 1; row.eventAt = stamp; row.tzID = "Asia/Riyadh"; row.dayPolicy = "fajr@1"; row.weekStart = "saturday"
                row.createdAt = stamp; row.updatedAt = stamp; row.writerID = "synthetic-v11"
                if id == deadID { row.deletedAt = stamp; row.deletionBarrierAt = stamp }
                old.mainContext.insert(row)
                let shape = HabitEvent(); shape.id = row.id; shape.habitID = habitID; shape.dayKey = row.dayKey; shape.periodKey = row.periodKey
                shape.delta = 1; shape.eventAt = stamp; shape.tzID = row.tzID; shape.dayPolicy = row.dayPolicy; shape.weekStart = row.weekStart
                shape.createdAt = stamp; shape.updatedAt = stamp; shape.writerID = row.writerID
                shape.deletedAt = row.deletedAt; shape.deletionBarrierAt = row.deletionBarrierAt
                var record = try shape.record(); record.fields.removeValue(forKey: "entryID"); before.append(record)
            }
            try old.mainContext.save()
        }
        try DurableFiles.encode(11, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID, recordsHash: RecordFingerprint.hash(before), createdAt: stamp), to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil, accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        let sourceHash = try stableGenerationHashes(generation)
        let upgraded = try ManagedDataStore(root: root)
        #expect(upgraded.binding.generationID != oldID)
        #expect(try stableGenerationHashes(generation) == sourceHash)
        #expect(try MadarContainerFactory.storeVersionForAdoption(at: upgraded.binding.syncedDirectory) == MadarSchema.version)
        let rows = try upgraded.container.mainContext.fetch(FetchDescriptor<HabitEvent>())
        #expect(rows.count == 2 && rows.allSatisfy { $0.entryID == nil && $0.habitID == habitID && $0.delta == 1 })
        #expect(rows.first { $0.id == liveID }?.dayKey == "2026-02-23")
        #expect(rows.first { $0.id == deadID }?.deletionBarrierAt == stamp)
        let expected = try SchemaCompatibility.currentRecords(before, from: 11)
        #expect(try RecordFingerprint.hash(RecordBridge.all(upgraded.container.mainContext)) == RecordFingerprint.hash(expected))
        let reopened = try ManagedDataStore(root: root)
        #expect(reopened.binding.generationID == upgraded.binding.generationID)
        let live = try #require(reopened.container.mainContext.fetch(FetchDescriptor<HabitEvent>()).first { $0.id == liveID })
        let entry = UUID(); live.entryID = entry; try reopened.container.mainContext.save()
        let sealed = try BackupCodec.export(records: RecordBridge.all(reopened.container.mainContext), passphrase: "synthetic habit-link password")
        let checked = try BackupCodec.validate(sealed, passphrase: "synthetic habit-link password")
        #expect(checked.records.first { $0.id == liveID }?.fields["entryID"] == .string(entry.uuidString))
        #expect(try stableGenerationHashes(generation) == sourceHash)
    }

    @Test func schemaV2BackupValidationAndMergeRetainsPrayerLogWithoutFridayKind() async throws {
        let eventAt = Date(timeIntervalSince1970: 1_797_000_000)
        let sourceRow = try schemaV2PrayerRow(at: eventAt)
        let line = try JSONValue.object(sourceRow.fields).canonicalData() + Data([0x0a])
        var files = Dictionary(uniqueKeysWithValues: MadarSchemaV2.syncedNames.map { ("data/\($0).jsonl", Data()) })
        files["data/PrayerLog.jsonl"] = line
        let manifest = BackupManifest(
            formatVersion: 1, storeSchemaVersion: 2, createdAt: eventAt,
            counts: Dictionary(uniqueKeysWithValues: MadarSchemaV2.syncedNames.map { ($0, $0 == "PrayerLog" ? 1 : 0) }),
            files: files.map { BackupManifest.File(path: $0.key, bytes: $0.value.count, sha256: BackupCodec.hash($0.value)) }
                .sorted { $0.path < $1.path }
        )
        files["manifest.json"] = try JSONEncoder().encode(manifest)

        let backup = try BackupCodec.validateFiles(files, manifest: manifest, sourceModels: MadarSchemaV2.syncedNames)
        #expect(backup.manifest.storeSchemaVersion == 2)
        #expect(backup.records.count == 1)
        #expect(backup.records[0].fields["fridayKind"] == .null)
        let target = try MadarContainerFactory.makeInMemory()
        #expect(try BackupRestore.merge(backup, into: target.mainContext) == 1)
        let imported = try #require(target.mainContext.fetch(FetchDescriptor<PrayerLog>()).first)
        #expect(imported.fridayKind == nil)
    }
    private func schemaV2PrayerRow(at eventAt: Date) throws -> DataRecord {
        let logID = UUID(uuidString: "00000000-0000-0000-0000-000000000303")!
        return try DataRecord(model: "PrayerLog", fields: [
            "id": JSONValue.encode(logID), "createdAt": JSONValue.encode(eventAt), "updatedAt": JSONValue.encode(eventAt),
            "deletedAt": JSONValue.encode(Date?.none), "writerID": JSONValue.encode("fixture-device"),
            "mergedInto": JSONValue.encode(UUID?.none), "deletionBarrierAt": JSONValue.encode(Date?.none),
            "restoredAt": JSONValue.encode(Date?.none), "dayKey": JSONValue.encode("2026-10-09"),
            "prayer": JSONValue.encode("dhuhr"), "status": JSONValue.encode("jamaah"),
            "heart": JSONValue.encode(String?.none), "eventAt": JSONValue.encode(eventAt),
            "tzID": JSONValue.encode("Asia/Riyadh"), "dayPolicy": JSONValue.encode("prayerDay@1"),
            "loggedAt": JSONValue.encode(eventAt), "source": JSONValue.encode("app"),
            "tripID": JSONValue.encode(UUID?.none), "pairID": JSONValue.encode(UUID?.none),
            "shortened": JSONValue.encode(Bool?.none)
        ])
    }
    private func schemaV2ManagedFixture(_ base: URL) throws -> (URL, UUID, URL, DataRecord) {
        let root = base.appendingPathComponent("Managed", isDirectory: true)
        let oldID = UUID(uuidString: "00000000-0000-0000-0000-000000000203")!
        let generation = root.appendingPathComponent("Generations/\(oldID.uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: generation, withIntermediateDirectories: true)
        let eventAt = Date(timeIntervalSince1970: 1_797_000_000)
        let oldRow = try schemaV2PrayerRow(at: eventAt)
        try autoreleasepool {
            let oldContainer = try ModelContainer(for: MadarSchemaV2.schema, configurations: [
                ModelConfiguration("synced", schema: Schema(MadarSchemaV2.syncedTypes),
                    url: generation.appendingPathComponent("Madar.store"), cloudKitDatabase: .none),
                ModelConfiguration("deviceOnly", schema: Schema(MadarSchemaV2.deviceTypes),
                    url: root.appendingPathComponent("Device.store"), cloudKitDatabase: .none)
            ])
            oldContainer.mainContext.autosaveEnabled = false
            let oldLog = MadarSchemaV2.PrayerLog()
            oldLog.id = try oldRow.decode("id", as: UUID.self)
            oldLog.createdAt = eventAt; oldLog.updatedAt = eventAt; oldLog.writerID = "fixture-device"
            oldLog.dayKey = "2026-10-09"; oldLog.prayer = "dhuhr"; oldLog.status = "jamaah"
            oldLog.eventAt = eventAt; oldLog.tzID = "Asia/Riyadh"; oldLog.dayPolicy = "prayerDay@1"
            oldLog.loggedAt = eventAt
            oldContainer.mainContext.insert(oldLog)
            let receiptID = UUID(uuidString: "00000000-0000-0000-0000-000000000403")!
            let receipt = CommandReceipt()
            receipt.id = receiptID; receipt.commandID = UUID(uuidString: "00000000-0000-0000-0000-000000000503")!
            receipt.name = "prayer.log"; receipt.payloadHash = "synthetic-prayer"; receipt.status = "applied"
            receipt.undoJSON = Data("synthetic-undo".utf8); receipt.expiresAt = eventAt.addingTimeInterval(86400)
            receipt.undoExpiresAt = eventAt.addingTimeInterval(600)
            oldContainer.mainContext.insert(receipt)
            let scope = DeviceSetting()
            scope.id = UUID(uuidString: "00000000-0000-0000-0000-000000000603")!
            scope.key = "sys.commandReceiptScope:\(receiptID.uuidString)"
            scope.valueJSON = try JSONEncoder().encode(ReceiptScope(version: 1, generationID: oldID))
            oldContainer.mainContext.insert(scope)
            try oldContainer.mainContext.save()
        }
        try DurableFiles.encode(2, to: generation.appendingPathComponent("SchemaVersion.json"))
        try DurableFiles.encode(1, to: root.appendingPathComponent("DeviceSchemaVersion.json"))
        try DurableFiles.encode(GenerationReady(version: 1, generationID: oldID,
            recordsHash: try RecordFingerprint.hash([oldRow]), createdAt: eventAt),
            to: generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version: 1, generationID: oldID, previousGenerationID: nil,
            accountHash: nil, cloudKitContainerIdentifier: nil), to: root.appendingPathComponent("ActiveGeneration.json"))
        return (root, oldID, generation, oldRow)
    }
    private func assertReceiptScope(in context: ModelContext, generationID: UUID) throws {
        let receipt = try #require(context.fetch(FetchDescriptor<CommandReceipt>()).first)
        let scope = try #require(context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == "sys.commandReceiptScope:\(receipt.id.uuidString)" })
        let decoded = try JSONDecoder().decode(ReceiptScope.self, from: scope.valueJSON)
        #expect(decoded.version == 1 && decoded.generationID == generationID)
        #expect(receipt.undoJSON == Data("synthetic-undo".utf8))
    }
    private func fileHashes(_ directory: URL) throws -> [String:String] {
        let files = try #require(FileManager.default.enumerator(atPath:directory.path))
        var result: [String:String] = [:]
        for case let relativePath as String in files {
            let url = directory.appendingPathComponent(relativePath)
            if try url.resourceValues(forKeys:[.isRegularFileKey]).isRegularFile == true {
                result[relativePath] = BackupCodec.hash(try Data(contentsOf:url))
            }
        }
        return result
    }
    private func seedAllRoomMigrationRecords(in context: ModelContext, stamp: Date) throws -> [DataRecord] {
        var records: [DataRecord] = []
        func save(_ row: any MadarRecordModel) throws {
            context.insert(row)
            records.append(try row.record())
        }

        let prayer = PrayerLog()
        prayer.dayKey = "2026-10-30"; prayer.prayer = "dhuhr"; prayer.status = "alone"
        prayer.eventAt = stamp; prayer.tzID = "Asia/Riyadh"; prayer.dayPolicy = "prayerDay@1"
        prayer.loggedAt = stamp; prayer.writerID = "synthetic-room-fixture"
        try save(prayer)

        let quran = HifzSession()
        quran.dayKey = "2026-10-30"; quran.endedAt = stamp; quran.tzID = "Asia/Riyadh"; quran.dayPolicy = "fajr@1"
        quran.kind = "hifz"; quran.fromAyah = 4; quran.toAyah = 6; quran.pages = [42]; quran.mistakes = 1
        quran.method = "coach"; quran.writerID = "synthetic-room-fixture"
        try save(quran)

        let entry = Entry()
        entry.dayKey = "2026-10-30"; entry.eventAt = stamp; entry.tzID = "Asia/Riyadh"; entry.dayPolicy = "fajr@1"
        entry.text = "synthetic migration diary entry"; entry.writerID = "synthetic-room-fixture"
        try save(entry)

        let habit = Habit()
        habit.name = "synthetic migration habit"; habit.kind = "custom"; habit.writerID = "synthetic-room-fixture"
        try save(habit)
        let habitLog = HabitLog()
        habitLog.habitID = habit.id; habitLog.periodKey = "2026-10-30"; habitLog.value = 2
        habitLog.eventAt = stamp; habitLog.tzID = "Asia/Riyadh"; habitLog.dayPolicy = "fajr@1"
        habitLog.writerID = "synthetic-room-fixture"
        try save(habitLog)

        let account = Account()
        account.name = "synthetic migration account"; account.kind = "savings"; account.currency = "SAR"
        account.balanceMinor = 125_000; account.writerID = "synthetic-room-fixture"
        try save(account)
        let category = Category()
        category.name = "synthetic migration category"; category.icon = "cup.and.saucer"; category.color = "clay"
        category.order = 3; category.writerID = "synthetic-room-fixture"
        try save(category)

        let book = Book()
        book.title = "synthetic migration book"; book.author = "fixture"; book.kind = "paper"; book.shelf = "reading"
        book.pages = 120; book.currentPage = 37; book.readCount = 1; book.writerID = "synthetic-room-fixture"
        try save(book)
        let reading = ReadingSession()
        reading.bookID = book.id; reading.start = stamp.addingTimeInterval(-900); reading.end = stamp
        reading.activeSeconds = 900; reading.fromPage = 34; reading.toPage = 37; reading.pagesCounted = 3
        reading.startProgression = 0.27; reading.endProgression = 0.31; reading.dayKey = "2026-10-30"
        reading.tzID = "Asia/Riyadh"; reading.dayPolicy = "fajr@1"; reading.writerID = "synthetic-room-fixture"
        try save(reading)

        let setting = Setting()
        setting.key = "core.firstCalendar"; setting.valueJSON = Data("\"hijri\"".utf8)
        setting.writerID = "synthetic-room-fixture"
        try save(setting)
        let widget = WidgetConfig()
        widget.name = "synthetic migration widget"; widget.familyID = "small"; widget.items = ["prayer.today"]
        widget.styleJSON = Data("{}".utf8); widget.writerID = "synthetic-room-fixture"
        try save(widget)

        let deviceSetting = DeviceSetting()
        deviceSetting.key = "synthetic.migration.fixture"; deviceSetting.valueJSON = Data("true".utf8)
        deviceSetting.writerID = "synthetic-room-fixture"
        try save(deviceSetting)
        let schedule = PageSchedule()
        schedule.page = 77; schedule.stage = 4; schedule.ease = 1.2; schedule.nextDue = "2026-11-02"
        schedule.lastReviewedAt = stamp; schedule.lastGrade = "good"; schedule.scheduleVersion = 1
        schedule.writerID = "synthetic-room-fixture"
        try save(schedule)
        return records
    }
    private func stableGenerationHashes(_ directory: URL) throws -> [String:String] {
        let files = try #require(FileManager.default.enumerator(atPath: directory.path))
        var result: [String:String] = [:]
        for case let relativePath as String in files {
            guard !relativePath.hasSuffix("-wal"), !relativePath.hasSuffix("-shm") else { continue }
            let url = directory.appendingPathComponent(relativePath)
            if try url.resourceValues(forKeys: [.isRegularFileKey]).isRegularFile == true {
                result[relativePath] = BackupCodec.hash(try Data(contentsOf: url))
            }
        }
        return result
    }
    @Test func test_M0S1_RA4_fileHashesKeepSourcePathsRelativeAndOnlyExcludeRootLock() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("MadarFileHashesTest-\(UUID())")
        defer { try? FileManager.default.removeItem(at:root) }
        let sourcePaths = ["Device.store", "Device.store-wal", "Device.store-shm", "DeviceSchemaVersion.json",
                           "ActiveGeneration.json", "Generations/old/Madar.store", "Generations/old/GenerationReady.json",
                           "Generations/old/SchemaVersion.json", "Media/photo.bin", "Media/CommandBus.lock"]
        let expectedHash = "2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824" // SHA-256 of "hello".
        for path in sourcePaths {
            let file = root.appendingPathComponent(path)
            try FileManager.default.createDirectory(at:file.deletingLastPathComponent(),withIntermediateDirectories:true)
            try Data("hello".utf8).write(to:file)
        }
        let before = try fileHashes(root)
        #expect(before == Dictionary(uniqueKeysWithValues:sourcePaths.map { ($0,expectedHash) }))
        try Data().write(to:root.appendingPathComponent("CommandBus.lock"))
        let after = try fileHashes(root)
        #expect(after["CommandBus.lock"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(after.filter { $0.key != "CommandBus.lock" } == before)
        #expect(after["Media/CommandBus.lock"] == expectedHash)
        try Data("changed".utf8).write(to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        #expect(try fileHashes(root).filter { $0.key != "CommandBus.lock" } != before)
    }
    private func oldManagedFixture(_ base: URL) throws -> (URL,UUID,URL) {
        let root = base.appendingPathComponent("ManagedV1")
        let id = UUID(uuidString:"00000000-0000-0000-0000-000000000099")!
        let generation = root.appendingPathComponent("Generations/\(id.uuidString)")
        try FileManager.default.createDirectory(at:generation.deletingLastPathComponent(),withIntermediateDirectories:true)
        try FileManager.default.copyItem(at:base.appendingPathComponent("Flat"),to:generation)
        for url in try FileManager.default.contentsOfDirectory(at:generation,includingPropertiesForKeys:nil) where url.lastPathComponent.hasPrefix("Device.store") {
            try FileManager.default.moveItem(at:url,to:root.appendingPathComponent(url.lastPathComponent))
        }
        try DurableFiles.encode(1,to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        let old = try JSONDecoder().decode([DataRecord].self,from:Data(contentsOf:resources.appendingPathComponent("records.json")))
        try DurableFiles.encode(GenerationReady(version:1,generationID:id,recordsHash:try RecordFingerprint.hash(old.filter { MadarSchemaV1.syncedNames.contains($0.model) }),createdAt:Date(timeIntervalSince1970:123456)),to:generation.appendingPathComponent("GenerationReady.json"))
        try DurableFiles.encode(ManagedPointer(version:1,generationID:id,previousGenerationID:nil,accountHash:"legacy-account",cloudKitContainerIdentifier:"iCloud.legacy.fixture"),to:root.appendingPathComponent("ActiveGeneration.json"))
        return (root,id,generation)
    }
    @Test(arguments:[LegacyGenerationMigration.Checkpoint.afterCopy,.afterStaging,.afterPointer])
    func test_M0S1_RA4_managedMigrationRecoversAtEveryCommitBoundary(_ checkpoint: LegacyGenerationMigration.Checkpoint) async throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let (root,oldID,generation) = try oldManagedFixture(base)
        let originalHashes = try fileHashes(generation)
        let pointerBytes = try Data(contentsOf:root.appendingPathComponent("ActiveGeneration.json"))
        #expect(throws:BackupOperationError.simulatedInterruption("migration \(checkpoint.rawValue)")) {
            try ManagedDataStore(root:root,migrationInterruption:checkpoint)
        }
        #expect(try fileHashes(generation) == originalHashes)
        if checkpoint != .afterPointer { #expect(try Data(contentsOf:root.appendingPathComponent("ActiveGeneration.json")) == pointerBytes) }
        let migrated = try ManagedDataStore(root:root)
        #expect(migrated.binding.generationID != oldID)
        #expect(migrated.binding.accountHash == "legacy-account" && !migrated.isCloudBacked)
        #expect(migrated.recoveryRequiresRefresh)
        let pointer = try JSONDecoder().decode(ManagedPointer.self,from:Data(contentsOf:root.appendingPathComponent("ActiveGeneration.json")))
        #expect(pointer.previousGenerationID == oldID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(migrated.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
        #expect(try fileHashes(generation) == originalHashes)
        let reopened = try ManagedDataStore(root:root)
        #expect(reopened.binding.generationID == migrated.binding.generationID)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
        #expect(!FileManager.default.fileExists(atPath:root.appendingPathComponent("SchemaMigration.json").path))
        let coordinator = BackupCoordinator(store:reopened,backupDirectory:base.appendingPathComponent("Backups"),keyStore:MemoryBackupKeyStore())
        #expect(try await coordinator.recoverPendingLifecycle().isEmpty)
        #expect(!reopened.recoveryRequiresRefresh)
        #expect(try RecordFingerprint.hash(RecordBridge.all(reopened.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
    }
    @Test func test_M0S1_RA4_invalidDeviceStampNeverPromotesOrChangesOldSource() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let (root,_,generation) = try oldManagedFixture(base)
        try DurableFiles.encode(999,to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        let hashes = try fileHashes(root)
        #expect(hashes["CommandBus.lock"] == nil)
        #expect(throws:DataError.newerStore) { try ManagedDataStore(root:root) }
        let after = try fileHashes(root)
        #expect(after["CommandBus.lock"] == "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855")
        #expect(after.filter { $0.key != "CommandBus.lock" } == hashes)
        #expect(try MadarContainerFactory.storeVersion(at:generation) == 1)
        try DurableFiles.encode(1,to:root.appendingPathComponent("DeviceSchemaVersion.json"))
        let repaired = try ManagedDataStore(root:root)
        #expect(try RecordFingerprint.hash(RecordBridge.all(repaired.container.mainContext,syncedOnly:false)) == RecordFingerprint.hash(expectedRows()))
    }
    @Test func test_M0S1_RA4_flatSourceIsByteIdenticalAndNeverOpenedByCurrentFactory() throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at:base) }
        let flat = base.appendingPathComponent("Flat"); let before = try fileHashes(flat)
        #expect(throws:DataError.legacyStoreRequiresAdoption) { try MadarContainerFactory.makeLocal(at:flat) }
        _ = try ManagedDataStore.adoptLegacy(from:flat,at:base.appendingPathComponent("Adopted"))
        #expect(try fileHashes(flat) == before)
    }

    @Test func test_M0S1_M0R4_01_committedRestoreCleanupSurvivesMigrationAndReopen() async throws {
        for phase in [RestoreJournal.Phase.ready, .promoted] {
            for checkpoint in [LegacyGenerationMigration.Checkpoint.afterCopy, .afterStaging, .afterHooksJournal, .afterPointer] {
                let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
                let (root, id, generation) = try oldManagedFixture(base)
                let sourceHashes = try fileHashes(generation)
                try DurableFiles.encode(RestoreJournal(operationID: UUID(), oldGenerationID: UUID(), newGenerationID: id, phase: phase, hooksPending: true), to: root.appendingPathComponent("RestoreJournal.json"))
                #expect(throws: BackupOperationError.simulatedInterruption("migration \(checkpoint.rawValue)")) {
                    try ManagedDataStore(root: root, migrationInterruption: checkpoint)
                }
                let store = try ManagedDataStore(root: root)
                let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
                #expect(try await coordinator.recoverPendingLifecycle().isEmpty)
                let context = store.container.mainContext
                #expect(try context.fetchCount(FetchDescriptor<PageSchedule>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<SessionDraft>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<ProcessingJob>()) == 0)
                #expect(try context.fetchCount(FetchDescriptor<CommandReceipt>()) == 1)
                #expect(try fileHashes(generation) == sourceHashes)
                #expect(!store.recoveryRequiresRefresh)
            }
        }
    }
    @Test func test_M0S1_M0R4_01_uncommittedRestorePreservesDeviceRowsAndRejectsMismatch() async throws {
        for phase in [RestoreJournal.Phase.preparing, .ready] {
            let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
            let (root, id, _) = try oldManagedFixture(base)
            let abandoned = UUID(); let staging = root.appendingPathComponent("Generations/\(abandoned.uuidString)")
            try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
            try DurableFiles.encode(RestoreJournal(operationID: UUID(), oldGenerationID: id, newGenerationID: abandoned, phase: phase, hooksPending: true), to: root.appendingPathComponent("RestoreJournal.json"))
            let store = try ManagedDataStore(root: root)
            let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
            #expect(try await coordinator.recoverPendingLifecycle().isEmpty)
            #expect(try RecordFingerprint.hash(RecordBridge.all(store.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expectedRows()))
            #expect(!FileManager.default.fileExists(atPath: staging.path))
        }
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let (root, _, _) = try oldManagedFixture(base)
        try DurableFiles.encode(RestoreJournal(operationID: UUID(), oldGenerationID: UUID(), newGenerationID: UUID(), phase: .ready, hooksPending: true), to: root.appendingPathComponent("RestoreJournal.json"))
        let before = try fileHashes(root)
        #expect(throws: BackupOperationError.invalidManagedStore) { try ManagedDataStore(root: root) }
        #expect(try fileHashes(root).filter { $0.key != "CommandBus.lock" } == before)
    }

    @Test func test_M0S1_M0R4_02_flatAdoptionPreflightsDeviceStampWithoutTargetWrites() throws {
        for stamp in ["999", "0", "-1", "\"malformed\"", "{"] {
            let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
            let flat = base.appendingPathComponent("Flat"); let target = base.appendingPathComponent("Adopted")
            try Data(stamp.utf8).write(to: flat.appendingPathComponent("DeviceSchemaVersion.json"))
            let before = try fileHashes(flat)
            if stamp == "999" {
                #expect(throws: DataError.newerStore) { try ManagedDataStore.adoptLegacy(from: flat, at: target) }
            } else {
                #expect(throws: (any Error).self) { try ManagedDataStore.adoptLegacy(from: flat, at: target) }
            }
            #expect(try fileHashes(flat) == before)
            #expect(!FileManager.default.fileExists(atPath: target.path))
            #expect(!FileManager.default.fileExists(atPath: base.appendingPathComponent("Adopted-AdoptionJournal.json").path))
        }
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let flat = base.appendingPathComponent("Flat"); let stamp = flat.appendingPathComponent("DeviceSchemaVersion.json")
        if FileManager.default.fileExists(atPath: stamp.path) { try FileManager.default.removeItem(at: stamp) }
        let before = try fileHashes(flat)
        let adopted = try ManagedDataStore.adoptLegacy(from: flat, at: base.appendingPathComponent("Adopted"))
        #expect(try RecordFingerprint.hash(RecordBridge.all(adopted.container.mainContext, syncedOnly: false)) == RecordFingerprint.hash(expectedRows()))
        #expect(try fileHashes(flat) == before)
    }

    @Test func test_M0S1_M0R4_03_legacyMoneyPreviewUsesConvertedCountsPreservingManifest() async throws {
        let base = try fixtureDirectory(); defer { try? FileManager.default.removeItem(at: base) }
        let oldRows = try JSONDecoder().decode([DataRecord].self, from: Data(contentsOf: resources.appendingPathComponent("records.json"))).filter { $0.model == "Transaction" }
        #expect(oldRows.count == 2)
        var files: [String: Data] = [:]
        for model in MadarSchemaV1.syncedNames {
            var data = Data()
            for row in oldRows where row.model == model { data += try JSONValue.object(row.fields).canonicalData() + Data([0x0a]) }
            files["data/\(model).jsonl"] = data
        }
        let manifest = BackupManifest(formatVersion: 1, storeSchemaVersion: 1, createdAt: Date(timeIntervalSince1970: 2_000_000_000), counts: Dictionary(uniqueKeysWithValues: MadarSchemaV1.syncedNames.map { ($0, $0 == "Transaction" ? 2 : 0) }), files: files.map { .init(path: $0.key, bytes: $0.value.count, sha256: BackupCodec.hash($0.value)) })
        files["manifest.json"] = try JSONEncoder().encode(manifest)
        let archive = try BackupCodec.encodeArchive(files); #expect(archive.count < 1024 * 1024)
        let credential = try BackupCredential.derive(passphrase: "legacy fixture password")
        let prefix = Data([1, 2, 3, 4])
        let header = BackupHeader(magic: "MADARBK", formatVersion: 1, appVersion: "review-regression", storeSchemaVersion: 1, createdAt: manifest.createdAt, kdf: .init(alg: "PBKDF2-HMAC-SHA256", iterations: 600000, salt: credential.salt), cipher: "AES-256-GCM", chunkSize: 1024 * 1024, chunkCount: 1, noncePrefix: prefix)
        let headerBytes = try JSONEncoder().encode(header)
        let index = BackupCodec.integer(0, bytes: 8)
        let sealed = try AES.GCM.seal(archive, using: SymmetricKey(data: credential.keyData), nonce: AES.GCM.Nonce(data: prefix + index), authenticating: headerBytes + index + Data([1]))
        let body = sealed.ciphertext + sealed.tag
        let bytes = BackupCodec.integer(UInt64(headerBytes.count), bytes: 4) + headerBytes + BackupCodec.integer(UInt64(body.count), bytes: 4) + body
        let legacyURL = base.appendingPathComponent("TransactionOnly.madarbackup"); try bytes.write(to: legacyURL)
        let store = try ManagedDataStore(root: base.appendingPathComponent("Managed"))
        let coordinator = BackupCoordinator(store: store, backupDirectory: base.appendingPathComponent("Backups"), keyStore: MemoryBackupKeyStore())
        let preview = try await coordinator.preview(file: legacyURL, passphrase: "legacy fixture password")
        #expect(preview.counts["MoneyTransaction"] == 2); #expect(preview.counts["Transaction"] == nil)
        #expect(preview.additions == 2); #expect(preview.counts.values.reduce(0, +) == 2)
        #expect(preview.validated.manifest.counts["Transaction"] == 2)
        #expect(preview.validated.manifest.counts["MoneyTransaction"] == nil)
        #expect(preview.validated.manifest.files.contains { $0.path == "data/Transaction.jsonl" })
        #expect(try Data(contentsOf: legacyURL) == bytes)
        let currentRows = try SchemaCompatibility.currentRecords(oldRows, from: 1)
        let currentURL = base.appendingPathComponent("Current.madarbackup")
        try BackupCodec.export(records: currentRows, passphrase: "legacy fixture password").write(to: currentURL)
        let current = try await coordinator.preview(file: currentURL, passphrase: "legacy fixture password")
        #expect(current.counts == current.validated.manifest.counts)
        #expect(current.counts["MoneyTransaction"] == 2)
    }

}
