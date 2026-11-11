import Foundation
import Testing
import SwiftData
import MadarData
import MadarMoney
@testable import MadarCommands

/// B1-7: the collision check reads only the rows with the same keys. An existing key is still refused (deleted rows too);
/// unrelated keys among thousands of others write normally.
@MainActor struct MoneyAllocationWriteTests {
    private func row(_ key: String, amount: Int = 100) -> AllocationRow {
        .init(groupID: key, target: .daily, amountMinor: amount, kind: .adjust, idempotencyKey: key)
    }
    @Test func existingKeyIsRefusedAndNewKeysWriteAmongManyOthers() throws {
        let context = ModelContext(try MadarContainerFactory.makeInMemory()); context.autosaveEnabled = false
        for index in 0..<300 { let old = Allocation(); old.idempotencyKey = "old:\(index)"; context.insert(old) }
        let deleted = Allocation(); deleted.idempotencyKey = "gone"; deleted.deletedAt = Date(); context.insert(deleted)
        try context.save()
        try MoneyMutationHandler.writeAllocations([row("fresh:1"), row("fresh:2")], context: context, now: Date(), writer: "test")
        try context.save()
        #expect(try context.fetch(FetchDescriptor<Allocation>()).count == 303)
        #expect(throws: MoneyCommandError.invalidReference) {
            try MoneyMutationHandler.writeAllocations([row("fresh:3"), row("old:42")], context: context, now: Date(), writer: "test")
        }
        #expect(throws: MoneyCommandError.invalidReference) {
            try MoneyMutationHandler.writeAllocations([row("gone")], context: context, now: Date(), writer: "test")
        }
        try MoneyMutationHandler.writeAllocations([], context: context, now: Date(), writer: "test")
    }
}
