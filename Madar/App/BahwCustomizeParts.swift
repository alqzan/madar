import SwiftUI
import MadarCore
import MadarDesign

/// M4-V04 · `bahw/05-W4-Takhsis.jpg`: the live lobby model and the block list. Both read and write `bahw.layout` only;
/// rooms not built yet (habits, money, Mihbara) keep their slots in the setting but have no row here (RL9).
extension BahwBlock {
    var detail: String {
        switch self {
        case .salah: "القادمة والفروض"; case .quran: "في صدرك والمراجعة"; case .notes: "صفحة اليوم وصورتها"
        case .year: "كم مضى وكم بقي"; case .upcoming: "كم بقي على ما يهمّك"; default: ""
        }
    }
    var tone: String { switch self { case .salah: "amber"; case .quran: "green"; case .notes: "clay"; case .year: "gregorianInk"; case .upcoming: "clay"; default: "sepia" } }
}
extension BahwBlockSize {
    var title: String { switch self { case .icon: "أيقونة"; case .small: "صغيرة"; case .wide: "عريضة"; case .large: "كبيرة" } }
}

struct BahwCustomizePreview: View {
    @Bindable var session: AppSession
    let changes: String
    let reset: () -> Void
    private var lobby: RoomTheme { RoomTheme(room: "bahw", dark: session.string("core.theme") == "dark") }
    private var layout: BahwLayoutValue { BahwLayoutValue(session.values["bahw.layout"]) }
    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack(alignment: .top, spacing: 14) {
                VStack(alignment: .leading, spacing: 10) {
                    HStack(spacing: 6) { Circle().fill(lobby.color("green")).frame(width: 8, height: 8); Text("نموذج حيّ").font(MadarTypography.caption()).foregroundStyle(lobby.accent) }
                    Text("بهوك كما سيظهر").font(MadarTypography.cardTitle()).lineLimit(1).minimumScaleFactor(0.8)
                    VStack(alignment: .leading, spacing: 7) {
                        line("الودجات", sizesSummary)
                        line("السنة", label("bahw.yearWhich"))
                        line("الأيام", label("bahw.upcomingCount"))
                        line("اليوم", label("core.dayStart"))
                    }
                    Text(changes).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk).accessibilityIdentifier("customization-changes")
                }
                Spacer(minLength: 0)
                miniLobby.frame(width: 120, height: 236).accessibilityHidden(true)
            }
            HStack(spacing: 10) {
                Button { session.selectedTab = "foundation" } label: {
                    Text("افتح البهو").font(MadarTypography.section()).padding(.horizontal, 20).frame(minHeight: 48).foregroundStyle(lobby.onAccent).background(lobby.ink, in: .capsule)
                }.buttonStyle(.plain).accessibilityIdentifier("bahw-custom-open-lobby")
                Button { reset() } label: {
                    Text("أعِد الافتراضي").font(MadarTypography.section()).padding(.horizontal, 18).frame(minHeight: 48).overlay { Capsule().stroke(lobby.line) }
                }.buttonStyle(.plain).accessibilityIdentifier("reset-settings")
                Spacer(minLength: 0)
            }
        }
        .padding(20).background(lobby.color("amber").opacity(0.08), in: .rect(cornerRadius: 28)).background(lobby.surface, in: .rect(cornerRadius: 28))
        .overlay { RoundedRectangle(cornerRadius: 28).stroke(lobby.line) }
    }
    private var sizesSummary: String {
        let visible = layout.visible.map { layout.size($0) }
        return [BahwBlockSize.small, .wide, .large, .icon].compactMap { size in
            let n = visible.filter { $0 == size }.count
            return n == 0 ? nil : session.digits(n) + " " + size.title
        }.joined(separator: "، ")
    }
    private func label(_ key: String) -> String {
        session.schema.settings.first(where: { $0.key == key })?.options.first(where: { $0.value == session.values[key] })?.label ?? ""
    }
    private func line(_ title: String, _ value: String) -> some View {
        HStack(spacing: 12) {
            Text(title).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk).frame(width: 54, alignment: .leading)
            Text(value).font(MadarTypography.caption().bold()).lineLimit(2).fixedSize(horizontal: false, vertical: true)
        }
    }
    /// A small phone drawn with the same packing as the lobby (`BahwGrid.pack`).
    private var miniLobby: some View {
        let visible = layout.visible, placements = BahwGrid.pack(visible.map { ($0.rawValue, layout.size($0)) })
        return VStack(spacing: 6) {
            HStack { Circle().stroke(lobby.secondaryInk, lineWidth: 1).frame(width: 9, height: 9); Circle().stroke(lobby.secondaryInk, lineWidth: 1).frame(width: 9, height: 9); Spacer(); Capsule().fill(lobby.ink).frame(width: 48, height: 6) }
            GeometryReader { geometry in
                let gap: CGFloat = 4, unit = (geometry.size.width - 3 * gap) / 4
                ForEach(Array(zip(visible, placements)), id: \.0) { block, place in
                    let w = CGFloat(place.size.columns) * unit + CGFloat(place.size.columns - 1) * gap, h = CGFloat(place.size.rows) * unit + CGFloat(place.size.rows - 1) * gap
                    RoundedRectangle(cornerRadius: 7).fill(lobby.color(block.tone).opacity(0.16))
                        .overlay { RoundedRectangle(cornerRadius: 7).stroke(lobby.line) }
                        .overlay { if place.size != .icon { Text(block.title).font(.custom("thmanyahsans-Bold", size: 11, relativeTo: .caption2)).foregroundStyle(lobby.ink).lineLimit(1).minimumScaleFactor(0.7).padding(2) } }
                        .frame(width: w, height: h)
                        .position(x: CGFloat(place.column) * (unit + gap) + w / 2, y: CGFloat(place.row) * (unit + gap) + h / 2)
                }
            }.clipped()
        }
        .padding(9).background(lobby.background, in: .rect(cornerRadius: 26)).overlay { RoundedRectangle(cornerRadius: 26).stroke(lobby.ink.opacity(0.6), lineWidth: 1.5) }
    }
}

