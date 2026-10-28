import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

/// RL1: each visible bead has a visible name and a 44 pt target. Extra habits stay in the labelled list.
struct HabitOrbitView:View {
    let readings:[HabitReading]; let digits:MadarNumberFormatter; let theme:RoomTheme
    let nowPositions:[HabitFrequency:Double]
    let select:(HabitReading)->Void
    private let frequencies:[HabitFrequency] = [.daily,.weekly,.monthly,.yearly]
    /// A linked habit's bead takes its room's colour (prayer, Quran, diary, Mihbara), as W2 draws them.
    private func beadColour(_ row:HabitReading)->Color {
        let room:String? = switch row.source { case "jamaah": "salah"; case "review": "quran"; case "diaryLine": "notes"; case "reading","hadith": "mihbara"; default: nil }
        return room.map { RoomTheme(room:$0,dark:theme.dark).accentFill } ?? theme.accentFill
    }
    private var centreCount:String {
        let daily=readings.filter{$0.summary.current?.rule.frequency == .daily && ($0.summary.current?.target ?? 0)>0 && !$0.paused}
        return daily.isEmpty ? "اليوم راحة" : digits.string(daily.filter{$0.summary.current?.met == true}.count)+" من "+digits.string(daily.count)
    }
    var body:some View {
        GeometryReader { g in
            let centre = CGPoint(x:g.size.width/2,y:175), base = min(g.size.width/2-14,164.0)
            ZStack {
                ForEach(Array(frequencies.enumerated()),id:\.element) { index,f in
                    let radius=base-Double(3-index)*28, rows=readings.filter{$0.summary.current?.rule.frequency == f}, due=rows.filter{!$0.paused && ($0.summary.current?.target ?? 0)>0}, met=due.filter{$0.summary.current?.met == true}.count
                    Circle().stroke(theme.line,lineWidth:1).frame(width:radius*2,height:radius*2).position(centre)
                    Circle().trim(from:0,to:due.isEmpty ? 0 : Double(met)/Double(due.count)).stroke(theme.accentFill.opacity(0.6),style:.init(lineWidth:3.5,lineCap:.round)).rotationEffect(.degrees(-90)).frame(width:radius*2,height:radius*2).position(centre)
                    let period = f == .daily ? "اليوم" : f == .weekly ? "الأسبوع" : f == .monthly ? "الشهر" : "السنة"
                    let progress = due.isEmpty ? "" : " " + digits.percent(Int((Double(met) * 100 / Double(due.count)).rounded()))
                    Text(period + progress).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                        .padding(.horizontal,5).background(theme.surface).position(x:centre.x,y:centre.y-radius)
                        .accessibilityIdentifier("habit-orbit-progress-" + f.rawValue)
                        .accessibilityLabel(period + (due.isEmpty ? "، لا أهداف في هذه الفترة" : progress))
                    ForEach(Array(rows.prefix(3).enumerated()),id:\.element.id) { offset,row in
                        let angle=(Double(offset)*100+30+Double(index)*35)*Double.pi/180
                        Button { select(row) } label: {
                            VStack(spacing:2) {
                                HabitBead(state:HabitBead.State(row),colour:beadColour(row),theme:theme).frame(width:17,height:17)
                                Text(row.name).font(.custom("thmanyahsans-Regular",size:11,relativeTo:.caption2)).lineLimit(1).padding(.horizontal,3).background(theme.background.opacity(0.92),in:.capsule)
                            }.frame(width:86,height:44)
                        }.buttonStyle(.plain).accessibilityLabel(row.name+"، "+row.statusTitle).accessibilityIdentifier("habit-orbit-"+row.id.uuidString).position(x:centre.x+cos(angle)*radius,y:centre.y+sin(angle)*radius)
                    }
                    if let phase = nowPositions[f] {
                        let angle = (phase * 360 - 90) * Double.pi / 180
                        Circle().fill(theme.ink).frame(width: 6, height: 6)
                            .overlay { Circle().stroke(theme.surface, lineWidth: 1) }
                            .position(x: centre.x + cos(angle) * radius, y: centre.y + sin(angle) * radius)
                            .accessibilityHidden(true)
                    }
                }
                VStack(spacing:4) { Text(centreCount).font(MadarTypography.cardTitle()); Text("عادات اليوم").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }.frame(width:88,height:88).background(theme.surface,in:.circle).overlay{Circle().stroke(theme.line)}.position(centre)
            }.environment(\.layoutDirection,.leftToRight)
        }.frame(height:380)
        .overlay(alignment:.bottom) { HStack(spacing:10) { ForEach([HabitBead.State.done,.waiting,.atRisk,.paused],id:\.self) { st in Label { Text(st.title) } icon: { HabitBead(state:st,colour:theme.accentFill,theme:theme).frame(width:11,height:11) } }; Label { Text("الآن") } icon: { Circle().fill(theme.ink).frame(width:6,height:6) } }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).padding(.bottom,8) }
        .background(theme.surface.opacity(0.35),in:.rect(cornerRadius:26)).overlay{RoundedRectangle(cornerRadius:26).stroke(theme.line)}
    }
}

/// DA-05: W2's beads drawn, not icons: filled when done, half when a period was missed, hollow while waiting,
/// dashed when frozen; «أقلّ القليل» fills softly.
struct HabitBead:View {
    enum State:Hashable { case done, minimum, waiting, atRisk, paused
        init(_ row:HabitReading) { self = row.paused ? .paused : row.summary.current?.outcome == .minimum ? .minimum : row.summary.current?.met == true ? .done : row.summary.atRisk ? .atRisk : .waiting }
        var title:String { switch self { case .done: "تمّت"; case .minimum: "أقلّ القليل"; case .waiting: "تنتظر"; case .atRisk: "فاتتك مرة"; case .paused: "مجمّدة" } }
    }
    let state:State; let colour:Color; let theme:RoomTheme
    var body:some View {
        GeometryReader { g in
            let w=g.size.width
            ZStack {
                switch state {
                case .done: Circle().fill(colour)
                case .minimum: Circle().fill(colour.opacity(0.45)); Circle().stroke(colour,lineWidth:max(1.5,w*0.12))
                case .waiting: Circle().fill(theme.surface); Circle().stroke(colour,lineWidth:max(1.5,w*0.13))
                case .atRisk: Circle().fill(theme.surface); Rectangle().fill(colour).frame(width:w/2).frame(maxWidth:.infinity,alignment:.leading).clipShape(Circle()); Circle().stroke(colour,lineWidth:max(1.5,w*0.12))
                case .paused: Circle().fill(theme.surface); Circle().stroke(theme.secondaryInk,style:.init(lineWidth:max(1.2,w*0.1),dash:[2,2]))
                }
            }
        }.aspectRatio(1,contentMode:.fit).accessibilityHidden(true)
    }
}
