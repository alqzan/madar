import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarPrayer

public enum MoneyCommandError: String, Error, Sendable {
    case missingRow, invalidAmount, invalidCurrency, missingRate, ambiguousAccount, cardKindRequired
    case invalidSplit, invalidReference, alreadyConfirmed, salaryNeedsCycleConfirmation, undoSuperseded
}

public struct MoneyParsedFields: Codable, Sendable {
    public var v = 1
    public var kind: String
    public var amountMinor: Int?
    public var currency: String?
    public var last4: String?
    public var cardKind: String?
    public var merchant: String?
    public var biller: String?
    public var provider: String?
    public var eventAt: Date?
    public var statementDueMinor: Int?
    public var minimumDueMinor: Int?
    public var dueDate: Date?
    public var balanceMinor: Int?
    public var statedHomeMinor: Int?
    init(_ p: ParsedBankMessage) {
        kind = p.kind.rawValue; amountMinor = p.amountMinor; currency = p.currency; last4 = p.last4
        cardKind = p.cardKind?.rawValue; merchant = p.merchant; biller = p.biller; provider = p.provider
        eventAt = p.eventAt; statedHomeMinor = p.statedHomeMinor; statementDueMinor = p.statementDueMinor; minimumDueMinor = p.minimumDueMinor
        dueDate = p.dueDate; balanceMinor = p.balanceMinor
    }
}

struct MoneyStagedResult { var inverse: Data?; var duplicate: Bool }
private struct MoneyInverse: Codable { var v = 1; var before: [DataRecord]; var after: [DataRecord]; var reserveGoalID: UUID? = nil }

