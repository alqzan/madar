import SwiftUI
import WidgetKit
import MadarDesign
import MadarSnapshots

struct RoomWidgetsGallery:View {
    @Environment(\.colorScheme) private var colorScheme
    @Bindable var session:AppSession
    @Environment(\.dismiss)private var dismiss
    private var theme:RoomTheme{.init(room:"bahw",dark:colorScheme == .dark)}
    private var now:Date{session.prayerNow()}
    private func snapshot(_ room:BuiltRoomWidget)->RoomWidgetSnapshot?{session.snapshotStore.read(room.rawValue,as:RoomWidgetSnapshot.self,now:now)?.payload}
    private func mihbaraSnapshot()->(MihbaraSnapshot?,Bool){let value=session.snapshotStore.read(BuiltRoomWidget.mihbara.rawValue,as:MihbaraSnapshot.self,now:now);return(value?.payload,value?.privacy.notesLocked == true)}
    var body:some View {
        VStack(spacing:0) {
            HStack {Text("ودجات مدار").font(MadarTypography.title()).accessibilityIdentifier("room-widgets-title");Spacer();Button("تمّ"){dismiss()}.frame(minHeight:44)}.padding(.horizontal,20).padding(.top,12)
            ScrollView {
                VStack(alignment:.leading,spacing:16) {
                    Text("أضفها من معرض الودجات في الآيفون، واختر الحجم هناك. اضغط مطوّلًا على الودجة لتختار قالبها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    NavigationLink {LockWidgetGallery(session:session)} label:{Label("القفل والاستعداد ومركز التحكم",systemImage:"lock.rectangle").font(MadarTypography.section()).frame(maxWidth:.infinity,minHeight:44)}.buttonStyle(.madarPlain).accessibilityIdentifier("room-widgets-lock")
                    Link(destination:URL(string:"madar://salah")!) {
                        let prayers=session.snapshotStore.read("prayerNext",as:PrayerNextSnapshot.self,now:now)
                        NextPrayerView(entry:.init(date:now,snapshot:prayers?.payload,tzID:prayers?.tzID ?? session.activePlace.timeZoneID),previewFamily:.systemMedium).padding(16).frame(height:160).background(theme.surface,in:.rect(cornerRadius:26))
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("room-widget-prayer")
                    HStack(alignment:.top,spacing:12) {
                        Link(destination:URL(string:"madar://quran")!) {QuranWidgetContent(snapshot:session.snapshotStore.read("quran",as:QuranWidgetSnapshot.self,now:now)?.payload,template:.path,compact:true,smallHome:true).padding(14).frame(height:170).frame(maxWidth:.infinity).background(RoomTheme(room:"quran",dark:colorScheme == .dark).surface,in:.rect(cornerRadius:24))}.buttonStyle(.madarPlain).accessibilityIdentifier("room-widget-quran")
                        preview(.habits,family:.systemSmall,template:"today").frame(height:170)
                    }
                    Text("قالب العادات القادمة").font(MadarTypography.section())
                    Text("المتوسطة · أقرب ٣ مواعيد").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    previewContent(.habits,family:.systemMedium,template:"coming").frame(height:170).accessibilityIdentifier("room-widget-habits-coming-medium")
                    HStack(alignment:.top,spacing:12) {
                        previewContent(.habits,family:.systemSmall,template:"coming").frame(width:170,height:170).accessibilityIdentifier("room-widget-habits-coming-small")
                        VStack(alignment:.leading,spacing:6) {
                            Text("الصغيرة").font(MadarTypography.section())
                            Text("أقرب موعد وآخر إنجاز").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        }.frame(maxWidth:.infinity,minHeight:170,alignment:.center)
                    }
                    preview(.upcoming,family:.systemMedium,template:"upcoming").frame(height:180)
                    GeometryReader { geometry in
                        let side = geometry.size.width * 0.44
                        HStack(alignment:.top,spacing:12) {
                            previewContent(.upcoming,family:.systemSmall,template:"upcoming").frame(width:side,height:side).accessibilityIdentifier("room-widget-upcoming-small")
                            VStack(alignment:.leading,spacing:6) {
                                Text("الصغيرة").font(MadarTypography.section())
                                Text("اليومان الأقرب مع مصدرهما").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                            }.frame(maxWidth:.infinity,minHeight:side,alignment:.center)
                        }.frame(maxWidth:.infinity,maxHeight:.infinity,alignment:.topLeading)
                    }.frame(height:180)
                    Link(destination:URL(string:"madar://mal")!){previewContent(.money,family:.systemMedium,template:"now")}.buttonStyle(.madarPlain).frame(height:180).accessibilityIdentifier("room-widget-money")
                    Link(destination:URL(string:BuiltRoomWidget.mihbara.route)!){preview(.mihbara,family:.systemMedium,template:"summary").frame(height:190)}.buttonStyle(.madarPlain).accessibilityIdentifier("room-widget-mihbara")
                    Text("السنة وسطر اليوم").font(MadarTypography.section())
                    preview(.year,family:.systemMedium,template:"both").frame(height:185)
                    Link(destination:URL(string:BuiltRoomWidget.diaryWrite.route)!) {previewContent(.diaryWrite,family:.systemSmall,template:"write")}.buttonStyle(.madarPlain).frame(height:170).accessibilityIdentifier("room-widget-diaryWrite")
                    let diaryRows=Set((snapshot(.diaryWrite)?.rows ?? []).map(\.id))
                    if diaryRows.isEmpty {
                        Text("ودجة «سطر سريع» تفتح الكتابة ولا تعرض نصًا أو صورة من مذكراتك.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    } else {
                        // RD7: shown only after the owner turned on «محتوى المذكرات في الودجات».
                        HStack(spacing:12) {
                            ForEach(["intention","lastLine"].filter(diaryRows.contains),id:\.self) { template in
                                Link(destination:URL(string:BuiltRoomWidget.diaryWrite.route)!) {previewContent(.diaryWrite,family:.systemSmall,template:template)}.buttonStyle(.madarPlain).frame(height:170).accessibilityIdentifier("room-widget-diary-"+template)
                            }
                        }
                        if diaryRows.contains("thatDay") {
                            Link(destination:URL(string:"madar://notes")!) {previewContent(.diaryWrite,family:.systemMedium,template:"thatDay")}.buttonStyle(.madarPlain).frame(height:170).accessibilityIdentifier("room-widget-diary-thatDay")
                        }
                        Text("هذه الودجات تعرض نصًا من مذكراتك لأنك فعّلت «محتوى المذكرات في الودجات»، ويحجبه iOS حين يكون الجهاز مقفلًا.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    }
                }.padding(16)
            }.clipped()
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accent).toolbarVisibility(.hidden,for:.navigationBar)
        .environment(\.openURL,OpenURLAction{url in session.open(url);dismiss();return .handled})
        .onAppear{do{try session.publishSnapshot()}catch{session.errorMessage=madarUserMessage(error)}}
    }
    private func preview(_ room:BuiltRoomWidget,family:WidgetFamily,template:String)->some View {previewContent(room,family:family,template:template).accessibilityIdentifier("room-widget-"+room.rawValue)}
    private func previewContent(_ room:BuiltRoomWidget,family:WidgetFamily,template:String)->some View {
        let mihbara=mihbaraSnapshot()
        return RoomWidgetContent(room:room,snapshot:snapshot(room),template:template,family:family,mihbaraSnapshot:room == .mihbara ? mihbara.0 : nil,mihbaraLocked:room == .mihbara && mihbara.1,numerals:session.string("core.numerals")).padding(14).frame(maxWidth:.infinity,maxHeight:.infinity).background(room == .money ? (MadarToken.colors["widgetIdentity.room.mal.\(colorScheme == .dark ? "dark" : "light").bg"] ?? theme.surface) : room == .mihbara ? RoomTheme(room:"mihbara",dark:colorScheme == .dark).surface : theme.surface,in:.rect(cornerRadius:24))
    }
}
