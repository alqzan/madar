import SwiftUI
import MadarCore
import MadarDesign

struct DiaryDayView: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    var initialEntryID: UUID? = nil
    var initialEntryRouteID: UUID? = nil
    var embeddedInNavigationStack = false
    /// The write buttons on the home open this page with the cursor in the composer.
    var focusComposerOnOpen = false
    /// A question chosen on the home: shown above the composer, never saved into the text.
    var prompt: String? = nil
    /// madar://notes/write opens today's page with the composer already grown.
    var expandComposerOnOpen = false
    /// A day opened from the archive, search or a week is already inside that screen: it does not offer the same screens again on top of themselves.
    var showsNavigationTools = true
    @Environment(\.roomTheme) private var roomTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: GregorianDay?
    @State private var page: DiaryDisplayDay?
    @State private var photoViewer: DiaryPhotoViewerStart?
    @State private var photoStripToken = 0
    @State private var highlightedEntryID: UUID?
    @State private var highlightGeneration = 0
    @State private var failure: String?
    @State private var writing = false
    @State private var composerExpanded = false
    @State private var promptDismissed = false
    @State private var insertAt: Date?
    @State private var anchorLabel: String?
    @State private var inlineEdit: DiaryLineEdit?
    @State private var focusTick = 0
    @State private var retry = 0
    @State private var intentions: [DiaryIntention] = []
    @State private var intentionsOpen = false
    @State private var niyyaSaved = false
    @State private var niyyaToken: UUID?
    @State private var todayBox = TodayBox()
    @State private var revealedEntryID: UUID?
    @State private var appearance: DiaryDayAppearance?
    /// The page opened on «today»; when the day boundary passes while it is open, it moves on to the new day instead of becoming an old page.
    @State private var followedToday: GregorianDay?
    /// The same page a year ago, shown quietly on an empty today page (only when something was written then).
    @State private var echo: DiaryDisplayDay?
    @State private var returnDay: GregorianDay?
    @State private var returnDismissed = false
    @State private var archiveOpen = false
    @State private var weekOpen = false
    @State private var searchOpen = false
    @State private var displayNow = Date()
    @State private var travel: DiaryTravelPage?
    @State private var travelReturn: DiaryTravelReturn?
    @Environment(\.scenePhase) private var scenePhase
    @State private var aiComposerOpen = false
    @State private var aiAvailability: MadarAIAvailability = .checking
    @State private var stampsOpen = false
    @State private var editing: DiaryLineEdit?
    @State private var deleteConfirmation: UUID?
    @State private var original: DiaryLineEdit?
    @State private var waitingLetter: DiaryLetterCard?
    @State private var openingLetter: DiaryLetterCard?
    @State private var sealedHere = 0
    @State private var periodLabels: [String: DiaryPeriodLabel] = [:]
    @State private var expandedRuns: Set<String> = []
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var readingOpen = false
    @State private var reviewOpen = false
    @State private var afterIsha = false
#if DEBUG
    @State private var injectedReadFailures: Set<String> = []
