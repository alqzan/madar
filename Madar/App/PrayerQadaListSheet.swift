import SwiftUI
import MadarCore
import MadarDesign
import MadarPrayer

/// S5 · «الفوائت والقضاء», matched to `screens/salah/06-S5-Qada.jpg`: the count, the cited text,
/// every recorded missed prayer oldest first (touch one to choose it), then «اقضِ واحدة».
struct PrayerQadaListSheet: View {
    let session: AppSession
    let dateLabel: (GregorianDay) -> String
    let loadSnapshot: () throws -> PrayerSnapshot
    let rootDraftChanged: (UUID, Bool) -> Void
    let makeUp: (PrayerQada) -> Void
    let addOld: () -> Void
    @Environment(\.roomTheme) private var theme
    @State private var chosen: UUID?
    @State private var rootBlockerID = UUID()
    @State private var contentHeight: CGFloat = 640
    @State private var items: [PrayerQada] = []
    @State private var didLoad = false
    @State private var readFailed = false
    @State private var bulkOpen = false
    private var hasUnsavedInput: Bool { chosen != nil }
    private var digits: MadarNumberFormatter { MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi) }

    var body: some View {
        let selected = items.first { $0.id == chosen } ?? items.first
        VStack(alignment: .leading, spacing: 0) {
            Text("الفوائت والقضاء").font(.custom("thmanyahserifdisplay-Bold", size: 30, relativeTo: .title)).accessibilityAddTraits(.isHeader)
                .accessibilityIdentifier("prayer-qada-title")
            HStack(alignment: .center, spacing: 12) {
                if didLoad && !readFailed && !items.isEmpty { Text(digits.string(items.count)).font(.custom("thmanyahserifdisplay-Bold", size: 64, relativeTo: .largeTitle)) }
                Text(!didLoad ? "جارٍ قراءة الفوائت…" : readFailed ? "تعذّرت قراءة الفوائت الآن." : PrayerCopy.owed(items.count))
                    .font(PrayerHomeType.lead).foregroundStyle(theme.secondaryInk)
                Spacer(minLength: 0)
            }
            .padding(.top, 14).accessibilityElement(children: .combine)
            HStack(alignment: .top, spacing: 12) {
                Rectangle().fill(theme.color("missed")).frame(width: 2)
                PrayerQadaCitation()
            }
            .fixedSize(horizontal: false, vertical: true).padding(.top, 8)
            ScrollView {
                if !didLoad {
                    ProgressView().frame(maxWidth: .infinity, minHeight: 72)
                } else if readFailed {
                    VStack(spacing: 10) {
                        Text("تعذّرت قراءة سجل الصلاة. أعد المحاولة لعرض الفوائت.")
                            .font(PrayerHomeType.body).multilineTextAlignment(.center)
                            .accessibilityIdentifier("prayer-qada-read-error")
                        Button("أعد المحاولة", action: load)
                            .font(PrayerHomeType.strong).frame(minHeight: 44)
                            .accessibilityIdentifier("prayer-qada-retry")
                    }
                    .frame(maxWidth: .infinity, minHeight: 120)
                } else {
                    LazyVStack(spacing: 0) {
                        // Prayers missed on the same day share one date: it is written once, on the
                        // group's first row, and the group has no divider inside it.
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                            let opensDay = index == 0 || items[index - 1].reference.day != item.reference.day
                            if opensDay { Rectangle().fill(theme.ink.opacity(0.1)).frame(height: 1) }
                            row(item, on: item.id == selected?.id, showsDate: opensDay)
                        }
                        Rectangle().fill(theme.ink.opacity(0.1)).frame(height: 1)
                    }
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: readFailed || !didLoad ? 120 : min(CGFloat(items.count) * 61 + 1, 280))
            .padding(.top, 16)
            actions(readFailed || !didLoad ? nil : selected, canAddOld: didLoad && !readFailed)
            // FB-39 (owner, 6 Nov): «قضيتُ ٥ من الفجر» without touching each row.
            if didLoad && !readFailed && items.count > 1 {
                Button { bulkOpen = true } label: {
                    Text("قضيتُ عددًا منها").font(PrayerHomeType.body).frame(maxWidth: .infinity, minHeight: 44)
                }
                .buttonStyle(.madarPlain).padding(.top, 6).accessibilityIdentifier("prayer-qada-bulk-open")
            }
        }
        .padding(.horizontal, 20).padding(.top, 26).padding(.bottom, 14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .onGeometryChange(for: CGFloat.self) { $0.size.height } action: { contentHeight = $0 + 20 }
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.height(min(max(contentHeight, 360), 760)), .large])
        .presentationBackground(theme.background)
        .presentationDragIndicator(.visible)
        .presentationCornerRadius(34)
        .task { load() }
        .sheet(isPresented: $bulkOpen, onDismiss: load) { PrayerQadaBulkMakeUpSheet(session: session, items: items) }
        .onChange(of: hasUnsavedInput, initial: true) { _, dirty in rootDraftChanged(rootBlockerID, dirty) }
        .onDisappear { rootDraftChanged(rootBlockerID, false) }
    }

    private func load() {
        do {
            items = try loadSnapshot().qada.filter { $0.madeUpAt == nil }
            readFailed = false
        } catch {
            readFailed = true
        }
        didLoad = true
    }

    private func row(_ item: PrayerQada, on: Bool, showsDate: Bool) -> some View {
        Button { chosen = item.id } label: {
            HStack(spacing: 12) {
                PrayerStar().fill(theme.color("missed")).frame(width: 14, height: 14).accessibilityHidden(true)
                Text(prayerTitle(item.reference.prayer)).font(PrayerHomeType.lead)
                Spacer(minLength: 8)
                MadarDateLabel(dateLabel(item.reference.day)).foregroundStyle(theme.secondaryInk)
                    .opacity(showsDate ? 1 : 0)
            }
            .padding(.horizontal, 10).frame(minHeight: 60)
            .background(on ? theme.color("missed").opacity(0.08) : .clear, in: .rect(cornerRadius: 14))
            .contentShape(.rect)
        }
        .buttonStyle(.madarPlain)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(on ? .isSelected : [])
        .accessibilityIdentifier("prayer-qada-row-\(item.reference.day)-\(item.reference.prayer.rawValue)")
    }

    private func actions(_ selected: PrayerQada?, canAddOld: Bool) -> some View {
        HStack(spacing: 12) {
            Button { if let selected { makeUp(selected) } } label: {
                Text("اقضِ واحدة").font(PrayerHomeType.strong).foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity, minHeight: 56).background(theme.ink, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.madarPlain).disabled(selected == nil || session.prayerWriteInProgress)
            .opacity(selected == nil ? 0.4 : 1).accessibilityIdentifier("prayer-qada-makeup-chosen")
            Button(action: addOld) {
                Text("أضِف فائتة قديمة").font(PrayerHomeType.strong).padding(.horizontal, 22).frame(minHeight: 56)
                    .overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.ink.opacity(0.14), lineWidth: 1) }
                    .contentShape(.rect(cornerRadius: 18))
            }
            .buttonStyle(.madarPlain).disabled(!canAddOld).opacity(canAddOld ? 1 : 0.4)
            .accessibilityIdentifier("prayer-old-missed")
        }
        .padding(.top, 16)
    }
}

