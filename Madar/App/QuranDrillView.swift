import SwiftUI
import MadarDesign

/// M2-V04 · screens/quran/06-R18-Drill.jpg. One spot at a time: the hidden word (or whole ayah) under a prompt line;
/// «قلتها، اكشف» reveals it, then the reciter says whether it was right. Each answer is its own committed drill session.
struct QuranDrillView: View {
    let service: AppQuranService
    let close: () -> Void
    /// Owned here: each spot is a new draft, and writing it back to the home's cover item would re-present the cover.
    @State private var state: QuranUISessionState
    init(service: AppQuranService, initial: QuranUISessionState, close: @escaping () -> Void) {
        self.service = service; self.close = close; _state = State(initialValue: initial)
    }
    @Environment(\.roomTheme) private var theme
    @State private var busy = false
    @State private var error: String?
    @State private var showExit = false
    /// Set when the chosen tab has nothing left today; the last card is then replaced by a quiet message.
    @State private var empty: (tab: QuranUIDrillTab, board: QuranUIDrillBoard)?

    private func font(_ size: CGFloat, bold: Bool = false) -> Font {
        .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body)
    }
    private var card: QuranUIDrillCard? { empty == nil ? state.drill : nil }
    /// The reciter's tab choice wins; a spot in both queues does not pull the tab back to «اليوم».
    @State private var chosen: QuranUIDrillTab?
    private var tab: QuranUIDrillTab { empty?.tab ?? chosen ?? state.drill?.tab ?? .today }

    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 16).padding(.top, 8)
            tabs.padding(.horizontal, 12).padding(.top, 18)
            segments.padding(.horizontal, 12).padding(.top, 14)
            ScrollView {
                if let card { spotCard(card).padding(.horizontal, 12).padding(.top, 20) }
                else { emptyCard.padding(.horizontal, 12).padding(.top, 20) }
            }.scrollBounceBehavior(.basedOnSize)
            footer
        }
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .alert("لم تكتمل العملية", isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })) { Button("تمّ") { error = nil } } message: { Text(error ?? "") }
        .sheet(isPresented: $showExit) {
            VStack(alignment: .leading, spacing: 16) {
                Text("جلسة التدريب محفوظة كمسودة").font(font(21, bold: true))
                Text("لم تسجّل هذه الإجابة بعد. احتفظ بها للمتابعة لاحقًا أو احذفها.").font(font(14)).foregroundStyle(theme.secondaryInk)
                Button { showExit = false; close() } label: {
                    Text("احتفظ بها كمسودة").font(font(14, bold: true)).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }.accessibilityIdentifier("quran-drill-keep")
                Button(role: .destructive) {
                    showExit = false
                    run { try await act(.discard); close() }
                } label: {
                    Text("احذف الجلسة").font(font(14, bold: true)).frame(maxWidth: .infinity, minHeight: 48).contentShape(Rectangle())
                }.accessibilityIdentifier("quran-drill-discard")
                Button { showExit = false } label: {
                    Text("تابع الجلسة").font(font(14)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle())
                }.accessibilityIdentifier("quran-drill-continue")
            }
            .padding(24).frame(maxWidth: .infinity, alignment: .leading).foregroundStyle(theme.ink)
            .presentationBackground(theme.background).presentationDetents([.height(300)]).presentationDragIndicator(.visible)
            .environment(\.layoutDirection, .rightToLeft)
        }
        .interactiveDismissDisabled()
    }

    private var header: some View {
        ZStack {
            VStack(spacing: 4) {
                Text("اختبار مواضع الخطأ").font(font(19, bold: true)).accessibilityAddTraits(.isHeader)
                Text("يُطمس موضع تعثّرك وتُسأل عنه").font(font(13)).foregroundStyle(theme.secondaryInk)
            }.multilineTextAlignment(.center).padding(.horizontal, 56)
            HStack {
                Button { leave() } label: {
                    Image(systemName: "chevron.forward").font(.system(size: 17, weight: .semibold))
                        .frame(width: 44, height: 44).background(theme.color("track"), in: Circle())
                }.buttonStyle(.madarPlain).disabled(busy).accessibilityLabel("رجوع").accessibilityIdentifier("quran-drill-close")
                Spacer()
            }
        }
    }

    private var tabs: some View {
        let labels = (today: state.drill?.todayLabel ?? empty?.board.todayLabel ?? "اليوم", mine: state.drill?.mineLabel ?? empty?.board.mineLabel ?? "أخطائي")
        return HStack(spacing: 0) {
            tabButton(.today, labels.today)
            tabButton(.mine, labels.mine)
        }
        .padding(4).background(theme.color("track"), in: Capsule())
    }
    private func tabButton(_ value: QuranUIDrillTab, _ title: String) -> some View {
        Button { switchTo(value) } label: {
            Text(title).font(font(15, bold: true)).frame(maxWidth: .infinity, minHeight: 44)
                .foregroundStyle(value == tab ? theme.ink : theme.secondaryInk)
                .background { if value == tab { Capsule().fill(theme.surface).shadow(color: .black.opacity(0.06), radius: 3, y: 1) } }
                .contentShape(Capsule())
        }.buttonStyle(.madarPlain).disabled(busy)
            .accessibilityAddTraits(value == tab ? .isSelected : []).accessibilityIdentifier("quran-drill-tab-" + value.rawValue)
    }

    private var segments: some View {
        let total = max(1, card.map { tab == .today ? $0.todayTotal : $0.mineTotal } ?? empty?.board.allowance ?? 1), done = card?.done ?? empty?.board.done ?? 0
        return HStack(spacing: 6) {
            ForEach(0..<total, id: \.self) { index in
                Capsule().fill(index < done ? theme.accent : theme.color("track")).frame(height: 4)
            }
        }
        .accessibilityElement().accessibilityLabel("تدرّبت على " + service.numerals.string(done) + " من " + service.numerals.string(total))
    }

    private func spotCard(_ card: QuranUIDrillCard) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline) {
                Text(card.title).font(font(17, bold: true)).accessibilityIdentifier("quran-drill-title")
                Spacer(minLength: 8)
                Text(card.timesLabel).font(font(12)).foregroundStyle(theme.color("dueText"))
            }
            if let prompt = card.prompt {
                Text("قبلها · للتلقين").font(font(13)).foregroundStyle(theme.secondaryInk).padding(.top, 18)
                Text(prompt).font(.custom(card.fontName, size: 19, relativeTo: .body)).foregroundStyle(theme.secondaryInk)
                    .frame(maxWidth: .infinity, alignment: .leading).padding(.top, 6)
                    .accessibilityLabel("قبلها: " + prompt)
            }
            Rectangle().fill(theme.color("line")).frame(height: 1).padding(.top, 14)
            DrillWordFlow(spacing: 9, lineSpacing: 16) {
                ForEach(Array(card.words.enumerated()), id: \.offset) { index, word in
                    let hidden = !card.revealed && (card.hiddenIndex == nil || card.hiddenIndex == index)
                    Text(word).font(.custom(card.fontName, size: 27, relativeTo: .title2))
                        .foregroundStyle(hidden ? .clear : (card.revealed && (card.hiddenIndex == nil || card.hiddenIndex == index) ? theme.accent : theme.ink))
                        .background {
                            if hidden {
                                RoundedRectangle(cornerRadius: 10).fill(theme.color("gold").opacity(card.hiddenIndex == nil ? 0.4 : 0.55))
                                    .padding(-4).blur(radius: 7)
                            }
                        }
                }
                if card.continues { Text("…").font(.custom(card.fontName, size: 27, relativeTo: .title2)).foregroundStyle(theme.secondaryInk) }
            }
            .padding(.top, 22).padding(.bottom, 6)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(card.revealed ? card.words.joined(separator: " ") : (card.hiddenIndex == nil ? "الآية مستورة" : "الكلمة مستورة"))
            .accessibilityIdentifier("quran-drill-ayah")
            HStack(spacing: 8) {
                Text("نجاحان متتاليان يُغلقانه").font(font(13)).foregroundStyle(theme.secondaryInk)
                ForEach(0..<card.mastery, id: \.self) { index in
                    Circle().fill(index < card.successStreak ? theme.accent : .clear)
                        .glassEffect(.regular.interactive(), in: .circle).frame(width: 16, height: 16)
                }
            }
            .padding(.top, 14)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("نجاحان متتاليان يُغلقانه، تحقق " + service.numerals.string(card.successStreak))
        }
        .padding(.horizontal, 24).padding(.top, 26).padding(.bottom, 24)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .shadow(color: .black.opacity(0.06), radius: 14, y: 6)
    }

    private var emptyCard: some View {
        VStack(spacing: 10) {
            // AU-26: «أتممت» only when something was practised; an empty «أخطائي» is not a finished day.
            let finished = (empty?.board.done ?? 0) > 0
            Text(tab == .today ? "لا مواضع من أخطاء اليوم" : finished ? "أتممت مواضع اليوم" : "لا مواضع مفتوحة في أخطائك").font(font(17, bold: true))
            Text(tab == .today ? "ما تعثّرت فيه اليوم يظهر هنا للتدريب" : finished ? "تعود المواضع المفتوحة غدًا" : "ما تعثّرت فيه أثناء المراجعة يظهر هنا").font(font(13)).foregroundStyle(theme.secondaryInk)
        }
        .multilineTextAlignment(.center).frame(maxWidth: .infinity).padding(.vertical, 40).padding(.horizontal, 24)
        .background(theme.surface, in: RoundedRectangle(cornerRadius: 30, style: .continuous))
        .accessibilityElement(children: .combine).accessibilityIdentifier("quran-drill-empty")
    }

    private var footer: some View {
        Group {
            if let card {
                if !card.revealed {
                    primary("قلتها · اكشف", id: "quran-drill-reveal") {
                        if let ayah = state.mistakeAyahID { run { try await act(.reveal(ayahID: ayah, wordIndex: nil)) } }
                    }
                } else {
                    HStack(spacing: 10) {
                        Button { answer("fail") } label: {
                            Text("أخطأت").font(font(17, bold: true)).frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(theme.ink).background(theme.color("track"), in: Capsule())
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-drill-fail")
                        Button { answer("pass") } label: {
                            Text("أصبت").font(font(17, bold: true)).frame(maxWidth: .infinity, minHeight: 56)
                                .foregroundStyle(theme.onAccent).background(theme.accent, in: Capsule())
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-drill-pass")
                    }
                }
            } else {
                primary("أغلق", id: "quran-drill-done") { close() }
            }
        }
        .disabled(busy)
        .padding(10).background(theme.surface, in: Capsule())
        .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
    private func primary(_ title: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(font(17, bold: true)).frame(maxWidth: .infinity, minHeight: 56)
                .foregroundStyle(theme.onAccent).background(theme.accent, in: Capsule())
        }.buttonStyle(.madarPlain).accessibilityIdentifier(id)
    }

    // MARK: actions
    private func run(_ work: @escaping () async throws -> Void) {
        guard !busy else { return }; busy = true
        Task { defer { busy = false }; do { try await work() } catch { self.error = quranUserMessage(error) } }
    }
    @discardableResult private func act(_ action: QuranUISessionAction) async throws -> QuranUISessionResult {
        let result = try await service.session(draftID: state.id, action: action)
        if case .active(let next) = result { state = next }
        return result
    }
    /// The answer is saved with its own session, then the next spot of the same tab opens.
    private func answer(_ id: String) {
        let current = tab
        run {
            try await act(.chooseAnswer(id))
            try await act(.commit)
            try await openNext(current)
        }
    }
    private func openNext(_ tab: QuranUIDrillTab) async throws {
        let board = try service.drillBoard()
        if let next = (tab == .today ? board.today : board.mine).first {
            state = try await service.start(kind: .drill, stepID: nil, range: nil, rakaat: nil, spotID: next); empty = nil
        } else { empty = (tab, board) }
    }
    private func switchTo(_ value: QuranUIDrillTab) {
        guard value != tab else { return }
        run {
            if empty == nil, state.drill?.answered == false { try await act(.discard) }
            chosen = value
            try await openNext(value)
        }
    }
    /// Ask before leaving an unanswered spot: the draft can be resumed or discarded explicitly.
    private func leave() {
        if empty != nil || state.drill == nil { close(); return }
        showExit = true
    }
}

/// Words wrap right to left like the printed line; each word stays whole.
private struct DrillWordFlow: Layout {
    var spacing: CGFloat
    var lineSpacing: CGFloat
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let rows = rows(subviews, width: width)
        let height = rows.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(0, rows.count - 1))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y + (row.height - size.height) / 2), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + lineSpacing
        }
    }
    private func rows(_ subviews: Subviews, width: CGFloat) -> [(indices: [Int], width: CGFloat, height: CGFloat)] {
        var result: [(indices: [Int], width: CGFloat, height: CGFloat)] = []
        var current: [Int] = [], lineWidth: CGFloat = 0, lineHeight: CGFloat = 0
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed = current.isEmpty ? size.width : lineWidth + spacing + size.width
            if !current.isEmpty && needed > width {
                result.append((current, lineWidth, lineHeight)); current = [index]; lineWidth = size.width; lineHeight = size.height
            } else { current.append(index); lineWidth = needed; lineHeight = max(lineHeight, size.height) }
        }
        if !current.isEmpty { result.append((current, lineWidth, lineHeight)) }
        return result
    }
}
