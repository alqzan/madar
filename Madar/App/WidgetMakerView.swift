import SwiftUI
import SwiftData
import WidgetKit
import MadarCore
import MadarData
import MadarDesign
import MadarCommands
import MadarSnapshots

struct WidgetMakerView: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var nameFocused: Bool
    @State private var draft = WidgetMakerDraft()
    @State private var baseline: WidgetMakerDraft?
    @State private var saved: [WidgetMakerDraft] = []
    @State private var rows: [WidgetCatalogSnapshot.Row] = []
    @State private var habits: [HabitReading] = []
    @State private var days: [BahwUpcomingItem] = []
    @State private var busy = false
    @State private var status = ""
    @State private var deleting: WidgetMakerDraft?
    @State private var discard = false
    @State private var pendingSelection: WidgetMakerDraft?
    @State private var pendingTemplateRoom: String?
    @State private var selectionRevision = 0
    @State private var makerDataReady = false
    @State private var beforeReset: (WidgetMakerStyle, String)?
    /// A route creates an unsaved template draft, while `baseline` normally describes a saved preset.
    @State private var baselineIsPersisted = false
    private var theme: RoomTheme { .init(room: "bahw", dark: colorScheme == .dark) }
    private var dirty: Bool { baseline.map { draft != $0 } ?? (!draft.name.isEmpty || !draft.items.isEmpty || draft.style != WidgetMakerStyle()) }
    private var family: WidgetFamily {
        if draft.familyID == "extraLargePortrait" {
            return .systemExtraLargePortrait
        }
        return switch draft.familyID { case "small": .systemSmall; case "large": .systemLarge; case "accessoryCircular": .accessoryCircular; case "accessoryRectangular": .accessoryRectangular; case "accessoryInline": .accessoryInline; default: .systemMedium }
    }
    private var pinsPreview: Bool { !dynamicTypeSize.isAccessibilitySize && !["large", "extraLargePortrait"].contains(draft.familyID) }
    private var config: WidgetCatalogSnapshot.Config { .init(id: draft.id, name: draft.name.isEmpty ? "مدار" : draft.name, familyID: draft.familyID, styleJSON: (try? JSONEncoder().encode(draft.style)) ?? Data(), rows: rows) }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18, pinnedViews: [.sectionHeaders]) {
                Section {
                Color.clear.frame(height: 0).id("widget-maker-controls")
                if !pinsPreview { preview }

                if draft.style.surface == "lock" {
                    choices("معاينة الحجم", selection: $draft.familyID, options: [("accessoryCircular", "دائرية"), ("accessoryRectangular", "مستطيلة"), ("accessoryInline", "سطر")])
                } else {
                    choices("معاينة الحجم", selection: $draft.familyID, options: previewFamilies)
                }
                Text("تضيف ودجة النظام من معرض iOS، وتختار حجمها هناك. ثم اختر اسمها من «القالب».").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                contentChoices
                if !draft.items.isEmpty { selectedOrder }
                choices("العائلة", selection: $draft.style.family, options: [("manuscript", "مخطوط"), ("glass", "زجاج"), ("ink", "حبر")])
                if draft.style.family == "glass", ["home", "standby"].contains(draft.style.surface) {
                    Text("مظهر الزجاج على شاشة iPhone يتبع مظهر الشاشة الرئيسية.")
                        .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                choices("الخط", selection: $draft.style.font, options: [("naskh", "نسخ"), ("modern", "حديث")])
                choices("الأرقام", selection: $draft.style.numerals, options: [("hindi", "١٢٣"), ("western", "123")])
                choices("الكثافة", selection: $draft.style.density, options: [("compact", "مضغوطة"), ("regular", "مريحة"), ("airy", "رحبة")])
                Toggle("بالرسم", isOn: $draft.style.showArt).font(MadarTypography.body()).frame(minHeight: 44).accessibilityIdentifier("widget-maker-art")
                colors
                MadarCard {
                    VStack(spacing: 12) {
                        behavior("تتبدّل وحدها بالوقت", detail: "يتقدّم العدّ الأقرب، وتبقى أولويتك لبقية العناصر", value: $draft.style.smartBundle, id: "smart")
                        Divider()
                        behavior("تختفي إذا لا شيء يهمّ", detail: "تختفي من البهو، وتقل أولويتها في الرزمة الذكية", value: $draft.style.hideWhenEmpty, id: "empty")
                        Divider()
                        behavior("أخفِ المال على شاشة القفل", detail: "إخفاء المال خارج التطبيق يبقى هو الحاكم", value: $draft.style.hideMoney, id: "money")
                        Divider()
                        behavior("في رمضان تصير عدّ الإفطار", detail: "بتوقيت مدينتك أو وجهة سفرك", value: $draft.style.iftarCountdown, id: "iftar")
                        Divider()
                        behavior("أزرار تُتمّ من الودجة", detail: "خطوة من عادة مخصصة؛ العادة المربوطة تُفتح دون تسجيل", value: $draft.style.interactive, id: "interactive")
                    }
                }
                Button("أعِد المظهر الافتراضي") { beforeReset = (draft.style, draft.familyID); draft.style = .init(); draft.familyID = "medium" }.frame(minHeight: 44)
                if let previous = beforeReset { Button("تراجع عن إعادة المظهر") { draft.style = previous.0; draft.familyID = previous.1; beforeReset = nil }.frame(minHeight: 44) }
                if !saved.isEmpty { savedWidgets }
                if session.undoToken != nil {
                    Button("تراجع عن آخر حفظ أو حذف") { session.undo() }.frame(minHeight: 44).accessibilityIdentifier("widget-maker-undo")
                }
                } header: {
                    VStack(spacing: 10) {
                        makerHeader
                        if pinsPreview { preview }
                        choices("المكان", selection: Binding(get: { draft.style.surface }, set: { surface in
                            draft.style.surface = surface; draft.familyID = surface == "lock" ? "accessoryRectangular" : "medium"
                        }), options: [("home", "الرئيسية"), ("lock", "القفل"), ("lobby", "البهو"), ("standby", "الاستعداد")])
                    }.padding(.bottom, 10).background(theme.background)
                }
            }.padding(16)
        }
        .onChange(of: selectionRevision) {
            let target = draft.items.first.map { "widget-item-" + $0 } ?? "widget-maker-controls"
            proxy.scrollTo(target, anchor: .center)
        }
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.accentFill)
        .disabled(busy)
        .environment(\.roomTheme, theme).toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) { saveBar }
        .interactiveDismissDisabled(dirty)
        .alert("تجاهل تعديل الودجة؟", isPresented: $discard) {
            Button("تجاهله", role: .destructive) {
                if let pendingSelection { applySelection(pendingSelection); self.pendingSelection = nil } else { dismiss() }
            }
            Button("أكمل التعديل", role: .cancel) { pendingSelection = nil }
        } message: { Text("التعديل الذي لم تحفظه لن يبقى.") }
        .confirmationDialog("احذف الودجة المحفوظة؟", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), titleVisibility: .visible) {
            if let deleting { Button("احذفها", role: .destructive) { remove(deleting) } }
            Button("إلغاء", role: .cancel) { deleting = nil }
        } message: { Text(deleting?.id == draft.id && dirty ? "يبقى محتوى غرفك كما هو، ويتاح التراجع. تعديلك الذي لم تحفظه على هذه الودجة لن يبقى. يظل موضع ودجة النظام تحت تحكم iOS." : "يبقى محتوى غرفك كما هو، ويتاح التراجع. يظل موضع ودجة النظام تحت تحكم iOS.") }
        // AU-28: «حُفظت …» stops claiming the widget is saved once it is edited again.
        .onChange(of: draft) { if dirty, !status.isEmpty { status = "" } }
        .task {
            reload()
            habits = (try? HabitRepository(context: ModelContext(session.container)).readings(at: session.prayerNow())) ?? []
            days = AppBahwService(session: session).upcoming(limit: Int.max).filter { UUID(uuidString: $0.id) != nil }
            makerDataReady = true
            applyInitialRoom(session.widgetMakerRoute?.parameters["template"])
        }
        .onChange(of: session.widgetMakerRouteID) { _, requestID in
            guard makerDataReady, requestID != nil else { return }
            guard let room = session.widgetMakerRoute?.parameters["template"] else { pendingTemplateRoom = nil; return }
            if busy { pendingTemplateRoom = room; return }
            applyInitialRoom(room)
        }
        .task(id: draft.items.joined(separator: "|") + "-\(draft.style.iftarCountdown)-\(draft.style.surface)-\(session.prayerRevision)") {
            try? await Task.sleep(for: .milliseconds(150)); guard !Task.isCancelled else { return }
            rows = session.widgetMakerRows(draft, at: session.prayerNow(), outside: draft.style.surface != "lobby")
        }
        .onChange(of: session.prayerRevision) { reload() }
    }
    private var makerHeader: some View {
        HStack {
            Button { if dirty { pendingSelection = nil; discard = true } else { dismiss() } } label: {
                Label("رجوع", systemImage: "chevron.right").frame(width: 72, height: 44)
            }.accessibilityIdentifier("widget-maker-close")
            VStack(spacing: 2) {
                Text("صانع الودجة").font(.custom("thmanyahserifdisplay-Bold", size: 24, relativeTo: .title2))
                    .accessibilityIdentifier("widget-maker-title")
                Text("اصنعها مرة، واخترها حيث تحب").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }.frame(maxWidth: .infinity)
            Color.clear.frame(width: 72, height: 44)
        }
    }
    private var preview: some View {
        VStack(spacing: 12) {
            WidgetMakerContent(config: config, family: family, date: session.prayerNow(), timeZoneID: AppBahwService(session: session).prayerLocation().place.timeZoneID, emptyPrompt: draft.items.isEmpty ? "اختر المحتوى الذي تحب أن تراه" : nil)
                .padding(14)
                .frame(width: family == .systemSmall ? 170 : family == .accessoryCircular ? 100 : nil, height: draft.familyID == "extraLargePortrait" ? 500 : family == .systemLarge ? 340 : draft.style.surface == "lock" ? 100 : 170)
                .modifier(WidgetMakerAppSurface(style: draft.style, dark: colorScheme == .dark, cornerRadius: 24))
                .allowsHitTesting(false).accessibilityElement(children: .contain).accessibilityIdentifier("widget-maker-preview")
            MadarDateLabel(session.dateLabels(AppBahwService(session: session).today), primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine())
                .foregroundStyle(theme.secondaryInk)
        }.padding(14).frame(maxWidth: .infinity).background(LinearGradient(colors: [theme.color("lapis").opacity(0.3), theme.color("amber").opacity(0.3)], startPoint: .top, endPoint: .bottom), in: .rect(cornerRadius: 28))
    }
    private var previewFamilies: [(String, String)] {
        [("small", "صغيرة"), ("medium", "متوسطة"), ("large", "كبيرة"), ("extraLargePortrait", "ضخمة")]
    }
    private var contentChoices: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("ماذا تعرض؟").font(MadarTypography.section()); Spacer(); if !draft.items.isEmpty { Button("امسح") { draft.items = [] }.font(MadarTypography.caption()).frame(minHeight: 44) } }
            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: dynamicTypeSize.isAccessibilitySize ? 2 : 3), spacing: 8) {
                // FB-34: the Forty Nawawi left the Mihbara, so «حديث اليوم» is no longer offered (saved widgets keep working).
                ForEach(WidgetMakerStyle.itemIDs.filter { $0 != "hadith" }, id: \.self) { id in
                    Button { toggle(id) } label: {
                        HStack { Text(title(id)).font(MadarTypography.caption()); Spacer(minLength: 3); if let n = draft.items.firstIndex(of: id) { Text(session.digits(n + 1)).font(MadarTypography.fine()).padding(5).background(theme.accentFill, in: .circle).foregroundStyle(theme.onAccent) } }
                            .padding(10).frame(maxWidth: .infinity, minHeight: 48).background(theme.surface, in: .rect(cornerRadius: 16))
                            .overlay { RoundedRectangle(cornerRadius: 16).stroke(draft.items.contains(id) ? theme.accentFill : theme.line) }
                    }.buttonStyle(.madarPlain).accessibilityAddTraits(draft.items.contains(id) ? .isSelected : []).accessibilityIdentifier("widget-item-" + id).id("widget-item-" + id)
                }
            }
            if !habits.isEmpty { Menu("عادة بعينها") { ForEach(habits) { habit in Button(habit.name) { toggle("habit:" + habit.id.uuidString) } } }.frame(minHeight: 44).accessibilityIdentifier("widget-pick-habit") }
            if !days.isEmpty { Menu("يوم تختاره") { ForEach(days) { day in Button(day.title) { toggle("day:" + day.id) } } }.frame(minHeight: 44) }
        }
    }
    private var selectedOrder: some View {
        MadarCard {
            VStack(alignment: .leading, spacing: 8) {
                Text("بالترتيب الذي تختاره").font(MadarTypography.section())
                ForEach(draft.items, id: \.self) { id in
                    HStack { Text(title(id)).font(MadarTypography.caption()); Spacer(); Button { move(id, -1) } label: { Image(systemName: "chevron.up").frame(width: 44, height: 44) }.disabled(draft.items.first == id); Button { move(id, 1) } label: { Image(systemName: "chevron.down").frame(width: 44, height: 44) }.disabled(draft.items.last == id) }
                }
            }
        }
    }
    private var colors: some View {
        HStack {
            ForEach(["gold", "green", "blue", "clay", "plum", "sepia", "ink"], id: \.self) { color in
                Button { draft.style.color = color } label: {
                    var style = draft.style
                    let _ = style.color = color
                    Circle().fill(WidgetMakerContent.accent(style, dark: colorScheme == .dark)).frame(width: 30, height: 30)
                        .padding(5).overlay { Circle().stroke(draft.style.color == color ? theme.accent : .clear, lineWidth: 2) }.frame(maxWidth: .infinity, minHeight: 44)
                }.buttonStyle(.madarPlain).accessibilityLabel(["gold": "ذهبي", "green": "أخضر", "blue": "أزرق", "clay": "طيني", "plum": "برقوقي", "sepia": "بني", "ink": "حبر"][color] ?? color).accessibilityAddTraits(draft.style.color == color ? .isSelected : []).accessibilityIdentifier("widget-color-" + color)
            }
        }
    }
    private var savedWidgets: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack { Text("ودجاتي").font(MadarTypography.section()); Spacer(); Button("جديدة") { select(.init()) }.frame(minHeight: 44) }
            ScrollView(.horizontal) {
                WidgetMakerGlassGroup {
                HStack(alignment: .top, spacing: 10) {
                    ForEach(saved) { item in
                        savedCard(item)
                    }
                }.padding(.vertical, 2)
                }
            }.scrollIndicators(.hidden)
        }
    }
    private func savedCard(_ item: WidgetMakerDraft) -> some View {
        let cardTheme = WidgetMakerContent.theme(item.style, dark: colorScheme == .dark)
        return VStack(spacing: 0) {
            Button { select(item) } label: {
                VStack(alignment: .leading, spacing: 10) {
                    Text(surfaceTitle(item.style.surface) + "، " + familyTitle(item.familyID))
                        .font(MadarTypography.fine()).foregroundStyle(cardTheme.secondaryInk)
                        .lineLimit(2).padding(.trailing, item.id == baseline?.id ? 22 : 0)
                    Spacer(minLength: 0)
                    Text(item.name).font(MadarTypography.section()).lineLimit(2)
                    Text(item.items.map(title).joined(separator: "، "))
                        .font(MadarTypography.fine()).foregroundStyle(cardTheme.secondaryInk).lineLimit(2)
                }
                .padding(14).frame(width: 164, height: 142, alignment: .leading)
                .foregroundStyle(cardTheme.ink)
                .clipShape(.rect(cornerRadius: 22))
                .modifier(WidgetMakerAppSurface(style: item.style, dark: colorScheme == .dark, interactive: true))
                .overlay(alignment: .topTrailing) {
                    if item.id == baseline?.id {
                        Image(systemName: "checkmark.circle.fill")
                            .foregroundStyle(WidgetMakerContent.accent(item.style, dark: colorScheme == .dark))
                            .padding(8).accessibilityHidden(true)
                    }
                }
                .overlay { RoundedRectangle(cornerRadius: 22).stroke(item.id == baseline?.id ? theme.accentFill : theme.line, lineWidth: 1) }
            }.buttonStyle(.madarPlain).accessibilityIdentifier("widget-saved-" + item.id.uuidString)
            Button { deleting = item } label: { Label("احذف", systemImage: "trash").font(MadarTypography.fine()).frame(minHeight: 44) }
                .accessibilityLabel("احذف " + item.name).accessibilityIdentifier("widget-delete-" + item.id.uuidString)
        }
    }
    private func surfaceTitle(_ surface: String) -> String {
        ["home": "الرئيسية", "lock": "القفل", "lobby": "البهو", "standby": "الاستعداد"][surface] ?? "الرئيسية"
    }
    private func familyTitle(_ family: String) -> String {
        ["small": "صغيرة", "medium": "متوسطة", "large": "كبيرة", "extraLargePortrait": "ضخمة", "accessoryCircular": "دائرية", "accessoryRectangular": "مستطيلة", "accessoryInline": "سطر"][family] ?? "متوسطة"
    }
    private var saveBar: some View {
        VStack(spacing: 6) {
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_WIDGET_MAKER_ROUTE_HARNESS"] == "1" {
                Button("اختبر رابط قالب المال") { session.open(URL(string: "madar://bahw/widget-maker?template=mal")!) }
                    .accessibilityIdentifier("ui-test-widget-maker-template-money")
            }
#endif
            if !status.isEmpty { Text(status).font(MadarTypography.fine()).accessibilityIdentifier("widget-maker-status") }
            HStack(spacing: 8) {
                TextField("سَمِّ ودجتك…", text: $draft.name).focused($nameFocused).submitLabel(.done).onSubmit { nameFocused = false }.font(MadarTypography.body()).padding(12).background(theme.surface, in: .capsule).disabled(busy).accessibilityIdentifier("widget-maker-name")
                Button { save() } label: { if busy { ProgressView() } else { Text("احفظها").font(MadarTypography.section()) } }
                    .frame(minWidth: 88, minHeight: 48).background(theme.accentFill, in: .capsule).foregroundStyle(theme.onAccent)
                    .disabled(busy || draft.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || draft.name.count > 80 || draft.items.isEmpty).accessibilityIdentifier("widget-maker-save")
            }
        }.padding(12).background(theme.background)
    }
    private func choices(_ title: String, selection: Binding<String>, options: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 8) { Text(title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Picker(title, selection: selection) { ForEach(options, id: \.0) { option in Text(option.1).tag(option.0) } }.pickerStyle(.segmented) }
    }
    private func behavior(_ title: String, detail: String, value: Binding<Bool>, id: String) -> some View {
        Toggle(isOn: value) { VStack(alignment: .leading, spacing: 4) { Text(title).font(MadarTypography.body()); Text(detail).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) } }.frame(minHeight: 52).accessibilityIdentifier("widget-behavior-" + id)
    }
    private func toggle(_ id: String) { if draft.items.contains(id) { draft.items.removeAll { $0 == id } } else if draft.items.count < 20 { draft.items.append(id) } }
    private func move(_ id: String, _ delta: Int) { if let i = draft.items.firstIndex(of: id), draft.items.indices.contains(i + delta) { draft.items.swapAt(i, i + delta) } }
    private func title(_ id: String) -> String {
        if id.hasPrefix("habit:"), let habit = habits.first(where: { "habit:" + $0.id.uuidString == id }) { return habit.name }
        if id.hasPrefix("day:"), let day = days.first(where: { "day:" + $0.id == id }) { return day.title }
        return ["prayerNext": "الصلاة القادمة", "habitsToday": "عادات اليوم", "moneyNow": "لك الآن", "ramadan": "رمضان", "year": "نسبة السنة", "upcoming": "أقرب يوم", "quranCoverage": "في صدرك", "quranReview": "من القرآن اليوم", "book": "الكتاب", "hadith": "حديث اليوم", "diaryLine": "سطر اليوم", "hijriClock": "الساعة والتاريخان"][id] ?? "عنصر غير متاح"
    }
    private func applySelection(_ item: WidgetMakerDraft) {
        draft = item
        beforeReset = nil
        baselineIsPersisted = saved.contains { $0.id == item.id }
        baseline = baselineIsPersisted ? item : nil
        status = ""
        selectionRevision += 1
    }
    private func select(_ item: WidgetMakerDraft) {
        if dirty { pendingSelection = item; discard = true } else { applySelection(item) }
    }
    private func reload() {
        do {
            saved = try session.widgetMakerDrafts()
            if baselineIsPersisted, baseline != nil, !dirty {
                if let current = saved.first(where: { $0.id == draft.id }) { draft = current; baseline = current }
                else { draft = .init(); baseline = nil; baselineIsPersisted = false; status = "" }
            }
        } catch { session.errorMessage = madarUserMessage(error) }
    }
    private func applyInitialRoom(_ room: String?) {
        guard let room else { return }
        let item: String? = switch room {
        case "salah": "prayerNext"
        case "habits": "habitsToday"
        case "quran": "quranCoverage"
        case "notes": "diaryLine"
        case "mal": "moneyNow"
        case "mihbara": "book"
        case "year": "year"
        case "bahw": "upcoming"
        default: nil
        }
        guard let item, WidgetMakerStyle.itemIDs.contains(item) else { return }
        // A saved widget is never overwritten by a template link: the routed widget starts as a new one.
        var routed = saved.contains { $0.id == draft.id } ? WidgetMakerDraft() : draft
        routed.items = [item]
        if dirty { select(routed) }
        else { draft = routed; baseline = routed; baselineIsPersisted = false; beforeReset = nil; status = ""; selectionRevision += 1 }
    }
    private func save() {
        guard !busy else { return }
        busy = true; let value = draft
        Task {
            defer { busy = false; applyPendingTemplateIfNeeded() }
            do {
                try await session.saveWidget(value)
                baseline = value; baselineIsPersisted = true; status = "حُفظت «" + value.name + "»"; reload()
            } catch { session.errorMessage = madarUserMessage(error) }
        }
    }
    private func remove(_ item: WidgetMakerDraft) {
        guard !busy else { return }
        deleting = nil
        busy = true
        Task {
            defer { busy = false; applyPendingTemplateIfNeeded() }
            do {
                try await session.executeDiaryCommand("widget.delete", payload: ["id": .string(item.id.uuidString)])
                if draft.id == item.id { draft = .init(); baseline = nil; baselineIsPersisted = false }
                reload()
            } catch { session.errorMessage = madarUserMessage(error) }
        }
    }
    private func applyPendingTemplateIfNeeded() {
        guard let room = pendingTemplateRoom else { return }
        pendingTemplateRoom = nil
        applyInitialRoom(room)
    }
}
