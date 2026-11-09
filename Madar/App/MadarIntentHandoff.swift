import Foundation
import MadarCore
import MadarData
import MadarPrayer
import MadarCommands
import MadarMoney
import SwiftData

/// A Siri/Shortcuts request that needs the app's own command path (RA2) and its lock gate.
/// It never travels through a public URL, so no link or webpage can write a diary line.
enum MadarIntentRequest: Equatable, Sendable {
    case capture(text: String, id: UUID)
    case diaryLine(text: String, day: String, id: UUID)
    /// A habit whose snapshot period went stale: only the app can resolve today's period.
    case completeHabit(habitID: UUID, id: UUID)
}

/// Holds foreground intent requests until the session has loaded and the diary is open.
/// A held request keeps its command ID, so a retry can never write the line twice.
@MainActor final class MadarIntentHandoff {
    static let shared = MadarIntentHandoff()
    private var pending: [MadarIntentRequest] = []
    private var handler: ((MadarIntentRequest) async -> Bool)?
    private var flushing = false
    private var flushWaiters: [CheckedContinuation<Void, Never>] = []
    /// Requests that ran and failed, with the app's own message, so the Siri dialog never says «سُجّلت» for them.
    private var failures: [(MadarIntentRequest, String)] = []
    func fail(_ request: MadarIntentRequest, _ message: String) { failures.append((request, message)); failures = Array(failures.suffix(20)) }
    /// The failure message for a request that ran, removed once read.
    func takeFailure(_ request: MadarIntentRequest) -> String? {
        guard let index = failures.firstIndex(where: { $0.0 == request }) else { return nil }
        return failures.remove(at: index).1
    }

    /// Returns false while the request is held (diary locked or Madar still loading), so the
    /// Siri dialog never claims a line was added before it was.
    @discardableResult
    func submit(_ request: MadarIntentRequest) async -> Bool {
        pending.append(request)
        await flush()
        return !pending.contains(request)
    }
    func attach(_ handler: @escaping (MadarIntentRequest) async -> Bool) async {
        self.handler = handler
        await flush()
    }
    /// Runs on attach, on every return to the foreground and when a lock opens.
    func flush() async {
        guard let handler else { return }
        if flushing {
            await withCheckedContinuation { flushWaiters.append($0) }
            return
        }
        flushing = true
        defer {
            flushing = false
            let waiters = flushWaiters
            flushWaiters.removeAll()
            waiters.forEach { $0.resume() }
        }
        var held: [MadarIntentRequest] = []
        while !pending.isEmpty {
            let request = pending.removeFirst()
            if !(await handler(request)) { held.append(request) }
        }
        pending = held
    }
}

