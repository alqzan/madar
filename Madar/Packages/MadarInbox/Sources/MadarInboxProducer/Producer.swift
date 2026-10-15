import Foundation
import MadarCore
import MadarInbox

/// Synthetic RA2 producer. Its target has no dependency on SwiftData or MadarData.
@main struct Producer {
    static func main() throws {
        let args = CommandLine.arguments
        if args.count == 3, args[1] == "budget-seed" {
            let now = ISO8601DateFormatter().date(from: "2026-10-09T04:40:00+03:00")!
            let day = try GregorianDay("2026-10-09")
            let days = (0..<3).compactMap { PrayerTimesEngine.calculate(day: day.adding(days: $0), place: .riyadh) }
            try NotificationBudgetStore(directory: URL(fileURLWithPath: args[2])).publish(.init(generatedAt: now, validUntil: now.addingTimeInterval(24*3600),
                activityEnabled: true, remindersEnabled: true, dailyBudget: 4, quietFromMinutes: nil, dayBoundary: .fajr, prayerDays: days))
            return
        }
        if args.count == 4, ["budget-reserve", "budget-activity"].contains(args[1]) {
            let now = ISO8601DateFormatter().date(from: "2026-10-09T04:40:00+03:00")!
            let budget = NotificationBudgetStore(directory: URL(fileURLWithPath: args[2]))
            do {
                if args[1] == "budget-activity" { _ = try budget.reservePrayerActivity(id: args[3], now: now) }
                else { try budget.reserve(.init(id: args[3], dayKey: "2026-10-09", scheduledAt: now.addingTimeInterval(6*3600)), now: now) }
                print("reserved")
            } catch NotificationBudgetError.full { print("full") }
            catch NotificationBudgetError.duplicate { print("duplicate") }
            return
        }
        guard args.count == 6, let commandID = UUID(uuidString: args[2]),
              let source = CommandSource(rawValue: args[3]), let generationID = UUID(uuidString: args[4]),
              let deliveryID = UUID(uuidString: args[5]) else { throw InboxError.malformedRecord }
        let inbox = PendingInbox(directory: URL(fileURLWithPath: args[1], isDirectory: true))
        let command = CommandEnvelope(commandID: commandID, name: "prayer.log", payload: .object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string("jamaah")]), source: source)
        let ticket = try inbox.enqueue(.init(deliveryID: deliveryID, expectedGenerationID: generationID, command: command))
        print("enqueued \(ticket.commandID.uuidString)")
    }
}
