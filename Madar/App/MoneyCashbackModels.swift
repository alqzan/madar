import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// M5-V16 «الاسترداد النقدي · الجرّة»: the year in `core.firstCalendar`, its months, and every card's cashback, all
/// from `CashbackJar` (one definition per number). Read-only; the only write is the hand-entered rate (§7.5).
struct MoneyCashbackCard: Identifiable {
    var id: UUID
    var name: String
    var kind: String
    var rateBp: Int?
    /// 0 gold (the main credit card), 1 navy, 2 olive, 3 plum: the same order as the card miniatures.
    var tint: Int
    var total: CashbackJar.CardTotal
    var recorded: Bool
    var source: MoneySourceDetail
}
struct MoneyCashbackMonth: Identifiable {
    var id: Int
    var start: GregorianDay
    var short: String
    /// The other calendar's month where this one starts, under the axis label.
    var secondaryShort: String
    var labels: MadarDateLabels
    var current: Bool
}
struct MoneyCashbackSwitch {
    var to: MoneyCashbackCard
    var rows: [MoneyCashbackSwitchRow]
    var totalMinor: Int
}
struct MoneyCashbackSwitchRow: Identifiable {
    var id: String
    var categoryID: UUID?
    var title: String
    var from: [String]
    var baseMinor: Int
    var gainMinor: Int
    var preferredCardID: UUID?
}
struct MoneyCashbackDestination: Identifiable {
    var id: UUID
    var name: String
    var role: String
}
struct MoneyCashbackReading {
    var yearTitle: String
    var yearSecondary: String
    var months: [MoneyCashbackMonth]
    var cards: [MoneyCashbackCard]
    var jar: CashbackJar.Reading
    var switchSuggestion: MoneyCashbackSwitch?
    var hasPurchases: Bool
    var destinations: [MoneyCashbackDestination]
    var destinationID: UUID?
    var current: Int { months.count - 1 }
}

extension AppMoneyService {
    private static let gregorianShort = ["ينا", "فبر", "مار", "أبر", "ماي", "يون", "يول", "أغس", "سبت", "أكت", "نوف", "ديس"]
    private func hijriShort(_ month: Int) -> String {
        ["محرم", "صفر", "ربيع " + digits.string(1), "ربيع " + digits.string(2), "جمادى " + digits.string(1), "جمادى " + digits.string(2), "رجب", "شعبان", "رمضان", "شوال", "القعدة", "الحجة"][(month - 1) % 12]
    }