extension AppSession {
    /// Returns false only when the request must wait (diary locked); every other outcome is final
    /// and reported in the room it belongs to.
    func handleIntentRequest(_ request: MadarIntentRequest) async -> Bool {
        let earlier = errorMessage; errorMessage = nil
        let done = await performIntentRequest(request)
        if done, let message = errorMessage { MadarIntentHandoff.shared.fail(request, message) }
        if errorMessage == nil { errorMessage = earlier }
        return done
    }
    private func performIntentRequest(_ request: MadarIntentRequest) async -> Bool {
        switch request {
        case .diaryLine(let text, let day, let id):
            return await addDiaryLineFromIntent(text: text, day: day, id: id)
        case .completeHabit(let habitID, let id):
            habitRouteID = habitID; selectedTab = "foundation"; habitsOpen = true
            let reading = (try? HabitRepository(context: ModelContext(container)).readings(at: prayerNow()))?.first { $0.id == habitID }
            guard let current = reading?.summary.current else { errorMessage = "لم تعد هذه العادة متاحة."; return true }
            do {
                try await executeDiaryCommand("habit.complete", payload: ["id": .string(habitID.uuidString), "delta": .number(current.rule.measure == .duration ? 15 : 1)], id: id)
                clearRecoveredMaintenanceError()
            } catch BackupOperationError.busy { return false }
            catch { errorMessage = madarUserMessage(error) }
            return true
        case .capture(let text, let id):
            switch CaptureRouter.route(text) {
            case .moneyExpense(let amount, let merchant):
                guard let exp = CurrencyExponents.specified.exponent(string("core.currency")), let n = MoneyAmountInput.minor(amount, exponent: exp), n > 0 else { errorMessage = "راجع مبلغ المصروف وعملته."; return true }
                presentMoneyExpenseSeed(.init(id: id, amount: amount, merchant: merchant, homeCurrency: true)); return true
            case .empty: errorMessage = "لم يصل نص لالتقاطه."; return true
            case .tooLong: errorMessage = "النص أطول من سطر واحد في صفحة اليوم (٢٠٠٠ حرف)."; return true
            case .diaryLine(let line, let kind):
                return await addDiaryLineFromIntent(text: kind == .idea ? "فكرة: " + line : line, day: "today", id: id)
            // FB-39: the Mihbara notebook has no entry point any more, so an idea lands on today's diary page where the owner can see it.
            case .mihbaraIdea(let idea): return await addDiaryLineFromIntent(text: "فكرة: " + idea, day: "today", id: id)
            case .logPrayer(let prayer, let status, let shortened, let fridayKind):
                return logPrayerFromCapture(prayer, status: status, shortened: shortened, fridayKind: fridayKind)
            case .choosePrayerStatus(let prayer, _):
                selectedTab = "prayer"; prayerLogRequest = prayer; return true
            }
        }
    }

    private func addDiaryLineFromIntent(text: String, day: String, id: UUID) async -> Bool {
        // Land on the same day the command will write; while the diary is locked its gate shows instead and the line waits.
        if day == "yesterday",
           let today = try? DiaryLineRenderer.today(context: ModelContext(container), now: prayerNow()) {
            open(URL(string: "madar://notes/day/\(today.adding(days: -1).description)")!)
        } else {
            open(URL(string: "madar://notes/today")!)
        }
        guard lockController?.canPresent(.notes) ?? protectedDataAuthorized else { return false }
        do {
            try await executeDiaryCommand("diary.appendLine", payload: ["text": .string(text), "day": .string(day)], id: id)
            clearRecoveredMaintenanceError()
        } catch BackupOperationError.busy { return false }
        catch { errorMessage = "لم يُضف السطر. \(madarUserMessage(error))" }
        return true
    }

    /// The prayer day comes from the same snapshot as the prayer home (Fajr to the next Fajr).
    /// Friday Dhuhr said as «الظهر» is recorded as Dhuhr, never silently as Jumu'ah.
    private func logPrayerFromCapture(_ prayer: Prayer, status: String, shortened: Bool?, fridayKind: FridayPrayerKind?) -> Bool {
        selectedTab = "prayer"
        guard let snapshot = try? prayerSnapshot(at: prayerNow()),
              let cell = snapshot.today.cells.first(where: { $0.reference.prayer == prayer }) else {
            errorMessage = "تعذّر تحديد يوم الصلاة. افتح الصلاة وسجّلها من قوسها."; return true
        }
        if fridayKind == .jumuah, !cell.isFriday { errorMessage = "اليوم ليس جمعة؛ سجّل الظهر من قوسها."; return true }
        var payload: [String: MadarCore.JSONValue] = [
            "dayKey": .string(cell.reference.day.description), "prayer": .string(prayer.rawValue), "status": .string(status)
        ]
        if let shortened { payload["shortened"] = .bool(shortened) }
        if prayer == .dhuhr, cell.isFriday { payload["fridayKind"] = .string((fridayKind ?? .dhuhr).rawValue) }
        return logCapturedPrayer(payload: .object(payload), undoMessage: "سُجّلت " + Self.prayerName(prayer, friday: payload["fridayKind"] == .string("jumuah")) + (status == "jamaah" ? " جماعة" : " منفردًا") + "")
    }

    static func prayerName(_ prayer: Prayer, friday: Bool) -> String {
        if friday { return "الجمعة" }
        return [.fajr: "الفجر", .dhuhr: "الظهر", .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء"][prayer] ?? ""
    }
}
