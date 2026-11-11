import SwiftUI
import MadarCore
import MadarDesign

struct DiaryDayView: View {
    @Bindable var app: AppSession
    let day: GregorianDay
    var initialEntryID: UUID? = nil
    var initialEntryRouteID: UUID? = nil
    var embeddedInNavigationStack = false
    @Environment(\.roomTheme) private var roomTheme
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var selected: GregorianDay?
    @State private var page: DiaryDisplayDay?
    @State private var highlightedEntryID: UUID?
    @State private var highlightGeneration = 0
    @State private var failure: String?
    @State private var writing = false
    @State private var insertAt: Date?
    @State private var anchorLabel: String?
    @State private var inlineEdit: DiaryLineEdit?
    @State private var focusTick = 0
    @State private var retry = 0
    @State private var intentions: [DiaryIntention] = []
    @State private var arc: DiaryDayArc?
    @State private var intentionsOpen = false
    @State private var niyyaSaved = false
    @State private var appearance: DiaryDayAppearance?
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
    @State private var projectLinks: [String: String] = [:]
    @State private var projectSuggestions: [String: DiaryProjectCard] = [:]
#if DEBUG
    @State private var injectedReadFailures: Set<String> = []
#endif
    /// Travel days wear the air-mail paper everywhere on the page and in its sheets (§7.3).
    private var theme: RoomTheme { travel == nil ? roomTheme : RoomTheme(room: "notes.travel", dark: roomTheme.dark) }
    private var friday: Bool { appearance?.friday == true && travel == nil }
    private var shownDay: GregorianDay { selected ?? day }
    private var fridayStyle: DiaryFridayStyle { DiaryFridayStyle(app) }
    /// OR-16: the Friday title wears the look chosen in the diary settings.
    @ViewBuilder private var fridayOrnament: some View {
        switch fridayStyle {
        case .ribbon: DiaryFridayFrame().stroke(theme.accent.opacity(0.65), lineWidth: 0.7).padding(.horizontal, 12)
        case .mihrab:
            ZStack(alignment: .top) {
                DiaryMihrabShape().stroke(theme.accent.opacity(0.55), lineWidth: 1).padding(.horizontal, 56);
                DiaryStarShape().fill(theme.accent).frame(width: 22, height: 22).padding(.top, 16)
            }.accessibilityHidden(true).accessibilityIdentifier("diary-friday-mihrab")
        case .medallion:
            ZStack {
                Circle().stroke(theme.accent.opacity(0.6), lineWidth: 1);
                DiaryStarShape().fill(theme.accent).frame(width: 18, height: 18)
            }.frame(width: 36, height: 36).frame(maxHeight: .infinity, alignment: .top).accessibilityHidden(true)
                .accessibilityIdentifier("diary-friday-medallion")
        }
    }
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var canReadDiary: Bool { app.protectedDataAuthorized }
    private var pageReloadID: String {
        [shownDay.description, String(app.prayerRevision), String(retry), canReadDiary ? "open" : "closed"].joined(separator: ":")
    }
    private var aiAvailabilityID: String { [page?.id ?? "loading", String(retry), String(intentions.count)].joined(separator: ":") }
    private var analysisText: String {
        guard let page else { return "" }
        return page.lines
            .filter { ["normal", "late", "ghad", "margin"].contains($0.kind) }
            .map { $0.markdown == true ? DayOneMarkdown.plain($0.text) : $0.text }
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .joined(separator: "\n\n")
    }
    private var today: GregorianDay { (try? service.currentDay()) ?? day }
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text(
                            service.weekday(shownDay) + "، "
                                + (first == .gregorian && appearance?.night == true ? "ليلة " : "")
                                + service.dateTitle(
                                    first == .gregorian ? appearance?.hijriDisplayDay ?? shownDay : shownDay,
                                    calendar: first == .hijri ? .gregorian : .hijri)
                                + (friday ? "، " + service.dateTitle(shownDay, calendar: first) : "")
                        )
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier(
                            "diary-day-secondary-date")
                        // OR-12: the date and its three tabs share one row, as the canonical today page; «حتى الآن» left (lighter header).
                        let title = Text(
                            friday
                                ? "جمعة مباركة"
                                : (first == .hijri && appearance?.night == true ? "ليلة " : "")
                                    + service.dateTitle(
                                        first == .hijri ? appearance?.hijriDisplayDay ?? shownDay : shownDay,
                                        calendar: first)
                        ).foregroundStyle(friday ? theme.accent : theme.ink).font(
                            .custom("thmanyahserifdisplay-Bold", size: 32, relativeTo: .largeTitle)
                        ).lineLimit(1).minimumScaleFactor(0.7).accessibilityIdentifier("diary-day-title")
                        if friday {
                            title
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .bottom, spacing: 8) {
                                    title; Spacer(minLength: 4); tabs
                                }
                                VStack(alignment: .leading, spacing: 8) {
                                    title; tabs
                                }
                            }
                        }
                    }.padding(.horizontal, 18).padding(.vertical, 10).frame(
                        maxWidth: .infinity, alignment: friday ? .center : .leading
                    ).padding(.top, friday && fridayStyle != .ribbon ? 34 : 0).background {
                        if friday { fridayOrnament }
                    }
                }
                if let returnDay, !returnDismissed {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("آخر صفحة كتبتها: " + service.bothDates(returnDay, calendar: first)).font(DiaryType.label)
                        Text("لا تحتاج إلى تعويض شيء.").font(MadarTypography.body())
                        HStack(spacing: 8) {
                            Button {
                                archiveOpen = true
                            } label: {
                                Text("افتح يومًا سابقًا").frame(maxWidth: .infinity, minHeight: 44).overlay {
                                    Capsule().stroke(theme.line)
                                }
                            }.accessibilityIdentifier("diary-return-days")
                            Button {
                                returnDismissed = true; writing = true
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
                        letter: waitingLetter, digitsTitle: service.bothDates(waitingLetter.writtenDay)
                    ) { openingLetter = waitingLetter }.padding(.horizontal, 18).padding(.vertical, 6)
                }
                if shownDay == today, travel == nil, let arc {
                    DiaryDayArcView(arc: arc).padding(.horizontal, 18).padding(.top, 2)
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
                        }.padding(.horizontal, 18).frame(minHeight: 54).contentShape(.rect)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-niyya-open")
                }
                GeometryReader { geometry in
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 0) {
                                if let page {
                                    // 10 Nov owner design: the day is one flow — the day's library photos on top, then every line, recording and attachment in the order it happened.
                                    if shownDay == today, travel == nil { dayPhotoStrip }
                                    let flow = page.lines.filter { $0.kind != "intention" }
                                    ForEach(Array(flow.enumerated()), id: \.element.id) { index, line in
                                        let attached = page.media.filter { $0.entryID == line.id }
                                        let hasAudio = attached.contains { $0.kind == "audio" }
                                        // A recording's text is its transcript: the card below shows it whole and editable, so the line itself is not repeated.
                                        if !hasAudio { lineRow(line, page: page).id("diary-entry-" + line.id) }
                                        ForEach(attached.filter { $0.kind != "missing" }) { media in
                                            DiaryMediaCard(app: app, media: media, transcript: line.text)
                                                .overlay(alignment: .topLeading) {
                                                    if media.kind == "audio" { Text(service.time(line.at, zone: line.tzID)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text")).frame(width: 38).padding(.leading, 6).padding(.top, 20) }
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
                                            DiaryEnvelope(sealed: true).frame(width: 38, height: 26)
                                            Text("رسالة مختومة تُفتح في وقتها، ولا تُقرأ قبله").font(DiaryType.writing)
                                                .redacted(reason: .placeholder).blur(radius: 2.2).accessibilityHidden(
                                                    true)
                                        }.padding(.leading, 6).padding(.trailing, 18).padding(.vertical, 10)
                                            .accessibilityElement(children: .ignore).accessibilityLabel("رسالة مختومة")
                                            .accessibilityIdentifier("diary-sealed-letter-line")
                                    }
                                    if !page.media.contains(where: { $0.id == page.photoID }), let data = page.photo,
                                        let image = UIImage(data: data)
                                    {
                                        Image(uiImage: image).resizable().scaledToFit().frame(maxWidth: 150).padding(8)
                                            .background(theme.surface)
                                            .overlay(alignment: .top) {
                                                Rectangle().fill(theme.line).frame(width: 48, height: 16)
                                                    .rotationEffect(.degrees(-5)).offset(y: -8)
                                            }
                                            .rotationEffect(.degrees(-2)).shadow(
                                                color: theme.ink.opacity(0.1), radius: 5, y: 5
                                            )
                                            .padding(.vertical, 24).frame(maxWidth: .infinity, alignment: .center)
                                            .accessibilityLabel("صورة من هذا اليوم")
                                    }
                                    if page.lines.isEmpty && page.photo == nil {
                                        Text(shownDay == today ? "صفحة تنتظر سطرك." : "لم تُكتب سطور في هذا اليوم.")
                                            .font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(
                                                .vertical, 40
                                            ).padding(.horizontal, 54)
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
                if canReadDiary, (!analysisText.isEmpty || !intentions.isEmpty),
                                   (aiAvailability == .ready || aiAvailability == .needsDownload) {
                                    Button {
                        aiComposerOpen = true
                                    } label: {
                                        Label(
                            aiAvailability == .ready ? "اسأل عن هذا اليوم" : "جهّز الترجمة على الجهاز",
                                            systemImage: "sparkles"
                                        )
                                            .font(DiaryType.label).foregroundStyle(theme.accent)
                                            .padding(.horizontal, 18).padding(.vertical, 12)
                                            .background(theme.surface.opacity(0.82), in: Capsule())
                                            .glassEffect(.regular.interactive(), in: .capsule)
                                    }
                                    .buttonStyle(.madarPlain)
                                    .padding(.horizontal, 18).padding(.top, 8)
                                    .accessibilityIdentifier("diary-ai-analysis")
                                }
                                Spacer(minLength: 70)
                            }.padding(.vertical, 14).frame(maxWidth: .infinity, alignment: .leading).frame(
                                minHeight: geometry.size.height, alignment: .topLeading
                            ).background {
                                Canvas { context, size in
                                    var rules = Path()
                                    for y in stride(from: 14.0, through: size.height, by: 34) {
                                        rules.move(to: .init(x: 0, y: y)); rules.addLine(to: .init(x: size.width, y: y))
                                    }
                                    context.stroke(rules, with: .color(theme.line), lineWidth: 0.7)
                                    if shownDay == today, travel == nil {
                                        // The flow's rail: one thin line beside the times, the way the day runs (RTL: the time column is on the right).
                                        var rail = Path(); rail.move(to: .init(x: size.width - 50, y: 8)); rail.addLine(to: .init(x: size.width - 50, y: size.height - 70))
                                        context.stroke(rail, with: .color(theme.accent.opacity(0.35)), lineWidth: 1)
                                    }
                                    var margin = Path(); margin.move(to: .init(x: size.width - 50, y: 0));
                                    margin.addLine(to: .init(x: size.width - 50, y: size.height))
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
                        .onChange(of: page?.lines.map(\.id), initial: true) { _, _ in revealInitialEntry(using: proxy) }
                        .onChange(of: initialEntryID) { _, _ in revealInitialEntry(using: proxy) }
                        .onChange(of: initialEntryRouteID) { _, requestID in
                            if requestID != nil { revealInitialEntry(using: proxy) }
                        }
                    }
                }
            }
            .background(theme.background).foregroundStyle(theme.ink).environment(\.roomTheme, theme).scrollDismissesKeyboard(.interactively)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                VStack(spacing: 8) {
                    if app.undoToastVisible {
                        UndoToast(message: app.undoMessage, undo: app.undo, dismiss: app.hideUndoToast).hostsUndo(app)
                            .accessibilityIdentifier("diary-day-undo")
                    }
                    if shownDay == today, travel == nil {
                        DiaryInlineComposer(app: app, insertAt: $insertAt, anchor: $anchorLabel, edit: $inlineEdit, focusTick: $focusTick,
                                            editorOpen: writing, openEditor: { insertAt = nil; anchorLabel = nil; writing = true }, saved: { retry += 1 })
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
            .toolbar {
                ToolbarItemGroup(placement: .topBarTrailing) {
                    Button {
                        searchOpen = true
                    } label: {
                        Image(systemName: "magnifyingglass")
                    }.accessibilityLabel("ابحث في مذكراتك");
                    Button {
                        archiveOpen = true
                    } label: {
                        Image(systemName: "book.closed")
                    }.accessibilityLabel("أيامك")
                }
                ToolbarItem(placement: .topBarTrailing) {
                    if niyyaSaved, app.undoToken != nil {
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
            .alert(
                "احذف السطر؟",
                isPresented: Binding(get: { deleteConfirmation != nil }, set: { if !$0 { deleteConfirmation = nil } })
            ) {
                Button("إلغاء", role: .cancel) { deleteConfirmation = nil }
                Button("احذف", role: .destructive) {
                    guard let id = deleteConfirmation else { return }
                    deleteConfirmation = nil
                    Task {
                        do {
                            try await app.executeDiaryCommand(
                                "diary.deleteEntry", payload: ["entryID": .string(id.uuidString)])
                        } catch { failure = madarUserMessage(error) }
                    }
                }.accessibilityIdentifier("diary-line-delete-confirm")
            } message: {
                Text("تبقى الهوامش في يوم كتابتها، ويمكنك التراجع فور الحذف من زر «تراجع».")
            }
            .fullScreenCover(isPresented: $searchOpen) { DiarySearchView(app: app).environment(\.roomTheme, theme) }
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
            .sheet(isPresented: $stampsOpen) { DiaryStampsView(app: app).environment(\.roomTheme, theme) }
            .sheet(isPresented: $weekOpen) { DiaryWeekView(app: app, day: shownDay).environment(\.roomTheme, theme) }
            .navigationDestination(isPresented: $writing) {
                DiaryTextEditor(app: app, margin: shownDay == today ? nil : shownDay, insertAt: insertAt, embeddedInNavigationStack: true)
                    .environment(\.roomTheme, theme).madarSheetErrorAlert(app).toolbarVisibility(.visible, for: .navigationBar)
            }
            // N04: letters are checked when the diary is open and the app comes to the foreground.
            .onChange(of: scenePhase) { _, phase in
                if phase == .active { aiAvailability = .checking; retry += 1 }
                else if phase == .background { aiComposerOpen = false }
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
                        try await Task.sleep(for: .seconds(30)); displayNow = service.clock();
                        appearance = try service.appearance(shownDay); arc = service.dayArc(shownDay)
                    } catch { break }
                }
            }
            .task(id: pageReloadID) { await loadDiaryPage() }
            .task(id: aiAvailabilityID) {
                guard page != nil, (!analysisText.isEmpty || !intentions.isEmpty) else { aiAvailability = .checking; return }
                aiAvailability = .checking
                aiAvailability = await MadarAIAvailabilityChecker.check()
            }
    }

    @MainActor private func loadDiaryPage() async {
        do {
            guard canReadDiary else { page = nil; aiComposerOpen = false; return }
            if page?.day != shownDay { page = nil; aiComposerOpen = false; aiAvailability = .checking }
            try await service.prepareClosedDay(shownDay)
            guard !Task.isCancelled, canReadDiary else { page = nil; aiComposerOpen = false; return }
            let displayPage = try await service.dayOffMain(shownDay)
            try Task.checkCancellation()
            guard canReadDiary, displayPage.day == shownDay else { return }
            page = displayPage
            intentions = try service.intentions(shownDay)
            arc = service.dayArc(shownDay)
            appearance = try service.appearance(shownDay)
            displayNow = service.clock()
            returnDay = try service.returnAfterAbsence(shownDay)
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
            do {
#if DEBUG
                try injectReadFailureOnce("projects")
#endif
                (projectLinks, projectSuggestions) = ([:], [:])
            } catch {
                projectLinks = [:]; projectSuggestions = [:]
                failure = madarUserMessage(error)
                return
            }
            failure = nil
        } catch is CancellationError {
            return
        } catch {
            page = nil
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
                                intentions = try service.intentions(shownDay); niyyaSaved = true
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
    private var tabs: some View {
        HStack(spacing: 4) {
            dateChoice("اليوم", id: "today", value: today)
            dateChoice("أمس", id: "yesterday", value: today.adding(days: -1))
            dateChoice("قبل سنة", id: "year", value: aYearAgo)
        }.fixedSize()
    }
    private func dateChoice(_ title: String, id: String, value: GregorianDay) -> some View {
        Button {
            selected = value
        } label: {
            Text(title).font(DiaryType.label).frame(minHeight: 44).padding(.horizontal, 10).background(
                shownDay == value ? theme.surface : .clear, in: .rect(topLeadingRadius: 10, topTrailingRadius: 10)
            ).overlay {
                UnevenRoundedRectangle(topLeadingRadius: 10, topTrailingRadius: 10).stroke(
                    shownDay == value ? theme.color("ink3Text") : theme.line)
            }
        }
        .buttonStyle(.madarPlain).accessibilityIdentifier("diary-day-" + id).accessibilityAddTraits(
            shownDay == value ? .isSelected : [])
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
            guard let data = await DiaryPhotoLibrary.data(asset), let copy = DiaryPhotoLibrary.smallCopy(of: data) else { return false }
            do { try await service.appendMedia(data: copy, kind: "photo", contentType: "image/jpeg", day: "today", writingDay: shownDay, assetID: asset.localIdentifier); retry += 1; return true }
            catch { failure = madarUserMessage(error); return false }
        }.padding(.horizontal, 18).padding(.bottom, 10).accessibilityIdentifier("diary-day-photo-strip")
    }
    /// 10 Nov owner: no permanent «اكتب هنا» between every item. Any line is the place to write: its menu (or a tap on a room's own line) writes right after it, in time.
    private func writeAfter(_ line: DiaryDisplayLine, page: DiaryDisplayDay) {
        guard shownDay == today, travel == nil else { return }
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
        if shownDay == today, travel == nil { insertAt = nil; anchorLabel = nil; inlineEdit = .init(id: line.id, text: line.text) }
        else { editing = .init(id: line.id, text: line.text) }
    }
    private func lineRow(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        let auto = ["salah", "quran", "mihbara", "mal", "habits"].contains(line.kind)
        return HStack(alignment: .firstTextBaseline, spacing: 12) {
            Text(service.time(line.at, zone: line.tzID)).font(
                .custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)
            ).foregroundStyle(theme.color("ink3Text")).frame(width: 38, alignment: .center).accessibilityIdentifier(
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
                            "هامش", page.marginDays[line.id].map { service.bothDates($0) } ?? "تاريخ الكتابة غير متاح",
                        ])
                    ).font(DiaryType.label)
                }
            }.foregroundStyle(
                line.kind == "margin"
                    ? secondInk
                    : line.kind == "late" ? theme.color("late") : auto ? theme.color("autoInkText") : theme.ink)
        }.contentShape(Rectangle()).onTapGesture {
            // Tap a line you wrote to change it right there; tap a room's own line (prayer, Quran…) to write after it.
            if page.editable.contains(line.id) { editLine(line) } else { writeAfter(line, page: page) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-entry-" + line.id).overlay {
            if highlightedEntryID?.uuidString == line.id {
                RoundedRectangle(cornerRadius: 12).stroke(theme.accent, lineWidth: 2)
            }
        }.animation(.easeInOut(duration: 0.2), value: highlightedEntryID)
            // FB-39: editing and deleting a line lived only in a long press; a quiet «⋯» shows that the line can be changed.
            .overlay(alignment: .topTrailing) {
                if page.editable.contains(line.id) || page.deletable.contains(line.id) {
                    Menu { lineActions(line, page: page) } label: {
                        Image(systemName: "ellipsis").font(.footnote).foregroundStyle(theme.color("ink3Text"))
                            .frame(width: 36, height: 30).contentShape(Rectangle())
                    }.accessibilityLabel("خيارات السطر").accessibilityIdentifier("diary-line-menu").offset(x: 14, y: 2)
                }
            }
            .contextMenu { lineActions(line, page: page) }.padding(.leading, 6).padding(.trailing, travel == nil || typeSize.isAccessibilitySize ? 18 : 92).padding(
                .vertical, 10
            ).frame(minHeight: 34)
    }
    @ViewBuilder private func lineActions(_ line: DiaryDisplayLine, page: DiaryDisplayDay) -> some View {
        if shownDay == today, travel == nil {
            Button("اكتب بعده", systemImage: "text.append") { writeAfter(line, page: page) }.accessibilityIdentifier("diary-line-write-after")
        }
        if !line.text.isEmpty { Button("انسخ", systemImage: "doc.on.doc") { UIPasteboard.general.string = line.text } }
        if page.editable.contains(line.id) {
            Button("عدّل السطر", systemImage: "pencil") { editing = .init(id: line.id, text: line.text) }
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
                    do { try await service.saveIntention(line.text, day: shownDay); niyyaSaved = true } catch {
                        failure = madarUserMessage(error)
                    }
                }
            }
        }
    }
    private func revealInitialEntry(using proxy: ScrollViewProxy) {
        guard let initialEntryID,
            page?.lines.contains(where: { $0.id == initialEntryID.uuidString }) == true
        else { return }
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
