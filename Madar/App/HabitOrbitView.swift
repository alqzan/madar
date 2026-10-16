import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

/// RL1: each visible bead has a visible name and a 44 pt target. Extra habits stay in the labelled list.
struct HabitOrbitView:View {
    let readings:[HabitReading]; let digits:MadarNumberFormatter; let theme:RoomTheme; let select:(HabitReading)->Void
    private let frequencies:[HabitFrequency] = [.daily,.weekly,.monthly,.yearly]
    private var centreCount:String {
        let daily=readings.filter{$0.summary.current?.rule.frequency == .daily && ($0.summary.current?.target ?? 0)>0 && !$0.paused}
        return daily.isEmpty ? "اليوم راحة" : digits.string(daily.filter{$0.summary.current?.met == true}.count)+" من "+digits.string(daily.count)
    }
    var body:some View {
        GeometryReader { g in
            let centre = CGPoint(x:g.size.width/2,y:175), base = min(g.size.width/2-14,164.0)
            ZStack {
                ForEach(Array(frequencies.enumerated()),id:\.offset) { index,f in
                    let radius=base-Double(3-index)*28, rows=readings.filter{$0.summary.current?.rule.frequency == f}, met=rows.filter{$0.summary.current?.met == true}.count
                    Circle().stroke(theme.line,lineWidth:1).frame(width:radius*2,height:radius*2).position(centre)
                    Circle().trim(from:0,to:rows.isEmpty ? 0 : Double(met)/Double(rows.count)).stroke(theme.accentFill.opacity(0.65),lineWidth:3).rotationEffect(.degrees(-90)).frame(width:radius*2,height:radius*2).position(centre)
                    Text(f == .daily ? "اليوم" : f == .weekly ? "الأسبوع" : f == .monthly ? "الشهر" : "السنة").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.horizontal,5).background(theme.background).position(x:centre.x,y:centre.y-radius)
                    ForEach(Array(rows.prefix(3).enumerated()),id:\.element.id) { offset,row in
                        let angle=(Double(offset)*100+30+Double(index)*35)*Double.pi/180
                        Button { select(row) } label: {
                            VStack(spacing:2) {
                                Image(systemName:row.paused ? "pause.circle" : row.summary.current?.outcome == .minimum ? "checkmark.circle" : row.summary.current?.met == true ? "checkmark.circle.fill" : row.summary.atRisk ? "circle.lefthalf.filled" : "circle").font(.system(size:15)).foregroundStyle(theme.accent)
                                Text(row.name).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1).padding(.horizontal,3).background(theme.background.opacity(0.92),in:.capsule)
                            }.frame(width:86,height:44)
                        }.buttonStyle(.plain).position(x:centre.x+cos(angle)*radius,y:centre.y+sin(angle)*radius)
                    }
                }
                VStack(spacing:4) { Text(centreCount).font(MadarTypography.cardTitle()); Text("عادات اليوم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.frame(width:88,height:88).background(theme.surface,in:.circle).overlay{Circle().stroke(theme.line)}.position(centre)
            }.environment(\.layoutDirection,.leftToRight)
        }.frame(height:380)
        .overlay(alignment:.bottom) { HStack(spacing:12) { Label("تمّت",systemImage:"checkmark.circle.fill"); Label("تنتظر",systemImage:"circle"); Label("مجمّدة",systemImage:"pause.circle") }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.bottom,8) }
        .background(theme.surface.opacity(0.35),in:.rect(cornerRadius:26)).overlay{RoundedRectangle(cornerRadius:26).stroke(theme.line)}
    }
}
