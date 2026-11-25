import SwiftUI
import MadarCore
import MadarDesign

/// Reading mode: a quiet full-screen page of the day as prose. No editing controls; swipe (RTL-correct, like a book) to the
/// neighbouring days that have something written. The pager follows the layout direction, so right-to-left needs no special case.
struct DiaryReadingView: View {
    @Bindable var app: AppSession
    let start: GregorianDay
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var days: [GregorianDay]
    @State private var current: GregorianDay
    @State private var archiveStore: ObjectIdentifier?
    @State private var archiveFailed = false
    @State private var archiveAttempt = 0
    #if DEBUG
    @State private var injectedArchiveFailure = false
    #endif
    private var service: AppDiaryService { .init(app: app) }

    private struct ArchiveRequest: Equatable {
        let store: ObjectIdentifier
        let revision: Int
        let canRead: Bool
        let attempt: Int
    }

    private var archiveRequest: ArchiveRequest {
        .init(store: ObjectIdentifier(app.container), revision: app.prayerRevision,
              canRead: app.protectedDataAuthorized && !app.maintenanceInProgress, attempt: archiveAttempt)
    }

    init(app: AppSession, start: GregorianDay) {
        self.app = app
        self.start = start
        _current = State(initialValue: start)
        _days = State(initialValue: [start])
    }

    var body: some View {
        let request = archiveRequest
        let visibleDays = archiveStore == request.store && app.protectedDataAuthorized ? days : [start]
        ZStack(alignment: .topLeading) {
            theme.background.ignoresSafeArea()
            TabView(selection: $current) {
                ForEach(visibleDays, id: \.self) { day in
                    DiaryReadingPage(app: app, day: day).tag(day)
                }
            }
            .id(request.store)
            .tabViewStyle(.page(indexDisplayMode: .never))
            .accessibilityIdentifier(visibleDays.count > 1 ? "diary-reading-pager" : "diary-reading-single-page")
            HStack {
                Button { dismiss() } label: {
                    Text("تمّ").font(DiaryType.label).padding(.horizontal, 16).frame(minHeight: 44)
                        .background(theme.surface.opacity(0.9), in: .capsule).overlay { Capsule().stroke(theme.line) }
                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-reading-close")
                Spacer()
                if typeSize.isAccessibilitySize, visibleDays.count > 1, let index = visibleDays.firstIndex(of: current) {
                    // Large text: the same neighbours as plain buttons beside the swipe.
                    Button("اليوم السابق") { if index > 0 { current = visibleDays[index - 1] } }.disabled(index == 0)
                    Button("اليوم التالي") { if index < visibleDays.count - 1 { current = visibleDays[index + 1] } }.disabled(index == visibleDays.count - 1)
                }
            }.padding(.horizontal, 16).padding(.top, 6).font(DiaryType.label)
        }
        .foregroundStyle(theme.ink).environment(\.roomTheme, theme)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if archiveFailed, request.canRead, archiveStore == request.store {
                HStack(spacing: 12) {
                    Text("تعذّر فتح بقية الصفحات.").foregroundStyle(theme.secondaryInk)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Button { archiveAttempt += 1 } label: {
                        Text("حاول مرة أخرى").frame(minHeight: 44).contentShape(.rect)
                    }.buttonStyle(.madarPlain).foregroundStyle(theme.accent)
                        .accessibilityIdentifier("diary-reading-archive-retry")
                }.font(DiaryType.label).padding(.horizontal, 24).padding(.vertical, 4)
                    .background(theme.surface)
            }
        }
        .task(id: request) { await loadArchive(request) }
    }

    private func loadArchive(_ request: ArchiveRequest) async {
        guard !Task.isCancelled, request == archiveRequest else { return }
        if archiveStore != request.store || !app.protectedDataAuthorized {
            current = start
            days = [start]
            archiveStore = request.store
        }
        archiveFailed = false
        guard request.canRead else { return }
        do {
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if !injectedArchiveFailure,
               environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               environment["MADAR_UI_DIARY_READING_ARCHIVE_FAILURE_ONCE"] == "1" {
                injectedArchiveFailure = true
                throw CocoaError(.fileReadUnknown)
            }
            #endif
            let archive = try await service.archiveOffMain()
            try Task.checkCancellation()
            guard request == archiveRequest else { return }
            var list = archive.days.filter { $0.writings > 0 || !$0.photoIDs.isEmpty }.map(\.day)
            if !list.contains(start) { list.append(start) }
            days = Array(Set(list)).sorted()
            if !days.contains(current) { current = start }
        } catch is CancellationError {
        } catch {
            guard !Task.isCancelled, request == archiveRequest else { return }
            archiveFailed = true
        }
    }
}

