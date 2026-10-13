import SwiftUI
import MadarData
import MadarCore
import MadarPrayer
import MadarDesign

/// `salah.layout` for the prayer home: the order and visibility of the movable blocks.
/// «الصلاة القادمة» and «الرواق» are pinned: they stay at the top and are never hidden.
struct PrayerHomeLayout: Equatable {
    static let pinned = ["next", "riwaq"]
    static let movable = ["pending", "hali", "qada", "qiyam"]
    var order: [String]
    var hidden: Set<String>

    init(_ value: MadarData.JSONValue?) {
        let blocks = value?.object?["blocks"]?.array?.compactMap(\.string) ?? []
        let hiddenIDs = value?.object?["hidden"]?.array?.compactMap(\.string) ?? []
        var ordered = blocks.filter { Self.movable.contains($0) }
        for key in Self.movable where !ordered.contains(key) { ordered.append(key) }
        order = ordered
        hidden = Set(hiddenIDs).intersection(Self.movable)
    }
    var visible: [String] { order.filter { !hidden.contains($0) } }
    var visibleCount: Int { Self.pinned.count + visible.count }
    var payload: MadarData.JSONValue {
        .object(["blocks": .array((Self.pinned + order).map { .string($0) }),
                 "pinned": .array(Self.pinned.map { .string($0) }),
                 "hidden": .array(order.filter { hidden.contains($0) }.map { .string($0) }),
                 "sizes": .object([:])])
    }
    func moved(_ key: String, by delta: Int) -> PrayerHomeLayout {
        var copy = self
        guard let index = order.firstIndex(of: key), order.indices.contains(index + delta) else { return self }
        copy.order.swapAt(index, index + delta)
        return copy
    }
    func toggled(_ key: String) -> PrayerHomeLayout {
        var copy = self
        if copy.hidden.contains(key) { copy.hidden.remove(key) } else { copy.hidden.insert(key) }
        return copy
    }
    static func title(_ key: String) -> String {
        switch key {
        case "next": "الصلاة القادمة"; case "riwaq": "الرواق"; case "pending": "تنبيه غير المسجّلة"
        case "hali": "حالي"; case "qada": "القضاء"; default: "قيام الليل"
        }
    }
    static func detail(_ key: String) -> String {
        switch key {
        case "next": "الاسم والوقت وكم بقي"; case "riwaq": "خمسة أقواس تمتلئ بحالها"
        case "pending": "يظهر حين تنتظر صلاة"; case "hali": "السبحة ونسبة الشهر والسلسلتان"
        case "qada": "الفوائت والتذكير بالنص"; default: "الركعات والوتر وأثر ٣٠ ليلة"
        }
    }
}

