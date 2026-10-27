import SwiftUI
import MadarDesign

struct MoneyZakatScale: View {
    let pool: Int
    let nisab: Int?
    let visible: Bool
    let entered: Bool
    let theme: RoomTheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private var tilt: Double { guard visible, let nisab, nisab > 0 else { return 0 }; return pool >= nisab ? 18 : -18 }
    var body: some View {
        GeometryReader { g in
            let w = g.size.width, center = CGPoint(x: w/2, y: 62), shift = entered ? tilt : 0
            let left = CGPoint(x: 45, y: center.y - shift), right = CGPoint(x: w-45, y: center.y+shift)
            ZStack {
                Path { p in p.move(to:CGPoint(x:30,y:232));p.addLine(to:CGPoint(x:30,y:82));p.addQuadCurve(to:CGPoint(x:w/2,y:15),control:CGPoint(x:50,y:30));p.addQuadCurve(to:CGPoint(x:w-30,y:82),control:CGPoint(x:w-50,y:30));p.addLine(to:CGPoint(x:w-30,y:232));p.closeSubpath() }.fill(theme.background.opacity(0.5))
                // Keep the arch outline open at its foot; its closing edge crossed the balance labels below.
                Path { p in p.move(to:CGPoint(x:30,y:232));p.addLine(to:CGPoint(x:30,y:82));p.addQuadCurve(to:CGPoint(x:w/2,y:15),control:CGPoint(x:50,y:30));p.addQuadCurve(to:CGPoint(x:w-30,y:82),control:CGPoint(x:w-50,y:30));p.addLine(to:CGPoint(x:w-30,y:232)) }.stroke(theme.color("reserveText"),lineWidth:0.7)
                Path { p in p.move(to:center);p.addLine(to:CGPoint(x:w/2,y:222));p.move(to:left);p.addLine(to:right) }.stroke(theme.ink,style: .init(lineWidth:3,lineCap:.round))
                Path { p in p.move(to:CGPoint(x:w/2-27,y:220));p.addLine(to:CGPoint(x:w/2+27,y:220));p.addLine(to:CGPoint(x:w/2+39,y:234));p.addLine(to:CGPoint(x:w/2-39,y:234));p.closeSubpath() }.fill(theme.color("reserveText"))
                pan(left, coin: false); pan(right, coin: true)
                Image(systemName:"seal.fill").font(.system(size:20)).foregroundStyle(theme.color("reserveText")).position(x:center.x,y:center.y-20)
                Circle().fill(theme.color("reserve")).overlay { Circle().stroke(theme.ink,lineWidth:1) }.frame(width:14,height:14).position(center)
            }.animation(reduceMotion ? nil : .easeInOut(duration:0.5),value:entered).animation(reduceMotion ? nil : .easeInOut(duration:0.35),value:tilt)
        }.environment(\.layoutDirection, .leftToRight)
    }
    private func pan(_ point: CGPoint, coin: Bool) -> some View {
        ZStack {
            Path { p in p.move(to:point);p.addLine(to:CGPoint(x:point.x-39,y:point.y+69));p.move(to:point);p.addLine(to:CGPoint(x:point.x+39,y:point.y+69)) }.stroke(theme.secondaryInk,lineWidth:0.7)
            if coin {
                ForEach(0..<3,id:\.self) { column in
                    ForEach(0..<(column == 0 ? 5 : 4),id:\.self) { row in
                        Ellipse().fill(theme.color("reserve")).overlay { Ellipse().stroke(theme.color("reserveText"),lineWidth:0.7) }.frame(width:22,height:6).position(x:point.x+Double(column-1)*21,y:point.y+65-Double(row)*6)
                    }
                }
            } else {
                Path { p in p.move(to:CGPoint(x:point.x-24,y:point.y+68));p.addLine(to:CGPoint(x:point.x+24,y:point.y+68));p.addLine(to:CGPoint(x:point.x+18,y:point.y+54));p.addLine(to:CGPoint(x:point.x-17,y:point.y+54));p.closeSubpath() }.fill(theme.color("reserve")).overlay { Path { p in p.move(to:CGPoint(x:point.x-24,y:point.y+68));p.addLine(to:CGPoint(x:point.x-17,y:point.y+54));p.addLine(to:CGPoint(x:point.x+18,y:point.y+54));p.addLine(to:CGPoint(x:point.x+24,y:point.y+68)) }.stroke(theme.color("reserveText"),lineWidth:0.7) }
            }
            Path { p in p.move(to:CGPoint(x:point.x-41,y:point.y+69));p.addQuadCurve(to:CGPoint(x:point.x+41,y:point.y+69),control:CGPoint(x:point.x,y:point.y+90));p.closeSubpath() }.fill(theme.ink)
        }
    }
}

