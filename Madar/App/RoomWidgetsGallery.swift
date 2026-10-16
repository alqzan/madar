import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots

struct RoomWidgetsGallery:View {
    @Bindable var session:AppSession
    @Environment(\.dismiss)private var dismiss
    private var theme:RoomTheme{.init(room:"bahw",dark:session.string("core.theme")=="dark")}
    private var now:Date{session.prayerNow()}
    private func snapshot(_ room:BuiltRoomWidget)->RoomWidgetSnapshot?{session.snapshotStore.read(room.rawValue,as:RoomWidgetSnapshot.self,now:now)?.payload}
    var body:some View {
        VStack(spacing:0) {
            HStack {Text("ودجات مدار").font(MadarTypography.title()).accessibilityIdentifier("room-widgets-title");Spacer();Button("تمّ"){dismiss()}.frame(minHeight:44)}.padding(.horizontal,20).padding(.top,12)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("أضفها من معرض الودجات في الآيفون، واختر الحجم هناك. اضغط مطوّلًا على الودجة لتختار قالبها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Link(destination:URL(string:"madar://salah")!) {
                        let prayers=session.snapshotStore.read("prayerNext",as:PrayerNextSnapshot.self,now:now)
                        NextPrayerView(entry:.init(date:now,snapshot:prayers?.payload,tzID:prayers?.tzID ?? session.activePlace.timeZoneID),previewFamily:.systemMedium).padding(16).frame(height:160).background(theme.surface,in:.rect(cornerRadius:26))
                    }.buttonStyle(.plain).accessibilityIdentifier("room-widget-prayer")
                    HStack(alignment:.top,spacing:12) {
                        Link(destination:URL(string:"madar://quran")!) {QuranWidgetContent(snapshot:session.snapshotStore.read("quran",as:QuranWidgetSnapshot.self,now:now)?.payload,template:.path,compact:true).padding(14).frame(height:170).frame(maxWidth:.infinity).background(RoomTheme(room:"quran",dark:session.string("core.theme")=="dark").surface,in:.rect(cornerRadius:24))}.buttonStyle(.plain).accessibilityIdentifier("room-widget-quran")
                        preview(.habits,family:.systemSmall,template:"today").frame(height:170)
                    }
                    preview(.upcoming,family:.systemMedium,template:"upcoming").frame(height:180)
                    Text("السنة وسطر اليوم").font(MadarTypography.section())
                    preview(.year,family:.systemMedium,template:"both").frame(height:185)
                    Link(destination:URL(string:BuiltRoomWidget.diaryWrite.route)!) {previewContent(.diaryWrite,family:.systemSmall,template:"write")}.buttonStyle(.plain).frame(height:170).accessibilityIdentifier("room-widget-diaryWrite")
                    Text("ودجة «سطر سريع» تفتح الكتابة ولا تعرض نصًا أو صورة من مذكراتك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }.padding(16)
            }.clipped()
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent)
        .environment(\.openURL,OpenURLAction{url in session.open(url);dismiss();return .handled})
        .onAppear{do{try session.publishSnapshot()}catch{session.errorMessage=error.localizedDescription}}
    }
    private func preview(_ room:BuiltRoomWidget,family:WidgetFamily,template:String)->some View {previewContent(room,family:family,template:template).accessibilityIdentifier("room-widget-"+room.rawValue)}
    private func previewContent(_ room:BuiltRoomWidget,family:WidgetFamily,template:String)->some View {
        RoomWidgetContent(room:room,snapshot:snapshot(room),template:template,family:family).padding(14).frame(maxWidth:.infinity,maxHeight:.infinity).background(theme.surface,in:.rect(cornerRadius:24))
    }
}
