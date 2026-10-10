import SwiftUI
import SwiftData
import MadarData
import MadarDesign

private struct PresetChoice: Identifiable {
    let id: UUID
    let name: String
    let settings: [String: JSONValue]
    let layouts: [String: JSONValue]
}
struct PresetsView: View {
    @Bindable var session: AppSession
    @Query private var saved: [Preset]
    @State private var name = ""
    @State private var candidate: PresetChoice?
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                Text("الأنماط المحفوظة").font(MadarTypography.title())
                Text("احفظ مظهر مدار وترتيبه. إعدادات اليوم والمدن والبيانات تبقى كما هي.").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk)
                MadarCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Label("المتفق عليه", systemImage: "lock").font(MadarTypography.section())
                        Text("نمط مدار الافتراضي").foregroundStyle(theme.secondaryInk)
                        Button("عاين النمط") {
                            let settings = Dictionary(uniqueKeysWithValues: session.schema.settings.filter { $0.preset && AppSession.supportedKeys.contains($0.key) }.map { ($0.key, $0.defaultValue) })
                            candidate = .init(id: UUID(uuidString: "00000000-0000-0000-0000-000000000001")!, name: "المتفق عليه", settings: settings, layouts: [:])
                        }.frame(minHeight: 44).accessibilityIdentifier("preview-default-preset")
                    }
                }
                ForEach(saved.filter { $0.deletedAt == nil && !$0.locked }.sorted { $0.createdAt > $1.createdAt }) { preset in
                    MadarCard {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(preset.name).font(MadarTypography.section())
                            Text(preset.createdAt, format: .dateTime.year().month().day()).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            Button("عاين النمط") {
                                do {
                                    let payload = try JSONDecoder().decode(JSONValue.self, from: preset.payloadJSON)
                                    guard case .object(let root) = payload, case .object(let values) = root["settings"] else { throw PresetViewError.invalidPayload }
                                    let layouts = root["layouts"]?.object ?? [:]
                                    candidate = .init(id: preset.id, name: preset.name, settings: values, layouts: layouts)
                                } catch { session.errorMessage = "تعذّرت قراءة النمط المحفوظ. \(error.localizedDescription)" }
                            }.frame(minHeight: 44)
                        }
                    }
                }
                MadarCard {
                    VStack(alignment: .leading, spacing: 12) {
                        Text("احفظ إعداداتي الحالية نمطًا").font(MadarTypography.section())
                        TextField("اسم النمط", text: $name).textFieldStyle(.roundedBorder).accessibilityIdentifier("preset-name")
                        Button("احفظ النمط") { session.savePreset(name: name) { name = "" } }
                            .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                            .buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("save-preset")
                    }
                }
            }.padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background).foregroundStyle(theme.ink)
            .sheet(item: $candidate) { choice in
                PresetPreview(choice: choice, session: session)
            }
    }
}
private enum PresetViewError: Error { case invalidPayload }
private struct PresetPreview: View {
    let choice: PresetChoice
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    private var known: [SettingDefinition] { session.schema.settings.filter { choice.settings[$0.key] != nil && $0.preset && AppSession.supportedKeys.contains($0.key) } }
    private var changes: [SettingDefinition] { known.filter { session.values[$0.key] != choice.settings[$0.key] } }
    private var ignored: Int { choice.settings.count - known.count }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(choice.name).font(MadarTypography.title())
                    Text("سيتغيّر \(session.digits(changes.count)) إعداد").font(MadarTypography.section())
                    ForEach(changes, id: \.key) { definition in
                        MadarCard {
                            VStack(alignment: .leading, spacing: 8) {
                                Text(definition.title).font(MadarTypography.section())
                                HStack {
                                    Text(label(session.values[definition.key], definition: definition))
                                    Image(systemName: "arrow.left").accessibilityLabel("إلى")
                                    Text(label(choice.settings[definition.key], definition: definition))
                                }.font(MadarTypography.body())
                            }
                        }
                    }
                    if !choice.layouts.isEmpty { Text("ترتيب \(session.digits(choice.layouts.count)) غرف غير متاح في هذا الإصدار ولن يُطبّق.").foregroundStyle(theme.secondaryInk) }
                    if ignored > 0 { Text("\(session.digits(ignored)) إعداد غير متاح في هذا الإصدار سيُتجاهل.").foregroundStyle(theme.secondaryInk) }
                    Text("التراجع متاح فور التطبيق ولمدة دقيقة واحدة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Button("طبّق النمط") {
                        let applicable = choice.settings.filter { key, _ in known.contains { $0.key == key } }
                        session.applyPreset(applicable) { dismiss() }
                    }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("apply-preset")
                }.padding(16)
            }.background(theme.background).foregroundStyle(theme.ink)
                .toolbar { ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } } }
        }
    }
    private func label(_ value: JSONValue?, definition: SettingDefinition) -> String {
        if let option = definition.options.first(where: { $0.value == value }) { return option.label }
        if case .bool(let bool) = value { return bool ? "نعم" : "لا" }
        if case .number(let num) = value { return session.digits(Int(num)) }
        if case .string(let text) = value { return text }
        return "—"
    }
}
