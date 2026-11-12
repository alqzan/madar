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
    @State private var days: [GregorianDay] = []
    @State private var current: GregorianDay
    private var service: AppDiaryService { .init(app: app) }

    init(app: AppSession, start: GregorianDay) {
        self.app = app; self.start = start; _current = State(initialValue: start)
    }

    private var index: Int? { days.firstIndex(of: current) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            theme.background.ignoresSafeArea()
            Group {
                if days.isEmpty {
                    DiaryReadingPage(app: app, day: start)
                } else {
                    TabView(selection: $current) {
                        ForEach(days, id: \.self) { day in
                            DiaryReadingPage(app: app, day: day).tag(day)
                        }
                    }.tabViewStyle(.page(indexDisplayMode: .never)).accessibilityIdentifier("diary-reading-pager")
                }
            }
            HStack {
                Button { dismiss() } label: {
                    Text("تمّ").font(DiaryType.label).padding(.horizontal, 16).frame(minHeight: 44)
                        .background(theme.surface.opacity(0.9), in: .capsule).overlay { Capsule().stroke(theme.line) }
                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-reading-close")
                Spacer()
                if typeSize.isAccessibilitySize, let index {
                    // Large text: the same neighbours as plain buttons beside the swipe.
                    Button("اليوم السابق") { if index > 0 { current = days[index - 1] } }.disabled(index == 0)
                    Button("اليوم التالي") { if index < days.count - 1 { current = days[index + 1] } }.disabled(index == days.count - 1)
                }
            }.padding(.horizontal, 16).padding(.top, 6).font(DiaryType.label)
        }
        .foregroundStyle(theme.ink).environment(\.roomTheme, theme)
        .task {
            guard let archive = try? await service.archiveOffMain() else { return }
            var list = archive.days.filter { $0.writings > 0 || !$0.photoIDs.isEmpty }.map(\.day)
            if !list.contains(start) { list.append(start) }
            days = Array(Set(list)).sorted()
            current = start
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
    private var service: AppDiaryService { .init(app: app) }
    private let body19 = Font.custom("thmanyahseriftext-Regular", size: 22, relativeTo: .body)

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.weekday(day)).font(DiaryType.title)
                    Text(service.diaryDates(day)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }.padding(.top, 54)
                if let page {
                    let flow = page.lines.filter { $0.kind != "intention" }
                    let media = Dictionary(grouping: page.media, by: \.entryID)
                    ForEach(flow, id: \.id) { line in
                        if let label = labels[line.id] { heading(label) }
                        entry(line, media: media[line.id] ?? [])
                    }
                    if flow.isEmpty && page.photo == nil {
                        Text("لم تُكتب سطور في هذا اليوم.").font(body19).foregroundStyle(theme.color("ink3Text"))
                    }
                } else if failed {
                    Text("تعذّر فتح الصفحة.").font(body19).foregroundStyle(theme.color("ink3Text"))
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(.top, 40)
                }
            }.padding(.horizontal, 26).padding(.bottom, 60).frame(maxWidth: 620).frame(maxWidth: .infinity, alignment: .leading)
        }
        .accessibilityElement(children: .contain).accessibilityIdentifier("diary-reading-page-" + day.description)
        .task(id: day) {
            guard app.protectedDataAuthorized else { return }
            do {
                let loaded = try await service.dayOffMain(day)
                labels = service.periodLabels(for: loaded); page = loaded
            } catch is CancellationError {} catch { failed = true }
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
                DiaryDataThumbnail(data: item.data, maxPixel: 1400) { image in
                    image.resizable().scaledToFit().frame(maxWidth: .infinity).clipShape(.rect(cornerRadius: 14))
                }.accessibilityLabel("صورة").accessibilityIdentifier("diary-reading-photo")
            } else if item.kind == "audio" {
                audioLine(item, transcript: line.text)
            }
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
