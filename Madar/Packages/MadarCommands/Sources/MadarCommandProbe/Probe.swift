import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarCommands

/// Isolated synthetic test tool. Never points at an App Group or the owner's data.
@main struct Probe {
    @MainActor static func main() async throws {
        let arguments = CommandLine.arguments
        guard arguments.count >= 3 else { throw DataError.invalidValue("arguments") }
        let directory = URL(fileURLWithPath: arguments[2], isDirectory: true)
        let container = try MadarContainerFactory.makeLocal(at: directory)
        switch arguments[1] {
        case "prepare": print("prepared")
        case "inspect":
            let context = ModelContext(container)
            let rows = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.mergedInto == nil && $0.deletedAt == nil }
            let receipts = try context.fetchCount(FetchDescriptor<MadarData.CommandReceipt>())
            print("{\"rows\":\(rows.count),\"receipts\":\(receipts)}")
        case "write":
            guard arguments.count == 6, let id = UUID(uuidString: arguments[3]), let source = CommandSource(rawValue: arguments[4]) else { throw DataError.invalidValue("arguments") }
            let gate = URL(fileURLWithPath: arguments[5])
            try Data().write(to: gate.appendingPathExtension(id.uuidString))
            while !FileManager.default.fileExists(atPath: gate.path) { try await Task.sleep(for: .milliseconds(10)) }
            let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: directory))
            let command = CommandEnvelope(commandID: id, name: "prayer.log", payload: .object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string("jamaah")]), source: source)
            let result = try await bus.execute(command)
            print(result.status.rawValue)
        default: throw DataError.invalidValue("action")
        }
    }
}
