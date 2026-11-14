import SwiftUI
import UIKit
import MadarCore
import MadarDesign

enum DiaryType {
    static let title = Font.custom("thmanyahserifdisplay-Bold", size: 28, relativeTo: .largeTitle)
    static let heading = Font.custom("thmanyahserifdisplay-Bold", size: 21, relativeTo: .title2)
    static let writing = Font.custom("thmanyahseriftext-Regular", size: 19, relativeTo: .body)
    static let label = Font.custom("thmanyahsans-Regular", size: 12, relativeTo: .caption)
}
struct DiaryRoomView: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var outerTheme
    var body: some View {
        DiaryLaunchView(app: app)
        .environment(\.roomTheme, RoomTheme(room: "notes", dark: outerTheme.dark, calmPaper: app.string("core.roomIdentity") == "calmPaper"))
    }
}
private struct DiaryRootDraftBlocking: ViewModifier {
    @Bindable var app: AppSession
    let isBlocking: Bool
    @State private var blockerID = UUID()
    func body(content: Content) -> some View {
        content
            .onChange(of: isBlocking, initial: true) { _, blocked in app.setDiaryRootDraftBlocker(blockerID, active: blocked) }
            .onDisappear { app.setDiaryRootDraftBlocker(blockerID, active: false) }
    }
}
extension View {
    func diaryRootDraftBlocking(_ app: AppSession, isBlocking: Bool = true) -> some View {
        modifier(DiaryRootDraftBlocking(app: app, isBlocking: isBlocking))
    }
}
struct DiaryHomeView: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @Environment(\.roomVisit) private var roomVisit
    @Environment(\.isFrontRoom) private var isFrontRoom
    @Environment(\.horizontalSizeClass) private var sizeClass
    @State private var roomWidth: CGFloat = 0
    /// False once today's card has scrolled out of sight: the bottom bar then offers the same write control.
    @State private var todayCardVisible = true
    @State private var todayIntention: String?
    private var wide: Bool { isPadWide(sizeClass) && roomWidth >= 960 }
    private var rootToday: Bool { rootEnabled && !wide && snapshot != nil && failure == nil }
    /// Shipping behaviour: the room opens on today's page. The legacy home-first suites run with the flag off; the root has its own suite (`MADAR_UI_DIARY_ROOT=1`).
    private var rootEnabled: Bool {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if environment["MADAR_UI_STORE_ID"] != nil { return environment["MADAR_UI_DIARY_ROOT"] == "1" }
#endif
        return true
    }
    private struct RootParams { var entryID: UUID?; var routeID: UUID?; var focus = false; var prompt: String?; var expand = false; var preset: String?; var token = UUID() }
    @State private var rootParams = RootParams()
    @State private var stripPull: CGFloat = 0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var snapshot: DiaryHomeSnapshot?
    @State private var customizing = false
    @State private var archiveOpen = false
    @State private var searchOpen = false
    @State private var queuedDiaryRoute: Route?
    @State private var reader: GregorianDay?
    /// Set by the write buttons: the day page opens with the cursor already in its one writing field.
    @State private var focusReaderComposer = false
    @State private var readerPrompt: String?
    @State private var readerPreset: String?
    @State private var readerExpandComposer = false
    @State private var pendingDiaryRootRequestID: UUID?
    @State private var readerEntryID: UUID?
    @State private var routedHubTab: String?
    @State private var routedLetterID: UUID?
    @State private var routedLetterRequestID: UUID?
    @State private var routedSearchQuery: String?
    @State private var routedSearchRequestID: UUID?
    @State private var readerEntryRouteID: UUID?
    @State private var failure: String?
    @State private var intentionFollowUp: DiaryIntentionFollowUp?
#if DEBUG
    @State private var injectedReadFailure = false
