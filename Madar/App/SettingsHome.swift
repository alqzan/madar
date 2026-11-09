import SwiftUI
import MadarData
import MadarCore
import MadarDesign

/// Owner, 3 Nov 2026: «خصّص مدار» was one long pile (open the inkwell, open money, tafsir, widgets, twelve sections).
/// It is now three groups: the rooms, each room's own settings, and the general settings of the app.
struct SettingsHome: View {
    @Bindable var session: AppSession
    let openTafsir: () -> Void
    let openMaker: () -> Void
    let openGallery: () -> Void
    let resetAll: () -> Void
    let changes: String
    @Environment(\.roomTheme) private var theme

    /// iPad, wide: the rooms on the right, the general settings beside them.
    var twoColumns = false

    var body: some View {
        if twoColumns {
            HStack(alignment: .top, spacing: 28) {
                VStack(alignment: .leading, spacing: 24) { roomGroups }.frame(maxWidth: .infinity)
                VStack(alignment: .leading, spacing: 24) { generalGroup }.frame(maxWidth: .infinity)
            }
        } else {
            VStack(alignment: .leading, spacing: 24) { roomGroups; generalGroup }
        }
    }

    @ViewBuilder private var roomGroups: some View {
            group("الأقسام") {
                link("أقسامك والبهو", "أضف قسمًا أو أخفِه، ورتّب البهو وأحجامه", "square.grid.2x2") {
                    SettingsPage(title: "أقسامك والبهو") {
                        BahwBlocksSection(session: session)
                        action("ودجات الشاشة الرئيسية", "square.grid.2x2", openGallery)
                        action("اصنع ودجة", "square.stack.3d.up", openMaker)
                    }
                }
            }
            group("إعدادات كل قسم") {
                if session.roomEnabled(.salah) { link("الصلاة", "المواقيت وطريقة الحساب والتنبيهات", "clock") { sectionsPage("الصلاة", ["الصلاة", "المواقيت"]) } }
                if session.roomEnabled(.habits) { link("العادات", "التذكير والسلسلة وما تعرضه الودجة", "checkmark.circle") { sectionsPage("العادات", ["العادات", "الذكاء"]) } }
                if session.roomEnabled(.year) { link("السنة", "أي سنة تعرض", "calendar") { sectionsPage("السنة", ["السنة"]) } }
                if session.roomEnabled(.upcoming) { link("الأيام القادمة", "عدد الأيام المعروضة", "hourglass") { sectionsPage("الأيام القادمة", ["الأيام القادمة"]) } }
                if session.roomEnabled(.quran) { door("القرآن", "مكتبة التفاسير", "book", openTafsir) }
                if session.roomEnabled(.notes) { link("المذكرات", "الصفحة والتقويم والهامش والنقل", "book.closed") { DiaryCustomizeView(app: session) } }
                if session.roomEnabled(.mal) { door("المال", "اليوم والحدود والتذكيرات والسفر", "banknote") { session.moneyOpensSettings = true; session.moneyOpen = true } }
                if session.roomEnabled(.mihbara) { door("المحبرة", "إعدادات المحبرة داخل القسم", "books.vertical") { session.selectedTab = "mihbara" } }
                if !hasRoomSettings { Text("أضف قسمًا من «أقسامك والبهو» لتظهر إعداداته هنا.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            }
    }

    private var generalGroup: some View {
            group("عام") {
                link("اليوم والتقويم", "بداية اليوم والتقويم الأول", "moon") { sectionsPage("اليوم والتقويم", ["اليوم والتقويم", "مدينتك"]) }
                link("المظهر", "الوضع والألوان والأرقام", "paintpalette") { sectionsPage("المظهر", ["المظهر"]) }
                link("الإشعارات", "تذكيرات الغرف وأوقات الصمت", "bell.badge") { sectionsPage("الإشعارات", ["الإشعارات"]) }
                link("الخصوصية والبحث", "فهرسة Spotlight وإخفاء الأرقام", "lock") { sectionsPage("الخصوصية والبحث", ["الخصوصية", "البحث"]) }
                if let backup = session.backupService {
                    link("النسخ والاستعادة", "احفظ بياناتك أو استعدها", "externaldrive") {
                        BackupSettingsView(service: backup, numerals: session.string("core.numerals") == "western" ? .western : .hindi,
                                           dates: { session.dateLabels(GregorianDay.containing($0, in: session.activePlace.timeZone)) },
                                           time: { session.backupTime($0) })
                    }
                }
                link("انقل من مدار القديم", "استيراد بياناتك السابقة", "square.and.arrow.down") { LegacyMoveView(app: session) }
                door("أعِد الإعدادات المتفق عليها", changes, "arrow.counterclockwise", resetAll)
            }
    }

    private var hasRoomSettings: Bool { [BahwBlock.salah, .habits, .year, .upcoming, .quran, .notes, .mal, .mihbara].contains { session.roomEnabled($0) } }

    private func sectionsPage(_ title: String, _ sections: [String]) -> some View {
        SettingsPage(title: title) {
            if sections.contains("الإشعارات") { NotificationPermissionCard(session: session) }
            ForEach(sections, id: \.self) { section in
                let definitions = session.schema.settings.filter { definition in
                    guard AppSession.supportedKeys.contains(definition.key), sectionFor(definition.key) == section else { return false }
                    if definition.key == "core.hijriOffset" && session.string("core.hijriSource") != "sighting" { return false }
                    if ["notif.quietFrom", "notif.quietUntil"].contains(definition.key) && !session.bool("notif.quietAfterIsha") { return false }
                    return true
                }
                if !definitions.isEmpty {
                    SettingsSection(title: section, symbol: "slider.horizontal.3", definitions: definitions, session: session, searching: true, highlightedSettingKey: nil)
                }
            }
            SettingsPageReset(session: session, keys: AppSession.supportedKeys.filter { sections.contains(sectionFor($0)) })
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title).font(MadarTypography.section()).accessibilityAddTraits(.isHeader)
            VStack(spacing: 0) { content() }
                .background(theme.surface, in: .rect(cornerRadius: 20))
        }
    }

    private func rowLabel(_ title: String, _ subtitle: String, _ symbol: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: symbol).font(.system(size: 18)).frame(width: 28).foregroundStyle(theme.accent)
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(MadarTypography.body().bold())
                Text(subtitle).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).multilineTextAlignment(.leading)
            }
            Spacer(minLength: 8)
            Image(systemName: "chevron.left").font(.footnote).foregroundStyle(theme.secondaryInk)
        }
        .padding(.horizontal, 16).padding(.vertical, 12).frame(maxWidth: .infinity, minHeight: 56, alignment: .leading).contentShape(Rectangle())
    }

    private func link<Destination: View>(_ title: String, _ subtitle: String, _ symbol: String, @ViewBuilder _ destination: @escaping () -> Destination) -> some View {
        NavigationLink { destination() } label: { rowLabel(title, subtitle, symbol) }
            .buttonStyle(.madarPlain).accessibilityIdentifier("settings-link-" + title)
    }

    private func door(_ title: String, _ subtitle: String, _ symbol: String, _ open: @escaping () -> Void) -> some View {
        Button(action: open) { rowLabel(title, subtitle, symbol) }.buttonStyle(.madarPlain).accessibilityIdentifier("settings-door-" + title)
    }

    private func action(_ title: String, _ symbol: String, _ run: @escaping () -> Void) -> some View {
        Button(action: run) {
            HStack { Label(title, systemImage: symbol).font(MadarTypography.section()); Spacer(); Image(systemName: "chevron.left").font(.footnote) }
                .padding(16).frame(maxWidth: .infinity, minHeight: 50, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 20)).contentShape(Rectangle())
        }.buttonStyle(.madarPlain)
    }
}

/// A settings page in the room look, pushed from the settings home.
struct SettingsPage<Content: View>: View {
    let title: String
    @ViewBuilder let content: () -> Content
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text(title).font(MadarTypography.title()).accessibilityAddTraits(.isHeader)
                content()
            }.padding(.horizontal, 16).padding(.vertical, 16).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).font(MadarTypography.body())
    }
}
