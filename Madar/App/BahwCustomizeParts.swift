import SwiftUI
import MadarCore
import MadarDesign

/// M4-V04 · `bahw/05-W4-Takhsis.jpg`: the live lobby model and the block list. Both read and write `bahw.layout` only.
/// RL9 keeps unbuilt rooms out of the visible list; rooms whose milestones shipped appear here.
extension BahwBlock {
    var detail: String {
        switch self {
        case .habits: "عاداتك اليوم وفتراتها"; case .salah: "القادمة والفروض"; case .quran: "في صدرك والمراجعة"; case .notes: "صفحة اليوم وصورتها"
        case .year: "كم مضى وكم بقي"; case .upcoming: "كم بقي على ما يهمّك"; case .mal: "لك الآن وميزانيتك"; case .mihbara: "كتابك وصفحتك"
        }
    }
    var tone: String { switch self { case .salah: "amber"; case .quran: "green"; case .notes: "clay"; case .year: "gregorianInk"; case .upcoming: "clay"; default: "sepia" } }
}
extension BahwBlockSize {
    var title: String { switch self { case .icon: "أيقونة"; case .small: "صغيرة"; case .wide: "عريضة"; case .large: "كبيرة" } }
}

struct BahwBlocksSection: View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session: AppSession
    @State private var expanded = true
    private var lobby: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }
    private var layout: BahwLayoutValue { BahwLayoutValue(session.values["bahw.layout"]) }
    private var rows: [BahwBlock] { layout.blocks.compactMap(BahwBlock.init(rawValue:)).filter { BahwBlock.built.contains($0) } }
    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Button { withAnimation(.snappy) { expanded.toggle() } } label: {
                HStack(spacing: 12) {
                    Image(systemName: "line.3.horizontal").font(.system(size: 18)).frame(width: 48, height: 48).background(lobby.color("amber").opacity(0.16), in: .rect(cornerRadius: 14))
                    VStack(alignment: .leading, spacing: 3) {
                        Text("الودجات وأحجامها").font(MadarTypography.section())
                        Text(figure: summary).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk)
                    }
                    Spacer()
                    Image(systemName: expanded ? "chevron.up" : "chevron.down").foregroundStyle(lobby.secondaryInk)
                }.contentShape(.rect)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("bahw-custom-blocks")
            if expanded {
                Text("كلما كبرت الودجة، عرضت أكثر. اسحب لترتيبها، واستخدم مفتاحها لإظهارها أو إخفائها.")
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
            MadarGlyph(block.symbol, size: 17).foregroundStyle(lobby.ink).frame(width: 30, height: 30).background(lobby.color(block.tone).opacity(0.16), in: .rect(cornerRadius: 9)).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(block.title).font(MadarTypography.section()).lineLimit(1)
                Text(size.title + "، " + block.detail).font(MadarTypography.caption()).foregroundStyle(lobby.secondaryInk).lineLimit(1).minimumScaleFactor(0.85)
            }.frame(minWidth: 70, alignment: .leading).layoutPriority(1)
            Spacer(minLength: 0)
            HStack(spacing: 3) {
                ForEach([BahwBlockSize.icon, .small, .wide, .large], id: \.self) { option in
                    Button { update { $0.sizes[block.rawValue] = option.rawValue } } label: { glyph(option, on: option == size) }
                        .buttonStyle(.madarPlain).accessibilityLabel(option.title).accessibilityAddTraits(option == size ? .isSelected : [])
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
                guard value.blocks.contains(moved), value.blocks.contains(block.rawValue) else { return }
                value.blocks.removeAll { $0 == moved }
                value.blocks.insert(moved, at: value.blocks.firstIndex(of: block.rawValue) ?? value.blocks.endIndex)
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