#endif
    @State private var refreshGeneration = 0
    private var service: AppDiaryService { AppDiaryService(app: app) }
    var body: some View {
        VStack(spacing: 0) {
            if rootToday, let snapshot {
                // 14 Nov owner (T10): the room opens on today's page itself; nothing is pushed over a home.
                if !typeSize.isAccessibilitySize, let past = yearStripPage(snapshot) { yearStrip(past, snapshot: snapshot) }
                DiaryDayView(app: app, day: snapshot.today, initialEntryID: rootParams.entryID, initialEntryRouteID: rootParams.routeID,
                             embeddedInNavigationStack: true, focusComposerOnOpen: rootParams.focus, prompt: rootParams.prompt,
                             expandComposerOnOpen: rootParams.expand, onCustomize: { customizing = true }, writeDayPreset: rootParams.preset)
                             .task(id: rootParams.token) { if rootParams.preset != nil { guard (try? await Task.sleep(for: .seconds(5))) != nil else { return }; rootParams.preset = nil } }
                    .id(rootParams.token).environment(\.roomTheme, theme)
            } else if rootEnabled && !wide && snapshot == nil && failure == nil {
                ProgressView("تُفتح صفحتك…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
            header.padding(.horizontal, 14).padding(.top, 8)
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot {
                    if let intentionFollowUp { intentionFollowUpCard(intentionFollowUp) }
                    if wide {
                        // iPad, wide: today stands on the right, the years strip and the recent days run beside it.
                        HStack(alignment: .top, spacing: 28) {
                            todayCard(snapshot).frame(width: 440)
                            VStack(alignment: .leading, spacing: 14) { homeBlocks(snapshot) }.frame(maxWidth: .infinity, alignment: .leading)
                        }
                    } else {
                        todayCard(snapshot)
                        homeBlocks(snapshot)
                    }
                    DiaryQuestionsCard(app: app) { question in writeToday(snapshot.today, prompt: question) }
                } else if let failure {
                    VStack(alignment: .leading, spacing: 10) {
                        Text(failure).font(DiaryType.writing)
                        Button { Task { await refresh(retrying: true) } } label: { Text("حاول مرة أخرى").frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-home-retry")
                    }
                }
                else { ProgressView("تُفتح صفحتك…") }
            }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
            .frame(maxWidth: !isPadWide(sizeClass) ? .infinity : wide ? 1100 : 720).frame(maxWidth: .infinity)
            }
            }
        }
        .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        .background(theme.background).foregroundStyle(theme.ink)
        .safeAreaInset(edge: .bottom, spacing: 0) {
            // The write control lives in today's card; the bar only stands in for it once the card has scrolled away (never two on screen).
            if let snapshot, !todayCardVisible, !wide, !rootToday {
                todayBar(snapshot.todayPage).ignoresSafeArea(.keyboard, edges: .bottom).transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .madarAnimation(.quick, value: todayCardVisible)
        .scrollDismissesKeyboard(.interactively)
        .toolbarVisibility(rootToday ? .visible : .hidden, for: .navigationBar)
        .task(id: [isFrontRoom ? app.prayerRevision : -1, roomVisit]) {
            guard isFrontRoom else { return }
            await refresh()
            #if DEBUG
            let environment = ProcessInfo.processInfo.environment
            if environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
               environment["MADAR_UI_DIARY_HOME_READ_FAILURE_AFTER_FIRST"] == "1" {
                await refresh()
            }
            #endif
        }
        .task(id: isFrontRoom) {
            guard isFrontRoom else { return }
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                guard isFrontRoom, !Task.isCancelled else { break }
                if let previous = snapshot?.today, let current = try? await service.currentDayOffMain(), current != previous {
                    try? await service.prepareClosedDay(previous)
                    await refresh()
                }
            }
        }
        .fullScreenCover(isPresented: $searchOpen, onDismiss: { routedSearchQuery = nil; routedSearchRequestID = nil; applyPendingDiaryRootIfReady() }) { DiarySearchView(app: app, initialQuery: routedSearchQuery, initialQueryRequestID: routedSearchRequestID).environment(\.roomTheme, theme) }
        .fullScreenCover(isPresented: $archiveOpen, onDismiss: { clearHubRoute(); applyPendingDiaryRootIfReady() }) {
            DiaryHubView(app: app, initialTab: routedHubTab, initialLetterID: routedLetterID,
                initialLetterRequestID: routedLetterRequestID)
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app)
        }
        .sheet(isPresented: $customizing, onDismiss: { Task { await refresh() }; applyPendingDiaryRootIfReady() }) { DiaryCustomizeView(app: app).environment(\.roomTheme, theme).madarSheetErrorAlert(app) }
        .navigationDestination(item: $reader) { day in
            DiaryDayView(app: app, day: day, initialEntryID: readerEntryID, initialEntryRouteID: readerEntryRouteID, embeddedInNavigationStack: true, focusComposerOnOpen: focusReaderComposer, prompt: readerPrompt, expandComposerOnOpen: readerExpandComposer, writeDayPreset: readerPreset)
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app).toolbarVisibility(.visible, for: .navigationBar)
                .hidesRoomAccessory(app, id: "diary-day-destination")
        }
        .onChange(of: rootToday) { _, on in
            if on {
                // A route that arrived before the first load pushed nothing yet to show: hand it to the root instead of a second copy of today.
                if let r = reader, r == snapshot?.today {
                    rootParams = RootParams(entryID: readerEntryID, routeID: readerEntryRouteID, focus: focusReaderComposer, prompt: readerPrompt, expand: readerExpandComposer, preset: readerPreset)
                    reader = nil
                }
            } else {
                // A recreated root page must not replay an old request.
                rootParams.focus = false; rootParams.preset = nil; rootParams.prompt = nil; rootParams.entryID = nil; rootParams.routeID = nil; rootParams.expand = false
            }
        }
        .onChange(of: reader) { old, new in
            if rootToday, let new, new == snapshot?.today {
                // Today is the root page: the same request (entry, prompt, cursor) is handed to it instead of pushing a second copy.
                rootParams = RootParams(entryID: readerEntryID, routeID: readerEntryRouteID, focus: focusReaderComposer, prompt: readerPrompt, expand: readerExpandComposer, preset: readerPreset)
                reader = nil
                return
            }
            if old != nil, new == nil {
                readerEntryID = nil; readerEntryRouteID = nil; focusReaderComposer = false; readerPrompt = nil; readerPreset = nil; readerExpandComposer = false
                applyPendingDiaryRootIfReady()
            }
        }
        .onChange(of: app.diaryRoute, initial: true) { _, route in
            guard let route else { return }; app.diaryRoute = nil
            if !app.diaryRootDraftBlockers.isEmpty {
                queuedDiaryRoute = route
                return
            }
            openDiaryRoute(route)
        }
        .onChange(of: app.diaryRootRequestID, initial: true) { _, requestID in
            guard let requestID else { pendingDiaryRootRequestID = nil; return }
            pendingDiaryRootRequestID = requestID
            applyPendingDiaryRootIfReady()
        }
        .onChange(of: app.diaryRootDraftBlockers) { _, _ in
            applyPendingDiaryRootIfReady()
            applyQueuedDiaryRouteIfReady()
        }
        .onChange(of: app.searchRoute, initial: true) { _, route in
            guard let route, route.parameters["room"] == nil || route.parameters["room"] == "notes" else { return }
            app.searchRoute = nil
            routedSearchQuery = route.parameters["q"] ?? ""
            routedSearchRequestID = UUID()
            searchOpen = true
        }
    }
    private func clearHubRoute() { routedHubTab = nil; routedLetterID = nil; routedLetterRequestID = nil }
    private func applyQueuedDiaryRouteIfReady() {
        guard pendingDiaryRootRequestID == nil,
              app.diaryRootDraftBlockers.isEmpty, let route = queuedDiaryRoute else { return }
        queuedDiaryRoute = nil
        openDiaryRoute(route)
    }
    private func openDiaryRoute(_ route: Route) {
        if route.path.first == "write", route.path.count == 1 {
            let day = route.parameters["day"] ?? "today"
            // Today is written on today's page, with the composer already grown; «أمس» is the same composer started on that day.
            if let today = try? service.currentDay() { writeToday(today, expand: true, preset: day == "today" ? nil : day) }
        }
        else if route.path.first == "day", let key = route.path.last, let day = try? GregorianDay(key) {
            readerEntryID = nil; readerEntryRouteID = nil; reader = day
        }
        else if route.path.first == "entry", route.path.count == 2, let rawID = route.path.last, let id = UUID(uuidString: rawID) {
            do {
                guard let day = try service.entryDay(id) else { app.errorMessage = "هذا السطر لم يعد موجودًا في مذكراتك."; return }
                readerEntryID = id; readerEntryRouteID = UUID(); reader = day
            } catch { app.errorMessage = madarUserMessage(error) }
        }
        else if route.path.first == "letters" { routedHubTab = "letters"; archiveOpen = true }
        else if route.path.first == "letter", route.path.count == 2, let rawID = route.path.last, let id = UUID(uuidString: rawID) {
            routedHubTab = "letters"; routedLetterID = id; routedLetterRequestID = UUID(); archiveOpen = true
        }
        else if route.path.first == "project", route.path.count == 2, let rawID = route.path.last, let id = UUID(uuidString: rawID) {
            _ = id // Projects left the app (owner, 5 Nov 2026); an old link opens the diary itself.
        }
        else if route.path.first == "today" { readerEntryID = nil; readerEntryRouteID = nil; reader = try? service.currentDay() }
    }
    private func applyPendingDiaryRootIfReady() {
        guard let requestID = pendingDiaryRootRequestID,
              app.diaryRootRequestID == requestID,
              app.diaryRootDraftBlockers.isEmpty else { return }
        pendingDiaryRootRequestID = nil
        app.diaryRootRequestID = nil
        queuedDiaryRoute = nil
        searchOpen = false
        archiveOpen = false
        customizing = false
        reader = nil
        readerEntryID = nil
        readerEntryRouteID = nil
        clearHubRoute()
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                // Today's date lives in the today card right below; repeating it here said the same thing twice.
                Text("المذكرات").font(DiaryType.title).accessibilityIdentifier("diary-home-title")
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { searchOpen = true } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("ابحث في مذكراتك").accessibilityIdentifier("diary-search")
            Button { archiveOpen = true } label: { Image(systemName: "calendar").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("أيامك").accessibilityIdentifier("diary-days")
            Button { customizing = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }
                .buttonStyle(.madarPlain).accessibilityLabel("خصّص المذكرات").accessibilityIdentifier("diary-customize")
        }.padding(.vertical, 4)
    }
    /// The two blocks below today's card, in the order the owner chose in the customize screen.
    @ViewBuilder private func homeBlocks(_ snapshot: DiaryHomeSnapshot) -> some View {
        ForEach(blocks, id: \.self) { block in
            switch block {
            case "memory": if !hidden("memory") { years(snapshot) }
            case "days": if !hidden(block) { recentDays(snapshot) }
            default: EmptyView()
            }
        }
    }

    // MARK: Today

    /// 12 Nov, owner: the home opens on today's page, alive: both dates, the intention, the latest lines, the day's photos and the one write control.
    /// A tap anywhere on the card opens the page; the write capsule opens it with the cursor in the composer.
    private func todayCard(_ snapshot: DiaryHomeSnapshot) -> some View {
        let day = snapshot.todayPage
        let lines = day.lines.filter { $0.kind != "intention" && !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.suffix(3)
        let travelling = (try? service.travel(day.day)) != nil
        let empty = lines.isEmpty && day.media.isEmpty && day.photo == nil && !travelling
        let auto: Set<String> = ["salah", "quran", "mihbara", "mal", "habits"]
        return VStack(alignment: .leading, spacing: 12) {
            MadarDateLabel(app.dateLabels(day.day, weekday: true), primaryFont: DiaryType.heading, secondaryFont: DiaryType.label)
                .accessibilityIdentifier("diary-today-date")
            if let todayIntention {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text("النيّة").font(DiaryType.label).foregroundStyle(theme.color("accentText"))
                    Text(todayIntention).font(DiaryType.writing).lineLimit(2).frame(maxWidth: .infinity, alignment: .leading)
                }.accessibilityIdentifier("diary-today-intention")
            }
            if empty {
                Text("صفحة اليوم تنتظر سطرك الأول.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-today-invitation")
            } else {
                VStack(alignment: .leading, spacing: 6) {
                    ForEach(Array(lines)) { line in
                        let isAuto = auto.contains(line.kind)
                        HStack(alignment: .firstTextBaseline, spacing: 10) {
                            Text(service.time(line.at, zone: line.tzID)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(width: 46, alignment: .center)
                            Text(line.markdown == true ? DayOneMarkdown.plain(line.text) : line.text)
                                .font(.custom("thmanyahseriftext-Regular", size: isAuto ? 15 : 17, relativeTo: .body)).italic(isAuto).lineLimit(2)
                                .foregroundStyle(isAuto ? theme.color("autoInkText") : theme.ink).frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }.accessibilityIdentifier("diary-today-lines")
                recentMedia(day)
            }
            HStack {
                Spacer(minLength: 0)
                Button { writeToday(day.day) } label: {
                    Label(empty ? "اكتب سطرك الأول" : "اكتب", systemImage: "pencil").font(MadarTypography.section())
                        .padding(.horizontal, 20).frame(minHeight: 48).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-write")
            }
        }
        .padding(16).frame(maxWidth: .infinity, alignment: .leading)
        .background {
            Button { reader = day.day } label: {
                RoundedRectangle(cornerRadius: 24).fill(theme.surface).overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.line) }
            }.buttonStyle(.madarPlain).accessibilityLabel("صفحة اليوم").accessibilityIdentifier("diary-today")
        }
        .onScrollVisibilityChange(threshold: 0.2) { visible in todayCardVisible = visible }
    }

    /// «في مثل هذا اليوم»: one compact strip of year cards, newest year first; a year with neither words nor a photo is skipped; a card opens that day.
    @ViewBuilder private func years(_ snapshot: DiaryHomeSnapshot) -> some View {
        let pages = snapshot.selection.days.compactMap { day in snapshot.days.first { $0.day == day } }
            .filter { page in page.photo != nil || page.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        if !pages.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(snapshot.selection.match == .echo ? "أقرب ما كتبتَه إلى اليوم" : "في مثل هذا اليوم").font(DiaryType.heading).lineLimit(1).minimumScaleFactor(0.8)
                    Spacer()
                    HStack(spacing: 2) { calendarButton(.gregorian, "بالميلادي"); calendarButton(.hijri, "بالهجري") }
                        .padding(3).background(theme.ink.opacity(0.06), in: .capsule)
                }
                ScrollView(.horizontal) {
                    HStack(alignment: .top, spacing: 10) {
                        ForEach(pages) { page in yearCard(page, snapshot: snapshot) }
                    }.padding(.vertical, 2)
                }.scrollIndicators(.hidden).accessibilityIdentifier("diary-years")
            }
        }
    }
    /// The page a year (or the nearest match) ago that has something written or a photo; the strip over today's page shows it.
    private func yearStripPage(_ snapshot: DiaryHomeSnapshot) -> DiaryDisplayDay? {
        snapshot.selection.days.compactMap { day in snapshot.days.first { $0.day == day } }
            .first { page in page.photo != nil || page.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }
    /// 96 pt: the photo dimmed, one line over it. A pull down stretches it toward the full window and a long pull (or a tap) opens that page.
    private func yearStrip(_ page: DiaryDisplayDay, snapshot: DiaryHomeSnapshot) -> some View {
        let height = 96 + stripPull
        return ZStack(alignment: .bottomLeading) {
            if let data = page.photo {
                DiaryDataThumbnail(data: data, maxPixel: 900) { image in
                    image.resizable().scaledToFill().frame(maxWidth: .infinity).frame(height: height).clipped().overlay(theme.background.opacity(0.55 - Double(stripPull) / 800))
                }.id(page.photoID?.uuidString ?? page.id)
            } else { Rectangle().fill(theme.surface) }
            VStack(alignment: .leading, spacing: 2) {
                Text(service.distance(page.day, snapshot.today) + ": " + page.excerpt).font(.custom("thmanyahseriftext-Regular", size: 16, relativeTo: .body)).lineLimit(stripPull > 40 ? 3 : 1)
                MadarDateLabel(app.dateLabels(page.day)).foregroundStyle(theme.color("ink3Text"))
            }.padding(.horizontal, 16).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(height: height).frame(maxWidth: .infinity).clipped().contentShape(Rectangle())
        .onDisappear { stripPull = 0 }
        .onTapGesture { reader = page.day }
        .gesture(DragGesture(minimumDistance: 8)
            .onChanged { value in
                // Reduce Motion: no stretch, the gesture still opens the page.
                if !reduceMotion, value.translation.height > 0 { stripPull = min(260, value.translation.height * 0.9) }
            }
            .onEnded { value in
                let open = value.translation.height > 110
                withAnimation(reduceMotion ? nil : .snappy(duration: 0.25)) { stripPull = 0 }
                if open { reader = page.day }
            })
        .accessibilityElement(children: .combine).accessibilityAddTraits(.isButton).accessibilityIdentifier("diary-year-strip")
    }
    private func calendarButton(_ calendar: FirstCalendar, _ title: String) -> some View {
        Button { app.set(.string(calendar.rawValue), key: "notes.match") { Task { await refresh() } } } label: {
            Text(title).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background { if service.preferredMatch == calendar { Capsule().fill(theme.surface.opacity(0.6)).glassEffect(.regular.interactive(), in: .capsule) } }
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-match-" + calendar.rawValue)
    }
    private func yearCard(_ page: DiaryDisplayDay, snapshot: DiaryHomeSnapshot) -> some View {
        Button { reader = page.day } label: {
            HStack(alignment: .top, spacing: 10) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(service.distance(page.day, snapshot.today)).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)).foregroundStyle(theme.color("accentText"))
                    MadarDateLabel(app.dateLabels(page.day)).foregroundStyle(theme.color("ink3Text"))
                    Text(page.excerpt).font(.custom("thmanyahseriftext-Regular", size: 16, relativeTo: .body)).lineSpacing(4).lineLimit(2).multilineTextAlignment(.leading)
                    // A photo the import did not carry is named, never invented.
                    if page.photo == nil, page.missingPhotos > 0 { Label(page.missingPhotos == 1 ? "صورة هذا اليوم لم تُنقل" : page.missingPhotos == 2 ? "صورتا هذا اليوم لم تُنقلا" : "صور هذا اليوم لم تُنقل", systemImage: "photo.on.rectangle.angled").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let data = page.photo, !typeSize.isAccessibilitySize {
                    DiaryDataThumbnail(data: data, maxPixel: 144) { image in
                        image.resizable().scaledToFill().frame(width: 52, height: 64).clipShape(.rect(cornerRadius: 10)).accessibilityHidden(true)
                    }.id(page.photoID?.uuidString ?? page.id).frame(width: 52, height: 64)
                }
            }.padding(14).frame(width: typeSize.isAccessibilitySize ? 300 : 260, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line) }
                .contentShape(.rect(cornerRadius: 20))
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-year-" + page.day.description)
    }
    /// «أيامك» appears once a past day exists; before that the bottom bar and the first-page card are the only way in.
    @ViewBuilder private func recentDays(_ snapshot: DiaryHomeSnapshot) -> some View {
        if snapshot.days.contains(where: { $0.day < snapshot.today }) { recentDaysList(snapshot) }
    }
    private func recentDaysList(_ snapshot: DiaryHomeSnapshot) -> some View {
        let days = snapshot.days.filter { $0.day < snapshot.today }.prefix(5)
        let month = service.monthLabels(snapshot.today)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
            Button { archiveOpen = true } label: { HStack { Text("أيامك").font(DiaryType.heading); Image(systemName: "arrow.left").font(.caption) } }.buttonStyle(.madarPlain)
                Spacer()
                VStack(alignment: .leading, spacing: 2) {
                    Text(month.primary).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    Text(month.secondary).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(month.combined)
                .accessibilityIdentifier("diary-current-month")
            }.padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(days)) { day in
                    Button { reader = day.day } label: {
                        HStack(spacing: 14) {
                            VStack(spacing: 2) {
                                MadarDateLabel(app.dateLabels(day.day, compact: true)).frame(width: 80, alignment: .leading)
                                Text(service.weekday(day.day)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text"))
                            }.frame(minWidth: 35)
                            Text(day.excerpt).font(.custom("thmanyahseriftext-Regular", size: 17, relativeTo: .body)).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                            recentMedia(day)
                        }.padding(16)
                    }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-recent-" + day.day.description)
                    if day.id != days.last?.id { Divider().overlay(theme.line) }
                }
            }.background(theme.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-recent-days")
    }
    @ViewBuilder private func recentMedia(_ day: DiaryDisplayDay) -> some View {
        let hasPagePhoto = day.photo != nil && !day.media.contains(where: { $0.id == day.photoID })
        let media = Array(day.media.suffix(3))
        if hasPagePhoto || !media.isEmpty {
            HStack(spacing: 4) {
                if hasPagePhoto, let data = day.photo {
                    DiaryDataThumbnail(data: data, maxPixel: 120) { $0.resizable().scaledToFill().frame(width: 36, height: 36).clipShape(.rect(cornerRadius: 8)) }
                        .id(day.photoID?.uuidString ?? day.id).frame(width: 36, height: 36)
                }
                ForEach(media) { item in
                    Group {
                        if item.kind == "photo" {
                            DiaryDataThumbnail(data: item.data, maxPixel: 120) { $0.resizable().scaledToFill().frame(width: 36, height: 36).clipShape(.rect(cornerRadius: 8)) }
                        } else {
                            Image(systemName: item.kind == "audio" ? "waveform" : item.kind == "video" ? "play.rectangle" : "doc")
                                .font(.system(size: 15, weight: .medium)).foregroundStyle(theme.accent)
                                .frame(width: 36, height: 36).background(theme.background, in: .rect(cornerRadius: 8))
                        }
                    }.id(item.id)
                }
                let total = day.media.count + (hasPagePhoto ? 1 : 0)
                if total > 3 { Text("+" + service.digits.string(total - 3)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk) }
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("مرفقات هذا اليوم، " + service.digits.string(day.media.count))
            .accessibilityIdentifier("diary-recent-media-" + day.day.description)
        }
    }
    /// One place to write: today's page, with its field focused. The full page (camera, files, formatting) is one tap from there.
    private func writeToday(_ day: GregorianDay, prompt: String? = nil, expand: Bool = false, preset: String? = nil) {
        readerPreset = preset
        readerPrompt = prompt
        readerExpandComposer = expand
        focusReaderComposer = true
        reader = day
    }
    /// 12 Nov: one control (it used to be two that opened the same page). A tap opens today's page with the cursor in the composer;
    /// the latest line and its time say what is already there.
    private func todayBar(_ day: DiaryDisplayDay) -> some View {
        todayButton(day).padding(.horizontal, 14).padding(.vertical, 8).background(theme.background)
    }
    private func todayButton(_ day: DiaryDisplayDay) -> some View {
        let travelling = (try? service.travel(day.day)) != nil
        let empty = day.lines.isEmpty && day.media.isEmpty && day.photo == nil && !travelling
        let latest = day.lines.last(where: { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
        return Button { writeToday(day.day) } label: {
            HStack(spacing: 12) {
                Image(systemName: "pencil").font(.system(size: 18, weight: .semibold))
                if empty {
                    Text("اكتب سطرك الأول اليوم").font(MadarTypography.section())
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("اكتب في صفحة اليوم").font(MadarTypography.section())
                        if let latest {
                            Text("آخرها " + service.time(latest.at, zone: latest.tzID) + "، " + (latest.markdown == true ? DayOneMarkdown.plain(latest.text) : latest.text))
                                .font(DiaryType.label).lineLimit(1).opacity(0.85)
                        }
                    }
                }
                Spacer(minLength: 0)
            }.padding(.horizontal, 22).frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                .foregroundStyle(theme.background).background(theme.ink, in: .capsule)
        }.buttonStyle(.madarPlain).accessibilityIdentifier(empty ? "diary-write" : "diary-today")
    }
    private var blocks: [String] { DiaryHomeLayout(app.values["notes.layout"]).order }
    private func hidden(_ block: String) -> Bool { app.values["notes.layout"]?.object?["hidden"]?.array?.contains(.string(block)) == true }
    private func refresh(retrying: Bool = false) async {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let inject = environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil
            && environment["MADAR_UI_DIARY_HOME_READ_FAILURE_AFTER_FIRST"] == "1"
        if inject, injectedReadFailure, !retrying { return }
#endif
        guard !Task.isCancelled else { return }
        refreshGeneration += 1
        let generation = refreshGeneration
        do {
#if DEBUG
            if inject {
                if injectedReadFailure {
                    guard retrying else { return }
                } else if snapshot != nil {
                    injectedReadFailure = true
                    throw CocoaError(.fileReadUnknown)
                }
            }
#endif
            var value = try await service.homeOffMain()
            let displayed = value.selection.days
            let changed = try await service.prepareClosedDays(Set(displayed))
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            if changed {
                value = try await service.homeOffMain()
                guard generation == refreshGeneration, !Task.isCancelled else { return }
            }
            snapshot = value; failure = nil
            todayIntention = (try? service.intentions(value.today))?.first?.text
            if let pendingFollowUps = try? await service.dueIntentionFollowUpsOffMain() {
                guard generation == refreshGeneration, !Task.isCancelled else { return }
                let next = pendingFollowUps.first
                intentionFollowUp = next
            }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            snapshot = nil
            failure = madarUserMessage(error)
        }
    }
    private func intentionFollowUpCard(_ item: DiaryIntentionFollowUp) -> some View {
        // Its own view with its own text: a keystroke here no longer redraws the whole home page.
        IntentionReviewCard(app: app, item: item, saved: { intentionFollowUp = $0 })
            .id("\(item.id)-\(item.period)")
    }
}

/// The follow-up of an intention (week or month): the original words, one question and a field for the answer.
private struct IntentionReviewCard: View {
    @Bindable var app: AppSession
    let item: DiaryIntentionFollowUp
    let saved: (DiaryIntentionFollowUp?) -> Void
    @Environment(\.roomTheme) private var theme
    @State private var reviewText = ""
    @State private var saving = false
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var empty: Bool { !reviewText.contains { !$0.isWhitespace } }
    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline) {
                Text(item.period.title).font(DiaryType.heading)
                Spacer()
                Text(service.bothDates(item.writtenDay, calendar: app.diaryFirstCalendar)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
            }
            Text(item.intention).font(DiaryType.writing).frame(maxWidth: .infinity, alignment: .leading)
            Text(item.period.question).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
            TextField("اكتب مراجعتك هنا", text: $reviewText, axis: .vertical)
                .lineLimit(2...5).font(DiaryType.writing).padding(12)
                .background(theme.background, in: .rect(cornerRadius: 12))
                .accessibilityIdentifier("diary-intention-review-text")
            Button {
                guard !saving, !empty else { return }
                saving = true
                Task { @MainActor in
                    defer { saving = false }
                    do {
                        try await service.setIntentionReview(item.id, period: item.period, text: reviewText)
                        reviewText = ""
                        saved(try await service.dueIntentionFollowUpsOffMain().first)
                    } catch { app.errorMessage = madarUserMessage(error) } // the home's own `failure` shows only while nothing is loaded, so a failed save would stay silent
                }
            } label: {
                HStack {
                    if saving { ProgressView().tint(theme.background) }
                    Text("احفظ المراجعة")
                }.font(DiaryType.label).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(theme.background)
                    .background(theme.accent, in: .capsule)
            }.buttonStyle(.madarPlain).disabled(saving || empty)
                .accessibilityIdentifier("diary-intention-review-save")
        }
        .padding(16).background(theme.surface, in: .rect(cornerRadius: 20)).overlay { RoundedRectangle(cornerRadius: 20).stroke(theme.line) }
        .accessibilityElement(children: .contain).accessibilityIdentifier("diary-intention-follow-up")
        .diaryRootDraftBlocking(app, isBlocking: !reviewText.isEmpty || saving)
    }
}
