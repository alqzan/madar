import SwiftUI
import Observation
import MadarCore
import MadarDesign

// A display projection of the prayer engine. Dates, eligibility and statistics are
// resolved by the service in the active place's time zone, never inferred by UI.
enum PrayerUICode: String, CaseIterable, Identifiable, Sendable {
    case fajr, dhuhr, asr, maghrib, isha
    var id: String { rawValue }
    var title: String { switch self { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" } }
}
enum PrayerUIStatus: String, CaseIterable, Sendable {
    case jamaah, alone, qada, missed, unrecordedHistory, pending, future
    var title: String { switch self { case .jamaah: "في جماعة"; case .alone: "وحدي"; case .qada: "قُضيت"; case .missed: "فاتتني"; case .unrecordedHistory: "لم أسجّل"; case .pending: "لم تُسجَّل"; case .future: "لم يحن" } }
}
enum PrayerUIHeart: String, CaseIterable, Identifiable, Sendable {
    case distracted, present, khashi
    var id: String { rawValue }
    var title: String { switch self { case .distracted: "شارد"; case .present: "حاضر"; case .khashi: "خاشع" } }
    var sentence: String { switch self { case .distracted: "كنت في وادٍ آخر"; case .present: "عرفت ما أقول"; case .khashi: "وجدت لها أثرًا" } }
}
struct PrayerUISelection: Hashable, Identifiable, Sendable {
    let dayKey: String
    let prayer: PrayerUICode
    var id: String { dayKey + "." + prayer.rawValue }
}
struct PrayerUIEntry: Identifiable, Sendable {
    let selection: PrayerUISelection
    var title: String
    var time: Date?
    var timeLabel: String?
    var status: PrayerUIStatus
    var heart: PrayerUIHeart?
    var canLog: Bool
    var canMakeUp: Bool
    var canClear: Bool
    var shortened: Bool
    var canShorten: Bool
    var isFriday: Bool
    var fridayKind: FridayPrayerKind?
    var isNext: Bool
    var estimated: Bool
    var id: String { selection.id }
}
struct PrayerUINext: Sendable { var title: String; var time: Date; var timeLabel: String }
struct PrayerUIHistoryDay: Identifiable, Sendable { var dayKey: String; var title: String; var entries: [PrayerUIEntry]; var id: String { dayKey } }
struct PrayerUIQada: Identifiable, Sendable { var selection: PrayerUISelection; var title: String; var dateLabel: String; var fridayKind: FridayPrayerKind?; var isFriday: Bool; var id: String { selection.id } }
struct PrayerUIBead: Identifiable, Sendable { var id: String; var status: PrayerUIStatus; var accessibilityLabel: String }
struct PrayerUISummary: Sendable {
    var monthTitle: String
    var onTime: Int
    var denominator: Int
    var percentageLabel: String? // nil when the eligible denominator is zero
    var prayerStreakLabel: String
    var mosqueStreakLabel: String?
    var madeUpLabel: String
    var beads: [PrayerUIBead] // oldest first, maximum 25
    var commitment: [String]
    var heartSentences: [String] // qualitative only; no scores or averages
}
struct PrayerUINight: Identifiable, Sendable { var nightKey: String; var title: String; var rakaat: Int; var witr: Bool; var id: String { nightKey } }
struct PrayerUITravel: Sendable { var title: String; var canEnd: Bool; var availablePairs: [PrayerUIPair] }
enum PrayerUIPair: String, CaseIterable, Identifiable, Sendable {
    case dhuhrAsr, maghribIsha
    var id: String { rawValue }
    var title: String { self == .dhuhrAsr ? "الظهر والعصر" : "المغرب والعشاء" }
}
enum PrayerUIPairMode: String, CaseIterable, Identifiable, Sendable {
    case taqdim, takhir
    var id: String { rawValue }
    var title: String { self == .taqdim ? "جمع تقديم" : "جمع تأخير" }
}
struct PrayerRoomState: Sendable {
    var dayKey: String
    var dateTitle: String
    var secondaryDateTitle: String
    var placeTitle: String
    var locationMessage: String?
    var accuracyMessage: String?
    var next: PrayerUINext?
    var timesUnavailable: Bool
    var entries: [PrayerUIEntry]
    var pending: [PrayerUIEntry]
    var pendingDays: Int
    var pendingHeart: [PrayerUIEntry]
    var askHeart: Bool
    var summary: PrayerUISummary?
    var history: [PrayerUIHistoryDay]
    var qada: [PrayerUIQada]
    var oldMissedEarliest: Date // engine-provided selectable range
    var oldMissedLatest: Date
    var oldMissedDefault: Date
    var nights: [PrayerUINight] // engine-selected current/last elapsed + eligible last 7
    var nightFootprint: [PrayerUINight] // last 30 elapsed nights; gaps remain gaps
    var isNight: Bool
    var travel: PrayerUITravel?
    var balanceView: String
    var pool: Bool
    var fridayTallArch: Bool
    var blockOrder: [String]
    var hiddenBlocks: Set<String>
    var numeralLocale: String
    var timeZoneID: String
}
enum PrayerUICommand: Sendable {
    case log(PrayerUISelection, status: PrayerUIStatus, heart: PrayerUIHeart?, shortened: Bool, fridayKind: FridayPrayerKind?)
    case setHeart(PrayerUISelection, heart: PrayerUIHeart?)
    case makeUp(PrayerUISelection, fridayKind: FridayPrayerKind?)
    case clear(PrayerUISelection)
    case markUnrecorded([PrayerUISelection])
    case logPair(dayKey: String, pair: PrayerUIPair, status: PrayerUIStatus, mode: PrayerUIPairMode, shortened: Bool)
    case addOldMissed(day: Date, prayer: PrayerUICode, fridayKind: FridayPrayerKind?)
    case saveQiyam(nightKey: String, rakaat: Int, witr: Bool)
    case endTrip
}
@MainActor protocol PrayerUIService: AnyObject {
    func load() async throws -> PrayerRoomState
    // Returns only after a durable, validated CommandBus receipt. Root owns undo.
    func perform(_ command: PrayerUICommand) async throws
}
@MainActor @Observable final class PrayerRoomModel {
    let service: any PrayerUIService
    var state: PrayerRoomState?
    var busy = false
    var error: String?
    init(service: any PrayerUIService) { self.service = service }
    func refresh() async { guard !busy else { return }; do { state = try await service.load() } catch { self.error = madarUserMessage(error) } }
    func perform(_ command: PrayerUICommand) async -> Bool {
        guard !busy else { return false }; error = nil; busy = true; defer { busy = false }
        do { try await service.perform(command) }
        catch { self.error = madarUserMessage(error); return false }
        do { state = try await service.load() }
        catch { state = nil; self.error = "حُفظ التغيير، وتعذّرت إعادة قراءة السجلّ: " + madarUserDetail(error) }
        return true
    }
}

struct PrayerRoom: View {
    @State private var model: PrayerRoomModel
    @Environment(\.roomTheme) private var inheritedTheme
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var sheet: PrayerSheet?
    let settingsService: any PrayerSettingsUIService
    init(service: any PrayerUIService, settingsService: any PrayerSettingsUIService) {
        _model = State(initialValue: PrayerRoomModel(service: service)); self.settingsService = settingsService
    }
    private var theme: RoomTheme { RoomTheme(room: "salah", dark: inheritedTheme.dark, calmPaper: inheritedTheme.calmPaper) }
    var body: some View {
        ScrollView {
            if let state = model.state {
                VStack(alignment: .leading, spacing: 20) {
                    header(state)
                    if let message = state.locationMessage { Text(message).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
                    if let travel = state.travel { travelCard(travel, dayKey: state.dayKey) }
                    ForEach(blocks(state), id: \.self) { key in block(key, state: state) }
                    Button("سجلّ الصلاة") { sheet = .history }.frame(minHeight: 44).accessibilityIdentifier("prayer-history")
                }.padding(16).frame(maxWidth: 650).frame(maxWidth: .infinity)
            } else { ContentUnavailableView("الصلاة", systemImage: "moon.stars", description: Text("تُقرأ مواقيتك وسجلّك من هذا الجهاز.")); Button("حاول مجددًا") { Task { await model.refresh() } } }
        }
        .background(theme.background).foregroundStyle(theme.ink).font(MadarTypography.body())
        .environment(\.roomTheme, theme).navigationTitle("الصلاة").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { PrayerSettingsView(service: settingsService) } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("خصّص الصلاة").accessibilityIdentifier("prayer-settings") } }
        .task { await model.refresh() }
        .task { while !Task.isCancelled { do { try await Task.sleep(for: .seconds(60)) } catch { return }; await model.refresh() } }
        .refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .sheet(item: $sheet) { route in NavigationStack { sheetBody(route).alert("تعذّر إتمام العملية", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") }.toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { sheet = nil } } } }.environment(\.roomTheme, theme) }
        .alert("تعذّر إتمام العملية", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") }
        .disabled(model.busy)
        .overlay { if model.busy { ProgressView().padding(20).background(.regularMaterial, in: .capsule).accessibilityLabel("جارٍ حفظ الصلاة") } }
    }
    private func blocks(_ state: PrayerRoomState) -> [String] {
        let known = ["next", "riwaq", "pending", "hali", "qada", "qiyam"]
        var order = state.blockOrder.filter { known.contains($0) }
        order = Array(order.enumerated().filter { index, key in order.firstIndex(of: key) == index }.map(\.element))
        for key in known where !order.contains(key) { order.append(key) }
        if state.isNight, let index = order.firstIndex(of: "qiyam") { order.remove(at: index); order.insert("qiyam", at: min(2, order.count)) }
        return order.filter { !state.hiddenBlocks.contains($0) || ["next", "riwaq"].contains($0) }
    }
    private func header(_ state: PrayerRoomState) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            Text("الصلاة").font(MadarTypography.title())
            Text(state.dateTitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Text(state.secondaryDateTitle + "، " + state.placeTitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }
    }
    @ViewBuilder private func block(_ key: String, state: PrayerRoomState) -> some View {
        switch key {
        case "next": nextCard(state)
        case "riwaq": riwaq(state)
        case "pending": pendingCard(state)
        case "hali": if let summary = state.summary { Button { sheet = .hali } label: { MadarCard { VStack(alignment: .leading, spacing: 12) { Text("حالي").font(MadarTypography.cardTitle()); PrayerBalance(summary: summary, style: state.balanceView, locale: state.numeralLocale); Text(summary.percentageLabel.map { $0 + "، " + summary.monthTitle } ?? "لم تُحسب النسبة بعد"); Text(summary.prayerStreakLabel).foregroundStyle(theme.secondaryInk); if let mosque = summary.mosqueStreakLabel { Text(mosque).foregroundStyle(theme.secondaryInk) } } } }.buttonStyle(.plain).accessibilityIdentifier("prayer-hali") }
        case "qada": qadaCard(state)
        case "qiyam": if !state.nights.isEmpty { Button { sheet = .qiyam } label: { MadarCard { VStack(alignment: .leading, spacing: 10) { Label("قيام الليل", systemImage: "moon.stars").font(MadarTypography.cardTitle()); Text(state.nights[0].rakaat == 0 ? "سجّل ما قمتَه" : "\(number(state.nights[0].rakaat, state)) ركعات"); Text("ليس سلسلة تنكسر، أثرٌ يُرى").foregroundStyle(theme.secondaryInk) } } }.buttonStyle(.plain).accessibilityIdentifier("prayer-qiyam") }
        default: EmptyView()
        }
    }
    private func nextCard(_ state: PrayerRoomState) -> some View {
        VStack(spacing: 10) {
            if let next = state.next {
                Text("الصلاة القادمة").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                Text(next.title).font(MadarTypography.title())
                TimelineView(.periodic(from: .now, by: 60)) { timeline in
                    if next.time > timeline.date { HStack(spacing: 5) { Text("بعد"); Text(next.time, style: .relative).monospacedDigit() }.accessibilityLabel("الوقت المتبقي") }
                }
                Text(next.timeLabel).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            } else { Text(state.timesUnavailable ? "لا تُحسب المواقيت هنا اليوم" : "اكتمل يوم الصلاة").font(MadarTypography.cardTitle()); if state.timesUnavailable { Text("يمكنك التسجيل يدويًا؛ لا تذكير بمواقيت غير متاحة.").font(MadarTypography.caption()) } }
        }.frame(maxWidth: .infinity).padding(.vertical, 12).accessibilityIdentifier("prayer-next")
    }
    private func riwaq(_ state: PrayerRoomState) -> some View {
        MadarCard {
            VStack(spacing: 12) {
                if typeSize.isAccessibilitySize {
                    ForEach(state.entries) { entry in Button { sheet = .log(entry) } label: { HStack { PrayerStar().fill(statusColor(entry.status)).frame(width: 20, height: 20); VStack(alignment: .leading) { Text(entry.title); Text([entry.timeLabel, entry.status.title].compactMap { $0 }.joined(separator: "، ")).font(MadarTypography.caption()) }; Spacer(); Image(systemName: "chevron.forward") }.frame(minHeight: 60) }.buttonStyle(.plain).accessibilityIdentifier("prayer-arch-" + entry.selection.prayer.rawValue) }
                } else {
                    HStack(alignment: .bottom, spacing: 8) {
                        ForEach(state.entries) { entry in
                            Button { sheet = .log(entry) } label: { PrayerArchView(entry: entry, pool: state.pool, tall: state.fridayTallArch && entry.isFriday) }
                                .buttonStyle(.plain).frame(maxWidth: .infinity).accessibilityLabel([entry.title, entry.timeLabel, entry.status.title, entry.heart?.title].compactMap { $0 }.joined(separator: "، ")).accessibilityIdentifier("prayer-arch-" + entry.selection.prayer.rawValue)
                        }
                    }
                }
                if let message = state.accuracyMessage { Text(message).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            }
        }
    }
    @ViewBuilder private func pendingCard(_ state: PrayerRoomState) -> some View {
        if !state.pending.isEmpty {
            Button { sheet = .pending } label: { MadarCard { VStack(alignment: .leading, spacing: 8) { Text("\(number(state.pending.count, state)) صلوات تنتظر التسجيل").font(MadarTypography.section()); Text("تظل معلّقة \(number(state.pendingDays, state)) أيام صلاة، ثم تُحسب فائتة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Text("سجّلها").foregroundStyle(theme.accent) } } }.buttonStyle(.plain).accessibilityIdentifier("prayer-pending")
        }
        if let entry = state.pendingHeart.first { Button { sheet = .log(entry) } label: { MadarCard { Label("بقي سؤال القلب عن " + entry.title, systemImage: "sparkle").font(MadarTypography.section()) } }.buttonStyle(.plain).accessibilityIdentifier("prayer-pending-heart") }
    }
    private func qadaCard(_ state: PrayerRoomState) -> some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 14) {
                Text(state.qada.isEmpty ? "لا قضاء مسجّل عليك" : "\(number(state.qada.count, state)) فوائت عليك").font(MadarTypography.cardTitle()).foregroundStyle(state.qada.isEmpty ? theme.ink : theme.color("missedTextOnSurface"))
                PrayerQadaCitation()
                Button(state.qada.isEmpty ? "القضاء · أضِف فائتة قديمة" : "اقضِ واحدة") { sheet = .qada }.frame(minHeight: 44).accessibilityIdentifier("prayer-qada")
            }
        }
    }
    private func travelCard(_ travel: PrayerUITravel, dayKey: String) -> some View {
        MadarCard { VStack(alignment: .leading, spacing: 12) { Label(travel.title, systemImage: "suitcase").font(MadarTypography.section()); ForEach(travel.availablePairs) { pair in Button("سجّل " + pair.title + " جمعًا") { sheet = .pair(pair) }.frame(minHeight: 44).accessibilityIdentifier("prayer-pair-" + pair.rawValue) }; if travel.canEnd { Button("أنهِ الرحلة") { sheet = .endTrip }.frame(minHeight: 44).accessibilityIdentifier("prayer-end-trip") } } }
    }
    @ViewBuilder private func sheetBody(_ route: PrayerSheet) -> some View {
        if let state = model.state {
            switch route {
            case .log(let entry): PrayerLogSheet(entry: entry, model: model)
            case .history: PrayerHistorySheet(history: state.history, select: { sheet = .log($0) })
            case .hali: PrayerHaliSheet(state: state, select: { sheet = .log($0) })
            case .pending: PrayerPendingSheet(model: model, select: { sheet = .log($0) })
            case .qada: PrayerQadaSheet(model: model)
            case .qiyam: PrayerQiyamSheet(model: model)
            case .pair(let pair): PrayerPairSheet(model: model, pair: pair)
            case .endTrip: Form { Text("تبقى الصلوات التي سجّلتها كما هي. يعود الحساب لمدينتك من الفرض التالي."); Button("أنهِ الرحلة") { Task { if await model.perform(.endTrip) { sheet = nil } } }.accessibilityIdentifier("prayer-end-trip-confirm") }.navigationTitle("انتهاء الرحلة")
            }
        }
    }
    private func number(_ value: Int, _ state: PrayerRoomState) -> String { value.formatted(.number.locale(Locale(identifier: state.numeralLocale))) }
    private func statusColor(_ status: PrayerUIStatus) -> Color { status == .missed ? theme.color("missed") : status == .future || status == .pending || status == .unrecordedHistory ? theme.secondaryInk : theme.accent }
}
private enum PrayerSheet: Identifiable { case log(PrayerUIEntry), history, hali, pending, qada, qiyam, pair(PrayerUIPair), endTrip; var id: String { switch self { case .log(let entry): "log-" + entry.id; case .history: "history"; case .hali: "hali"; case .pending: "pending"; case .qada: "qada"; case .qiyam: "qiyam"; case .pair(let pair): pair.rawValue; case .endTrip: "endTrip" } } }

private struct PrayerLogSheet: View {
    let entry: PrayerUIEntry
    @Bindable var model: PrayerRoomModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var status: PrayerUIStatus
    @State private var heart: PrayerUIHeart?
    @State private var shortened: Bool
    @State private var fridayKind: FridayPrayerKind?
    @State private var savedMissed = false
    init(entry: PrayerUIEntry, model: PrayerRoomModel) { self.entry = entry; self.model = model; _status = State(initialValue: [.jamaah, .alone, .qada, .missed].contains(entry.status) ? entry.status : .jamaah); _heart = State(initialValue: entry.heart); _shortened = State(initialValue: entry.shortened); _fridayKind = State(initialValue: entry.isFriday && entry.status == .alone ? .dhuhr : entry.fridayKind) }
    var body: some View {
        Form {
                Section { Text(entry.title).font(MadarTypography.title()); if let time = entry.timeLabel { Text(time) } }
                if entry.canLog && !savedMissed {
                    Section("كيف صلّيت؟") {
                        ForEach([PrayerUIStatus.jamaah, .alone, .qada, .missed], id: \.self) { option in
                            if option != .qada || entry.canMakeUp { Button { status = option; if entry.isFriday && option == .alone { fridayKind = .dhuhr } } label: { HStack { Text(option == .qada ? "قضاءً · بعد وقتها" : option.title); Spacer(); if status == option { Image(systemName: "checkmark") } } }.accessibilityAddTraits(status == option ? .isSelected : []).accessibilityIdentifier("prayer-log-status-" + option.rawValue) }
                        }
                        if entry.isFriday {
                            Picker("نوع صلاة الجمعة", selection: $fridayKind) {
                                Text("اختر التصنيف").tag(nil as FridayPrayerKind?)
                                if status != .alone { Text("صلاة الجمعة").tag(FridayPrayerKind?.some(.jumuah)) }
                                Text("الظهر").tag(FridayPrayerKind?.some(.dhuhr))
                            }.accessibilityIdentifier("prayer-friday-kind")
                        }
                        if entry.canShorten && [.jamaah, .alone].contains(status) { Toggle(entry.isFriday ? "الظهر قصرًا" : "قصر", isOn: $shortened).accessibilityIdentifier("prayer-log-shortened"); if entry.isFriday { Text("اختيارك يحدّد التسجيل: الجمعة جماعة بلا قصر، أو الظهر قصرًا.").font(MadarTypography.caption()) } }
                    }
                }
                if status == .missed || savedMissed {
                    Section { Text("وهي عليك حتى تصلّيها").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("missedText")); PrayerQadaCitation() }
                    if savedMissed || (entry.status == .missed && status == .missed && entry.canMakeUp) { Button("قضيتُها الآن") { Task { if await model.perform(.makeUp(entry.selection, fridayKind: fridayKind ?? entry.fridayKind)) { dismiss() } } }.disabled(entry.isFriday && (fridayKind ?? entry.fridayKind) == nil).accessibilityIdentifier("prayer-makeup-now"); Button("لاحقًا") { dismiss() } }
                } else if model.state?.askHeart == true && (entry.canLog || [.jamaah, .alone, .qada].contains(entry.status)) {
                    Section("وكيف كان قلبك فيها؟ · اختياري") {
                        ForEach(PrayerUIHeart.allCases) { option in Button { heart = option } label: { HStack { VStack(alignment: .leading) { Text(option.title); Text(option.sentence).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }; Spacer(); if heart == option { Image(systemName: "checkmark") } } }.accessibilityAddTraits(heart == option ? .isSelected : []).accessibilityIdentifier("prayer-heart-" + option.rawValue) }
                        Button("أمرُّ") { heart = nil }.accessibilityIdentifier("prayer-heart-skip")
                    }
                }
                if !savedMissed {
                    if entry.canLog { Button("احفظ التسجيل") { Task { let command = PrayerUICommand.log(entry.selection, status: status, heart: status == .missed ? nil : heart, shortened: [.jamaah, .alone].contains(status) && shortened, fridayKind: entry.isFriday ? fridayKind : nil); if await model.perform(command) { if status == .missed { savedMissed = true } else { dismiss() } } } }.disabled(entry.isFriday && fridayKind == nil).accessibilityIdentifier("prayer-log-save") }
                    else if [.jamaah, .alone, .qada].contains(entry.status), model.state?.askHeart == true { Button("احفظ جواب القلب") { Task { if await model.perform(.setHeart(entry.selection, heart: heart)) { dismiss() } } }.accessibilityIdentifier("prayer-heart-save") }
                    else { Text("لم يحن وقت هذه الصلاة.").foregroundStyle(theme.secondaryInk) }
                    if entry.canClear { Button("امسح التسجيل", role: .destructive) { Task { if await model.perform(.clear(entry.selection)) { dismiss() } } }.accessibilityIdentifier("prayer-log-clear") }
                }
            }.font(MadarTypography.body()).disabled(model.busy).navigationTitle("تسجيل الصلاة")
    }
}

private struct PrayerHistorySheet: View {
    let history: [PrayerUIHistoryDay]
    let select: (PrayerUIEntry) -> Void
    var body: some View {
        List { if history.isEmpty { Text("لا سجلّ قبل بداية التتبّع.") }; ForEach(history) { day in Section(day.title) { ForEach(day.entries) { entry in Button { select(entry) } label: { VStack(alignment: .leading, spacing: 5) { Text(entry.title + " · " + entry.status.title); if let heart = entry.heart { Text(heart.title).font(MadarTypography.caption()) } } }.accessibilityIdentifier("prayer-history-" + entry.id) } } } }.navigationTitle("سجلّ الصلاة").font(MadarTypography.body())
    }
}
private struct PrayerHaliSheet: View {
    let state: PrayerRoomState
    let select: (PrayerUIEntry) -> Void
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 20) { if let summary = state.summary { MadarCard { VStack(alignment: .leading, spacing: 12) { Text(summary.percentageLabel ?? "لا نسبة بعد").font(MadarTypography.title()); Text(summary.monthTitle); PrayerBalance(summary: summary, style: state.balanceView, locale: state.numeralLocale); Text(summary.prayerStreakLabel); if let mosque = summary.mosqueStreakLabel { Text(mosque) }; Text(summary.madeUpLabel) } }; MadarCard { VStack(alignment: .leading, spacing: 12) { Text("التزامك بكل صلاة").font(MadarTypography.section()); ForEach(Array(summary.commitment.enumerated()), id: \.offset) { _, text in Text(text) } } }; MadarCard { VStack(alignment: .leading, spacing: 12) { Text("حضور القلب").font(MadarTypography.section()); if summary.heartSentences.isEmpty { Text("سجّل ما شعرت به حين تختار الإجابة.") }; ForEach(Array(summary.heartSentences.enumerated()), id: \.offset) { _, sentence in Text(sentence) } } }; NavigationLink("سجلّ الشهر") { PrayerHistorySheet(history: state.history, select: select) }.frame(minHeight: 44) } }.padding(16) }.navigationTitle("حالي").font(MadarTypography.body())
    }
}
private struct PrayerPendingSheet: View {
    @Bindable var model: PrayerRoomModel
    let select: (PrayerUIEntry) -> Void
    @State private var selected = Set<PrayerUISelection>()
    @State private var confirm = false
    var body: some View {
        List { Section { Text("سجّل ما تتذكّره. اختيار «لم أسجّل هذه الفترة» يترك الفروض المحدّدة خارج القضاء والنسبة والسلسلة.") }; ForEach(model.state?.pending ?? []) { entry in HStack { Toggle(isOn: Binding(get: { selected.contains(entry.selection) }, set: { if $0 { selected.insert(entry.selection) } else { selected.remove(entry.selection) } })) { Text(entry.selection.dayKey + "، " + entry.title) }; Button("سجّل") { select(entry) }.accessibilityIdentifier("prayer-pending-log-" + entry.id) } }; Button("لم أسجّل هذه الفترة") { confirm = true }.disabled(selected.isEmpty).accessibilityIdentifier("prayer-unrecorded") }
            .navigationTitle("صلوات معلّقة").font(MadarTypography.body()).disabled(model.busy)
            .confirmationDialog("اترك الفروض المحدّدة بلا سجل؟", isPresented: $confirm, titleVisibility: .visible) { Button("لم أسجّل هذه الفترة") { Task { if await model.perform(.markUnrecorded(Array(selected))) { selected.removeAll() } } } } message: { Text("لا تُعدّ فائتة، ويمكنك التراجع بعد الحفظ.") }
    }
}
private struct PrayerQadaSheet: View {
    @Bindable var model: PrayerRoomModel
    @State private var addingOld = false
    @State private var day: Date = .now
    @State private var prayer: PrayerUICode = .fajr
    @State private var fridayKinds: [PrayerUISelection: FridayPrayerKind] = [:]
    @State private var oldFridayKind: FridayPrayerKind?
    private var oldMissedIsFriday: Bool {
        guard prayer == .dhuhr, let state = model.state,
              let zone = TimeZone(identifier: state.timeZoneID) else { return false }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        return calendar.component(.weekday, from: day) == 6
    }
    var body: some View {
        Form {
            PrayerQadaCitation()
            if model.state?.qada.isEmpty == true { Text("لا فوائت مسجّلة عليك.") }
            ForEach(model.state?.qada ?? []) { item in
                VStack(alignment: .leading, spacing: 10) {
                    Text(item.title + "، " + item.dateLabel)
                    if item.isFriday && item.fridayKind == nil {
                        Picker("نوع صلاة الجمعة", selection: Binding(get: { fridayKinds[item.selection] }, set: { value in
                            if let value { fridayKinds[item.selection] = value } else { fridayKinds.removeValue(forKey: item.selection) }
                        })) {
                            Text("اختر التصنيف").tag(nil as FridayPrayerKind?)
                            Text("صلاة الجمعة").tag(FridayPrayerKind?.some(.jumuah))
                            Text("الظهر").tag(FridayPrayerKind?.some(.dhuhr))
                        }
                    }
                    Button("قضيتُها") { Task { _ = await model.perform(.makeUp(item.selection, fridayKind: item.fridayKind ?? fridayKinds[item.selection])) } }
                        .disabled(item.isFriday && item.fridayKind == nil && fridayKinds[item.selection] == nil)
                        .accessibilityIdentifier("prayer-qada-makeup-" + item.id)
                }
            }
            Button("أضِف فائتة قديمة") { if let state = model.state { day = state.oldMissedDefault }; oldFridayKind = nil; addingOld = true }.accessibilityIdentifier("prayer-add-old-missed")
            if addingOld, let state = model.state {
                Section("فائتة أضيفها صراحة") {
                    DatePicker("اليوم", selection: $day, in: state.oldMissedEarliest...state.oldMissedLatest, displayedComponents: .date)
                        .environment(\.timeZone, TimeZone(identifier: state.timeZoneID) ?? .gmt)
                        .onChange(of: day) { _, _ in oldFridayKind = nil }
                    Picker("الصلاة", selection: $prayer) { ForEach(PrayerUICode.allCases) { Text($0.title).tag($0) } }
                        .onChange(of: prayer) { _, _ in oldFridayKind = nil }
                    if oldMissedIsFriday {
                        Picker("نوع صلاة الجمعة", selection: $oldFridayKind) {
                            Text("اختر التصنيف").tag(nil as FridayPrayerKind?)
                            Text("صلاة الجمعة").tag(FridayPrayerKind?.some(.jumuah))
                            Text("الظهر").tag(FridayPrayerKind?.some(.dhuhr))
                        }
                    }
                    Button("أضِف الفائتة") { Task { if await model.perform(.addOldMissed(day: day, prayer: prayer, fridayKind: oldMissedIsFriday ? oldFridayKind : nil)) { addingOld = false } } }
                        .disabled(oldMissedIsFriday && oldFridayKind == nil)
                        .accessibilityIdentifier("prayer-add-old-confirm")
                }
            }
        }.navigationTitle("القضاء").font(MadarTypography.body()).disabled(model.busy)
    }
}
private struct PrayerQiyamSheet: View {
    @Bindable var model: PrayerRoomModel
    @State private var nightKey = ""
    @State private var rakaat = 0
    @State private var witr = false
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Form { Section { Picker("الليلة", selection: $nightKey) { ForEach(model.state?.nights ?? []) { Text($0.title).tag($0.nightKey) } }.accessibilityIdentifier("prayer-qiyam-night"); Stepper("الركعات: \(rakaat)", value: $rakaat, in: 0...100, step: 2).accessibilityIdentifier("prayer-qiyam-rakaat"); Toggle("أوترتُ", isOn: $witr).accessibilityIdentifier("prayer-qiyam-witr"); Button("احفظ قيام الليلة") { Task { if await model.perform(.saveQiyam(nightKey: nightKey, rakaat: rakaat, witr: witr)) { dismiss() } } }.disabled(nightKey.isEmpty).accessibilityIdentifier("prayer-qiyam-save") }; Section("آخر ثلاثين ليلة") { ScrollView(.horizontal) { HStack(spacing: 5) { ForEach(model.state?.nightFootprint ?? []) { night in RoundedRectangle(cornerRadius: 4).fill(night.rakaat > 0 || night.witr ? theme.accent : theme.line).frame(width: 10, height: 24).accessibilityLabel(night.title + (night.rakaat > 0 || night.witr ? "، قيام مسجّل" : "، بلا تسجيل")) } } }; Text("ليس سلسلة تنكسر، أثرٌ يُرى."); Text("التسجيل هنا للركعات والوتر؛ لا يكتب أوجهًا أو مراجعة قرآن.").font(MadarTypography.caption()) } }.navigationTitle("قيام الليل").font(MadarTypography.body()).disabled(model.busy).onAppear { if let first = model.state?.nights.first { nightKey = first.nightKey; rakaat = first.rakaat; witr = first.witr } }.onChange(of: nightKey) { _, key in if let night = model.state?.nights.first(where: { $0.nightKey == key }) { rakaat = night.rakaat; witr = night.witr } }
    }
}
private struct PrayerPairSheet: View {
    @Bindable var model: PrayerRoomModel
    let pair: PrayerUIPair
    @State private var status: PrayerUIStatus = .jamaah
    @State private var mode: PrayerUIPairMode = .taqdim
    @State private var shortened = false
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        Form { Text("يُسجّل الفرضان معًا في يوم الصلاة نفسه. اختيارك يصف ما صلّيته."); Picker("الحال", selection: $status) { Text("في جماعة").tag(PrayerUIStatus.jamaah); Text("وحدي").tag(PrayerUIStatus.alone) }; Picker("الجمع", selection: $mode) { ForEach(PrayerUIPairMode.allCases) { Text($0.title).tag($0) } }; Toggle(pair == .dhuhrAsr ? "قصر الظهر والعصر" : "قصر العشاء وحدها", isOn: $shortened); Button("احفظ الصلاتين") { guard let key = model.state?.dayKey else { return }; Task { if await model.perform(.logPair(dayKey: key, pair: pair, status: status, mode: mode, shortened: shortened)) { dismiss() } } }.accessibilityIdentifier("prayer-pair-save") }.navigationTitle(pair.title).font(MadarTypography.body()).disabled(model.busy)
    }
}

struct PrayerQadaCitation: View {
    @State private var index = 0
    private let citations = [
        ("«مَنْ نَسِيَ صَلَاةً فَلْيُصَلِّ إِذَا ذَكَرَهَا، لَا كَفَّارَةَ لَهَا إِلَّا ذَلِكَ»، ﴿وَأَقِمِ الصَّلَاةَ لِذِكْرِي﴾", "متفق عليه، البخاري ٥٩٧ ومسلم ٦٨٤"),
        ("مَنْ نَسِيَ صَلَاةً أَوْ نَامَ عَنْهَا فَكَفَّارَتُهَا أَنْ يُصَلِّيَهَا إِذَا ذَكَرَهَا", "مسلم ٦٨٤"),
        ("﴿حَافِظُوا عَلَى الصَّلَوَاتِ وَالصَّلَاةِ الْوُسْطَىٰ وَقُومُوا لِلَّهِ قَانِتِينَ﴾", "البقرة ٢٣٨")
    ]
    var body: some View { Button { index = (index + 1) % citations.count } label: { VStack(alignment: .leading, spacing: 8) { Text(citations[index].0).font(.custom("Amiri-Regular", size: 21, relativeTo: .title3)).fixedSize(horizontal: false, vertical: true); Text(citations[index].1).font(MadarTypography.caption()) } }.buttonStyle(.plain).accessibilityHint("لمسة تعرض نصًا آخر موثّقًا") }
}
struct PrayerStar: Shape {
    func path(in rect: CGRect) -> Path {
        var p = Path(); let center = CGPoint(x: rect.midX, y: rect.midY); let radius = min(rect.width, rect.height) / 2
        for n in 0..<16 { let angle = Double(n) * .pi / 8 - .pi / 2; let r = radius * (n.isMultiple(of: 2) ? 1 : 0.44); let point = CGPoint(x: center.x + cos(angle) * r, y: center.y + sin(angle) * r); if n == 0 { p.move(to: point) } else { p.addLine(to: point) } }; p.closeSubpath(); return p
    }
}
struct PrayerHorseshoe: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        let radius = rect.width / 2
        let center = CGPoint(x: rect.midX, y: rect.minY + radius)
        let shoulder = center.y + radius * 0.5
        let left = rect.minX + rect.width * 0.067
        let right = rect.maxX - rect.width * 0.067

