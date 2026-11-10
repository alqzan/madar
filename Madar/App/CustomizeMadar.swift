import SwiftUI
import MadarData
import MadarCore
import MadarDesign

struct CustomizeMadar: View {
    @Bindable var session: AppSession
    private var query: String { session.settingsQuery }
    @State private var confirmReset = false
    @State private var widgetGallery = false
    @State private var widgetMaker = false
    @State private var quranTafsirLibrary = false
    @State private var missingSettingsRoute = false
    @State private var highlightedSettingKey: String?
    @State private var routedSettingsQuery: String?
    @State private var routedSettingKey: String?
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var settingsWidth: CGFloat = 0
    private var settingsWide: Bool { isPadWide(sizeClass) && settingsWidth >= 960 && query.isEmpty }
    var body: some View {
        ScrollViewReader { proxy in
        CustomizationTemplate(title: "إعدادات مدار", subtitle: "كل تعديل يُحفظ وحده", maxWidth: settingsWide ? 1060 : 620) {
            EmptyView()
        } content: {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
                    TextField("ابحث في إعدادات مدار…", text: Binding(get: { session.settingsQuery }, set: updateSettingsQuery)).accessibilityIdentifier("settings-search")
                        .submitLabel(.search).padding(.trailing, query.isEmpty ? 0 : 34)
                        .overlay(alignment: .trailing) {
                            if !query.isEmpty {
                                Button { updateSettingsQuery("") } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryInk).frame(width: 44, height: 44) }
                                    .buttonStyle(.madarPlain).accessibilityLabel("امسح البحث").accessibilityIdentifier("settings-clear-search")
                            }
                        }
                }.padding(16).background(theme.surface, in: .capsule)
                if missingSettingsRoute {
                    MadarCard {
                        Text("الإعداد غير موجود").font(MadarTypography.section())
                            .accessibilityIdentifier("settings-route-missing")
                    }
                }
                if query.isEmpty {
                    SettingsHome(session: session, openTafsir: { quranTafsirLibrary = true }, openMaker: { widgetMaker = true }, openGallery: { widgetGallery = true },
                                 resetAll: { confirmReset = true }, changes: changesLabel, twoColumns: settingsWide)
                } else {
                if query.isEmpty || normalized("المحبرة").contains(normalized(query)) {
                    Button { session.selectedTab = "mihbara" } label: {
                        HStack { Text("افتح المحبرة").font(MadarTypography.section()); Spacer(); Image(systemName: "chevron.left") }.padding(16).background(theme.surface, in: .rect(cornerRadius: 20))
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-open")
                }
                if query.isEmpty || normalized("المال").contains(normalized(query)) {
                    Button { session.moneyOpen = true } label: {
                        HStack { Text("افتح المال").font(MadarTypography.section()); Spacer(); Image(systemName: "chevron.left") }
                            .padding(16).background(theme.surface, in: .rect(cornerRadius: 20))
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("money-open")
                }
                if query.isEmpty || normalized("القرآن التفسير مكتبة التفاسير مرجع الورد").contains(normalized(query)) {
                    Button { quranTafsirLibrary = true } label: {
                        HStack {
                            Label("خصّص تفاسير القرآن", systemImage: "books.vertical").font(MadarTypography.section())
                            Spacer()
                            Image(systemName: "chevron.left")
                        }
                        .padding(16).background(theme.surface, in: .rect(cornerRadius: 20))
                    }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("quran-tafsir-library-open")
                }
                if query.isEmpty || normalized("الودجات وأحجامها البهو الكتل").contains(normalized(query)) { BahwBlocksSection(session: session) }
                if query.isEmpty || normalized("صانع الودجة اصنع ودجة ودجاتي").contains(normalized(query)) {
                    Button { widgetMaker = true } label: { Label("اصنع ودجة", systemImage: "square.stack.3d.up").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).background(theme.surface, in: .rect(cornerRadius: 20)) }
                        .buttonStyle(.madarPlain).accessibilityIdentifier("widget-maker-open")
                }
                if query.isEmpty || normalized("ودجات الشاشة الرئيسية خارج التطبيق").contains(normalized(query)) {
                    Button {widgetGallery=true} label:{Label("ودجات الشاشة الرئيسية",systemImage:"square.grid.2x2").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:50).background(theme.surface,in:.rect(cornerRadius:20))}.buttonStyle(.madarPlain).accessibilityIdentifier("room-widgets-gallery")
                }
                if showsRoomLayouts { RoomHomeLayoutSection(session: session, searching: !query.isEmpty) }
                if filtered.isEmpty && !showsRoomLayouts && !(query.isEmpty || normalized("صانع الودجة اصنع ودجة ودجاتي").contains(normalized(query))) && !(query.isEmpty || normalized("المال").contains(normalized(query)) || normalized("المحبرة").contains(normalized(query)) || normalized("ودجات الشاشة الرئيسية خارج التطبيق").contains(normalized(query)) || normalized("القرآن التفسير مكتبة التفاسير مرجع الورد").contains(normalized(query))) && !normalized("النسخ والاستعادة نسخة احتياطية انقل من مدار القديم استيراد المزامنة iCloud").contains(normalized(query)) {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(sections, id: \.self) { section in
                        SettingsSection(title: section, symbol: symbols[section] ?? "slider.horizontal.3", definitions: filtered.filter { sectionFor($0.key) == section }, session: session, searching: !query.isEmpty, highlightedSettingKey: highlightedSettingKey)
                    }
                    if sections.contains("الإشعارات") { NotificationPermissionCard(session: session) }
                }
                // The data links are searchable too: «نسخ» or «انقل» used to land on an empty result.
                if query.isEmpty || normalized("النسخ والاستعادة نسخة احتياطية انقل من مدار القديم المزامنة").contains(normalized(query)) {
                    if let backup = session.backupService, query.isEmpty || normalized("النسخ والاستعادة نسخة احتياطية").contains(normalized(query)) {
                        NavigationLink("النسخ والاستعادة") {
                            BackupSettingsView(service: backup, numerals: session.string("core.numerals") == "western" ? .western : .hindi,
                                dates: { session.dateLabels(GregorianDay.containing($0, in: session.activePlace.timeZone)) },
                                time: { session.backupTime($0) })
                        }.frame(minHeight: 44).font(MadarTypography.section()).accessibilityIdentifier("backup-settings-link")
                    }
                    // Only a build signed for iCloud shows sync (no entry point to an unconfigured feature).
                    if AppSyncService.isProvisioned, let sync = session.syncService, query.isEmpty || normalized("المزامنة iCloud").contains(normalized(query)) {
                        NavigationLink("المزامنة عبر iCloud") {
                            SyncSettingsView(service: sync, dates: { session.dateLabels(GregorianDay.containing($0, in: session.activePlace.timeZone)) }, time: { session.backupTime($0) })
                        }
                            .frame(minHeight: 44).font(MadarTypography.section()).accessibilityIdentifier("sync-settings-link")
                    }
                    if query.isEmpty || normalized("انقل من مدار القديم استيراد").contains(normalized(query)) {
                        NavigationLink("انقل من مدار القديم") { LegacyMoveView(app: session) }
                            .frame(minHeight: 44).font(MadarTypography.section()).accessibilityIdentifier("legacy-move-link")
                    }
                }
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { settingsWidth = $0 }
        .navigationDestination(isPresented: $session.moneyOpen) { MoneyRoomView(app: session) }
        .navigationDestination(isPresented: $quranTafsirLibrary) { QuranTafsirLibraryView(app: session) }
        .sheet(isPresented: $widgetMaker, onDismiss: { session.widgetMakerRoute = nil; session.widgetMakerRouteID = nil }) {
            WidgetMakerView(session: session)
                .presentationDetents([.large]).madarSheetErrorAlert(session)
        }
        .sheet(isPresented:$widgetGallery){NavigationStack{RoomWidgetsGallery(session:session)}.madarSheetErrorAlert(session)}
        .toolbarVisibility(.hidden, for: .navigationBar)
        .onChange(of: session.widgetMakerRouteID, initial: true) { _, requestID in if requestID != nil { widgetMaker = true } }
        .confirmationDialog("أعِد الإعدادات المتفق عليها؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("أعِد الافتراضي", role: .destructive) { session.reset(AppSession.supportedKeys + ["bahw.layout"] + RoomHomeLayout.rooms.map { $0.0 + ".layout" }) }
        } message: { Text("يعود الشكل والترتيب والإعدادات. البيانات لا تُمسّ.") }
        .onChange(of: session.settingsRoute, initial: true) { _, route in showSettingsRoute(route, using: proxy) }
        .task(id: highlightedSettingKey) {
            guard highlightedSettingKey != nil else { return }
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            highlightedSettingKey = nil
        }
        .task {
#if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               let raw = environment["MADAR_UI_SETTINGS_ROUTE"], let url = URL(string: raw) {
                session.open(url)
            }
#endif
        }
        }
    }
    private func updateSettingsQuery(_ value: String) {
        session.settingsQuery = value
        if value != routedSettingsQuery {
            routedSettingsQuery = nil
            routedSettingKey = nil
            missingSettingsRoute = false
            highlightedSettingKey = nil
        }
    }
    private func showSettingsRoute(_ route: Route?, using proxy: ScrollViewProxy) {
        guard let route else { return }
        session.settingsRoute = nil
        guard let key = route.path.last, AppSession.supportedKeys.contains(key),
              let definition = try? session.schema.definition(for: key) else {
            session.settingsQuery = ""
            routedSettingsQuery = ""
            routedSettingKey = nil
            highlightedSettingKey = nil
            missingSettingsRoute = true
            return
        }
        session.settingsQuery = definition.title
        routedSettingsQuery = definition.title
        routedSettingKey = key
        missingSettingsRoute = false
        highlightedSettingKey = key
        Task { @MainActor in
            await Task.yield()
            guard highlightedSettingKey == key else { return }
            withAnimation(.easeInOut(duration: 0.25)) {
                proxy.scrollTo("settings-route-\(key)", anchor: .center)
            }
        }
    }
    private var showsRoomLayouts: Bool { query.isEmpty || normalized("ما يعرضه كل باب ترتيب الغرف").contains(normalized(query)) }
    private var filtered: [SettingDefinition] {
        session.schema.settings.filter { definition in
            guard AppSession.supportedKeys.contains(definition.key) else { return false }
            if definition.key == "core.hijriOffset" && session.string("core.hijriSource") != "sighting" && definition.key != routedSettingKey { return false }
            if ["notif.quietFrom", "notif.quietUntil"].contains(definition.key) && !session.bool("notif.quietAfterIsha") && definition.key != routedSettingKey { return false }
            return query.isEmpty || normalized(definition.title + " " + sectionFor(definition.key) + " " + definition.key).contains(normalized(query))
        }
    }
    private var sections: [String] { ["العادات", "السنة", "الأيام القادمة", "الذكاء", "اليوم والتقويم", "المظهر", "مدينتك", "البحث", "الإشعارات", "الصلاة", "المواقيت", "متقدم"].filter { section in filtered.contains { sectionFor($0.key) == section } } }
    private let symbols = ["متقدم": "gearshape.2", "الذكاء": "sparkles", "العادات": "MadarHabits","السنة": "MadarYear", "الأيام القادمة": "MadarUpcoming", "اليوم والتقويم": "moon", "الصلاة": "MadarPrayer", "المواقيت": "clock.arrow.circlepath", "البحث": "magnifyingglass", "المظهر": "paintpalette", "مدينتك": "location", "الإشعارات": "bell.badge"]
    private var changesLabel: String {
        let count = session.schema.settings.filter { (AppSession.supportedKeys + ["bahw.layout"] + RoomHomeLayout.rooms.map { $0.0 + ".layout" }).contains($0.key) && session.values[$0.key] != $0.defaultValue }.count
        return CustomizationCopy.changes(count: count, formattedCount: session.digits(count))
    }
    private func previewLine(_ title: String, value: String) -> some View {
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(theme.secondaryInk)
                    Text(figure: value)
                }
            } else { HStack { Text(title).foregroundStyle(theme.secondaryInk); Spacer(); Text(figure: value) } }
        }.font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
    }
}

