import Foundation
import Testing
@testable import MadarCore

/// Expected values come from §8 item 8 (sanctity = adhan + 30 min, digest names kinds, B − 1 + digest),
/// §7.1 (habit reminder at window start, none without a window) and the salah.qadaReminder options.
@Suite struct RoomRemindersTests {
    let day = try! #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    var dawn: Date { day.fajr.addingTimeInterval(-3 * 3600) }
    @Test func cardDueLeadDaysStableIdentityAndPaidSuppression() throws {
        let card = UUID(), due = try GregorianDay("2026-10-12"), zone = ActivePlace.riyadh.timeZone
        let reminder = try #require(RoomReminders.cardDue(cardID: card, dueDay: due, amountMinor: 425_000, daysBefore: 3, timeZone: zone, prayerDays: [day], now: dawn))
        #expect(reminder.id == "mal.cardDue.\(card.uuidString).2026-10-12")
        #expect(reminder.dayKey == "2026-10-09")
        #expect(GregorianDay.containing(reminder.dueAt, in: zone).description == "2026-10-09")
        #expect(SanctityGuard(prayerDays: [day]).clamp(reminder.dueAt) == reminder.dueAt)
        #expect(RoomReminders.cardDue(cardID: card, dueDay: due, amountMinor: 1, daysBefore: 3, timeZone: zone, prayerDays: [day], now: dawn)?.id == reminder.id)
        #expect(RoomReminders.cardDue(cardID: card, dueDay: due, amountMinor: 0, daysBefore: 3, timeZone: zone, prayerDays: [day], now: dawn) == nil)
        #expect(RoomReminders.cardDue(cardID: card, dueDay: due, amountMinor: 1, daysBefore: 2, timeZone: zone, prayerDays: [day], now: dawn) == nil)
        #expect(RoomReminders.cardDue(cardID: card, dueDay: due, amountMinor: 1, daysBefore: 3, timeZone: zone, prayerDays: [day], now: reminder.dueAt) == nil)
        let oneDay = RoomReminders.cardDue(cardID: card, dueDay: day.day.adding(days: 1), amountMinor: 1, daysBefore: 1, timeZone: zone, prayerDays: [day], now: dawn)
        #expect(oneDay?.dayKey == "2026-10-09")
        let cash = RoomReminders.cardDue(cardID: card, dueDay: day.day, amountMinor: 1, daysBefore: 0, timeZone: zone, prayerDays: [day], now: dawn)
        #expect(cash?.id == "mal.cardCash.\(card.uuidString).2026-10-09")
        #expect(RoomReminders.digestKinds(memberIDs: [reminder.id, cash!.id]) == ["سداد البطاقة"])
    }

    @Test func billDueRemindsAheadAndOnTheDueDayThroughTheSanctityGuard() throws {
        let bill = UUID(), due = try GregorianDay("2026-10-12"), zone = ActivePlace.riyadh.timeZone
        let ahead = try #require(RoomReminders.billDue(billID: bill, dueDay: due, daysBefore: 3, timeZone: zone, prayerDays: [day], now: dawn))
        #expect(ahead.id == "mal.billDue.\(bill.uuidString).2026-10-12.3")
        #expect(ahead.dayKey == "2026-10-09")
        #expect(SanctityGuard(prayerDays: [day]).clamp(ahead.dueAt) == ahead.dueAt)
        let sameDay = try #require(RoomReminders.billDue(billID: bill, dueDay: day.day, daysBefore: 0, timeZone: zone, prayerDays: [day], now: dawn))
        #expect(sameDay.id.hasSuffix("2026-10-09.0"))
        #expect(RoomReminders.billDue(billID: bill, dueDay: due, daysBefore: 2, timeZone: zone, prayerDays: [day], now: dawn) == nil)
        #expect(RoomReminders.billDue(billID: bill, dueDay: due, daysBefore: 3, timeZone: zone, prayerDays: [day], now: ahead.dueAt) == nil)
        #expect(RoomReminders.digestKinds(memberIDs: [ahead.id, sameDay.id]) == ["موعد فاتورة"])
    }