        path.move(to: CGPoint(x: left, y: rect.maxY))
        path.addLine(to: CGPoint(x: left, y: shoulder))
        path.addArc(center: center, radius: radius, startAngle: .degrees(150), endAngle: .degrees(390), clockwise: false)
        path.addLine(to: CGPoint(x: right, y: rect.maxY))
        // The fill closes this contour implicitly; the stroke stays open where the feet meet the waterline.
        return path
    }
}
private struct PrayerArchView: View {
    let entry: PrayerUIEntry
    let pool: Bool
    let tall: Bool
    @Environment(\.roomTheme) private var theme
    private var color: Color { entry.status == .missed ? theme.color("missed") : entry.status == .future || entry.status == .pending || entry.status == .unrecordedHistory || entry.status == .qada ? theme.secondaryInk : theme.accent }
    var body: some View {
        VStack(spacing: 5) {
            ZStack { PrayerHorseshoe().fill(entry.status == .jamaah || entry.status == .alone ? theme.color("goldSoft") : .clear); PrayerHorseshoe().stroke(entry.isNext ? theme.accent : theme.line, style: StrokeStyle(lineWidth: entry.isNext ? 3 : 1, dash: entry.status == .pending ? [3, 3] : [])); VStack { PrayerLattice().frame(height: 56).clipShape(PrayerHorseshoe()); Spacer() }; if entry.status == .pending || entry.status == .future || entry.status == .unrecordedHistory { Capsule().fill(color).frame(width: 12, height: 2).opacity(entry.status == .pending ? 0.7 : 0.25) } else { PrayerStar().fill(entry.status == .missed ? .clear : entry.status == .alone ? theme.color("goldMid") : color).overlay { if entry.status == .alone || entry.status == .missed { PrayerStar().stroke(color, lineWidth: 1) } }.frame(width: 16, height: 16) } }.frame(height: tall ? 112 : 100)
            if pool { PrayerHorseshoe().stroke(theme.accent, lineWidth: 1).scaleEffect(x: 1, y: -1).opacity(0.28).frame(height: tall ? 56 : 50).overlay { VStack(spacing: 6) { ForEach(0..<7, id: \.self) { _ in Rectangle().fill(theme.background.opacity(0.8)).frame(height: 1) } } }.accessibilityHidden(true) }
            Text(entry.title).font(MadarTypography.section()).lineLimit(1).minimumScaleFactor(0.8)
            Text(entry.timeLabel ?? "—").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Text(entry.status.title).font(MadarTypography.fine()).foregroundStyle(entry.status == .missed ? theme.color("missedTextOnSurface") : theme.secondaryInk)
            if entry.estimated { Image(systemName: "info.circle").font(.caption2).accessibilityLabel("وقت تقديري") }
        }.frame(maxWidth: .infinity)
    }
}
private struct PrayerBeads: View {
    let beads: [PrayerUIBead]
    let locale: String
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    var body: some View {
        if typeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) { ForEach(beads.suffix(25)) { bead in Text(bead.accessibilityLabel).font(MadarTypography.caption()) } }
        } else {
            GeometryReader { geometry in
                ZStack { ForEach(Array(beads.suffix(25).enumerated()), id: \.element.id) { index, bead in
                    let angle = -Double(index) * 10 * .pi / 180 + .pi / 6
                    let radius = min(geometry.size.width * 0.42, 90)
                    Circle().fill(bead.status == .jamaah ? theme.accent : bead.status == .alone ? theme.color("goldMid") : .clear).overlay { Circle().stroke(bead.status == .missed ? theme.color("missed") : theme.line, style: StrokeStyle(lineWidth: 1, dash: bead.status == .pending ? [2, 2] : [])) }.frame(width: index == beads.suffix(25).count - 1 ? 12 : 9, height: index == beads.suffix(25).count - 1 ? 12 : 9).position(x: geometry.size.width / 2 + cos(angle) * radius, y: 90 + sin(angle) * radius).accessibilityLabel(bead.accessibilityLabel)
                } }
            }.frame(height: 190)
        }
    }
}