    func loadCashback(at instant: Date? = nil) throws -> MoneyCashbackReading? {
        let now = instant ?? app.prayerNow(), zone = app.activePlace.timeZone
        let context = ModelContext(app.container), repo = MoneyRepository(context: context)
        let today = try DiaryLineRenderer.today(context: context, now: now)
        let days = logCalendar, hijriFirst = app.string("core.firstCalendar") != "gregorian"
        // The year and its twelve month starts in the primary calendar.
        let year = hijriFirst ? MadarYear.hijriYear(today, days) : MadarYear.gregorianYear(today)
        var starts: [GregorianDay] = [year.start]
        while starts.count < 12 {
            let last = starts[starts.count - 1]
            if hijriFirst { starts.append(last.adding(days: days.hijriMonthLength(containing: last))) }
            else { starts.append(try GregorianDay(year: last.month == 12 ? last.year + 1 : last.year, month: last.month == 12 ? 1 : last.month + 1, day: 1)) }
        }
        let end = year.start.adding(days: year.length)
        func month(_ day: GregorianDay) -> Int? {
            guard day >= year.start, day < end else { return nil }
            return starts.lastIndex { $0 <= day }
        }
        guard let current = month(today) else { return nil }
        let months = (0...current).map { index in
            MoneyCashbackMonth(id: index, start: starts[index], short: hijriFirst ? hijriShort(days.hijri(starts[index]).month) : Self.gregorianShort[starts[index].month - 1],
                               secondaryShort: hijriFirst ? Self.gregorianShort[starts[index].month - 1] : hijriShort(days.hijri(starts[index]).month),
                               labels: logMonthLabels(starts[index]), current: index == current)
        }
        let last = end.adding(days: -1)
        let yearTitle: String, yearSecondary: String
        if hijriFirst {
            yearTitle = digits.string(days.hijri(today).year) + "هـ"
            yearSecondary = (year.start.year == last.year ? digits.string(last.year) : digits.string(year.start.year) + "–" + digits.string(last.year)) + "م"
        } else {
            yearTitle = digits.string(today.year) + "م"
            let a = days.hijri(year.start).year, b = days.hijri(last).year
            yearSecondary = (a == b ? digits.string(a) : digits.string(a) + "–" + digits.string(b)) + "هـ"
        }

        // The same card set as «البطاقات»: live, owned and tracked accounts only.
        let accounts = try context.fetch(FetchDescriptor<Account>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.ownership == "mine" && $0.tracked }
        let rows = try context.fetch(FetchDescriptor<Card>()).filter { card in card.deletedAt == nil && card.mergedInto == nil && (card.accountID == nil || accounts.contains { $0.id == card.accountID }) }
        let ordered = rows.filter { $0.kind == "credit" }.sorted { $0.name < $1.name } + rows.filter { $0.kind != "credit" }.sorted { $0.name < $1.name }
        let ids = Set(ordered.map(\.id))
        let transactions = try repo.confirmedTransactions().filter { $0.eventAt <= now }
        let byID = Dictionary(transactions.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        let categories = Dictionary(try context.fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }.map { ($0.id, $0) }, uniquingKeysWith: { a, _ in a })
        func monthOf(_ tx: MoneyTransaction) -> Int? { (try? GregorianDay(tx.dayKey)).flatMap(month) }
        var purchases: [CashbackJar.Purchase] = []
        for tx in transactions {
            switch tx.kind {
            case "expense":
                guard let card = tx.cardID, ids.contains(card), let m = monthOf(tx) else { continue }
                let category = tx.categoryID.flatMap { categories[$0] }
                purchases.append(.init(cardID: card.uuidString, month: m, amountMinor: tx.homeAmountMinor, category: category?.name, categoryID: category?.id.uuidString))
            case "refund":
                // A linked refund lands on its original's month and category (V13: «يعود إلى يوم الأصل»).
                let original = tx.relatedTransactionID.flatMap { byID[$0] }
                guard let card = tx.cardID ?? original?.cardID, ids.contains(card), let m = original.map(monthOf) ?? monthOf(tx) else { continue }
                let category = (original?.categoryID ?? tx.categoryID).flatMap { categories[$0] }
                purchases.append(.init(cardID: card.uuidString, month: m, amountMinor: -tx.homeAmountMinor, category: category?.name, categoryID: category?.id.uuidString))
            default: continue
            }
        }
        let entries = try context.fetch(FetchDescriptor<CashbackEntry>()).filter { $0.deletedAt == nil && $0.mergedInto == nil && $0.eventAt <= now }
        let earned = entries.compactMap { entry -> CashbackJar.Recorded? in
            guard entry.kind == "earned", let card = entry.cardID, ids.contains(card), let m = month(.containing(entry.eventAt, in: zone)) else { return nil }
            return .init(cardID: card.uuidString, month: m, amountMinor: entry.amountMinor)
        }
        // Landed: each confirmed cashback movement once (its card from the movement or its linked redeemed row), plus
        // redeemed rows that carry no movement.
        var landed: [CashbackJar.Landed] = transactions.compactMap { tx in
            guard tx.kind == "cashback", monthOf(tx) != nil else { return nil }
            let card = tx.cardID ?? entries.first { $0.kind == "redeemed" && $0.transactionID == tx.id }?.cardID
            return .init(cardID: card.flatMap { ids.contains($0) ? $0.uuidString : nil }, amountMinor: tx.homeAmountMinor)
        }
        landed += entries.compactMap { entry in
            guard entry.kind == "redeemed", entry.transactionID == nil, month(.containing(entry.eventAt, in: zone)) != nil else { return nil }
            return .init(cardID: entry.cardID.flatMap { ids.contains($0) ? $0.uuidString : nil }, amountMinor: entry.amountMinor)
        }
        let jarCards = ordered.map { CashbackJar.Card(id: $0.id.uuidString, rateBp: $0.cashbackBp) }
        guard let jar = CashbackJar.read(.init(cards: jarCards, current: current, purchases: purchases, earned: earned, landed: landed)) else { return nil }
        let messages = try context.fetch(FetchDescriptor<BankMessage>()).filter { $0.deletedAt == nil }
        var cards: [MoneyCashbackCard] = []
        var tint = 0
        for (index, card) in ordered.enumerated() {
            let fields = (try? JSONSerialization.jsonObject(with: card.fieldSourcesJSON)) as? [String: Any] ?? [:]
            let field = fields["cashbackBp"] as? [String: Any], source = field?["source"] as? String ?? fields["cashbackBp"] as? String
            let explanation = (card.cashbackBp == nil ? "النسبة غير معروفة، فلا يُقدَّر لها استرداد. " : "")
                + (source == "entered" ? "أدخلتها يدويًا." : source == "inferred" ? "قيمة مستنتجة؛ راجع شروط البطاقة." : source == "message" ? "من رسالة البنك المحفوظة لهذا الحقل." : "لم يُحفظ مصدر هذه النسبة بعد.")
                + " الاسترداد في الجرّة تقدير: مشتريات كل شهر بعد الردود × النسبة، يُقرَّب مرة واحدة. شروط البنك وكشفه هما المرجع."
            let detail = MoneySourceDetail(id: "cashback-" + card.id.uuidString, title: "نسبة الاسترداد", amountMinor: 0, explanation: explanation,
                message: (field?["messageID"] as? String).flatMap(UUID.init(uuidString:)).flatMap { id in messages.first { $0.id == id }?.text }, date: nil,
                valueText: card.cashbackBp.map { percent($0) } ?? "غير معروفة")
            let isMain = card.kind == "credit" && index == 0
            let color = isMain ? 0 : 1 + (tint % 3)
            if !isMain { tint += 1 }
            cards.append(.init(id: card.id, name: card.name, kind: card.kind, rateBp: card.cashbackBp, tint: color, total: jar.cards[index],
                               recorded: earned.contains { $0.cardID == card.id.uuidString }, source: detail))
        }
        // «أعلى استرداد» among credit cards only: moving purchases between credit cards, never onto credit.
        var suggestion: MoneyCashbackSwitch?
        let credit = cards.filter { $0.kind == "credit" }
        if let result = CashbackJar.switchToBest(cards: credit.map { .init(id: $0.id.uuidString, rateBp: $0.rateBp) }, purchases: purchases),
           let to = credit.first(where: { $0.id.uuidString == result.toCardID }) {
            suggestion = .init(to: to, rows: result.rows.map { row in
                let from = Set(credit.filter { card in
                    card.id != to.id && (card.rateBp ?? Int.max) < (to.rateBp ?? 0)
                        && purchases.contains { $0.cardID == card.id.uuidString && $0.categoryID == row.categoryID && $0.amountMinor > 0 }
                }.map(\.name)).sorted()
                let categoryID = row.categoryID.flatMap(UUID.init(uuidString:))
                return MoneyCashbackSwitchRow(id: row.categoryID ?? "uncategorised", categoryID: categoryID,
                    title: row.category ?? "بلا تصنيف", from: from, baseMinor: row.baseMinor, gainMinor: row.gainMinor,
                    preferredCardID: categoryID.flatMap { categories[$0]?.preferredCardID })
            }, totalMinor: result.totalGainMinor)
        }
        let envelopes = try context.fetch(FetchDescriptor<Envelope>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .sorted { $0.name < $1.name }
        // Surplus has its own explicit chip; showing its backing row again made the choice ambiguous.
        let destinations = envelopes.filter { $0.role != "surplus" }.map { MoneyCashbackDestination(id: $0.id, name: $0.name, role: $0.role) }
        let savedDestination = try SettingsStore(context: context).value(for: "mal.cashbackDestination").string.flatMap(UUID.init(uuidString:))
        let destinationID = savedDestination.flatMap { id in destinations.contains(where: { $0.id == id }) ? id : nil }
        return .init(yearTitle: yearTitle, yearSecondary: yearSecondary, months: months, cards: cards, jar: jar, switchSuggestion: suggestion,
                     hasPurchases: purchases.contains { $0.amountMinor > 0 }, destinations: destinations, destinationID: destinationID)
    }

    /// Basis points as a percent with no trailing zeros: 50 → «٠٫٥٪», 125 → «١٫٢٥٪», 200 → «٢٪».
    func percent(_ bp: Int) -> String {
        let whole = bp / 100, fraction = bp % 100
        if fraction == 0 { return digits.string(whole) + "٪" }
        let tenths = fraction % 10 == 0
        return digits.amount(minorUnits: Int64(tenths ? bp / 10 : bp), fractionDigits: tenths ? 1 : 2, signed: false) + "٪"
    }
}
