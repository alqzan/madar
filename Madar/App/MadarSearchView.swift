import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign

// Owner, 22 Nov 2026 (mockup «ابحث في مدار», approved): one search from the lobby that finds a habit, a diary line,
// a book, a surah or a money movement, and opens it in its room. It only reads what each room already owns;
// nothing is written or copied, and each room keeps its own search for deeper filters.

struct MadarSearchHit: Identifiable, Equatable, Sendable {
    enum Room: String, CaseIterable, Sendable { case habits, notes, mihbara, quran, mal
        var title: String { switch self { case .habits: "العادات"; case .notes: "المذكرات"; case .mihbara: "المحبرة"; case .quran: "القرآن"; case .mal: "المال" } }
        var theme: String { switch self { case .habits: "bahw"; case .notes: "notes"; case .mihbara: "mihbara"; case .quran: "quran"; case .mal: "mal" } }
    }
    let id: String
    let room: Room
    let title: String
    let detail: String
    var day: GregorianDay? = nil
    let url: URL
}

@MainActor struct MadarSearch {
    let session: AppSession
    nonisolated static let limitPerRoom = 4

    /// Arabic-insensitive matching: diacritics, tatweel, alef forms, taa marbuta and yaa folded the same way the diary search folds them.
    nonisolated static func key(_ text: String) -> String { DiarySearchParser.normalize(text) }

    func hits(for needle: String) async -> [MadarSearchHit] {
        guard needle.count >= 2, !session.maintenanceInProgress else { return [] }
        let container = session.container
        let habitHits = habits(needle)
        guard session.protectedDataAuthorized else { return habitHits }
        let quranHits = await quran(needle)
        guard canRead(container) else { return habitHits }
        let diaryHits = await diary(needle)
        guard canRead(container) else { return habitHits }
        let records = Task.detached(priority: .userInitiated) {
            let context = ModelContext(container)
            return Self.books(needle, in: context) + Self.money(needle, in: context)
        }
        let recordHits = await withTaskCancellationHandler { await records.value } onCancel: { records.cancel() }
        guard canRead(container) else { return habitHits }
        return habitHits + quranHits + diaryHits + recordHits
    }

    private func canRead(_ container: ModelContainer) -> Bool {
        !Task.isCancelled && session.protectedDataAuthorized && !session.maintenanceInProgress && session.container === container
    }

    private func habits(_ needle: String) -> [MadarSearchHit] {
        session.habitReadings(at: session.prayerNow())
            .filter { Self.key($0.name).contains(needle) }
            .prefix(Self.limitPerRoom)
            .map { row in
                MadarSearchHit(id: "habit-" + row.id.uuidString, room: .habits, title: row.name,
                               detail: row.paused ? "مجمّدة" : row.statusTitle(AppBahwService(session: session).digits),
                               url: URL(string: "madar://bahw/habits/" + row.id.uuidString)!)
            }
    }

    private func quran(_ needle: String) async -> [MadarSearchHit] {
        guard let items = try? await AppQuranService(session: session).index(.surah) else { return [] }
        return items.filter { Self.key($0.title).contains(needle) || Self.key($0.searchText).contains(needle) }
            .prefix(Self.limitPerRoom)
            .map { item in
                MadarSearchHit(id: "surah-" + item.id, room: .quran, title: item.title, detail: item.subtitle,
                               url: URL(string: "madar://quran/page/\(item.firstPage)")!)
            }
    }

    nonisolated private static func books(_ needle: String, in context: ModelContext) -> [MadarSearchHit] {
        guard !Task.isCancelled else { return [] }
        let descriptor = FetchDescriptor<Book>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil },
                                               sortBy: [SortDescriptor(\.updatedAt, order: .reverse)])
        let rows = (try? context.fetch(descriptor)) ?? []
        let matching = rows.lazy.filter { !Task.isCancelled && (Self.key($0.title).contains(needle) || Self.key($0.author).contains(needle)) }
            .prefix(Self.limitPerRoom)
        return matching.map { book in
            MadarSearchHit(id: "book-" + book.id.uuidString, room: .mihbara, title: book.title,
                           detail: book.author.isEmpty ? "كتاب في رفوفك" : book.author,
                           url: URL(string: "madar://mihbara/book/" + book.id.uuidString)!)
        }
    }

    private func diary(_ needle: String) async -> [MadarSearchHit] {
        guard let index = try? await AppDiaryService(app: session).searchIndexOffMain() else { return [] }
        return index.documents.filter { Self.key($0.text).contains(needle) }
            .sorted { $0.day.description > $1.day.description }
            .prefix(Self.limitPerRoom)
            .map { document in
                let line = document.text.replacingOccurrences(of: "\n", with: " ")
                return MadarSearchHit(id: "diary-" + document.id, room: .notes,
                                      title: line.count > 70 ? String(line.prefix(70)) + "…" : line,
                                      detail: "", day: document.day,
                                      url: URL(string: "madar://notes/day/" + document.day.description)!)
            }
    }

    /// Movements by their name only; amounts stay in the money room, where «المال مخفي حتى اللمس» is honoured.
    nonisolated private static func money(_ needle: String, in context: ModelContext) -> [MadarSearchHit] {
        guard !Task.isCancelled else { return [] }
        let descriptor = FetchDescriptor<MoneyTransaction>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil },
                                                           sortBy: [SortDescriptor(\.dayKey, order: .reverse)])
        let rows = (try? context.fetch(descriptor)) ?? []
        let matching = rows.lazy.filter { row in
            !Task.isCancelled && [row.merchant, row.counterparty].compactMap { $0 }.contains { Self.key($0).contains(needle) }
        }.prefix(Self.limitPerRoom)
        return matching.map { row in
            MadarSearchHit(id: "tx-" + row.id.uuidString, room: .mal, title: row.merchant ?? row.counterparty ?? "حركة",
                           detail: "", day: try? GregorianDay(row.dayKey),
                           url: URL(string: "madar://mal/tx/" + row.id.uuidString)!)
        }
    }
}

