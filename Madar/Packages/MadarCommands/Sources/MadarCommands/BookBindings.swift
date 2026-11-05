import Foundation

/// Owner, 22 Oct 2026: «ابي ٢٠ شكل ولون مختلف يشابه الكتب المعروفه». Each binding is a printed edition's look —
/// leather or cloth, its gilt or ink, and one ornament — drawn on the shelf for single books and for sets alike.
/// Every colour that carries text is checked against the colour behind it (≥ 4.5:1, `BookBindingsTests`).
public enum BookBindings {
    public enum Ornament: String, Sendable, CaseIterable {
        /// Thin gilt rules at head and foot.
        case goldBands
        /// A row of small lozenges between two rules.
        case lozengeBand
        /// A pointed arch at head and foot, as on Mushaf and classical bindings.
        case arabesqueHead
        /// Raised ribs across the spine, as on old leather.
        case raisedRibs
        /// The title on a framed label of another colour.
        case titlePanel
        /// Head and foot in a second colour, divided by a gilt rule.
        case twoTone
        /// A wide coloured band near head and foot.
        case stripedBands
        /// No ornament: clean type, a modern trade book.
        case plainModern
        /// An eight-point star medallion.
        case geometricStar
        /// A dotted gilt frame along the spine.
        case dottedBorder
    }

    public struct Binding: Sendable, Equatable {
        public let name: String
        /// Base leather or cloth, and a darker shade for its curve.
        public let base: UInt32
        public let shade: UInt32
        /// Title and number ink on the base.
        public let ink: UInt32
        public let ornament: Ornament
        /// The label, band or two-tone colour, and the ink on it when text sits there.
        public let accent: UInt32
        public let accentInk: UInt32
        /// A short single title reads across the spine (modern covers); otherwise down it.
        public let acrossWhenShort: Bool
    }

    public static let all: [Binding] = [
        .init(name: "عنابي مذهّب بقوس", base: 0x6B1E2B, shade: 0x4A1019, ink: 0xE2C275, ornament: .arabesqueHead, accent: 0x4A1019, accentInk: 0xE2C275, acrossWhenShort: false),
        .init(name: "زمردي بلوحة عنابية", base: 0x1F4D3A, shade: 0x143427, ink: 0xE8CF8E, ornament: .titlePanel, accent: 0x6B1E2B, accentInk: 0xF0DDB0, acrossWhenShort: false),
        .init(name: "كحلي بخطوط ذهبية", base: 0x14213D, shade: 0x0B1426, ink: 0xD9C28A, ornament: .goldBands, accent: 0x0B1426, accentInk: 0xD9C28A, acrossWhenShort: false),
        .init(name: "أسود مضلّع", base: 0x1B1B1D, shade: 0x0C0C0D, ink: 0xD4AF5A, ornament: .raisedRibs, accent: 0x0C0C0D, accentInk: 0xD4AF5A, acrossWhenShort: false),
        .init(name: "قرمزي بأشرطة ذهبية", base: 0x7A2E22, shade: 0x55190F, ink: 0xF0DDB0, ornament: .stripedBands, accent: 0xD4AF5A, accentInk: 0x2B1A0E, acrossWhenShort: false),
        .init(name: "زيتي بمعيّنات", base: 0x3B4A2A, shade: 0x27331B, ink: 0xE6D3A0, ornament: .lozengeBand, accent: 0x27331B, accentInk: 0xE6D3A0, acrossWhenShort: false),
        .init(name: "فيروزي منقّط", base: 0x0F4C55, shade: 0x093339, ink: 0xEBD9A6, ornament: .dottedBorder, accent: 0x093339, accentInk: 0xEBD9A6, acrossWhenShort: false),
        .init(name: "جملي عتيق", base: 0xC2A06B, shade: 0xA8854F, ink: 0x2B1A0E, ornament: .raisedRibs, accent: 0x2B1A0E, accentInk: 0xE3C487, acrossWhenShort: false),
        .init(name: "بني ثنائي", base: 0x4A2C1A, shade: 0x33190C, ink: 0xE3C487, ornament: .twoTone, accent: 0x2B1A0E, accentInk: 0xE3C487, acrossWhenShort: false),
        .init(name: "كريمي بنجمة", base: 0xF1E8D2, shade: 0xDDD0B2, ink: 0x3A2A1A, ornament: .geometricStar, accent: 0x6B1E2B, accentInk: 0xF2E6C4, acrossWhenShort: false),
        .init(name: "بورجندي مذهّب", base: 0x8A1F2E, shade: 0x5E1220, ink: 0xF4E6C0, ornament: .goldBands, accent: 0x5E1220, accentInk: 0xF4E6C0, acrossWhenShort: false),
        .init(name: "أخضر بلوحة عاجية", base: 0x2E5E4E, shade: 0x1D4033, ink: 0xF2E7C9, ornament: .titlePanel, accent: 0xF2E7C9, accentInk: 0x1D4033, acrossWhenShort: false),
        .init(name: "بني قماشي", base: 0x7B4A2B, shade: 0x5A3219, ink: 0xF1E1BC, ornament: .goldBands, accent: 0x5A3219, accentInk: 0xF1E1BC, acrossWhenShort: false),
        .init(name: "رمادي داكن حديث", base: 0x2A2D3A, shade: 0x171923, ink: 0xC9CCD4, ornament: .plainModern, accent: 0x171923, accentInk: 0xC9CCD4, acrossWhenShort: true),
        .init(name: "رمادي فاتح حديث", base: 0xE4E6E8, shade: 0xC9CDD1, ink: 0x1E2430, ornament: .plainModern, accent: 0x1E2430, accentInk: 0xE4E6E8, acrossWhenShort: true),
        .init(name: "عاجي بشريطين", base: 0xF7F3EA, shade: 0xE8E1D0, ink: 0x222222, ornament: .stripedBands, accent: 0x6B1E2B, accentInk: 0xF2E6C4, acrossWhenShort: true),
        .init(name: "توتي منقّط", base: 0x5A2A3E, shade: 0x3C1727, ink: 0xE5C98E, ornament: .dottedBorder, accent: 0x3C1727, accentInk: 0xE5C98E, acrossWhenShort: false),
        .init(name: "أخضر غابة بمعيّنات", base: 0x1C5B3F, shade: 0x103D2A, ink: 0xE6C873, ornament: .lozengeBand, accent: 0x103D2A, accentInk: 0xE6C873, acrossWhenShort: false),
        .init(name: "نيلي ثنائي", base: 0x2B3A55, shade: 0x1B2740, ink: 0xE9E2CF, ornament: .twoTone, accent: 0x14213D, accentInk: 0xE9E2CF, acrossWhenShort: false),
        .init(name: "خمري بلوحة ورقية", base: 0x7A2436, shade: 0x561726, ink: 0xF2E6C4, ornament: .titlePanel, accent: 0xF2E6C4, accentInk: 0x2A1A10, acrossWhenShort: false),
    ]