/// OR-27 (owner, 27 Oct 2026): the owner switches between three ways of writing money figures in the room's settings.
enum MoneyFigureStyle: String { case heritage, modern, classic
    @MainActor init(_ app: AppSession) { self = Self(rawValue: app.string("mal.figureStyle")) ?? .heritage }
    var font: String { switch self { case .heritage: "thmanyahserifdisplay-Black"; case .modern: "thmanyahsans-Medium"; case .classic: "Amiri-Regular" } }
}

/// One isolated number run: riyals large, halalas smaller after «٫». Heritage groups with a narrow space instead of
/// the comma-like «٬» the display serif draws; modern keeps «٬» small in gold; classic keeps the calligraphic marks.
struct MoneyFigure: View {
    let value: String
    let style: MoneyFigureStyle
    var size: CGFloat = 48
    @Environment(\.roomTheme) private var theme
    var body: some View {
        let parts = value.split(separator: "٫", maxSplits: 1).map(String.init)
        let whole = parts.first ?? value
        let fraction = parts.count > 1 && parts[1].contains(where: { ($0.wholeNumberValue ?? 0) > 0 }) ? parts[1] : nil
        let font = Font.custom(style.font, size: size, relativeTo: .largeTitle)
        var text = Text(verbatim: ""), run = ""
        func flush() { guard !run.isEmpty else { return }; text = Text("\(text)\(Text(verbatim: run).font(font))"); run = "" }
        for c in whole {
            guard c == "٬" || c == "," else { run.append(c); continue }
            switch style {
            // U+202F is a common separator, so the two digit groups stay one right-to-left-safe number.
            case .heritage: run.append("\u{202F}")
            case .modern: flush(); text = Text("\(text)\(Text(verbatim: "٬").font(.custom(style.font, size: size * 0.6, relativeTo: .largeTitle)).foregroundStyle(theme.color("reserveText")))")
            case .classic: run.append(c)
            }
        }
        flush()
        if let fraction {
            // The display faces draw «٫» like a low comma; Amiri's decimal mark reads as a decimal point.
            let ink = style == .classic ? theme.secondaryInk : theme.color("reserveText"), small = size * 0.52
            text = Text("\(text)\(Text(verbatim: "٫").font(.custom("Amiri-Regular", size: small, relativeTo: .title2)).foregroundStyle(ink))\(Text(verbatim: fraction).font(.custom(style.font, size: small, relativeTo: .title2)).foregroundStyle(ink))")
        }
        return text.monospacedDigit().lineLimit(1).minimumScaleFactor(0.6).accessibilityLabel(value)
    }
}

enum MoneyHawlStyle: String { case crescents, orbit, calendar
    @MainActor init(_ app: AppSession) { self = Self(rawValue: app.string("mal.hawlStyle")) ?? .crescents }
}

