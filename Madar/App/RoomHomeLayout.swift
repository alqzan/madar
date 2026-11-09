import SwiftUI
import MadarCore
import MadarDesign

/// Existing layout settings change presentation only; pinned content and stored records stay intact.
@MainActor struct RoomHomeLayout {
    let key: String
    let blocks: [String]
    let pinned: Set<String>
    let hidden: Set<String>
    private var object: [String: JSONValue]

    init(session: AppSession, key: String) {
        self.key = key
        guard case .object(let defaults) = session.schema.settings.first(where: { $0.key == key })?.defaultValue else {
            blocks = []; pinned = []; hidden = []; object = [:]; return
        }
        func strings(_ value: JSONValue?) -> [String] {
            guard case .array(let items) = value else { return [] }
            return items.compactMap { if case .string(let text) = $0 { text } else { nil } }
        }
        let allowed = strings(defaults["blocks"])
        if case .object(let saved) = session.values[key] { object = saved } else { object = defaults }
        var order: [String] = []
        for id in strings(object["blocks"]) + allowed where allowed.contains(id) && !order.contains(id) { order.append(id) }
        let fixed = strings(defaults["pinned"])
        if key == "salah.layout" { blocks = fixed + order.filter { !fixed.contains($0) } }
        else if key == "notes.layout" { blocks = order.filter { $0 != "todayBar" } + ["todayBar"] }
        else { blocks = order }
        pinned = Set(fixed)
        hidden = Set(strings(object["hidden"])).intersection(allowed).subtracting(pinned)
    }
    var visible: [String] { blocks.filter { !hidden.contains($0) } }
    func toggled(_ id: String) -> JSONValue {
        var next = hidden
        if !pinned.contains(id) { if next.contains(id) { next.remove(id) } else { next.insert(id) } }
        return payload(order: blocks, hidden: next)
    }
    func moved(_ id: String, by delta: Int) -> JSONValue {
        var order = blocks
        if let index = order.firstIndex(of: id), order.indices.contains(index + delta) { order.swapAt(index, index + delta) }
        return payload(order: order, hidden: hidden)
    }
    private func payload(order: [String], hidden: Set<String>) -> JSONValue {
        var value = object
        value["blocks"] = .array(order.map(JSONValue.string))
        value["pinned"] = .array(blocks.filter(pinned.contains).map(JSONValue.string))
        value["hidden"] = .array(blocks.filter(hidden.contains).map(JSONValue.string))
        return .object(value)
    }
    static let rooms = [("salah", "الصلاة"), ("quran", "القرآن"), ("mal", "المال"), ("notes", "المذكرات"), ("mihbara", "المحبرة")]
    static func title(_ id: String, room: String) -> String {
        let titles: [String: String] = switch room {
        case "salah": ["next": "الصلاة القادمة", "riwaq": "رواق الصلوات", "pending": "ما ينتظر تسجيلك", "hali": "حالي", "qiyam": "قيام الليل"]
        case "quran": ["sadr": "في صدرك", "path": "مسار اليوم", "log14": "آخر أربعة عشر يومًا", "tools": "أدوات القرآن"]
        case "mal": ["curve": "منحنى الدورة", "now": "مالك الآن", "envelopes": "المظاريف", "limits": "حدود الصرف", "obligations": "الالتزامات"]
        case "notes": ["memory": "نافذة الذكريات", "thatDay": "ذاك اليوم", "sinceThatDay": "منذ ذاك اليوم", "days": "أيامك", "todayBar": "اكتب اليوم"]
        default: ["shelf": "رفوف الكتب", "desk": "رحل القراءة", "notebook": "الدفتر الخاص"]
        }
        return titles[id] ?? id
    }
}

