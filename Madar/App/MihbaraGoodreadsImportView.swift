import SwiftUI
import SwiftData
import MadarCore
import MadarDesign
import MadarData
import MadarCommands

struct MihbaraGoodreadsImportView: View {
    let app: AppSession
    let stage: GoodreadsCSVStage
    @Binding var selectedMatches: [String: UUID]
    @Binding var cutoffYear: Int
    @Binding var missingDateShelf: String
    let onImported: () -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var entries: [GoodreadsCSVEntry] = []
    @State private var candidates: [GoodreadsBookCandidate] = []
    @State private var preview: GoodreadsPreview?
    @State private var loading = true
    @State private var saving = false
    @State private var failure: String?

    private var digits: MadarNumberFormatter { .init(style: app.string("core.numerals") == "western" ? .western : .hindi) }
    private var targetsAreUnique: Bool {
        guard let preview else { return false }
        let targets = preview.rows.compactMap(\.targetBookID)
        return targets.count == Set(targets).count
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
#if DEBUG
                if ProcessInfo.processInfo.environment["MADAR_UI_MIHBARA_ROOT_ROUTE_HARNESS"] == "1" {
                    Button("اختبر الجذر") { app.open(URL(string: "madar://mihbara")!) }
                        .accessibilityIdentifier("mihbara-goodreads-root-route")
                }
#endif
                VStack(alignment: .leading, spacing: 5) {
                    HStack {
                        Button {
                            dismiss()
                        } label: {
                            Label("رجوع", systemImage: "chevron.right")
                                .font(MadarTypography.caption())
                                .frame(minHeight: 44)
                        }
                        .disabled(saving)
                        .accessibilityIdentifier("mihbara-goodreads-back")
                        Spacer(minLength: 8)
                    }
                    Text("معاينة مكتبة Goodreads").font(MadarTypography.title())
                    Text(stage.fileName).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                }
                if loading { ProgressView("أفحص الكتب…").tint(theme.ink).frame(maxWidth: .infinity, minHeight: 150) }
                else if let preview {
                    if let failure {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("تعذّرت الإضافة").font(MadarTypography.cardTitle())
                            Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                                .accessibilityIdentifier("mihbara-goodreads-import-error")
                        }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                            .background(theme.surface, in: .rect(cornerRadius: 18))
                    }
                    Text("أراجع الملف قبل إضافته. الكتب المطابقة لا تُدمج إلا بعد اختيارك.")
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    HStack(spacing: 9) {
                        GoodreadsCountCard(title: "كتب جديدة", value: digits.string(preview.createCount), theme: theme)
                        GoodreadsCountCard(title: "تحديثات", value: digits.string(preview.updateCount), theme: theme)
                        GoodreadsCountCard(title: "تحتاج اختيارك", value: digits.string(preview.suggestionCount), theme: theme)
                    }
                    if entries.contains(where: { $0.exclusiveShelf == "read" && $0.dateRead != nil }) { cutoffCard }
                    if entries.contains(where: { $0.exclusiveShelf == "read" && $0.dateRead == nil }) { missingDateCard }
                    VStack(alignment: .leading, spacing: 10) {
                        Text("الكتب في الملف").font(MadarTypography.section())
                        LazyVStack(alignment: .leading, spacing: 10) {
                            ForEach(preview.rows, id: \.entry.rowKey) { row in goodreadsRow(row) }
                        }
                    }
                } else if let failure {
                    VStack(alignment: .leading, spacing: 10) {
                        Text("تعذّرت المعاينة").font(MadarTypography.cardTitle())
                        Text(failure).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                        Button("العودة لاختيار الملف") { dismiss() }.buttonStyle(MadarPrimaryButton())
                    }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 18))
                }
            }.padding(18).frame(maxWidth: 680).frame(maxWidth: .infinity)
        }
        .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink)
        .environment(\.layoutDirection, .rightToLeft)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .safeAreaInset(edge: .bottom) {
            if !loading && preview != nil {
                Button(action: importBooks) {
                    HStack(spacing: 9) {
                        if saving { ProgressView().tint(theme.background) }
                        Text(saving ? "يُضاف إلى المحبرة…" : importButtonTitle)
                    }.font(MadarTypography.body()).foregroundStyle(theme.background)
                        .frame(maxWidth: .infinity).frame(height: 52).background(theme.ink, in: .rect(cornerRadius: 14))
                }
                .buttonStyle(.madarPlain).disabled(saving || !targetsAreUnique || preview == nil)
                .padding(.horizontal, 18).padding(.top, 10).padding(.bottom, 12).background(theme.background)
                .accessibilityIdentifier("mihbara-goodreads-import")
            }
        }
        .task(id: stage.id) { load() }
        .onChange(of: cutoffYear) { _, _ in rebuildPreview() }
        .onChange(of: missingDateShelf) { _, _ in rebuildPreview() }
        .onChange(of: selectedMatches) { _, _ in rebuildPreview() }
    }

    private var cutoffCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("رفّ الكتب المقروءة").font(MadarTypography.cardTitle())
            Text("ما قُرئ قبل السنة المحددة يذهب إلى «قديمًا»، وما قُرئ في السنة المحددة أو بعدها إلى «أنهيتها».")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            HStack(spacing: 16) {
                Button { cutoffYear = max(1900, cutoffYear - 1) } label: { Image(systemName: "minus.circle.fill").font(.title2) }
                    .accessibilityLabel("سنة أقدم")
                MadarDateLabel(app.yearLabels(cutoffYear), primaryFont: MadarTypography.title(), secondaryFont: MadarTypography.fine())
                    .accessibilityElement(children: .combine).accessibilityLabel(app.yearLabels(cutoffYear).combined)
                    .accessibilityIdentifier("mihbara-goodreads-cutoff-year")
                Button { cutoffYear = min(2100, cutoffYear + 1) } label: { Image(systemName: "plus.circle.fill").font(.title2) }
                    .accessibilityLabel("سنة أحدث")
                Spacer(minLength: 0)
            }.foregroundStyle(theme.color("accentText"))
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 16))
    }

    private var missingDateCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("كتاب مقروء بلا تاريخ قراءة").font(MadarTypography.cardTitle())
            Text("بعض الكتب بلا تاريخ في الملف؛ اختر الرف الذي تذهب إليه.")
                .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            HStack(spacing: 8) { missingDateChoice("قديمًا", value: "old"); missingDateChoice("أنهيتها", value: "finished") }
        }.padding(15).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 16))
    }

    private func missingDateChoice(_ title: String, value: String) -> some View {
        let selected = missingDateShelf == value
        return Button { missingDateShelf = value } label: {
            Text(title).font(MadarTypography.caption()).frame(maxWidth: .infinity, minHeight: 42)
                .foregroundStyle(selected ? theme.background : theme.ink)
                .background(selected ? theme.ink : theme.background, in: .rect(cornerRadius: 11))
                .overlay { RoundedRectangle(cornerRadius: 11).stroke(theme.line, lineWidth: selected ? 0 : 1) }
        }.buttonStyle(.madarPlain).accessibilityIdentifier("mihbara-goodreads-missing-\(value)")
    }

    @ViewBuilder private func goodreadsRow(_ row: GoodreadsPreviewRow) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(row.entry.title).font(MadarTypography.cardTitle()).lineLimit(3)
                    Text(row.entry.author.isEmpty ? "المؤلف غير مذكور" : row.entry.author)
                        .font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).lineLimit(2)
                }
                Spacer(minLength: 0)
                Text(shelfName(row.targetShelf)).font(MadarTypography.fine()).padding(.horizontal, 9).padding(.vertical, 6)
                    .background(theme.background, in: .capsule)
            }
            HStack(spacing: 8) {
                if let rating = row.entry.rating { Text("التقييم \(digits.string(rating))/٥") }
                Text(row.entry.readCount == 0 ? "لم تُقرأ بعد" : "قُرئت " + arabicCount(row.entry.readCount, ["مرة واحدة","مرتين","مرات","مرة"], digits))
                if let pages = row.entry.pages { Text(MihbaraCopy.pages(pages, digits)) }
            }.font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            if let date = row.entry.dateRead {
                MadarDateLabel(app.dateLabels(GregorianDay.containing(date, in: app.activePlace.timeZone)),
                               primaryFont: MadarTypography.fine(), secondaryFont: MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            } else if row.entry.exclusiveShelf == "read" {
                Text(row.entry.dateReadText.isEmpty ? "بلا تاريخ قراءة؛ سيبقى التاريخ فارغًا" : "لم أتعرف على تاريخ القراءة؛ لن أضيف تاريخًا")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
            if let review = row.entry.review, !review.isEmpty {
                Text(review).font(MadarTypography.caption()).lineLimit(3).padding(10).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.background, in: .rect(cornerRadius: 10))
                    .accessibilityIdentifier("mihbara-goodreads-review-\(row.entry.rowKey)")
            }
            if let note = row.entry.privateNote {
                Label("ملاحظة خاصة: " + note, systemImage: "lock.fill").font(MadarTypography.fine())
                    .lineLimit(3).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("mihbara-goodreads-private-note-\(row.entry.rowKey)")
            }
            if !row.suggestions.isEmpty && row.targetBookID == nil {
                Menu {
                    Button("أضفه ككتاب مستقل") { selectedMatches.removeValue(forKey: row.entry.rowKey) }
                    ForEach(row.suggestions, id: \.id) { candidate in
                        Button("حدّث «\(candidate.title)»") { selectedMatches[row.entry.rowKey] = candidate.id }
                            .disabled(selectedMatches.contains(where: { $0.key != row.entry.rowKey && $0.value == candidate.id }))
                    }
                } label: {
                    Label("قد يكون هذا الكتاب موجودًا — اختر المطابقة", systemImage: "arrow.triangle.merge")
                        .font(MadarTypography.fine()).frame(maxWidth: .infinity, minHeight: 40, alignment: .leading)
                        .foregroundStyle(theme.color("accentText"))
                }.accessibilityIdentifier("mihbara-goodreads-match-\(row.entry.rowKey)")
            } else if row.targetBookID != nil {
                Label("سيُحدّث الكتاب الموجود", systemImage: "checkmark.circle")
                    .font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            }
        }.padding(14).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 15))
            .overlay { RoundedRectangle(cornerRadius: 15).stroke(theme.line.opacity(0.7), lineWidth: 1) }
            .accessibilityElement(children: .contain)
            .accessibilityIdentifier("mihbara-goodreads-row-\(row.entry.rowKey)")
    }

    private func shelfName(_ shelf: String) -> String {
        switch shelf { case "reading": "أقرأها"; case "want": "أبي أقرأها"; case "finished": "أنهيتها"; default: "قديمًا" }
    }

    private var importButtonTitle: String {
        let noun = entries.count == 1 ? "كتابًا واحدًا" : entries.count == 2 ? "كتابين" : MihbaraCopy.books(entries.count, digits)
        return "أضف \(noun) إلى المحبرة"
    }

    private func load() {
        loading = true; failure = nil
        do {
            let (data, _) = try GoodreadsCSVFiles.read(id: stage.id, root: app.bookStagingDirectory, expectedHash: stage.sha256)
            entries = try GoodreadsCSV.parse(data)
            let stored = try ModelContext(app.container).fetch(FetchDescriptor<Book>())
            candidates = stored.filter { $0.deletedAt == nil && $0.mergedInto == nil }.map {
                GoodreadsBookCandidate(id: $0.id, title: $0.title, author: $0.author, isbn13: $0.isbn13,
                                       sourceGoodreadsID: $0.sourceGoodreadsID, shelf: $0.shelf)
            }
            rebuildPreview()
        } catch { failure = madarUserMessage(error) }
        loading = false
    }

    private func rebuildPreview() {
        guard !entries.isEmpty else { preview = nil; return }
        preview = GoodreadsCSV.preview(entries: entries, existing: candidates, cutoffYear: cutoffYear,
                                       missingDateShelf: missingDateShelf, selectedMatches: selectedMatches)
    }

    private func importBooks() {
        guard preview != nil, targetsAreUnique else { return }
        failure = nil; saving = true
        Task {
            do {
                let selectedData = try JSONEncoder().encode(selectedMatches)
                let payload: [String: MadarCore.JSONValue] = [
                    "id": .string(UUID().uuidString), "fileID": .string(stage.id.uuidString),
                    "sha256": .string(stage.sha256), "fileName": .string(stage.fileName),
                    "cutoffYear": .number(Double(cutoffYear)), "missingDateShelf": .string(missingDateShelf),
                    "selectedMatchesJSON": .string(String(decoding: selectedData, as: UTF8.self))
                ]
                try await app.executeBookCommand("book.importGoodreads", payload: payload, undoMessage: "أُضيفت كتب Goodreads إلى المحبرة")
                GoodreadsCSVFiles.discard(id: stage.id, root: app.bookStagingDirectory)
                onImported()
            } catch { failure = madarUserMessage(error) }
            saving = false
        }
    }
}

private struct GoodreadsCountCard: View {
    let title: String
    let value: String
    let theme: RoomTheme
    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(value).font(MadarTypography.cardTitle())
            Text(title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(2)
        }.frame(maxWidth: .infinity, minHeight: 58, alignment: .leading).padding(10)
            .background(theme.surface, in: .rect(cornerRadius: 13))
            .overlay { RoundedRectangle(cornerRadius: 13).stroke(theme.line.opacity(0.7), lineWidth: 1) }
    }
}
