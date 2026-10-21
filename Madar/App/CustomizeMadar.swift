import SwiftUI
import MadarData
import MadarCore
import MadarDesign

struct CustomizeMadar: View {
    @Bindable var session: AppSession
    private var query: String { session.settingsQuery }
    @State private var confirmReset = false
    @State private var widgetGallery = false
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        CustomizationTemplate(title: "خصّص مدار", subtitle: "كل تعديل يُحفظ وحده") {
            // M4-V04: the live model is the lobby itself (05-W4-Takhsis).
            // While searching, results come first; the model returns when the search is cleared.
            if query.isEmpty { BahwCustomizePreview(session: session, changes: changesLabel) { confirmReset = true } }
        } content: {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
                    TextField("ابحث في إعدادات مدار…", text: $session.settingsQuery).accessibilityIdentifier("settings-search")
                        .submitLabel(.search).padding(.trailing, query.isEmpty ? 0 : 34)
                        .overlay(alignment: .trailing) {
                            if !query.isEmpty {
                                Button { session.settingsQuery = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryInk).frame(width: 44, height: 44) }
                                    .buttonStyle(.plain).accessibilityLabel("امسح البحث").accessibilityIdentifier("settings-clear-search")
                            }
                        }
                }.padding(16).background(theme.surface, in: .capsule)
                if query.isEmpty || normalized("المحبرة").contains(normalized(query)) {
                    Button { session.mihbaraOpen = true } label: {
                        HStack { Text("افتح المحبرة").font(MadarTypography.section()); Spacer(); Image(systemName: "chevron.left") }.padding(16).background(theme.surface, in: .rect(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("mihbara-open")
                }
                if query.isEmpty || normalized("المال").contains(normalized(query)) {
                    Button { session.moneyOpen = true } label: {
                        HStack { Text("افتح المال").font(MadarTypography.section()); Spacer(); Image(systemName: "chevron.left") }
                            .padding(16).background(theme.surface, in: .rect(cornerRadius: 20))
                    }.buttonStyle(.plain).accessibilityIdentifier("money-open")
                }
                if query.isEmpty || normalized("الودجات وأحجامها البهو الكتل").contains(normalized(query)) { BahwBlocksSection(session: session) }
                if query.isEmpty || normalized("ودجات الشاشة الرئيسية خارج التطبيق").contains(normalized(query)) {
                    Button {widgetGallery=true} label:{Label("ودجات الشاشة الرئيسية",systemImage:"square.grid.2x2").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:50).background(theme.surface,in:.rect(cornerRadius:20))}.buttonStyle(.plain).accessibilityIdentifier("room-widgets-gallery")
                }
                if filtered.isEmpty && !(query.isEmpty || normalized("المال").contains(normalized(query)) || normalized("المحبرة").contains(normalized(query)) || normalized("ودجات الشاشة الرئيسية خارج التطبيق").contains(normalized(query))) {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(sections, id: \.self) { section in
                        SettingsSection(title: section, symbol: symbols[section] ?? "slider.horizontal.3", definitions: filtered.filter { sectionFor($0.key) == section }, session: session, searching: !query.isEmpty)
                    }
                    if sections.contains("الإشعارات") && session.bool("salah.askReminder") && !session.notificationsAuthorized {
                        MadarCard {
                            VStack(alignment: .leading, spacing: 10) {
                                Text(session.notificationPermissionTitle).font(MadarTypography.body())
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
                if query.isEmpty {
                    if let backup = session.backupService {
                        NavigationLink("النسخ والاستعادة") {
                            BackupSettingsView(service: backup, numerals: session.string("core.numerals") == "western" ? .western : .hindi,
                                dates: { session.dateLabels(GregorianDay.containing($0, in: session.activePlace.timeZone)) },
                                time: { session.backupTime($0) })
                        }.frame(minHeight: 44).font(MadarTypography.section()).accessibilityIdentifier("backup-settings-link")
                    }
                }
            }
        }
        .fullScreenCover(isPresented: $session.mihbaraOpen) { MihbaraHomeView(app: session) }
        .navigationDestination(isPresented: $session.moneyOpen) { MoneyRoomView(app: session) }
        .sheet(isPresented:$widgetGallery){NavigationStack{RoomWidgetsGallery(session:session)}}
        .toolbarVisibility(.hidden, for: .navigationBar)
        .confirmationDialog("أعِد الإعدادات المتفق عليها؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("أعِد الافتراضي", role: .destructive) { session.reset(AppSession.supportedKeys + ["bahw.layout"]) }
        } message: { Text("يعود الشكل والترتيب والإعدادات. البيانات لا تُمسّ.") }
    }
    private var filtered: [SettingDefinition] {
        session.schema.settings.filter { definition in
            guard AppSession.supportedKeys.contains(definition.key) else { return false }
            if definition.key == "core.hijriOffset" && session.string("core.hijriSource") != "sighting" { return false }
            if definition.key == "notif.quietFrom" && !session.bool("notif.quietAfterIsha") { return false }
            return query.isEmpty || normalized(definition.title + " " + sectionFor(definition.key) + " " + definition.key).contains(normalized(query))
        }
    }
    private var sections: [String] { ["العادات", "السنة", "الأيام القادمة", "اليوم والتقويم", "المظهر", "مدينتك", "الخصوصية", "البحث", "الإشعارات", "الصلاة", "المواقيت"].filter { section in filtered.contains { sectionFor($0.key) == section } } }
    private let symbols = ["العادات": "MadarHabits","السنة": "MadarYear", "الأيام القادمة": "MadarUpcoming", "اليوم والتقويم": "moon", "الصلاة": "MadarPrayer", "المواقيت": "clock.arrow.circlepath", "الخصوصية": "lock", "البحث": "magnifyingglass", "المظهر": "paintpalette", "مدينتك": "location", "الإشعارات": "bell.badge"]
    private var changesLabel: String {
        let count = session.schema.settings.filter { (AppSession.supportedKeys + ["bahw.layout"]).contains($0.key) && session.values[$0.key] != $0.defaultValue }.count
        return CustomizationCopy.changes(count: count, formattedCount: session.digits(count))
    }
    private func valueLabel(_ key: String) -> String {
        session.schema.settings.first(where: { $0.key == key })?.options.first(where: { $0.value == session.values[key] })?.label ?? ""
    }
    private func previewLine(_ title: String, value: String) -> some View {
        Group {
            if dynamicType.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).foregroundStyle(theme.secondaryInk)
                    Text(value)
                }
            } else { HStack { Text(title).foregroundStyle(theme.secondaryInk); Spacer(); Text(value) } }
        }.font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true)
    }
}

