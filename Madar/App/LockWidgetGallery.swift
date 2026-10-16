import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots

struct LockWidgetGallery:View {
    @Bindable var session:AppSession
    @Environment(\.dismiss)private var dismiss
    private var theme:RoomTheme{.init(room:"bahw",dark:session.string("core.theme")=="dark")}
    private func value(_ room:BuiltRoomWidget)->RoomWidgetSnapshot?{session.snapshotStore.read(room.rawValue,as:RoomWidgetSnapshot.self,now:session.prayerNow())?.payload}
    var body:some View {
        VStack(spacing:0) {
            HStack {Button{dismiss()}label:{Label("الودجات",systemImage:"chevron.right")}.frame(minHeight:44);Spacer();Text("القفل والاستعداد").font(.custom("thmanyahserifdisplay-Bold",size:26,relativeTo:.title)).accessibilityIdentifier("lock-widgets-title")}.padding(16)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("أضفها من تخصيص شاشة القفل. تتبع ألوان النظام؛ وفي الاستعداد تُستخدم ودجات الشاشة الرئيسية.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    HStack(spacing:14){ForEach(BuiltRoomWidget.allCases,id:\.self){room in Link(destination:URL(string:room.route)!){RoomWidgetContent(room:room,snapshot:value(room),family:.accessoryCircular).frame(maxWidth:.infinity).frame(height:74)}.buttonStyle(.plain)}}.padding(14).background(theme.surface,in:.rect(cornerRadius:22))
                    RoomWidgetContent(room:.upcoming,snapshot:value(.upcoming),family:.accessoryInline).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:18))
                    HStack(spacing:16) {
                        let next=session.snapshotStore.read("prayerNext",as:PrayerNextSnapshot.self,now:session.prayerNow())
                        NextPrayerView(entry:.init(date:session.prayerNow(),snapshot:next?.payload,tzID:next?.tzID ?? session.activePlace.timeZoneID),previewFamily:.accessoryRectangular)
                        RoomWidgetContent(room:.habits,snapshot:value(.habits),family:.accessoryRectangular)
                    }.frame(height:78).padding(14).background(theme.surface,in:.rect(cornerRadius:22))
                    Text("مركز التحكم وزر الإجراء").font(MadarTypography.section())
                    HStack(spacing:12) {
                        Link(destination:URL(string:"madar://notes/write")!){Label("سطر سريع",image:"MadarDiary").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20))}.accessibilityIdentifier("control-preview-diary")
                        Link(destination:URL(string:"madar://bahw/habits")!){Label("عاداتك",image:"MadarHabits").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20))}.accessibilityIdentifier("control-preview-habits")
                    }.buttonStyle(.plain)
                    Text("«سطر سريع» يفتح المحرر مباشرة، و«عاداتك» يفتح الغرفة لاختيار ما تسجّله. تسجيل الصلاة ومؤقّت المراجعة متاحان أيضًا في المعرض.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text("وضع الاستعداد").font(MadarTypography.section())
                    HStack(spacing:12){RoomWidgetContent(room:.habits,snapshot:value(.habits),family:.systemSmall).padding(14).background(theme.surface,in:.rect(cornerRadius:24));RoomWidgetContent(room:.upcoming,snapshot:value(.upcoming),template:"nearest",family:.systemSmall).padding(14).background(theme.surface,in:.rect(cornerRadius:24))}.frame(height:180)
                }.padding(16)
            }.clipped()
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).toolbarVisibility(.hidden,for:.navigationBar)
    }
}
