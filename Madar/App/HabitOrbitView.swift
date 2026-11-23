import SwiftUI
import MadarCore
import MadarCommands
import MadarDesign

/// The canvas «Habits» orbit (owner order, 17 Nov 2026): four rings (today, week, month, year) with every habit as a bead on its own
/// ring, the chosen habit enlarged and named, the rest dimmed, a moving dot for «الآن» on each ring and the day's count in the middle.
/// Progress runs against the clock as Arabic reads. From AX1 the drawing gives way to one line per ring.
struct HabitOrbitView:View {
    let readings:[HabitReading]; let digits:MadarNumberFormatter; let theme:RoomTheme
    let nowPositions:[HabitFrequency:Double]
    var selected:UUID? = nil
    let select:(HabitReading)->Void
    /// What the centre says: «٣ من ٦» and its caption, or the chosen habit's own state.
    var centre:(title:String,caption:String) = ("","")
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let frequencies:[HabitFrequency] = [.daily,.weekly,.monthly,.yearly]
    private static let radii:[Double] = [78,112,144,162]
    private static let single:[Double] = [0.5,0.28,0.72,0.4]
    private func beadColour(_ row:HabitReading)->Color { habitRoomColour(row.source,dark:theme.dark) }
    private func share(_ f:HabitFrequency)->(met:Int,due:Int) {
        let due=readings.filter{$0.summary.current?.rule.band == f && !$0.paused && ($0.summary.current?.target ?? 0)>0}
        return (due.filter{$0.summary.current?.met == true}.count,due.count)
    }
    private func title(_ f:HabitFrequency)->String { f == .daily ? "اليوم" : f == .weekly ? "الأسبوع" : f == .monthly ? "الشهر" : "السنة" }
    private func label(_ f:HabitFrequency)->String { let s=share(f); return title(f)+(s.due == 0 ? "" : " "+digits.percent(Int((Double(s.met)*100/Double(s.due)).rounded()))) }
    var body:some View {
        VStack(spacing:14) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment:.leading,spacing:6) { ForEach(frequencies,id:\.self) { f in Text(label(f)).font(HabitType.caption()) } }.frame(maxWidth:.infinity,alignment:.leading).padding(.horizontal,16)
            } else {
                GeometryReader { g in
                    let size=min(g.size.width,358.0), k=size/358.0, c=size/2
                    ZStack {
                        ForEach(Array(frequencies.enumerated()),id:\.element) { index,f in
                            let r=Self.radii[index]*k, s=share(f), fraction=s.due == 0 ? 0 : Double(s.met)/Double(s.due)
                            Circle().stroke(theme.accentFill.opacity(0.22),lineWidth:1.5).frame(width:r*2,height:r*2).position(x:c,y:c)
                            Circle().trim(from:0,to:fraction).stroke(theme.accentFill,style:.init(lineWidth:4,lineCap:.round)).rotationEffect(.degrees(-90)).scaleEffect(x:-1)
                                .frame(width:r*2,height:r*2).position(x:c,y:c).opacity(selected == nil ? 0.85 : 0.3)
                            Text(label(f)).font(HabitType.fine()).foregroundStyle(theme.ink.opacity(0.72)).padding(.horizontal,6).background(Rectangle().fill(theme.background).overlay(theme.accentFill.opacity(0.07)))
                                .position(x:c,y:c-r).accessibilityIdentifier("habit-orbit-progress-"+f.rawValue).accessibilityLabel(title(f)+(s.due == 0 ? "، لا أهداف في هذه الفترة" : " "+digits.percent(Int((fraction*100).rounded()))))
                            if let phase=nowPositions[f] {
                                let a=phase*2*Double.pi
                                Circle().fill(theme.ink).frame(width:7,height:7).position(x:c-r*sin(a),y:c-r*cos(a)).accessibilityHidden(true)
                            }
                        }
                        ForEach(Array(frequencies.enumerated()),id:\.element) { index,f in
                            let rows=readings.filter{$0.summary.current?.rule.band == f}
                            ForEach(Array(rows.enumerated()),id:\.element.id) { offset,row in
                                let on=row.id == selected, r=Self.radii[index]*k
                                // One bead sits where the canvas puts it; several spread over the ring and keep clear of the label at the top.
                                let fraction=rows.count == 1 ? Self.single[index] : 0.08+0.84*(Double(offset)+0.5)/Double(rows.count)
                                let a=fraction*2*Double.pi
                                let x=c-r*sin(a), y=c-r*cos(a)
                                Button { select(row) } label: {
                                    HabitBead(state:HabitBead.State(row),colour:beadColour(row),theme:theme).frame(width:on ? 26 : 18,height:on ? 26 : 18)
                                        .shadow(color:on ? theme.accentFill.opacity(0.55) : .clear,radius:on ? 9 : 0)
                                        .frame(width:44,height:44).contentShape(.circle)
                                }.buttonStyle(.madarPlain).opacity(selected == nil || on ? 1 : 0.32)
                                .accessibilityLabel(row.name+"، "+row.statusTitle(digits)).accessibilityAddTraits(on ? .isSelected : []).accessibilityIdentifier("habit-orbit-"+row.id.uuidString)
                                .position(x:x,y:y)
                                if on {
                                    Text(row.name).font(HabitType.fine()).foregroundStyle(theme.surface).padding(.horizontal,8).padding(.vertical,2).background(theme.accent,in:.rect(cornerRadius:10))
                                        .position(x:min(max(x,40),size-40),y:y+26).allowsHitTesting(false)
                                }
                            }
                        }
                        VStack(spacing:2) {
                            Text(centre.title).font(HabitType.cardTitle()).lineLimit(1).minimumScaleFactor(0.6)
                                .contentTransition(.numericText()).animation(reduceMotion ? nil : .snappy, value: centre.title)
                            Text(centre.caption).font(HabitType.fine()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.center).lineLimit(2).minimumScaleFactor(0.8)
                        }.padding(8).frame(width:100*k,height:100*k).background(theme.surface,in:.circle).position(x:c,y:c)
                    }.frame(width:size,height:size).frame(maxWidth:.infinity)
                }.aspectRatio(1,contentMode:.fit).frame(maxWidth:358).environment(\.layoutDirection,.leftToRight)
            }
            HStack(spacing:14) {
                legend("تمّت",.done); legend("فاتتك مرة",.atRisk); legend("تنتظر",.waiting)
                HStack(spacing:5) { Circle().fill(theme.ink).frame(width:7,height:7); Text("الآن").font(HabitType.fine()) }
            }.foregroundStyle(theme.ink.opacity(0.72)).padding(.horizontal,12)
        }
        .padding(.vertical,16).frame(maxWidth:.infinity)
        .background(theme.accentFill.opacity(0.07),in:.rect(cornerRadius:28)).overlay{RoundedRectangle(cornerRadius:28).stroke(theme.accentFill.opacity(0.24))}
    }
    private func legend(_ title:String,_ state:HabitBead.State)->some View {
        HStack(spacing:5) { HabitBead(state:state,colour:theme.accent,theme:theme).frame(width:10,height:10); Text(title).font(HabitType.fine()) }
    }
}

/// DA-05: W2's beads drawn, not icons: filled when done, half when a period was missed, hollow while waiting,
/// dashed when frozen; «أقلّ القليل» fills softly.
struct HabitBead:View {
    enum State:Hashable { case done, minimum, waiting, atRisk, paused
        init(_ row:HabitReading) { self = row.paused ? .paused : row.summary.current?.outcome == .minimum ? .minimum : row.summary.current?.met == true ? .done : row.summary.atRisk ? .atRisk : .waiting }
        var title:String { switch self { case .done: "تمّت"; case .minimum: "أقلّ القليل"; case .waiting: "تنتظر"; case .atRisk: "فاتتك"; case .paused: "مجمّدة" } }
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
