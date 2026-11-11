import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign
import MadarCommands

/// What waits for the owner when Madar opens: bank messages and balance differences that need a decision.
/// Neither is time-critical, so this is a sheet over the lobby (never a notification); the money room stays for details.
struct BahwAttention: Equatable, Identifiable {
    var id: String { signature }
    /// An account whose newest bank message printed a balance: the owner confirms that Madar's book agrees, or sees the difference.
    struct ReconcileItem: Identifiable, Equatable {
        let id: UUID
        let name: String
        let expectedMinor: Int
        let observedMinor: Int
        let at: Date
        var matches: Bool { expectedMinor == observedMinor }
    }
    /// B2-14 (owner vision, 4 Nov): the latest prayer of today that is still unlogged and past its adhan, asked once with two buttons.
    struct PrayerAsk: Equatable {
        let reference: PrayerReference
        let title: String
    }
    var moneyCount = 0
    var reconcile: [ReconcileItem] = []
    var prayer: PrayerAsk?
    var isEmpty: Bool { moneyCount == 0 && reconcile.isEmpty && prayer == nil }
    /// The same day with the same waiting items is shown once; a new day or a changed set shows it again.
    var signature: String {
        "m\(moneyCount)|p\(prayer.map { $0.reference.day.description + $0.reference.prayer.rawValue } ?? "")|r" + reconcile.map { "\($0.id.uuidString):\($0.observedMinor)" }.sorted().joined(separator: ",")
    }
}

extension AppBahwService {
    /// An account is offered for reconciliation when its newest bank message printed a balance and it was last reconciled a week ago or more.
    static let reconcileOfferAfterDays = 7

