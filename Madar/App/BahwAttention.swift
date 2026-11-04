import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarPrayer
import MadarCommands

/// What waits for the owner when Madar opens: prayers whose window closed without a record, and bank messages that need sorting.
/// Neither is time-critical, so this is a sheet over the lobby (never a notification); the prayer room and the money room stay for details.
struct BahwAttention: Equatable, Identifiable {
    var id: String { signature }
    struct PrayerItem: Identifiable, Equatable {
        let reference: PrayerReference
        let name: String
        let dayWord: String
        let fridayNoon: Bool
        var id: String { reference.day.description + "." + reference.prayer.rawValue }
    }
    /// An account whose newest bank message printed a balance: the owner confirms that Madar's book agrees, or sees the difference.
    struct ReconcileItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let expectedMinor: Int
        let observedMinor: Int
        let at: Date
        var matches: Bool { expectedMinor == observedMinor }
    }
    var prayers: [PrayerItem] = []
    var moneyCount = 0
    var reconcile: [ReconcileItem] = []
    var isEmpty: Bool { prayers.isEmpty && moneyCount == 0 && reconcile.isEmpty }
    /// The same day with the same waiting items is shown once; a new day or a changed set shows it again.
    var signature: String {
        prayers.map(\.id).sorted().joined(separator: ",") + "|m\(moneyCount)"
            + "|r" + reconcile.map { "\($0.id.uuidString):\($0.observedMinor)" }.sorted().joined(separator: ",")
    }
}

extension AppBahwService {
    /// An account is offered for reconciliation when its newest bank message printed a balance and it was last reconciled a week ago or more.
    static let reconcileOfferAfterDays = 7

    func attention(includeReconcile: Bool = false, ignoringThrottle: Bool = false) -> BahwAttention {
        guard session.lockController?.canPresent(.app) ?? session.protectedDataAuthorized else { return .init() }
        var result = BahwAttention()
        if session.roomEnabled(.salah), let snapshot = try? session.prayerSnapshot(at: now) {
            let pending = Set(snapshot.pending)
            // Only prayers whose window has really ended are listed (`canMarkMissed`: Fajr until sunrise, the others until the next adhan; RP1/RP2: nothing becomes «missed» by itself).
            let closed = snapshot.history.flatMap(\.cells).filter { pending.contains($0.reference) && $0.canLog && $0.canMarkMissed && $0.time != nil }
            var references = snapshot.unconfirmed
            for cell in closed where !references.contains(cell.reference) { references.append(cell.reference) }
            let fridays = snapshot.unconfirmedFridayNoon.union(closed.filter { $0.isFriday && $0.reference.prayer == .dhuhr }.map(\.reference))
            let names: [Prayer: String] = [.fajr: "الفجر", .dhuhr: "الظهر", .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء"]
            let today = snapshot.today.day
            let order: [Prayer: Int] = [.fajr: 0, .dhuhr: 1, .asr: 2, .maghrib: 3, .isha: 4]
            result.prayers = references.sorted { ($0.day, order[$0.prayer] ?? 0) < ($1.day, order[$1.prayer] ?? 0) }.map { reference in
                let friday = fridays.contains(reference)
                let dayWord = reference.day == today ? "اليوم" : reference.day == today.adding(days: -1) ? "أمس" : session.dateLabels(reference.day, compact: true).primary
                return .init(reference: reference, name: friday ? "الجمعة" : names[reference.prayer] ?? "", dayWord: dayWord, fridayNoon: friday)
            }
        }
        if session.roomEnabled(.mal) { result.moneyCount = pendingBankDecisions() }
        // The whole-ledger reading is heavy for a pop-up, so the lobby asks at most once every few hours.
        if includeReconcile, session.roomEnabled(.mal), (ignoringThrottle || BahwAttentionMemory.reconcileDue(now: now)) { result.reconcile = reconcileOffers() }
        return result
    }
    /// Accounts whose latest bank message carries a balance and whose book has not moved since it (the same rule as the reconcile page's prefill).
    func reconcileOffers() -> [BahwAttention.ReconcileItem] {
        guard let reading = try? AppMoneyService(app: session).loadReconcile(at: now) else { return [] }
        let cutoff = now.addingTimeInterval(-Double(Self.reconcileOfferAfterDays) * 86_400)
        return reading.rows.compactMap { row in
            guard row.side == .account, let suggestion = row.suggestion, row.pending.isEmpty else { return nil }
            if let last = row.lastAt, last > cutoff { return nil }
            return .init(id: row.id, name: row.name, expectedMinor: row.expectedMinor, observedMinor: suggestion.observedMinor, at: suggestion.at)
        }.sorted { $0.name < $1.name }
    }
    /// The count alone, from the repository: the whole money reading is far heavier than a pop-up deserves.
    func pendingBankDecisions() -> Int {
        (try? MoneyRepository(context: ModelContext(session.container)).pendingDecisionCount()) ?? 0
    }
}

/// «شيء ينتظرك»: short, one decision per line, one save. «لاحقًا» keeps everything as it is.
struct BahwAttentionSheet: View {
    @Bindable var session: AppSession
    @State var attention: BahwAttention
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    @State private var choices: [String: Option] = [:]
    @State private var moneyOpen = false
    @State private var reconcileOpen = false
    @State private var revealed = false
    @State private var saving = false
    @State private var reconcileFailure: String?

