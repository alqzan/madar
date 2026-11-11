import SwiftUI
import MadarData
import MadarCore
import MadarPrayer
import MadarDesign

/// `salah.layout` for the prayer home: the order and visibility of the movable blocks.
/// «الصلاة القادمة» and «الرواق» are pinned: they stay at the top and are never hidden.
struct PrayerHomeLayout: Equatable {
    static let pinned = ["next", "riwaq"]
    /// Owner, 5 Nov 2026: «احذف حق القيام». The night-prayer card left the home and the editor, but its key stays in the stored
    /// layout (the schema lists it) and is always hidden, so a reorder still saves a valid layout.
    static let movable = ["pending", "hali", "qiyam"]
    var order: [String]
    var hidden: Set<String>

    init(_ value: MadarData.JSONValue?) {
        let blocks = value?.object?["blocks"]?.array?.compactMap(\.string) ?? []
        let hiddenIDs = value?.object?["hidden"]?.array?.compactMap(\.string) ?? []
        var ordered = blocks.filter { Self.movable.contains($0) }
        for key in Self.movable where !ordered.contains(key) { ordered.append(key) }
        ordered.removeAll { $0 == "qiyam" }; ordered.append("qiyam")
        order = ordered
        hidden = Set(hiddenIDs).intersection(Self.movable).union(["qiyam"])
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
        case "hali": "حالي"; default: "قيام الليل"
        }
    }
    static func detail(_ key: String) -> String {
        switch key {
        case "next": "الاسم والوقت وكم بقي"; case "riwaq": "خمسة أقواس تمتلئ بحالها"
        case "pending": "يظهر حين تنتظر صلاة"; case "hali": "السبحة ونسبة الشهر والسلسلتان"
        default: "الركعات والوتر وأثر ٣٠ ليلة"
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
    @State private var travelLocator = TravelLocator()
    @State private var askedLocation = false
    @State private var editingStart = false
    @State private var confirmStart = false
    @State private var startDate = Date()

    private var theme: RoomTheme { RoomTheme(room: "salah", dark: inheritedTheme.dark, calmPaper: inheritedTheme.calmPaper) }
    private var layout: PrayerHomeLayout { PrayerHomeLayout(session.values["salah.layout"]) }
    private var salahKeys: [String] { ["salah.layout"] + AppSession.supportedKeys.filter { $0.hasPrefix("salah.") } }


    private struct CustomizeGroup: Identifiable {
        let id: String, title: String, symbol: String, keys: [String]
    }
    private let groups: [CustomizeGroup] = [
        .init(id: "riwaq", title: "الرواق والميزان", symbol: "paintpalette", keys: ["salah.pool", "salah.fridayTallArch", "salah.showMosqueStreak"]),
        .init(id: "log", title: "التسجيل", symbol: "checkmark", keys: ["salah.askHeart", "salah.pendingDays"]),
        .init(id: "times", title: "المواقيت", symbol: "clock", keys: ["salah.method", "salah.tripMethod", "salah.asr", "salah.highLatitudeRule", "salah.offsets", "salah.travelShortenCombine"]),
        .init(id: "remind", title: "التذكير", symbol: "bell", keys: ["salah.beforeReminder", "salah.beforeAdhanMin", "salah.askReminder", "salah.askAfterAdhanMin", "salah.liveActivity"]),
    ]
    private func definitions(_ group: CustomizeGroup) -> [SettingDefinition] {
        group.keys.compactMap { key in AppSession.supportedKeys.contains(key) ? session.schema.settings.first { $0.key == key } : nil }
            .filter { query.isEmpty || normalized($0.title + " " + group.title).contains(normalized(query)) }
    }
    private var showsTrackingStart: Bool {
        query.isEmpty || normalized("بداية التتبع بداية التتبّع التسجيل أول يوم").contains(normalized(query))
    }
    private func label(_ key: String) -> String {
        session.schema.settings.first { $0.key == key }?.options.first { $0.value == session.values[key] }?.label ?? ""
    }
    private func subtitle(_ group: CustomizeGroup) -> String {
        switch group.id {
        case "riwaq": return session.bool("salah.showMosqueStreak") ? "سلسلة الجماعة ظاهرة" : "سلسلة الجماعة مخفية"
        case "log": return session.bool("salah.askHeart") ? "اسألني عن القلب" : "بلا سؤال القلب"
        case "times": return label("salah.method") + " · " + label("salah.asr")
        default:
            let digits = MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)
            if session.bool("salah.beforeReminder") { return "قبل الأذان بـ " + PrayerCopy.minutes(Int(session.number("salah.beforeAdhanMin")), digits: digits) }
            return session.bool("salah.askReminder") ? "بعد الأذان بـ " + PrayerCopy.minutes(Int(session.number("salah.askAfterAdhanMin")), digits: digits) : "بلا تذكير"
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
                    if !items.isEmpty || (group.id == "log" && showsTrackingStart) { groupCard(group, items) }
                }
                // AU-26: a search with no match explains itself instead of leaving a blank page.
                if !query.isEmpty, !showsTrackingStart, !normalized("ترتيب الرئيسية").contains(normalized(query)), groups.allSatisfy({ definitions($0).isEmpty }) {
                    Text("لا إعداد يطابق «\(query)». جرّب «المواقيت» أو «التذكير».").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    Button { query = "" } label: { Text("امسح البحث").font(PrayerHomeType.body.bold()).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("prayer-customize-clear-search")
                }
                Text("تصمت تنبيهات مدار " + MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi).string(30)
                     + " دقيقة بعد كل أذان، و" + MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi).string(20)
                     + " دقيقة بعد أذان المغرب. لا يمكن إيقاف هذه الحرمة.")
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
            }.buttonStyle(.madarPlain).accessibilityIdentifier("prayer-customize-back")
            Text("خصّص الصلاة").font(prayerSerif(40)).accessibilityAddTraits(.isHeader)
            Text("كل تعديل يُحفظ وحده").font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
        }
    }

    private var previewCard: some View {
        PrayerPaperCard {
            HStack(alignment: .top, spacing: 18) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) {
                        Circle().fill(theme.accent).frame(width: 8, height: 8)
                        Text("معاينة حيّة").font(PrayerHomeType.smallBold).foregroundStyle(theme.color("accentText"))
                    }
                    Text("الصلاة كما ستظهر").font(prayerSerif(26))
                    previewLine("الأجزاء", arabicCount(layout.visibleCount, ["جزء واحد ظاهر", "جزآن ظاهران", "أجزاء ظاهرة", "جزءًا ظاهرًا"], MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi))) // AU-37: «٥ أجزاء ظاهرة», not «٥ ظاهرة».
                    previewLine("طريقة الحساب", label("salah.method"))
                    previewLine("وقت العصر", label("salah.asr"))
                    Text(CustomizationCopy.changes(count: changedCount, formattedCount: session.digits(changedCount)))
                        .font(PrayerHomeType.smallBold).foregroundStyle(theme.secondaryInk)
                        .accessibilityIdentifier("prayer-customize-changes")
                    HStack(spacing: 8) {
                        Button { dismiss() } label: {
                            Text("افتح الصلاة").font(PrayerHomeType.strong).foregroundStyle(theme.color("onAccent")).lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 16).frame(minHeight: 48)
                                .background(theme.ink, in: .rect(cornerRadius: 24))
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("prayer-customize-open")
                        Button { confirmReset = true } label: {
                            Text("أعِد الافتراضي").font(PrayerHomeType.strong).lineLimit(1).minimumScaleFactor(0.8)
                                .padding(.horizontal, 12).frame(minHeight: 48)
                                .overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.ink.opacity(0.14), lineWidth: 1) }
                        }.buttonStyle(.madarPlain).disabled(changedCount == 0).accessibilityIdentifier("prayer-customize-reset")
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
            TextField("ابحث: المواقيت، القلب، التذكير…", text: $query).font(PrayerHomeType.lead)
                .submitLabel(.search).accessibilityIdentifier("prayer-customize-search")
        }
        .padding(.horizontal, 18).frame(minHeight: 52)
        .glassEffect(.regular.interactive(), in: .capsule)
    }

    private func card<Body: View>(_ id: String, title: String, subtitle: String, symbol: String, highlighted: Bool = false, @ViewBuilder body: () -> Body) -> some View {
        let open = expanded.contains(id) || !query.isEmpty
        return VStack(alignment: .leading, spacing: 0) {
            Button { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } } label: {
                HStack(spacing: 14) {
                    Image(systemName: symbol).font(.system(size: 20)).foregroundStyle(theme.color("accentText"))
                        .frame(width: 52, height: 52).background(theme.surface, in: .rect(cornerRadius: 16))
                    VStack(alignment: .leading, spacing: 2) {
                        Text(title).font(prayerSerif(22))
                        Text(subtitle).font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk)
                    }
                    Spacer(minLength: 8)
                    Image(systemName: open ? "chevron.up" : "chevron.down").foregroundStyle(theme.secondaryInk)
                }.frame(minHeight: 56).contentShape(.rect)
            }.buttonStyle(.madarPlain).accessibilityAddTraits(.isButton).accessibilityValue(open ? "مفتوح" : "مطوي")
                .accessibilityIdentifier("prayer-customize-card-" + id)
            if open { VStack(alignment: .leading, spacing: 0) { body() }.padding(.top, 12) }
        }
        .padding(.horizontal, 18).padding(.vertical, 14)
        .background(theme.color("card"), in: .rect(cornerRadius: 26))
        .overlay { RoundedRectangle(cornerRadius: 26).stroke(highlighted && open ? theme.accent : theme.ink.opacity(0.1), lineWidth: highlighted && open ? 1.5 : 1) }
    }

    private var layoutCard: some View {
        card("layout", title: "ترتيب الرئيسية", subtitle: "\(session.digits(layout.visibleCount)) من \(session.digits(PrayerHomeLayout.pinned.count + PrayerHomeLayout.movable.count - 1)) ظاهرة", symbol: "square.grid.2x2", highlighted: true) {
            Text("الصلاة القادمة والأقواس ثابتة في الأعلى، وترتّب الباقي أو تخفيه.")
                .font(PrayerHomeType.body).foregroundStyle(theme.secondaryInk).padding(.bottom, 12)
            ForEach(PrayerHomeLayout.pinned, id: \.self) { key in
                Divider().overlay(theme.ink.opacity(0.1))
                blockRow(key, pinned: true)
            }
            ForEach(layout.order.filter { $0 != "qiyam" }, id: \.self) { key in
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
                arrow("chevron.down", id: "prayer-block-down-" + key, label: "أخّر " + PrayerHomeLayout.title(key), disabled: index == nil || index == layout.order.count - 2) { session.set(layout.moved(key, by: 1).payload, key: "salah.layout") }
                Toggle(PrayerHomeLayout.title(key), isOn: Binding(get: { !layout.hidden.contains(key) }, set: { _ in session.set(layout.toggled(key).payload, key: "salah.layout") }))
                    .labelsHidden().tint(theme.accent).disabled(session.settingsWriteInProgress).accessibilityIdentifier("prayer-block-" + key)
            }
        }
        .padding(.vertical, 10).frame(minHeight: 60)
    }

    private func arrow(_ symbol: String, id: String, label: String, disabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol).font(.system(size: 17, weight: .semibold)).frame(width: 44, height: 44).contentShape(.rect)
        }
        .buttonStyle(.madarPlain).disabled(disabled || session.settingsWriteInProgress).opacity(disabled ? 0.3 : 1)
        .accessibilityLabel(label).accessibilityIdentifier(id)
    }

    // MARK: Tracking start (P04)

    private var numeralLocale: Locale { Locale(identifier: session.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab") }

    @ViewBuilder private var trackingStartBlock: some View {
        if let tracking = try? session.prayerSnapshot(at: session.prayerNow()).tracking {
            let zone = session.activePlace.timeZone
            let earliest = tracking.firstRun.adding(days: -30).date(in: zone).addingTimeInterval(12 * 3600)
            let latest = tracking.firstRun.date(in: zone).addingTimeInterval(12 * 3600)
            VStack(alignment: .leading, spacing: 8) {
                Text("بداية التتبّع").font(PrayerHomeType.strong)
                MadarDateLabel(session.dateLabels(tracking.day), primaryFont: PrayerHomeType.body).accessibilityIdentifier("prayer-tracking-start")
                Text("يبدأ السجل من اليوم الذي تختاره؛ ما قبله لا يدخل في سجل الصلاة.")
                    .font(PrayerHomeType.small).foregroundStyle(theme.secondaryInk)
                if tracking.edits == 0 {
                    if editingStart {
                        DatePicker("البداية", selection: $startDate, in: earliest...latest, displayedComponents: .date)
                            .environment(\.timeZone, zone)
                            .accessibilityIdentifier("prayer-tracking-date")
                        MadarDateLabel(session.dateLabels(GregorianDay.containing(startDate, in: zone)))
                        Button { confirmStart = true } label: {
                            Text("احفظ البداية").font(PrayerHomeType.strong).foregroundStyle(theme.color("onAccent"))
                                .padding(.horizontal, 20).frame(minHeight: 48).background(theme.ink, in: .rect(cornerRadius: 24))
                        }.buttonStyle(.madarPlain).disabled(session.prayerWriteInProgress).accessibilityIdentifier("prayer-tracking-save")
                    } else {
                        Button { startDate = tracking.day.date(in: zone).addingTimeInterval(12 * 3600); editingStart = true } label: {
                            Text("عدّل بداية التتبّع").font(PrayerHomeType.strong).foregroundStyle(theme.color("accentText")).frame(minHeight: 44)
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("prayer-tracking-edit")
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
            } message: { Text("بعد الحفظ لا تتغيّر البداية مرة أخرى، والأيام المضافة تُحسب معلّقة من اليوم.") }
        }
    }

    private func groupCard(_ group: CustomizeGroup, _ items: [SettingDefinition]) -> some View {
        card(group.id, title: group.title, subtitle: subtitle(group), symbol: group.symbol) {
            VStack(alignment: .leading, spacing: 16) {
                ForEach(items, id: \.key) { definition in
                    Divider().overlay(theme.ink.opacity(0.1))
                    SettingControl(definition: definition, session: session)
                }
                if group.id == "log", showsTrackingStart { Divider().overlay(theme.ink.opacity(0.1)); trackingStartBlock }
                if group.id == "times" && query.isEmpty && session.bool("salah.travelShortenCombine") && session.string("core.travelMode") != "manual" && !askedLocation && travelLocator.canAskForLocation {
                    Divider().overlay(theme.ink.opacity(0.1))
                    Text("يقارن موقعك بمدينتك عند فتح الصلاة ليعرف أنك سافرت، ولا يحفظه. وبدونه يبقى السفر اليدوي.").font(PrayerHomeType.body)
                    Button { askedLocation = true; travelLocator.askForLocation() } label: { Text("اسمح بالموقع لكشف السفر")
                        .frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("prayer-travel-location-request")
                }
                if group.id == "remind" && (session.bool("salah.askReminder") || session.bool("salah.beforeReminder")) && !session.notificationsAuthorized {
                    Divider().overlay(theme.ink.opacity(0.1))
                    Text(session.notificationPermissionTitle).font(PrayerHomeType.body)
                    if session.canRequestNotificationPermission {
                        Button { session.requestPrayerNotificationPermission() } label: { Text("اسمح بإشعارات الصلاة")
                            .frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("prayer-notification-permission-request")
                    } else if session.shouldOpenNotificationSettings {
                        Button { session.openPrayerNotificationSettings() } label: { Text("افتح إعدادات النظام")
                            .frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("prayer-notification-permission-settings")
                    }
                }
            }
        }
    }
}

private extension AppSession {
    func value(for definition: SettingDefinition) -> MadarData.JSONValue { values[definition.key] ?? definition.defaultValue }
}
