import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

/// One line of «دفتر القيد» (Table 1): what the salary pays, in order, and the balance after it.
struct MoneySalaryEntry: Identifiable, Equatable {
    var id: String
    var title: String
    var amountMinor: Int
    var balanceMinor: Int
    var tint: String
    var explanation: String
}

struct MoneySalaryBullet: Identifiable, Equatable {
    var id: String
    var text: String
    var tint: String
}

struct MoneySalaryHistoryBar: Identifiable, Equatable {
    var id: String
    var label: String
    var carriedMinor: Int
    var current: Bool
}

struct MoneySalaryReading {
    var opening: SalaryOpeningReading
    var cycleName: String
    var ratingWord: String
    var ratingTint: String
    var entries: [MoneySalaryEntry]
    var bullets: [MoneySalaryBullet]
    var history: [MoneySalaryHistoryBar]
    var surplusAfterMinor: Int
    var today: GregorianDay
    var needsChoice: Bool
    var plan: SalaryOpeningPlan { opening.plan }
}

extension AppMoneyService {
    /// The cycle takes the name of the month holding most of its days, in `mal.cycleCalendar` (27 Oct → 26 Nov = «نوفمبر»).
    func cycleMonthName(start: GregorianDay, end: GregorianDay) -> String {
        let hijri = app.string("mal.cycleCalendar") == "hijri", zone = app.activePlace.timeZone
        let middle = start.adding(days: MadarCalendarDays.distance(from: start, to: end) / 2).date(in: zone)
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: hijri ? .islamicUmmAlQura : .gregorian); formatter.locale = Locale(identifier: "ar"); formatter.timeZone = zone
        formatter.dateFormat = "MMMM"
        return formatter.string(from: middle)
    }

    func loadSalary(id: UUID, previewCycle: UUID, remainderTo: SalaryRemainder? = nil) throws -> MoneySalaryReading {
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        _ = app.prayerRevision
        let context = ModelContext(app.container)
        let opening = try MoneyRepository(context: context).salaryOpening(salaryID: id, newCycleID: previewCycle, remainderOverride: remainderTo)
        let plan = opening.plan, salary = opening.salaryMinor, length = opening.input.expectedLengthDays
        let daily = plan.rate.dailyRateMinor
        // DECISIONS 16 Oct: the word follows «الباقي» in dailies — 3 or more = comfortable, 0 or more = balanced, below = tight.
        let rating: (String, String) = plan.leftoverMinor >= 3 * max(daily, 1) ? ("مريحة", "surplus") : plan.leftoverMinor >= 0 ? ("متوازنة", "accent") : ("ضيقة", "due")

        var balance = salary
        var entries = [MoneySalaryEntry(id: "salary", title: "الراتب", amountMinor: salary, balanceMinor: balance, tint: "ink",
            explanation: "دخل الدورة كله؛ منه تُحسب كل نسبة في التقرير.")]
        balance -= plan.obligationsMinor
        entries.append(.init(id: "obligations", title: "الالتزامات", amountMinor: -plan.obligationsMinor, balanceMinor: balance, tint: "accent",
            explanation: "أقساط وفواتير يحلّ موعدها قبل الراتب القادم، بعملتك."))
        balance -= plan.envelopesMinor
        entries.append(.init(id: "envelopes", title: "المظاريف", amountMinor: -plan.envelopesMinor, balanceMinor: balance, tint: "bills",
            explanation: "ما تأخذه المظاريف من الراتب نفسه؛ التمويل من الفوائض أو الاحتياطي لا يُحسب هنا."))
        balance -= plan.dailiesMinor
        entries.append(.init(id: "dailies", title: "يومياتك " + digits.string(length) + " × " + amount(daily), amountMinor: -plan.dailiesMinor, balanceMinor: balance, tint: "surplus",
            explanation: plan.rate.lastDayRemainderMinor > 0 ? "اليومية مجمّدة لهذه الدورة، وباقي القسمة " + amount(plan.rate.lastDayRemainderMinor) + " في آخر يوم." : "اليومية مجمّدة لهذه الدورة؛ تعديلها لاحقًا يبدأ من اليوم التالي."))

        var bullets: [MoneySalaryBullet] = []
        if salary > 0 {
            bullets.append(.init(id: "obligations", text: "الالتزامات " + percent(plan.obligationsMinor, of: salary) + " فقط من الراتب.", tint: "accent"))
        }
        if let close = plan.close, let carried = opening.input.closing?.availableNowMinor {
            if carried > 0 {
                let target = close.toReserveMinor == 0 ? "الفوائض" : close.toSurplusMinor == 0 ? "الاحتياطي" : "الفوائض حتى سقفها ثم الاحتياطي"
                bullets.append(.init(id: "carry", text: "فائض " + amount(carried) + " من الدورة السابقة يذهب إلى " + target + "، لا إلى الراتب.", tint: "surplus"))
            } else if close.offsetMinor > 0 {
                bullets.append(.init(id: "carry", text: "عجز " + amount(-carried) + " من الدورة السابقة غُطّي من الفوائض.", tint: "reserve"))
            } else if close.carryMinor < 0 {
                bullets.append(.init(id: "carry", text: "عجز " + amount(-close.carryMinor) + " يُرحَّل إلى الدورة الجديدة ظاهرًا.", tint: "due"))
            }
        }
        if plan.toSurplusMinor > 0 || plan.toReserveMinor > 0 {
            let full = opening.input.remainder == .surplusThenReserve && plan.toSurplusMinor == 0
            let text = plan.toReserveMinor == 0 ? "الباقي كله للفوائض." : full ? "الفوائض بلغت سقفها " + amount(opening.input.surplusCapMinor) + "، فالباقي كله للاحتياطي." : plan.toSurplusMinor == 0 ? "الباقي كله للاحتياطي." :
                "الباقي يملأ الفوائض حتى " + amount(opening.input.surplusCapMinor) + "، والزائد " + amount(plan.toReserveMinor) + " للاحتياطي."
            bullets.append(.init(id: "leftover", text: text, tint: "reserve"))
        } else if plan.leftoverMinor < 0 {
            bullets.append(.init(id: "leftover", text: "يومياتك والتزاماتك أكبر من الراتب بـ" + amount(-plan.leftoverMinor) + "؛ راجع اليومية أو المظاريف قبل الاعتماد.", tint: "due"))
        }
        for short in plan.shortfalls {
            let name = opening.envelopes.first { $0.planID.uuidString == short.planID }?.name ?? "مظروف"
            bullets.append(.init(id: "short-" + short.planID, text: "ينقص " + amount(short.shortMinor) + " من «" + name + "»؛ مصدره لا يكفي هذه المرة.", tint: "due"))
        }

        let zone = app.activePlace.timeZone
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: app.string("mal.cycleCalendar") == "hijri" ? .islamicUmmAlQura : .gregorian); formatter.locale = Locale(identifier: "ar"); formatter.timeZone = zone
        formatter.dateFormat = "MMMM"
        // Each bar carries its cycle's name by the same rule as «دورة …» (the month holding most of its days).
        var history = opening.history.suffix(4).enumerated().map { index, item in
            MoneySalaryHistoryBar(id: "h\(index)", label: formatter.string(from: item.start.addingTimeInterval(15 * 86_400)), carriedMinor: item.carriedMinor, current: false)
        }
        if let closing = opening.input.closing, let start = opening.closingStartDay {
            history.append(.init(id: "current", label: cycleMonthName(start: start, end: opening.startDay), carriedMinor: closing.availableNowMinor, current: true))
        }
        _ = zone
        let surplusAfter = (plan.close?.surplusAfterMinor ?? opening.surplusBeforeMinor)
            + plan.rows.filter { $0.target == .surplus && $0.cycleID == previewCycle.uuidString }.reduce(0) { $0 + $1.amountMinor }
        return .init(opening: opening, cycleName: "دورة " + cycleMonthName(start: opening.startDay, end: opening.endDay), ratingWord: rating.0, ratingTint: rating.1,
                     entries: entries, bullets: bullets, history: history, surplusAfterMinor: surplusAfter,
                     today: try DiaryLineRenderer.today(context: context, now: app.prayerNow()),
                     needsChoice: remainderTo == nil && (plan.awaitingChoiceMinor > 0 || (plan.close?.awaitingChoiceMinor ?? 0) > 0))
    }

    /// A share of the salary as a whole percent («٩٪»), rounded half up in integers.
    func percent(_ part: Int, of whole: Int) -> String {
        guard whole > 0 else { return digits.string(0) + "٪" }
        return digits.string((part * 100 + whole / 2) / whole) + "٪"
    }
}
