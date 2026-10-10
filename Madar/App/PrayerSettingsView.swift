import SwiftUI
import Observation
import MadarData
import MadarDesign

struct PrayerTrackingUIState: Sendable {
    var title: String
    var date: Date
    var earliestDate: Date
    var latestDate: Date
    var canEdit: Bool
}
struct PrayerNotificationUIState: Sendable {
    var title: String
    var explanation: String
    var canRequest: Bool
    var canOpenSystemSettings: Bool
    var liveActivityMessage: String?
}
struct PrayerSettingsUIState: Sendable {
    var definitions: [SettingDefinition]
    var values: [String: MadarData.JSONValue]
    var supportedKeys: Set<String> // actual connected service features only
    var blockOrder: [String]
    var hiddenBlocks: Set<String>
    var tracking: PrayerTrackingUIState
    var notifications: PrayerNotificationUIState
    var timeZoneID: String
}
@MainActor protocol PrayerSettingsUIService: AnyObject {
    func loadSettings() async throws -> PrayerSettingsUIState
    func set(_ value: MadarData.JSONValue, for key: String) async throws
    func setLayout(blocks: [String], hidden: Set<String>) async throws
    func changeTrackingStart(to date: Date) async throws
    func requestNotifications() async throws
    func openSystemSettings() async throws
    func resetSettings() async throws // excludes trackingStart, no data reset
}
@MainActor @Observable final class PrayerSettingsModel {
    let service: any PrayerSettingsUIService
    var state: PrayerSettingsUIState?
    var busy = false
    var error: String?
    init(service: any PrayerSettingsUIService) { self.service = service }
    func refresh() async { guard !busy else { return }; do { state = try await service.loadSettings() } catch { self.error = error.localizedDescription } }
    func run(_ operation: @MainActor () async throws -> Void) async {
        guard !busy else { return }; error = nil; busy = true; defer { busy = false }
        do { try await operation() } catch { self.error = error.localizedDescription; return }
        do { state = try await service.loadSettings() } catch { state = nil; self.error = "حُفظ التغيير، وتعذّرت إعادة قراءة الإعدادات: " + error.localizedDescription }
    }
    func set(_ value: MadarData.JSONValue, key: String) { Task { await run { try await service.set(value, for: key) } } }
    func value(_ definition: SettingDefinition) -> MadarData.JSONValue { state?.values[definition.key] ?? definition.defaultValue }
}
struct PrayerSettingsView: View {
    @State private var model: PrayerSettingsModel
    @State private var trackingDate: Date = .now
    @State private var editingTracking = false
    @State private var confirmTracking = false
    @State private var confirmReset = false
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomTheme) private var theme
    init(service: any PrayerSettingsUIService) { _model = State(initialValue: PrayerSettingsModel(service: service)) }
    var body: some View {
        Form {
            if let state = model.state {
                Section("ترتيب الرئيسية") {
                    ForEach(state.blockOrder, id: \.self) { key in
                        HStack {
                            if ["next", "riwaq"].contains(key) { Label(blockTitle(key), systemImage: "pin.fill") }
                            else { Toggle(blockTitle(key), isOn: Binding(get: { !state.hiddenBlocks.contains(key) }, set: { visible in var hidden = state.hiddenBlocks; if visible { hidden.remove(key) } else { hidden.insert(key) }; Task { await model.run { try await model.service.setLayout(blocks: state.blockOrder, hidden: hidden) } } })).accessibilityIdentifier("prayer-block-" + key) }
                        }.frame(minHeight: 44)
                    }.onMove { indexes, destination in var order = state.blockOrder; order.move(fromOffsets: indexes, toOffset: destination); Task { await model.run { try await model.service.setLayout(blocks: order, hidden: state.hiddenBlocks) } } }
                    Text("الصلاة القادمة والرواق ظاهران دائمًا.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                ForEach(["الرواق والميزان", "التسجيل", "المواقيت", "التذكير"], id: \.self) { section in
                    Section(section) { ForEach(definitions(section, state: state), id: \.key) { definition in setting(definition) } }
                }
                Section("بداية التتبّع") {
                    Text(state.tracking.title)
                    Text("ما قبل هذا اليوم لا يُعدّ معلّقًا أو فائتًا. يمكنك تعديل البداية مرة واحدة، حتى ثلاثين يومًا قبل أول تشغيل.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    if state.tracking.canEdit {
                        Button("عدّل بداية التتبّع") { trackingDate = state.tracking.date; editingTracking = true }.accessibilityIdentifier("prayer-tracking-edit")
                        if editingTracking { DatePicker("البداية", selection: $trackingDate, in: state.tracking.earliestDate...state.tracking.latestDate, displayedComponents: .date).environment(\.timeZone, TimeZone(identifier: state.timeZoneID) ?? .gmt).accessibilityIdentifier("prayer-tracking-date"); Button("احفظ التعديل الوحيد") { confirmTracking = true }.accessibilityIdentifier("prayer-tracking-save") }
                    } else { Text("اكتمل التعديل الوحيد لبداية التتبّع.").font(MadarTypography.caption()) }
                }
                Section("إذن الإشعارات") {
                    Text(state.notifications.title).accessibilityIdentifier("prayer-notification-state")
                    Text(state.notifications.explanation).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    if state.notifications.canRequest { Button("اسمح بتذكير الصلاة") { Task { await model.run { try await model.service.requestNotifications() } } }.accessibilityIdentifier("prayer-request-notifications") }
                    if state.notifications.canOpenSystemSettings { Button("افتح إعدادات النظام") { Task { await model.run { try await model.service.openSystemSettings() } } }.accessibilityIdentifier("prayer-notification-system-settings") }
                    if let message = state.notifications.liveActivityMessage { Text(message).font(MadarTypography.caption()) }
                    Text("لا يصدر تذكير قبل انتهاء حرمة الصلاة. إيقاف السؤال يلغي أسئلته المعلّقة؛ يبقى التسجيل من التطبيق متاحًا.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
                Button("أعِد إعدادات الصلاة المتفق عليها") { confirmReset = true }.accessibilityIdentifier("prayer-settings-reset")
            } else { ContentUnavailableView("إعدادات الصلاة", systemImage: "slider.horizontal.3", description: Text("تُقرأ الإعدادات المحفوظة من هذا الجهاز.")); Button("حاول مجددًا") { Task { await model.refresh() } } }
        }
        .font(MadarTypography.body()).navigationTitle("خصّص الصلاة")
        .toolbar { ToolbarItem(placement: .topBarTrailing) { EditButton().accessibilityIdentifier("prayer-layout-edit") } }
        .disabled(model.busy).task { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .confirmationDialog("احفظ بداية التتبّع؟", isPresented: $confirmTracking, titleVisibility: .visible) { Button("احفظ التعديل الوحيد") { Task { await model.run { try await model.service.changeTrackingStart(to: trackingDate) }; if model.error == nil { editingTracking = false } } } } message: { Text("بعد نجاح الحفظ لن يُقبل تعديل آخر للبداية. الأيام المضافة تبدأ مهلة تعليقها من يوم التعديل.") }
        .confirmationDialog("أعِد إعدادات الصلاة؟", isPresented: $confirmReset, titleVisibility: .visible) { Button("أعِد المتفق عليه", role: .destructive) { Task { await model.run { try await model.service.resetSettings() } } } } message: { Text("تعود إعدادات الشكل والمواقيت والتذكير. سجلّك وبداية التتبّع محفوظان.") }
        .alert("تعذّر حفظ الإعداد", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") }
    }
    private func definitions(_ section: String, state: PrayerSettingsUIState) -> [SettingDefinition] {
        let keys: [String]
        switch section {
        case "الرواق والميزان": keys = ["salah.pool", "salah.balanceView", "salah.fridayTallArch", "salah.showMosqueStreak"]
        case "التسجيل": keys = ["salah.askHeart", "salah.pendingDays"]
        case "المواقيت": keys = ["salah.method", "salah.asr", "salah.highLatitudeRule", "salah.offsets", "salah.travelShortenCombine"]
        default: keys = ["salah.askAfterAdhanMin", "salah.askReminder", "salah.qadaReminder", "salah.liveActivity"]
        }
        return keys.compactMap { key in state.supportedKeys.contains(key) ? state.definitions.first(where: { $0.key == key }) : nil }
    }
    @ViewBuilder private func setting(_ definition: SettingDefinition) -> some View {
        switch definition.type {
        case "bool": Toggle(definition.title, isOn: Binding(get: { model.value(definition) == .bool(true) }, set: { model.set(.bool($0), key: definition.key) })).accessibilityIdentifier("prayer-setting-" + definition.key)
        case "choice": VStack(alignment: .leading, spacing: 8) { Text(definition.title).font(MadarTypography.section()); ForEach(Array(definition.options.enumerated()), id: \.offset) { _, option in Button { model.set(option.value, key: definition.key) } label: { HStack { Text(option.label); Spacer(); if model.value(definition) == option.value { Image(systemName: "checkmark") } }.frame(minHeight: 44) }.accessibilityAddTraits(model.value(definition) == option.value ? .isSelected : []).accessibilityIdentifier("prayer-option-" + definition.key + "-" + optionCode(option.value)) } }
        case "int": Stepper(value: Binding(get: { if case .number(let n) = model.value(definition) { return Int(n) }; return 0 }, set: { model.set(.number(Double($0)), key: definition.key) }), in: Int(definition.range?.first ?? 0)...Int(definition.range?.last ?? 100)) { Text(definition.title); if case .number(let n) = model.value(definition) { Text(Int(n), format: .number) } }.accessibilityIdentifier("prayer-setting-" + definition.key)
        case "map": VStack(alignment: .leading, spacing: 12) { Text(definition.title).font(MadarTypography.section()); ForEach(PrayerUICode.allCases) { prayer in Stepper(value: Binding(get: { if case .object(let map) = model.value(definition), case .number(let n) = map[prayer.rawValue] { return Int(n) }; return 0 }, set: { n in guard case .object(var map) = model.value(definition) else { return }; map[prayer.rawValue] = .number(Double(n)); model.set(.object(map), key: definition.key) }), in: -60...60) { Text(prayer.title); Text(offset(prayer.rawValue, definition: definition), format: .number) }.accessibilityIdentifier("prayer-offset-" + prayer.rawValue) } }
        default: EmptyView()
        }
    }
    private func offset(_ prayer: String, definition: SettingDefinition) -> Int { if case .object(let map) = model.value(definition), case .number(let n) = map[prayer] { return Int(n) }; return 0 }
    private func optionCode(_ value: MadarData.JSONValue) -> String { if case .string(let code) = value { return code }; return "value" }
    private func blockTitle(_ key: String) -> String { switch key { case "next": "الصلاة القادمة"; case "riwaq": "الرواق"; case "pending": "غير المسجّلة"; case "hali": "حالي"; case "qada": "القضاء"; case "qiyam": "قيام الليل"; default: key } }
}
