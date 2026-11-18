import Foundation
import SwiftData
import Testing
import MadarCore
import MadarData
@testable import MadarCommands

@MainActor struct PrayerRetiredTests {
    @Test func productionAdapterRejectsPrayerLogFromEverySource() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "PrayerRetired-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let container = try MadarContainerFactory.makeLocal(at: root)
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for source in [CommandSource.app, .widget, .control, .siri, .shortcut, .notification, .spotlight, .system] {
            let command = CommandEnvelope(name: "prayer.log", payload: .object(["dayKey": .string("2026-11-18"), "prayer": .string("fajr"), "status": .string("jamaah")]), source: source, issuedAt: now)
            let result = try await bus.execute(command, now: now)
            #expect(result.status == .rejected, "source \(source)")
        }
        #expect(try ModelContext(container).fetchCount(FetchDescriptor<PrayerLog>()) == 0)
    }
}
