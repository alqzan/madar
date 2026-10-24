import SwiftUI
import MadarDesign

struct QuranStrengthView:View {
    let service:AppQuranService
    let close:()->Void
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var type
    @State private var board:QuranUIStrengthBoard?
    @State private var selected:Int?
    @State private var recovery=false
    @State private var days=7
    @State private var details=false
    @State private var review=false
    @State private var busy=false
    @State private var error:String?
    private var app:AppSession {service.app}
    private var part:QuranUIStrengthPart? {board?.parts.first {$0.id == selected}}
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:18) {
                QuranScreenHeader(title:"منسوب الحفظ",close:close)
                Text("كل أنبوب جزء، المسه لتراه").font(quranFont(13)).foregroundStyle(theme.secondaryInk)
                if let board {
                    HStack {
                        VStack(alignment:.leading,spacing:5) {Text("منسوب صدرك").font(quranFont(12));Text(board.mean.map {service.numerals.percent($0)} ?? "—").font(quranSerif(43)).foregroundStyle(theme.color("hifzText")).accessibilityIdentifier("quran-strength-mean")}
                        Spacer()
                        if board.far > 0 || board.active != nil {Button {recovery=true} label: {VStack(spacing:4) {Text(service.faceCount(board.far)+" بعيدة");Text(board.active == nil ? "خطة استرداد" : "خطّتك")}.font(quranFont(12,bold:true)).padding(12).background(theme.color("dueTint"),in:.rect(cornerRadius:16))}.buttonStyle(.plain).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("quran-strength-recovery")}
                    }
                    Text("مؤشر وصفي من تقييمك ومواعيد المراجعة؛ ليس احتمالًا للحفظ. البعيد: متأخر مدة كاملة أو متانته تحت خمسين.").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                    if board.parts.isEmpty {QuranPaperCard {Text("يظهر المنسوب بعد إكمال حفظ وجه؛ الأوجه الجزئية تُراجع ضمن القريب.").font(quranFont(16))}}
                    else if type.isAccessibilitySize {
                        ForEach(board.parts) {p in Button {selected=p.id} label: {Text(p.title+"، "+service.numerals.percent(p.strength)).font(quranFont(16)).frame(minHeight:44)} }
                    } else {tubes(board.parts)}
                    if let part {partCard(part)}
                }
                if let error {Text(error).font(quranFont(13)).foregroundStyle(theme.color("dueText"))}
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review")).disabled(busy)
            .safeAreaInset(edge:.bottom) {if app.undoToken != nil {UndoToast(message:app.undoMessage,undo:app.undo).accessibilityIdentifier("quran-strength-undo")}}
            .task {load()}.onChange(of:app.undoToken?.id) {load()}
            .sheet(isPresented:$recovery) {recoverySheet}
            .sheet(isPresented:$details) {faceDetails}
            .fullScreenCover(isPresented:$review) {QuranFreeView(service:service,close:{review=false},initialRange:part.flatMap {p in guard let first=p.faces.first?.id,let last=p.faces.last?.id else {return nil};return QuranUIRange(fromPage:first,toPage:last)})}
            .alert("لم تكتمل العملية",isPresented:Binding(get:{app.errorMessage != nil},set:{if !$0 {app.errorMessage=nil}})) {Button("تمّ") {app.errorMessage=nil}} message: {Text(app.errorMessage ?? "")}
    }
    private func tubes(_ parts:[QuranUIStrengthPart])->some View {
        GeometryReader {proxy in
            // A tube keeps tube proportions with few parts memorised (owner trial: one juz drew a full-width blob).
            let gap:CGFloat=5,w=min(56,(proxy.size.width-CGFloat(parts.count-1)*gap)/CGFloat(parts.count))
            let inset=(proxy.size.width-CGFloat(parts.count)*w-CGFloat(parts.count-1)*gap)/2
            Canvas {context,size in
                for (i,p) in parts.enumerated() {
                    let r=CGRect(x:size.width-inset-CGFloat(i+1)*w-CGFloat(i)*gap,y:0,width:w,height:size.height-24),path=Path(roundedRect:r,cornerRadius:w/2)
                    context.fill(path,with:.color(theme.color("track")))
                    var water=context;water.clip(to:path);water.fill(Path(CGRect(x:r.minX,y:r.maxY-r.height*CGFloat(p.strength)/100,width:w,height:r.height*CGFloat(p.strength)/100)),with:.color(waterColor(p.strength)))
                    var threshold=Path();threshold.move(to:CGPoint(x:r.minX,y:r.maxY-r.height*0.7));threshold.addLine(to:CGPoint(x:r.maxX,y:r.maxY-r.height*0.7));context.stroke(threshold,with:.color(theme.secondaryInk),style:StrokeStyle(lineWidth:0.8,dash:[2,2]))
                    if p.id == selected {context.stroke(path,with:.color(theme.ink),lineWidth:1.5)}
                    if p.scheduled,let projected=p.projected {var level=Path();level.move(to:CGPoint(x:r.minX,y:r.maxY-r.height*CGFloat(projected)/100));level.addLine(to:CGPoint(x:r.maxX,y:r.maxY-r.height*CGFloat(projected)/100));context.stroke(level,with:.color(theme.ink),style:StrokeStyle(lineWidth:1.5,dash:[2,2]))}
                    context.draw(Text(service.numerals.string(p.id)).font(quranFont(11)).foregroundStyle(theme.secondaryInk),at:CGPoint(x:r.midX,y:r.maxY+14))
                }
            }.onTapGesture {point in let offset=proxy.size.width-inset-point.x,index=Int(offset/(w+gap));if offset>=0,parts.indices.contains(index) {selected=parts[index].id}}
                .accessibilityLabel("أنابيب الأجزاء، الحد المرجعي سبعون بالمئة")
        }.frame(height:280)
    }
    private func partCard(_ p:QuranUIStrengthPart)->some View {
        QuranPaperCard {
            VStack(alignment:.leading,spacing:16) {
                HStack {Text(p.title).font(quranFont(17,bold:true));Spacer();Text(service.numerals.percent(p.strength)).font(quranSerif(30)).foregroundStyle(waterText(p.strength))}
                Canvas {context,size in
                    let w=size.width/CGFloat(max(1,p.faces.count))
                    for (i,face) in p.faces.enumerated() {context.fill(Path(roundedRect:CGRect(x:size.width-CGFloat(i+1)*w+1,y:0,width:max(1,w-2),height:24),cornerRadius:3),with:.color(waterColor(face.strength)))}
                }.frame(height:24).accessibilityHidden(true)
                Button("تفاصيل الأوجه") {details=true}.font(quranFont(13)).frame(minHeight:44).accessibilityIdentifier("quran-strength-details")
                Text("في هذا الجزء: "+service.faceCount(p.faces.filter(\.far).count)+" بعيدة وفق تعريف المنسوب").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                if p.scheduled {Text("أُضيفت إلى الغد").font(quranFont(14,bold:true)).accessibilityIdentifier("quran-strength-raised")}
                if let projected=p.projected {Text("لو راجعت الأوجه المختارة غدًا بتقييم جيد: "+service.numerals.percent(projected)).font(quranFont(12)).foregroundStyle(theme.secondaryInk)}
                HStack(spacing:8) {
                    if !p.raised.isEmpty && !p.scheduled {Button {run {try await service.perform(.raisePages(juz:p.id));load()}} label: {Text("ارفعه، "+service.faceCount(p.raised.count)+" للغد").font(quranFont(13,bold:true)).frame(maxWidth:.infinity,minHeight:48).foregroundStyle(theme.onAccent).background(theme.accent,in:Capsule())}.accessibilityIdentifier("quran-strength-raise")}
                    Button("راجعه الآن") {review=true}.font(quranFont(13,bold:true)).frame(minHeight:48).accessibilityIdentifier("quran-strength-review")
                }
            }
        }
    }
    private var recoverySheet:some View {
        ScrollView {VStack(alignment:.leading,spacing:16) {
            Text("استرداد البعيد").font(quranSerif(29))
            if let board {
                Text(service.faceCount(board.far)+" بعيدة").font(quranFont(17,bold:true))
                if let active=board.active {Text(active).font(quranFont(15,bold:true));Text("المتبقي: "+service.faceCount(board.remaining)+"، حصة اليوم: "+service.faceCount(board.activeShare)).font(quranFont(13));Button("ألغِ خطة الاسترداد") {run {try await service.perform(.cancelRecovery);load();recovery=false}}.frame(minHeight:44).accessibilityIdentifier("quran-recovery-cancel")}
                ForEach(board.options) {option in Button {days=option.id} label: {HStack {Image(systemName:days == option.id ? "largecircle.fill.circle":"circle");VStack(alignment:.leading,spacing:5) {Text(option.title).font(quranFont(16,bold:true));Text("زيادة اليوم: "+service.faceCount(option.daily)+"، الإتمام "+option.end).font(quranFont(12))};Spacer()}.padding(12).background(theme.color("reviewTint"),in:.rect(cornerRadius:16)).contentShape(Rectangle())}.buttonStyle(.plain).accessibilityIdentifier("quran-recovery-days-"+String(option.id))}
                if board.far > 0 {Button(board.active == nil ? "ابدأ الاسترداد":"ابدأ خطة جديدة") {run {try await service.perform(.createRecovery(days:days));load();recovery=false}}.font(quranFont(16,bold:true)).foregroundStyle(theme.onAccent).frame(maxWidth:.infinity,minHeight:50).background(theme.accent,in:Capsule()).accessibilityIdentifier("quran-recovery-create")}
            }
            Button("تمّ") {recovery=false}.frame(minHeight:44)
        }.padding(24)}.foregroundStyle(theme.ink).background(theme.surface).presentationDetents([.height(590),.large]).environment(\.layoutDirection,.rightToLeft)
    }
    private var faceDetails:some View {ScrollView {VStack(alignment:.leading,spacing:16) {Text(part?.title ?? "").font(quranSerif(27));ForEach(part?.faces ?? []) {face in VStack(alignment:.leading,spacing:6) {Text("الوجه "+service.numerals.string(face.id)+"، "+service.numerals.percent(face.strength)).font(quranFont(16,bold:true));Text("آخر تسميع: "+face.reviewed+"\nالموعد: "+face.due).font(quranFont(13));if face.far {Text("بعيد").font(quranFont(12)).foregroundStyle(theme.color("dueText"))}};Divider()};Button("تمّ") {details=false}.frame(minHeight:44)}.padding(24)}.foregroundStyle(theme.ink).background(theme.surface).presentationDetents([.medium,.large]).environment(\.layoutDirection,.rightToLeft)}
    private func waterColor(_ n:Int)->Color {theme.color(n > 70 ? "review":n >= 50 ? "hifz":"due")}
    private func waterText(_ n:Int)->Color {theme.color(n > 70 ? "reviewText":n >= 50 ? "hifzText":"dueText")}
    private func load() {do {let value=try service.strengthBoard();board=value;if selected == nil {selected=value.parts.min {$0.strength < $1.strength}?.id}} catch {self.error=quranUserMessage(error)}}
    private func run(_ work:@escaping @MainActor () async throws ->Void) {guard !busy else {return};busy=true;Task {defer {busy=false};do {try await work()} catch {self.error=quranUserMessage(error)}}}
}