func sectionFor(_ key: String) -> String {
    if key == "bahw.smartPresence" { return "الذكاء" }
    if ["bahw.reminder", "bahw.streakBreakAfter", "bahw.travelFreezesHome", "bahw.widgetScope"].contains(key) { return "العادات" }
    if key == "bahw.yearWhich" { return "السنة" }
    if key == "bahw.upcomingCount" { return "الأيام القادمة" }
    // B2-18: values most people never change sit in one «متقدم» fold (no value or default changes).
    if ["core.hijriSource", "core.hijriOffset", "salah.highLatitudeRule", "salah.offsets", "core.spotlightIndex"].contains(key) { return "متقدم" }
    if ["core.dayStart", "core.firstCalendar", "core.weekStart"].contains(key) { return "اليوم والتقويم" }
    if ["salah.method", "salah.asr"].contains(key) { return "المواقيت" }
    if key == "core.homeCity" { return "مدينتك" }
    if ["salah.showMosqueStreak", "salah.askHeart"].contains(key) { return "الصلاة" }
    // FB-39: these prayer keys used to fall through to «المظهر», so travel method and pending days were never on the prayer page.
    if ["salah.pendingDays", "salah.tripMethod", "salah.travelShortenCombine", "salah.pool", "salah.fridayTallArch"].contains(key) { return "الصلاة" }
    if ["salah.beforeReminder", "salah.beforeAdhanMin", "notes.eveningLine", "salah.askAfterAdhanMin", "salah.askReminder", "salah.liveActivity", "notif.thisDeviceReminders", "notif.dailyBudget", "notif.quietAfterIsha", "notif.quietFrom", "notif.quietUntil"].contains(key) { return "الإشعارات" }
    return "المظهر"
}
func normalized(_ text: String) -> String {
    String(text.unicodeScalars.filter { !CharacterSet.nonBaseCharacters.contains($0) }.map { scalar in
        switch String(scalar) { case "أ", "إ", "آ": "ا"; case "ة": "ه"; case "ى": "ي"; default: String(scalar) }
    }.joined()).lowercased()
}