/// «خصّص الصلاة»: the room's own customization screen. Every control writes through `AppSession`.
struct PrayerCustomizeView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var inheritedTheme
    @State private var query = ""
    @State private var expanded: Set<String> = ["layout"]
    @State private var confirmReset = false
    @State private var editingStart = false
    @State private var confirmStart = false
    @State private var startDate = Date()

    private var theme: RoomTheme { RoomTheme(room: "salah", dark: inheritedTheme.dark, calmPaper: inheritedTheme.calmPaper) }
    private var layout: PrayerHomeLayout { PrayerHomeLayout(session.values["salah.layout"]) }
    private var salahKeys: [String] { ["salah.layout"] + AppSession.supportedKeys.filter { $0.hasPrefix("salah.") } }
    private func serif(_ size: CGFloat) -> Font { .custom("thmanyahserifdisplay-Bold", size: size, relativeTo: .title) }

    private struct CustomizeGroup: Identifiable {
        let id: String, title: String, symbol: String, keys: [String]
    }
    private let groups: [CustomizeGroup] = [
        .init(id: "riwaq", title: "الرواق والميزان", symbol: "paintpalette", keys: ["salah.showMosqueStreak"]),
        .init(id: "log", title: "التسجيل", symbol: "checkmark", keys: ["salah.askHeart"]),
        .init(id: "times", title: "المواقيت", symbol: "clock", keys: ["salah.method", "salah.asr", "salah.highLatitudeRule", "salah.offsets"]),
        .init(id: "remind", title: "التذكير", symbol: "bell", keys: ["salah.askReminder", "salah.askAfterAdhanMin", "salah.liveActivity"]),
    ]
    private func definitions(_ group: CustomizeGroup) -> [SettingDefinition] {
        group.keys.compactMap { key in AppSession.supportedKeys.contains(key) ? session.schema.settings.first { $0.key == key } : nil }
            .filter { query.isEmpty || normalized($0.title + " " + group.title).contains(normalized(query)) }
    }
    private func label(_ key: String) -> String {
        session.schema.settings.first { $0.key == key }?.options.first { $0.value == session.values[key] }?.label ?? ""
    }
    private func subtitle(_ group: CustomizeGroup) -> String {
        switch group.id {
        case "riwaq": return session.bool("salah.showMosqueStreak") ? "سلسلة المسجد ظاهرة" : "سلسلة المسجد مخفية"
        case "log": return session.bool("salah.askHeart") ? "اسألني عن القلب" : "بلا سؤال القلب"
        case "times": return label("salah.method") + " · " + label("salah.asr")
        default: return session.bool("salah.askReminder") ? "بعد الأذان بـ \(session.digits(Int(session.number("salah.askAfterAdhanMin")))) دقيقة" : "بلا تذكير"
        }
    }
    private var changedCount: Int {
        session.schema.settings.filter { salahKeys.contains($0.key) && session.value(for: $0) != $0.defaultValue }.count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                titleRow
                previewCard
                searchField
                if query.isEmpty || normalized("ترتيب الرئيسية").contains(normalized(query)) { layoutCard }
                ForEach(groups) { group in
                    let items = definitions(group)
                    if !items.isEmpty { groupCard(group, items) }
                }
                Text("حرمة الصلاة ليست هنا لأنها لا تُطفأ: من الأذان حتى انقضاء الصلاة لا يرسل مدار شيئًا.")
                    .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk).padding(.top, 4)
            }
            .padding(.horizontal, 20).padding(.top, 8).padding(.bottom, 40)
            .frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(theme.background).foregroundStyle(theme.ink)
        .environment(\.roomTheme, theme)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .confirmationDialog("أعِد إعدادات الصلاة؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("أعِد الافتراضي", role: .destructive) { session.reset(salahKeys) }
        } message: { Text("يعود الترتيب والمواقيت والتذكير. سجلّك وبداية التتبّع محفوظان.") }
    }

    // MARK: Parts

    private var titleRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Button { dismiss() } label: {
                HStack(spacing: 6) {
                    Image(systemName: "chevron.backward").font(.system(size: 14, weight: .semibold))
                    Text("الصلاة").font(PrayerHomeType.strong)
                }.frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("prayer-customize-back")
            Text("خصّص الصلاة").font(serif(40)).accessibilityAddTraits(.isHeader)
            Text("كل تعديل يُحفظ وحده").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
        }
    }

    private var previewCard: some View {
        PrayerPaperCard {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(Color(.systemGreen)).frame(width: 8, height: 8)
                        Text("معاينة حيّة").font(PrayerHomeType.smallBold).foregroundStyle(theme.color("accentText"))
                    }
                    Text("الصلاة كما ستظهر").font(serif(26))
                    previewLine("الأجزاء", "\(session.digits(layout.visibleCount)) ظاهرة")
                    previewLine("طريقة الحساب", label("salah.method"))
                    previewLine("وقت العصر", label("salah.asr"))
                    Text(changedCount == 0 ? "كما اتفقنا" : "عُدّل \(session.digits(changedCount)) من الإعدادات")
                        .font(PrayerHomeType.smallBold).foregroundStyle(theme.secondaryInk)
                        .accessibilityIdentifier("prayer-customize-changes")
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            Text("افتح الصلاة").font(PrayerHomeType.strong).foregroundStyle(theme.color("onAccent")).lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 16).frame(minHeight: 48)
                                .background(theme.ink, in: .rect(cornerRadius: 24))
                        }.buttonStyle(.plain).accessibilityIdentifier("prayer-customize-open")
                        Button { confirmReset = true } label: {
                            Text("أعِد الافتراضي").font(PrayerHomeType.strong).lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 12).frame(minHeight: 48)
                                .overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.ink.opacity(0.14), lineWidth: 1) }
                        }.buttonStyle(.plain).disabled(changedCount == 0).accessibilityIdentifier("prayer-customize-reset")
                    }
                }
                miniPhone
            }
        }
        .accessibilityIdentifier("prayer-customize-preview")
    }

    private func previewLine(_ title: String, _ value: String) -> some View {
        HStack { Text(title).foregroundStyle(theme.secondaryInk); Spacer(minLength: 8); Text(value).font(PrayerHomeType.strong) }
            .font(PrayerHomeType.body)
    }

    /// A shape-only sketch of the home: no text, so no size under 11 pt.
    private var miniPhone: some View {
        VStack(spacing: 6) {
            Capsule().fill(theme.ink.opacity(0.35)).frame(width: 36, height: 4).frame(maxWidth: .infinity, alignment: .trailing)
            ForEach(PrayerHomeLayout.pinned + layout.visible, id: \.self) { key in
                RoundedRectangle(cornerRadius: 8).fill(theme.surface)
                    .frame(maxWidth: .infinity, minHeight: key == "riwaq" ? 34 : 22, maxHeight: key == "riwaq" ? 34 : 22)
                    .overlay(alignment: .trailing) { Capsule().fill(theme.color("accentText").opacity(0.55)).frame(width: key == "next" ? 40 : 28, height: 4).padding(.trailing, 8) }
            }
            Spacer(minLength: 0)
        }
        .padding(8).frame(width: 104, height: 180)
        .overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.ink.opacity(0.25), lineWidth: 1.5) }
        .accessibilityHidden(true)
    }

    private var searchField: some View {
        HStack(spacing: 10) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
            TextField("ابحث: المواقيت، القلب، القضاء…", text: $query).font(PrayerHomeType.lead)
                .submitLabel(.search).accessibilityIdentifier("prayer-customize-search")
        }
        .padding(.horizontal, 18).frame(minHeight: 52)
        .overlay { Capsule().stroke(theme.ink.opacity(0.12), lineWidth: 1) }
    }

    private func card<Body: View>(_ id: String, title: String, subtitle: String, symbol: String, highlighted: Bool = false, @ViewBuilder body: () -> Body) -> some View {
        let open = expanded.contains(id) || !query.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Button { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(theme.color("accentText"))
                        .frame(width: 52, height: 52).background(theme.surface, in: .rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(serif(22))
                        Text(subtitle).font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(theme.secondaryInk)
                }.frame(minHeight: 56).contentShape(.rect)
            }.buttonStyle(.plain).accessibilityAddTraits(.isButton).accessibilityValue(open ? "مفتوح" : "مطوي")
                .accessibilityIdentifier("prayer-customize-card-" + id)
            if open { VStack(alignment: .leading, spacing: 0) { body() }.padding(.top, 12) }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(theme.color("card"), in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(highlighted && open ? theme.accent : theme.ink.opacity(0.1), lineWidth: highlighted && open ? 1.5 : 1) }
    }

    private var layoutCard: some View {
        card("layout", title: "ترتيب الرئيسية", subtitle: "\(session.digits(layout.visibleCount)) من \(session.digits(PrayerHomeLayout.pinned.count + PrayerHomeLayout.movable.count)) ظاهرة", symbol: "square.grid.2x2", highlighted: true) {
            Text("الصلاة القادمة والرواق ثابتان: هما جواب «ماذا الآن؟». الباقي يتقدّم ويتأخّر ويُخفى.")
                .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).padding(.bottom, 12)
            ForEach(PrayerHomeLayout.pinned, id: \.self) { key in
                Divider().overlay(theme.ink.opacity(0.1))
                blockRow(key, pinned: true)
            }
            ForEach(layout.order, id: \.self) { key in
                Divider().overlay(theme.ink.opacity(0.1))
                blockRow(key, pinned: false)
            }
        }
    }

    private func blockRow(_ key: String, pinned: Bool) -> some View {
        let index = layout.order.firstIndex(of: key)
        return HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                Text(PrayerHomeLayout.title(key)).font(PrayerHomeType.strong)
                Text(PrayerHomeLayout.detail(key)).font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            }
            Spacer(minLength: 6)
            if pinned {
                Text("ثابت").font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
            } else {
                arrow("chevron.up", id: "prayer-block-up-" + key, label: "قدّم " + PrayerHomeLayout.title(key), disabled: index == 0) { session.set(layout.moved(key, by: -1).payload, key: "salah.layout") }
                arrow("chevron.down", id: "prayer-block-down-" + key, label: "أخّر " + PrayerHomeLayout.title(key), disabled: index == nil || index == layout.order.count - 1) { session.set(layout.moved(key, by: 1).payload, key: "salah.layout") }
                Toggle(PrayerHomeLayout.title(key), isOn: Binding(get: { !layout.hidden.contains(key) }, set: { _ in session.set(layout.toggled(key).payload, key: "salah.layout") }))
                    .labelsHidden().tint(Color(.systemGreen)).accessibilityIdentifier("prayer-block-" + key)
            }
        }
        .padding(.vertical, 10).frame(minHeight: 60)
    }

    private func arrow(_ symbol: String, id: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.plain).disabled(disabled || session.settingsWriteInProgress).opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // MARK: Tracking start (P04)

    private var numeralLocale: Locale { Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab") }
    private func dateWords(_ day: GregorianDay) -> String {
        let zone = session.activePlace.timeZone
        let formatter = DateFormatter()
        formatter.locale = numeralLocale; formatter.timeZone = zone; formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "EEEE d MMMM yyyy"
        return formatter.string(from: day.date(in: zone).addingTimeInterval(12 * 3600))
    }
    @ViewBuilder private var trackingStartBlock: some View {
        if let tracking = try? session.prayerSnapshot(at: session.prayerNow()).tracking {
            let zone = session.activePlace.timeZone
            let earliest = tracking.firstRun.adding(days: -30).date(in: zone).addingTimeInterval(12 * 3600)
            let latest = tracking.firstRun.date(in: zone).addingTimeInterval(12 * 3600)
            VStack(alignment: .leading, spacing: 8) {
                Text("بداية التتبّع").font(PrayerHomeType.strong)
                Text(dateWords(tracking.day)).font(PrayerHomeType.body).accessibilityIdentifier("prayer-tracking-start")
                Text("ما قبل هذا اليوم لا يُعدّ معلّقًا ولا فائتًا أبدًا. يمكنك تقديم البداية مرة واحدة، حتى ثلاثين يومًا قبل أول تشغيل.")
                    .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                if tracking.edits == 0 {
                    if editingStart {
                        DatePicker("البداية", selection: $startDate, in: earliest...latest, displayedComponents: .date)
                            .environment(\.timeZone, zone)
                            .accessibilityIdentifier("prayer-tracking-date")
                        Button { confirmStart = true } label: {
                            Text("احفظ التعديل الوحيد").font(PrayerHomeType.strong).foregroundStyle(theme.color("onAccent"))
                                .padding(.horizontal, 20).frame(minHeight: 48).background(theme.ink, in: .rect(cornerRadius: 24))
                        }.buttonStyle(.plain).disabled(session.prayerWriteInProgress).accessibilityIdentifier("prayer-tracking-save")
                    } else {
                        Button { startDate = tracking.day.date(in: zone).addingTimeInterval(12 * 3600); editingStart = true } label: {
                            Text("عدّل بداية التتبّع").font(PrayerHomeType.strong).foregroundStyle(theme.color("accentText")).frame(minHeight: 44)
                        }.buttonStyle(.plain).accessibilityIdentifier("prayer-tracking-edit")
                    }
                } else {
                    Text("اكتمل التعديل الوحيد لبداية التتبّع.").font(PrayerHomeType.small).accessibilityIdentifier("prayer-tracking-done")
                }
            }
            .confirmationDialog("احفظ بداية التتبّع؟", isPresented: $confirmStart, titleVisibility: .visible) {
                Button("احفظ البداية") {
                    let day = GregorianDay.containing(startDate, in: zone)
                    session.editPrayerTrackingStart(day) { ok in if ok { editingStart = false } }
                }
            } message: { Text("بعد الحفظ لا يُقبل تعديل آخر للبداية. الأيام المضافة تبدأ مهلة تعليقها من اليوم.") }
        }
    }

    private func groupCard(_ group: CustomizeGroup, _ items: [SettingDefinition]) -> some View {
        card(group.id, title: group.title, subtitle: subtitle(group), symbol: group.symbol) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(items, id: \.key) { definition in
                    Divider().overlay(theme.ink.opacity(0.1))
                    SettingControl(definition: definition, session: session)
                }
                if group.id == "log", query.isEmpty { Divider().overlay(theme.ink.opacity(0.1)); trackingStartBlock }
                if group.id == "remind" && session.bool("salah.askReminder") && !session.notificationsAuthorized {
                    Divider().overlay(theme.ink.opacity(0.1))
                    Text(session.notificationPermissionTitle).font(PrayerHomeType.body)
                    if session.canRequestNotificationPermission {
                        Button("اسمح بإشعارات الصلاة") { session.requestPrayerNotificationPermission() }
                            .frame(minHeight: 44).accessibilityIdentifier("prayer-notification-permission-request")
                    } else if session.shouldOpenNotificationSettings {
                        Button("افتح إعدادات النظام") { session.openPrayerNotificationSettings() }
                            .frame(minHeight: 44).accessibilityIdentifier("prayer-notification-permission-settings")
                    }
                }
            }
        }
    }
}

private extension AppSession {
    func value(for definition: SettingDefinition) -> MadarData.JSONValue { values[definition.key] ?? definition.defaultValue }
}
