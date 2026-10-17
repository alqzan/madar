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
                Path { p in p.move(to:CGPoint(x:30,y:232));p.addLine(to:CGPoint(x:30,y:82));p.addQuadCurve(to:CGPoint(x:w/2,y:15),control:CGPoint(x:50,y:30));p.addQuadCurve(to:CGPoint(x:w-30,y:82),control:CGPoint(x:w-50,y:30));p.addLine(to:CGPoint(x:w-30,y:232));p.closeSubpath() }.stroke(theme.color("reserveText"),lineWidth:0.7)
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