#endif
    /// Travel days wear the air-mail paper everywhere on the page and in its sheets (§7.3).
    private var theme: RoomTheme { travel == nil ? roomTheme : RoomTheme(room: "notes.travel", dark: roomTheme.dark) }
    /// Writing happens in the one inline composer of the root page; a day opened in a sheet (search, hub, week, import) reads, and its pencil opens the full page.
    private var inlineWriting: Bool { shownDay == today && travel == nil && embeddedInNavigationStack }
    private var friday: Bool { appearance?.friday == true && travel == nil }
    private var shownDay: GregorianDay { selected ?? day }
    private var fridayStyle: DiaryFridayStyle { DiaryFridayStyle(app) }
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var canReadDiary: Bool { app.protectedDataAuthorized }
    private var pageReloadID: String {
        [shownDay.description, String(app.prayerRevision), String(retry), canReadDiary ? "open" : "closed"].joined(separator: ":")
    }
    private var aiAvailabilityID: String { [page?.id ?? "loading", String(retry), String(intentions.count), String(page?.lines.count ?? 0)].joined(separator: ":") }
    private var analysisText: String {
        guard let page else { return "" }
        return page.lines
            .filter { ["normal", "late", "ghad", "margin"].contains($0.kind) }
            .map { $0.markdown == true ? DayOneMarkdown.plain($0.text) : $0.text }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
    /// «Today» is read from the store once and kept (every row asks for it on every redraw); the 30-second tick and the foreground refresh renew it.
    private var today: GregorianDay {
        if let cached = todayBox.value { return cached }
        let fresh = (try? service.currentDay()) ?? day
        todayBox.value = fresh
        return fresh
    }
    private var first: FirstCalendar { app.diaryFirstCalendar }
    private var eveningPrimary: Bool { shownDay == today && !intentions.isEmpty && service.intentionEvening(shownDay) }
    private var secondInk: Color {
        switch app.string("notes.secondInk") {
        case "green": theme.color("ghad");
        case "brown": theme.color("autoInkText");
        default: theme.color("pencil")
        }
    }
    var body: some View {
        Group {
            if embeddedInNavigationStack { dayContent }
            else { NavigationStack { dayContent } }
        }.toolbarVisibility(.visible, for: .navigationBar)
    }
    @ViewBuilder private var dayContent: some View {
            VStack(spacing: 0) {
                if let appearance, let ramadanDay = appearance.ramadanDay {
                    DiaryRamadanBanner(
                        style: DiaryRamadanStyle(app),
                        dayText: "اليوم " + service.digits.string(ramadanDay) + " من رمضان",
                        headline: appearance.iftarAt.map { "الإفطار بعد " + countdown($0) }
                            ?? (appearance.night ? "ليلة من رمضان" : "رمضان")
                    ).padding(.horizontal, 18).padding(.vertical, 6).accessibilityIdentifier("diary-ramadan")
                }

                if let travel {
                    DiaryTravelHeader(
                        page: travel, subtitle: service.bothDates(shownDay, calendar: first),
                        distance: service.kilometres(travel.kilometres), digits: service.digits)
                } else {
                    DiaryDayHeader(app: app, theme: theme, shownDay: shownDay, today: today, yearAgo: aYearAgo, appearance: appearance, friday: friday, selected: $selected)
                }
                if !composerExpanded {
                if let returnDay, !returnDismissed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("آخر صفحة كتبتها: " + service.bothDates(returnDay, calendar: first)).font(DiaryType.label)
                        Text("لا تحتاج إلى تعويض شيء.").font(MadarTypography.body())
                        HStack(spacing: 8) {
                            if showsNavigationTools { Button {
                                archiveOpen = true
                            } label: {
                                Text("افتح يومًا سابقًا").frame(maxWidth: .infinity, minHeight: 44).overlay {
                                    Capsule().stroke(theme.line)
                                }
                            }.accessibilityIdentifier("diary-return-days") }
                            Button {
                                returnDismissed = true; if inlineWriting { composerExpanded = true } else { writing = true }
                            } label: {
                                Text("ابدأ من اليوم").frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(
                                    theme.background
                                ).background(theme.ink, in: .capsule)
                            }.accessibilityIdentifier("diary-return-write")
                        }.font(DiaryType.label).buttonStyle(.madarPlain)
                    }.padding(16).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                        .accessibilityElement(children: .contain).accessibilityIdentifier("diary-return")
                }
                if appearance?.weekAvailable == true, typeSize.isAccessibilitySize {
                    HStack {
                        Button("صندوق الأسبوع") { weekOpen = true }.accessibilityIdentifier("diary-week-open");
                        Spacer(); Text("يوم الجمعة").foregroundStyle(theme.color("ghad"))
                    }.font(DiaryType.label).frame(minHeight: 44).padding(.horizontal, 22)
                }
                if let travelReturn {
                    DiaryTravelReturnCard(
                        trip: travelReturn, days: dayCount(travelReturn.days),
                        distance: service.kilometres(travelReturn.kilometres)
                    ) { stampsOpen = true }.padding(.horizontal, 18).padding(.vertical, 6)
                }
                if shownDay == today, let waitingLetter {
                    DiaryLetterWaitingCard(
                        letter: waitingLetter, digitsTitle: service.diaryDates(waitingLetter.writtenDay)
                    ) { openingLetter = waitingLetter }.padding(.horizontal, 18).padding(.vertical, 6)
                }
                if intentionsOpen {
                    DiaryIntentionsView(app: app, day: shownDay, evening: service.intentionEvening(shownDay), inline: true, onClose: { intentionsOpen = false })
                        .environment(\.roomTheme, theme).padding(.horizontal, 12)
                        .accessibilityIdentifier("diary-niyya-inline")
                } else if eveningPrimary, let first = intentions.first {
                    eveningIntention(first)
                } else if shownDay == today || !intentions.isEmpty {
                    Button {
                        intentionsOpen = true
                    } label: {
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text("النيّة").font(DiaryType.label).foregroundStyle(theme.accent);
                            VStack(alignment: .leading, spacing: 2) {
                                Text(intentions.first?.text ?? "أضف نيّتك لليوم").font(DiaryType.writing).lineLimit(2);
                                if shownDay == today, !intentions.isEmpty {
                                    Text("أسألك عنها بعد العشاء").font(DiaryType.label).foregroundStyle(
                                        theme.color("ink3Text"))
                                }
                            }.frame(maxWidth: .infinity, alignment: .leading);
                            Image(systemName: "chevron.backward").font(.caption)
                        }.padding(.horizontal, 18).frame(minHeight: 40).contentShape(.rect)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-niyya-open")
                }
                }
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            LazyVStack(alignment: .leading, spacing: 0) {
                                if let page {
                                    // 10 Nov owner design: the day is one flow — the day's library photos on top, then every line, recording and attachment in the order it happened.
                                    if travel == nil { dayPhotoStrip }
                                    let flow = page.lines.filter { $0.kind != "intention" }
                                    let mediaByEntry = Dictionary(grouping: page.media, by: \.entryID)
                                    let runs = autoRuns(flow)
                                    ForEach(Array(flow.enumerated()), id: \.element.id) { index, line in
                                        let attached = mediaByEntry[line.id] ?? []
                                        let hasAudio = attached.contains { $0.kind == "audio" }
                                        // A recording's text is its transcript: the card below shows it whole and editable, so the line itself is not repeated.
                                        if let label = periodLabels[line.id] { DiaryPeriodHeadingRow(label: label) }
                                        if let run = runs[line.id], run.texts.count >= 2, !expandedRuns.contains(run.id) {
                                            // 14 Nov owner (T10): what Madar wrote for a chapter is one faint line; a tap opens it.
                                            if run.first { autoRunSummary(run).id("diary-entry-" + line.id) }
                                        } else if !hasAudio {
                                            lineRow(line, page: page).id("diary-entry-" + line.id)
                                            if let run = runs[line.id], run.first, run.texts.count >= 2 { collapseRunButton(run) }
                                        }
                                        ForEach(attached.filter { $0.kind != "missing" }) { media in
                                            DiaryMediaCard(app: app, media: media, transcript: line.text, openPhoto: { photoViewer = .init(id: $0.id.uuidString) })
                                                .overlay(alignment: .topLeading) {
                                                    if media.kind == "audio" { Text(service.time(line.at, zone: line.tzID)).font(DiaryType.label).lineLimit(1).minimumScaleFactor(0.92).foregroundStyle(theme.color("ink3Text")).frame(width: DiaryDayMetrics.timeColumn).padding(.leading, 6).padding(.top, 20) }
                                                }
                                                .id(hasAudio ? "diary-entry-" + line.id : media.id.uuidString)
                                                // 10 Nov owner: a photo or recording is as free as a line — hold it to delete, copy or write after it.
                                                .contextMenu { lineActions(line, page: page) }
                                        }
                                        // Owner real-data trial, 24 Oct 2026: one line for the entry's missing files, not one per file.
                                        if let first = attached.first(where: { $0.kind == "missing" }) {
                                            DiaryMediaCard(
                                                app: app, media: first, transcript: line.text,
                                                missingCount: attached.filter { $0.kind == "missing" }.count)
                                        }
                                    }
                                    ForEach(0..<sealedHere, id: \.self) { _ in
                                        HStack(alignment: .center, spacing: 12) {
                                            DiaryEnvelope(sealed: true).frame(width: DiaryDayMetrics.timeColumn, height: 26)
                                            Text("رسالة مختومة تُفتح في وقتها، ولا تُقرأ قبله").font(DiaryType.writing)
                                                .redacted(reason: .placeholder).blur(radius: 2.2).accessibilityHidden(
                                                    true)
                                        }.padding(.leading, 6).padding(.trailing, 18).padding(.vertical, 10)
                                            .accessibilityElement(children: .ignore).accessibilityLabel("رسالة مختومة")
                                            .accessibilityIdentifier("diary-sealed-letter-line")
                                    }
                                    if !page.media.contains(where: { $0.id == page.photoID }), let data = page.photo {
                                        DiaryDataThumbnail(data: data, maxPixel: 900) { image in image.resizable().scaledToFill() }
                                            .frame(maxWidth: .infinity).aspectRatio(4 / 3, contentMode: .fit)
                                            .clipShape(.rect(cornerRadius: 16)).padding(.vertical, 12)
                                            .accessibilityLabel("صورة من هذا اليوم")
                                    }
                                    if page.lines.isEmpty && page.photo == nil {
                                        Text(shownDay == today ? "صفحة تنتظر سطرك." : "لم تُكتب سطور في هذا اليوم.")
                                            .font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(
                                                .vertical, 40
                                            ).padding(.horizontal, 54)
                                        if shownDay == today, let echo { echoBlock(echo) }
                                    }
                                } else if failure == nil {
                                    ProgressView("تُفتح الصفحة…").padding(30)
                                }
                                if let failure {
                                    VStack(alignment: .leading, spacing: 10) {
                                        Text(failure).font(MadarTypography.body()).accessibilityIdentifier("diary-day-read-error")
                                        Button { retry += 1 } label: { Text("حاول مرة أخرى").frame(minHeight: 44).contentShape(Rectangle()) }
                                            .accessibilityIdentifier("diary-day-read-retry")
                                    }.padding(20)
                                }
                                if afterIsha, shownDay == today, travel == nil, canReadDiary {
                                    Button { reviewOpen = true } label: {
                                        Text("محاسبة اليوم").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(minHeight: 44).contentShape(.rect)
                                    }.buttonStyle(.madarPlain).padding(.leading, DiaryDayMetrics.contentLeading).padding(.trailing, 18)
                                        .accessibilityIdentifier("diary-review-link")
                                }
                if canReadDiary, (!analysisText.isEmpty || !intentions.isEmpty),
                                   (aiAvailability == .ready || aiAvailability == .needsDownload) {
                                    Button {
                        aiComposerOpen = true
                                    } label: {
                                        Label(
                            aiAvailability == .ready ? "اسأل عن هذا اليوم" : "جهّز المساعد على جهازك",
                                            systemImage: "sparkles"
                                        )
                                            .font(DiaryType.label).foregroundStyle(theme.accent)
                                            .padding(.horizontal, 18).padding(.vertical, 12)
                                            .background(theme.surface.opacity(0.82), in: Capsule())
                                            .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.madarPlain)
                                    .padding(.leading, DiaryDayMetrics.contentLeading).padding(.trailing, 18).padding(.top, 8)
                                    .accessibilityIdentifier("diary-ai-analysis")
                                }
                                Spacer(minLength: 70)
                            }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).frame(
                                minHeight: geometry.size.height, alignment: .topLeading
                            ).background {
                                Canvas { context, size in
                                    // Entries differ in height, so a fixed grid of rules cut through letters: each line row draws its own rule instead.
                                    if shownDay == today, travel == nil {
                                        // The flow's rail: one thin line beside the times, the way the day runs (RTL: the time column is on the right).
                                        var rail = Path(); rail.move(to: .init(x: size.width - DiaryDayMetrics.marginX, y: 8)); rail.addLine(to: .init(x: size.width - DiaryDayMetrics.marginX, y: size.height - 70))
                                        context.stroke(rail, with: .color(theme.accent.opacity(0.35)), lineWidth: 1)
                                    }
                                    var margin = Path(); margin.move(to: .init(x: size.width - DiaryDayMetrics.marginX, y: 0));
                                    margin.addLine(to: .init(x: size.width - DiaryDayMetrics.marginX, y: size.height))
                                    context.stroke(margin, with: .color(theme.color("margin")), lineWidth: 1)
                                }
                            }
                        }.overlay(alignment: .topTrailing) {
                            if let travel, !typeSize.isAccessibilitySize {
                                DiaryPassportStamp(city: travel.city, date: service.stampDate(travel.arrival)).padding(
                                    .top, 40
                                ).padding(.trailing, 4)
                            }
                        }.overlay(alignment: .topTrailing) {
                            if friday, !typeSize.isAccessibilitySize {
                                HStack(alignment: .top, spacing: 5) {
                                    if fridayStyle == .ribbon { ribbon("يوم الجمعة", color: theme.accent, height: 88) };
                                    if appearance?.weekAvailable == true {
                                        Button {
                                            weekOpen = true
                                        } label: {
                                            ribbon("صندوق الأسبوع", color: theme.color("ghad"), height: 130).frame(
                                                width: 44
                                            ).contentShape(.rect)
                                        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-week-open")
                                    }
                                }.padding(.trailing, 12)
                            }
                        }
                        .onChange(of: page?.lines.map(\.id), initial: true) { old, new in
                            revealInitialEntry(using: proxy)
                            // A line just written is brought into view (the keyboard and the composer cover the foot of the page); a whole page loading is not.
                            if inlineWriting, let old, let new, !old.isEmpty, new.count > old.count, new.count - old.count <= 2,
                               let added = new.first(where: { !old.contains($0) }) {
                                withAnimation(.snappy(duration: 0.25)) { proxy.scrollTo("diary-entry-" + added, anchor: .center) }
                            }
                        }
                        .onChange(of: initialEntryID) { _, _ in revealedEntryID = nil; revealInitialEntry(using: proxy) }
                        .onChange(of: initialEntryRouteID) { _, requestID in
                            if requestID != nil { revealedEntryID = nil; revealInitialEntry(using: proxy) }
                        }
                    }
                }.frame(maxHeight: composerExpanded ? 0 : .infinity).clipped()
                writingArea
            }
            // iPad: the page is a column of paper in the middle, not lines stretched across the screen.
            .frame(maxWidth: 680).frame(maxWidth: .infinity)
            .background(theme.background).foregroundStyle(theme.ink).environment(\.roomTheme, theme).scrollDismissesKeyboard(.interactively)
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    if showsNavigationTools {
                        Button {
                            searchOpen = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }.accessibilityLabel("ابحث في مذكراتك")
                        Button {
                            archiveOpen = true
                        } label: {
                            Image(systemName: "calendar")
                        }.accessibilityLabel("أيامك").accessibilityIdentifier("diary-day-archive")
                    }
                }
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { readingOpen = true } label: { Label("اقرأ", systemImage: "book") }.accessibilityIdentifier("diary-day-read")
                        if shownDay == today, travel == nil {
                            Button { reviewOpen = true } label: { Label("محاسبة اليوم", systemImage: "moon.stars") }.accessibilityIdentifier("diary-day-review")
                        }
                    } label: { Image(systemName: "ellipsis.circle") }.accessibilityLabel("المزيد").accessibilityIdentifier("diary-day-more")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if niyyaSaved, let token = app.undoToken, token.id == niyyaToken {
                        Button("تراجع") {
                            app.undo(); niyyaSaved = false
                        }.accessibilityIdentifier("diary-day-niyya-undo")
                    }
                }
                if !embeddedInNavigationStack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("المذكرات", systemImage: "chevron.backward")
                        }.accessibilityIdentifier("diary-day-close")
                    }
                }
            }
            .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
            // Deleting a line needs no confirmation: the «تراجع» badge that follows is enough.
            .onChange(of: deleteConfirmation) { _, id in
                guard let id else { return }
                deleteConfirmation = nil
                Task {
                    do { try await app.executeDiaryCommand("diary.deleteEntry", payload: ["entryID": .string(id.uuidString)]) }
                    catch { failure = madarUserMessage(error) }
                }
            }
            .fullScreenCover(isPresented: $searchOpen) { DiarySearchView(app: app).environment(\.roomTheme, theme) }
            .fullScreenCover(item: $photoViewer, onDismiss: { photoStripToken += 1 }) { start in
                DiaryPhotoViewer(app: app, day: shownDay, load: { await refreshLines(); return viewerItems() }, selection: start.id).environment(\.roomTheme, theme)
            }
            .fullScreenCover(isPresented: $archiveOpen) {
                DiaryHubView(app: app).environment(\.roomTheme, theme).madarSheetErrorAlert(app)
            }
            .sheet(item: $openingLetter, onDismiss: { retry += 1 }) { letter in
                DiaryLetterMoment(app: app, letter: letter).environment(\.roomTheme, theme)
            }
            .sheet(isPresented: $aiComposerOpen) {
                MadarAIAnalysisSheet(app: app, kind: .diary, initialScope: .day, initialDay: shownDay)
                    .environment(\.roomTheme, theme)
            }
            .sheet(item: $editing) { edit in
                DiaryLineEditSheet(app: app, edit: edit) { }.environment(\.roomTheme, theme)
                    .diaryRootDraftBlocking(app)
            }
            .sheet(item: $original) { first in
                DiaryOriginalSheet(text: first.text).environment(\.roomTheme, theme).presentationDetents([
                    .medium, .large,
                ])
            }
            .fullScreenCover(isPresented: $readingOpen) { DiaryReadingView(app: app, start: shownDay).environment(\.roomTheme, theme) }
            .sheet(isPresented: $reviewOpen) {
                DiaryNightReviewView(app: app, day: shownDay, page: page, intention: intentions.first) { Task { await refreshLines() } }
                    .environment(\.roomTheme, theme).madarSheetErrorAlert(app)
            }
            .sheet(isPresented: $stampsOpen) { DiaryStampsView(app: app).environment(\.roomTheme, theme) }
            .sheet(isPresented: $weekOpen) { DiaryWeekView(app: app, day: shownDay).environment(\.roomTheme, theme) }
            .navigationDestination(isPresented: $writing) { editorDestination }
            // N04: letters are checked when the diary is open and the app comes to the foreground.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { followToday(); aiAvailability = .checking; retry += 1 }
                else if phase == .background { aiComposerOpen = false }
            }
            .onChange(of: expandComposerOnOpen) { _, open in if open, inlineWriting { composerExpanded = true } }
            .onChange(of: shownDay) { _, _ in
                // A line being edited or a «write after» chip belongs to the page it began on.
                inlineEdit = nil; insertAt = nil; anchorLabel = nil; composerExpanded = false
            }
            .onChange(of: canReadDiary) { _, canRead in
                if canRead {
                    aiAvailability = .checking
                    retry += 1
                } else {
                    aiComposerOpen = false
                    aiAvailability = .checking
                    page = nil
                    retry += 1
                }
            }
            .task {
                while !Task.isCancelled {
                    do {
                        try await Task.sleep(for: .seconds(30)); displayNow = service.clock(); followToday()
                        // One failed read must not end the loop: it is what moves an open page on at the day boundary.
                        if let fresh = try? service.appearance(shownDay) { appearance = fresh }
                    } catch { break }
                }
            }
            .task(id: pageReloadID) { await loadDiaryPage() }
            .task {
                guard focusComposerOnOpen || expandComposerOnOpen else { return }
                // After the push settles; an earlier focus request is dropped before the field joins its window.
                try? await Task.sleep(for: .milliseconds(450))
                if inlineWriting { if expandComposerOnOpen { composerExpanded = true } else { focusTick += 1 } }
            }
            .task(id: aiAvailabilityID) {
                guard page != nil, (!analysisText.isEmpty || !intentions.isEmpty) else { aiAvailability = .checking; return }
                // No reset to «checking» here: the button stays put while a new line is saved, instead of blinking away and back.
                aiAvailability = await MadarAIAvailabilityChecker.check()
            }
    }

    /// The foot of the page: the undo line, a chosen question and the writing area (the composer on today's root page).
    @ViewBuilder private var writingArea: some View {
                VStack(spacing: 8) {
                    if app.undoToastVisible {
                        UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).hostsUndo(app)
                            .accessibilityIdentifier("diary-day-undo")
                    }
                    if inlineWriting, let prompt, !promptDismissed {
                        HStack(alignment: .top, spacing: 8) {
                            Text(prompt).font(.custom("thmanyahseriftext-Regular", size: 17, relativeTo: .body)).foregroundStyle(theme.color("ink3Text"))
                                .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier("diary-day-prompt")
                            Button { promptDismissed = true } label: { Image(systemName: "xmark.circle.fill").frame(width: 44, height: 44).contentShape(Rectangle()) }
                                .buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text")).accessibilityLabel("أخفِ السؤال")
                        }.padding(.horizontal, 22)
                    }
                    if inlineWriting {
                        DiaryInlineComposer(app: app, insertAt: $insertAt, anchor: $anchorLabel, edit: $inlineEdit, focusTick: $focusTick,
                                            expanded: $composerExpanded, page: page, saved: { Task { await refreshLines() } })
                    } else { HStack(spacing: 10) {
                        if let travel, shownDay == today {
                            Button {
                                insertAt = nil; writing = true
                            } label: {
                                Text("اكتب من " + travel.city).font(MadarTypography.section()).frame(
                                    maxWidth: .infinity, minHeight: 54
                                ).foregroundStyle(theme.color("onButton")).background(
                                    theme.color("button"), in: .capsule)
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-day-write")
                        } else {
                            Button {
                                insertAt = nil; writing = true
                            } label: {
                                Label(shownDay == today ? "اكتب" : "اكتب في هامشها", systemImage: "pencil").font(
                                    MadarTypography.section()
                                ).frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(theme.background)
                                    .background(theme.dark ? theme.accent : theme.ink, in: .capsule)
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-day-write")

                        }
                        if travel != nil {
                            Button {
                                stampsOpen = true
                            } label: {
                                Text("الأختام").font(DiaryType.label).frame(minHeight: 54).padding(.horizontal, 18)
                                    .glassEffect(.regular.interactive(), in: .capsule)
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-stamps-open")
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 8).background(theme.background) }
                }.background(theme.background)
    }
    private var editorDestination: some View {
        DiaryTextEditor(app: app, margin: shownDay == today ? nil : shownDay, insertAt: insertAt, embeddedInNavigationStack: true)
            .environment(\.roomTheme, theme).madarSheetErrorAlert(app).toolbarVisibility(.visible, for: .navigationBar)
            .hidesRoomAccessory(app, id: "diary-editor-from-day")
    }
    /// After a line or photo is added only the page's lines are read again; closed-day preparation, letters and the AI check stay as they were.
    @MainActor private func refreshLines() async {
        guard canReadDiary else { return }
        let target = shownDay
        do {
            let fresh = try await service.dayOffMain(target)
            guard target == shownDay, canReadDiary else { return }
            page = fresh; periodLabels = service.periodLabels(for: fresh); echo = nil
        } catch is CancellationError {
        } catch { failure = madarUserMessage(error) }
    }
    @MainActor private func followToday() {
        todayBox.value = nil
        guard let followed = followedToday, let now = try? service.currentDay(), now != followed else { return }
        followedToday = now
        if selected == nil || selected == followed { selected = now }
    }
    @MainActor private func loadDiaryPage() async {
        if followedToday == nil, selected == nil, day == today { followedToday = day }
        do {
            guard canReadDiary else { page = nil; aiComposerOpen = false; return }
            if page?.day != shownDay { page = nil; aiComposerOpen = false; aiAvailability = .checking }
            try await service.prepareClosedDay(shownDay)
            guard !Task.isCancelled, canReadDiary else { page = nil; aiComposerOpen = false; return }
            let displayPage = try await service.dayOffMain(shownDay)
            try Task.checkCancellation()
            guard canReadDiary, displayPage.day == shownDay else { return }
            page = displayPage
            periodLabels = service.periodLabels(for: displayPage)
            afterIsha = shownDay == today && service.ishaPassed(on: shownDay)
            intentions = try service.intentions(shownDay)
            appearance = try service.appearance(shownDay)
            displayNow = service.clock()
            echo = nil
            if shownDay == today, displayPage.lines.isEmpty, displayPage.photo == nil,
               let old = try? await service.dayOffMain(aYearAgo), (!old.lines.isEmpty || old.photo != nil) { echo = old }
            returnDay = try await service.returnAfterAbsenceOffMain(shownDay)
            travel = try service.travel(shownDay)
            travelReturn = travel == nil ? try service.travelReturn(shownDay) : nil
            if shownDay == today { try? await service.refreshLetters() }
            guard !Task.isCancelled, canReadDiary else { page = nil; aiComposerOpen = false; return }
            do {
#if DEBUG
                try injectReadFailureOnce("letters")
#endif
                let letters = try service.letters()
                waitingLetter = letters.first { $0.state == .eligible }
                sealedHere = letters.filter { $0.writtenDay == shownDay && $0.state != .opened }.count
            } catch {
                waitingLetter = nil; sealedHere = 0
                failure = madarUserMessage(error)
                return
            }
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            // A failed secondary read (intentions, appearance, travel) must not blank a page that already loaded.
            if page?.day != shownDay { page = nil }
            failure = madarUserMessage(error)
        }
    }
#if DEBUG
    private func injectReadFailureOnce(_ key: String) throws {
        let environment = ProcessInfo.processInfo.environment
        guard !injectedReadFailures.contains(key),
              environment["MADAR_UI_DIARY_DAY_READ_FAILURE_ONCE"] == key,
              environment["MADAR_UI_DIARY_FIXTURE"] == "letters",
              environment["MADAR_UI_STORE_ID"] != nil else { return }
        injectedReadFailures.insert(key)
        throw CocoaError(.fileReadUnknown)
    }
#endif
    /// OR-15: after Isha the morning's intention comes back on the page itself and asks how it went.
    private func eveningIntention(_ row: DiaryIntention) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("نويت صباحًا").font(DiaryType.label).foregroundStyle(theme.accent); Spacer();
                if intentions.count > 1 {
                    Button(
                        "و"
                            + arabicCount(
                                intentions.count - 1, ["نيّة أخرى", "نيّتان أخريان", "نيّات أخرى", "نيّةً أخرى"],
                                service.digits)
                    ) { intentionsOpen = true }.font(DiaryType.label).frame(minHeight: 44).accessibilityIdentifier(
                        "diary-niyya-more")
                }
            }
            Button {
                intentionsOpen = true
            } label: {
                Text(row.text).font(DiaryType.writing).frame(maxWidth: .infinity, alignment: .leading).lineLimit(3)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-niyya-open")
            HStack(spacing: 6) {
                ForEach([("done", "تمّت"), ("partial", "جزئيًا"), ("notEasy", "ما تيسّرت")], id: \.0) { value, title in
                    Button {
                        Task { @MainActor in
                            do {
                                try await service.setIntentionResult(row.id, result: row.result == value ? nil : value);
                                intentions = try service.intentions(shownDay); niyyaSaved = true; niyyaToken = app.undoToken?.id
                            } catch { failure = madarUserMessage(error) }
                        }
                    } label: {
                        Text(title).font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(
                            row.result == value ? theme.background : theme.ink
                        ).background(
                            row.result == value ? (theme.dark ? theme.accent : theme.ink) : .clear, in: .capsule
                        ).glassEffect(.regular.interactive(), in: .capsule)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-niyya-inline-" + value)
                        .accessibilityAddTraits(row.result == value ? .isSelected : [])
                }
            }
        }.padding(14).background(theme.surface, in: .rect(cornerRadius: 18)).overlay {
            RoundedRectangle(cornerRadius: 18).stroke(theme.line)
        }.padding(.horizontal, 18).padding(.vertical, 6).accessibilityElement(children: .contain)
            .accessibilityIdentifier("diary-niyya-evening")
    }
    /// «في مثل هذا اليوم»: one quiet line from the same day a year ago, on a page that has nothing yet. A tap opens that day.
    private func echoBlock(_ old: DiaryDisplayDay) -> some View {
        Button { selected = old.day } label: {
            VStack(alignment: .leading, spacing: 6) {
                Text("في مثل هذا اليوم قبل سنة").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                Text(old.excerpt).font(DiaryType.writing).italic().lineSpacing(8).lineLimit(3).multilineTextAlignment(.leading)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(service.bothDates(old.day, calendar: first)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
            }.padding(.top, 14).overlay(alignment: .top) { Rectangle().fill(theme.line).frame(height: 1) }
                .padding(.horizontal, 54).contentShape(Rectangle())
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-day-echo")
    }
    private func ribbon(_ title: String, color: Color, height: CGFloat) -> some View {
        Text(title).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(
            theme.background
        ).fixedSize().rotationEffect(.degrees(90)).frame(width: 24, height: height - 8).frame(
            height: height, alignment: .top
        ).background(DiaryRibbonShape().fill(color)).accessibilityLabel(title)
    }
    private func countdown(_ date: Date) -> String {
        let formatter = DateComponentsFormatter(); formatter.unitsStyle = .full;
        formatter.allowedUnits = [.hour, .minute]; formatter.maximumUnitCount = 2
        var calendar = Calendar(identifier: .gregorian);
        calendar.locale = Locale(
            identifier: app.string("core.numerals") == "western" ? "ar_SA@numbers=latn" : "ar_SA@numbers=arab");
        formatter.calendar = calendar
        return formatter.string(from: max(0, date.timeIntervalSince(displayNow))) ?? "أقل من دقيقة"
    }

    private var aYearAgo: GregorianDay {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = app.activePlace.timeZone
        return calendar.date(byAdding: .year, value: -1, to: today.date(in: app.activePlace.timeZone)).map {
            GregorianDay.containing($0, in: app.activePlace.timeZone)
        } ?? today.adding(days: -365)
    }
    /// Arabic counted noun: يوم واحد، يومان، ٣–١٠ أيام، ١١–٩٩ يومًا، ١٠٠ يوم.
    private func dayCount(_ n: Int) -> String {
        if n == 1 { return "يوم واحد" }; if n == 2 { return "يومان" }
        let r = n % 100; return service.digits.string(n) + ((3...10).contains(r) ? " أيام" : r <= 2 ? " يوم" : " يومًا")
    }
    private static let rooms = [
        "salah": "الصلاة", "quran": "القرآن", "mal": "المال", "habits": "العادات", "mihbara": "المحبرة",
    ]
    /// RU1: the joiner picks «، » when the line ends in a digit.
    private func roomSuffix(_ line: DiaryDisplayLine) -> String {
        let text = line.text.trimmingCharacters(in: .whitespacesAndNewlines),
            joined = MadarInlineText.joined([text, Self.rooms[line.kind] ?? ""])
        return String(joined.dropFirst(text.count))
    }
    private func styledLine(_ line: DiaryDisplayLine, auto: Bool) -> AttributedString {
        var content = line.markdown == true
            ? ((try? AttributedString(
                markdown: line.text, options: .init(interpretedSyntax: .inlineOnlyPreservingWhitespace)))
                ?? AttributedString(line.text))
            : AttributedString(line.text)
        // Thmanyah has no «٬» or «٫», so the fallback font draws them wide («١٤٠ , ٠٠»); use its own shapes, as displayFigure does.
        if thmanyahBundled {
            for (mark, shape, scale, raise) in [("٬", "،", 0.65, 0.23), ("٫", ",", 0.9, 0.0)] {
                while let range = content.range(of: mark) {
                    var glyph = AttributedString(shape)
                    glyph.font = .custom("thmanyahseriftext-Regular", size: (auto ? 17 : 19) * scale, relativeTo: .body)
                    if raise > 0 { glyph.baselineOffset = (auto ? 17 : 19) * raise }
                    content.replaceSubrange(range, with: glyph)
                }
            }
        }
        if auto {
            var suffix = AttributedString(roomSuffix(line))
            suffix.font = .custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)
            content.append(suffix)
        }
        return content
    }
    /// The day's photos from the library, on top of the flow: a tap adds one to the page, the rest stay a preview.
    @ViewBuilder private var dayPhotoStrip: some View {
        DiaryDayPhotos(app: app, day: shownDay) { asset in
            guard let data = await DiaryPhotoLibrary.data(asset), let copy = await Task.detached(priority: .userInitiated, operation: { DiaryPhotoLibrary.smallCopy(of: data) }).value else { return false }
            do { try await service.appendMedia(data: copy, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: shownDay, assetID: asset.localIdentifier); await refreshLines(); return true }
            catch { failure = madarUserMessage(error); return false }
        } open: { asset in photoViewer = .init(id: "asset:" + asset.localIdentifier) }
            .id(photoStripToken).padding(.leading, DiaryDayMetrics.contentLeading).padding(.trailing, 18).padding(.bottom, 10).accessibilityIdentifier("diary-day-photo-strip")
    }
    /// The day's photos for the viewer: those on the page in the order they happened, then the day's library photos not on any page.
    private func viewerItems() -> [DiaryViewerItem] {
        var items: [DiaryViewerItem] = []
        if let page {
            let mediaByEntry = Dictionary(grouping: page.media, by: \.entryID)
            for line in page.lines where line.kind != "intention" {
                for media in mediaByEntry[line.id] ?? [] where media.kind == "photo" {
                    items.append(.init(id: media.id.uuidString, mediaID: media.id, assetID: media.assetID, lineID: line.id, comment: line.text, data: media.data))
                }
            }
        }
        guard travel == nil else { return items }
        let linked = DiaryPhotoLibrary.linkedIDs(app)
        for asset in DiaryPhotoLibrary.assets(on: shownDay, timeZone: app.activePlace.timeZone) where !linked.contains(asset.localIdentifier) {
            items.append(.init(id: "asset:" + asset.localIdentifier, assetID: asset.localIdentifier, comment: ""))
        }
        return items
    }
    /// 10 Nov owner: no permanent «اكتب هنا» between every item. Any line is the place to write: its menu (or a tap on a room's own line) writes right after it, in time.
    private func writeAfter(_ line: DiaryDisplayLine, page: DiaryDisplayDay) {
        guard inlineWriting else { return }
        let flow = page.lines.filter { $0.kind != "intention" }
        if let index = flow.firstIndex(where: { $0.id == line.id }), index < flow.count - 1 {
            let gap = flow[index + 1].at.timeIntervalSince(line.at)
            insertAt = gap > 2 ? line.at.addingTimeInterval(gap / 2) : line.at.addingTimeInterval(1)
            anchorLabel = String(line.text.prefix(24))
        } else { insertAt = nil; anchorLabel = nil }
        inlineEdit = nil; focusTick += 1
    }
    /// A tap on a line you wrote changes it in the field at the foot of today's page; older days use the sheet (it explains the «عُدّل» mark).
    private func editLine(_ line: DiaryDisplayLine) {
        if inlineWriting { insertAt = nil; anchorLabel = nil; inlineEdit = .init(id: line.id, text: line.text) }
        else { editing = .init(id: line.id, text: line.text) }
    }
    private struct AutoRun { let id: String; let first: Bool; let texts: [String] }
    private static let autoKinds: Set<String> = ["salah", "quran", "mihbara", "mal", "habits"]
    /// Consecutive lines written by Madar inside one prayer chapter. A chapter heading or a line of yours ends the run.
    private func autoRuns(_ flow: [DiaryDisplayLine]) -> [String: AutoRun] {
        var result: [String: AutoRun] = [:]
        var members: [DiaryDisplayLine] = []
        func close() {
            if let head = members.first {
                let texts = members.map(\.text).filter { !$0.isEmpty }
                for line in members { result[line.id] = AutoRun(id: head.id, first: line.id == head.id, texts: texts) }
            }
            members = []
        }
        for line in flow {
            if Self.autoKinds.contains(line.kind) {
                if periodLabels[line.id] != nil { close() }
                members.append(line)
            } else { close() }
        }
        close()
        return result
    }
    private func autoRunSummary(_ run: AutoRun) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { _ = expandedRuns.insert(run.id) }
        } label: {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Color.clear.frame(width: DiaryDayMetrics.timeColumn, height: 1)
                Text(run.texts.joined(separator: "، ")).font(.custom("thmanyahseriftext-Regular", size: 17, relativeTo: .body)).italic()
                    .foregroundStyle(theme.color("autoInkText")).multilineTextAlignment(.leading).lineLimit(2)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").font(.caption).foregroundStyle(theme.color("ink3Text"))
            }.padding(.leading, 6).padding(.trailing, 18).padding(.vertical, 10).frame(minHeight: 44).contentShape(Rectangle())
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-auto-run")
    }
    private func collapseRunButton(_ run: AutoRun) -> some View {
        Button {
            withAnimation(reduceMotion ? nil : .snappy) { _ = expandedRuns.remove(run.id) }
        } label: {
            Text("اطوِ").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity, minHeight: 30)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-auto-run-collapse")
    }
    private func lineRow(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        let auto = ["salah", "quran", "mihbara", "mal", "habits"].contains(line.kind)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(service.time(line.at, zone: line.tzID)).font(DiaryType.label).lineLimit(1).minimumScaleFactor(0.92)
                .foregroundStyle(theme.color("ink3Text")).frame(width: DiaryDayMetrics.timeColumn, alignment: .center).accessibilityIdentifier(
                "diary-day-line-time")
            VStack(alignment: .leading, spacing: 5) {
                // OR-12: the room's name follows its line, small and in the same light ink («· الصلاة»), as the canonical.
                Text(styledLine(line, auto: auto))
                    .font(.custom("thmanyahseriftext-Regular", size: auto ? 17 : 19, relativeTo: .body)).lineSpacing(11)
                    .italic(auto || line.kind == "margin")
                    .frame(maxWidth: .infinity, alignment: .leading).accessibilityIdentifier(
                        "diary-day-line")
                if let first = page.originals[line.id] {
                    Button {
                        original = .init(id: line.id, text: first)
                    } label: {
                        Text("عُدّل · الأصل").font(DiaryType.label).frame(minHeight: 30)
                    }.buttonStyle(.madarPlain).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier(
                        "diary-line-edited")
                }
                if line.kind == "late" { Text("كُتبت لاحقًا").font(DiaryType.label) }
                if line.kind == "margin" {
                    Text(
                        MadarInlineText.joined([
                            "هامش", page.marginDays[line.id].map { service.diaryDates($0) } ?? "تاريخ الكتابة غير متاح",
                        ])
                    ).font(DiaryType.label)
                }
            }.foregroundStyle(
                line.kind == "margin"
                    ? secondInk
                    : line.kind == "late" ? theme.color("late") : auto ? theme.color("autoInkText") : theme.ink)
        }.contentShape(Rectangle()).onTapGesture {
            // Tap a line to write after it; changing a line lives in its long-press menu.
            writeAfter(line, page: page)
        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-entry-" + line.id).overlay {
            if highlightedEntryID?.uuidString == line.id {
                RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: 2)
            }
        }.animation(.easeInOut(duration: 0.2), value: highlightedEntryID)
            .contextMenu { lineActions(line, page: page) }.padding(.leading, 6).padding(.trailing, travel == nil || typeSize.isAccessibilitySize ? 18 : 92).padding(
                .vertical, 10
            ).frame(minHeight: 34).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 0.7) }
    }
    @ViewBuilder private func lineActions(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        if inlineWriting {
            Button("اكتب بعده", systemImage: "text.append") { writeAfter(line, page: page) }.accessibilityIdentifier("diary-line-write-after")
        }
        if !line.text.isEmpty { Button("انسخ", systemImage: "doc.on.doc") { UIPasteboard.general.string = line.text } }
        if page.editable.contains(line.id) {
            Button("عدّل السطر", systemImage: "pencil") { editLine(line) }
        }
        if page.deletable.contains(line.id), let id = UUID(uuidString: line.id) {
            Button(role: .destructive) {
                deleteConfirmation = id
            } label: {
                Label("احذف السطر", systemImage: "trash")
            }
            .accessibilityIdentifier("diary-line-delete")
        }
        if shownDay == today, ["normal", "late", "ghad"].contains(line.kind), !line.text.isEmpty {
            Button("اجعلها نيّة اليوم") {
                Task {
                    do { try await service.saveIntention(line.text, day: shownDay); niyyaSaved = true; niyyaToken = app.undoToken?.id } catch {
                        failure = madarUserMessage(error)
                    }
                }
            }
        }
    }
    private func revealInitialEntry(using proxy: ScrollViewProxy) {
        guard let initialEntryID, revealedEntryID != initialEntryID,
            page?.lines.contains(where: { $0.id == initialEntryID.uuidString }) == true
        else { return }
        // Once per request: editing a line makes a new revision and used to throw the reader back to the opened entry.
        revealedEntryID = initialEntryID
        highlightGeneration += 1
        let generation = highlightGeneration
        highlightedEntryID = initialEntryID
        proxy.scrollTo("diary-entry-" + initialEntryID.uuidString, anchor: .center)
        Task { @MainActor in
            do { try await Task.sleep(for: .seconds(2)) } catch { return }
            if highlightGeneration == generation, highlightedEntryID == initialEntryID { highlightedEntryID = nil }
        }
    }
}


/// The day page's paper: one column for the time and the margin line right after it, the text after that.
enum DiaryDayMetrics {
    static let timeColumn: CGFloat = 46
    /// Distance of the red margin line from the leading (right, RTL) edge: after the 6 pt inset and the time column.
    static let marginX: CGFloat = 58
    /// Where free content (photo strip, buttons) starts so it never crosses the margin line.
    static let contentLeading: CGFloat = 70
}

/// A value kept across redraws that is not itself observed: the page renews it at known moments.
final class TodayBox { var value: GregorianDay? }
