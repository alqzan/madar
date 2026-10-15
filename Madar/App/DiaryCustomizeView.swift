import SwiftUI
import MadarData
import MadarDesign

struct DiaryHomeLayout {
    static let all = ["memory", "thatDay", "sinceThatDay", "days", "todayBar"]
    static let titles = ["memory": "الذكرى", "thatDay": "ذاك اليوم", "sinceThatDay": "منذ ذاك اليوم", "days": "أيامك", "todayBar": "شريط صفحة اليوم"]
    var order: [String]
    var hidden: Set<String>
    init(_ value: JSONValue?) {
        var seen = Set<String>()
        order = (value?.object?["blocks"]?.array?.compactMap(\.string) ?? Self.all).filter { Self.all.contains($0) && $0 != "todayBar" && seen.insert($0).inserted }
        for id in Self.all where id != "todayBar" && !order.contains(id) { order.append(id) }
        order.append("todayBar")
        hidden = Set(value?.object?["hidden"]?.array?.compactMap(\.string) ?? []).intersection(["thatDay", "sinceThatDay", "days"])
    }
    var payload: JSONValue { .object(["blocks": .array(order.map(JSONValue.string)), "pinned": .array([.string("memory"), .string("todayBar")]), "hidden": .array(hidden.sorted().map(JSONValue.string)), "sizes": .object([:])]) }
    func move(_ id: String, by offset: Int) -> Self {
        var result = self
        guard let i = order.firstIndex(of: id), id != "todayBar", (0..<(order.count-1)).contains(i+offset) else { return self }
        result.order.swapAt(i, i+offset); return result
    }
    func toggle(_ id: String) -> Self { var result = self; if result.hidden.contains(id) { result.hidden.remove(id) } else if !["memory", "todayBar"].contains(id) { result.hidden.insert(id) }; return result }
}

