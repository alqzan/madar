import Foundation
import MadarCore
import MadarInbox

/// Synthetic RA2 producer. Its target has no dependency on SwiftData or MadarData.
@main struct Producer {
    static func main() throws {
        let args = CommandLine.arguments
        guard args.count == 6, let commandID = UUID(uuidString: args[2]),
              let source = CommandSource(rawValue: args[3]), let generationID = UUID(uuidString: args[4]),
              let deliveryID = UUID(uuidString: args[5]) else { throw InboxError.malformedRecord }
        let inbox = PendingInbox(directory: URL(fileURLWithPath: args[1], isDirectory: true))
        let command = CommandEnvelope(commandID: commandID, name: "prayer.log", payload: .object(["dayKey": .string("2026-10-10"), "prayer": .string("fajr"), "status": .string("jamaah")]), source: source)
        let ticket = try inbox.enqueue(.init(deliveryID: deliveryID, expectedGenerationID: generationID, command: command))
        print("enqueued \(ticket.commandID.uuidString)")
    }
}