struct SettingsSection: View {
    let title: String
    let symbol: String
    let definitions: [SettingDefinition]
    @Bindable var session: AppSession
    let searching: Bool
    let highlightedSettingKey: String?
    @State private var expanded = false
    @Environment(\.roomTheme) private var theme
    /// The current choices, read from the values (05-W4-Takhsis-s1: «هجري أولًا، يبدأ اليوم من الفجر»).
    private var summary: String {
        definitions.prefix(3).compactMap { definition -> String? in
            if let option = definition.options.first(where: { $0.value == session.values[definition.key] }) { return option.label }
            if definition.type == "place" { return session.cityName }
            if definition.type == "bool" { return nil }
            return nil
        }.joined(separator: "، ")
    }
    var body: some View {
        MadarCard {
            DisclosureGroup(isExpanded: Binding(get: { searching || expanded }, set: { expanded = $0 })) {
                VStack(alignment: .leading, spacing: 16) {
                    ForEach(definitions, id: \.key) { definition in
                        Divider().overlay(theme.line)
                        SettingControl(definition: definition, session: session, highlighted: highlightedSettingKey == definition.key)
                            .id("settings-route-\(definition.key)")
                    }
                }.padding(.top, 12)
            } label: {
                HStack(spacing: 12) {
                    MadarGlyph(symbol, size: 22).foregroundStyle(theme.ink).frame(width: 48, height: 48).background(theme.background, in: .rect(cornerRadius: 14)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(MadarTypography.section()).foregroundStyle(theme.ink)
                        if !summary.isEmpty { Text(figure: summary).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true) }
                    }
                }
            }
        }
    }
}