    @Test func reconciliationReminderUsesFreeLastCheckDateAndWaitsForSanctity() throws {
        let id = UUID(), zone = ActivePlace.riyadh.timeZone
        let dueToday = RoomReminders.reconciliation(lineID: id, since: day.day.adding(days: -90), everyDays: 90,
            timeZone: zone, prayerDays: [day], now: dawn)
        #expect(dueToday?.id == "mal.reconcile.\(id.uuidString).2026-07-11.90")
        #expect(dueToday?.room == .mal && dueToday?.dayKey == "2026-10-09")
        #expect(dueToday?.dueAt == SanctityGuard(prayerDays: [day]).clamp(calendarDate(12, day: day.day, zone: zone)))
        #expect(RoomReminders.reconciliation(lineID: id, since: day.day, everyDays: 90, timeZone: zone, prayerDays: [day], now: dawn) == nil)
        #expect(RoomReminders.reconciliation(lineID: id, since: day.day, everyDays: 0, timeZone: zone, prayerDays: [day], now: dawn) == nil)

        let inSanctity = RoomReminders.reconciliation(lineID: id, since: day.day.adding(days: -90), everyDays: 90,
            timeZone: zone, prayerDays: [day], now: day.asr.addingTimeInterval(300))
        #expect(inSanctity?.dueAt == day.asr.addingTimeInterval(1800))
        #expect(RoomReminders.kindLabel(for: dueToday!.id) == "مطابقة الرصيد")
    }

    @Test func zakatReminderUsesTheChosenAnnualDateAndAmountFreeIdentity() throws {
        let anniversary = day.day.adding(days: 60), zone = ActivePlace.riyadh.timeZone
        let reminder = try #require(RoomReminders.zakat(anniversary: anniversary, lead: "1month", timeZone: zone, prayerDays: [day], now: dawn))
        #expect(reminder.id == "mal.zakat.1month.\(anniversary)")
        #expect(reminder.kind == .annualReminder && reminder.room == .mal)
        #expect(reminder.dayKey == anniversary.adding(days: -30).description)
        #expect(GregorianDay.containing(reminder.dueAt, in: zone) == anniversary.adding(days: -30))
        #expect(RoomReminders.zakat(anniversary: anniversary, lead: "off", timeZone: zone, prayerDays: [day], now: dawn) == nil)
        #expect(RoomReminders.kindLabel(for: reminder.id) == "الزكاة")

        let oneDay = try #require(RoomReminders.zakat(anniversary: anniversary, lead: "1day", timeZone: zone, prayerDays: [day], now: dawn))
        let oneWeek = try #require(RoomReminders.zakat(anniversary: anniversary, lead: "1week", timeZone: zone, prayerDays: [day], now: dawn))
        #expect(GregorianDay.containing(oneDay.dueAt, in: zone) == anniversary.adding(days: -1))
        #expect(GregorianDay.containing(oneWeek.dueAt, in: zone) == anniversary.adding(days: -7))
    }

    @Test func annualRemindersHaveABoundedHorizonAndStillUseSanctity() {
        let year = NotificationCandidate(id: "mal.zakat.1week.2027-10-09", room: .mal, kind: .annualReminder,
            dueAt: dawn.addingTimeInterval(300 * 86_400), dayKey: "2027-08-01")
        let secondYear = NotificationCandidate(id: "mal.zakat.1week.2028-10-09", room: .mal, kind: .annualReminder,
            dueAt: dawn.addingTimeInterval(730 * 86_400), dayKey: "2028-08-01")
        let outside = NotificationCandidate(id: "mal.zakat.1week.2029-10-09", room: .mal, kind: .annualReminder,
            dueAt: dawn.addingTimeInterval(741 * 86_400), dayKey: "2029-08-01")
        let ordinary = NotificationCandidate(id: "mal.cardDue.too-far", room: .mal,
            dueAt: dawn.addingTimeInterval(3 * 86_400), dayKey: "2026-10-12")
        let plan = NotificationArbiter.plan(candidates: [year, secondYear, outside, ordinary], prayerDays: [day], now: dawn,
            timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false, dayBoundary: .midnight))
        #expect(plan.scheduled.map(\.id).contains(year.id))
        #expect(plan.scheduled.map(\.id).contains(secondYear.id))
        #expect(plan.droppedIDs.contains(outside.id))
        #expect(plan.droppedIDs.contains(ordinary.id), "The 48-hour horizon stays unchanged for ordinary reminders")

