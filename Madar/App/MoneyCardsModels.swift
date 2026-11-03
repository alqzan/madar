import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyCardMovement: Identifiable {
    var id: UUID
    var merchant: String
    var amountMinor: Int
    var day: GregorianDay
    var budgeted: Bool
    var detail: MoneySourceDetail
}
struct MoneyCardReading: Identifiable {
    var id: UUID
    var name: String
    var bank: String
    var last4: String
    var kind: String
    var network: String
    var billedMinor: Int
    var unbilledMinor: Int
    var limitMinor: Int?
    var minimumMinor: Int?
    var cashbackBp: Int?
    var aprBp: Int?
    var close: GregorianDay?
    var due: GregorianDay?
    var nextClose: GregorianDay?
    var purchaseDue: GregorianDay?
    var estimatedClose: Bool
    var graceDays: Int?
    var purchases: [MoneyCardMovement]
    var matchedPurchases: [MoneyCardMovement]
    var payment: MoneyCardMovement?
    var sources: [String: MoneySourceDetail]
    var owedMinor: Int { billedMinor + unbilledMinor }
}
struct MoneyCardDue: Identifiable {
    var id: String
    var cardID: UUID?
    var name: String
    var day: GregorianDay
    var amountMinor: Int
    var cashAfterMinor: Int
}
struct MoneyCardsReading {
    var today: GregorianDay
    var cards: [MoneyCardReading]
    var dues: [MoneyCardDue]
    var cashMinor: Int
}
extension AppMoneyService {
    func loadCards(at instant: Date? = nil) throws -> MoneyCardsReading {
        let now = instant ?? app.prayerNow(), zone = app.activePlace.timeZone
        let home = try load(at: now), context = ModelContext(app.container), repo = MoneyRepository(context: context)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let transactions = try repo.confirmedTransactions().filter { $0.eventAt <= now }
        let statements = try context.fetch(FetchDescriptor<Statement>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.closeDate <= now }
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.ownership == "mine" && $0.tracked }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let debts = try repo.cardDebts(at: now)
        let cards = try context.fetch(FetchDescriptor<Card>()).filter { card in card.deletedAt == nil && card.mergedInto == nil && (card.accountID == nil || accounts.contains { $0.id == card.accountID }) }.sorted { $0.name < $1.name }
        func movement(_ row: MoneyTransaction) throws -> MoneyCardMovement {
            let day = try GregorianDay(row.dayKey)
            return .init(id: row.id, merchant: row.merchant ?? row.counterparty ?? (row.kind == "cardPayment" ? "سداد البطاقة" : "حركة بطاقة"), amountMinor: ["refund", "cashback"].contains(row.kind) ? -row.homeAmountMinor : row.homeAmountMinor, day: day, budgeted: !row.ignoredFromBudget,
                detail: .init(id: row.id.uuidString, title: row.kind == "cardPayment" ? "سداد البطاقة" : row.merchant ?? "حركة بطاقة", amountMinor: row.homeAmountMinor,
                    explanation: row.kind == "cardPayment" ? "تحويل لسداد البطاقة؛ ينقص النقد والدين معًا، ولا يُخصم من اليومية مرة أخرى." : row.kind == "refund" ? "ردّ مرتبط بالشراء الأصلي؛ يعود للميزانية على يوم الأصل." : row.ignoredFromBudget ? "شراء مثبت، خارج الميزانية. يبقى في دين البطاقة أو رصيد حسابها." : "حركة مؤكّدة؛ أثر الميزانية في يوم الشراء، والنقد عند سداد البطاقة الائتمانية.",
                    message: messages.first { $0.id == row.messageID }?.text, date: day))
        }
        let readings = try cards.map { card -> MoneyCardReading in
            let history = statements.filter { $0.cardID == card.id }.sorted { $0.closeDate < $1.closeDate }
            let statement = history.last, debt = debts.first { $0.cardID == card.id }
            let next = CardStatements.predictNextClose(history.map(\.closeDate), calendar: calendar).flatMap { $0 > now ? $0 : nil }
            let purchaseDue = next.flatMap { next -> Date? in
                guard let statement, let due = statement.dueDate else { return nil }
                let months = calendar.dateComponents([.month], from: calendar.dateInterval(of: .month, for: statement.closeDate)!.start, to: calendar.dateInterval(of: .month, for: next)!.start).month ?? 0
                return calendar.date(byAdding: .month, value: months, to: due)
            }
            let tx = transactions.filter { $0.cardID == card.id }.sorted { $0.eventAt > $1.eventAt }
            let purchases = try tx.filter { ["expense", "fee", "refund", "cashback"].contains($0.kind) && $0.eventAt > (statement?.closeDate ?? .distantPast) }.map(movement)
            let payment = tx.first { $0.kind == "cardPayment" }
            let paidStatement = payment.flatMap { payment in history.last { $0.closeDate < payment.eventAt } }
            let periodStart = paidStatement?.periodStart ?? paidStatement.flatMap { paid in history.last { $0.closeDate < paid.closeDate }?.closeDate }
            let matched = try tx.filter { row in
                guard let paidStatement, let periodStart else { return false }
                return ["expense", "fee"].contains(row.kind) && row.eventAt >= periodStart && row.eventAt < paidStatement.closeDate
            }.map(movement)
            var sources: [String: MoneySourceDetail] = [:]
            let closeDay = statement.map { GregorianDay.containing($0.closeDate, in: zone) }
            let sourceMessage = messages.first { $0.id == statement?.messageID }?.text
            sources["statement"] = .init(id: "statement-" + card.id.uuidString, title: "الكشف المستحق", amountMinor: debt?.statementLeftMinor ?? 0,
                explanation: statement == nil ? "لا كشف محفوظ لهذه البطاقة. لا يُفترض أن الكشف صفر أو أن تاريخ القفل معروف." : "المتبقي من الكشف المحفوظ بعد السداد والردود المرتبطة؛ كشف البنك هو المرجع.", message: sourceMessage, date: closeDay, estimated: statement?.closeDateSource == "estimated")
            sources["unbilled"] = .init(id: "unbilled-" + card.id.uuidString, title: "غير المفوتر", amountMinor: debt?.unbilledLeftMinor ?? 0,
                explanation: statement == nil ? "كل حركات البطاقة المؤكدة قبل وصول أول كشف، بعد الردود والسداد. لا نعرف فترة كشف البنك بعد." : "الحركات المؤكدة بعد آخر قفل، بعد الردود وما زاد من السداد. لا تُضاف إلى الكشف مرتين.", message: nil, date: closeDay, estimated: statement?.closeDateSource == "estimated")
            if statement == nil { sources["statement"]?.valueText = "لم يصل كشف" }
            sources["minimum"] = .init(id: "minimum-" + card.id.uuidString, title: "الحد الأدنى", amountMinor: statement?.minimumDueMinor ?? 0,
                explanation: statement == nil ? "لم يصل كشف يذكر الحد الأدنى." : "الحد الأدنى من آخر كشف محفوظ؛ ما دفعته منذ القفل يُحتسب منه. لا يعني إعفاء الباقي من الفائدة.", message: sourceMessage, date: closeDay)
            if statement == nil { sources["minimum"]?.valueText = "لم يصل كشف" }
            let fields = (try? JSONSerialization.jsonObject(with: card.fieldSourcesJSON)) as? [String: Any] ?? [:]
            for (key, value, title) in [("limitMinor", card.limitMinor, "حد البطاقة"), ("cashbackBp", card.cashbackBp, "نسبة الاسترداد"), ("aprBp", card.aprBp, "نسبة الفائدة السنوية")] {
                let field = fields[key] as? [String: Any], source = field?["source"] as? String ?? fields[key] as? String
                let explanation = source == "entered" ? "أدخلته يدويًا." : source == "inferred" ? "قيمة مستنتجة؛ راجع كشف البنك." : source == "message" ? "من رسالة البنك المحفوظة لهذا الحقل." : "لم يُحفظ مصدر هذا الحقل بعد؛ راجع البطاقة أو كشف البنك."
                sources[key] = .init(id: key + card.id.uuidString, title: title, amountMinor: key == "limitMinor" ? value ?? 0 : 0,
                    explanation: (value == nil ? "القيمة غير معروفة. " : "") + explanation + (key != "limitMinor" && value != nil ? " النسبة " + digits.amount(minorUnits: Int64(value!), fractionDigits: 2, signed: false) + "٪." : ""),
                    message: (field?["messageID"] as? String).flatMap(UUID.init(uuidString:)).flatMap { id in messages.first { $0.id == id }?.text }, date: nil)
                if key != "limitMinor" || value == nil { sources[key]?.valueText = value.map { digits.amount(minorUnits: Int64($0), fractionDigits: 2, signed: false) + "٪" } ?? "غير معروف" }
            }
            let paid = max(0, (statement?.statementMinor ?? 0) - (debt?.statementLeftMinor ?? 0))
            return .init(id: card.id, name: card.name, bank: card.bank, last4: card.last4, kind: card.kind, network: card.network,
                billedMinor: debt?.statementLeftMinor ?? 0, unbilledMinor: debt?.unbilledLeftMinor ?? 0, limitMinor: card.limitMinor,
                minimumMinor: statement.map { max(0, $0.minimumDueMinor - paid) }, cashbackBp: card.cashbackBp, aprBp: card.aprBp,
                close: closeDay, due: statement?.dueDate.map { GregorianDay.containing($0, in: zone) }, nextClose: next.map { GregorianDay.containing($0, in: zone) },
                purchaseDue: purchaseDue.map { GregorianDay.containing($0, in: zone) }, estimatedClose: statement?.closeDateSource == "estimated",
                graceDays: purchaseDue.map { max(0, MadarCalendarDays.distance(from: today, to: .containing($0, in: zone))) },
                purchases: purchases, matchedPurchases: matched, payment: try payment.map(movement), sources: sources)
        }
        var dues = readings.compactMap { card -> MoneyCardDue? in
            guard card.kind == "credit", let due = card.due, card.billedMinor > 0 else { return nil }
            return .init(id: card.id.uuidString, cardID: card.id, name: card.name, day: due, amountMinor: card.billedMinor, cashAfterMinor: 0)
        }
        dues += home.obligations.map { .init(id: $0.id.uuidString, cardID: nil, name: $0.name, day: $0.due, amountMinor: $0.amountMinor, cashAfterMinor: 0) }
        dues.sort { $0.day == $1.day ? $0.id < $1.id : $0.day < $1.day }
        let coverage = CardPlanning.cashAfter(availableMinor: home.basis.inAccountMinor, dueMinor: dues.map(\.amountMinor)) ?? []
        for index in dues.indices { if index < coverage.count { dues[index].cashAfterMinor = coverage[index] } }
        return .init(today: today, cards: readings, dues: dues, cashMinor: home.basis.inAccountMinor)
    }
}
