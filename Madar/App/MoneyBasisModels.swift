import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneySourceDetail: Identifiable {
    var id: String
    var title: String
    var amountMinor: Int
    var explanation: String
    var message: String?
    var date: GregorianDay?
    var estimated: Bool = false
}
struct MoneyBasisPiece: Identifiable {
    var id: String
    var title: String
    var amountMinor: Int
    var role: String
    var detail: MoneySourceDetail
}
struct MoneyBasisReading {
    var home: MoneyHomeReading
    var explanation: BasisBreakdown
    var reserved: [MoneyBasisPiece]
    var accounts: [MoneySourceDetail]
    var debts: [MoneySourceDetail]
}

extension AppMoneyService {
    func loadBasis() throws -> MoneyBasisReading {
        let now = app.prayerNow(), home = try load(at: now), context = ModelContext(app.container), repo = MoneyRepository(context: context)
        let input = try repo.basisInput(at: now)
        let future = home.cycle.map { ReconciliationEngine.notYetAccrued(elapsedDays: $0.elapsedDays, $0.input) }
        let explanation = BasisBreakdownEngine.explain(home.basis, futureDailyMinor: future, availableNowMinor: home.cycle?.headline.availableNowMinor)
        let zone = app.activePlace.timeZone
        let accountRows = try repo.homeAccountBalances(at: now).map { item in
            MoneySourceDetail(id: "account:" + item.account.id.uuidString, title: item.account.name, amountMinor: item.homeMinor,
                explanation: "آخر رصيد أكّدته، مضافًا إليه الداخل ومطروحًا منه الخارج المسجّل بعده. لا تنقص مشتريات الائتمان الكاش قبل السداد.",
                date: item.account.balanceAt.map { .containing($0, in: zone) })
        }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        var debts: [MoneySourceDetail] = []
        for card in try repo.cardDebts(at: now) {
            if card.statementLeftMinor > 0 {
                debts.append(.init(id: "statement:" + card.cardID.uuidString, title: "كشف " + card.cardName, amountMinor: card.statementLeftMinor,
                    explanation: "المتبقي من الكشف بعد السداد والردود المرتبطة به؛ ما زاد من السداد ينقص غير المفوتر.",
                    message: messages.first { $0.id == card.messageID }?.text, date: card.dueDate.map { .containing($0, in: zone) }, estimated: card.estimatedClose))
            }
            if card.unbilledLeftMinor > 0 {
                debts.append(.init(id: "unbilled:" + card.cardID.uuidString, title: "غير مفوتر، " + card.cardName, amountMinor: card.unbilledLeftMinor,
                    explanation: "مشتريات الائتمان والرسوم بعد قفل الكشف، بعد الردود والمدفوع الزائد على الكشف.", estimated: card.estimatedClose))
            }
        }
        let obligations = try context.fetch(FetchDescriptor<Obligation>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let items = try context.fetch(FetchDescriptor<InstallmentItem>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        for obligation in obligations where obligation.kind == "installment" {
            let remaining = items.filter { $0.obligationID == obligation.id }.reduce(0) { $0 + max(0, $1.amountMinor - $1.paidMinor) }
            if remaining > 0 {
                debts.append(.init(id: "bnpl:" + obligation.id.uuidString, title: "باقي " + obligation.name, amountMinor: remaining,
                    explanation: "باقي الأقساط من أصل الشراء، محسوب مرة واحدة. سداد القسط ينقص الكاش والدين معًا، ولا يُحسب مصروفًا جديدًا.",
                    message: messages.first { $0.id == obligation.sourceMessageID }?.text))
            }
        }
        let envelopeAmount = input.envelopeAllocationsMinor.reduce(0, +)
        let reserved = [
            MoneyBasisPiece(id: "envelopes", title: "المظاريف والاحتياطي", amountMinor: envelopeAmount, role: "envelopes",
                detail: .init(id: "envelopes", title: "المظاريف والاحتياطي", amountMinor: envelopeAmount, explanation: "مجموع التخصيصات الحية للمظاريف والاحتياطي والفائض؛ المظروف السالب داخل المجموع، وليس دينًا يضاف إلى «عليك».")),
            MoneyBasisPiece(id: "bills", title: "الفواتير", amountMinor: input.billsDueMinor, role: "bills",
                detail: .init(id: "bills", title: "فواتير الدورة", amountMinor: input.billsDueMinor, explanation: "الفواتير التي حُجزت لهذه الدورة ولم تُسدد. الحركة المرتبطة بالفاتورة لا تخصم من يومك مرة أخرى.")),
            MoneyBasisPiece(id: "loan", title: "القرض المستحق", amountMinor: input.loanDueMinor, role: "reserveText",
                detail: .init(id: "loan", title: "القرض المستحق", amountMinor: input.loanDueMinor, explanation: "قسط القرض المحجوز لهذه الدورة. باقي القرض خارج «عليك»؛ ينقص الكاش عند سداده ويسقط المحجوز بقدره."))
        ]
        return .init(home: home, explanation: explanation, reserved: reserved, accounts: accountRows, debts: debts)
    }
}
