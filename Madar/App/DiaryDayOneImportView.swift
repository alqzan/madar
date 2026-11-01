import SwiftUI
import UniformTypeIdentifiers
import MadarCore
import MadarDesign
import MadarCommands

/// notes-app/12-import «من داي ون»: choose the export → preview → «استورد» → result with one undo.
struct DiaryDayOneImportView: View {
    @Bindable var app: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @Environment(\.scenePhase) private var phase
    @State private var choosing = false
    @State private var reading = false
    @State private var draft: DayOneImportDraft?
    @State private var preview: DayOnePreview?
    @State private var choice = DayOneMerge.Choice.automatic
    @State private var importing: (Int, Int)?
    @State private var rootBlockerID = UUID()
    @State private var receipt: DayOneReceipt?
    @State private var undone = false
    @State private var failure: String?
    @State private var openDay: GregorianDay?
    private var service: AppDiaryImportService { .init(app: app) }
    private var diary: AppDiaryService { .init(app: app) }
    private var digits: MadarNumberFormatter { diary.digits }
    private var first: FirstCalendar { FirstCalendar(rawValue: app.string("notes.calendarFirst")) ?? .gregorian }
    private var busy: Bool { reading || importing != nil }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text("من داي ون").font(.custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)).accessibilityAddTraits(.isHeader)
                    Text("صدّر دفترك من داي ون بصيغة JSON، واختر الملف. تُوضع كل صفحة في يومها، وفي مكانها بين الصلوات بحسب وقتها.")
                        .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).lineSpacing(6).fixedSize(horizontal: false, vertical: true).padding(.bottom, 6)
                    if let receipt { result(receipt) }
                    else if undone { undoneCard }
                    else if let draft, let preview { previewCards(draft, preview) }
                    else { picker }
                    if let failure { Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.ink).padding(14).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 14)).accessibilityIdentifier("dayone-failure") }
                }.padding(.horizontal, 21).padding(.top, 4).padding(.bottom, 32)
            }
            .background(theme.background).foregroundStyle(theme.ink).navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button { close() } label: { HStack(spacing: 6) { Image(systemName: "chevron.backward"); Text("رجوع").font(MadarTypography.body()) } }.disabled(importing != nil).accessibilityIdentifier("dayone-close") } }
            .tint(theme.accent).toolbarBackground(theme.background, for: .navigationBar)
            .fileImporter(isPresented: $choosing, allowedContentTypes: [.zip]) { result in
                switch result {
                case .success(let url): read(url)
                case .failure(let error):
                    if DiaryDayOnePickerFailure.isCancellation(error) { failure = nil }
                    else { failure = "لم يُفتح الملف. جرّب اختياره مرة أخرى." }
                }
            }
            .onChange(of: choice) { _, value in
                guard let draft else { return }
                do { preview = try service.preview(draft, choice: value); failure = nil }
                catch { failure = "تعذّرت قراءة المعاينة بهذا الاختيار. جرّب اختيارًا آخر." }
            }
            .onChange(of: phase) { _, value in if value == .background, importing == nil, receipt == nil { reset() } }
            // Mid-import the folder is still being read: no swipe away, and nothing is discarded under it.
            .madarSheetLock(saving: importing != nil)
            // A «madar://notes» link during the import waits: closing the cover would drop its receipt and undo.
            .onChange(of: importing != nil, initial: true) { _, running in app.setDiaryRootDraftBlocker(rootBlockerID, active: running) }
            .onDisappear { app.setDiaryRootDraftBlocker(rootBlockerID, active: false); if importing == nil { service.discard(draft) } }
            .sheet(isPresented: Binding(get: { openDay != nil }, set: { if !$0 { openDay = nil } })) { if let openDay { DiaryDayView(app: app, day: openDay).environment(\.roomTheme, theme).madarSheetErrorAlert(app) } }
        }
    }

    // MARK: canonical first state
    private var picker: some View {
        Button { choose() } label: {
            HStack(spacing: 14) {
                Image(systemName: reading ? "hourglass" : "doc").font(.system(size: 20, weight: .regular)).frame(width: 28)
                VStack(alignment: .leading, spacing: 5) {
                    Text(reading ? "يقرأ الملف…" : "اختر ملف التصدير").font(MadarTypography.section())
                    Text("Journal.zip").font(MadarTypography.caption()).foregroundStyle(theme.color("ink3Text")).environment(\.layoutDirection, .leftToRight)
                }
                Spacer(minLength: 0)
                if reading { ProgressView() }
            }
            .padding(.horizontal, 18).frame(maxWidth: .infinity, minHeight: 70, alignment: .leading)
            .background(theme.surface.opacity(0.55), in: .rect(cornerRadius: 3))
            .overlay { RoundedRectangle(cornerRadius: 3).stroke(theme.color("ink3Text").opacity(0.55), style: StrokeStyle(lineWidth: 1, dash: [4, 3])) }
            .contentShape(.rect)
        }.buttonStyle(.madarPlain).disabled(reading).accessibilityIdentifier("dayone-choose")
    }

    // MARK: preview (N01: counts, days, media, missing, duplicates — nothing written before «استورد»)
    private func previewCards(_ draft: DayOneImportDraft, _ p: DayOnePreview) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                HStack(spacing: 10) { Image(systemName: "doc.zipper"); Text(draft.fileName).font(MadarTypography.caption()).lineLimit(1).truncationMode(.middle).environment(\.layoutDirection, .leftToRight); Spacer(minLength: 0); Text(journalsLabel(draft)).font(MadarTypography.caption()).foregroundStyle(theme.color("ink3Text")) }
                Divider().overlay(theme.line)
                HStack(alignment: .firstTextBaseline, spacing: 26) {
                    metric(p.writes, "المدخلات", id: "dayone-preview-entries")
                    metric(p.days.count, "الأيام", id: "dayone-preview-days")
                    metric(p.mediaFound.values.reduce(0, +), "المرفقات", id: "dayone-preview-media")
                }
                if let from = p.days.first, let to = p.days.last {
                    Divider().overlay(theme.line)
                    HStack(alignment: .top, spacing: 12) {
                        VStack(alignment: .leading, spacing: 4) { Text("من").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")); MadarDateLabel(diary.dateLabels(from, first: first)) }
                        Spacer(minLength: 0)
                        VStack(alignment: .leading, spacing: 4) { Text("إلى").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")); MadarDateLabel(diary.dateLabels(to, first: first)) }
                    }.accessibilityElement(children: .combine).accessibilityIdentifier("dayone-preview-range")
                }
            }
            if !p.mediaFound.isEmpty || !p.mediaMissing.isEmpty || !p.mediaTooLarge.isEmpty {
                card {
                    sectionTitle("المرفقات")
                    ForEach(["photo", "audio", "video", "doc"], id: \.self) { kind in
                        if let n = p.mediaFound[kind] { row(kindName(kind), digits.string(n)) }
                    }
                    if !p.mediaMissing.isEmpty {
                        Divider().overlay(theme.line)
                        Label { Text(missingSentence(p.mediaMissing)).font(MadarTypography.caption()) } icon: { Image(systemName: "exclamationmark.circle") }
                            .foregroundStyle(theme.color("accentText")).accessibilityIdentifier("dayone-preview-missing")
                    }
                    if !p.mediaTooLarge.isEmpty {
                        Divider().overlay(theme.line)
                        Label { Text(missingSentence(p.mediaTooLarge, lead: "أكبر من أن يُنقل: ")).font(MadarTypography.caption()) } icon: { Image(systemName: "externaldrive.badge.exclamationmark") }
                            .foregroundStyle(theme.color("accentText")).accessibilityIdentifier("dayone-preview-too-large")
                    }
                    if !p.mediaMissing.isEmpty || !p.mediaTooLarge.isEmpty {
                        Text("تدخل المدخلة كما هي بعلامة «مرفق ناقص»، ولا يُختلق ملف.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    }
                }
            }
            if !p.tags.isEmpty {
                card {
                    sectionTitle("الوسوم")
                    Text(p.tags.map { "#" + $0 }.joined(separator: "  ")).font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dayone-preview-tags")
                    Text(p.tagBackfill > 0 ? "تُستعاد وسوم المدخلات القديمة من الملف الأصلي، وتبقى كتاباتك ومشاريعك كما هي." : "أول وسم في كل مدخلة يصير فصلًا في «المشاريع» (" + p.projects.joined(separator: "، ") + ")، وتبقى كل الوسوم مع النجمة والطقس في ملف داي ون الأصلي المحفوظ معها.")
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).fixedSize(horizontal: false, vertical: true)
                }
            }
            if p.tagBackfill > 0 {
                card {
                    sectionTitle("استعادة الوسوم المحفوظة")
                    row("مدخلات", digits.string(p.tagBackfill))
                    Text("سيُضاف حقل الوسوم فقط؛ نصوصك ومرفقاتك تبقى كما هي، ويمكنك التراجع عن الاستعادة.")
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).fixedSize(horizontal: false, vertical: true)
                        .accessibilityIdentifier("dayone-preview-tag-backfill")
                }
            }
            let skippedRows = skipped(p)
            if !skippedRows.isEmpty {
                card {
                    sectionTitle("لن يُستورد")
                    ForEach(skippedRows, id: \.0) { row($0.0, digits.string($0.1)) }
                }.accessibilityElement(children: .contain).accessibilityIdentifier("dayone-preview-skipped")
            }
            if p.changed > 0 {
                card {
                    sectionTitle("عُدّلت في داي ون بعد استيرادها")
                    row("مدخلات", digits.string(p.changed))
                    ForEach([(DayOneMerge.Choice.automatic, "حدّثها إن لم أعدّلها هنا، وإلا أبقِ الاثنتين"), (.update, "حدّثها"), (.keepMine, "أبقِ نسختي"), (.keepBoth, "احتفظ بالاثنتين")], id: \.0) { value, title in
                        Button { choice = value } label: { HStack { Text(title).font(MadarTypography.body()); Spacer(); Image(systemName: choice == value ? "checkmark.circle.fill" : "circle").foregroundStyle(choice == value ? theme.accent : theme.line) }.frame(minHeight: 44).contentShape(.rect) }
                            .buttonStyle(.madarPlain).accessibilityIdentifier("dayone-choice-" + value.rawValue)
                    }
                }
            }
            if let importing {
                VStack(spacing: 8) {
                    ProgressView(value: Double(importing.0), total: Double(max(importing.1, 1))).tint(theme.accent)
                    Text("ينقل صفحاتك إلى دفترك…").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                }.padding(.vertical, 8).accessibilityIdentifier("dayone-importing")
            } else if p.writes > 0 {
                Button { commit(draft) } label: { Text("استورد").font(DiaryType.heading).frame(maxWidth: .infinity, minHeight: 56).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("dayone-confirm")
                Text("لا يُكتب شيء في دفترك قبل أن تضغط «استورد»، ويمكنك التراجع بعده.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity)
            } else {
                Text("كل ما في هذا الملف موجود في دفترك من قبل. لا شيء جديد.").font(MadarTypography.body()).accessibilityIdentifier("dayone-nothing-new")
            }
            if importing == nil {
                Button("اختر ملفًا آخر") { reset(); choose() }.font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44).accessibilityIdentifier("dayone-choose-again")
            }
        }
    }

    // MARK: result + one undo
    private func result(_ r: DayOneReceipt) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            card {
                let restoredTags = r.summary.restoredTags ?? 0
                let importedEntries = r.summary.added + r.summary.keptBoth + r.summary.updated
                let title = r.status == "partial" ? "دخلت صفحاتك، وبعض المرفقات ناقصة" : restoredTags > 0 && importedEntries == 0 ? "استُعيدت وسوم يومياتك" : "دخلت صفحاتك إلى دفترك"
                HStack(spacing: 10) { Image(systemName: "checkmark.seal"); Text(title).font(MadarTypography.section()) }.accessibilityIdentifier("dayone-done")
                Divider().overlay(theme.line)
                if importedEntries > 0 || r.summary.days > 0 {
                    HStack(alignment: .firstTextBaseline, spacing: 26) {
                        if r.summary.added + r.summary.keptBoth > 0 { metric(r.summary.added + r.summary.keptBoth, "الجديدة", id: "dayone-done-added") }
                        if r.summary.updated > 0 { metric(r.summary.updated, "المحدَّثة", id: "dayone-done-updated") }
                        if r.summary.days > 0 { metric(r.summary.days, "الأيام", id: "dayone-done-days") }
                    }
                }
                if restoredTags > 0 {
                    Divider().overlay(theme.line)
                    metric(restoredTags, "استُعيدت وسومها", id: "dayone-done-tags-restored")
                }
                if !r.summary.missing.isEmpty {
                    Divider().overlay(theme.line)
                    Text(missingSentence(Dictionary(grouping: r.summary.missing, by: \.kind).mapValues(\.count))).font(MadarTypography.caption()).foregroundStyle(theme.color("accentText"))
                }
                if !r.summary.tooLarge.isEmpty {
                    Text(missingSentence(Dictionary(grouping: r.summary.tooLarge, by: \.kind).mapValues(\.count), lead: "أكبر من أن يُنقل: ")).font(MadarTypography.caption()).foregroundStyle(theme.color("accentText"))
                }
                if let last = r.summary.lastDay.flatMap({ try? GregorianDay($0) }) {
                    Divider().overlay(theme.line)
                    Button { openDay = last } label: {
                        HStack { VStack(alignment: .leading, spacing: 4) { Text("افتح آخر يوم وصل").font(MadarTypography.body()); MadarDateLabel(diary.dateLabels(last, first: first)) }; Spacer(); Image(systemName: "chevron.backward").font(.caption) }.contentShape(.rect)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("dayone-open-day")
                }
            }
            Button { dismiss() } label: { Text("تمّ").font(DiaryType.heading).frame(maxWidth: .infinity, minHeight: 56).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }.buttonStyle(.madarPlain).accessibilityIdentifier("dayone-finish")
            Button { undo(r.batchID) } label: { Label("تراجع عن هذا الاستيراد", systemImage: "arrow.uturn.backward").font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 44) }.accessibilityIdentifier("dayone-undo")
        }
    }
    private var undoneCard: some View {
        card {
            Text("أُلغي الاستيراد. لم يبقَ منه شيء في دفترك، وما كتبته بنفسك لم يُمسّ.").font(MadarTypography.body()).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("dayone-undone")
            Button("اختر ملفًا") { undone = false; choose() }.font(MadarTypography.caption()).frame(minHeight: 44)
        }
    }

    // MARK: pieces
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 12, content: content).padding(16).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 18)).overlay { RoundedRectangle(cornerRadius: 18).stroke(theme.line) }
    }
    private func sectionTitle(_ text: String) -> some View { Text(text).font(MadarTypography.fine()).foregroundStyle(theme.color("ink3Text")) }
    private func metric(_ value: Int, _ label: String, id: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(digits.string(value)).font(.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .title)).monospacedDigit()
            Text(label).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
        }.accessibilityElement(children: .combine).accessibilityIdentifier(id)
    }
    private func row(_ title: String, _ value: String) -> some View {
        HStack { Text(title).font(MadarTypography.body()); Spacer(); Text(value).font(MadarTypography.body()).monospacedDigit() }.frame(minHeight: 30)
    }
    private func kindName(_ kind: String) -> String { ["photo": "صور", "audio": "تسجيلات صوتية", "video": "مقاطع", "doc": "ملفات PDF"][kind] ?? "مرفقات" }
    private func missingSentence(_ missing: [String: Int], lead: String = "لم توجد في الملف: ") -> String {
        let parts = ["photo", "audio", "video", "doc"].compactMap { kind in missing[kind].map { kindName(kind) + ": " + digits.string($0) } }
        return lead + parts.joined(separator: "، ")
    }
    private func journalsLabel(_ draft: DayOneImportDraft) -> String {
        draft.plan.journals.count == 1 ? "دفتر واحد" : "الدفاتر: " + digits.string(draft.plan.journals.count)
    }
    private func skipped(_ p: DayOnePreview) -> [(String, Int)] {
        let count = { (reason: DayOneSkip.Reason) in p.skipped.filter { $0.reason == reason }.count }
        return [("موجودة في دفترك كما هي", p.same), ("أبقيت نسختك منها", p.keepMine), ("حذفتها من دفترك من قبل", p.deletedHere),("مكررة داخل الملف", count(.duplicateInFile)), ("من تصدير مدار نفسه", count(.madarExport)),
                ("فارغة بلا نص ولا مرفق", count(.empty)), ("بلا معرّف أو تاريخ", count(.noIdentity) + count(.noDate))].filter { $0.1 > 0 }
    }

    // MARK: actions
    private func choose() {
        failure = nil
        #if DEBUG
        // UI tests hand the bundled synthetic export straight in; the system picker is never driven.
        let env = ProcessInfo.processInfo.environment
        if env["MADAR_UI_STORE_ID"] != nil, let encoded = env["MADAR_UI_DAYONE_ZIP_B64"], let bytes = Data(base64Encoded: encoded) {
            let url = FileManager.default.temporaryDirectory.appending(path: "Journal.zip")
            if (try? bytes.write(to: url, options: .atomic)) != nil { read(url); return }
        }
        #endif
        choosing = true
    }
    private func read(_ url: URL) {
        reading = true; failure = nil
        Task { @MainActor in
            defer { reading = false }
            do { let opened = try await service.open(url); service.discard(draft); draft = opened; choice = .automatic; preview = try service.preview(opened, choice: .automatic) }
            catch { failure = AppDiaryImportService.message(error) }
        }
    }
    private func commit(_ draft: DayOneImportDraft) {
        importing = (0, max(1, preview?.mediaFound.values.reduce(0, +) ?? 1)); failure = nil
        Task { @MainActor in
            defer { importing = nil }
            do { receipt = try await service.commit(draft, choice: choice) { done, total in importing = (done, total) }; service.discard(draft); self.draft = nil; preview = nil }
            catch { failure = "توقف الاستيراد قبل اكتماله. أعد الاستيراد من الملف نفسه ليُكمل ما بقي دون تكرار." }
        }
    }
    private func undo(_ batch: UUID) {
        Task { @MainActor in
            do { try await service.undo(batch); receipt = nil; undone = true }
            catch { failure = "لم يتم التراجع. أعد المحاولة." }
        }
    }
    private func reset() { service.discard(draft); draft = nil; preview = nil; choice = .automatic }
    private func close() { if importing == nil { reset(); dismiss() } }
}

enum DiaryDayOnePickerFailure {
    static func isCancellation(_ error: Error) -> Bool {
        let value = error as NSError
        return (value.domain == NSCocoaErrorDomain && value.code == CocoaError.userCancelled.rawValue)
            || (value.domain == NSURLErrorDomain && value.code == NSURLErrorCancelled)
    }
}