/// OR-27: the hawl drawn three ways. Crescents are real crescents (a disc minus an offset disc), not symbol glyphs.
struct MoneyHawlArt: View {
    let style: MoneyHawlStyle
    let fraction: Double
    /// Hijri month (1...12) the hawl starts in, for the calendar style.
    let startMonth: Int
    var centre: AnyView? = nil
    @Environment(\.roomTheme) private var theme
    static let months = ["محرم", "صفر", "ربيع الأول", "ربيع الآخر", "جمادى الأولى", "جمادى الآخرة", "رجب", "شعبان", "رمضان", "شوال", "ذو القعدة", "ذو الحجة"]
    private var current: Int { min(11, max(0, Int(fraction * 12))) }
    var body: some View {
        switch style {
        case .crescents: crescents
        case .orbit: orbit
        case .calendar: calendar
        }
    }
    private static func crescent(_ c: CGPoint, _ r: CGFloat) -> Path {
        Path(ellipseIn: CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r))
            .subtracting(Path(ellipseIn: CGRect(x: c.x - r * 0.45, y: c.y - r * 1.12, width: 2 * r, height: 2 * r)))
    }
    private var crescents: some View {
        VStack(spacing: 2) {
            Canvas { context, size in
                let gold = theme.color("reserve"), goldText = theme.color("reserveText")
                func point(_ t: Double) -> CGPoint { .init(x: size.width - 18 - t * (size.width - 36), y: size.height - 14 - (size.height - 34) * 4 * t * (1 - t)) }
                var arc = Path(); arc.move(to: point(0)); for i in 1...48 { arc.addLine(to: point(Double(i) / 48)) }
                context.stroke(arc, with: .color(goldText.opacity(0.35)), style: .init(lineWidth: 1, dash: [2, 4]))
                for m in 0..<12 {
                    let c = point(Double(m) / 11), here = m == current, r: CGFloat = here ? 11 : 7.5
                    if here { context.fill(Path(ellipseIn: CGRect(x: c.x - 22, y: c.y - 22, width: 44, height: 44)), with: .color(gold.opacity(0.22))) }
                    let shape = Self.crescent(c, r)
                    if m <= current { context.fill(shape, with: .color(here ? gold : goldText)) } else { context.stroke(shape, with: .color(goldText.opacity(0.6)), lineWidth: 1) }
                }
            }.frame(height: 88)
            HStack { Text("بدأ الحول"); Spacer(); Text("يحول") }.font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.secondaryInk).padding(.horizontal, 6)
        }
    }
    private var orbit: some View {
        ZStack {
            Canvas { context, size in
                let gold = theme.color("reserve"), r = min(size.width, size.height) / 2 - 16, o = CGPoint(x: size.width / 2, y: size.height / 2)
                // Starts at the top and runs counter-clockwise, the reading direction of the room.
                func point(_ t: Double) -> CGPoint { let a = -Double.pi / 2 - t * 2 * .pi; return .init(x: o.x + r * cos(a), y: o.y + r * sin(a)) }
                context.stroke(Path(ellipseIn: CGRect(x: o.x - r, y: o.y - r, width: 2 * r, height: 2 * r)), with: .color(theme.line), lineWidth: 5)
                var done = Path(); done.move(to: point(0)); for i in 1...96 where Double(i) / 96 <= fraction { done.addLine(to: point(Double(i) / 96)) }; done.addLine(to: point(fraction))
                context.stroke(done, with: .color(gold), style: .init(lineWidth: 5, lineCap: .round))
                for m in 0..<12 { let c = point(Double(m) / 12); context.fill(Path(ellipseIn: CGRect(x: c.x - 3, y: c.y - 3, width: 6, height: 6)), with: .color(Double(m) / 12 <= fraction ? gold : theme.line)) }
                let m = point(fraction)
                context.fill(Path(ellipseIn: CGRect(x: m.x - 20, y: m.y - 20, width: 40, height: 40)), with: .color(gold.opacity(0.25)))
                context.fill(Path(ellipseIn: CGRect(x: m.x - 12, y: m.y - 12, width: 24, height: 24)), with: .color(theme.ink))
                context.fill(Self.crescent(m, 10), with: .color(theme.color("glass")))
            }
            centre
        }.frame(height: 230)
    }
    private var calendar: some View {
        LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: 4), spacing: 6) {
            ForEach(0..<12, id: \.self) { i in
                let name = Self.months[(startMonth - 1 + i) % 12], here = i == current, past = i < current
                VStack(spacing: 3) {
                    Canvas { context, size in
                        let shape = Self.crescent(CGPoint(x: size.width / 2, y: size.height / 2), 6.5)
                        if past || here { context.fill(shape, with: .color(theme.color("reserve"))) } else { context.stroke(shape, with: .color(theme.color("reserveText")), lineWidth: 1) }
                    }.frame(width: 18, height: 16)
                    Text(name).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).lineLimit(1).minimumScaleFactor(0.8)
                }
                .frame(maxWidth: .infinity, minHeight: 50)
                .foregroundStyle(here ? theme.background : theme.ink)
                .background(here ? theme.ink : past ? theme.color("reserve").opacity(0.16) : .clear, in: .rect(cornerRadius: 10))
                .overlay { RoundedRectangle(cornerRadius: 10).stroke(here ? theme.ink : theme.line) }
            }
        }
    }
}