struct RoomHomeLayoutSection: View {
    @Bindable var session: AppSession
    @State private var expanded = false
    var searching = false
    @Environment(\.roomTheme) private var theme
    var body: some View {
        MadarCard {
            DisclosureGroup(isExpanded: Binding(get: { searching || expanded }, set: { expanded = $0 })) {
                VStack(spacing: 0) {
                    ForEach(RoomHomeLayout.rooms, id: \.0) { room in
                        NavigationLink {
                            RoomHomeLayoutEditor(session: session, room: room.0, title: room.1)
                        } label: {
                            HStack {
                                Text(room.1).font(MadarTypography.body())
                                Spacer()
                                Text("رتّب ما تراه").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                            }.frame(minHeight: 48)
                        }.accessibilityIdentifier("room-layout-" + room.0)
                    }
                }.padding(.top, 10)
            } label: {
                Label("ما يعرضه كل باب", systemImage: "rectangle.3.group").font(MadarTypography.section()).frame(minHeight: 44)
            }
        }
    }
}

struct RoomHomeLayoutEditor: View {
    @Bindable var session: AppSession
    let room: String
    let title: String
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dismiss) private var dismiss
    private var theme: RoomTheme { .init(room: room, dark: colorScheme == .dark) }
    private var layout: RoomHomeLayout { .init(session: session, key: room + ".layout") }
    private var blocks: [String] { room == "mihbara" ? layout.blocks.filter { ["shelf"].contains($0) } : layout.blocks.filter { $0 != "qiyam" } }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                HStack {
                    Button { dismiss() } label: { Label("رجوع", systemImage: "chevron.right").padding(.horizontal, 12).frame(minHeight: 44).glassEffect(.regular.interactive(), in: .capsule) }
                        .accessibilityIdentifier("room-layout-back")
                    Spacer(); Text(title).font(MadarTypography.title())
                }
                Text(room == "mihbara" ? "تُخفي الأجزاء الاختيارية، ويبقى الرحل والرف في مكانهما." : "رتّب ما تراه وأخفِ ما لا تحتاجه. سجلاتك تبقى محفوظة.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                if room == "notes" { Text("الترتيب يخصّ شكل النافذة، والإخفاء يسري على أشكال المذكرات كلها.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
                MadarCard {
                    VStack(spacing: 8) {
                        ForEach(blocks, id: \.self) { id in
                            HStack(spacing: 6) {
                                Text(RoomHomeLayout.title(id, room: room)).font(MadarTypography.body())
                                Spacer(minLength: 4)
                                if layout.pinned.contains(id) {
                                    Text("ثابت").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                } else {
                                    if room != "mihbara" {
                                        arrow("chevron.up", id: id, delta: -1)
                                        arrow("chevron.down", id: id, delta: 1)
                                    }
                                    Toggle("إظهار " + RoomHomeLayout.title(id, room: room), isOn: Binding(get: { !layout.hidden.contains(id) }, set: { _ in session.set(layout.toggled(id), key: layout.key) }))
                                        .labelsHidden().accessibilityIdentifier("room-block-" + room + "-" + id)
                                }
                            }.frame(minHeight: 52)
                        }
                    }
                }
                Button { session.reset([layout.key]) } label: { Text("أعِد الترتيب الافتراضي")
                    .font(MadarTypography.body()).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("room-layout-reset")
            }.padding(16)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .disabled(session.settingsWriteInProgress)
    }
    private func arrow(_ symbol: String, id: String, delta: Int) -> some View {
        let index = layout.blocks.firstIndex(of: id) ?? 0
        let target = index + delta
        let fixedPrayerBlock = room == "salah" && layout.blocks.indices.contains(target) && layout.pinned.contains(layout.blocks[target])
        let fixedDiaryBar = room == "notes" && layout.blocks.indices.contains(target) && layout.blocks[target] == "todayBar"
        return Button { session.set(layout.moved(id, by: delta), key: layout.key) } label: {
            Image(systemName: symbol).frame(width: 44, height: 44)
        }.buttonStyle(.madarPlain).disabled(!layout.blocks.indices.contains(target) || fixedPrayerBlock || fixedDiaryBar)
            .accessibilityLabel((delta < 0 ? "قدّم " : "أخّر ") + RoomHomeLayout.title(id, room: room))
            .accessibilityIdentifier("room-block-" + room + "-" + id + (delta < 0 ? "-up" : "-down"))
    }
}
