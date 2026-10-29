import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots

struct LockWidgetGallery:View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session:AppSession
    @Environment(\.dismiss)private var dismiss
    private var theme:RoomTheme{.init(room:"bahw",dark:colorScheme == .dark)}
    private func value(_ room:BuiltRoomWidget)->RoomWidgetSnapshot?{session.snapshotStore.read(room.rawValue,as:RoomWidgetSnapshot.self,now:session.prayerNow())?.payload}
    private func mihbaraValue()->(MihbaraSnapshot?,Bool){let value=session.snapshotStore.read(BuiltRoomWidget.mihbara.rawValue,as:MihbaraSnapshot.self,now:session.prayerNow());return(value?.payload,value?.privacy.notesLocked == true)}
    private func preview(_ room:BuiltRoomWidget,family:WidgetFamily)->some View {
        let mihbara=mihbaraValue()
        return RoomWidgetContent(room:room,snapshot:value(room),family:family,mihbaraSnapshot:room == .mihbara ? mihbara.0 : nil,mihbaraLocked:room == .mihbara && mihbara.1,numerals:session.string("core.numerals"))
    }
    var body:some View {
        VStack(spacing:0) {
            HStack {Button{dismiss()}label:{Label("الودجات",systemImage:"chevron.right")}.frame(minHeight:44);Spacer();Text("القفل والاستعداد").font(.custom("thmanyahserifdisplay-Bold",size:26,relativeTo:.title)).accessibilityIdentifier("lock-widgets-title")}.padding(16)
            ScrollView {
                VStack(alignment:.leading,spacing:18) {
                    Text("أضفها من تخصيص شاشة القفل. تتبع ألوان النظام؛ وفي الاستعداد تُستخدم ودجات الشاشة الرئيسية.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 18) {
                        ForEach(BuiltRoomWidget.allCases, id: \.self) { room in
                            Link(destination: URL(string: room.route)!) {
                                VStack(spacing: 6) {
                                    preview(room, family: .accessoryCircular).frame(width: 74, height: 74)
                                    Text(room.title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                }.frame(maxWidth: .infinity)
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("lock-circle-" + room.rawValue)
                        }
                    }.padding(14).background(theme.surface, in: .rect(cornerRadius: 22))
                    RoomWidgetContent(room:.upcoming,snapshot:value(.upcoming),family:.accessoryInline).padding(14).frame(maxWidth:.infinity,alignment:.leading).background(theme.surface,in:.rect(cornerRadius:18))
                    HStack(spacing:16) {
                        let next=session.snapshotStore.read("prayerNext",as:PrayerNextSnapshot.self,now:session.prayerNow())
                        NextPrayerView(entry:.init(date:session.prayerNow(),snapshot:next?.payload,tzID:next?.tzID ?? session.activePlace.timeZoneID),previewFamily:.accessoryRectangular)
                        preview(.habits,family:.accessoryRectangular)
                    }.frame(height:78).padding(14).background(theme.surface,in:.rect(cornerRadius:22))
                    Text("مركز التحكم وزر الإجراء").font(MadarTypography.section())
                    HStack(spacing:12) {
                        Link(destination:URL(string:"madar://notes/write")!){Label("سطر سريع",image:"MadarDiary").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20))}.accessibilityIdentifier("control-preview-diary")
                        Link(destination:URL(string:"madar://bahw/habits")!){Label("عاداتك",image:"MadarHabits").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20))}.accessibilityIdentifier("control-preview-habits")
                        Link(destination:URL(string:BuiltRoomWidget.mihbara.route)!){Label("المحبرة",systemImage:"books.vertical").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20))}.accessibilityIdentifier("control-preview-mihbara")
                    }.buttonStyle(.madarPlain)
                    Text("كل عنصر يفتح غرفته من دون عرض محتواها. تسجيل الصلاة ومؤقّت المراجعة متاحان أيضًا في المعرض.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Link(destination:URL(string:"madar://mal/add")!){Label("مصروف",systemImage:"plus.circle").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:56).background(theme.surface,in:.rect(cornerRadius:20))}.buttonStyle(.madarPlain).accessibilityIdentifier("control-preview-money")
                    Text("وضع الاستعداد").font(MadarTypography.section())
                    HStack(spacing:12){preview(.habits,family:.systemSmall).padding(14).background(theme.surface,in:.rect(cornerRadius:24));preview(.mihbara,family:.systemSmall).padding(14).background(RoomTheme(room:"mihbara",dark:colorScheme == .dark).surface,in:.rect(cornerRadius:24))}.frame(height:180)
                }.padding(16)
            }.clipped()
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).toolbarVisibility(.hidden,for:.navigationBar)
    }
}