struct BahwBlocksSection: View {
    @Bindable var session: AppSession
    @State private var expanded = true
    private var lobby: RoomTheme { RoomTheme(room: "bahw", dark: session.string("core.theme") == "dark") }
    private var layout: BahwLayoutValue { BahwLayoutValue(session.values["bahw.layout"]) }
    private var rows: [BahwBlock] { layout.blocks.compactMap(BahwBlock.init(rawValue:)).filter { BahwBlock.built.contains($0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 18)).frame(width: 48, height: 48).background(lobby.color("amber").opacity(0.16), in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("الودجات وأحجامها").font(MadarTypography.section())
                        Text(summary).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(lobby.secondaryInk)
                }.contentShape(.rect)
            }.buttonStyle(.plain).accessibilityIdentifier("bahw-custom-blocks")
            if expanded {
                Text("كل ودجة بأربعة أحجام، وكلما كبرت عرضت أكثر. اسحب المقبض لترتيبها، والمفتاح يُظهرها أو يُخفيها. وتقدر تفعل هذا كله من البهو بالضغط المطوّل.")
                    .font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk).fixedSize(horizontal: false, vertical: true)
                ForEach(rows, id: \.self) { block in row(block) }
            }
        }
        .padding(14).background(lobby.surface, in: .rect(cornerRadius: 26)).overlay { RoundedRectangle(cornerRadius: 26).stroke(expanded ? lobby.accent : lobby.line, lineWidth: expanded ? 1.2 : 1) }
    }
    private var summary: String {
        let shown = layout.visible, sizes = shown.map { layout.size($0) }
        let parts = [session.digits(shown.count) + " من " + session.digits(rows.count) + " ظاهرة"] + [BahwBlockSize.small, .wide, .large, .icon].compactMap { size in
            let n = sizes.filter { $0 == size }.count; return n == 0 ? nil : session.digits(n) + " " + size.title
        }
        return parts.joined(separator: "، ")
    }
    private func row(_ block: BahwBlock) -> some View {
        let size = layout.size(block), shown = !layout.hidden.contains(block.rawValue)
        return HStack(spacing: 7) {
            Image(systemName: "circle.grid.2x3.fill").font(.system(size: 11)).foregroundStyle(lobby.secondaryInk).accessibilityHidden(true)
            Image(systemName: block.symbol).font(.system(size: 13)).foregroundStyle(lobby.ink).frame(width: 30, height: 30).background(lobby.color(block.tone).opacity(0.16), in: .rect(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(MadarTypography.section()).lineLimit(1)
                Text(size.title + "، " + block.detail).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk).lineLimit(1).minimumScaleFactor(0.75)
            }.frame(minWidth: 70, alignment: .leading).layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach([BahwBlockSize.icon, .small, .wide, .large], id: \.self) { option in
                    Button { update { $0.sizes[block.rawValue] = option.rawValue } } label: { glyph(option, on: option == size) }
                        .buttonStyle(.plain).accessibilityLabel(option.title).accessibilityAddTraits(option == size ? .isSelected : [])
                        .accessibilityIdentifier("bahw-custom-size-\(block.rawValue)-\(String(describing: option))")
                }
            }
            Toggle(block.title, isOn: Binding(get: { shown }, set: { on in update { value in
                value.hidden.removeAll { $0 == block.rawValue }; if !on { value.hidden.append(block.rawValue) }
            } })).labelsHidden().tint(lobby.color("green")).scaleEffect(0.8).frame(width: 52).accessibilityIdentifier("bahw-custom-visible-\(block.rawValue)")
        }
        .padding(.horizontal, 9).padding(.vertical, 9)
        .background(lobby.background.opacity(0.55), in: .rect(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(lobby.line) }
        .draggable(block.rawValue)
        .dropDestination(for: String.self) { items, _ in
            guard let moved = items.first, moved != block.rawValue else { return false }
            update { value in
                guard let from = value.blocks.firstIndex(of: moved), let to = value.blocks.firstIndex(of: block.rawValue) else { return }
                value.blocks.remove(at: from); value.blocks.insert(moved, at: to)
            }
            return true
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("bahw-custom-block-" + block.rawValue)
    }
    private func glyph(_ option: BahwBlockSize, on: Bool) -> some View {
        let shape: CGSize = switch option { case .icon: .init(width: 4, height: 4); case .small: .init(width: 8, height: 8); case .wide: .init(width: 16, height: 8); case .large: .init(width: 13, height: 13) }
        return RoundedRectangle(cornerRadius: 2).fill(on ? lobby.surface : lobby.secondaryInk.opacity(0.6)).frame(width: shape.width, height: shape.height)
            .frame(width: 28, height: 28).background(on ? lobby.ink : lobby.surface, in: .rect(cornerRadius: 8)).overlay { RoundedRectangle(cornerRadius: 8).stroke(lobby.line) }
    }
    private func update(_ change: (inout BahwLayoutValue) -> Void) {
        var value = layout; change(&value)
        guard value != layout else { return }
        session.set(value.json, key: "bahw.layout")
    }
}