func sectionFor(_ key: String) -> String {
    if ["bahw.reminder", "bahw.streakBreakAfter", "bahw.travelFreezesHome"].contains(key) { return "العادات" }
    if key == "bahw.yearWhich" { return "السنة" }
    if key == "bahw.upcomingCount" { return "الأيام القادمة" }
    if ["core.dayStart", "core.firstCalendar", "core.hijriSource", "core.hijriOffset", "core.weekStart"].contains(key) { return "اليوم والتقويم" }
    if ["salah.method", "salah.asr", "salah.highLatitudeRule", "salah.offsets"].contains(key) { return "المواقيت" }
    if key == "core.homeCity" { return "مدينتك" }
    if ["salah.showMosqueStreak", "salah.askHeart"].contains(key) { return "الصلاة" }
    if key == "core.faceIDLock" { return "الخصوصية" }
    if key == "core.spotlightIndex" { return "البحث" }
    if ["salah.askAfterAdhanMin", "salah.askReminder", "salah.liveActivity", "notif.thisDeviceReminders", "notif.quietAfterIsha", "notif.quietFrom"].contains(key) { return "الإشعارات" }
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
                        SettingControl(definition: definition, session: session)
                    }
                }.padding(.top, 12)
            } label: {
                HStack(spacing: 12) {
                    MadarGlyph(symbol, size: 22).foregroundStyle(theme.ink).frame(width: 48, height: 48).background(theme.background, in: .rect(cornerRadius: 14)).accessibilityHidden(true)
                    VStack(alignment: .leading, spacing: 3) {
                        Text(title).font(MadarTypography.section()).foregroundStyle(theme.ink)
                        if !summary.isEmpty { Text(summary).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(1) }
                    }
                }
            }
        }
    }
}

struct SettingControl: View {
    let definition: SettingDefinition
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
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
            }
            switch definition.type {
            case "choice":
                ViewThatFits(in: .horizontal) {
                    if !dynamicType.isAccessibilitySize { HStack(spacing: 4) { choices } }
                    VStack(alignment: .leading, spacing: 8) { choices }
                }
            case "bool":
                Toggle(definition.title, isOn: Binding(get: { session.bool(definition.key) }, set: { session.set(.bool($0), key: definition.key) }))
                    .labelsHidden().accessibilityIdentifier("setting-\(definition.key)")
            case "int":
                Stepper(value: Binding(get: { Int(session.number(definition.key)) }, set: { session.set(.number(Double($0)), key: definition.key) }), in: integerRange) {
                    let n = Int(session.number(definition.key))
                    Text(unitForms.map { arabicCount(n, $0, MadarNumberFormatter(style: session.string("core.numerals") == "western" ? .western : .hindi)) } ?? session.digits(n))
                }.accessibilityIdentifier("setting-\(definition.key)")
            case "map":
                if definition.key == "salah.offsets" {
                    ForEach(Prayer.allCases, id: \.self) { prayer in
                        if dynamicType.isAccessibilitySize {
                            VStack(alignment: .leading, spacing: 8) { Text(prayerTitle(prayer)); offsetControls(prayer) }
                        } else {
                            HStack { Text(prayerTitle(prayer)); Spacer(); offsetControls(prayer) }
                        }
                    }
                    Text("التعديل بالدقائق من −٦٠ إلى ٦٠، ويُطبّق على المواقيت دون تغيير تسجيلاتك.")
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
            if definition.key == "core.spotlightIndex" {
                Text("يفهرس عناوين كتب المحبرة فقط؛ لا يُفهرس نص الكتب أو المؤلفون أو الملاحظات الخاصة.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
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
            }.buttonStyle(.plain).accessibilityLabel(option.label)
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

/// Later rooms reuse the same search, preview and settings controls without owning global values.
struct CustomizeRoom<Preview: View>: View {
    let title: String
    let owner: String
    @Bindable var session: AppSession
    @ViewBuilder let preview: () -> Preview
    var body: some View {
        CustomizationTemplate(title: "خصّص \(title)", preview: preview) {
            ForEach(session.schema.settings.filter { $0.owner == owner && AppSession.supportedKeys.contains($0.key) }, id: \.key) { definition in
                MadarCard { SettingControl(definition: definition, session: session) }
            }
            Text("المظهر واليوم ومدينتك من خصّص مدار").font(MadarTypography.caption())
        }
    }
}
