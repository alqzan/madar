import SwiftUI
import SwiftData
import MadarCore
import MadarData
import MadarDesign

// Owner, 22 Nov 2026 (mockup «ابحث في مدار», approved): one search from the lobby that finds a habit, a diary line,
// a book, a surah or a money movement, and opens it in its room. It only reads what each room already owns;
// nothing is written or copied, and each room keeps its own search for deeper filters.

struct MadarSearchHit: Identifiable, Equatable {
    enum Room: String, CaseIterable { case habits, notes, mihbara, quran, mal
        var title: String { switch self { case .habits: "العادات"; case .notes: "المذكرات"; case .mihbara: "المحبرة"; case .quran: "القرآن"; case .mal: "المال" } }
        var theme: String { switch self { case .habits: "bahw"; case .notes: "notes"; case .mihbara: "mihbara"; case .quran: "quran"; case .mal: "mal" } }
    }
    let id: String
    let room: Room
    let title: String
    let detail: String
    var day: GregorianDay? = nil
    let url: URL
    static func == (a: Self, b: Self) -> Bool { a.id == b.id && a.title == b.title && a.detail == b.detail }
}

@MainActor struct MadarSearch {
    let session: AppSession
    static let limitPerRoom = 4

    /// Arabic-insensitive matching: diacritics, tatweel, alef forms, taa marbuta and yaa folded the same way the diary search folds them.
    nonisolated static func key(_ text: String) -> String { DiarySearchParser.normalize(text) }

    func hits(for query: String) async -> [MadarSearchHit] {
        let needle = Self.key(query)
        guard needle.count >= 2 else { return [] }
        var result: [MadarSearchHit] = []
        result += habits(needle)
        guard session.protectedDataAuthorized else { return result }
        result += await quran(needle)
        result += books(needle)
        result += await diary(needle)
        result += money(needle)
        return result
    }

    private func habits(_ needle: String) -> [MadarSearchHit] {
        session.habitReadings(at: session.prayerNow())
            .filter { Self.key($0.name).contains(needle) }
            .prefix(Self.limitPerRoom)
            .map { row in
                MadarSearchHit(id: "habit-" + row.id.uuidString, room: .habits, title: row.name,
                               detail: row.paused ? "مجمّدة" : row.statusTitle,
                               url: URL(string: "madar://habits/habit/" + row.id.uuidString)!)
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

    private func books(_ needle: String) -> [MadarSearchHit] {
        let rows = (try? ModelContext(session.container).fetch(FetchDescriptor<Book>())) ?? []
        return rows.filter { $0.deletedAt == nil && $0.mergedInto == nil && (Self.key($0.title).contains(needle) || Self.key($0.author).contains(needle)) }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(Self.limitPerRoom)
            .map { book in
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
    private func money(_ needle: String) -> [MadarSearchHit] {
        let rows = (try? ModelContext(session.container).fetch(FetchDescriptor<MoneyTransaction>())) ?? []
        return rows.filter { row in
            row.deletedAt == nil && row.mergedInto == nil
                && [row.merchant, row.counterparty].compactMap { $0 }.contains { Self.key($0).contains(needle) }
        }
        .sorted { $0.dayKey > $1.dayKey }
        .prefix(Self.limitPerRoom)
        .map { row in
            MadarSearchHit(id: "tx-" + row.id.uuidString, room: .mal, title: row.merchant ?? row.counterparty ?? "حركة",
                           detail: "", day: try? GregorianDay(row.dayKey),
                           url: URL(string: "madar://mal/tx/" + row.id.uuidString)!)
        }
    }
}

struct MadarSearchView: View {
    let session: AppSession
    @Environment(\.dismiss) private var dismiss
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var query = ""
    @State private var hits: [MadarSearchHit] = []
    @State private var searching = false
    @FocusState private var focused: Bool
    private var theme: RoomTheme { RoomTheme(room: "bahw", dark: colorScheme == .dark) }

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 14) {
                    if query.trimmingCharacters(in: .whitespaces).count < 2 {
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
            .task(id: query) {
                let text = query
                guard MadarSearch.key(text).count >= 2 else { hits = []; return }
                searching = true
                try? await Task.sleep(for: .milliseconds(180))
                guard !Task.isCancelled else { return }
                let found = await MadarSearch(session: session).hits(for: text)
                guard !Task.isCancelled, text == query else { return }
                hits = found; searching = false
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
            if searching { ProgressView().controlSize(.small) }
            else if !query.isEmpty {
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
        dismiss()
        // The sheet leaves first, so the room's own navigation receives the route on a settled screen.
        Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(350))
            if hit.room == .mihbara, let id = UUID(uuidString: String(hit.id.dropFirst(5))) { session.openSpotlightBook(id) }
            else if hit.room == .habits, let id = UUID(uuidString: String(hit.id.dropFirst(6))) {
                session.selectedTab = "foundation"; session.habitRouteID = id; session.habitsOpen = true
            }
            else { session.open(hit.url) }
        }
    }
}