/// FB-39: make up several debts of one prayer at once. The oldest go first, as in «اقضِ واحدة».
private struct PrayerQadaBulkMakeUpSheet: View {
    let session: AppSession
    let items: [PrayerQada]
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var prayer: Prayer = .fajr
    @State private var countText = ""
    private var digits: MadarNumberFormatter { MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi) }
    private var owed: [Prayer: Int] { Dictionary(grouping: items, by: \.reference.prayer).mapValues(\.count) }
    private var available: [Prayer] { Prayer.allCases.filter { (owed[$0] ?? 0) > 0 } }
    private var count: Int? {
        let values = countText.compactMap(\.wholeNumberValue)
        guard !values.isEmpty else { return nil }
        let value = values.reduce(0) { $0 * 10 + $1 }
        return (1...(owed[prayer] ?? 0)).contains(value) ? value : nil
    }
    private func title(_ prayer: Prayer) -> String { switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" } }
    private func prayers(_ n: Int) -> String { WidgetCopy.agree(n, digits, one: "صلاة واحدة", two: "صلاتان", few: "صلوات", many: "صلاة") }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            Text("قضيتُ عددًا منها").font(.custom("thmanyahserifdisplay-Bold", size: 26, relativeTo: .title2)).accessibilityAddTraits(.isHeader)
            Picker("الصلاة", selection: $prayer) {
                ForEach(available, id: \.self) { Text(title($0)).tag($0) }
            }
            .pickerStyle(.segmented).accessibilityIdentifier("prayer-qada-bulk-prayer")
            Text("عليك من \(title(prayer)) " + prayers(owed[prayer] ?? 0) + ".").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
            HStack {
                Text("كم قضيت؟").font(PrayerHomeType.body)
                Spacer()
                TextField("٥", text: $countText).keyboardType(.numberPad).multilineTextAlignment(.center)
                    .font(PrayerHomeType.strong).frame(width: 96, height: 48)
                    .background(theme.surface, in: .rect(cornerRadius: 12))
                    .accessibilityIdentifier("prayer-qada-bulk-count")
            }
            Text("تُسجَّل الأقدم أولًا، بتاريخ اليوم.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Button {
                guard let count else { return }
                session.makeUpOldest(prayer: prayer, count: count) { success in if success { dismiss() } }
            } label: {
                Text(count.map { "سجّل قضاء " + prayers($0) } ?? "سجّل القضاء").font(PrayerHomeType.strong).foregroundStyle(theme.background)
                    .frame(maxWidth: .infinity, minHeight: 56).background(theme.ink, in: .rect(cornerRadius: 18))
            }
            .buttonStyle(.madarPlain).disabled(count == nil || session.prayerWriteInProgress).opacity(count == nil ? 0.4 : 1)
            .accessibilityIdentifier("prayer-qada-bulk-save")
        }
        .padding(22).frame(maxHeight: .infinity, alignment: .top)
        .background(theme.background).foregroundStyle(theme.ink)
        .presentationDetents([.height(420)]).presentationBackground(theme.background)
        .environment(\.layoutDirection, .rightToLeft)
        .onAppear { if let first = available.first, owed[prayer] == nil { prayer = first } }
        .onChange(of: prayer) { _, _ in countText = "" }
    }
}
