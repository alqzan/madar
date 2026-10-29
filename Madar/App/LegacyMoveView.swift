import SwiftUI
import UniformTypeIdentifiers
import MadarCore
import MadarData
import MadarDesign

/// Item 24 «من مدار القديم»: choose the old app's backup → what each room holds → «انقل» → what moved, with one undo.
/// Nothing is written before «انقل»; a second move adds nothing; what the owner already keeps here is never duplicated.
struct LegacyMoveView: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @State private var choosing = false
    @State private var preview: LegacyMovePreview?
    @State private var moving: String?
    @State private var movementProgress: (reviewed: Int, total: Int)?
    @State private var receipt: LegacyMoveReceipt?
    @State private var last: LegacyMoveReceipt?
    @State private var undone: LegacyMoveUndo?
    @State private var scroll = ScrollPosition(edge: .top)
    @State private var confirmUndo = false
    @State private var failure: String?
    @State private var diaryOpen = false
    private var service: AppLegacyMoveService { .init(app: app) }
    private var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("من مدار القديم").font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                Text("اختر النسخة الاحتياطية التي صدّرتها من مدار القديم. ترى ما في كل غرفة قبل أن يُكتب شيء، وما عندك هنا يبقى كما هو ولا يتكرر.")
                    .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).lineSpacing(6).fixedSize(horizontal: false, vertical: true)
                if moving != nil { EmptyView() }
                else if let undone { undoneCard(undone) }
                else if let receipt { resultCards(receipt) }
                else if let preview { previewCards(preview) }
                else {
                    picker
                    if let last { lastMoveCard(last) }
                }
                if let failure {
                    Text(failure).font(MadarTypography.caption()).padding(14).frame(maxWidth: .infinity, alignment: .leading)
                        .background(theme.surface, in: .rect(cornerRadius: 14)).accessibilityIdentifier("legacy-move-failure")
                }
                diaryCard
            }
            .padding(.horizontal, 21).padding(.top, 4).padding(.bottom, 120).frame(maxWidth: 620).frame(maxWidth: .infinity)
        }
        .scrollPosition($scroll)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if moving == nil, receipt == nil, undone == nil, let preview {
                Button("انقل إلى مدار") { commit(preview) }
                    .buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("legacy-move-commit")
                    .padding(.horizontal, 21).padding(.vertical, 12)
                    .frame(maxWidth: 620).frame(maxWidth: .infinity).background(theme.background)
            }
        }
        .safeAreaInset(edge: .top, spacing: 0) {
            if let moving { progressCard(moving).padding(.horizontal, 21).padding(.vertical, 8).background(theme.background) }
        }
        .background(theme.background).foregroundStyle(theme.ink).navigationBarTitleDisplayMode(.inline)
        .navigationBarBackButtonHidden(moving != nil)
        .toolbarVisibility(.hidden, for: .tabBar).hidesRoomAccessory(app, id: "legacy-move")
        .onChange(of: preview?.id) { scroll.scrollTo(edge: .top) }
        .onChange(of: receipt) { scroll.scrollTo(edge: .top) }
        .fileImporter(isPresented: $choosing, allowedContentTypes: [.json, .data]) { result in
            switch result { case .success(let url): read(url); case .failure: failure = "لم يُفتح الملف. جرّب اختياره مرة أخرى." }
        }
        .confirmationDialog("ترجع بياناتك كما كانت قبل النقل؟", isPresented: $confirmUndo, titleVisibility: .visible) {
            Button("تراجع عن النقل", role: .destructive, action: undo).accessibilityIdentifier("legacy-move-undo-confirm")
        } message: { Text("يُزال ما نُقل، وما عدّلته بعد النقل يبقى كما هو.") }
        .fullScreenCover(isPresented: $diaryOpen) { DiaryDayOneImportView(app: app).environment(\.roomTheme, theme) }
        .onAppear { last = service.lastMove() }
    }

    // MARK: states
    private var picker: some View {
        Button(action: choose) {
            HStack(spacing: 14) {
                Image(systemName: "doc.badge.arrow.up").font(.system(size: 20)).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text("اختر نسخة مدار القديم").font(MadarTypography.section())
                    Text("madar-backup.json").font(MadarTypography.caption()).foregroundStyle(theme.color("ink3Text")).environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(theme.surface.opacity(0.55), in: .rect(cornerRadius: 3))
            .overlay { RoundedRectangle(cornerRadius: 3).stroke(theme.color("ink3Text").opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .contentShape(.rect)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("legacy-move-choose")
    }

    private func previewCards(_ p: LegacyMovePreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                HStack(spacing: 10) {
                    Image(systemName: "doc.text"); Text(p.fileName).font(MadarTypography.caption()).lineLimit(1).truncationMode(.middle).environment(\.layoutDirection, .leftToRight)
                    Spacer(minLength: 0)
                }.foregroundStyle(theme.secondaryInk)
                ForEach(p.rooms) { room in
                    Divider().overlay(theme.line)
                    roomRow(room.title, room.symbol, room.isEmpty ? ["لا شيء منها في الملف"] : room.lines, muted: room.isEmpty)
                        .accessibilityIdentifier("legacy-move-room-" + room.id)
                }
            }
            Text("كل غرفة تُنقل وحدها. الصلاة المسجّلة هنا في يومها، والعادة بالاسم نفسه، والحساب برقمه، تبقى كما هي وتأخذ تاريخها القديم معها. الرسائل البنكية تمرّ بالمراجعة كأنها وصلت الآن.")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
            Button("اختر ملفًا آخر") { preview = nil; choose() }.frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("legacy-move-other")
        }
    }

    private func progressCard(_ room: String) -> some View {
        card {
            if let movementProgress, movementProgress.total > 0, !room.isEmpty {
                Text("ينقل " + room + "…").font(MadarTypography.body())
                ProgressView(value: Double(movementProgress.reviewed), total: Double(movementProgress.total))
                    .tint(theme.color("accentText"))
                Text("الحركات المفحوصة: " + digits.string(movementProgress.reviewed) + " من " + digits.string(movementProgress.total))
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            } else {
                HStack(spacing: 12) { ProgressView(); Text(room.isEmpty ? "يرجع بياناتك كما كانت…" : "ينقل " + room + "…").font(MadarTypography.body()) }
            }
            Text("ابقَ في مدار حتى يكتمل النقل.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
        }.accessibilityElement(children: .combine).accessibilityIdentifier("legacy-move-progress")
    }

    private func resultCards(_ r: LegacyMoveReceipt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                Text(r.outcomes.contains { $0.failed != nil } ? "انتقل ما أمكن؛ بعض البيانات لم تُنقل." : r.added == 0 ? "كل ما في الملف عندك من قبل؛ لم يتكرر شيء." : "انتقلت غرفك إلى مدار.")
                    .font(MadarTypography.section()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("legacy-move-result")
                ForEach(r.outcomes) { o in
                    Divider().overlay(theme.line)
                    roomRow(o.title, symbol(o.id), outcomeLines(o), muted: o.added == 0 && o.failed == nil)
                        .accessibilityIdentifier("legacy-move-outcome-" + o.id)
                    if o.id == "money", o.waiting > 0, o.failed == nil {
                        Button { app.moneyOpensMessages = true; app.moneyOpen = true } label: {
                            Label("راجعها الآن", systemImage: "tray.full").font(MadarTypography.body()).frame(maxWidth: .infinity, minHeight: 44)
                        }.buttonStyle(.bordered).tint(theme.color("accentText")).accessibilityIdentifier("legacy-move-review-money")
                    }
                }
            }
            HStack(spacing: 12) {
                Button("تراجع عن النقل") { confirmUndo = true }.frame(minHeight: 44).disabled(r.added == 0 && service.lastMove() == nil).accessibilityIdentifier("legacy-move-undo")
                Spacer(minLength: 0)
                Button("انقل الملف مرة أخرى") { receipt = nil }.frame(minHeight: 44).accessibilityIdentifier("legacy-move-again")
            }
        }
    }

    private func lastMoveCard(_ r: LegacyMoveReceipt) -> some View {
        card {
            Text("آخر نقل").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Text(when(r.at)).font(MadarTypography.body())
            Text(r.added == 0 ? "لم يضف شيئًا" : "أضاف " + service.phrase(r.outcomes.reduce(into: [:]) { $0.merge($1.parts, uniquingKeysWith: +) })).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Button("تراجع عن هذا النقل") { confirmUndo = true }.frame(minHeight: 44).accessibilityIdentifier("legacy-move-undo-last")
        }.accessibilityElement(children: .contain).accessibilityIdentifier("legacy-move-last")
    }

    private func undoneCard(_ result: LegacyMoveUndo) -> some View {
        card {
            Text(result.isPartial ? (result.plan.isEmpty ? "أبقينا بياناتك كما هي لحمايتها." : "تراجعت عن التغييرات التي أمكن التحقق منها.") : "رجعت بياناتك كما كانت قبل النقل.").font(MadarTypography.section()).accessibilityIdentifier("legacy-move-undone")
            if result.isPartial {
                Text("قد يبقى جزء من النقل السابق: سجلّه غير مكتمل أو من إصدار أقدم. أبقينا البيانات غير الموثّقة كما هي لحمايتها.")
                    .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier("legacy-move-partial-undo")
            }
            if result.plan.keptChanged > 0 {
                Text("وما عدّلته بعد النقل بقي كما هو (" + digits.string(result.plan.keptChanged) + ").").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            Button("ابدأ من جديد") { undone = nil; preview = nil; receipt = nil; last = service.lastMove() }.frame(minHeight: 44).accessibilityIdentifier("legacy-move-restart")
        }
    }

    /// The old app exported the diary as a Day One file; it moves through the diary's own import.
    private var diaryCard: some View {
        Button { diaryOpen = true } label: {
            HStack(spacing: 12) {
                Image(systemName: "book.closed").frame(width: 28)
                VStack(alignment: .leading, spacing: 3) {
                    Text("مذكراتك").font(MadarTypography.section())
                    Text("صدّرها مدار القديم ملفًا بصيغة داي ون؛ تنتقل من هنا بأيامها وصورها.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.backward").font(.caption).foregroundStyle(theme.secondaryInk)
            }
            .padding(16).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 14)).contentShape(.rect)
        }.buttonStyle(.madarPlain).disabled(moving != nil).accessibilityIdentifier("legacy-move-diary")
    }

    // MARK: pieces
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 14))
    }
    private func roomRow(_ title: String, _ symbol: String, _ lines: [String], muted: Bool) -> some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: symbol).frame(width: 26).foregroundStyle(muted ? theme.secondaryInk : theme.color("accentText"))
            VStack(alignment: .leading, spacing: 3) {
                Text(title).font(MadarTypography.body().weight(.semibold))
                ForEach(lines, id: \.self) { Text($0).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).fixedSize(horizontal: false, vertical: true) }
            }
            Spacer(minLength: 0)
        }.frame(minHeight: 44).accessibilityElement(children: .combine)
    }
    private func outcomeLines(_ o: LegacyMoveOutcome) -> [String] {
        if o.failed != nil {
            return (o.added > 0 ? ["وصل " + service.phrase(o.parts)] : []) + ["لم يكتمل نقلها؛ سجلاتك الحالية محفوظة، وبقيت الغرف الأخرى. جرّب النقل مرة أخرى."]
        }
        var lines: [String] = [o.added == 0 ? "لا جديد؛ كله عندك من قبل" : "وصل " + service.phrase(o.parts)]
        if o.keptNative > 0 { lines.append("وما كان عندك هنا بقي كما هو (" + digits.string(o.keptNative) + ")") }
        if o.waiting > 0 { lines.append(service.counted(o.waiting, ["رسالة تنتظر", "رسالتان تنتظران", "رسائل تنتظر", "رسالة تنتظر"]) + " مراجعتك في المال") }
        return lines
    }
    private func symbol(_ id: String) -> String { ["prayer": "moon.stars", "quran": "book", "habits": "circle.dashed", "personal": "envelope", "money": "banknote"][id] ?? "square" }
    private func when(_ at: Date) -> String {
        let labels = app.dateLabels(GregorianDay.containing(at, in: app.activePlace.timeZone))
        return labels.primary + (labels.secondary.isEmpty ? "" : "، " + labels.secondary)
    }

    // MARK: actions
    private func choose() {
        failure = nil
        #if DEBUG
        // UI tests hand the old backup straight in; the system picker is never driven.
        let env = ProcessInfo.processInfo.environment
        if env["MADAR_UI_STORE_ID"] != nil, let path = env["MADAR_UI_LEGACY_BACKUP"], !path.isEmpty { read(URL(fileURLWithPath: path)); return }
        #endif
        choosing = true
    }
    private func read(_ url: URL) {
        do { preview = try service.open(url); receipt = nil; undone = nil }
        catch { failure = (error as? LocalizedError)?.errorDescription ?? "لم يُقرأ الملف. تأكد أنه نسخة مدار القديم كما صدّرها." }
    }
    private func commit(_ p: LegacyMovePreview) {
        failure = nil; movementProgress = nil; moving = p.rooms.first { !$0.isEmpty }?.title ?? ""
        Task { @MainActor in
            defer { moving = nil }
            do {
                receipt = try await service.commit(p, progress: { moving = $0 }, movementProgress: { movementProgress = ($0, $1) })
                preview = nil; last = service.lastMove()
            }
            catch { failure = "لم يكتمل النقل. " + madarUserDetail(error) }
        }
    }
    private func undo() {
        failure = nil; movementProgress = nil; moving = ""
        Task { @MainActor in
            defer { moving = nil }
            do { undone = try await service.undo(); receipt = nil; last = nil }
            catch { failure = "لم يكتمل التراجع. " + madarUserDetail(error) }
        }
    }
}