        let duringSanctity = NotificationCandidate(id: "mal.zakat.1day.near", room: .mal, kind: .annualReminder,
            dueAt: day.asr.addingTimeInterval(300), dayKey: day.day.description)
        let clamped = NotificationArbiter.plan(candidates: [duringSanctity], prayerDays: [day], now: day.asr.addingTimeInterval(60),
            timeZone: ActivePlace.riyadh.timeZone, policy: .init(staleNudgeEnabled: false))
        #expect(clamped.scheduled.first?.dueAt == day.asr.addingTimeInterval(1800))
    }

    private func calendarDate(_ hour: Int, day: GregorianDay, zone: TimeZone) -> Date {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.date(bySettingHour: hour, minute: 0, second: 0, of: day.date(in: zone))!
    }

    @Test func qadaFallsAtTheEndOfTheChosenPrayersSanctity() {
        let fajr = RoomReminders.qada(days: [day], time: .afterFajr, owed: 3, now: dawn)
        #expect(fajr == [.init(id: "qada.2026-10-09", room: .salah, dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-09")])
        let isha = RoomReminders.qada(days: [day], time: .afterIsha, owed: 1, now: dawn)
        #expect(isha.first?.dueAt == day.isha.addingTimeInterval(1800))
    }

    @Test func qadaIsSilentWhenNothingIsOwedOrTheKindIsOff() {
        #expect(RoomReminders.qada(days: [day], time: .afterFajr, owed: 0, now: dawn).isEmpty)
        #expect(RoomReminders.qada(days: [day], time: .off, owed: 4, now: dawn).isEmpty)
    }

    @Test func habitReminderStartsWithItsWindowAndLeavesSanctity() {
        let id = UUID()
        // A window opening 10 minutes after the Asr adhan is inside sanctity; it waits until adhan + 30 (this Friday's Dhuhr holds 60).
        let shifted = RoomReminders.habit(id: id, windowStart: day.asr.addingTimeInterval(600), dayKey: "2026-10-09", prayerDays: [day], now: dawn)
        #expect(shifted?.dueAt == day.asr.addingTimeInterval(1800))
        #expect(shifted?.id == "habits.2026-10-09.\(id.uuidString)")
        #expect(RoomReminders.habit(id: id, windowStart: nil, dayKey: "2026-10-09", prayerDays: [day], now: dawn) == nil)
    }

    /// §7.5: the 80% alert fires at 80% of the limit and not below, once per (category, cycle), and leaves sanctity (RP3).
    @Test func limitAlertAtEightyPercentOncePerCategoryCycle() {
        let category = UUID(), cycle = UUID(), next = UUID()
        #expect(RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 1_896, limitMinor: 2_400, dayKey: "2026-10-09", prayerDays: [day], now: dawn) == nil, "79%")
        let at80 = RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 1_920, limitMinor: 2_400, dayKey: "2026-10-09", prayerDays: [day], now: dawn)
        #expect(at80?.id == "mal.alert80.\(cycle.uuidString).\(category.uuidString)")
        #expect(at80?.room == .mal); #expect(at80?.dueAt == dawn.addingTimeInterval(60))
        let fixedZero = RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 100, limitMinor: 0, dayKey: "2026-10-09", prayerDays: [day], now: dawn)
        #expect(fixedZero?.id == at80?.id)
        #expect(fixedZero?.dueAt == dawn.addingTimeInterval(60))
        #expect(RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 0, limitMinor: 0, dayKey: "2026-10-09", prayerDays: [day], now: dawn) == nil)
        #expect(RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 100, limitMinor: nil, dayKey: "2026-10-09", prayerDays: [day], now: dawn) == nil, "No configured limit")
        #expect(RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: Int.max, limitMinor: Int.max, dayKey: "2026-10-09", prayerDays: [day], now: dawn) != nil)
        // A later movement in the same cycle makes the same request; a new cycle makes a new one.
        let again = RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 2_300, limitMinor: 2_400, dayKey: "2026-10-10", prayerDays: [day], now: dawn)
        #expect(again?.id == at80?.id)
        // A later pass keeps the time already planned instead of pushing it another minute on.
        #expect(RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 2_300, limitMinor: 2_400, dayKey: "2026-10-09", prayerDays: [day], now: dawn.addingTimeInterval(30), scheduledAt: dawn.addingTimeInterval(60))?.dueAt == dawn.addingTimeInterval(60))
        #expect(RoomReminders.limit80(categoryID: category, cycleID: next, spentMinor: 2_000, limitMinor: 2_400, dayKey: "2026-11-09", prayerDays: [day], now: dawn)?.id != at80?.id)
        // Crossing 80% during Asr's sanctity waits until adhan + 30 minutes.
        let inSanctity = RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 2_000, limitMinor: 2_400, dayKey: "2026-10-09", prayerDays: [day], now: day.asr.addingTimeInterval(300))
        #expect(inSanctity?.dueAt == day.asr.addingTimeInterval(1800))
        // Two requests for the same pair in one plan: the arbiter keeps one.
        let plan = NotificationArbiter.plan(candidates: [at80!, .init(id: "mal.alert80.dup", room: .mal, dueAt: dawn.addingTimeInterval(120), dayKey: "2026-10-09", categoryCycleKey: at80!.categoryCycleKey)],
                                            prayerDays: [day], now: dawn, timeZone: TimeZone(identifier: "Asia/Riyadh")!)
        #expect(plan.scheduled.filter { $0.room == .mal }.count == 1)
        #expect(RoomReminders.kindLabel(for: at80!.id) == "حدود الصرف")
    }

    @Test func digestNamesKindsNeverContent() {
        #expect(RoomReminders.digestKinds(memberIDs: ["quran.2026-10-09.wird", "qada.2026-10-09", "habits.2026-10-09.\(UUID())"]) == ["الورد", "القضاء", "عادة"])
        #expect(RoomReminders.digestKinds(memberIDs: (0..<11).map { "habits.d.\($0)" }) == ["عادة"])
    }

    @Test func budgetOfFourSendsThreeAndOneDigestThatKnowsItsMembers() {
        // Five room requests on one Madar day, B = 4: the first B − 1 by priority then time, the rest in a digest.
        // Default priority (owner, 4 Nov 2026): Quran, habits, diary, prayer, money, Mihbara — what is lost with time first, so the qada reminder waits in the digest.
        let at = { (minutes: Double) in day.dhuhr.addingTimeInterval(3600 + minutes * 60) }
        let candidates: [NotificationCandidate] = [
            RoomReminders.qada(days: [day], time: .afterFajr, owed: 2, now: dawn)[0],
            .init(id: "quran.2026-10-09.wird", room: .quran, dueAt: at(0), dayKey: "2026-10-09"),
            .init(id: "quran.2026-10-09.late", room: .quran, dueAt: at(10), dayKey: "2026-10-09"),
            .init(id: "habits.2026-10-09.a", room: .habits, dueAt: at(20), dayKey: "2026-10-09"),
            .init(id: "habits.2026-10-09.b", room: .habits, dueAt: at(30), dayKey: "2026-10-09")
        ]
        let plan = NotificationArbiter.plan(candidates: candidates, prayerDays: [day], now: dawn, timeZone: ActivePlace.riyadh.timeZone,
                                            policy: .init(dailyBudget: 4, staleNudgeEnabled: false))
        #expect(plan.scheduled.filter { $0.kind == .reminder }.map(\.id) == ["quran.2026-10-09.wird", "quran.2026-10-09.late", "habits.2026-10-09.a"])
        #expect(plan.scheduled.filter { $0.kind == .digest }.map(\.id) == ["digest.2026-10-09"])
        #expect(plan.digestMembers["digest.2026-10-09"] == ["habits.2026-10-09.b", "qada.2026-10-09"])
    }

    // §7.3: the intention card after Fajr, «في مثل هذا اليوم» after Isha by default; §8 item 8 ids and the notes cap of 2.
    @Test func diaryKindsFallAfterTheirPrayerAndRespectTheNotesCap() {
        let niyya = RoomReminders.diary(.niyya, day: day, time: .afterFajr, prayerDays: [day], now: dawn)
        #expect(niyya == .init(id: "notes.2026-10-09.niyya", room: .notes, dueAt: day.fajr.addingTimeInterval(1800), dayKey: "2026-10-09"))
        let memory = RoomReminders.diary(.onThisDay, day: day, time: .afterIsha, prayerDays: [day], now: dawn)
        #expect(memory?.dueAt == day.isha.addingTimeInterval(1800))
        #expect(RoomReminders.diary(.onThisDay, day: day, time: .off, prayerDays: [day], now: dawn) == nil)
        let letter = RoomReminders.diary(.letter, day: day, time: .afterFajr, prayerDays: [day], now: dawn)!
        #expect(RoomReminders.digestKinds(memberIDs: [niyya!.id, memory!.id, letter.id]) == ["النيّة", "ذكرى", "رسالة"])
        let plan = NotificationArbiter.plan(candidates: [niyya!, memory!, letter], prayerDays: [day], now: dawn, timeZone: ActivePlace.riyadh.timeZone,
                                            policy: .init(dailyBudget: 10, staleNudgeEnabled: false, notesDailyCap: 2))
        #expect(plan.scheduled.map(\.id).sorted() == [letter.id, niyya!.id].sorted())
        #expect(plan.droppedIDs == [memory!.id])
        let none = NotificationArbiter.plan(candidates: [niyya!], prayerDays: [day], now: dawn, timeZone: ActivePlace.riyadh.timeZone,
                                            policy: .init(staleNudgeEnabled: false, notesDailyCap: 0))
        #expect(none.scheduled.isEmpty)
    }
}
