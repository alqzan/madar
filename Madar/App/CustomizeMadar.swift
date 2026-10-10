import SwiftUI
import MadarData
import MadarCore
import MadarDesign

struct CustomizeMadar: View {
    @Bindable var session: AppSession
    private var query: String { session.settingsQuery }
    @State private var confirmReset = false
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        CustomizationTemplate(title: "خصّص مدار", subtitle: "كل تعديل يُحفظ وحده") {
            MadarCard {
                VStack(alignment: .leading, spacing: 12) {
                    Text("نموذج حيّ").font(MadarTypography.fine()).foregroundStyle(theme.accent)
                    Text("مدار كما سيظهر").font(MadarTypography.cardTitle())
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 16) {
                            previewLine("اليوم يبدأ", value: valueLabel("core.dayStart"))
                            previewLine("التقويم الأول", value: valueLabel("core.firstCalendar"))
                            Label(session.cityName, systemImage: "circle.hexagongrid").font(MadarTypography.caption())
                        }
                    } else { HStack {
                        VStack(alignment: .leading, spacing: 8) {
                            previewLine("اليوم يبدأ", value: valueLabel("core.dayStart"))
                            previewLine("التقويم الأول", value: valueLabel("core.firstCalendar"))
                        }
                        Spacer(minLength: 8)
                        VStack(spacing: 10) {
                            Image(systemName: "circle.hexagongrid").font(.system(size: 38)).foregroundStyle(theme.accent)
                            Text(session.cityName).font(MadarTypography.caption())
                        }.padding(16).background(theme.background, in: .rect(cornerRadius: 24))
                    } }
                    if dynamicType.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(changesLabel).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Button("أعِد الافتراضي") { confirmReset = true }.frame(minHeight: 44).accessibilityIdentifier("reset-settings")
                        }
                    } else { HStack {
                        Text(changesLabel).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Spacer()
                        Button("أعِد الافتراضي") { confirmReset = true }.frame(minHeight: 44).accessibilityIdentifier("reset-settings")
                    } }
                }
            }
        } content: {
            VStack(spacing: 16) {
                HStack {
                    Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
                    TextField("ابحث في إعدادات مدار…", text: $session.settingsQuery).accessibilityIdentifier("settings-search")
                        .submitLabel(.search)
                }.padding(16).background(theme.surface, in: .capsule)
                if filtered.isEmpty {
                    ContentUnavailableView.search(text: query)
                } else {
                    ForEach(sections, id: \.self) { section in
                        SettingsSection(title: section, symbol: symbols[section] ?? "slider.horizontal.3", definitions: filtered.filter { sectionFor($0.key) == section }, session: session, searching: !query.isEmpty)
                    }
                }
                if query.isEmpty {
                    if let backup = session.backupService {
                        NavigationLink("النسخ والاستعادة") { BackupSettingsView(service: backup) }.frame(minHeight: 44).font(MadarTypography.section()).accessibilityIdentifier("backup-settings-link")
                    }
                }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .confirmationDialog("أعِد الإعدادات المتفق عليها؟", isPresented: $confirmReset, titleVisibility: .visible) {
            Button("أعِد الافتراضي", role: .destructive) { session.reset(AppSession.supportedKeys) }
        } message: { Text("يعود الشكل والترتيب والإعدادات. البيانات لا تُمسّ.") }
    }
    private var filtered: [SettingDefinition] {
        session.schema.settings.filter { definition in
            guard AppSession.supportedKeys.contains(definition.key) else { return false }
            if definition.key == "core.hijriOffset" && session.string("core.hijriSource") != "sighting" { return false }
            return query.isEmpty || normalized(definition.title + " " + sectionFor(definition.key) + " " + definition.key).contains(normalized(query))
        }
    }
    private var sections: [String] { ["اليوم والتقويم", "المظهر", "مدينتك", "الخصوصية"].filter { section in filtered.contains { sectionFor($0.key) == section } } }
    private let symbols = ["اليوم والتقويم": "calendar", "المظهر": "textformat", "مدينتك": "location"]
    private var changesLabel: String {
        let count = session.schema.settings.filter { AppSession.supportedKeys.contains($0.key) && session.values[$0.key] != $0.defaultValue }.count
        return count == 0 ? "كما اتفقنا" : "\(session.digits(count)) تعديل عن المتفق عليه"
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
    if ["core.dayStart", "core.firstCalendar", "core.hijriSource", "core.hijriOffset", "core.weekStart"].contains(key) { return "اليوم والتقويم" }
    if key == "core.homeCity" { return "مدينتك" }
    if key == "core.faceIDLock" { return "الخصوصية" }
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
    @State private var expanded = true
    @Environment(\.roomTheme) private var theme
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
                Label(title, systemImage: symbol).font(MadarTypography.section()).foregroundStyle(theme.ink)
            }
        }
    }
}

struct SettingControl: View {
    let definition: SettingDefinition
    @Bindable var session: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var dynamicType
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(definition.title).font(MadarTypography.section())
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
                    Text(session.digits(Int(session.number(definition.key))))
                }.accessibilityIdentifier("setting-\(definition.key)")
            case "place": NavigationLink(session.cityName) { CityEditor(session: session) }.frame(minHeight: 44).accessibilityIdentifier("setting-\(definition.key)")
            default: EmptyView()
            }
        }
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
