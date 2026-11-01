import SwiftUI
import MadarDesign

struct MoneyHomeDoors: View {
    let accountsFact: String?
    let reconcileFact: String?
    let goalFact: String?
    let cardsFact: String?
    let zakatFact: String?
    let openLog: () -> Void
    let openAnalysis: () -> Void
    let openCards: () -> Void
    let openAccounts: () -> Void
    let openReconcile: () -> Void
    let openGoal: () -> Void
    let openCashback: () -> Void
    let openZakat: () -> Void
    let openSettings: () -> Void

    @Environment(\.roomTheme) private var theme

    var body: some View {
        VStack(spacing: 10) {
            // Not lazy: eight drawers are cheap, and every door must exist before it scrolls into view.
            Grid(horizontalSpacing: 10, verticalSpacing: 10) {
                GridRow {
                    drawer("السجل", "book.pages", "money-log-open", action: openLog)
                    drawer("التحليل", "chart.bar.xaxis", "money-analysis-open", action: openAnalysis)
                }
                GridRow {
                    drawer("البطاقات", "creditcard", "money-cards-open", fact: cardsFact, action: openCards)
                    drawer("الحسابات", "tree", "money-accounts-open", fact: accountsFact, action: openAccounts)
                }
                GridRow {
                    drawer("المطابقة مع البنك", "checkmark.seal", "money-reconcile-open", fact: reconcileFact, action: openReconcile)
                    drawer("جهّز لشيء قادم", "sparkles", "money-goal-open", fact: goalFact, action: openGoal)
                }
                GridRow {
                    drawer("الاسترداد النقدي", "drop", "money-cashback-open", action: openCashback)
                    drawer("الزكاة", "scalemass", "money-zakat-open", fact: zakatFact, action: openZakat)
                }
            }
            Button(action: openSettings) {
                Label("إعدادات المال", systemImage: "slider.horizontal.3")
                    .font(MadarTypography.caption())
                    .foregroundStyle(theme.secondaryInk)
                    .frame(minHeight: 44)
            }
            .buttonStyle(.madarPlain)
            .accessibilityIdentifier("money-settings-open")
        }
        .padding(.top, 8)
    }

    /// OR-22: light chips keep the room's drawers compact, legible, and easy to reach.
    private func drawer(_ title: String, _ symbol: String, _ id: String, fact: String? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 16, weight: .regular))
                    .foregroundStyle(theme.color("reserveText"))
                    .frame(width: 22)
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(MadarTypography.body()).lineLimit(1).minimumScaleFactor(0.8)
                    if let fact {
                        Text(fact).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            .lineLimit(1).minimumScaleFactor(0.85)
                    }
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
            .background(theme.surface.opacity(0.7), in: .rect(cornerRadius: 12))
            .overlay { RoundedRectangle(cornerRadius: 12).stroke(theme.color("reserveText").opacity(0.25), lineWidth: 0.8) }
            .contentShape(.rect(cornerRadius: 12))
        }
        .buttonStyle(.madarPlain)
        .accessibilityLabel(title)
        .accessibilityValue(fact ?? "")
        .accessibilityIdentifier(id)
    }
}