    enum Option: Hashable {
        case jamaah, alone, skip, jumuah, dhuhr
        var title: String {
            switch self { case .jamaah: "في جماعة"; case .alone: "وحدي"; case .skip: "لم أسجّل"; case .jumuah: "الجمعة"; case .dhuhr: "ظهرًا" }
        }
        var resolution: (status: PrayerStoredStatus, friday: FridayPrayerKind?) {
            switch self {
            case .jamaah: (.jamaah, nil)
            case .alone: (.alone, nil)
            case .skip: (.unrecordedHistory, nil)
            case .jumuah: (.jamaah, .jumuah)
            case .dhuhr: (.alone, .dhuhr)
            }
        }
    }

    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    private var service: AppBahwService { .init(session: session) }
    private var digits: MadarNumberFormatter { service.digits }
    /// A long gap is settled in one tap, as in the prayer room (RP1: never counted as missed).
    private var longGap: Bool { attention.prayers.count > 6 }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("شيء ينتظرك").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                if !attention.prayers.isEmpty { prayersSection }
                if attention.moneyCount > 0 { moneySection }
                if !attention.reconcile.isEmpty { reconcileSection }
                Button { later() } label: {
                    Text(saveEnabled ? "احفظ" : "لاحقًا").font(MadarTypography.body().bold())
                        .foregroundStyle(saveEnabled ? theme.onAccent : theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(saveEnabled ? theme.accentFill : theme.surface, in: .capsule)
                        .overlay { if !saveEnabled { Capsule().stroke(theme.line) } }
                }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("bahw-attention-primary")
                if saveEnabled {
                    Button("لاحقًا") { markSeen(); dismiss() }.font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("bahw-attention-later")
                }
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationBackground(theme.background)
        .sheet(isPresented: $reconcileOpen, onDismiss: refreshReconcile) {
            NavigationStack { MoneyReconcileView(app: session, revealed: $revealed) }
        }
        .sheet(isPresented: $moneyOpen, onDismiss: { attention.moneyCount = service.pendingBankDecisions(); if attention.isEmpty { dismiss() } }) {
            NavigationStack { MoneyMessagesView(app: session, revealed: $revealed) }
        }
    }

    private var saveEnabled: Bool { !choices.isEmpty }

