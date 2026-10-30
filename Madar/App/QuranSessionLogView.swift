import SwiftUI
import MadarDesign

struct QuranSessionLogView: View {
    let service: AppQuranService
    let close: () -> Void
    @Binding var selection: QuranLogTab
    private let initialSessionID: UUID?
    @Environment(\.roomTheme) private var theme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var value: QuranUISessionLog?
    @State private var filter = "all"
    @State private var expanded: UUID?
    @State private var page = 1
    @State private var deleting: UUID?
    @State private var busy = false
    @State private var error: String?
    @State private var pendingSessionID: UUID?
    @State private var routeUnavailableID: UUID?
#if DEBUG
    @State private var injectedReadFailure = false
#endif
    private var app: AppSession { service.app }
    private var records: [QuranUILogRecord] { value?.records.filter { filter == "all" || (filter == "review" ? [.review,.free,.qiyam].contains($0.kind) : $0.kind.rawValue == filter) } ?? [] }
    init(service: AppQuranService, close: @escaping () -> Void, selection: Binding<QuranLogTab>, initialSessionID: UUID? = nil) {
        self.service = service; self.close = close; self._selection = selection; self.initialSessionID = initialSessionID
        _pendingSessionID = State(initialValue: initialSessionID)
    }
    var body: some View {
        ScrollViewReader { proxy in
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                QuranScreenHeader(title: "السجلّ", close: close); QuranLogTabs(selection: $selection)
                if let value {
                    if let routeUnavailableID {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("هذه الجلسة لم تعد موجودة في السجلّ.").font(quranFont(14)).accessibilityIdentifier("quran-history-route-unavailable")
                            Button("اعرض السجل الكامل") { self.routeUnavailableID = nil; filter = "all" }
                                .font(quranFont(13, bold: true)).frame(minHeight: 44).accessibilityIdentifier("quran-history-route-show-all")
                        }.padding(14).background(theme.surface, in: .rect(cornerRadius: 16))
                    }
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
                            Button { filter = key } label: { Text(title).font(quranFont(12, bold: filter == key)).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(filter == key ? theme.onAccent : theme.ink).background(filter == key ? theme.accent : theme.surface, in: Capsule()) }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-history-filter-" + key)
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
                    // AU-04 (R18-Sijil-Log): one card per day, sessions divided inside it, the day's kinds beside its date.
                    ForEach(dayGroups, id: \.day) { group in
                        VStack(alignment: .leading, spacing: 8) {
                            HStack(alignment: .firstTextBaseline) {
                                HStack(alignment: .firstTextBaseline, spacing: 6) {
                                    if let relative = group.records.first?.relative { Text(relative + "،").font(quranFont(12, bold: true)).foregroundStyle(theme.ink) }
                                    MadarDateLabel(group.day).font(quranFont(12, bold: true)).foregroundStyle(theme.secondaryInk)
                                }
                                Spacer(minLength: 8)
                                Text(kinds(group.records)).font(quranFont(11)).foregroundStyle(theme.secondaryInk)
                            }
                            QuranPaperCard {
                                VStack(alignment: .leading, spacing: 0) {
                                    ForEach(Array(group.records.enumerated()), id: \.element.id) { index, record in
                                        if index > 0 { Divider().padding(.vertical, 8) }
                                        row(record)
                                    }
                                }
                            }
                        }
                    }
                    Text("تعديل التقييم يعيد حساب الموعد. حذف الحفظ قد يعيد موضع الورد إلى فجوة؛ الجلسات الأخرى تبقى.").font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                }
                if let error {
                    VStack(alignment: .leading, spacing: 8) {
                        Text(error).font(quranFont(13))
                        Button("حاول مرة أخرى") { load() }
                            .font(quranFont(13, bold: true)).frame(minHeight: 44)
                            .accessibilityIdentifier("quran-history-retry")
                    }
                }
            }.padding(16)
        }
            .onChange(of: expanded) { _, id in
                guard let id, id == initialSessionID else { return }
                if reduceMotion {
                    proxy.scrollTo("quran-history-route-details-" + id.uuidString, anchor: .center)
                } else {
                    withAnimation(.easeInOut(duration: 0.25)) {
                        proxy.scrollTo("quran-history-route-details-" + id.uuidString, anchor: .center)
                    }
                }
            }
            .background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).tint(theme.color("review")).disabled(busy)
            .safeAreaInset(edge: .bottom) { if app.undoToastVisible { UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).accessibilityIdentifier("quran-history-undo") } }
            .task { load() }.onChange(of: app.undoToken?.id) { load() }
            .alert("احذف هذه الجلسة؟", isPresented: Binding(get: { deleting != nil }, set: { if !$0 { deleting = nil } }), presenting: deleting) { id in
                Button("احذف", role: .destructive) { deleting = nil; run { try await service.perform(.deleteSession(id)); expanded = nil; load() } }
                Button("أبقِ الجلسة", role: .cancel) { deleting = nil }
            } message: { _ in Text("ستُزال آثارها من الحفظ والمواعيد والأخطاء. يمكنك التراجع فور الحذف من الشريط أسفل الشاشة.") }
            .alert("لم تكتمل العملية", isPresented: Binding(get: { app.errorMessage != nil }, set: { if !$0 { app.errorMessage = nil } })) { Button("تمّ") { app.errorMessage = nil } } message: { Text(app.errorMessage ?? "") }
        }
    }
    private var dayGroups: [(day: String, records: [QuranUILogRecord])] {
        records.reduce(into: []) { groups, record in
            if groups.last?.day == record.day { groups[groups.count - 1].records.append(record) } else { groups.append((record.day, [record])) }
        }
    }
    private func kinds(_ list: [QuranUILogRecord]) -> String {
        var names: [String] = []
        for record in list {
            let name = switch record.kind { case .hifz: "حفظ"; case .drill: "مذاكرة"; default: "مراجعة" }
            if !names.contains(name) { names.append(name) }
        }
        return names.joined(separator: "، ")
    }
    /// The session's weakest page grade; a session is only as settled as its weakest face.
    private func weakest(_ record: QuranUILogRecord) -> QuranUIGrade? {
        record.grades.map(\.grade).max { QuranUIGrade.allCases.firstIndex(of: $0)! < QuranUIGrade.allCases.firstIndex(of: $1)! }
    }
    private func palette(_ grade: QuranUIGrade) -> (ink: String, tint: String) {
        switch grade { case .mastered: ("reviewText", "reviewTint"); case .good: ("hifzText", "hifzTint"); case .needs: ("dueText", "dueTint") }
    }
    @ViewBuilder private func row(_ record: QuranUILogRecord) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Button {
                expanded = expanded == record.id ? nil : record.id
                page = record.grades.first?.page ?? 1
            } label: {
                HStack(spacing: 10) {
                    Rectangle().fill(theme.color(record.kind == .hifz ? "hifz" : "review")).frame(width: 3)
                    VStack(alignment: .leading, spacing: 5) { Text(record.title).font(quranFont(16, bold: true)); Text(record.detail).font(quranFont(12)).foregroundStyle(theme.secondaryInk) }
                    Spacer(minLength: 6)
                    if let grade = weakest(record) {
                        let colours = palette(grade)
                        Text(grade.title).font(quranFont(11, bold: true)).foregroundStyle(theme.color(colours.ink))
                            .padding(.horizontal, 10).padding(.vertical, 4).background(theme.color(colours.tint), in: Capsule())
                    }
                    Image(systemName: expanded == record.id ? "chevron.up" : "chevron.down").font(.system(size: 12)).foregroundStyle(theme.secondaryInk)
                }.frame(minHeight: 50).contentShape(Rectangle())
            }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-history-record-" + record.id.uuidString)
            if expanded == record.id {
                VStack(alignment: .leading, spacing: 12) {
                if !record.grades.isEmpty {
                    Picker("الوجه", selection: $page) { ForEach(record.grades) { grade in Text(grade.title).tag(grade.page) } }.font(quranFont(14)).tint(theme.ink)
                        .accessibilityIdentifier(initialSessionID == record.id ? "quran-history-route-target-" + record.id.uuidString : "quran-history-page-picker")
                    HStack(spacing: 4) {
                        ForEach(QuranUIGrade.allCases) { grade in
                            let current = record.grades.first { $0.page == page }?.grade == grade
                            let colours = palette(grade)
                            Button { run { try await service.perform(.editSessionGrade(sessionID: record.id, page: page, grade: grade)); load() } } label: {
                                Text(grade.title).font(quranFont(12, bold: current))
                                    .foregroundStyle(theme.color(colours.ink))
                                    .frame(maxWidth: .infinity, minHeight: 44)
                                    .background(current ? theme.color(colours.tint) : theme.surface, in: Capsule())
                                    .overlay { Capsule().stroke(theme.color(colours.ink).opacity(current ? 1 : 0.28), lineWidth: current ? 1.5 : 0.8) }
                            }.buttonStyle(.madarPlain).accessibilityAddTraits(current ? .isSelected : [])
                                .accessibilityIdentifier("quran-history-grade-" + grade.id)
                        }
                    }
                    if let due = value?.nextDue[page] { Text("الموعد التالي: " + due).font(quranFont(12)).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("quran-history-due") }
                }
                if !record.mistakes.isEmpty {
                    VStack(alignment: .leading, spacing: 7) {
                        Text("مواضع تعثّرت فيها").font(quranFont(13, bold: true)).accessibilityIdentifier("quran-history-mistakes")
                        ForEach(record.mistakes) { mistake in
                            VStack(alignment: .leading, spacing: 3) {
                                Text(mistake.title).font(quranFont(12, bold: true)).foregroundStyle(theme.color("dueText"))
                                    .accessibilityIdentifier("quran-history-mistake-" + mistake.id.uuidString)
                                Text(mistake.detail).font(quranFont(12)).foregroundStyle(theme.secondaryInk)
                            }
                        }
                    }.padding(12).frame(maxWidth: .infinity, alignment: .leading).background(theme.color("dueTint"), in: .rect(cornerRadius: 14))
                }
                if let warning = record.warning { Text(warning).font(quranFont(13)).foregroundStyle(theme.color("dueText")).accessibilityIdentifier("quran-history-warning") }
                Button("احذف الجلسة", role: .destructive) { deleting = record.id }.font(quranFont(13, bold: true)).foregroundStyle(theme.color("dueText")).frame(minHeight: 44).accessibilityIdentifier("quran-history-delete")
                }.id("quran-history-route-details-" + record.id.uuidString)
            }
        }
    }
    private func load() {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if !injectedReadFailure,
           environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           environment["MADAR_UI_QURAN_SESSION_LOG_READ_FAILURE_ONCE"] == "1" {
            injectedReadFailure = true
            value = nil
            error = quranUserMessage(CocoaError(.fileReadUnknown))
            return
        }
#endif
        do {
            let loaded = try service.sessionLog()
            value = loaded; error = nil
            guard let target = pendingSessionID else { return }
            filter = "all"
            if let record = loaded.records.first(where: { $0.id == target }) {
                expanded = target
                page = record.grades.first?.page ?? 1
            } else { routeUnavailableID = target }
            pendingSessionID = nil
        } catch { value = nil; self.error = quranUserMessage(error) }
    }
    private func run(_ work: @escaping @MainActor () async throws -> Void) { guard !busy else { return }; busy = true; Task { defer { busy = false }; do { try await work() } catch { self.error = quranUserMessage(error) } } }
}
