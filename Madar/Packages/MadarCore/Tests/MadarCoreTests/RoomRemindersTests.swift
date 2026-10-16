import Foundation
import Testing
@testable import MadarCore

/// Expected values come from §8 item 8 (sanctity = adhan + 30 min, digest names kinds, B − 1 + digest),
/// §7.1 (habit reminder at window start, none without a window) and the salah.qadaReminder options.
@Suite struct RoomRemindersTests {
    let day = try! #require(PrayerTimesEngine.calculate(day: GregorianDay("2026-10-09"), place: .riyadh))
    var dawn: Date { day.fajr.addingTimeInterval(-3 * 3600) }

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
        #expect(RoomReminders.limit80(categoryID: category, cycleID: cycle, spentMinor: 100, limitMinor: 0, dayKey: "2026-10-09", prayerDays: [day], now: dawn) == nil, "No limit, no alert")
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
        #expect(plan.scheduled.filter { $0.kind == .reminder }.map(\.id) == ["qada.2026-10-09", "quran.2026-10-09.wird", "quran.2026-10-09.late"])
        #expect(plan.scheduled.filter { $0.kind == .digest }.map(\.id) == ["digest.2026-10-09"])
        #expect(plan.digestMembers["digest.2026-10-09"] == ["habits.2026-10-09.a", "habits.2026-10-09.b"])
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