struct MadarSearchView: View {
    let session: AppSession
    let onSelect: (URL) -> Void
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var result: (request: Request, hits: [MadarSearchHit])?
    @FocusState private var focused: Bool
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }

    private struct Request: Equatable {
        let needle: String
        let container: ObjectIdentifier
        let canRead: Bool
        let maintenance: Bool
    }

    private var request: Request {
        Request(needle: MadarSearch.key(query), container: ObjectIdentifier(session.container),
                canRead: session.protectedDataAuthorized, maintenance: session.maintenanceInProgress)
    }
    private var hits: [MadarSearchHit] { result?.request == request ? result?.hits ?? [] : [] }
    private var searching: Bool { request.needle.count >= 2 && result?.request != request }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if request.needle.count < 2 {
                        Text("اكتب حرفين أو أكثر: اسم عادة، سطر من مذكراتك، كتاب، سورة، أو اسم متجر.")
                            .font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).padding(.top, 8)
                    } else if hits.isEmpty && !searching {
                        Text("لا شيء في مدار يحتوي «\(query)».").font(MadarTypography.body()).foregroundStyle(theme.secondaryInk).padding(.top, 8)
                            .accessibilityIdentifier("madar-search-empty")
                    }
                    ForEach(MadarSearchHit.Room.allCases, id: \.self) { room in
                        let group = hits.filter { $0.room == room }
                        if !group.isEmpty {
                            VStack(alignment: .leading, spacing: 6) {
                                Text(room.title).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                                ForEach(group) { hit in row(hit) }
                            }
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: 8)))
                        }
                    }
                }
                .padding(.horizontal, 16).padding(.bottom, 24)
                .animation(reduceMotion ? nil : .smooth(duration: 0.3), value: hits)
            }
            .safeAreaInset(edge: .top, spacing: 0) { field }
            .background(theme.background.ignoresSafeArea())
            .navigationTitle("ابحث في مدار").navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تمّ") { dismiss() }.accessibilityIdentifier("madar-search-close") } }
            .task(id: request) { [request] in
                guard !Task.isCancelled, request == self.request else { return }
                result = nil
                guard request.needle.count >= 2 else { return }
                do { try await Task.sleep(for: .milliseconds(180)) } catch { return }
                guard !Task.isCancelled, request == self.request else { return }
                let found = await MadarSearch(session: session).hits(for: request.needle)
                guard !Task.isCancelled, request == self.request else { return }
                result = (request, found)
            }
        }
        .environment(\.roomTheme, theme).tint(theme.accent)
        .onAppear { focused = true }
    }

    private var field: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(theme.secondaryInk)
            TextField("ابحث في عاداتك ومذكراتك وكتبك ومالك", text: $query)
                .font(MadarTypography.body()).focused($focused).submitLabel(.search)
                .accessibilityIdentifier("madar-search-field")
            if searching { ProgressView().controlSize(.small).accessibilityIdentifier("madar-search-loading") }
            if !query.isEmpty {
                Button { query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(theme.secondaryInk).frame(width: 32, height: 44) }
                    .buttonStyle(.madarPlain).accessibilityLabel("امسح البحث")
            }
        }
        .padding(.horizontal, 14).frame(minHeight: 46)
        .glassEffect(.regular.interactive(), in: .capsule)
        .padding(.horizontal, 16).padding(.vertical, 8)
    }

    private func row(_ hit: MadarSearchHit) -> some View {
        let room = RoomTheme(room: hit.room.theme, dark: colorScheme == .dark)
        return Button { open(hit) } label: {
            HStack(spacing: 10) {
                Capsule().fill(room.accentFill).frame(width: 3, height: 30)
                VStack(alignment: .leading, spacing: 3) {
                    Text(hit.title).font(MadarTypography.body()).lineLimit(2).multilineTextAlignment(.leading)
                    if let day = hit.day {
                        MadarDateLabel(session.dateLabels(day, first: hit.room == .notes ? session.diaryFirstCalendar : nil)).foregroundStyle(theme.secondaryInk)
                    } else if !hit.detail.isEmpty {
                        Text(hit.detail).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk).lineLimit(1)
                    }
                }
                Spacer(minLength: 4)
                Image(systemName: "chevron.left").font(.caption).foregroundStyle(theme.secondaryInk)
            }
            .padding(.horizontal, 14).padding(.vertical, 10)
            .frame(maxWidth: .infinity, minHeight: 52, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 16))
        }
        .buttonStyle(.madarPressableTile)
        .accessibilityIdentifier("madar-search-hit-" + hit.id)
    }

    private func open(_ hit: MadarSearchHit) {
        onSelect(hit.url)
        dismiss()
    }
}