/// Stages only, under DurableCommandAdapter's lease. The receipt, movement, allocations and
/// source messages are saved together. No producer/extension opens SwiftData.
@MainActor public enum MoneyMutationHandler {
    static func discards(name: String, payload: [String: MadarCore.JSONValue]) -> Bool {
        if name == MoneyCommandPayload.intakeName {
            return discard(text(payload, "text"))
        }
        if name == "money.pasteBankMessages", case .array(let values) = payload["messages"] {
            return values.allSatisfy { if case .object(let p) = $0 { discard(text(p, "text")) } else { false } }
        }
        return false
    }
    private static func discard(_ text: String) -> Bool {
        let decision = BankIntake.decision(BankMessageParser.classify(text))
        return decision == .discard || decision == .discardWithoutText
    }
    static func stage(name: String, payload p: [String: MadarCore.JSONValue], id: UUID, issuedAt: Date,
                      source: CommandSource, context: ModelContext, now: Date, writer: String) throws -> MoneyStagedResult {
        if name == "money.markVisit" {
            // «منذ آخر زيارة»: a per-device marker, never synced and never undone.
            let key = "sys.moneyLastVisit", value = Data(("\"" + ISO8601DateFormatter().string(from: now) + "\"").utf8)
            let row = try context.fetch(FetchDescriptor<DeviceSetting>()).first { $0.key == key && $0.deletedAt == nil } ?? { let r = DeviceSetting(); r.key = key; r.createdAt = now; context.insert(r); return r }()
            row.valueJSON = value; try touch(row, now, writer)
            return .init(inverse: nil, duplicate: false)
        }
        let before = try records(context)
        switch name {
        case "money.prepareGoal":
            let reading = try MoneyRepository(context: context).goalPreparation(at: now)
            guard reading.signature == text(p, "signature"), let total = MoneyCommandPayload.integer(p["totalMinor"]),
                  let upfront = MoneyCommandPayload.integer(p["upfrontMinor"]), let daily = MoneyCommandPayload.integer(p["dailyMinor"]),
                  let due = MoneyCommandPayload.date(p["due"]), due >= now, case .array(let rawIDs) = p["paidIDs"] else { throw MoneyCommandError.invalidReference }
            let ids = Set(rawIDs.compactMap { value -> UUID? in if case .string(let raw) = value { UUID(uuidString: raw) } else { nil } })
            let paid = reading.paid.filter { ids.contains($0.id) }
            guard paid.count == ids.count else { throw MoneyCommandError.invalidReference }
            let already = try sum(paid.map(\.amountMinor))
            guard total > already else { throw MoneyCommandError.invalidAmount }
            let target = total - already, source = text(p, "source")
            guard upfront <= target, upfront <= max(0, source == "surplus" ? reading.surplusMinor : reading.reserveMinor),
                  daily <= reading.dailyMinor, upfront == target || daily > 0, reading.cycleID != nil || upfront == target else { throw MoneyCommandError.invalidAmount }
            let envelope = Envelope(); envelope.id = id; envelope.name = text(p, "name"); envelope.role = "goal"; envelope.targetMinor = target; envelope.due = due; envelope.createdAt = now; envelope.updatedAt = now; envelope.writerID = writer; context.insert(envelope)
            if daily > 0 && upfront < target {
                let plan = EnvelopePlan(); plan.id = id; plan.envelopeID = id; plan.source = "daily"; plan.period = "perDay"; plan.perPaycheckMinor = daily; plan.startDayKey = reading.today.adding(days: 1).description; plan.createdAt = now; plan.updatedAt = now; plan.writerID = writer; context.insert(plan)
            }
            if upfront > 0 {
                let key = "goal-fund:" + id.uuidString
                try writeAllocations([
                    .init(groupID: key, target: source == "reserve" ? .reserve : .surplus, amountMinor: -upfront, kind: .fund, idempotencyKey: key + ":from"),
                    .init(groupID: key, target: .envelope(id.uuidString), amountMinor: upfront, kind: .fund, idempotencyKey: key + ":to")
                ], context: context, now: now, writer: writer)
            }
        case "money.saveZakat":
            let profiles = try context.fetch(FetchDescriptor<ZakatProfile>()).filter { live($0) }
            guard profiles.count <= 1, try MoneyRepository.zakatSignature(profiles.first) == text(p, "signature") else { throw MoneyCommandError.invalidReference }
            let hawl = text(p, "hawl")
            if !hawl.isEmpty {
                let parts = hawl.hasPrefix("h:") ? String(hawl.dropFirst(2)).split(separator: "-").compactMap { Int($0) } : []
                guard parts.count == 3, (1...9999).contains(parts[0]), (1...12).contains(parts[1]), (1...30).contains(parts[2]) else { throw MoneyCommandError.invalidReference }
                var calendar = Calendar(identifier: .islamicUmmAlQura); calendar.timeZone = .gmt
                guard let date = calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2])), calendar.component(.day, from: date) == parts[2] else { throw MoneyCommandError.invalidReference }
            }
            let row: ZakatProfile
            if let old = profiles.first { row = old }
            else {
                let all = try context.fetch(FetchDescriptor<ZakatProfile>())
                guard all.count <= 1, all.first?.mergedInto == nil else { throw MoneyCommandError.invalidReference }
                if let old = all.first {
                    row = old; var record = try old.record()
                    let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
                    try record.set(Optional<Date>.none, for: "deletedAt"); try record.set(stamp, for: "restoredAt"); try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID"); try old.apply(record)
                } else { row = ZakatProfile(); row.id = StableIdentity.uuid(for: "ZakatProfile:singleton"); row.createdAt = now; context.insert(row) }
            }
            let gold = MoneyCommandPayload.integer(p["goldPriceMinor"]), silver = MoneyCommandPayload.integer(p["silverPriceMinor"])
            if gold != row.goldPricePerGramMinor || profiles.isEmpty { row.goldPricePerGramMinor = gold; row.goldPriceSetAt = gold == nil ? nil : now }
            if silver != row.silverPricePerGramMinor || profiles.isEmpty { row.silverPricePerGramMinor = silver; row.silverPriceSetAt = silver == nil ? nil : now }
            row.nisabBasis = text(p, "basis"); row.debtsPolicy = text(p, "debts"); row.nisabMg = MoneyCommandPayload.integer(p["goldMg"]) ?? 85000; row.nisabSilverMg = MoneyCommandPayload.integer(p["silverMg"]) ?? 595000
            row.otherAssetsMinor = MoneyCommandPayload.integer(p["otherMinor"]) ?? 0; row.hawlStartHijri = hawl
            try touch(row, now, writer)
        case "money.repriceTrip":
            guard let tripID = uuid(p, "id"), let trip = try context.fetch(FetchDescriptor<Trip>()).first(where: { $0.id == tripID && live($0) }), trip.fxRateToHome == text(p, "rate") else { throw MoneyCommandError.invalidReference }
            let preview = try MoneyRepository(context: context).previewTripReprice(id: tripID, rate: text(p, "rate"), at: now)
            guard preview.signature == text(p, "signature"), !preview.lines.isEmpty else { throw MoneyCommandError.invalidReference }
            for line in preview.lines {
                let row = try transaction(line.id, context); row.homeAmountMinor = line.afterMinor; row.rateAtTime = text(p, "rate"); row.rateSource = "trip"; try touch(row, now, writer)
            }
            for row in try context.fetch(FetchDescriptor<Allocation>()) {
                if let value = preview.allocations[row.id] { row.amountMinor = value; try touch(row, now, writer) }
            }
        case "money.configureTrip":
            try configureTrip(p, context: context, now: now, writer: writer)
        case "money.fundTrip":
            try fundTrip(p, commandID: id, context: context, now: now, writer: writer)
        case "money.distributeBigExpense":
            try distributeBigExpense(p, id: id, issuedAt: issuedAt, context: context, now: now, writer: writer)
        case "money.accruePlans":
            if let cycle = try MoneyRepository(context: context).cycle(at: now) {
                try accrueDailyPlans(cycle, through: cycle.elapsedDays, context: context, now: now, writer: writer)
            }
        case "money.setEnvelopeSaving":
            guard let planID = uuid(p, "id"), let amount = MoneyCommandPayload.integer(p["amountMinor"]), amount >= 0,
                  let plan = try context.fetch(FetchDescriptor<EnvelopePlan>()).first(where: { $0.id == planID && live($0) }),
                  plan.kind == "fund", plan.source == "salary", plan.period == "perCycle", plan.perPaycheckMinor == MoneyCommandPayload.integer(p["expectedMinor"]),
                  let envelopeID = plan.envelopeID,
                  try context.fetch(FetchDescriptor<Envelope>()).contains(where: { $0.id == envelopeID && live($0) && !["reserve", "surplus"].contains($0.role) }) else { throw MoneyCommandError.invalidReference }
            if plan.perPaycheckMinor != amount { plan.perPaycheckMinor = amount; try touch(plan, now, writer) }
        case "money.repayEnvelopeNow":
            guard let envelopeID = uuid(p, "id"),
                  let envelope = try context.fetch(FetchDescriptor<Envelope>()).first(where: { $0.id == envelopeID && live($0) }),
                  !["reserve", "surplus"].contains(envelope.role), let debt = MoneyCommandPayload.integer(p["debtMinor"]) else { throw MoneyCommandError.invalidReference }
            let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) }
            let balance = try sum(allocations.filter { $0.targetID == envelopeID }.map(\.amountMinor))
            guard balance < 0, -balance == debt else { throw MoneyCommandError.invalidAmount }
            let role = text(p, "source"), roleIDs = Set(try context.fetch(FetchDescriptor<Envelope>()).filter { live($0) && $0.role == role }.map(\.id))
            let available = try sum(allocations.filter { ($0.target == role && $0.targetID == nil) || $0.targetID.map(roleIDs.contains) == true }.map(\.amountMinor))
            guard available >= debt else { throw MoneyCommandError.invalidAmount }
            let key = "repay-now:" + id.uuidString, from: AllocationTarget = role == "reserve" ? .reserve : .surplus
            try writeAllocations([
                .init(groupID: key, target: from, amountMinor: -debt, kind: .repay, idempotencyKey: key + ":from"),
                .init(groupID: key, target: .envelope(envelopeID.uuidString), amountMinor: debt, kind: .repay, idempotencyKey: key + ":to")
            ], context: context, now: now, writer: writer)
        case "money.adoptRepayment":
            // M5-V04 / L03: a salary repayment separate from the saving plan. It replaces an earlier repayment of the
            // same envelope (whose payments are already in the balance), never a fund plan; undo restores it.
            guard let envelopeID = uuid(p, "id"),
                  try context.fetch(FetchDescriptor<Envelope>()).contains(where: { $0.id == envelopeID && live($0) && !["reserve", "surplus"].contains($0.role) }),
                  let debt = MoneyCommandPayload.integer(p["debtMinor"]), let salaries = MoneyCommandPayload.integer(p["salaries"]) else { throw MoneyCommandError.invalidReference }
            let balance = try sum(context.fetch(FetchDescriptor<Allocation>()).filter { live($0) && $0.targetID == envelopeID }.map(\.amountMinor))
            guard balance < 0, -balance == debt, (1...MoneyCommandPayload.maxRepaySalaries).contains(salaries),
                  let first = RepaymentEngine.nextPayment(.init(totalMinor: debt, paychecks: salaries)) else { throw MoneyCommandError.invalidAmount }
            for old in try context.fetch(FetchDescriptor<EnvelopePlan>()) where old.envelopeID == envelopeID && old.kind == "repay" && live(old) {
                try touch(old, now, writer, deleting: true)
            }
            let plan = EnvelopePlan(); plan.id = id; plan.envelopeID = envelopeID; plan.kind = "repay"; plan.source = "salary"
            plan.perPaycheckMinor = first; plan.repaymentTotalMinor = debt; plan.repaymentPaychecks = salaries
            plan.createdAt = now; plan.updatedAt = now; plan.writerID = writer
            context.insert(plan)
        case "money.setReserveGoal":
            let reserves = try context.fetch(FetchDescriptor<Envelope>()).filter { live($0) && $0.role == "reserve" }
            guard reserves.count <= 1 else { throw MoneyCommandError.invalidReference }
            let amount = MoneyCommandPayload.integer(p["targetMinor"])
            if let row = reserves.first {
                if row.targetMinor != amount { row.targetMinor = amount; try touch(row, now, writer) }
            } else if let amount {
                let row = Envelope(); row.name = "الاحتياطي"; row.role = "reserve"; row.targetMinor = amount; row.createdAt = now; context.insert(row); try touch(row, now, writer)
            }
        case "money.saveAccount": try saveAccount(p, context, now, writer)
        case "money.saveCard": try saveCard(p, context, now, writer)
        case "money.setCardCashback":
            // M5-V16: the cashback rate entered by hand; its source becomes «entered» (Card.fieldSourcesJSON).
            guard let cardID = uuid(p, "id"), let card = try context.fetch(FetchDescriptor<Card>()).first(where: { $0.id == cardID && live($0) }) else { throw MoneyCommandError.invalidReference }
            let rate = MoneyCommandPayload.integer(p["cashbackBp"])
            var sources = (try? JSONSerialization.jsonObject(with: card.fieldSourcesJSON)) as? [String: Any] ?? [:]
            if let rate { sources["cashbackBp"] = "entered" } else { sources.removeValue(forKey: "cashbackBp") }
            card.cashbackBp = rate; card.fieldSourcesJSON = try JSONSerialization.data(withJSONObject: sources, options: [.sortedKeys])
            try touch(card, now, writer)
        case MoneyCommandPayload.intakeName:
            try ingest([p], batch: nil, command: id, issuedAt: issuedAt, context: context, now: now, writer: writer)
        case "money.pasteBankMessages":
            guard case .array(let items) = p["messages"] else { throw MoneyCommandError.invalidReference }
            let inputs = items.compactMap { if case .object(let item) = $0, !discard(text(item, "text")) { item } else { nil } }
            // Hash only messages retained by policy. Never persist an OTP, its hash or a batch containing it.
            let hash = try MadarCore.JSONValue.array(inputs.map(MadarCore.JSONValue.object)).sha256()
            if try context.fetch(FetchDescriptor<ImportBatch>()).contains(where: { $0.kind == "bankBulk" && $0.fileHash == hash }) {
                return .init(inverse: nil, duplicate: true)
            }
            let batch = ImportBatch(); batch.id = uuid(p, "batchID") ?? id; batch.kind = "bankBulk"; batch.fileName = "رسائل ملصقة"
            guard !(try context.fetch(FetchDescriptor<ImportBatch>())).contains(where: { $0.id == batch.id }) else { throw MoneyCommandError.invalidReference }
            batch.fileHash = hash; batch.startedAt = now; batch.finishedAt = now; batch.status = "done"; context.insert(batch); try touch(batch, now, writer)
            try ingest(inputs, batch: batch.id, command: id, issuedAt: issuedAt, context: context, now: now, writer: writer)
        case "money.logExpense":
            let row = MoneyTransaction(); row.id = id; row.kind = "expense"; row.source = "manual"
            row.amountMinor = MoneyCommandPayload.integer(p["amountMinor"]) ?? 0; row.currency = text(p, "currency")
            row.homeCurrency = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
            row.merchant = optionalText(p, "merchant"); row.method = optionalText(p, "method") ?? "cash"
            row.fromAccountID = uuid(p, "fromAccountID"); row.cardID = uuid(p, "cardID"); row.categoryID = uuid(p, "categoryID")
            row.rateAtTime = optionalText(p, "rateAtTime"); row.rateSource = row.rateAtTime == nil ? nil : "manual"
            row.showInDiary = p["showInDiary"] != .bool(false)
            try stampDay(row, at: MoneyCommandPayload.date(p["eventAt"]) ?? issuedAt, context: context, now: now)
            row.reviewState = "needsLook"; row.createdAt = now; context.insert(row)
            if source == .app {
                try resolvePayment(row, context: context)
                // M5-V17: the sheet's split (envelope first, «يومك» last) must add up to the charge, as in a confirmation.
                try confirm(row, payload: p["allocations"].map { ["allocations": $0] } ?? [:], context: context, now: now, writer: writer)
            } else {
                // A draft from outside the app waits for review; a split is only decided in the app.
                guard p["allocations"] == nil else { throw MoneyCommandError.invalidSplit }
                try touch(row, now, writer)
            }
        case "money.confirmTransaction":
            let row = try transaction(uuid(p, "id"), context)
            guard row.reviewState != "ok" else { throw MoneyCommandError.alreadyConfirmed }
            try confirm(row, payload: p, context: context, now: now, writer: writer)
        case "money.setCategoryLimit":
            guard let categoryID = uuid(p, "categoryID"), try context.fetch(FetchDescriptor<MadarData.Category>()).contains(where: { $0.id == categoryID && live($0) }) else { throw MoneyCommandError.invalidReference }
            // One live limit per category (natural key); extra rows from a merge are tombstoned here.
            let rows = try context.fetch(FetchDescriptor<CategoryLimit>()).filter { $0.categoryID == categoryID && live($0) }.sorted { $0.updatedAt > $1.updatedAt }
            for extra in rows.dropFirst() { try touch(extra, now, writer, deleting: true) }
            let limit = rows.first ?? { let row = CategoryLimit(); row.id = id; row.categoryID = categoryID; row.createdAt = now; context.insert(row); return row }()
            limit.mode = text(p, "mode")
            limit.limitMinor = limit.mode == "fixed" ? MoneyCommandPayload.integer(p["limitMinor"]) ?? 0 : 0
            limit.percentBp = limit.mode == "percent" ? MoneyCommandPayload.integer(p["percentBp"]) : nil
            limit.base = limit.mode == "percent" ? text(p, "base") : "income"
            try touch(limit, now, writer)
        case "money.saveObligation":
            let obligation = Obligation(); obligation.id = id; obligation.kind = text(p, "kind"); obligation.name = text(p, "name").trimmingCharacters(in: .whitespacesAndNewlines)
            obligation.amountMinor = MoneyCommandPayload.integer(p["amountMinor"]) ?? 0
            obligation.currency = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
            guard obligation.amountMinor > 0, !obligation.name.isEmpty else { throw MoneyCommandError.invalidAmount }
            // M5-X00: a free interval and first due day; without one, a loan/instalment plan is monthly from its first day.
            let interval = p["repeatUnit"] == nil ? nil : Recurrence(every: MoneyCommandPayload.integer(p["repeatEvery"]), unit: optionalText(p, "repeatUnit"), firstDayKey: optionalText(p, "firstDue"))
            if p["repeatUnit"] != nil && interval == nil { throw MoneyCommandError.invalidReference }
            if let interval {
                obligation.repeatEvery = interval.every; obligation.repeatUnit = interval.unit.rawValue; obligation.firstDueDayKey = interval.first.description
            }
            if obligation.isRecurring {
                obligation.totalMinor = obligation.amountMinor
                if interval == nil {
                    guard obligation.kind == "bill" else { throw MoneyCommandError.invalidReference }
                    obligation.dueDay = MoneyCommandPayload.integer(p["dueDay"])
                }
            } else {
                guard let count = MoneyCommandPayload.integer(p["count"]), (1...120).contains(count), let first = optionalText(p, "firstDue").flatMap({ try? GregorianDay($0) }),
                      let schedule = interval ?? Recurrence(every: 1, unit: .month, first: first) else { throw MoneyCommandError.invalidReference }
                let zone = try PrayerRepository(context: context).place(at: now).timeZone
                obligation.totalMinor = obligation.amountMinor * count; obligation.remainingCount = count
                // The ladder and «يوم N من كل شهر» read dueDay only for a monthly plan.
                obligation.dueDay = schedule.unit == .month && schedule.every == 1 ? first.day : nil
                for n in 1...count {
                    guard let due = schedule.occurrence(n - 1)?.date(in: zone) else { throw MoneyCommandError.invalidReference }
                    let item = InstallmentItem(); item.id = StableIdentity.uuid(for: "InstallmentItem:\(id):\(n)"); item.obligationID = id; item.seq = n
                    item.dueDate = due; item.amountMinor = obligation.amountMinor; item.createdAt = now
                    context.insert(item); try touch(item, now, writer)
                }
            }
            obligation.createdAt = now; context.insert(obligation); try touch(obligation, now, writer)
        case "money.confirmSalary":
            try confirmSalary(p, command: id, context: context, now: now, writer: writer)
        case "money.confirmClear":
            // «اعتمد الواضح»: one receipt and one undo for every listed draft; any refusal rejects all (rollback).
            guard case .array(let values) = p["ids"] else { throw MoneyCommandError.invalidReference }
            for value in values {
                guard case .string(let raw) = value else { throw MoneyCommandError.invalidReference }
                let row = try transaction(UUID(uuidString: raw), context)
                guard row.reviewState == "needsLook" else { throw MoneyCommandError.alreadyConfirmed }
                try confirm(row, payload: [:], context: context, now: now, writer: writer)
            }
        case "money.setBudgetExclusion":
            try setBudgetExclusion(p, context: context, now: now, writer: writer)
        case "money.categorize":
            let row = try transaction(uuid(p, "id"), context), category = uuid(p, "categoryID")
            if let category, !(try context.fetch(FetchDescriptor<MadarData.Category>())).contains(where: { $0.id == category && live($0) }) { throw MoneyCommandError.invalidReference }
            row.categoryID = category; try touch(row, now, writer)
            if p["remember"] == .bool(true) {
                guard let merchant = row.merchant ?? row.counterparty, !merchant.isEmpty else { throw MoneyCommandError.invalidReference }
                try saveRule(merchant: merchant, category: category, ignore: false, context: context, now: now, writer: writer)
            }
        case "money.saveMerchantRule":
            let category = uuid(p, "categoryID")
            if let category, !(try context.fetch(FetchDescriptor<MadarData.Category>())).contains(where: { $0.id == category && live($0) }) { throw MoneyCommandError.invalidReference }
            try saveRule(merchant: text(p, "merchant"), category: category, ignore: p["ignore"] == .bool(true), context: context, now: now, writer: writer)
        case "money.forgetMerchantRule":
            guard let id = uuid(p, "id"), let rule = try context.fetch(FetchDescriptor<MerchantRule>()).first(where: { $0.id == id && live($0) }) else { throw MoneyCommandError.missingRow }
            try touch(rule, now, writer, deleting: true)
        case "money.applyStatement":
            try applyStatement(uuid(p, "id"), context: context, now: now, writer: writer)
        case "money.reconcile":
            try reconcile(p, command: id, context: context, now: now, writer: writer)
        case "money.ignoreMessage":
            guard let id = uuid(p, "id"), let message = try context.fetch(FetchDescriptor<BankMessage>()).first(where: { $0.id == id && live($0) }),
                  ["needsLook", "possibleDuplicate"].contains(message.status) else { throw MoneyCommandError.missingRow }
            // A message with a live draft is dismissed by deleting the draft, which also ignores the message.
            guard !(try transactions(context)).contains(where: { $0.messageID == id }) else { throw MoneyCommandError.invalidReference }
            message.status = "ignored"; try touch(message, now, writer)
        case "money.deleteTransaction":
            let row = try transaction(uuid(p, "id"), context)
            guard !(try transactions(context)).contains(where: { $0.relatedTransactionID == row.id }) else { throw MoneyCommandError.invalidReference }
            if row.kind == "repayment", row.reviewState == "ok", let itemID = row.installmentID,
               let item = try context.fetch(FetchDescriptor<InstallmentItem>()).first(where: { $0.id == itemID && live($0) }) {
                let paid = try installmentAmount(row, item: item, context: context)
                guard item.paidMinor >= paid else { throw MoneyCommandError.invalidAmount }
                item.paidMinor -= paid
                let prior = try transactions(context).filter { $0.id != row.id && $0.installmentID == itemID && $0.reviewState == "ok" }.max { $0.eventAt < $1.eventAt }
                item.paidTransactionID = prior?.id; item.paidAt = prior?.eventAt; try touch(item, now, writer)
            }
            try touch(row, now, writer, deleting: true)
            for allocation in try context.fetch(FetchDescriptor<Allocation>()) where allocation.transactionID == row.id && live(allocation) {
                try touch(allocation, now, writer, deleting: true)
            }
            for message in try messages(for: row, context) { message.status = "ignored"; try touch(message, now, writer) }
        default: throw MoneyCommandError.invalidReference
        }
        try rebuildEnvelopes(context, now, writer)
        let after = try records(context), old = Dictionary(uniqueKeysWithValues: before.map { (recordKey($0), $0) })
        let changed = after.filter { old[recordKey($0)] != $0 }
        guard !changed.isEmpty else { return .init(inverse: nil, duplicate: true) }
        try RecordValidator.validate(changed)
        return .init(inverse: name == "money.accruePlans" ? nil : try JSONEncoder().encode(MoneyInverse(before: before.filter { oldRow in changed.contains { recordKey($0) == recordKey(oldRow) } }, after: changed, reserveGoalID: name == "money.setReserveGoal" ? changed.first(where: { $0.model == "Envelope" && $0.fields["role"]?.string == "reserve" })?.id : nil)), duplicate: false)
    }

    private static func saveAccount(_ p: [String: MadarCore.JSONValue], _ context: ModelContext, _ now: Date, _ writer: String) throws {
        guard let id = uuid(p, "id"), let amount = MoneyCommandPayload.integer(p["balanceMinor"]),
              var at = MoneyCommandPayload.date(p["balanceAt"]), at <= now else { throw MoneyCommandError.invalidAmount }
        try currency(text(p, "currency"))
        let existing = try context.fetch(FetchDescriptor<Account>()).first { $0.id == id }
        guard existing == nil || live(existing!) else { throw MoneyCommandError.invalidReference }
        let row = existing ?? Account()
        if let last4 = optionalText(p, "last4"), !last4.isEmpty, !fourDigits(last4) { throw MoneyCommandError.invalidReference }
        // M5-V19: one bank cannot hold two live accounts with the same last 4 (intake needs exactly one match).
        if try MoneyAccountRules.duplicateLast4(optionalText(p, "last4"), bank: text(p, "bank"), excluding: id, in: context) { throw MoneyCommandError.invalidReference }
        // The initial checkpoint is immutable once movements refer to it; reconciliation owns later corrections.
        // M5-V19: the kind too (a cash wallet's purchases are read differently). The stored instant is kept: an ISO
        // string cannot carry its sub-second part back.
        let fixedCheckpoint = try existing != nil && MoneyAccountRules.hasMovements(id, in: context)
        let originalAt = row.balanceAt
        if fixedCheckpoint {
            guard row.currency == text(p, "currency"), row.balanceMinor == amount,
                  row.kind == text(p, "kind"), row.ownership == text(p, "ownership"), row.tracked == (p["tracked"] != .bool(false)) else { throw MoneyCommandError.invalidReference }
            if let stored = row.balanceAt {
                guard abs(stored.timeIntervalSince(at)) < 1 else { throw MoneyCommandError.invalidReference }
                at = stored
            }
        }
        row.id = id; row.name = text(p, "name"); row.bank = text(p, "bank"); row.kind = text(p, "kind"); row.ownership = text(p, "ownership")
        row.currency = text(p, "currency"); row.balanceMinor = amount; row.balanceAt = fixedCheckpoint ? originalAt : at; row.last4 = optionalText(p, "last4")
        row.senderIDs = strings(p["senderIDs"]); row.tracked = p["tracked"] != .bool(false); row.zakatInclude = p["zakatInclude"] != .bool(false)
        if existing == nil { row.createdAt = now; context.insert(row) }; try touch(row, now, writer)
    }
    private static func saveCard(_ p: [String: MadarCore.JSONValue], _ context: ModelContext, _ now: Date, _ writer: String) throws {
        guard let id = uuid(p, "id"), fourDigits(text(p, "last4")) else { throw MoneyCommandError.invalidReference }
        let kind = text(p, "kind"), accountID = uuid(p, "accountID")
        if kind != "credit" && accountID == nil { throw MoneyCommandError.ambiguousAccount }
        if let accountID { _ = try account(accountID, context) }
        let cards = try context.fetch(FetchDescriptor<Card>())
        guard !cards.contains(where: { $0.id != id && live($0) && $0.last4 == text(p, "last4") && BankDedupe.normalize($0.bank) == BankDedupe.normalize(text(p, "bank")) }) else { throw MoneyCommandError.invalidReference }
        let existing = cards.first { $0.id == id }; guard existing == nil || live(existing!) else { throw MoneyCommandError.invalidReference }
        let row = existing ?? Card()
        if existing != nil, try transactions(context).contains(where: { $0.cardID == id && $0.reviewState == "ok" }) {
            guard row.kind == kind && row.accountID == accountID else { throw MoneyCommandError.invalidReference }
        }
        row.id = id; row.name = text(p, "name"); row.bank = text(p, "bank"); row.last4 = text(p, "last4"); row.kind = kind
        row.accountID = accountID; row.aliases = strings(p["aliases"])
        if existing == nil { row.createdAt = now; context.insert(row) }; try touch(row, now, writer)
    }

    /// M5-V15 / F03 «المحضر»: one Reconciliation per line. expected is the book at the line's time (the same
    /// `accountBalance` / `cardDebts` the basis reads), re-checked against what the screen showed; a stale line rejects
    /// the whole command. A named difference writes one adjustment movement — budget-neutral, or «مصروف لم يُسجَّل»
    /// charged to today's «يومك» — and no name leaves it open. Undo tombstones the movement and the record together.
    private static func reconcile(_ p: [String: MadarCore.JSONValue], command: UUID, context: ModelContext, now: Date, writer: String) throws {
        guard case .array(let rows) = p["rows"] else { throw MoneyCommandError.invalidReference }
        let repo = MoneyRepository(context: context)
        let home = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
        let basis = try repo.basis(at: now), available = try repo.cycle(at: now)?.headline.availableNowMinor
        let other = try context.fetch(FetchDescriptor<MadarData.Category>()).first { live($0) && $0.name == "أخرى" }
        let cycleID = try context.fetch(FetchDescriptor<Cycle>()).filter { live($0) && $0.start <= now && ($0.end == nil || now < $0.end!) }.max { $0.start < $1.start }?.id
        for (index, value) in rows.enumerated() {
            guard case .object(let r) = value, let observed = MoneyCommandPayload.integer(r["observedMinor"]), observed >= 0,
                  let shown = MoneyCommandPayload.integer(r["expectedMinor"]) else { throw MoneyCommandError.invalidAmount }
            let at = MoneyCommandPayload.date(r["at"]) ?? now
            guard at <= now else { throw MoneyCommandError.invalidReference }
            let name: ReconcileName?
            if let raw = optionalText(r, "name") { guard let parsed = ReconcileName(rawValue: raw) else { throw MoneyCommandError.invalidReference }; name = parsed } else { name = nil }
            let line: ReconcileLine, accountID = uuid(r, "accountID"), cardID = uuid(r, "cardID")
            if let accountID {
                let owned = try account(accountID, context)
                guard owned.ownership == "mine", owned.tracked, owned.currency == home else { throw MoneyCommandError.invalidReference }
                line = .init(side: .account, expectedMinor: try repo.accountBalance(owned, at: at), observedMinor: observed)
            } else if let cardID, let debt = try repo.cardDebts(at: at).first(where: { $0.cardID == cardID }) {
                line = .init(side: .creditCard, expectedMinor: debt.totalMinor, observedMinor: observed)
            } else { throw MoneyCommandError.invalidReference }
            // The screen showed another book (a movement arrived meanwhile): nothing is written.
            guard line.expectedMinor == shown else { throw MoneyCommandError.invalidAmount }
            guard let resolution = ReconcileEngine.resolution(name, for: line) else { throw MoneyCommandError.invalidReference }
            let record = Reconciliation(); record.id = StableIdentity.uuid(for: "Reconciliation:\(command):\(index)")
            record.accountID = accountID; record.cardID = cardID; record.at = at
            record.expectedMinor = line.expectedMinor; record.observedMinor = observed; record.deltaMinor = line.deltaMinor
            record.resolution = resolution; record.note = name == .bankFee ? "رسوم بنكية" : nil
            var snapshot: [String: Any] = ["v": 1, "balanceMinor": line.expectedMinor, "inAccountMinor": basis.inAccountMinor, "netMinor": basis.netMinor]
            if let available { snapshot["availableNowMinor"] = available }
            record.beforeJSON = try JSONSerialization.data(withJSONObject: snapshot, options: [.sortedKeys])
            record.createdAt = now; context.insert(record)
            if let effect = ReconcileEngine.effect(line, resolution: resolution) {
                let row = MoneyTransaction(); row.id = StableIdentity.uuid(for: "MoneyTransaction:reconcile:\(record.id)")
                row.kind = "adjustment"; row.source = "manual"; row.method = cardID == nil ? "transfer" : "card"
                row.amountMinor = abs(line.deltaMinor); row.homeAmountMinor = row.amountMinor; row.currency = home; row.homeCurrency = home
                if let accountID { if line.deltaMinor < 0 { row.fromAccountID = accountID } else { row.toAccountID = accountID } }
                row.cardID = cardID
                row.merchant = name == .missedSpend ? "مصاريف فاتتني" : name == .bankFee ? "رسوم بنكية" : "تسوية مطابقة"
                row.categoryID = resolution == "unrecordedSpend" ? other?.id : nil
                try stampDay(row, at: now, context: context, now: now)
                row.cycleID = cycleID; row.reviewState = "ok"; row.showInDiary = false; row.createdAt = now
                context.insert(row); try touch(row, now, writer)
                record.adjustmentTransactionID = row.id
                if effect.budgetChargeMinor > 0 {
                    try writeAllocations(try AllocationEngine.spend(transactionID: row.id.uuidString, homeAmountMinor: effect.budgetChargeMinor, cycleID: cycleID?.uuidString),
                                         context: context, now: now, writer: writer)
                }
            }
            try touch(record, now, writer)
        }
    }

    private static func ingest(_ raw: [[String: MadarCore.JSONValue]], batch: UUID?, command: UUID, issuedAt: Date,
                               context: ModelContext, now: Date, writer: String) throws {
        let all = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.mergedInto == nil }
        let prayer = try PrayerRepository(context: context)
        let homeCurrency = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
        let items = raw.filter { !discard(text($0, "text")) }.map { p in
            let at = MoneyCommandPayload.date(p["receivedAt"]) ?? issuedAt
            let parsed = BankMessageParser.parse(text(p, "text"), timeZone: prayer.place(at: at).timeZone, homeCurrency: homeCurrency)
            return (p, at, parsed, BankDedupe.fingerprint(sender: text(p, "sender"), text: text(p, "text")))
        }
        let existing = all.map { message -> BankDedupe.Stored in
            let parsedAt = message.parsedJSON.flatMap { try? JSONDecoder().decode(MoneyParsedFields.self, from: $0).eventAt }
            return .init(key: .init(fingerprint: message.fingerprint, occurrence: message.occurrence), at: parsedAt ?? message.receivedAt)
        }
        let placements = batch == nil ? items.map { BankDedupe.live($0.3, at: $0.2.eventAt ?? $0.1, existing: existing) }
            : BankDedupe.bulk(items.map { .init(fingerprint: $0.3, hasOwnTime: $0.2.eventAt != nil, at: $0.2.eventAt ?? $0.1) }, existing: existing)
        for (index, pair) in zip(items, placements).enumerated() {
            let (input, placement) = pair, (p, received, parsed, fingerprint) = input
            let occurrence: Int, possibleDuplicate: Bool
            switch placement {
            case .alreadyThere: continue
            case .insert(let n, let possible): occurrence = n; possibleDuplicate = possible
            case .mayExist(let n): occurrence = n; possibleDuplicate = true
            }
            let message = BankMessage(); message.id = StableIdentity.uuid(for: "BankMessage:\(command):\(index)")
            message.sender = text(p, "sender"); message.text = text(p, "text"); message.normalizedText = BankDedupe.normalize(message.text)
            message.receivedAt = received; message.receivedAtSource = parsed.eventAt != nil ? "parsedFromText" : batch != nil ? "batch" : "device"
            message.channel = batch == nil ? "shortcut" : "bulk"; message.importBatchID = batch; message.kind = parsed.kind.rawValue
            message.fingerprint = fingerprint; message.occurrence = occurrence; message.parseVersion = BankMessageParser.version
            message.parsedJSON = try JSONEncoder().encode(MoneyParsedFields(parsed)); message.createdAt = now
            message.status = parsed.kind == .declined ? "ignored" : possibleDuplicate ? "possibleDuplicate" : "needsLook"
            context.insert(message); try touch(message, now, writer)
            guard parsed.kind != .declined && parsed.kind != .unknown && parsed.kind != .statement,
                  let amount = parsed.amountMinor, amount > 0, amount <= 9_007_199_254_740_991, let code = parsed.currency else { continue }
            let row = MoneyTransaction(); row.id = StableIdentity.uuid(for: "BankMovement:\(message.id)")
            row.messageID = message.id; row.amountMinor = amount; row.currency = code; row.source = "bank"
            row.homeCurrency = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
            row.homeAmountMinor = code == row.homeCurrency ? amount : 0
            row.kind = transactionKind(parsed.kind); row.merchant = parsed.merchant; row.counterparty = parsed.counterparty
            row.reviewState = possibleDuplicate ? "possibleDuplicate" : "needsLook"; row.createdAt = now
            try stampDay(row, at: parsed.eventAt ?? received, context: context, now: now)
            try identify(row, parsed: parsed, sender: message.sender, context: context)
            if row.currency != row.homeCurrency, let stated = parsed.statedHomeMinor, stated > 0 {
                row.homeAmountMinor = stated; row.rateAtTime = try FX.impliedRate(amountMinor: row.amountMinor, currency: row.currency, homeMinor: stated, home: row.homeCurrency); row.rateSource = "message"
            } else if row.currency != row.homeCurrency, let trip = try MoneyRepository(context: context).trip(at: row.eventAt), trip.currency == row.currency, let rate = trip.fxRateToHome {
                row.rateAtTime = rate; row.rateSource = "trip"
                row.homeAmountMinor = try FX.homeAmount(amountMinor: row.amountMinor, currency: row.currency, rate: rate, home: row.homeCurrency)
            }
            // A known merchant brings its category (or its «خارج الميزانية»); the draft still waits for the user.
            if let rule = try rule(for: row.merchant ?? row.counterparty, in: context) {
                if rule.ignore { row.ignoredFromBudget = true } else { row.categoryID = rule.categoryID }
            }
            let accounts = try context.fetch(FetchDescriptor<Account>())
            let referenced = row.fromAccountID ?? row.toAccountID
            if let owner = accounts.first(where: { $0.id == referenced }), owner.ownership == "notMine" {
                message.status = "ignored"; try touch(message, now, writer); continue
            }
            context.insert(row); try touch(row, now, writer)
            try flagNearDuplicate(row, message: message, context: context, now: now, writer: writer)
        }
        try pairTransfers(context: context, now: now, writer: writer)
    }

    /// One rule per merchant: the pattern is the normalized merchant name (DECISIONS, M5-V07).
    private static func saveRule(merchant: String, category: UUID?, ignore: Bool, context: ModelContext, now: Date, writer: String) throws {
        let pattern = BankDedupe.normalize(merchant)
        guard !pattern.isEmpty, category != nil || ignore else { throw MoneyCommandError.invalidReference }
        let rules = try context.fetch(FetchDescriptor<MerchantRule>()).filter { live($0) && $0.pattern == pattern }
        let rule = rules.first ?? { let r = MerchantRule(); r.pattern = pattern; r.createdAt = now; context.insert(r); return r }()
        rule.categoryID = ignore ? nil : category; rule.ignore = ignore; try touch(rule, now, writer)
        for extra in rules.dropFirst() { try touch(extra, now, writer, deleting: true) }
    }
    static func rule(for merchant: String?, in context: ModelContext) throws -> MerchantRule? {
        guard let merchant, !merchant.isEmpty else { return nil }
        let pattern = BankDedupe.normalize(merchant)
        return try context.fetch(FetchDescriptor<MerchantRule>()).filter { live($0) && $0.pattern == pattern }.max { $0.updatedAt < $1.updatedAt }
    }

    /// F07: a statement message updates its card once. Natural key (card, close day); the close day is
    /// estimated from the message's day. A second message within 5 days with the same amount updates the
    /// same row; a different amount stays in review. An unknown card is never created here.
    private static func applyStatement(_ id: UUID?, context: ModelContext, now: Date, writer: String) throws {
        guard let id, let message = try context.fetch(FetchDescriptor<BankMessage>()).first(where: { $0.id == id && live($0) }),
              message.kind == BankMessageKind.statement.rawValue, ["needsLook", "possibleDuplicate"].contains(message.status),
              let bytes = message.parsedJSON, let parsed = try? JSONDecoder().decode(MoneyParsedFields.self, from: bytes),
              let amount = parsed.statementDueMinor, amount >= 0, let last4 = parsed.last4 else { throw MoneyCommandError.missingRow }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { live($0) && $0.kind == "credit" }
        guard case .known(let raw) = CardStatements.identify(sender: message.sender, last4: last4, cards: cards.map { .init(id: $0.id.uuidString, bank: $0.bank, last4: $0.last4, aliases: $0.aliases) }),
              let cardID = UUID(uuidString: raw) else { throw MoneyCommandError.invalidReference }
        let zone = try PrayerRepository(context: context).place(at: message.receivedAt).timeZone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let close = calendar.startOfDay(for: message.receivedAt)
        let stored = try context.fetch(FetchDescriptor<Statement>()).filter { live($0) && $0.cardID == cardID }.sorted { $0.closeDate < $1.closeDate }
        let row: Statement
        switch CardStatements.place(closeDate: close, statementMinor: amount, existing: stored.map { .init(closeDate: $0.closeDate, statementMinor: $0.statementMinor, estimated: $0.closeDateSource == "estimated") }) {
        case .needsLook: throw MoneyCommandError.invalidAmount
        case .sameStatement(let index): row = stored[index]
        case .new:
            if let same = stored.first(where: { $0.closeDate == close }) { row = same } else {
                row = Statement(); row.id = StableIdentity.uuid(for: "Statement:\(cardID):\(Int(close.timeIntervalSince1970))")
                row.cardID = cardID; row.closeDate = close; row.closeDateSource = "estimated"; row.createdAt = now; context.insert(row)
            }
        }
        row.statementMinor = amount; row.minimumDueMinor = parsed.minimumDueMinor ?? row.minimumDueMinor; row.dueDate = parsed.dueDate ?? row.dueDate
        row.periodStart = stored.last(where: { $0.closeDate < close && $0.id != row.id })?.closeDate ?? row.periodStart
        row.messageID = message.id; try touch(row, now, writer)
        message.status = "ok"; try touch(message, now, writer)
    }

    private static func identify(_ row: MoneyTransaction, parsed: ParsedBankMessage, sender: String, context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { live($0) }
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { live($0) }
        let known = cards.filter { $0.last4 == parsed.last4 && (BankDedupe.normalize($0.bank) == BankDedupe.normalize(sender) || $0.aliases.map(BankDedupe.normalize).contains(BankDedupe.normalize(sender))) }
        if known.count == 1, let card = known.first {
            row.cardID = card.id; row.method = "card"
            if card.kind != "credit" {
                if parsed.kind == .refund || parsed.kind == .reversal { row.toAccountID = card.accountID }
                else { row.fromAccountID = card.accountID }
            }
        } else {
            let matching = accounts.filter { MoneyAccountRules.matches($0, sender: sender, last4: parsed.last4) }
            if matching.count == 1, let account = matching.first {
                if [.salary, .income, .transferIn, .refund, .reversal].contains(parsed.kind) { row.toAccountID = account.id }
                else { row.fromAccountID = account.id }
                row.method = "transfer"
                if account.ownership == "notMine" { row.reviewState = "needsLook" }
            }
        }
        if parsed.kind == .transferOut || parsed.kind == .transferIn { row.method = "transfer" }
        if parsed.kind == .billPayment, let biller = parsed.biller {
            let matches = try context.fetch(FetchDescriptor<Obligation>()).filter { live($0) && $0.kind == "bill" && $0.provider == biller }
            if matches.count == 1 { row.obligationID = matches.first?.id }
        }
        if parsed.kind == .bnplInstalment, let provider = parsed.provider {
            let matches = try context.fetch(FetchDescriptor<Obligation>()).filter { live($0) && $0.kind == "installment" && $0.provider == provider }
            if matches.count == 1 { row.obligationID = matches.first?.id }
        }
    }
    private static func flagNearDuplicate(_ row: MoneyTransaction, message: BankMessage, context: ModelContext, now: Date, writer: String) throws {
        guard let key = row.cardID ?? row.fromAccountID ?? row.toAccountID else { return }
        let rows = try transactions(context), messages = try context.fetch(FetchDescriptor<BankMessage>())
        let existing = rows.filter { $0.id != row.id && ($0.cardID ?? $0.fromAccountID ?? $0.toAccountID) == key }.compactMap { old -> BankDedupe.Movement? in
            // M5-V17: an expense recorded by hand has no message; it still counts, so its bank message waits for a decision.
            let fingerprint = messages.first(where: { $0.id == old.messageID })?.fingerprint ?? (old.messageID == nil && old.source == "manual" && old.kind == "expense" ? "manual:" + old.id.uuidString : nil)
            guard let fingerprint else { return nil }
            return .init(accountKey: key.uuidString, amountMinor: old.amountMinor, merchant: old.merchant, at: old.eventAt, fingerprint: fingerprint)
        }
        if BankDedupe.nearDuplicate(.init(accountKey: key.uuidString, amountMinor: row.amountMinor, merchant: row.merchant, at: row.eventAt, fingerprint: message.fingerprint), among: existing) {
            row.reviewState = "possibleDuplicate"; message.status = "possibleDuplicate"; try touch(row, now, writer); try touch(message, now, writer)
        }
    }
    private static func pairTransfers(context: ModelContext, now: Date, writer: String) throws {
        let rows = try transactions(context).filter { $0.kind == "transfer" && $0.reviewState != "ok" && ($0.fromAccountID == nil || $0.toAccountID == nil) }
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { live($0) }
        // Compare the original currency too; two amounts called 100 in different currencies cannot pair.
        for currency in Set(rows.map(\.currency)) {
            let same = rows.filter { $0.currency == currency }
            let legs = same.compactMap { row -> BankLeg? in
                guard let id = row.fromAccountID ?? row.toAccountID,
                      let account = accounts.first(where: { $0.id == id }), account.ownership == "mine", account.tracked else { return nil }
                return .init(id: row.id.uuidString, accountID: id.uuidString, direction: row.fromAccountID != nil ? .out : .in, amountMinor: row.amountMinor, at: row.eventAt)
            }
            for pair in TransferPairing.pairs(legs) {
                guard let outgoing = same.first(where: { $0.id.uuidString == pair.out }), let incoming = same.first(where: { $0.id.uuidString == pair.in }) else { continue }
                outgoing.toAccountID = incoming.toAccountID; incoming.mergedInto = outgoing.id
                try touch(outgoing, now, writer); try touch(incoming, now, writer)
            }
        }
    }

    /// «الواضح»: the drafts the real confirmation accepts as read. Each runs in its own unsaved
    /// context that is rolled back, so the UI flag and money.confirmClear share one definition.
    /// M5-V08 «نزل الراتب»: one write closes the open cycle (report once, offset or leftover rows), opens the new cycle
    /// with its frozen policy, moves the salary day's movements into it, funds the plans and confirms the salary.
    private static func confirmSalary(_ p: [String: MadarCore.JSONValue], command: UUID, context: ModelContext, now: Date, writer: String) throws {
        guard let salaryID = uuid(p, "id") else { throw MoneyCommandError.missingRow }
        let override: SalaryRemainder? = switch optionalText(p, "remainderTo") { case "surplus": .surplusThenReserve; case "reserve": .reserve; default: nil }
        var reading = try MoneyRepository(context: context).salaryOpening(salaryID: salaryID, newCycleID: command, remainderOverride: override)
        if let oldID = reading.closingCycleID, let old = try MoneyRepository(context: context).cycle(at: reading.salaryAt.addingTimeInterval(-0.001)), old.id == oldID {
            try accrueDailyPlans(old, through: max(0, MadarCalendarDays.distance(from: old.startDay, to: reading.startDay)), context: context, now: now, writer: writer)
            reading = try MoneyRepository(context: context).salaryOpening(salaryID: salaryID, newCycleID: command, remainderOverride: override)
        }
        let plan = reading.plan
        // With «اسألني», the report asks first; the command never leaves money waiting without a home.
        guard plan.awaitingChoiceMinor == 0, plan.close?.awaitingChoiceMinor ?? 0 == 0 else { throw MoneyCommandError.invalidReference }
        let salary = try transaction(salaryID, context)
        if let oldID = reading.closingCycleID, let old = try context.fetch(FetchDescriptor<Cycle>()).first(where: { $0.id == oldID && live($0) }), let close = plan.close {
            guard old.closedAt == nil, old.closedReportJSON == nil else { throw MoneyCommandError.alreadyConfirmed }
            old.end = salary.eventAt; old.closedAt = now; old.reportVersion = 1
            old.closedReportJSON = try JSONEncoder().encode(SalaryCloseReport(start: old.start, end: salary.eventAt, carriedMinor: reading.input.closing?.availableNowMinor ?? 0,
                offsetMinor: close.offsetMinor, carryMinor: close.carryMinor, toSurplusMinor: close.toSurplusMinor, toReserveMinor: close.toReserveMinor, nextIncomeMinor: reading.salaryMinor))
            try touch(old, now, writer)
            // Cycle membership uses the salary day: movements already filed from that day on belong to the new cycle.
            let first = reading.startDay.description
            for row in try transactions(context) where row.cycleID == oldID && row.id != salaryID && row.dayKey >= first {
                row.cycleID = command; try touch(row, now, writer)
                for allocation in try context.fetch(FetchDescriptor<Allocation>()) where allocation.transactionID == row.id && allocation.cycleID == oldID && live(allocation) {
                    allocation.cycleID = command; try touch(allocation, now, writer)
                }
            }
        }
        let zone = try PrayerRepository(context: context).place(at: salary.eventAt).timeZone
        let cycle = Cycle(); cycle.id = command; cycle.start = salary.eventAt; cycle.expectedEnd = reading.endDay.date(in: zone)
        cycle.salaryTransactionID = salaryID; cycle.incomeMinor = reading.salaryMinor; cycle.carryAdjustMinor = plan.carryMinor
        let policy = CyclePolicy(); policy.id = StableIdentity.uuid(for: "CyclePolicy:\(command):\(reading.startDay)")
        policy.cycleID = command; policy.effectiveFromDayKey = reading.startDay.description
        policy.dailyRateMinor = plan.rate.dailyRateMinor; policy.lastDayRemainderMinor = plan.rate.lastDayRemainderMinor
        switch reading.input.allowance {
        case .fixed(let amount): cycle.mode = "fixed"; cycle.dailyAllowanceMinor = amount; policy.mode = "fixed"; policy.allowanceMinor = amount
        case .percent(let bp, _): cycle.mode = "percent"; cycle.percentBp = bp; policy.mode = "percent"; policy.percentBp = bp
        }
        cycle.createdAt = now; policy.createdAt = now
        context.insert(cycle); context.insert(policy); try touch(cycle, now, writer); try touch(policy, now, writer)
        try writeAllocations(plan.rows, context: context, now: now, writer: writer)
        salary.homeAmountMinor = reading.salaryMinor; salary.cycleID = command; salary.reviewState = "ok"; try touch(salary, now, writer)
        for message in try messages(for: salary, context) { message.status = "ok"; try touch(message, now, writer) }
    }
    public static func confirmableAsRead(_ ids: [UUID], container: ModelContainer, now: Date) -> Set<UUID> {
        Set(ids.filter { id in
            let context = ModelContext(container); context.autosaveEnabled = false
            defer { context.rollback() }
            guard let row = try? transaction(id, context), row.reviewState == "needsLook" else { return false }
            return (try? confirm(row, payload: [:], context: context, now: now, writer: "dryRun")) != nil
        })
    }
    private static func confirm(_ row: MoneyTransaction, payload p: [String: MadarCore.JSONValue], context: ModelContext, now: Date, writer: String) throws {
        guard row.kind != "salary" else { throw MoneyCommandError.salaryNeedsCycleConfirmation }
        for (key, setter) in [
            ("fromAccountID", { row.fromAccountID = $0 }), ("toAccountID", { row.toAccountID = $0 }),
            ("cardID", { row.cardID = $0 }), ("relatedTransactionID", { row.relatedTransactionID = $0 }),
            ("obligationID", { row.obligationID = $0 }), ("installmentID", { row.installmentID = $0 })
        ] as [(String, (UUID?) -> Void)] where p[key] != nil { setter(uuid(p, key)) }
        if let rate = optionalText(p, "rateAtTime") { row.rateAtTime = rate; row.rateSource = "manual" }
        if p["ignoredFromBudget"] != nil { row.ignoredFromBudget = p["ignoredFromBudget"] == .bool(true) }
        try currency(row.currency); try currency(row.homeCurrency)
        guard row.amountMinor > 0 else { throw MoneyCommandError.invalidAmount }
        try resolvePayment(row, context: context)
        if let category = row.categoryID, !(try context.fetch(FetchDescriptor<MadarData.Category>())).contains(where: { $0.id == category && live($0) }) { throw MoneyCommandError.invalidReference }
        if let obligation = row.obligationID, !(try context.fetch(FetchDescriptor<Obligation>())).contains(where: { $0.id == obligation && live($0) }) { throw MoneyCommandError.invalidReference }
        let original: MoneyTransaction?
        if row.kind == "refund" {
            original = try transaction(row.relatedTransactionID, context)
            guard let original, original.reviewState == "ok", ["expense", "fee", "transfer"].contains(original.kind),
                  original.currency == row.currency, original.cardID == row.cardID else { throw MoneyCommandError.invalidReference }
            let previous = try transactions(context).filter { $0.kind == "refund" && $0.reviewState == "ok" && $0.relatedTransactionID == original.id }
            let used = try sum(previous.map(\.amountMinor)), usedHome = try sum(previous.map(\.homeAmountMinor))
            guard row.amountMinor <= original.amountMinor - used else { throw MoneyCommandError.invalidAmount }
            let statedHome = row.rateSource == "message" ? row.homeAmountMinor : nil
            row.homeAmountMinor = try FX.refundHomeAmount(refundMinor: row.amountMinor,
                original: (original.amountMinor, original.homeAmountMinor, original.currency, original.rateAtTime),
                priorRefundsMinor: used, priorRefundsHomeMinor: usedHome, statedHomeMinor: statedHome, home: row.homeCurrency)
            if statedHome == nil { row.rateAtTime = original.rateAtTime; row.rateSource = original.rateSource }; row.tripID = original.tripID
            row.cycleID = original.cycleID // F06: a refund belongs to the original budget day.
            row.ignoredFromBudget = original.ignoredFromBudget
            row.categoryID = original.categoryID
        } else {
            original = nil
            if row.currency != row.homeCurrency && row.rateAtTime == nil {
                if let trip = try MoneyRepository(context: context).trip(at: row.eventAt), trip.currency == row.currency, let rate = trip.fxRateToHome {
                    row.rateAtTime = rate; row.rateSource = "trip"
                } else { throw MoneyCommandError.missingRate }
            }
            if row.rateSource != "message" { row.homeAmountMinor = try FX.homeAmount(amountMinor: row.amountMinor, currency: row.currency, rate: row.rateAtTime ?? "1", home: row.homeCurrency) }
            row.cycleID = try context.fetch(FetchDescriptor<Cycle>()).filter { live($0) && $0.start <= row.eventAt && ($0.end == nil || row.eventAt < $0.end!) }.max { $0.start < $1.start }?.id
        }
        guard row.homeAmountMinor > 0 && row.homeAmountMinor <= 9_007_199_254_740_991 else { throw MoneyCommandError.invalidAmount }
        let effect = try MoneyRepository(context: context).effect(of: row)
        var allocations: [AllocationRow] = []
        if effect.budgetChargeMinor > 0 {
            var sources = try splitSources(p["allocations"], context)
            if sources.isEmpty, let tripID = row.tripID,
               let trip = try context.fetch(FetchDescriptor<Trip>()).first(where: { $0.id == tripID && live($0) && !$0.dismissed }) {
                let envelope: Envelope
                if let old = try MoneyRepository(context: context).tripEnvelope(trip) { envelope = old }
                else { envelope = try restoreTripEnvelope(trip, context, now, writer) }
                sources = [(.envelope(envelope.id.uuidString), effect.budgetChargeMinor)]
            }
            if try !sources.isEmpty && sum(sources.map(\.1)) != effect.budgetChargeMinor { throw MoneyCommandError.invalidSplit }
            do { allocations = try AllocationEngine.spend(transactionID: row.id.uuidString, homeAmountMinor: effect.budgetChargeMinor, over: sources, cycleID: row.cycleID?.uuidString) }
            catch { throw MoneyCommandError.invalidSplit }
        } else if effect.budgetChargeMinor < 0, let original {
            let repo = MoneyRepository(context: context)
            let originalRows = try repo.allocationRows(transactionID: original.id).sorted { $0.idempotencyKey < $1.idempotencyKey }
            let priorIDs = Set(try transactions(context).filter { $0.kind == "refund" && $0.reviewState == "ok" && $0.relatedTransactionID == original.id }.map(\.id))
            let priorRows = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) && $0.transactionID.map(priorIDs.contains) == true }
            let priorHome = try sum(priorRows.map(\.amountMinor))
            let cumulative = AllocationEngine.refund(refundTransactionID: row.id.uuidString, homeAmountMinor: priorHome + row.homeAmountMinor, original: originalRows)
            allocations = try cumulative.enumerated().map { index, value in
                var result = value
                let paid = try sum(priorRows.filter { $0.idempotencyKey.hasSuffix(":\(index)") }.map(\.amountMinor))
                result.amountMinor -= paid; return result
            }
        } else if p["allocations"] != nil { throw MoneyCommandError.invalidSplit }
        try writeAllocations(allocations, context: context, now: now, writer: writer)
        if row.kind == "repayment" {
            guard let itemID = row.installmentID, let item = try context.fetch(FetchDescriptor<InstallmentItem>()).first(where: { $0.id == itemID && live($0) }),
                  item.obligationID == row.obligationID else { throw MoneyCommandError.invalidReference }
            let paid = try installmentAmount(row, item: item, context: context)
            guard paid <= item.amountMinor - item.paidMinor else { throw MoneyCommandError.invalidAmount }
            item.paidMinor += paid; item.paidTransactionID = row.id; item.paidAt = row.eventAt; try touch(item, now, writer)
        }
        row.reviewState = "ok"; try touch(row, now, writer)
        for message in try messages(for: row, context) { message.status = "ok"; try touch(message, now, writer) }
    }

    /// F06: remove only budget allocations; keep the movement and its cash/debt effect.
    /// Tombstones retain the original split so lifting the stamp restores every minor unit.
    private static func setBudgetExclusion(_ p: [String: MadarCore.JSONValue], context: ModelContext, now: Date, writer: String) throws {
        let row = try transaction(uuid(p, "id"), context)
        guard row.reviewState == "ok", row.obligationID == nil,
              row.eventAt <= now,
              ["expense", "fee", "withdrawal", "transfer"].contains(row.kind),
              p["expectedExcluded"] == .bool(row.ignoredFromBudget) else { throw MoneyCommandError.invalidReference }
        let excluded = p["excluded"] == .bool(true)
        if let cycleID = row.cycleID {
            guard try context.fetch(FetchDescriptor<Cycle>()).contains(where: { $0.id == cycleID && live($0) && $0.closedAt == nil && $0.start <= now && ($0.end == nil || now < $0.end!) }) else { throw MoneyCommandError.invalidReference }
        }
        if excluded == row.ignoredFromBudget { return }
        let charge = try MoneyRepository(context: context).effect(of: row, includingExcluded: true).budgetChargeMinor
        guard charge > 0 else { throw MoneyCommandError.invalidReference }
        let refunds = try transactions(context).filter { $0.kind == "refund" && $0.relatedTransactionID == row.id && $0.reviewState == "ok" }
            .sorted { $0.eventAt == $1.eventAt ? $0.id.uuidString < $1.id.uuidString : $0.eventAt < $1.eventAt }
        let ids = Set(([row] + refunds).map(\.id))
        let stored = try context.fetch(FetchDescriptor<Allocation>()).filter { $0.transactionID.map(ids.contains) == true && $0.mergedInto == nil }
        guard stored.allSatisfy({ ["spend", "refund"].contains($0.kind) }) else { throw MoneyCommandError.invalidReference }
        // M5-X00: the stamp's optional reason lives on the movement only, and leaves with the stamp.
        let reason = optionalText(p, "reason")?.trimmingCharacters(in: .whitespacesAndNewlines)
        row.ignoredFromBudget = excluded; row.budgetIgnoreReason = excluded && reason?.isEmpty == false ? reason.map { String($0.prefix(MoneyCommandPayload.maxReasonLength)) } : nil
        try touch(row, now, writer)
        for refund in refunds { refund.ignoredFromBudget = excluded; try touch(refund, now, writer) }
        if excluded {
            for allocation in stored where live(allocation) { try touch(allocation, now, writer, deleting: true) }
            return
        }
        // A purchase excluded at intake has no prior split: F02's default is the daily budget.
        let originals = stored.filter { $0.transactionID == row.id && $0.kind == "spend" }
        if originals.isEmpty {
            try writeAllocations(AllocationEngine.spend(transactionID: row.id.uuidString, homeAmountMinor: charge, over: [], cycleID: row.cycleID?.uuidString), context: context, now: now, writer: writer)
        } else {
            guard try sum(originals.map(\.amountMinor)) == -charge else { throw MoneyCommandError.invalidSplit }
            let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { live($0) }
            for allocation in originals {
                if let target = allocation.targetID, !envelopes.contains(where: { $0.id == target }) { throw MoneyCommandError.invalidReference }
                try restoreBudgetAllocation(allocation, now: now, writer: writer)
            }
        }
        let source = try MoneyRepository(context: context).allocationRows(transactionID: row.id).sorted { $0.idempotencyKey < $1.idempotencyKey }
        var cumulativeHome = 0
        var paid: [Int: Int] = [:]
        for refund in refunds {
            cumulativeHome = try sum([cumulativeHome, refund.homeAmountMinor])
            guard cumulativeHome <= charge else { throw MoneyCommandError.invalidAmount }
            let values = AllocationEngine.refund(refundTransactionID: refund.id.uuidString, homeAmountMinor: cumulativeHome, original: source)
            for (index, value) in values.enumerated() {
                let amount = value.amountMinor - (paid[index] ?? 0)
                paid[index] = value.amountMinor
                if let old = stored.first(where: { $0.idempotencyKey == value.idempotencyKey }) {
                    old.amountMinor = amount; try restoreBudgetAllocation(old, now: now, writer: writer)
                } else {
                    var next = value; next.amountMinor = amount
                    try writeAllocations([next], context: context, now: now, writer: writer)
                }
            }
        }
    }
    private static func restoreBudgetAllocation(_ row: Allocation, now: Date, writer: String) throws {
        var record = try row.record()
        let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
        try record.set(Optional<Date>.none, for: "deletedAt")
        try record.set(stamp, for: "restoredAt"); try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID")
        try row.apply(record)
    }
    private static func resolvePayment(_ row: MoneyTransaction, context: ModelContext) throws {
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { live($0) }
        if let messageID = row.messageID, let message = try context.fetch(FetchDescriptor<BankMessage>()).first(where: { $0.id == messageID }),
           let bytes = message.parsedJSON, let parsed = try? JSONDecoder().decode(MoneyParsedFields.self, from: bytes),
           parsed.cardKind != nil && row.cardID == nil { throw MoneyCommandError.cardKindRequired }
        if let id = row.cardID {
            guard let card = try context.fetch(FetchDescriptor<Card>()).first(where: { $0.id == id && live($0) }) else { throw MoneyCommandError.invalidReference }
            if let messageID = row.messageID, let message = try context.fetch(FetchDescriptor<BankMessage>()).first(where: { $0.id == messageID }),
               let bytes = message.parsedJSON, let parsed = try? JSONDecoder().decode(MoneyParsedFields.self, from: bytes),
               let kind = parsed.cardKind, kind != card.kind { throw MoneyCommandError.cardKindRequired }
            if ["expense", "fee"].contains(row.kind) && card.kind != "credit" { row.fromAccountID = card.accountID }
            if row.kind == "refund" && card.kind != "credit" { row.toAccountID = card.accountID }
            if row.kind == "cardPayment", card.kind != "credit" { throw MoneyCommandError.invalidReference }
            if let accountID = card.accountID {
                let owner = try account(accountID, context)
                guard owner.ownership == "mine" && owner.tracked else { throw MoneyCommandError.invalidReference }
            }
            if card.kind != "credit" && card.accountID == nil { throw MoneyCommandError.ambiguousAccount }
            row.method = "card"
        } else if row.method == "card" { throw MoneyCommandError.cardKindRequired }
        let isIncoming = ["income", "salary", "refund", "cashback"].contains(row.kind)
        if row.cardID == nil && row.fromAccountID == nil && row.toAccountID == nil {
            guard row.source != "bank" else { throw MoneyCommandError.ambiguousAccount }
            let candidates = accounts.filter { $0.ownership == "mine" && $0.tracked && $0.currency == row.currency
                && (row.method == "cash" ? $0.kind == "cash" : ["current", "savings", "wallet"].contains($0.kind)) }
            guard candidates.count == 1, let candidate = candidates.first else { throw MoneyCommandError.ambiguousAccount }
            if isIncoming { row.toAccountID = candidate.id } else { row.fromAccountID = candidate.id }
        }
        for id in [row.fromAccountID, row.toAccountID].compactMap({ $0 }) {
            let owner = try account(id, context)
            guard owner.currency == row.currency || owner.currency == row.homeCurrency else { throw MoneyCommandError.invalidCurrency }
        }
        if ["expense", "fee", "withdrawal", "cardPayment", "billPayment", "repayment"].contains(row.kind), row.fromAccountID == nil && row.cardID == nil { throw MoneyCommandError.ambiguousAccount }
        if let id = isIncoming ? row.toAccountID : row.fromAccountID {
            let owner = try account(id, context)
            guard owner.ownership == "mine", owner.tracked else { throw MoneyCommandError.invalidReference }
        }
        if row.kind == "withdrawal", row.toAccountID == nil {
            let cash = accounts.filter { $0.kind == "cash" && $0.ownership == "mine" && $0.tracked && $0.currency == row.currency }
            guard cash.count == 1 else { throw MoneyCommandError.ambiguousAccount }; row.toAccountID = cash.first?.id
        }
        if row.fromAccountID != nil && row.fromAccountID == row.toAccountID { throw MoneyCommandError.invalidReference }
    }

    private static func installmentAmount(_ row: MoneyTransaction, item: InstallmentItem, context: ModelContext) throws -> Int {
        guard let obligation = try context.fetch(FetchDescriptor<Obligation>()).first(where: { $0.id == item.obligationID && live($0) }) else { throw MoneyCommandError.invalidReference }
        if obligation.currency == row.currency { return row.amountMinor }
        if obligation.currency == row.homeCurrency { return row.homeAmountMinor }
        throw MoneyCommandError.missingRate
    }
    private static func splitSources(_ value: MadarCore.JSONValue?, _ context: ModelContext) throws -> [(AllocationTarget, Int)] {
        guard let value else { return [] }
        guard case .array(let parts) = value else { throw MoneyCommandError.invalidSplit }
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { live($0) }
        return try parts.map { part in
            guard case .object(let p) = part, let amount = MoneyCommandPayload.integer(p["amountMinor"]) else { throw MoneyCommandError.invalidSplit }
            let target: AllocationTarget
            switch text(p, "target") {
            case "daily": target = .daily
            case "reserve": target = .reserve
            case "surplus": target = .surplus
            case "envelope", "goal":
                guard let id = uuid(p, "targetID"), envelopes.contains(where: { $0.id == id }) else { throw MoneyCommandError.invalidReference }
                target = text(p, "target") == "goal" ? .goal(id.uuidString) : .envelope(id.uuidString)
            default: throw MoneyCommandError.invalidSplit
            }
            return (target, amount)
        }
    }
    private static func allocationTarget(_ row: Allocation) -> AllocationTarget? {
        switch row.target {
        case "daily": .daily
        case "reserve": .reserve
        case "surplus": .surplus
        case "envelope": row.targetID.map { .envelope($0.uuidString) }
        case "goal": row.targetID.map { .goal($0.uuidString) }
        default: nil
        }
    }
    static func writeAllocations(_ rows: [AllocationRow], context: ModelContext, now: Date, writer: String) throws {
        let stored = try context.fetch(FetchDescriptor<Allocation>())
        for value in rows {
            guard !stored.contains(where: { $0.idempotencyKey == value.idempotencyKey }) else { throw MoneyCommandError.invalidReference }
            let row = Allocation(); row.id = StableIdentity.uuid(for: "Allocation:\(value.idempotencyKey)")
            row.transactionID = value.transactionID.flatMap(UUID.init(uuidString:)); row.groupID = value.groupID.map { StableIdentity.uuid(for: $0) }
            row.cycleID = value.cycleID.flatMap(UUID.init(uuidString:)); row.amountMinor = value.amountMinor
            row.kind = value.kind.rawValue; row.idempotencyKey = value.idempotencyKey
            switch value.target {
            case .daily: row.target = "daily"
            case .reserve: row.target = "reserve"
            case .surplus: row.target = "surplus"
            case .envelope(let id): row.target = "envelope"; row.targetID = UUID(uuidString: id)
            case .goal(let id): row.target = "goal"; row.targetID = UUID(uuidString: id)
            }
            row.createdAt = now; context.insert(row); try touch(row, now, writer)
        }
    }

    static func undo(_ data: Data, context: ModelContext, now: Date, writer: String) throws {
        let inverse = try JSONDecoder().decode(MoneyInverse.self, from: data)
        guard inverse.v == 1 else { throw MoneyCommandError.undoSuperseded }
        if let id = inverse.reserveGoalID {
            guard let after = inverse.after.first(where: { $0.model == "Envelope" && $0.id == id }),
                  let row = try context.fetch(FetchDescriptor<Envelope>()).first(where: { $0.id == id && live($0) }),
                  try row.record().fields["targetMinor"] == after.fields["targetMinor"] else { throw MoneyCommandError.undoSuperseded }
            let before = inverse.before.first { $0.model == "Envelope" && $0.id == id }
            row.targetMinor = try before?.fields["targetMinor"].flatMap { $0 == .null ? nil : try $0.decode(Int.self) }
            try touch(row, now, writer)
            return // Only the target changes; later allocations and their rebuilt balance stay intact.
        }
        let current = try records(context), changedIDs = Set(inverse.after.map(\.id))
        // An adopted repayment that a salary already paid into stays: undoing it would orphan those payments.
        for plan in inverse.after where plan.model == "EnvelopePlan" && plan.fields["kind"]?.string == "repay" && !inverse.before.contains(where: { recordKey($0) == recordKey(plan) }) {
            let suffix = ":" + plan.id.uuidString
            guard !current.contains(where: { $0.model == "Allocation" && $0.isLive && ($0.fields["idempotencyKey"]?.string).map { $0.hasPrefix("fund:") && $0.hasSuffix(suffix) } == true }) else { throw MoneyCommandError.undoSuperseded }
        }
        for after in inverse.after {
            guard current.first(where: { recordKey($0) == recordKey(after) }) == after else { throw MoneyCommandError.undoSuperseded }
            // A later refund must not be left excluded while this undo restores its purchase.
            if after.model == "MoneyTransaction", let before = inverse.before.first(where: { recordKey($0) == recordKey(after) }),
               before.fields["ignoredFromBudget"] != after.fields["ignoredFromBudget"],
               current.contains(where: { $0.model == "MoneyTransaction" && $0.isLive && !changedIDs.contains($0.id) && $0.fields["relatedTransactionID"]?.string == after.id.uuidString }) {
                throw MoneyCommandError.undoSuperseded
            }
            // Never remove the account/card/original while a later live movement depends on it.
            if !inverse.before.contains(where: { recordKey($0) == recordKey(after) }), ["Account", "Card", "MoneyTransaction", "Cycle", "Obligation"].contains(after.model) {
                let dependencies = current.filter { $0.isLive && !changedIDs.contains($0.id) }
                // A cycle opened by a salary stays once later movements or allocations were filed into it.
                let referenceKeys = ["accountID", "fromAccountID", "toAccountID", "cardID", "relatedTransactionID", "cycleID", "obligationID"]
                guard !dependencies.contains(where: { record in referenceKeys.contains { record.fields[$0]?.string == after.id.uuidString } }) else { throw MoneyCommandError.undoSuperseded }
            }
        }
        for after in inverse.after {
            var restored = inverse.before.first { recordKey($0) == recordKey(after) } ?? after
            let stamp = StableIdentity.monotonic(now: now, previous: after.date("updatedAt") ?? now)
            try restored.set(stamp, for: "updatedAt"); try restored.set(writer, for: "writerID")
            if !inverse.before.contains(where: { recordKey($0) == recordKey(after) }) {
                try restored.set(stamp, for: "deletedAt"); try restored.set(stamp, for: "deletionBarrierAt")
            } else if restored.isLive && after.deletedAt != nil {
                try restored.set(after.date("deletionBarrierAt"), for: "deletionBarrierAt"); try restored.set(stamp, for: "restoredAt")
            }
            try RecordBridge.upsert(restored, in: context)
        }
        try rebuildEnvelopes(context, now, writer)
    }

    /// Settings and their next-day policy share one receipt and one undo; the current policy, carry and plans stay.
    static func stageDailyAllowanceChange(_ value: MadarData.JSONValue, context: ModelContext, now: Date, writer: String) throws -> Data? {
        let schema = try SettingsSchema.bundled()
        if value != (try schema.definition(for: "mal.dailyAllowance").defaultValue) { try schema.validate(value, for: "mal.dailyAllowance") }
        guard let object = value.object, let cycle = try MoneyRepository(context: context).cycle(at: now),
              let storedCycle = try context.fetch(FetchDescriptor<Cycle>()).first(where: { $0.id == cycle.id }) else { return nil }
        let amount = object["amountMinor"]?.number.map(Int.init), bp = object["percentBp"]?.number.map(Int.init)
        let percent = object["mode"]?.string == "percent"
        let day = cycle.today.adding(days: 1).description
        let existing = try context.fetch(FetchDescriptor<CyclePolicy>()).first { $0.cycleID == cycle.id && $0.effectiveFromDayKey == day }
        let before = try existing.map { try $0.record() }
        if percent ? bp == nil : amount == nil {
            guard let existing, existing.deletedAt == nil else { return nil }
            try touch(existing, now, writer, deleting: true) // reset cancels tomorrow's draft policy, never an elapsed day.
            return try JSONEncoder().encode(MoneyInverse(before: before.map { [$0] } ?? [], after: [try existing.record()]))
        }

        let policy = existing ?? CyclePolicy(); policy.id = existing?.id ?? StableIdentity.uuid(for: "CyclePolicy:\(cycle.id):\(day)")
        policy.cycleID = cycle.id; policy.effectiveFromDayKey = day; policy.mode = percent ? "percent" : "fixed"; policy.allowanceMinor = amount ?? 0; policy.percentBp = percent ? bp : nil
        let mode: AllowanceMode = percent ? .percent(basisPoints: bp ?? 0, incomeMinor: storedCycle.incomeMinor) : .fixed(allowanceMinor: amount ?? 0)
        let rate = CycleEngine.freeze(mode, expectedLengthDays: cycle.input.expectedLengthDays)
        policy.dailyRateMinor = rate.dailyRateMinor; policy.lastDayRemainderMinor = rate.lastDayRemainderMinor
        if policy.deletedAt != nil { policy.restoredAt = StableIdentity.monotonic(now: now, previous: policy.deletionBarrierAt ?? now); policy.deletedAt = nil }
        if existing == nil { policy.createdAt = now; context.insert(policy) }
        try touch(policy, now, writer)
        return try JSONEncoder().encode(MoneyInverse(before: before.map { [$0] } ?? [], after: [try policy.record()]))
    }

    private static func restoreTripEnvelope(_ trip: Trip, _ context: ModelContext, _ now: Date, _ writer: String) throws -> Envelope {
        let existing = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.id == trip.id }
        guard existing.count <= 1 else { throw MoneyCommandError.invalidReference }
        if let old = existing.first {
            guard old.role == "trip", old.mergedInto == nil else { throw MoneyCommandError.invalidReference }
            var record = try old.record()
            let stamp = StableIdentity.monotonic(now: now, previous: record.date("updatedAt") ?? now)
            try record.set(Optional<Date>.none, for: "deletedAt"); try record.set(stamp, for: "restoredAt"); try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID")
            try old.apply(record); return old
        }
        let row = Envelope(); row.id = trip.id; row.role = "trip"; row.name = "رحلة " + trip.city; row.createdAt = now; context.insert(row); try touch(row, now, writer); return row
    }
    private static func configureTrip(_ p: [String: MadarCore.JSONValue], context: ModelContext, now: Date, writer: String) throws {
        guard let id = uuid(p, "id"), let trip = try context.fetch(FetchDescriptor<Trip>()).first(where: { $0.id == id && live($0) && !$0.dismissed }),
              trip.currency == optionalText(p, "expectedCurrency"), trip.fxRateToHome == optionalText(p, "expectedRate") else { throw MoneyCommandError.invalidReference }
        let code = text(p, "currency"), home = try SettingsStore(context: context).value(for: "core.currency").string ?? "SAR"
        try currency(code)
        let rate = code == home ? nil : optionalText(p, "rate")
        if code != home { guard let rate else { throw MoneyCommandError.missingRate }; _ = try FX.parseRate(rate) }
        trip.currency = code; trip.fxRateToHome = rate; trip.fxSetAt = now; try touch(trip, now, writer)
    }
    private static func fundTrip(_ p: [String: MadarCore.JSONValue], commandID: UUID, context: ModelContext, now: Date, writer: String) throws {
        let repo = MoneyRepository(context: context)
        guard let trip = try repo.trip(at: now), trip.id == uuid(p, "id"), let amount = MoneyCommandPayload.integer(p["amountMinor"]), amount > 0,
              let due = MoneyCommandPayload.date(p["due"]), trip.start != nil, due >= now else { throw MoneyCommandError.invalidReference }
        let all = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) }, role = text(p, "source")
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { live($0) }
        let balance = try sum(all.filter { $0.targetID == trip.id }.map(\.amountMinor))
        guard balance == MoneyCommandPayload.integer(p["expectedBalanceMinor"]) else { throw MoneyCommandError.invalidReference }
        let sourceIDs = Set(envelopes.filter { $0.role == role }.map(\.id))
        let available = try sum(all.filter { ($0.target == role && $0.targetID == nil) || $0.targetID.map(sourceIDs.contains) == true }.map(\.amountMinor))
        guard available >= amount else { throw MoneyCommandError.invalidAmount }
        let envelope: Envelope
        if let old = try repo.tripEnvelope(trip) { envelope = old }
        else { envelope = try restoreTripEnvelope(trip, context, now, writer) }
        envelope.targetMinor = try sum([envelope.targetMinor ?? 0, amount]); envelope.due = due; try touch(envelope, now, writer)
        let key = "trip-fund:" + commandID.uuidString
        try writeAllocations([
            .init(groupID: key, target: role == "reserve" ? .reserve : .surplus, amountMinor: -amount, kind: .fund, idempotencyKey: key + ":from"),
            .init(groupID: key, target: .envelope(envelope.id.uuidString), amountMinor: amount, kind: .fund, idempotencyKey: key + ":to")
        ], context: context, now: now, writer: writer)
    }
    private static func records(_ context: ModelContext) throws -> [DataRecord] {
        var rows = try context.fetch(FetchDescriptor<Account>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Trip>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ZakatProfile>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Card>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MoneyTransaction>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Allocation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<BankMessage>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<ImportBatch>()).filter { $0.kind == "bankBulk" }.map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Envelope>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<EnvelopePlan>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<InstallmentItem>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Statement>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<MerchantRule>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Obligation>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<CategoryLimit>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Cycle>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<CyclePolicy>()).map { try $0.record() }
        rows += try context.fetch(FetchDescriptor<Reconciliation>()).map { try $0.record() }
        return rows
    }
    private static func rebuildEnvelopes(_ context: ModelContext, _ now: Date, _ writer: String) throws {
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) }
        for row in try context.fetch(FetchDescriptor<Envelope>()) where live(row) {
            let total = try sum(allocations.filter { $0.targetID == row.id || ($0.targetID == nil && $0.target == row.role && ["reserve", "surplus"].contains(row.role)) }.map(\.amountMinor))
            if row.balanceMinor != total { row.balanceMinor = total; try touch(row, now, writer) }
        }
    }
    private static func stampDay(_ row: MoneyTransaction, at: Date, context: ModelContext, now: Date) throws {
        guard at <= now.addingTimeInterval(300) else { throw MoneyCommandError.invalidReference }
        let prayer = try PrayerRepository(context: context), place = prayer.place(at: at)
        let civil = GregorianDay.containing(at, in: place.timeZone)
        let boundary = DayBoundary(rawValue: try SettingsStore(context: context).value(for: "core.dayStart").string ?? "fajr") ?? .fajr
        let days = [civil.adding(days: -1), civil].compactMap { PrayerTimesEngine.calculate(day: $0, place: place, options: prayer.options) }
        let stored = try MadarDay.resolve(instant: at, place: place, boundary: boundary, prayerDays: days)
        row.tripID = try MoneyRepository(context: context).trip(at: at)?.id
        row.eventAt = at; row.dayKey = stored.dayKey; row.tzID = place.timeZoneID; row.dayPolicy = boundary.rawValue + "@1"
    }
    private static func messages(for row: MoneyTransaction, _ context: ModelContext) throws -> [BankMessage] {
        let ids = Set(([row] + (try context.fetch(FetchDescriptor<MoneyTransaction>())).filter { $0.mergedInto == row.id }).compactMap(\.messageID))
        return try context.fetch(FetchDescriptor<BankMessage>()).filter { ids.contains($0.id) && live($0) }
    }
    private static func transaction(_ id: UUID?, _ context: ModelContext) throws -> MoneyTransaction {
        guard let id, let row = try transactions(context).first(where: { $0.id == id }) else { throw MoneyCommandError.missingRow }; return row
    }
    private static func account(_ id: UUID, _ context: ModelContext) throws -> Account {
        guard let row = try context.fetch(FetchDescriptor<Account>()).first(where: { $0.id == id && live($0) }) else { throw MoneyCommandError.invalidReference }; return row
    }
    private static func transactions(_ context: ModelContext) throws -> [MoneyTransaction] { try context.fetch(FetchDescriptor<MoneyTransaction>()).filter { live($0) } }
    private static func currency(_ raw: String) throws { guard CurrencyExponents.specified.exponent(raw) != nil else { throw MoneyCommandError.invalidCurrency } }
    private static func fourDigits(_ raw: String) -> Bool { raw.count == 4 && raw.allSatisfy { ("0"..."9").contains($0) } }
    private static func live<T: MadarRecordModel>(_ row: T) -> Bool { (try? row.record().isLive) == true }
    private static func text(_ p: [String: MadarCore.JSONValue], _ key: String) -> String { optionalText(p, key) ?? "" }
    private static func accrueDailyPlans(_ cycle: MoneyCycleReading, through: Int, context: ModelContext, now: Date, writer: String) throws {
        let existing = Set(try context.fetch(FetchDescriptor<Allocation>()).map(\.idempotencyKey))
        var rows: [AllocationRow] = []
        for day in CycleEngine.days(through: through, cycle.input) {
            for (plan, amount) in day.dripsMinor where amount > 0 {
                guard let envelope = cycle.planEnvelopes[plan] else { throw MoneyCommandError.invalidReference }
                let key = "daily:\(cycle.id):\(plan):\(cycle.startDay.adding(days: day.day - 1))"
                let hasTo = existing.contains(key + ":to"), hasFrom = existing.contains(key + ":from")
                guard hasTo == hasFrom else { throw MoneyCommandError.invalidReference }
                if hasTo { continue }
                rows.append(.init(groupID: key, target: .daily, amountMinor: -amount, kind: try dailyPlanKind(plan, context), cycleID: cycle.id.uuidString, idempotencyKey: key + ":from"))
                rows.append(.init(groupID: key, target: .envelope(envelope.uuidString), amountMinor: amount, kind: try dailyPlanKind(plan, context), cycleID: cycle.id.uuidString, idempotencyKey: key + ":to"))
            }
        }
        try writeAllocations(rows, context: context, now: now, writer: writer)
    }

    private static func dailyPlanKind(_ id: String, _ context: ModelContext) throws -> AllocationRow.Kind {
        try context.fetch(FetchDescriptor<EnvelopePlan>()).contains { $0.id.uuidString == id && $0.kind == "repay" } ? .repay : .fund
    }

    private static func distributeBigExpense(_ p: [String: MadarCore.JSONValue], id: UUID, issuedAt: Date,
                                             context: ModelContext, now: Date, writer: String) throws {
        let repo = MoneyRepository(context: context)
        guard let cycle = try repo.cycle(at: now), let mode = BigExpense.Mode(rawValue: text(p, "mode")) else { throw MoneyCommandError.invalidReference }
        let allocations = try context.fetch(FetchDescriptor<Allocation>()).filter { live($0) }
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { live($0) }
        func balance(_ role: String) -> Int {
            let ids = Set(envelopes.filter { $0.role == role }.map(\.id))
            return allocations.filter { ($0.target == role && $0.targetID == nil) || $0.targetID.map(ids.contains) == true }.reduce(0) { $0 + $1.amountMinor }
        }
        let surplus = balance("surplus"), reserve = balance("reserve")
        guard cycle.headline.availableNowMinor == MoneyCommandPayload.integer(p["availableMinor"]),
              surplus == MoneyCommandPayload.integer(p["surplusMinor"]), reserve == MoneyCommandPayload.integer(p["reserveMinor"]) else { throw MoneyCommandError.invalidAmount }
        let row: MoneyTransaction
        if let transactionID = uuid(p, "transactionID") { row = try transaction(transactionID, context) }
        else {
            guard case .object(let expense) = p["expense"] else { throw MoneyCommandError.invalidReference }
            _ = try stage(name: "money.logExpense", payload: expense, id: id, issuedAt: issuedAt, source: .shortcut, context: context, now: now, writer: writer)
            row = try transaction(id, context)
        }
        guard row.kind == "expense", row.reviewState != "ok", !row.ignoredFromBudget, row.obligationID == nil,
              row.eventAt >= (try context.fetch(FetchDescriptor<Cycle>()).first { $0.id == cycle.id }?.start ?? .distantFuture) else { throw MoneyCommandError.invalidReference }
        try resolvePayment(row, context: context)
        row.homeAmountMinor = try FX.homeAmount(amountMinor: row.amountMinor, currency: row.currency, rate: row.rateAtTime ?? (row.currency == row.homeCurrency ? "1" : ""), home: row.homeCurrency)
        guard try repo.effect(of: row).budgetChargeMinor == row.homeAmountMinor,
              let plan = BigExpense.plan(amountMinor: row.homeAmountMinor, mode: mode, availableMinor: cycle.headline.availableNowMinor,
                  surplusMinor: surplus, reserveMinor: reserve, dailyMinor: cycle.headline.todayAllowanceMinor,
                  cycleDays: cycle.input.expectedLengthDays, cycles: MoneyCommandPayload.integer(p["cycles"]),
                  envelopeBalanceMinor: allocations.filter { $0.targetID == uuid(p, "envelopeID") && $0.targetID != nil }.reduce(0) { $0 + $1.amountMinor }) else { throw MoneyCommandError.invalidAmount }
        var splits: [MadarCore.JSONValue] = []
        func part(_ target: String, _ amount: Int, targetID: UUID? = nil) {
            guard amount > 0 else { return }
            var item: [String: MadarCore.JSONValue] = ["target": .string(target), "amountMinor": .string(String(amount))]
            if let targetID { item["targetID"] = .string(targetID.uuidString) }
            splits.append(.object(item))
        }
        part("daily", plan.dailyMinor); part("surplus", plan.surplusMinor); part("reserve", plan.reserveMinor)
        if plan.futureMinor > 0 {
            guard let envelopeID = uuid(p, "envelopeID") else { throw MoneyCommandError.invalidReference }
            if let existing = envelopes.first(where: { $0.id == envelopeID }) {
                guard !["reserve", "surplus"].contains(existing.role) else { throw MoneyCommandError.invalidReference }
            } else {
                guard let name = optionalText(p, "envelopeName"), !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw MoneyCommandError.invalidReference }
                let e = Envelope(); e.id = envelopeID; e.name = name; e.createdAt = now; context.insert(e); try touch(e, now, writer)
            }
            part("envelope", plan.futureMinor, targetID: envelopeID)
            // Its id names the original purchase. The next actual cycle starts its daily repayment, not a predicted date.
            if plan.repaymentMinor > 0 {
            let repayment = EnvelopePlan(); repayment.id = row.id; repayment.envelopeID = envelopeID; repayment.kind = "repay"; repayment.source = "daily"; repayment.period = "perCycle"
            repayment.perPaycheckMinor = plan.paymentsMinor.first ?? 0; repayment.repaymentTotalMinor = plan.repaymentMinor; repayment.repaymentPaychecks = plan.cycles
            repayment.createdAt = now; context.insert(repayment); try touch(repayment, now, writer)
            }
        }
        try confirm(row, payload: ["allocations": .array(splits)], context: context, now: now, writer: writer)
    }

    private static func optionalText(_ p: [String: MadarCore.JSONValue], _ key: String) -> String? { if case .string(let s) = p[key] { s } else { nil } }
    private static func uuid(_ p: [String: MadarCore.JSONValue], _ key: String) -> UUID? { optionalText(p, key).flatMap(UUID.init(uuidString:)) }
    private static func strings(_ value: MadarCore.JSONValue?) -> [String] { if case .array(let list) = value { list.compactMap { if case .string(let s) = $0 { s } else { nil } } } else { [] } }
    private static func transactionKind(_ kind: BankMessageKind) -> String {
        switch kind {
        case .purchase: "expense"
        case .transferOut, .transferIn: "transfer"
        case .reversal, .refund: "refund"
        case .bnplInstalment: "repayment"
        default: kind.rawValue
        }
    }
    private static func recordKey(_ row: DataRecord) -> String { row.model + ":" + row.id.uuidString }
    static func sum(_ values: [Int]) throws -> Int {
        try values.reduce(0) { total, next in
            let result = total.addingReportingOverflow(next); guard !result.overflow else { throw MoneyCommandError.invalidAmount }; return result.partialValue
        }
    }
    private static func touch<T: MadarRecordModel>(_ row: T, _ now: Date, _ writer: String, deleting: Bool = false) throws {
        var record = try row.record(), stamp = now
        if let previous = record.date("updatedAt") { stamp = StableIdentity.monotonic(now: now, previous: previous) }
        try record.set(stamp, for: "updatedAt"); try record.set(writer, for: "writerID")
        if deleting { try record.set(stamp, for: "deletedAt"); try record.set(stamp, for: "deletionBarrierAt") }
        try row.apply(record)
    }
}