    func attention(includeReconcile: Bool = false, ignoringThrottle: Bool = false) -> BahwAttention {
        guard session.protectedDataAuthorized else { return .init() }
        var result = BahwAttention()
        if session.roomEnabled(.mal) { result.moneyCount = pendingBankDecisions() }
        if session.roomEnabled(.salah) { result.prayer = unloggedPrayerAsk() }
        // The whole-ledger reading is heavy for a pop-up, so the lobby asks at most once every few hours.
        if includeReconcile, session.roomEnabled(.mal), (ignoringThrottle || BahwAttentionMemory.reconcileDue(now: now)) { result.reconcile = reconcileOffers() }
        return result
    }
    /// Accounts whose latest bank message carries a balance and whose book has not moved since it (the same rule as the reconcile page's prefill).
    func reconcileOffers() -> [BahwAttention.ReconcileItem] {
        // The reminder planner reads the same whole-ledger reading: share it until money or the day changes.
        guard let reading = MoneyReadingCache.read(session, now, \.reconcile, { try AppMoneyService(app: session).loadReconcile(at: now) }) else { return [] }
        let cutoff = now.addingTimeInterval(-Double(Self.reconcileOfferAfterDays) * 86_400)
        return reading.rows.compactMap { row in
            guard row.side == .account, let suggestion = row.suggestion, row.pending.isEmpty else { return nil }
            if let last = row.lastAt, last > cutoff { return nil }
            return .init(id: row.id, name: row.name, expectedMinor: row.expectedMinor, observedMinor: suggestion.observedMinor, at: suggestion.at)
        }.sorted { $0.name < $1.name }
    }
    /// Today's most recent past prayer that nobody has logged, never inside its sanctity window (adhan to +30 min, Maghrib +20) and never a Friday noon (its kind needs the prayer room).
    func unloggedPrayerAsk() -> BahwAttention.PrayerAsk? {
        guard let snapshot = try? session.prayerSnapshot(at: now) else { return nil }
        let cells = snapshot.today.cells
        let entries = cells.map { cell in
            PrayerLobbyAsk.Entry(prayer: cell.reference.prayer, adhan: cell.prayerTime, isPending: cell.status == .pending, canLog: cell.canLog,
                                 isFridayNoon: cell.isFriday && cell.reference.prayer == .dhuhr)
        }
        guard let chosen = PrayerLobbyAsk.choose(entries, now: now),
              let cell = cells.last(where: { $0.reference.prayer == chosen }) else { return nil }
        let names: [Prayer: String] = [.fajr: "الفجر", .dhuhr: "الظهر", .asr: "العصر", .maghrib: "المغرب", .isha: "العشاء"]
        guard let name = names[chosen] else { return nil }
        return .init(reference: cell.reference, title: name)
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
    @State private var moneyOpen = false
    @State private var reconcileOpen = false
    @State private var revealed = false
    @State private var saving = false
    @State private var reconcileFailure: String?

    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    private var service: AppBahwService { .init(session: session) }
    private var digits: MadarNumberFormatter { service.digits }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("شيء ينتظرك").font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                if let ask = attention.prayer { prayerSection(ask) }
                if attention.moneyCount > 0 { moneySection }
                if !attention.reconcile.isEmpty { reconcileSection }
                Button { later() } label: {
                    Text("لاحقًا").font(MadarTypography.body().bold())
                        .foregroundStyle(theme.ink)
                        .frame(maxWidth: .infinity, minHeight: 50)
                        .background(theme.surface, in: .capsule)
                        .overlay { Capsule().stroke(theme.line) }
                }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("bahw-attention-primary")
            }
            .padding(.horizontal, 20).padding(.top, 28).padding(.bottom, 20)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme)
        .presentationDetents([.medium, .large]).presentationDragIndicator(.visible).presentationBackground(theme.background)
        // FB-39: a swipe-down used to leave the sheet unseen, so it came back on every return to the app, and it dropped chosen chips silently.
        .interactiveDismissDisabled(saving)
        .onDisappear { markSeen() }
        .sheet(isPresented: $reconcileOpen, onDismiss: refreshReconcile) {
            NavigationStack { MoneyReconcileView(app: session, revealed: $revealed) }
        }
        .sheet(isPresented: $moneyOpen, onDismiss: { attention.moneyCount = service.pendingBankDecisions(); if attention.isEmpty { dismiss() } }) {
            NavigationStack { MoneyMessagesView(app: session, revealed: $revealed) }
        }
    }

    private func prayerSection(_ ask: BahwAttention.PrayerAsk) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("صلّيتَ \(ask.title)؟").font(MadarTypography.section())
            HStack(spacing: 10) {
                ForEach([(PrayerStoredStatus.jamaah, "في جماعة"), (.alone, "وحدي")], id: \.1) { status, title in
                    Button {
                        guard !saving else { return }; saving = true
                        session.recordPrayer(ask.reference, status: status) { ok in
                            saving = false
                            if ok { attention.prayer = nil; if attention.isEmpty { dismiss() } }
                        }
                    } label: {
                        Text(title).font(MadarTypography.caption().bold()).foregroundStyle(theme.onAccent)
                            .frame(maxWidth: .infinity, minHeight: 44).background(theme.accentFill, in: .capsule).contentShape(.capsule)
                    }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("bahw-attention-prayer-\(status.rawValue)")
                }
            }
        }
        .padding(16).background(theme.surface, in: .rect(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
    }

    private var moneySection: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(WidgetCopy.agree(attention.moneyCount, digits, one: "رسالة بنكية تنتظر فرزك", two: "رسالتان بنكيتان تنتظران فرزك", few: "رسائل بنكية تنتظر فرزك", many: "رسالة بنكية تنتظر فرزك"))
                    .font(MadarTypography.section())
                Text("لا تدخل أرقامك إلا بعد قرارك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 8)
            Button { moneyOpen = true } label: { Text("افرزها").font(MadarTypography.caption().bold()).foregroundStyle(theme.onAccent)
                .padding(.horizontal, 18).frame(minHeight: 44).background(theme.accentFill, in: .capsule).contentShape(.capsule) }
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
                        Text(figure: reconcileLine(item, money: money)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Button {
                        if item.matches { confirm(item) } else { reconcileOpen = true }
                    } label: { Text(item.matches ? "ثبّت" : "طابق")
                    .font(MadarTypography.caption().bold()).foregroundStyle(theme.onAccent)
                    .padding(.horizontal, 18).frame(minHeight: 44).background(theme.accentFill, in: .capsule).contentShape(.capsule) }
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

    private func later() { markSeen(); dismiss() }

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
