import Foundation
import SwiftData
import MadarCore
import MadarData
import MadarMoney
import MadarCommands

struct MoneyRuleCategory: Identifiable, Equatable {
    var id: UUID
    var name: String
    var icon: String
    var merchants: Int
    var times: Int
}

extension AppMoneyService {
    func categories() throws -> [MoneyRuleCategory] {
        try ModelContext(app.container).fetch(FetchDescriptor<MadarData.Category>()).filter { $0.deletedAt == nil && $0.mergedInto == nil }
            .sorted { $0.order == $1.order ? $0.name < $1.name : $0.order < $1.order }
            .map { .init(id: $0.id, name: $0.name, icon: $0.icon, merchants: 0, times: 0) }
    }

}
