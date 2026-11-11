import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney

/// Home of the money room: «مستحقات قادمة» and the quiet balance-difference rows. Hidden entirely when there is nothing to say.
struct MoneyBankInsightsSection: View {
    let app: AppSession
    let insights: MoneyBankInsights
    let visible: Bool
    var settle: (MoneyBankMismatch, ReconcileName?) -> Void
    var dismissDue: (MoneyUpcomingDue) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var settling: MoneyBankMismatch?
    private var service: AppMoneyService { .init(app: app) }
    private func amount(_ minor: Int, currency: String? = nil) -> String { visible ? service.amount(minor, currency: currency) : "•••" }

    var body: some View {
        if !insights.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                ForEach(insights.mismatches) { mismatch in mismatchRow(mismatch) }
                if !insights.dues.isEmpty { dues }
            }.padding(.top, 8).accessibilityElement(children: .contain).accessibilityIdentifier("money-bank-insights")
        }
    }

    private func mismatchRow(_ item: MoneyBankMismatch) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(item.accountName).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(figure: MoneyBankInsightsCopy.mismatchSentence(bank: amount(item.observedMinor), book: amount(item.expectedMinor),
                                                                difference: amount(abs(item.differenceMinor))))
                .font(MadarTypography.caption()).fixedSize(horizontal: false, vertical: true)
                .accessibilityIdentifier("money-bank-mismatch-text-" + item.accountID.uuidString)
            if item.isSettleable {
                Button { settling = item } label: {
                    Text("سوِّ الفرق").font(MadarTypography.caption()).foregroundStyle(theme.color("reserveText")).padding(.horizontal, 14)
                        .frame(minHeight: 44).overlay { Capsule().stroke(theme.color("reserveText"), lineWidth: 1).padding(.vertical, 4) }.contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-bank-settle-" + item.accountID.uuidString)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading).padding(.vertical, 8)
        .overlay(alignment: .top) { DoubleRule().stroke(theme.line, lineWidth: 0.7).frame(height: 3) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("money-bank-mismatch-" + item.accountID.uuidString)
        .confirmationDialog("سمِّ الفرق", isPresented: Binding(get: { settling?.accountID == item.accountID }, set: { if !$0 { settling = nil } }), titleVisibility: .visible) {
            ForEach(item.names, id: \.self) { name in
                Button(MoneyBankInsightsCopy.title(name)) { settle(item, name); settling = nil }
            }
            Button("إلغاء", role: .cancel) { settling = nil }
        } message: {
            Text(figure: (item.differenceMinor < 0 ? "ينقص " : "يزيد ") + amount(abs(item.differenceMinor)) + " عن رصيد البنك. ما يُختار يُسجَّل به الفرق.")
        }
    }

    private var dues: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack { Text("مستحقات قادمة").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("bills")); Rectangle().fill(theme.line).frame(height: 1) }
                .frame(minHeight: 36)
            ForEach(insights.dues) { due in DueLine(app: app, due: due, visible: visible, dismiss: { dismissDue(due) }) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("money-dues")
    }
}

/// One due as a single line: payee, amount, due date in both calendars and how near it is. Long-press removes it (a custom swipe was dropped so vertical scrolling is never contested).
private struct DueLine: View {
    let app: AppSession
    let due: MoneyUpcomingDue
    let visible: Bool
    var dismiss: () -> Void
    @Environment(\.roomTheme) private var theme
    private var service: AppMoneyService { .init(app: app) }
    private var phrase: String { MoneyBankInsightsCopy.duePhrase(daysUntil: due.daysUntil, digits: service.digits) }
    private var late: Bool { (due.daysUntil ?? 0) < 0 }
    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(due.payee).font(MadarTypography.body()).lineLimit(1)
                Text(phrase).font(MadarTypography.fine()).foregroundStyle(late ? theme.color("dueText") : theme.secondaryInk)
            }
            Spacer(minLength: 8)
            VStack(alignment: .trailing, spacing: 2) {
                Text(figure: visible ? service.amount(due.amountMinor, currency: due.currency) : "•••").font(MadarTypography.cardTitle()).lineLimit(1).minimumScaleFactor(0.7)
                if let day = due.dueDay { MadarDateLabel(app.dateLabels(day, compact: true), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()) }
            }
        }
        .padding(.vertical, 8).frame(minHeight: 48).contentShape(Rectangle())
        .contextMenu { Button("أزله من القائمة", role: .destructive, action: dismiss) }
        .accessibilityAction(named: "أزله من القائمة", dismiss)
        .accessibilityElement(children: .combine).accessibilityIdentifier("money-due-" + due.id.uuidString)
    }
}

/// «بطاقة تنتهي بـ‹tail› من ‹sender› — لأي حساب تتبع؟» in the bank-messages page.
struct MoneyTailQuestionCard: View {
    let question: MoneyTailQuestion
    let digits: MadarNumberFormatter
    var answer: (MoneyTailQuestion.Candidate, MoneyTailKind) -> Void
    var skip: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var kind: MoneyTailKind = .card
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("بطاقة تنتهي بـ" + digits.localized(question.tail) + " من " + question.sender + " — لأي حساب تتبع؟")
                .font(MadarTypography.cardTitle()).fixedSize(horizontal: false, vertical: true)
            Picker("النوع", selection: $kind) { ForEach(MoneyTailKind.allCases) { Text($0.title).tag($0) } }
                .pickerStyle(.segmented).accessibilityIdentifier("money-tail-kind")
            ForEach(question.candidates) { candidate in
                Button { answer(candidate, kind) } label: {
                    HStack(spacing: 8) {
                        Text(candidate.name).font(MadarTypography.body())
                        if !candidate.bank.isEmpty { Text(candidate.bank).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                        Spacer(minLength: 0)
                    }.frame(minHeight: 44).contentShape(Rectangle())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("money-tail-candidate-" + candidate.name)
            }
            Button(action: skip) { Text("ليست لي الآن").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).frame(minHeight: 44).contentShape(Rectangle()) }
                .buttonStyle(.madarPlain).accessibilityIdentifier("money-tail-skip")
        }.padding(14).background(theme.surface).overlay { TicketEdge().stroke(theme.color("reserveText"), lineWidth: 1) }
            .accessibilityElement(children: .contain).accessibilityIdentifier("money-tail-question")
    }
}
