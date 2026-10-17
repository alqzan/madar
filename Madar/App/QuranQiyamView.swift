import SwiftUI
import MadarDesign

enum QuranNightColors {
    static let background = MadarToken.colors["rooms.quran.qiyam.bg"] ?? .black
    static let during = MadarToken.colors["rooms.quran.qiyam.duringPrayer"] ?? .black
    static let text = MadarToken.colors["rooms.quran.qiyam.text"] ?? .white
    static let gold = MadarToken.colors["rooms.quran.light.gold"] ?? .primary
    static let ink = MadarToken.colors["widgetIdentity.room.quran.light.ink"] ?? .primary
}
struct QuranQiyamView:View {
    let service:AppQuranService
    let close:()->Void
    @State private var rakaat=2
    @State private var board:QuranUIQiyamBoard?
    @State private var session:QuranUISessionState?
    @State private var busy=false
    @State private var error:String?
    var body:some View {
        ScrollView {
            VStack(alignment:.leading,spacing:12) {
                HStack(spacing:12) {Button(action:close) {Image(systemName:"chevron.backward").frame(width:44,height:44)}.accessibilityLabel("رجوع");VStack(alignment:.leading,spacing:2) {Text("ورد القيام").font(quranSerif(22));Text("من قسم الصلاة، يُحسب في القرآن").font(quranFont(11))};Spacer()}
                Text("اقرأ في صلاتك مما في صدرك").font(quranFont(14))
                Text("ويُحسب لك مراجعة").font(quranSerif(29)).foregroundStyle(QuranNightColors.gold)
                Text("كم ركعة؟").font(quranFont(13))
                HStack(spacing:7) {ForEach([2,4,6,8],id:\.self) {n in Button {rakaat=n} label: {Text(service.numerals.string(n)).font(quranFont(19,bold:true)).frame(maxWidth:.infinity,minHeight:44).foregroundStyle(rakaat == n ? QuranNightColors.ink:QuranNightColors.gold).background(rakaat == n ? QuranNightColors.gold:QuranNightColors.text.opacity(0.08),in:.rect(cornerRadius:17))}.buttonStyle(.plain).accessibilityIdentifier("quran-qiyam-rakaat-"+String(n)).accessibilityAddTraits(rakaat == n ? .isSelected:[])}}
                if let board {
                    VStack(spacing:0) {ForEach(board.assignments) {rakah in HStack {Text(service.numerals.string(rakah.id+1)).font(quranFont(12,bold:true)).frame(width:26,height:26).background(QuranNightColors.text.opacity(0.08),in:Circle());Text(rakah.title).font(quranSerif(18));Spacer();Text(rakah.status).font(quranFont(11))}.padding(.vertical,7);Divider().overlay(QuranNightColors.text.opacity(0.1))}}.padding(12).background(QuranNightColors.text.opacity(0.05),in:.rect(cornerRadius:24))
                    Text("المستحق أولًا، ثم الأقرب موعدًا؛ كل وجه يُسجّل مرة واحدة").font(quranFont(12))
                    Text(board.night).font(quranFont(11))
                    if let unavailable=board.unavailable {Text(unavailable).font(quranFont(15,bold:true)).accessibilityIdentifier("quran-qiyam-unavailable")}
                }
                if let error {Text(error).font(quranFont(14))}
            }.padding(16)
        }.foregroundStyle(QuranNightColors.text).background(QuranNightColors.background.ignoresSafeArea()).preferredColorScheme(.dark)
            .safeAreaInset(edge:.bottom) {if board?.unavailable == nil,board != nil {Button("ابدأ القيام") {busy=true;Task {defer {busy=false};do {session=try await service.start(kind:.qiyam,stepID:nil,range:nil,rakaat:rakaat,spotID:nil)} catch {self.error=quranUserMessage(error)}}}.font(quranFont(16,bold:true)).foregroundStyle(QuranNightColors.ink).frame(maxWidth:.infinity,minHeight:54).background(QuranNightColors.gold,in:Capsule()).padding(16).background(QuranNightColors.background).disabled(busy).accessibilityIdentifier("quran-qiyam-start")}}
            .task(id:rakaat) {load()}
            .fullScreenCover(item:$session,onDismiss:load) {initial in QuranHomeSessionFlow(service:service,state:Binding(get:{session ?? initial},set:{session=$0}),close:{session=nil}).environment(\.roomTheme,RoomTheme(room:"quran",dark:true))}
    }
    private func load() {do {board=try service.qiyamBoard(rakaat:rakaat)} catch {self.error=quranUserMessage(error)}}
}
struct QuranQiyamSessionView:View {
    let state:QuranUISessionState
    let qiyam:QuranUIQiyamSession
    let busy:Bool
    let action:(QuranUISessionAction)->Void
    let close:()->Void
    @State private var exit=false
    var body:some View {
        VStack(spacing:16) {
            HStack {Button {exit=true} label: {Image(systemName:"xmark").frame(width:44,height:44)}.accessibilityLabel("إغلاق الجلسة").accessibilityIdentifier("quran-qiyam-session-close");Spacer();Text("ورد القيام").font(quranFont(15,bold:true))}
            if qiyam.finished || qiyam.pastDay {
                ScrollView {VStack(alignment:.leading,spacing:16) {
                    Text(qiyam.pastDay ? "جلسة من يوم سابق":"تقبّل الله قيامك").font(quranSerif(32)).foregroundStyle(QuranNightColors.gold)
                    Text("الركعات المكتملة: "+number(qiyam.completed)+" / "+number(qiyam.total)).font(quranFont(17,bold:true)).accessibilityIdentifier("quran-qiyam-completed")
                    if !qiyam.pastDay {ForEach(state.grades) {grade in Menu {ForEach(QuranUIGrade.allCases) {value in Button(value.title) {action(.grade(page:grade.page,grade:value))}}} label: {HStack {Text(grade.title);Spacer();Text(grade.grade.title)}.font(quranFont(15)).frame(minHeight:44)}.accessibilityIdentifier("quran-qiyam-grade-"+String(grade.page))}}
                    if qiyam.completed > 0 {Button(qiyam.finished ? "سجّل القيام والمراجعة":"سجّل ما أتممت") {action(qiyam.finished && !qiyam.pastDay ? .commit:.commitPartial)}.font(quranFont(16,bold:true)).foregroundStyle(QuranNightColors.ink).frame(maxWidth:.infinity,minHeight:54).background(QuranNightColors.gold,in:Capsule()).accessibilityIdentifier("quran-qiyam-save")}
                }}
            } else {
                Button {action(.advance)} label: {
                    VStack(spacing:26) {Spacer();Text("الركعة "+number(qiyam.current+1)+" / "+number(qiyam.total)).font(quranFont(14));Text(qiyam.assignments[qiyam.current].title).font(quranSerif(42)).multilineTextAlignment(.center).foregroundStyle(QuranNightColors.gold);Text(qiyam.assignments[qiyam.current].status).font(quranFont(14));Spacer();Text("أتممت الركعة، المس للتي تليها").font(quranFont(14));Spacer().frame(height:30)}.frame(maxWidth:.infinity,maxHeight:.infinity).contentShape(Rectangle())
                }.buttonStyle(.plain).accessibilityIdentifier("quran-qiyam-rakah-done")
            }
        }.padding(20).foregroundStyle(QuranNightColors.text).background(QuranNightColors.during.ignoresSafeArea()).preferredColorScheme(.dark).disabled(busy)
            .sheet(isPresented:$exit) {VStack(alignment:.leading,spacing:16) {Text("جلستك محفوظة").font(quranSerif(27));Text("لا تُسجّل الركعات والمراجعة قبل تأكيدك.").font(quranFont(14));if qiyam.completed > 0 {Button("سجّل ما أتممت") {exit=false;action(.commitPartial)}.frame(minHeight:44).accessibilityIdentifier("quran-qiyam-partial")};if !qiyam.pastDay {Button("احتفظ بالمسودة لوقت آخر") {exit=false;close()}.frame(minHeight:44).accessibilityIdentifier("quran-qiyam-keep")};Button("تجاهل الجلسة") {exit=false;action(.discard)}.frame(minHeight:44).accessibilityIdentifier("quran-qiyam-discard");Button("تابع") {exit=false}.frame(minHeight:44)}.font(quranFont(15)).padding(24).foregroundStyle(QuranNightColors.gold).frame(maxWidth:.infinity,alignment:.leading).presentationBackground(QuranNightColors.background).presentationDetents([.height(390)]).environment(\.layoutDirection,.rightToLeft)}
    }
    private func number(_ n:Int)->String {let f=NumberFormatter();f.locale=Locale(identifier:state.numeralLocale);return f.string(from:NSNumber(value:n)) ?? String(n)}
}