struct SettingControl: View {
    let definition: SettingDefinition
    @Bindable var session: AppSession
    var highlighted = false
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    /// AU-95: quick taps on +/− each stepped from the stored value, which only refreshes after the write lands, so
    /// three taps moved one step. The control steps from the value it last sent until that write comes back.
    @State private var sentInt: Int?
    private var shownInt: Int { sentInt ?? Int(session.number(definition.key)) }
    /// «اسألني بعد الأذان بـ (دقيقة)» over a bare «٣٠» reads as a form; the number carries its unit instead («٣٠ دقيقة»).
    private var unitSuffix: String { definition.title.hasSuffix(" (دقيقة)") ? " (دقيقة)" : " (أيام)" }
    private var unitForms: [String]? {
        guard definition.type == "int", (definition.range?.first ?? 0) >= 0 else { return nil }
        if definition.title.hasSuffix(" (دقيقة)") { return ["دقيقة واحدة", "دقيقتان", "دقائق", "دقيقة"] }
        if definition.title.hasSuffix(" (أيام)") { return ["يوم واحد", "يومان", "أيام", "يومًا"] }
        return nil
    }
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(unitForms == nil ? definition.title : String(definition.title.dropLast(unitSuffix.count))).font(MadarTypography.section())
                Spacer()
                if definition.scope == "device" { Text("لهذا الجهاز").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                // Owner, 6 Nov 2026: «مشطوف». A switch on its own line under the title ran past the card's edge; it sits beside its title, as iOS does.
                if definition.type == "bool" {
                    Toggle(definition.title, isOn: Binding(get: { session.bool(definition.key) }, set: { session.set(.bool($0), key: definition.key) }))
                        .labelsHidden().fixedSize().accessibilityIdentifier("setting-\(definition.key)")
                }
            }
            switch definition.type {
            case "choice":
                ViewThatFits(in: .horizontal) {
                    if !dynamicType.isAccessibilitySize { HStack(spacing: 4) { choices } }
                    VStack(alignment: .leading, spacing: 8) { choices }
                }
            case "bool":
                EmptyView()
            case "int":
                Stepper(value: Binding(get: { shownInt }, set: { value in
                    sentInt = value
                    session.set(.number(Double(value)), key: definition.key) { if sentInt == value { sentInt = nil } }
                }), in: integerRange) {
                    let n = shownInt
                    // AU-44: the Hijri correction reads as a sentence, not a signed number.
                    if definition.key == "core.hijriOffset" {
                        Text(n == 0 ? "بلا تصحيح" : (abs(n) == 1 ? "يوم" : abs(n) == 2 ? "يومان" : session.digits(abs(n)) + " أيام") + (n > 0 ? " زيادة" : " نقصان"))
                    } else {
                    Text(unitForms.map { arabicCount(n, $0, MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)) } ?? session.digits(n))
                    }
                }.accessibilityIdentifier("setting-\(definition.key)")
                .onChange(of: session.errorMessage) { _, message in if message != nil { sentInt = nil } }
            case "map":
                if definition.key == "salah.offsets" {
                    ForEach(Prayer.allCases, id: \.self) { prayer in
                        if dynamicType.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) { Text(prayerTitle(prayer)); offsetControls(prayer) }
                        } else {
                            HStack { Text(prayerTitle(prayer)); Spacer(); offsetControls(prayer) }
                        }
                    }
                    Text("التعديل بالدقائق من −" + session.digits(60) + " إلى " + session.digits(60) + "، ويُطبّق على المواقيت دون تغيير تسجيلاتك.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }
            case "place": NavigationLink(session.cityName) { CityEditor(session: session) }.frame(minHeight: 44).accessibilityIdentifier("setting-\(definition.key)")
            case "time":
                DatePicker(definition.title, selection: timeBinding, displayedComponents: .hourAndMinute)
                    .labelsHidden()
                    .environment(\.timeZone, session.activePlace.timeZone)
                    .accessibilityLabel(definition.title)
                    .accessibilityIdentifier("setting-\(definition.key)")
            default: EmptyView()
            }
            // AU-43: the switches that change what reaches the user say what they do.
            if let caption = ["notif.thisDeviceReminders": "إيقافه يوقف كل تذكيرات مدار على هذا الجهاز، وتبقى مواعيدك وسجلّك كما هي.",
                              "notif.quietAfterIsha": "لا تصلك تذكيرات الغرف من بدء الصمت حتى نهايته التي تختارها: الفجر أو الشروق أو منتصف الليل."][definition.key] {
                Text(caption).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            if definition.key == "notif.dailyBudget" {
                Text("الحد على هذا الجهاز من \(session.digits(1)) إلى \(session.digits(10)). لا يشمل سؤال الصلاة ولا متابعة القلب ولا النشاط الحي؛ ويُحسب الملخّص و«افتح مدار» تذكيرًا واحدًا لكل منهما.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("setting-notif.dailyBudget-note")
            }
            if definition.key == "core.spotlightIndex" {
                Text("يفهرس عناوين كتب المحبرة فقط؛ لا يُفهرس نص الكتب أو المؤلفون أو الملاحظات الخاصة.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if definition.key == "bahw.widgetScope" {
                Text(session.string("bahw.widgetScope") == "todayOnly" ? "تظهر العادات التي حان وقتها فقط." : "تظهر عادات اليوم كله، ومنها المتأخرة. عادات الغد لا تظهر.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            }
            if definition.key == "bahw.smartPresence" {
                Text((["calm": "ما يحتاج فعلًا الآن فقط", "present": "ما يحتاجك الآن، وما تبقّى اليوم، وخطوتك التالية في كل غرفة"][session.string("bahw.smartPresence")] ?? "ما يحتاجك الآن، وما تبقّى اليوم") + "، داخل البهو بلا إشعارات.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if definition.key == "bahw.reminder" {
                Text("يُطبّق على العادات الجديدة. الإشعار يحتاج وقتًا محددًا للعادة.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .overlay {
            if highlighted { RoundedRectangle(cornerRadius: 16).stroke(theme.accent, lineWidth: 2) }
        }
        .animation(.easeInOut(duration: 0.2), value: highlighted)
    }
    private var offsetRange: ClosedRange<Int> {
        let limits = definition.contract?["range"]?.array?.compactMap(\.number) ?? [-60, 60]
        return Int(limits[0])...Int(limits[1])
    }
    private func offset(_ prayer: Prayer) -> Int { Int(session.values[definition.key]?.object?[prayer.rawValue]?.number ?? 0) }
    private func setOffset(_ prayer: Prayer, delta: Int) {
        guard !session.settingsWriteInProgress else { return }
        var values = session.values[definition.key]?.object ?? definition.defaultValue.object ?? [:]
        values[prayer.rawValue] = .number(Double(min(offsetRange.upperBound, max(offsetRange.lowerBound, offset(prayer) + delta))))
        session.set(.object(values), key: definition.key)
    }
    private func offsetControls(_ prayer: Prayer) -> some View {
        HStack(spacing: 10) {
            Button { setOffset(prayer, delta: -1) } label: { Image(systemName: "minus").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("أنقص دقيقة من " + prayerTitle(prayer)).accessibilityIdentifier("offset-\(prayer.rawValue)-minus")
                .disabled(session.settingsWriteInProgress || offset(prayer) <= offsetRange.lowerBound)
            Text(session.digits(offset(prayer))).font(MadarTypography.body()).monospacedDigit()
                .accessibilityIdentifier("offset-\(prayer.rawValue)-value")
            Button { setOffset(prayer, delta: 1) } label: { Image(systemName: "plus").frame(width: 44, height: 44).contentShape(Rectangle()) }
                .accessibilityLabel("زد دقيقة على " + prayerTitle(prayer)).accessibilityIdentifier("offset-\(prayer.rawValue)-plus")
                .disabled(session.settingsWriteInProgress || offset(prayer) >= offsetRange.upperBound)
        }
    }
    private func prayerTitle(_ prayer: Prayer) -> String {
        switch prayer { case .fajr: "الفجر"; case .dhuhr: "الظهر"; case .asr: "العصر"; case .maghrib: "المغرب"; case .isha: "العشاء" }
    }
    private var timeBinding: Binding<Date> {
        Binding(get: {
            let parts = session.string(definition.key).split(separator: ":", omittingEmptySubsequences: false)
            let hour = parts.count == 2 ? Int(parts[0]) : nil
            let minute = parts.count == 2 ? Int(parts[1]) : nil
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = session.activePlace.timeZone
            return calendar.date(from: DateComponents(year: 2001, month: 1, day: 1,
                                                       hour: hour ?? 21, minute: minute ?? 30)) ?? .now
        }, set: { date in
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = session.activePlace.timeZone
            let parts = calendar.dateComponents([.hour, .minute], from: date)
            guard let hour = parts.hour, let minute = parts.minute else { return }
            session.set(.string(String(format: "%02d:%02d", hour, minute)), key: definition.key)
        })
    }
    private var integerRange: ClosedRange<Int> { Int(definition.range?.first ?? 0)...Int(definition.range?.last ?? 0) }
    @ViewBuilder private var choices: some View {
        ForEach(definition.options, id: \.value) { option in
            Button { session.set(option.value, key: definition.key) } label: {
                VStack(spacing: 3) {
                    Text(option.label).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
                    if option.value == definition.defaultValue { Text("افتراضي").font(MadarTypography.fine()) }
                }.frame(maxWidth: .infinity, minHeight: 44).padding(.horizontal, 8).padding(.vertical, 8)
                    .foregroundStyle(session.values[definition.key] == option.value ? theme.ink : theme.secondaryInk)
                    .background(session.values[definition.key] == option.value ? theme.surface : theme.background, in: .rect(cornerRadius: 12))
                    .overlay { RoundedRectangle(cornerRadius: 12).stroke(session.values[definition.key] == option.value ? theme.accent : theme.line, lineWidth: 1) }
            }.buttonStyle(.madarPlain).accessibilityLabel(option.label)
                .accessibilityValue(session.values[definition.key] == option.value ? "مختار" : "")
                .accessibilityAddTraits(session.values[definition.key] == option.value ? .isSelected : [])
                .accessibilityIdentifier("option-\(definition.key)-\(option.identifier)")
        }
    }
}

extension SettingOption {
    var identifier: String { if case .string(let value) = value { value } else { label } }
}
extension AppSession {
    func digits(_ integer: Int) -> String { MadarNumberFormatter(style: string("core.numerals") == "western" ? .western : .hindi).string(integer) }
}


/// FB-39: shown at the top of the notifications page too (it used to appear only in search results), so a refused permission is never hidden
/// behind switches that look on and do nothing.
struct NotificationPermissionCard: View {
    @Bindable var session: AppSession
    var body: some View {
        if (session.bool("salah.askReminder") || session.bool("salah.beforeReminder") || session.bool("notif.thisDeviceReminders")) && !session.notificationsAuthorized {
            MadarCard {
                VStack(alignment: .leading, spacing: 10) {
                    Text(session.notificationPermissionTitle).font(MadarTypography.body())
                    if session.canRequestNotificationPermission {
                        Button { session.requestPrayerNotificationPermission() } label: { Text("اسمح بالإشعارات")
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

/// One page's own «back to the agreed defaults», confirmed, data untouched (every setting has a reset; FB-39).
struct SettingsPageReset: View {
    @Bindable var session: AppSession
    let keys: [String]
    @State private var confirming = false
    @Environment(\.roomTheme) private var theme
    private var changed: Int { session.schema.settings.filter { keys.contains($0.key) && session.values[$0.key] != $0.defaultValue }.count }
    var body: some View {
        if changed > 0 {
            Button { confirming = true } label: {
                Text("أعِد هذه الصفحة إلى الافتراضي").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 44)
            }
            .buttonStyle(.madarPlain).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("settings-page-reset")
            .confirmationDialog("تعود إعدادات هذه الصفحة إلى المتفق عليه؟", isPresented: $confirming, titleVisibility: .visible) {
                Button("أعِد الافتراضي", role: .destructive) { session.reset(keys) }
                Button("إلغاء", role: .cancel) {}
            } message: { Text("بياناتك لا تُمسّ.") }
        }
    }
}
