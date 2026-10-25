import Foundation
import Testing
import SwiftData
import MadarCore
import MadarData
@testable import MadarCommands

/// §7.1 B03: a user day stores its rule; edit and delete undo back to the previous rule.
@MainActor struct BahwUpcomingPersistenceTests {
    private func date(_ value: String) -> Date { ISO8601DateFormatter().date(from: value)! }
    @Test func userDaySavesEditsDeletesAndUndoes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwUpcoming-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func run(_ name: String, _ payload: [String: MadarCore.JSONValue], at now: Date, id: UUID = UUID()) async throws -> CommandOutcome {
            try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
        }
        func row() throws -> UpcomingDay { try #require(ModelContext(container).fetch(FetchDescriptor<UpcomingDay>()).first) }
        let now = date("2026-10-15T20:00:00+03:00"), day = UUID(), edit = UUID(), delete = UUID()
        let base: [String: MadarCore.JSONValue] = ["id": .string(day.uuidString), "title": .string("ذكرى زواجنا"), "calendar": .string("greg"), "month": .number(11), "day": .number(3), "repeats": .string("yearly"), "countFromDayKey": .string("2026-10-15")]
        #expect(try await run("bahw.saveUpcomingDay", base, at: now).status == .applied)
        #expect(try row().title == "ذكرى زواجنا"); #expect(try row().month == 11)
        // A one-off day needs its year; a Hijri day 31 is refused.
        #expect(try await run("bahw.saveUpcomingDay", base.merging(["id": .string(UUID().uuidString), "repeats": .string("none")]) { $1 }, at: now).status != .applied)
        #expect(try await run("bahw.saveUpcomingDay", base.merging(["id": .string(UUID().uuidString), "calendar": .string("hijri"), "day": .number(31)]) { $1 }, at: now).status != .applied)
        #expect(try ModelContext(container).fetch(FetchDescriptor<UpcomingDay>()).count == 1)
        _ = try await run("bahw.saveUpcomingDay", base.merging(["month": .number(12)]) { $1 }, at: now.addingTimeInterval(1), id: edit)
        #expect(try row().month == 12)
        _ = try await run("system.undo", ["undoToken": .string(edit.uuidString)], at: now.addingTimeInterval(2))
        #expect(try row().month == 11)
        _ = try await run("bahw.deleteUpcomingDay", ["id": .string(day.uuidString)], at: now.addingTimeInterval(3), id: delete)
        #expect(try row().deletedAt != nil)
        _ = try await run("system.undo", ["undoToken": .string(delete.uuidString)], at: now.addingTimeInterval(4))
        #expect(try row().deletedAt == nil); #expect(try row().title == "ذكرى زواجنا")
    }
    /// Owner, 25 Oct: `countUpAfter` is stored for one-time days only, defaults off, and undo restores it.
    @Test func oneTimeDayKeepsCountingAfterItAndUndoRestoresTheOption() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "BahwCountUp-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data"))
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func run(_ name: String, _ payload: [String: MadarCore.JSONValue], at now: Date, id: UUID = UUID()) async throws -> CommandOutcome {
            try await bus.execute(.init(commandID: id, name: name, payload: .object(payload), issuedAt: now), now: now)
        }
        func rows() throws -> [UpcomingDay] { try ModelContext(container).fetch(FetchDescriptor<UpcomingDay>()) }
        let now = date("2026-10-25T20:00:00+03:00"), day = UUID(), edit = UUID()
        let base: [String: MadarCore.JSONValue] = ["id": .string(day.uuidString), "title": .string("أول يوم في العمل"), "calendar": .string("greg"), "year": .number(2026),
                                                   "month": .number(9), "day": .number(1), "repeats": .string("none"), "countFromDayKey": .string("2026-08-01")]
        #expect(try await run("bahw.saveUpcomingDay", base, at: now).status == .applied)
        #expect(try rows().first?.countUpAfter == false)
        // A repeating day has a next occurrence, so it never counts up; a non-boolean flag is refused.
        #expect(try await run("bahw.saveUpcomingDay", base.merging(["id": .string(UUID().uuidString), "repeats": .string("yearly"), "countUpAfter": .bool(true)]) { $1 }, at: now).status != .applied)
        #expect(try await run("bahw.saveUpcomingDay", base.merging(["id": .string(UUID().uuidString), "countUpAfter": .string("yes")]) { $1 }, at: now).status != .applied)
        #expect(try rows().count == 1)
        _ = try await run("bahw.saveUpcomingDay", base.merging(["countUpAfter": .bool(true)]) { $1 }, at: now.addingTimeInterval(1), id: edit)
        #expect(try rows().first?.countUpAfter == true)
        _ = try await run("system.undo", ["undoToken": .string(edit.uuidString)], at: now.addingTimeInterval(2))
        #expect(try rows().first?.countUpAfter == false)
    }
}