private struct DiaryReadingPage: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var page: DiaryDisplayDay?
    @State private var labels: [String: DiaryPeriodLabel] = [:]
    @State private var failed = false
    @State private var readAttempt = 0
    private var service: AppDiaryService { .init(app: app) }
    private let body19 = Font.custom("thmanyahseriftext-Regular", size: 22, relativeTo: .body)

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.weekday(day)).font(DiaryType.title)
                    Text(service.diaryDates(day)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }.padding(.top, 54)
                if !app.protectedDataAuthorized {
                    Text("تُتاح المذكرات عند فتح الجهاز.").font(DiaryType.writing)
                } else if let page {
                    let flow = page.lines.filter { $0.kind != "intention" }
                    let media = Dictionary(grouping: page.media, by: \.entryID)
                    if let photo = page.photo, !page.media.contains(where: { $0.kind == "photo" && $0.id == page.photoID }) {
                        readingPhoto(photo)
                    }
                    ForEach(flow, id: \.id) { line in
                        if let label = labels[line.id] { heading(label) }
                        entry(line, media: media[line.id] ?? [])
                    }
                    if flow.isEmpty && page.photo == nil {
                        Text("لم تُكتب سطور في هذا اليوم.").font(body19).foregroundStyle(theme.color("ink3Text"))
                    }
                } else if failed {
                    Text("تعذّر فتح الصفحة.").font(body19).foregroundStyle(theme.color("ink3Text"))
                    Button("حاول مرة أخرى") { readAttempt += 1 }
                        .font(DiaryType.label).frame(minHeight: 44)
                        .accessibilityIdentifier("diary-reading-retry")
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }.padding(.horizontal, 26).padding(.bottom, 60).frame(maxWidth: 620).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("diary-reading-page-" + day.description)
        .task(id: "\(app.protectedDataAuthorized)-\(readAttempt)") {
            guard app.protectedDataAuthorized else { page = nil; labels = [:]; return }
            failed = false
            do {
                let loaded = try await service.dayOffMain(day)
                try Task.checkCancellation()
                guard app.protectedDataAuthorized else { return }
                labels = service.periodLabels(for: loaded); page = loaded
            } catch is CancellationError {
            } catch {
                if !Task.isCancelled, app.protectedDataAuthorized { failed = true }
            }
        }
    }

    private func heading(_ label: DiaryPeriodLabel) -> some View {
        HStack(spacing: 8) {
            Text(label.title)
            if let time = label.time { Text(time) }
        }.font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).padding(.top, 10)
            .accessibilityElement(children: .combine).accessibilityIdentifier("diary-reading-heading")
    }

    @ViewBuilder private func entry(_ line: DiaryDisplayLine, media: [DiaryDisplayMedia]) -> some View {
        let auto = ["salah", "quran", "mihbara", "mal", "habits"].contains(line.kind)
        let hasAudio = media.contains { $0.kind == "audio" }
        if !hasAudio, !line.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            Text(attributed(line, auto: auto))
                .font(auto ? .custom("thmanyahseriftext-Regular", size: 18, relativeTo: .callout) : body19)
                .lineSpacing(auto ? 8 : 12).italic(auto).foregroundStyle(auto ? theme.color("autoInkText") : theme.ink)
                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-reading-line")
        }
        ForEach(media.filter { $0.kind != "missing" }) { item in
            if item.kind == "photo" {
                readingPhoto(item.data)
            } else if item.kind == "audio" {
                audioLine(item, transcript: line.text)
            }
        }
    }

    private func readingPhoto(_ data: Data) -> some View {
        DiaryDataThumbnail(data: data, maxPixel: 1400) { image in
            image.resizable().scaledToFit().frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: 14))
                .accessibilityLabel("صورة").accessibilityIdentifier("diary-reading-photo")
        }
    }

    private func audioLine(_ media: DiaryDisplayMedia, transcript: String) -> some View {
        let playback = app.diaryPlayback
        let playing = playback.activeID == media.id && playback.playing
        let seconds = media.duration ?? 0
        return VStack(alignment: .leading, spacing: 8) {
            Button { try? playback.toggle(id: media.id, data: media.data) } label: {
                HStack(spacing: 10) {
                    Image(systemName: playing ? "pause.circle.fill" : "play.circle.fill").font(.title2)
                    Text("تسجيل صوتي، " + service.digits.string(seconds / 60) + ":" + (seconds % 60 < 10 ? service.digits.string(0) : "") + service.digits.string(seconds % 60))
                        .font(DiaryType.label)
                    Spacer()
                }.frame(minHeight: 44).contentShape(.rect)
            }.buttonStyle(.madarPlain).foregroundStyle(theme.accent).accessibilityIdentifier("diary-reading-audio")
            let words = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
            if !words.isEmpty { Text(words).font(body19).lineSpacing(12).frame(maxWidth: .infinity, alignment: .leading) }
        }
    }

    private func attributed(_ line: DiaryDisplayLine, auto: Bool) -> AttributedString {
        line.markdown == true
            ? ((try? AttributedString(markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace))) ?? AttributedString(line.text))
            : AttributedString(line.text)
    }
}