struct DiaryCustomizeView: View {
    @Bindable var app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var query = ""
    @State private var expanded: Set<String> = ["home"]
    @State private var confirmReset = false
    private var layout: DiaryHomeLayout { .init(app.values["notes.layout"]) }
    private let groups: [(String, String, String, [String])] = [
        ("memory", "أي ذكرى تظهر", "clock", ["notes.match", "notes.noMemory", "notes.yearsBack", "notes.includeDayOne"]),
        ("display", "ما تعرضه الذكرى", "photo", ["notes.memorySize", "notes.showPhoto", "notes.showPlace", "notes.showAutoSections", "notes.sinceMetrics", "notes.autoLines"]),
        ("ink", "الكتابة والهامش", "pencil", ["notes.secondInk"])
    ]
    private var keys: [String] { ["notes.homeShape", "notes.layout"] + groups.flatMap(\.3) }
    private var changed: Int { app.schema.settings.filter { keys.contains($0.key) && app.values[$0.key] != $0.defaultValue }.count }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Label("المذكرات", systemImage: "chevron.backward").font(MadarTypography.caption()).frame(minHeight: 44) }.buttonStyle(.plain).accessibilityIdentifier("diary-customize-back")
                    Spacer()
                    Text("خصّص المذكرات").font(DiaryType.title)
                }
                Text("كل تعديل يُحفظ وحده").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity, alignment: .center)
                preview
                HStack {
                    Image(systemName: "magnifyingglass")
                    TextField("ابحث: الهجري، الهامش، الصورة…", text: $query).font(MadarTypography.body()).accessibilityIdentifier("diary-customize-search")
                }.padding(16).background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line) }
                if matches("الرئيسية ترتيب الواجهة النافذة الأصداء الهامش") { homeCard }
                ForEach(groups, id: \.0) { group in
                    let definitions = app.schema.settings.filter { group.3.contains($0.key) && matches(group.1 + " " + $0.title) }
                    if !definitions.isEmpty {
                        section(group.0, title: group.1, subtitle: summary(group.0), symbol: group.2) {
                            ForEach(definitions, id: \.key) { definition in
                                Divider().overlay(theme.line)
                                if definition.key == "notes.sinceMetrics" { metricControls }
                                else if definition.key == "notes.autoLines" { autoControls }
                                else { SettingControl(definition: definition, session: app) }
                            }
                        }
                    }
                }
                if !query.isEmpty && !matches("الرئيسية ترتيب الواجهة النافذة الأصداء الهامش") && !app.schema.settings.contains(where: { keys.contains($0.key) && matches($0.title) }) {
                    Text("لا إعداد بهذا الاسم. جرّب كلمة أقصر.").font(MadarTypography.body()).padding(16)
                }
                Text("بداية اليوم والمظهر والتقويم العام من «خصّص مدار». إخفاء الذكرى أو تغيير الشكل لا يغيّر كتابتك.")
                    .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 12)
            }.padding(16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }.background(theme.background).foregroundStyle(theme.ink).toolbarVisibility(.hidden, for: .navigationBar)
            .safeAreaInset(edge: .bottom) { if app.undoToken != nil { UndoToast(message: app.undoMessage, undo: app.undo) } }
            .confirmationDialog("أعِد إعدادات المذكرات؟", isPresented: $confirmReset, titleVisibility: .visible) {
                Button("أعِد الافتراضي", role: .destructive) { app.reset(keys) }.accessibilityIdentifier("diary-customize-reset-confirm")
            } message: { Text("يعود الشكل والترتيب والإعدادات. البيانات لا تُمسّ.") }
    }
    private var preview: some View {
        HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 10) {
                Label("معاينة حيّة", systemImage: "circle.fill").font(DiaryType.label).foregroundStyle(theme.accent)
                Text("المذكرات كما ستظهر").font(DiaryType.heading)
                previewLine("الأجزاء", app.digits(layout.order.count-layout.hidden.count) + " ظاهرة")
                previewLine("شكل الرئيسية", label("notes.homeShape"))
                previewLine("المطابقة", label("notes.match"))
                previewLine("إذا لا ذكرى", label("notes.noMemory"))
                Text(changed == 0 ? "كما اتفقنا" : "عُدّل " + app.digits(changed) + " من الإعدادات").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                ViewThatFits(in: .horizontal) {
                    HStack(spacing: 6) { previewButtons }
                    VStack(alignment: .leading, spacing: 8) { previewButtons }
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            VStack(spacing: 5) {
                Capsule().fill(theme.ink.opacity(0.3)).frame(width: 30, height: 4).padding(.vertical, 5)
                ForEach(layout.order.filter { !layout.hidden.contains($0) }, id: \.self) { id in
                    RoundedRectangle(cornerRadius: id == "memory" && app.string("notes.homeShape") == "margin" ? 2 : 7)
                        .fill(id == "memory" ? theme.accent : theme.line)
                        .frame(height: id == "memory" ? 62 : 20)
                }
                Spacer(minLength: 0)
            }.padding(8).frame(width: 90, height: 210).overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.color("ink3Text")) }.accessibilityHidden(true)
        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 26)).overlay { RoundedRectangle(cornerRadius: 26).stroke(theme.line) }
    }
    @ViewBuilder private var previewButtons: some View {
        Button { dismiss() } label: { Text("افتح المذكرات").font(MadarTypography.caption()).padding(.horizontal, 13).frame(minHeight: 44).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }.buttonStyle(.plain).accessibilityIdentifier("diary-customize-open")
        Button { confirmReset = true } label: { Text("أعِد الافتراضي").font(MadarTypography.caption()).padding(.horizontal, 10).frame(minHeight: 44).overlay { Capsule().stroke(theme.line) } }.buttonStyle(.plain).accessibilityIdentifier("diary-customize-reset")
    }
    private func previewLine(_ title: String, _ value: String) -> some View { HStack { Text(title).foregroundStyle(theme.color("ink3Text")); Spacer(minLength: 5); Text(value) }.font(DiaryType.label) }
    private var homeCard: some View {
        section("home", title: "الرئيسية", subtitle: app.digits(layout.order.count-layout.hidden.count) + " ظاهرة · " + label("notes.homeShape"), symbol: "square.grid.2x2") {
            Text("الذكرى وشريط اليوم ظاهران دائمًا. ترتيب الكتل للنافذة، وإخفاء «ذاك اليوم» و«أيامك» يسري على الأشكال الثلاثة.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
            ForEach(layout.order, id: \.self) { id in
                Divider().overlay(theme.line)
                HStack {
                    Text(DiaryHomeLayout.titles[id] ?? id).font(MadarTypography.section()).frame(maxWidth: .infinity, alignment: .leading)
                    if app.string("notes.homeShape") == "window", id != "todayBar" {
                        arrow(id, offset: -1); arrow(id, offset: 1)
                    }
                    if ["memory", "todayBar"].contains(id) { Text("ثابت").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                    else {
                        Toggle(DiaryHomeLayout.titles[id] ?? id, isOn: Binding(get: { !layout.hidden.contains(id) }, set: { _ in app.set(layout.toggle(id).payload, key: "notes.layout") }))
                            .labelsHidden().tint(Color(.systemGreen)).accessibilityIdentifier("diary-block-" + id)
                    }
                }.frame(minHeight: 48)
            }
            Divider().overlay(theme.line)
            if let definition = app.schema.settings.first(where: { $0.key == "notes.homeShape" }) { SettingControl(definition: definition, session: app) }
        }
    }
    private func arrow(_ id: String, offset: Int) -> some View {
        let index = layout.order.firstIndex(of: id) ?? 0
        return Button { app.set(layout.move(id, by: offset).payload, key: "notes.layout") } label: { Image(systemName: offset < 0 ? "chevron.up" : "chevron.down").frame(width: 44, height: 44) }
            .buttonStyle(.plain).disabled(!(0..<(layout.order.count-1)).contains(index+offset) || app.settingsWriteInProgress)
            .accessibilityLabel((offset < 0 ? "قدّم " : "أخّر ") + (DiaryHomeLayout.titles[id] ?? id)).accessibilityIdentifier("diary-block-" + (offset < 0 ? "up-" : "down-") + id)
    }
    private var metricControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("مقاييس منذ ذاك اليوم").font(MadarTypography.section())
            ForEach([("sadr", "في صدرك"), ("fajrJamaah", "الفجر جماعة")], id: \.0) { id, title in
                Toggle(title, isOn: Binding(get: { app.values["notes.sinceMetrics"]?.array?.contains(.string(id)) == true }, set: { on in
                    var values = app.values["notes.sinceMetrics"]?.array ?? []; values.removeAll { $0 == .string(id) }; if on { values.append(.string(id)) }; app.set(.array(values), key: "notes.sinceMetrics")
                })).font(MadarTypography.body()).tint(Color(.systemGreen)).accessibilityIdentifier("diary-metric-" + id)
            }
        }
    }
    private var autoControls: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("اليوم يكتب نفسه").font(MadarTypography.section())
            ForEach([("salah", "الصلاة"), ("quran", "القرآن")], id: \.0) { id, title in
                Toggle(title, isOn: Binding(get: { app.values["notes.autoLines"]?.object?[id] == .bool(true) }, set: { on in
                    var values = app.values["notes.autoLines"]?.object ?? [:]; values[id] = .bool(on); app.set(.object(values), key: "notes.autoLines")
                })).font(MadarTypography.body()).tint(Color(.systemGreen)).accessibilityIdentifier("diary-auto-" + id)
            }
        }
    }
    private func section<Content: View>(_ id: String, title: String, subtitle: String, symbol: String, @ViewBuilder content: () -> Content) -> some View {
        let open = expanded.contains(id) || !query.isEmpty
        return VStack(alignment: .leading, spacing: 14) {
            Button { if expanded.contains(id) { expanded.remove(id) } else { expanded.insert(id) } } label: {
                HStack {
                    Image(systemName: symbol).font(.title3).foregroundStyle(theme.accent).frame(width: 44, height: 44).background(theme.background, in: .rect(cornerRadius: 12))
                    VStack(alignment: .leading, spacing: 4) { Text(title).font(DiaryType.heading); Text(subtitle).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                    Spacer(); Image(systemName: open ? "chevron.up" : "chevron.down")
                }.contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("diary-customize-section-" + id).accessibilityValue(open ? "مفتوح" : "مطوي")
            if open { content() }
        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 24)).overlay { RoundedRectangle(cornerRadius: 24).stroke(id == "home" && open ? theme.accent : theme.line) }
    }
    private func label(_ key: String) -> String { app.schema.settings.first { $0.key == key }?.options.first { $0.value == app.values[key] }?.label ?? "" }
    private func matches(_ text: String) -> Bool { query.isEmpty || normalized(text).contains(normalized(query)) }
    private func summary(_ id: String) -> String { switch id { case "memory": label("notes.match") + " · " + label("notes.noMemory"); case "ink": label("notes.secondInk"); default: app.bool("notes.showPhoto") ? "الصورة والمكان وسطـور مدار" : "سطور الذكرى" } }
}