private struct PrayerBalance: View {
    let summary: PrayerUISummary
    let style: String
    let locale: String
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var size
    var body: some View {
        if style == "scale" {
            VStack(spacing: 12) {
                if !size.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 20) {
                        scalePan(count: summary.onTime, title: "في وقتها", color: theme.accent)
                        Rectangle().fill(theme.accent).frame(width: 2, height: 70).overlay(alignment: .top) { Rectangle().fill(theme.accent).frame(width: 150, height: 2) }.padding(.top, 8)
                        scalePan(count: max(0, summary.denominator - summary.onTime), title: "بعد الوقت أو فائتة", color: theme.color("missed"))
                    }.accessibilityHidden(true)
                }
                Text(number(summary.onTime) + " في وقتها من " + number(summary.denominator) + " فرضًا محسوبًا").font(MadarTypography.caption())
            }
        } else if style == "miniRiwaq" {
            VStack(alignment: .leading, spacing: 10) {
                Text("آخر الفروض · رواق مصغّر").font(MadarTypography.caption())
                if size.isAccessibilitySize { ForEach(summary.beads.suffix(25)) { Text($0.accessibilityLabel) } }
                else { LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 8), count: 5), spacing: 12) { ForEach(summary.beads.suffix(25)) { bead in PrayerHorseshoe().fill(bead.status == .jamaah ? theme.accent : bead.status == .alone ? theme.color("goldMid") : .clear).overlay { PrayerHorseshoe().stroke(bead.status == .missed ? theme.color("missed") : theme.line, style: StrokeStyle(lineWidth: 1, dash: bead.status == .pending ? [3, 2] : [])) }.frame(height: 35).accessibilityLabel(bead.accessibilityLabel) } } }
            }
        } else { PrayerBeads(beads: summary.beads, locale: locale) }
    }
    private func number(_ n: Int) -> String { n.formatted(.number.locale(Locale(identifier: locale))) }
    private func scalePan(count: Int, title: String, color: Color) -> some View { VStack(spacing: 8) { Text(number(count)).font(MadarTypography.cardTitle()); Text(title).font(MadarTypography.fine()); Capsule().stroke(color, lineWidth: 2).frame(height: 14) }.frame(maxWidth: .infinity).padding(.top, 14) }
}
private struct PrayerLattice: View {
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Canvas { context, size in
            var path = Path()
            for x in stride(from: -size.height, through: size.width + size.height, by: 8) {
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x + size.height * 0.6, y: size.height))
                path.move(to: CGPoint(x: x, y: 0)); path.addLine(to: CGPoint(x: x - size.height * 0.6, y: size.height))
            }
            context.stroke(path, with: .color(theme.line), lineWidth: 0.6)
        }.accessibilityHidden(true)
    }
}