    private var prayersSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(WidgetCopy.agree(attention.prayers.count, digits, one: "صلاة واحدة لم تُسجَّل", two: "صلاتان لم تُسجَّلا", few: "صلوات لم تُسجَّل", many: "صلاة لم تُسجَّل"))
                .font(MadarTypography.section())
            if longGap {
                Text("لا يلزمك واحدة واحدة. لا يُحسب عليك شيء.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                HStack(spacing: 10) {
                    chip("صلّيتها وحدي", on: false, id: "bahw-attention-gap-alone") { apply(.alone, to: attention.prayers.filter { !$0.fridayNoon }) }
                    chip("لم أسجّل الفترة", on: false, id: "bahw-attention-gap-skip") { apply(.skip, to: attention.prayers) }
                }
            } else {
                ForEach(attention.prayers) { item in
                    HStack(spacing: 8) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(item.name).font(MadarTypography.body().bold())
                            Text(item.dayWord).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        }.frame(minWidth: 52, alignment: .leading)
                        ForEach(options(for: item), id: \.self) { option in
                            chip(option.title, on: choices[item.id] == option, id: "bahw-attention-\(item.id)-\(option)") {
                                choices[item.id] = choices[item.id] == option ? nil : option
                            }
                        }
                    }
                }
            }
        }
    }

    private var moneySection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetCopy.agree(attention.moneyCount, digits, one: "رسالة بنكية تنتظر فرزك", two: "رسالتان بنكيتان تنتظران فرزك", few: "رسائل بنكية تنتظر فرزك", many: "رسالة بنكية تنتظر فرزك"))
                    .font(MadarTypography.section())
                Text("لا تدخل أرقامك إلا بعد قرارك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            Button("افرزها") { moneyOpen = true }.font(MadarTypography.caption().bold()).foregroundStyle(theme.onAccent)
                .padding(.horizontal, 18).frame(minHeight: 44).background(theme.accentFill, in: .capsule).contentShape(.capsule)
                .buttonStyle(.madarPlain).accessibilityIdentifier("bahw-attention-money")
        }
        .padding(16).background(theme.surface, in: .rect(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
    }

    private var moneyVisible: Bool { revealed || !session.bool("core.hideMoneyUntilTouch") }

    private var reconcileSection: some View {
        let money = AppMoneyService(app: session)
        return VStack(alignment: .leading, spacing: 12) {
            Text("مطابقة الرصيد").font(MadarTypography.section())
            ForEach(attention.reconcile) { item in
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(item.name).font(MadarTypography.body().bold())
                        Text(reconcileLine(item, money: money)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Button(item.matches ? "ثبّت" : "طابق") {
                        if item.matches { confirm(item) } else { reconcileOpen = true }
                    }
                    .font(MadarTypography.caption().bold()).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 18).frame(minHeight: 44).background(theme.accentFill, in: .capsule).contentShape(.capsule)
                    .buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("bahw-attention-reconcile-\(item.id.uuidString)")
                }
                .padding(16).background(theme.surface, in: .rect(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
            }
            if let reconcileFailure { Text(reconcileFailure).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
        }
    }

    /// No blame in the wording: a difference is a fact to look at, never a mistake. Amounts stay hidden while the owner keeps money hidden.
    private func reconcileLine(_ item: BahwAttention.ReconcileItem, money: AppMoneyService) -> String {
        if item.matches { return moneyVisible ? "رصيدك في مدار يوافق رسالة البنك: \(money.amount(item.observedMinor))" : "رصيدك في مدار يوافق رسالة البنك" }
        guard moneyVisible else { return "رصيد رسالة البنك الأخيرة يختلف عن دفترك" }
        let gap = abs(item.observedMinor - item.expectedMinor)
        return "الرسالة تقول \(money.amount(item.observedMinor)) ودفترك \(money.amount(item.expectedMinor)): فرق \(money.amount(gap))"
    }

    /// An exact match is settled here in one tap; a difference opens the reconcile page, where it can be named.
    private func confirm(_ item: BahwAttention.ReconcileItem) {
        guard !saving, item.matches else { return }
        saving = true; reconcileFailure = nil
        let row: MadarCore.JSONValue = .object([
            "accountID": .string(item.id.uuidString),
            "expectedMinor": .string(String(item.expectedMinor)),
            "observedMinor": .string(String(item.observedMinor)),
            "at": .string(ISO8601DateFormatter().string(from: item.at)),
        ])
        Task {
            do {
                try await session.executeMoneyCommand("money.reconcile", payload: ["rows": .array([row])])
                attention.reconcile.removeAll { $0.id == item.id }
                if attention.isEmpty { markSeen(); dismiss() }
            } catch {
                reconcileFailure = "تعذّر حفظ المطابقة الآن. افتح المطابقة لتراجعها."
            }
            saving = false
        }
    }

    private func refreshReconcile() {
        attention.reconcile = service.reconcileOffers()
        attention.moneyCount = service.pendingBankDecisions()
        if attention.isEmpty { dismiss() }
    }

    private func options(for item: BahwAttention.PrayerItem) -> [Option] { item.fridayNoon ? [.jumuah, .dhuhr, .skip] : [.jamaah, .alone, .skip] }

    private func chip(_ title: String, on: Bool, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title).font(MadarTypography.caption().bold()).lineLimit(1).minimumScaleFactor(0.8)
                .foregroundStyle(on ? theme.onAccent : theme.ink)
                .frame(maxWidth: .infinity, minHeight: 44)
                .background(on ? theme.accentFill : theme.surface, in: .capsule)
                .overlay { if !on { Capsule().stroke(theme.line) } }
                .contentShape(.capsule)
        }.buttonStyle(.madarPlain).accessibilityIdentifier(id).accessibilityAddTraits(on ? .isSelected : [])
    }

    /// One tap settles the whole gap and saves at once (one short undo on the home).
    private func apply(_ option: Option, to items: [BahwAttention.PrayerItem]) {
        for item in items { choices[item.id] = option }
        save()
    }

    private func later() {
        if saveEnabled { save() } else { markSeen(); dismiss() }
    }

    private func save() {
        let resolutions = attention.prayers.compactMap { item -> PrayerGapResolution? in
            guard let option = choices[item.id] else { return nil }
            let value = option.resolution
            return PrayerGapResolution(reference: item.reference, status: value.status, fridayKind: value.friday)
        }
        guard !resolutions.isEmpty else { return }
        saving = true
        session.resolvePrayerGap(resolutions) { ok in
            saving = false
            guard ok else { return }   // a failed save keeps the choices on screen
            let settled = Set(resolutions.map { $0.reference })
            attention.prayers.removeAll { settled.contains($0.reference) }
            choices = [:]
            if attention.isEmpty { markSeen(); dismiss() }
        }
    }

    private func markSeen() { UserDefaults.standard.set(attention.signature, forKey: BahwAttentionMemory.key) }
}

enum BahwAttentionMemory {
    static let key = "bahw.attention.seenSignature"
    static let reconcileCheckedKey = "bahw.reconcile.checkedAt"
    static let reconcileEveryHours = 3.0
    /// True at most once per window; the owner's own tap on a suggestion bypasses it (`force`).
    static func reconcileDue(now: Date) -> Bool {
        let last = UserDefaults.standard.object(forKey: reconcileCheckedKey) as? Date
        guard last.map({ now.timeIntervalSince($0) >= reconcileEveryHours * 3_600 || now < $0 }) ?? true else { return false }
        UserDefaults.standard.set(now, forKey: reconcileCheckedKey)
        return true
    }
    static func isNew(_ attention: BahwAttention) -> Bool {
        !attention.isEmpty && UserDefaults.standard.string(forKey: key) != attention.signature
    }
}
