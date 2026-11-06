import SwiftUI
import Foundation

struct MoneyExpenseSeed: Identifiable {
    var id = UUID()
    var amount = ""
    var merchant = ""
    var method: String?
    var homeCurrency = false
}
struct MoneyQuickExpense: View {
    let app: AppSession
    let seed: MoneyExpenseSeed
    @State private var revealed = false
    var body: some View { NavigationStack { MoneyExpenseView(app: app, revealed: $revealed, seed: seed) }.hidesMoneyInBackground($revealed) }
}
