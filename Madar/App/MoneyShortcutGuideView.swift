import SwiftUI
import SwiftData
import MadarData
import MadarCore
import MadarDesign

/// F09: instructions and observed intake, never a claim about an automation's enabled state.
struct MoneyShortcutGuideView: View {
    let app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.scenePhase) private var scene
    @State private var baseline: Set<UUID>?
    @State private var arrived: Date?
    @State private var checked = false
    @State private var failure: String?
    private var theme: RoomTheme { .init(room: "mal", dark: colorScheme == .dark) }
    var body: some View {
        ScrollView { VStack(alignment: .leading, spacing: 18) {
            HStack { Text("رسائل البنك إلى مدار").font(MadarTypography.title()); Spacer(); Button { dismiss() } label: { Image(systemName: "xmark").frame(width: 44, height: 44).overlay { Circle().stroke(theme.color("reserveText")) } }.accessibilityIdentifier("money-guide-close") }
            Text("تُعدّها مرة لكل بنك").font(MadarTypography.cardTitle()).foregroundStyle(theme.color("reserveText"))
            Text("مدار لا يقرأ صندوق رسائلك. أنت تختار الرسائل التي تمرّرها من تطبيق الاختصارات.").font(MadarTypography.body())
            step(1, "افتح أتمتة الرسائل", icon: "bolt.badge.clock", chips: ["الاختصارات", "أتمتة", "الرسالة"], detail: "أنشئ تحكمًا تلقائيًا شخصيًا جديدًا واختر وصول رسالة.")
            step(2, "حدّد رسائل البنك", icon: "line.3.horizontal.decrease", chips: ["المرسل", "الرسالة تحتوي على"], detail: "اختر مرسل البنك. إن لم يقبل النظام اسمه، استخدم عبارة مميزة من رسائله. إذا وضعت الشرطين فيلزم تحققهما معًا؛ تجنّب كلمات عامة تشمل رسائل أخرى.")
            step(3, "مرّر المحتوى إلى مدار", icon: "arrow.down.doc", chips: ["محتوى الرسالة", "سجّل رسالة بنك في مدار"], detail: "ابحث عن إجراء مدار بهذا الاسم، واجعل «نص الرسالة» محتوى الرسالة الواردة، و«المرسل» مرسلها. وقت الورود اختياري؛ إن تركته فارغًا يسجّل وقت التشغيل.")
            step(4, "شغّلها فور وصول الرسالة", icon: "play.circle", chips: ["تشغيل فورًا"], detail: "اختر التشغيل التلقائي دون سؤال قبل كل رسالة، وأوقف إشعار التشغيل إن ظهر هذا الخيار. قد تختلف أسماء الأزرار قليلًا مع نسخة iOS. كرّر الخطوات لكل بنك.")
            VStack(alignment: .leading, spacing: 12) {
                Text("اختبر الوصول").font(MadarTypography.cardTitle())
                Text("ابدأ الفحص، ثم جرّب وصول رسالة شراء أو كشف من المرسل الذي اخترته. افتح مدار بعدها وتحقق من النتيجة. رسائل التحقق والتسويق لا تُحفظ، فلا تصلح للاختبار.").font(MadarTypography.caption())
                Button(baseline == nil ? "ابدأ فحص الوصول" : "ابدأ فحصًا جديدًا") { start() }.frame(minHeight: 44).accessibilityIdentifier("money-guide-start")
                if baseline != nil {
                    Button("تحقق من الوصول") { check() }.frame(minHeight: 44).accessibilityIdentifier("money-guide-check")
                    Text(arrived != nil ? "وصلت رسالة عبر الاختصار ✓" : checked ? "لم تصل رسالة جديدة عبر الاختصار بعد" : "بانتظار رسالة جديدة عبر الاختصار").font(MadarTypography.body()).foregroundStyle(arrived != nil ? theme.color("surplusText") : theme.secondaryInk).accessibilityIdentifier("money-guide-status")
                    if let arrived { MadarDateLabel(app.dateLabels(.containing(arrived, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()); Text(AppMoneyService(app: app).time(arrived)).font(MadarTypography.fine()) }
                    if checked && arrived == nil { Text("راجع المرسل والعبارة، وأن محتوى الرسالة متصل بإجراء مدار، وأن الأتمتة ما زالت مفعّلة. افتح مدار مرة بعد إعادة تشغيل الهاتف، ثم جرّب مجددًا.").font(MadarTypography.caption()) }
                }
                if let failure { Text(failure).font(MadarTypography.caption()) }
            }.padding(18).background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
            Text("وصول رسالة يثبت تلك الرسالة فقط؛ لا يستطيع مدار معرفة أن أتمتتك ستبقى مفعّلة. الراتب والمصروف الكبير والمطابقة تنتظر قرارك داخل التطبيق. إذا تعطل الاختصار، استخدم «الصق رسائل» في رسائل البنك أو سجّل مصروفًا يدويًا.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Link("دليل Apple لإنشاء التحكم التلقائي", destination: URL(string: "https://support.apple.com/ar-sa/guide/shortcuts/apdfbdbd7123/ios")!).font(MadarTypography.caption()).frame(minHeight: 44)
        }.padding(20).frame(maxWidth: 620).frame(maxWidth: .infinity) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain).toolbarVisibility(.hidden, for: .navigationBar)
            .onChange(of: app.prayerRevision) { if baseline != nil { check() } }
            .onChange(of: scene) { if scene == .active && baseline != nil { check() } }
    }
    private func step(_ n: Int, _ title: String, icon: String, chips: [String], detail: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text(app.digits(n)).font(MadarTypography.cardTitle()).frame(width: 38, height: 38).overlay { Circle().stroke(theme.color("reserveText")) }; Text(title).font(MadarTypography.section()); Spacer(); Image(systemName: icon).font(.title2).foregroundStyle(theme.color("reserveText")) }
            ForEach(chips, id: \.self) { text in HStack { Image(systemName: "chevron.down").font(.caption); Text(text).font(MadarTypography.body()); Spacer() }.padding(10).background(theme.background, in: RoundedRectangle(cornerRadius: 8)) }
            Text(detail).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }.padding(16).background(theme.surface, in: RoundedRectangle(cornerRadius: 16))
    }
    private func messages() throws -> [BankMessage] {
        guard !app.maintenanceInProgress else { throw BackupOperationError.busy }
        guard app.lockController?.canPresent(.app) ?? app.protectedDataAuthorized else { throw DataError.authenticationFailed }
        return try ModelContext(app.container).fetch(FetchDescriptor<BankMessage>()).filter { $0.channel == "shortcut" }
    }
    private func start() { do { baseline = Set(try messages().map(\.id)); arrived = nil; checked = false; failure = nil } catch { failure = "تعذّر بدء الفحص. أعد فتح الصفحة وحاول مرة أخرى." } }
    private func check() { guard let baseline else { return }; do { arrived = try messages().filter { !baseline.contains($0.id) }.map(\.receivedAt).max(); checked = true; failure = nil } catch { failure = "تعذّر التحقق الآن. حاول بعد فتح مدار مجددًا." } }
}
