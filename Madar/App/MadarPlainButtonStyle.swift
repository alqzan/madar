import SwiftUI

/// AU-95 (owner, 29 Oct: «مشاكل بالتطبيق بالضغط والازرار»): `.plain` hit-tests only the drawn glyphs and text,
/// so the empty part of a 44 pt frame, a full-width row or a dashed «أضف» box took no tap. This keeps `.plain`'s
/// look (pressed and disabled states included) and makes the whole label frame tappable.
struct MadarPlainButtonStyle: PrimitiveButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button(role: configuration.role, action: configuration.trigger) {
            configuration.label.contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

extension PrimitiveButtonStyle where Self == MadarPlainButtonStyle {
    static var madarPlain: MadarPlainButtonStyle { MadarPlainButtonStyle() }
}
