import SwiftUI

/// Room identities are vector templates; utility/action symbols retain their system meaning.
struct MadarGlyph: View {
    let name: String
    var size: CGFloat = 18
    init(_ name: String, size: CGFloat = 18) { self.name = name; self.size = size }
    var body: some View {
        Group {
            if name.hasPrefix("Madar") { Image(name).renderingMode(.template).resizable().scaledToFit().frame(width: size, height: size) }
            else { Image(systemName: name).font(.system(size: size)) }
        }.accessibilityHidden(true)
    }
}