    /// WCAG 2 contrast ratio between two sRGB colours.
    public static func contrast(_ a: UInt32, _ b: UInt32) -> Double {
        func luminance(_ c: UInt32) -> Double {
            func channel(_ v: UInt32) -> Double { let s = Double(v) / 255; return s <= 0.03928 ? s / 12.92 : pow((s + 0.055) / 1.055, 2.4) }
            return 0.2126 * channel((c >> 16) & 0xFF) + 0.7152 * channel((c >> 8) & 0xFF) + 0.0722 * channel(c & 0xFF)
        }
        let (x, y) = (luminance(a), luminance(b))
        return (max(x, y) + 0.05) / (min(x, y) + 0.05)
    }

    /// FB-36: the binding whose leather is closest to a cover photo's average colour (0xRRGGBB), so a book with its
    /// own cover keeps one of the twenty contrast-tested bindings on the shelf instead of an untested colour.
    /// Distance is the "redmean" weighted RGB distance, which tracks perceived difference better than plain RGB.
    public static func nearest(to rgb: UInt32) -> Int {
        func parts(_ c: UInt32) -> (Double, Double, Double) { (Double((c >> 16) & 0xFF), Double((c >> 8) & 0xFF), Double(c & 0xFF)) }
        let (r, g, b) = parts(rgb)
        func distance(_ c: UInt32) -> Double {
            let (r2, g2, b2) = parts(c), mean = (r + r2) / 2
            let dr = r - r2, dg = g - g2, db = b - b2
            return (2 + mean / 256) * dr * dr + 4 * dg * dg + (2 + (255 - mean) / 256) * db * db
        }
        return all.indices.min { distance(all[$0].base) < distance(all[$1].base) } ?? 0
    }

    /// A stable binding per book that never repeats its neighbour on the shelf.
    public static func indices(for ids: [UUID]) -> [UUID: Int] {
        var result: [UUID: Int] = [:], previous = -1
        for id in ids {
            var h: UInt64 = 1469598103934665603
            for byte in id.uuidString.utf8 { h = (h ^ UInt64(byte)) &* 1099511628211 }
            var index = Int(h % UInt64(all.count))
            if index == previous { index = (index + 1) % all.count }
            result[id] = index; previous = index
        }
        return result
    }
}
