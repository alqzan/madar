import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarInbox
import MadarCommands

/// Isolated app-consumer proof. This is the only process that opens its synthetic store.
@main struct Consumer {
    @MainActor static func main() async throws {
        let args = CommandLine.arguments
        guard args.count == 3, let generationID = UUID(uuidString: args[2]) else { throw InboxError.malformedRecord }
        let root = URL(fileURLWithPath: args[1], isDirectory: true)
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Store"))
        let inbox = PendingInbox(directory: root.appending(path: "PendingInbox"))
        let adapter = DurableCommandAdapter(container: container, lockDirectory: root, generationProvider: { generationID })
        // Prayer logs need a tracking start on or before the prayer day (salah.trackingStart); the proof stages one in its own store.
        let setup = ModelContext(container)
        _ = try SettingsStore(context: setup).stage(["salah.trackingStart": .object(["dayKey": .string("2026-10-03"), "edits": .number(0)])], now: Date())
        try setup.save()
        var refreshes = 0
        let drainer = InboxDrainer(inbox: inbox, bus: CommandBus(adapter: adapter), generation: { .init(generationID: generationID, acceptsUnstampedDeliveries: false) }, hasReceipt: { try adapter.hasReceipt(commandID: $0) }, refresh: {
            // A synthetic refresh checkpoint; production AppSession performs snapshots/history.
            refreshes += 1
            try Data("refreshed".utf8).write(to: root.appending(path: "RefreshCheckpoint"), options: .atomic)
        })
        try await drainer.drain()
        let context = ModelContext(container)
        let rows = try context.fetch(FetchDescriptor<PrayerLog>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
        let receipts = try context.fetch(FetchDescriptor<MadarData.CommandReceipt>())
        let statuses = receipts.map(\.status).sorted()
        let result: [String: Any] = ["rows": rows.count, "receipts": receipts.count, "statuses": statuses, "refreshes": refreshes, "unacknowledged": try inbox.unacknowledgedCommandIDs().count]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys]), as: UTF8.self))
    }
}
