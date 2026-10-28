import SwiftUI
import MadarDesign

struct QuranSessionLogView: View {
    let service: AppQuranService
    let close: () -> Void
    @Binding var selection: QuranLogTab
    @Environment(\.roomTheme) private var theme
    @State private var value: QuranUISessionLog?
    @State private var filter = "all"
    @State private var expanded: UUID?
    @State private var page = 1
    @State private var deleting: UUID?
    @State private var busy = false
    @State private var error: String?
    private var app: AppSession { service.app }
    private var records: [QuranUILogRecord] { value?.records.filter { filter == "all" || (filter == "review" ? [.review,.free,.qiyam].contains($0.kind) : $0.kind.rawValue == filter) } ?? [] }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                QuranScreenHeader(title: "السجلّ", close: close); QuranLogTabs(selection: $selection)
                if let value {
                    QuranPaperCard {
                        VStack(alignment: .leading, spacing: 12) {
                            Text("في صدرك").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                            Text(value.coverage).font(quranSerif(29)).accessibilityIdentifier("quran-history-coverage")
                            ProgressView(value: value.fraction).tint(theme.color("memorized"))
                            if let gap = value.gap { Text(gap).font(quranFont(13)).foregroundStyle(theme.color("dueText")) }
                        }
                    }
                    HStack(spacing: 4) {
                        ForEach([("all","الكل"),("hifz","حفظ"),("review","مراجعة"),("drill","مذاكرة")], id: \.0) { key, title in
                            Button { filter = key } label: { Text(title).font(quranFont(12, bold: filter == key)).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(filter == key ? theme.onAccent : theme.ink).background(filter == key ? theme.accent : theme.surface, in: Capsule()) }.buttonStyle(.plain).accessibilityIdentifier("quran-history-filter-" + key)
                        }
                    }
                    if records.isEmpty {
                        // Audit 28 Oct: an empty filter is not an empty log.
                        if filter != "all" {
                            VStack(alignment: .leading, spacing: 8) {
                                Text("لا جلسات من هذا النوع بعد").font(quranFont(15))
                                Button("اعرض الكل") { filter = "all" }.font(quranFont(14, bold: true)).frame(minHeight: 44).accessibilityIdentifier("quran-log-show-all")
                            }.padding(20)
                        } else { Text("لا جلسات مسجّلة بعد؛ تظهر هنا بعد أول حفظ أو مراجعة").font(quranFont(15)).padding(20) }
                    }
                    let list = records
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, record in
                        VStack(alignment: .leading, spacing: 8) {
                            // One date per day (owner trial: eight reviews on one day repeated the same date eight times).
                            if index == 0 || list[index - 1].day != record.day {
                                MadarDateLabel(record.day).font(quranFont(12, bold: true)).foregroundStyle(theme.secondaryInk)
                            }
                            QuranPaperCard {
                                VStack(alignment: .leading, spacing: 12) {
                                    Button {
                                        expanded = expanded == record.id ? nil : record.id
                                        page = record.grades.first?.page ?? 1
                                    } label: {
                                        HStack {
                                            Rectangle().fill(theme.color(record.kind == .hifz ? "hifz" : "review")).frame(width: 3)
                                            VStack(alignment: .leading, spacing: 5) { Text(record.title).font(quranFont(16, bold: true)); Text(record.detail).font(quranFont(12)).foregroundStyle(theme.secondaryInk) }
                                            Spacer(); Image(systemName: expanded == record.id ? "chevron.up" : "chevron.down").font(.system(size: 12))
                                        }.frame(minHeight: 50).contentShape(Rectangle())
                                    }.buttonStyle(.plain).accessibilityIdentifier("quran-history-record-" + record.id.uuidString)
                                    if expanded == record.id {
                                        if !record.grades.isEmpty {
                                            Picker("الوجه", selection: $page) { ForEach(record.grades) { grade in Text(grade.title).tag(grade.page) } }.font(quranFont(14)).tint(theme.ink)
                                            HStack(spacing: 4) {
                                                ForEach(QuranUIGrade.allCases) { grade in
                                                    let current = record.grades.first { $0.page == page }?.grade == grade
                                                    let palette: (ink: String, tint: String) = switch grade {
                                                    case .mastered: ("reviewText", "reviewTint")
                                                    case .good: ("hifzText", "hifzTint")
                                                    case .needs: ("dueText", "dueTint")
                                                    }
                                                    Button { run { try await service.perform(.editSessionGrade(sessionID: record.id, page: page, grade: grade)); load() } } label: {
                                                        Text(grade.title).font(quranFont(12, bold: current))
                                                            .foregroundStyle(theme.color(palette.ink))
                                                            .frame(maxWidth: .infinity, minHeight: 44)
                                                            .background(current ? theme.color(palette.tint) : theme.surface, in: Capsule())
                                                            .overlay { Capsule().stroke(theme.color(palette.ink).opacity(current ? 1 : 0.28), lineWidth: current ? 1.5 : 0.8) }
                                                    }.buttonStyle(.plain).accessibilityAddTraits(current ? .isSelected : [])
                                                        .accessibilityIdentifier("quran-history-grade-" + grade.id)
                                                }
                                            }
                                            Text("الموعد التالي: " + (value.nextDue[page] ?? "—")).font(quranFont(12)).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("quran-history-due")
                                        }
                                        if let warning = record.warning { Text(warning).font(quranFont(13)).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("quran-history-warning") }
                                        Button("احذف الجلسة", role: .destructive) { deleting = record.id }.font(quranFont(13, bold: true)).foregroundStyle(theme.color("dueText")).frame(minHeight: 44).accessibilityIdentifier("quran-history-delete")
                                    }
                                }
                            }
                        }
                    }
                    Text("تعديل التقييم يعيد حساب الموعد. حذف الحفظ قد يعيد موضع الورد إلى فجوة؛ الجلسات الأخرى تبقى.").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                }
                if let error { Text(error).font(quranFont(13)) }
            }.padding(16)
        }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review")).disabled(busy)
            .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: app.undo).accessibilityIdentifier("quran-history-undo") } }
            .task { load() }.onChange(of: app.undoToken?.id) { load() }
            .alert("احذف هذه الجلسة؟", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { id in
                Button("احذف", role: .destructive) { deleting = nil; run { try await service.perform(.deleteSession(id)); expanded = nil; load() } }
                Button("أبقِ الجلسة", role: .cancel) { deleting = nil }
            } message: { _ in Text("ستُزال آثارها من الحفظ والمواعيد والأخطاء. يمكنك التراجع عشر دقائق.") }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("تمّ") { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
    }
    private func load() { do { value = try service.sessionLog() } catch { self.error = quranUserMessage(error) } }
    private func run(_ work: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; Task { defer { busy = false }; do { try await work() } catch { self.error = quranUserMessage(error) } } }
}
