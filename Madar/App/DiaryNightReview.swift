import SwiftUI
import MadarCore
import MadarDesign

/// One plain fact the day already recorded, read from the room that owns it. Nothing here is invented.
struct DiaryReviewFact: Identifiable, Equatable {
    let id: String
    let text: String
}

enum DiaryNightReviewFacts {
    /// The page's automatic lines are the owning rooms' own records (prayers, Quran, habits), so they are summarised, not recounted.
    static func facts(page: DiaryDisplayDay, intention: DiaryIntention?, spentToday: String?, digits: MadarNumberFormatter) -> [DiaryReviewFact] {
        var result: [DiaryReviewFact] = []
        let prayers = page.lines.filter { $0.kind == "salah" }.count
        if prayers > 0 {
            let text = prayers == 1 ? "سجّلت صلاة واحدة" : prayers == 2 ? "سجّلت صلاتين" : prayers <= 10 ? "سجّلت " + digits.string(prayers) + " صلوات" : "سجّلت " + digits.string(prayers) + " صلاة"
            result.append(.init(id: "salah", text: text))
        }
        for (kind, prefix) in [("quran", ""), ("habits", "")] {
            let texts = page.lines.filter { $0.kind == kind }.map(\.text)
            if !texts.isEmpty { result.append(.init(id: kind, text: prefix + MadarInlineText.joined(texts))) }
        }
        if let spentToday { result.append(.init(id: "mal", text: "صرفت اليوم " + spentToday)) }
        if let intention {
            var text = "نيّتك: " + intention.text
            if let r = intention.result?.trimmingCharacters(in: .whitespacesAndNewlines), !r.isEmpty { text += "، وكانت نتيجتها: " + r }
            result.append(.init(id: "niyya", text: text))
        }
        return result
    }
}

/// «محاسبة اليوم»: only when summoned. The day's facts, one gentle question from the bank, and a field whose answer becomes a normal line.
struct DiaryNightReviewView: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    let page: DiaryDisplayDay?
    let intention: DiaryIntention?
    let saved: () -> Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var facts: [DiaryReviewFact] = []
    @State private var question = ""
    @State private var answer = ""
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    private var service: AppDiaryService { .init(app: app) }
    private var canSave: Bool { !answer.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !saving }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Text(service.diaryDates(day)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if facts.isEmpty {
                        Text("لا شيء مسجّل في الغرف اليوم بعد.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text"))
                            .accessibilityIdentifier("diary-review-empty")
                    } else {
                        VStack(alignment: .leading, spacing: 10) {
                            ForEach(facts) { fact in
                                Text(fact.text).font(DiaryType.writing).frame(maxWidth: .infinity, alignment: .leading)
                                    .accessibilityIdentifier("diary-review-fact-" + fact.id)
                            }
                        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-review-facts")
                    }
                    Divider().overlay(theme.line)
                    Text(question).font(DiaryType.heading).frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityIdentifier("diary-review-question")
                    TextField("اكتب ما يخطر لك", text: $answer, axis: .vertical).lineLimit(3...10)
                        .font(DiaryType.writing).focused($focused).padding(14)
                        .background(theme.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line) }
                        .accessibilityIdentifier("diary-review-field")
                    if let failure { Text(failure).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                    Button { Task { await save() } } label: {
                        Text("أضفه إلى صفحة اليوم").font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 48)
                            .foregroundStyle(theme.onAccent).background(canSave ? theme.accentFill : theme.accentFill.opacity(0.35), in: .capsule)
                    }.buttonStyle(.madarPlain).disabled(!canSave).accessibilityIdentifier("diary-review-save")
                }.padding(20).frame(maxWidth: 640).frame(maxWidth: .infinity)
            }
            .scrollDismissesKeyboard(.interactively)
            .background(theme.background).foregroundStyle(theme.ink)
            .navigationTitle("محاسبة اليوم").navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button("تمّ") { dismiss() }.accessibilityIdentifier("diary-review-close")
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
        }
        .task {
            let seed = day.year * 372 + day.month * 31 + day.day
            let bank = DiaryQuestionBank.questions(.reflective)
            question = DiaryQuestionBank.selection(group: .reflective, modelIndices: nil, seed: seed).first.map { bank[$0].arabic } ?? bank[0].arabic
            var spent: String?
            let money = AppMoneyService(app: app)
            if let reading = try? money.load(at: service.clock()), reading.unratedAccountNames.isEmpty,
               let cycle = reading.cycle, cycle.headline.todaySpentMinor > 0 {
                spent = money.amount(cycle.headline.todaySpentMinor)
            }
            let digits = MadarNumberFormatter(style: app.string("core.numerals") == "western" ? .western : .hindi)
            if let page { facts = DiaryNightReviewFacts.facts(page: page, intention: intention, spentToday: spent, digits: digits) }
        }
    }

    private func save() async {
        let words = answer.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !words.isEmpty else { return }
        saving = true; failure = nil
        defer { saving = false }
        do {
            let id = UUID(), writing = try service.currentDay()
            try await service.saveDraft(id: id, text: question + "\n" + words, day: "today", margin: nil, writingDay: writing)
            try await app.executeDiaryCommand("diary.commitDraft", payload: ["id": .string(id.uuidString)], id: id)
            saved(); dismiss()
        } catch { failure = madarUserMessage(error) }
    }
}
