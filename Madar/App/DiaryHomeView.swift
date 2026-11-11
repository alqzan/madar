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
private struct DiaryEditorTarget: Identifiable, Hashable {
    var id: String { margin.map { "margin-\($0.description)" } ?? "write-\(day)" }
    let margin: GregorianDay?
    var day = "today"
    var prompt: String?
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
    private var wide: Bool { isPadWide(sizeClass) && roomWidth >= 960 }
    @State private var snapshot: DiaryHomeSnapshot?
    @State private var selected: GregorianDay?
    @State private var customizing = false
    @State private var archiveOpen = false
    @State private var searchOpen = false
    @State private var editor: DiaryEditorTarget?
    @State private var queuedDiaryRoute: Route?
    @State private var reader: GregorianDay?
    @State private var pendingDiaryRootRequestID: UUID?
    @State private var readerEntryID: UUID?
    @State private var routedHubTab: String?
    @State private var routedLetterID: UUID?
    @State private var routedLetterRequestID: UUID?
    @State private var routedSearchQuery: String?
    @State private var routedSearchRequestID: UUID?
    @State private var readerEntryRouteID: UUID?
    @State private var failure: String?
    @State private var defaultMemoryDay: GregorianDay?
    @State private var intentionFollowUp: DiaryIntentionFollowUp?
#if DEBUG
    @State private var injectedReadFailure = false
#endif
    @State private var refreshGeneration = 0
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var memory: DiaryDisplayDay? {
        guard let snapshot else { return nil }
        guard let day = selected ?? defaultMemoryDay ?? snapshot.selection.days.first else { return nil }
        return snapshot.days.first { $0.day == day }
    }
    /// Tour 25 Oct on the owner's data: the nearest year was a page with neither words nor a moved photo, so the
    /// memory opened on «صورة هذا اليوم لم تُنقل». It now opens on the nearest year that has something to show.
    private func preferredOpeningDay(in snapshot: DiaryHomeSnapshot, pages: [String: DiaryDisplayDay]) -> GregorianDay? {
        snapshot.selection.days.first { day in
            pages[day.description].map { page in page.photo != nil || page.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } } ?? false
        } ?? snapshot.selection.days.first
    }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8)
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot {
                    if let intentionFollowUp { intentionFollowUpCard(intentionFollowUp) }
                    if app.string("notes.homeShape") == "echoes" {
                        DiaryEchoesView(snapshot: snapshot, service: service, open: { reader = $0 })
                        if !hidden("days") { recentDays(snapshot) }
                    } else if app.string("notes.homeShape") == "margin", let memory {
                        DiaryMarginView(page: memory, snapshot: snapshot, service: service, showAuto: app.bool("notes.showAutoSections"), showLines: !hidden("thatDay"), ink: secondInk,
                            another: snapshot.selection.days.count > 1 ? { nextMemory(snapshot) } : nil, open: { reader = memory.day })
                        if !memory.dayOne, !hidden("sinceThatDay") { since(memory) }
                        if !hidden("days") { recentDays(snapshot) }
                    } else {
                    if wide {
                        // iPad, wide: the years stand on the right and the recent days run beside them.
                        HStack(alignment: .top, spacing: 28) {
                            VStack(alignment: .leading, spacing: 14) {
                    // A brand-new diary has no years to switch between: the first-page card below is the only thing to read (owner, 4 Nov).
                    if snapshot.days.contains(where: { $0.photo != nil || $0.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }) {
                    HStack {
                        Text(snapshot.selection.match == .echo ? "أقرب ما كتبتَه إلى اليوم" : "هذا اليوم عبر السنين").font(DiaryType.heading).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        HStack(spacing: 2) {
                            calendarButton(.gregorian, "بالميلادي")
                            calendarButton(.hijri, "بالهجري")
                        }.padding(3).background(theme.ink.opacity(0.06), in: .capsule)
                    }
                    }
                                if blocks.contains("memory") { years(snapshot) }
                            }.frame(maxWidth: .infinity, alignment: .leading)
                            if blocks.contains("days"), !hidden("days") { recentDays(snapshot).frame(width: 380) }
                        }
                    } else {
                    // A brand-new diary has no years to switch between: the first-page card below is the only thing to read (owner, 4 Nov).
                    if snapshot.days.contains(where: { $0.photo != nil || $0.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }) {
                    HStack {
                        Text(snapshot.selection.match == .echo ? "أقرب ما كتبتَه إلى اليوم" : "هذا اليوم عبر السنين").font(DiaryType.heading).lineLimit(1).minimumScaleFactor(0.8)
                        Spacer()
                        HStack(spacing: 2) {
                            calendarButton(.gregorian, "بالميلادي")
                            calendarButton(.hijri, "بالهجري")
                        }.padding(3).background(theme.ink.opacity(0.06), in: .capsule)
                    }
                    }
                    ForEach(blocks, id: \.self) { block in
                        switch block {
                        // OR-10 (owner picked mockup A, 26 Oct): one card per past year replaces the year drag, «ذاك اليوم» and «منذ ذاك اليوم».
                        case "memory": years(snapshot)
                        case "days": if !hidden(block) { recentDays(snapshot) }
                        default: EmptyView()
                        }
                    }
                    }
                    }
                    DiaryQuestionsCard(app: app) { question in editor = .init(margin: nil, day: "today", prompt: question) }
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
            .onGeometryChange(for: CGFloat.self) { $0.size.width } action: { roomWidth = $0 }
        }
        .background(theme.background).foregroundStyle(theme.ink)
         .safeAreaInset(edge: .bottom, spacing: 0) {
            if let snapshot {
                Group {
                    if app.string("notes.homeShape") == "margin", let memory { marginBar(snapshot.todayPage, target: memory.day) }
                    else { todayBar(snapshot.todayPage) }
                    // The bar stays where it is when the keyboard comes up for the review field, instead of riding over what is being typed.
                }.ignoresSafeArea(.keyboard, edges: .bottom)
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbarVisibility(.hidden, for: .navigationBar)
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
        .onChange(of: selected) { _, day in if let day { Task { try? await service.prepareClosedDay(day); await refresh() } } }
        .fullScreenCover(isPresented: $searchOpen, onDismiss: { routedSearchQuery = nil; routedSearchRequestID = nil; applyPendingDiaryRootIfReady() }) { DiarySearchView(app: app, initialQuery: routedSearchQuery, initialQueryRequestID: routedSearchRequestID).environment(\.roomTheme, theme) }
        .fullScreenCover(isPresented: $archiveOpen, onDismiss: { clearHubRoute(); applyPendingDiaryRootIfReady() }) {
            DiaryHubView(app: app, initialTab: routedHubTab, initialLetterID: routedLetterID,
                initialLetterRequestID: routedLetterRequestID)
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app)
        }
        .sheet(isPresented: $customizing, onDismiss: { selected = nil; Task { await refresh() }; applyPendingDiaryRootIfReady() }) { DiaryCustomizeView(app: app).environment(\.roomTheme, theme).madarSheetErrorAlert(app) }
        .navigationDestination(item: $editor) { target in
            DiaryTextEditor(app: app, margin: target.margin, initialDay: target.day, prompt: target.prompt, embeddedInNavigationStack: true)
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app).toolbarVisibility(.visible, for: .navigationBar)
                .hidesRoomAccessory(app, id: "diary-editor-destination")
        }
        .navigationDestination(item: $reader) { day in
            DiaryDayView(app: app, day: day, initialEntryID: readerEntryID, initialEntryRouteID: readerEntryRouteID, embeddedInNavigationStack: true)
                .environment(\.roomTheme, theme).madarSheetErrorAlert(app).toolbarVisibility(.visible, for: .navigationBar)
                .hidesRoomAccessory(app, id: "diary-day-destination")
        }
        .onChange(of: editor) { old, new in if old != nil, new == nil { editorDidDismiss() } }
        .onChange(of: reader) { old, new in
            if old != nil, new == nil {
                readerEntryID = nil; readerEntryRouteID = nil
                applyPendingDiaryRootIfReady()
            }
        }
        .onChange(of: app.diaryRoute, initial: true) { _, route in
            guard let route else { return }; app.diaryRoute = nil
            if editor != nil {
                if route.path.first == "write", route.path.count == 1,
                   editor?.id == DiaryEditorTarget(margin: nil, day: route.parameters["day"] ?? "today").id { return }
                queuedDiaryRoute = route
                if app.diaryRootDraftBlockers.isEmpty { editor = nil }
                return
            }
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
    private func editorDidDismiss() {
        if pendingDiaryRootRequestID != nil {
            queuedDiaryRoute = nil
            applyPendingDiaryRootIfReady()
        } else if queuedDiaryRoute != nil {
            applyQueuedDiaryRouteIfReady()
        } else {
            applyPendingDiaryRootIfReady()
        }
    }
    private func applyQueuedDiaryRouteIfReady() {
        guard editor == nil, pendingDiaryRootRequestID == nil,
              app.diaryRootDraftBlockers.isEmpty, let route = queuedDiaryRoute else { return }
        queuedDiaryRoute = nil
        openDiaryRoute(route)
    }
    private func openDiaryRoute(_ route: Route) {
        if route.path.first == "write", route.path.count == 1 {
            editor = .init(margin: nil, day: route.parameters["day"] ?? "today")
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
        if editor != nil { editor = nil; return }
        pendingDiaryRootRequestID = nil
        app.diaryRootRequestID = nil
        queuedDiaryRoute = nil
        searchOpen = false
        archiveOpen = false
        customizing = false
        reader = nil
        readerEntryID = nil
        readerEntryRouteID = nil
        selected = nil
        clearHubRoute()
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("المذكرات").font(DiaryType.title).accessibilityIdentifier("diary-home-title")
                if let snapshot {
                    MadarDateLabel(app.dateLabels(snapshot.today, weekday: true)).foregroundStyle(theme.color("ink3Text"))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { searchOpen = true } label: { Image(systemName: "magnifyingglass").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("ابحث في مذكراتك").accessibilityIdentifier("diary-search")
            Button { archiveOpen = true } label: { Image(systemName: "calendar").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }.buttonStyle(.madarPlain).accessibilityLabel("التقويم").accessibilityIdentifier("diary-days")
            Button { customizing = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }
                .buttonStyle(.madarPlain).accessibilityLabel("خصّص المذكرات").accessibilityIdentifier("diary-customize")
        }.padding(.vertical, 4)
    }
    private func calendarButton(_ calendar: FirstCalendar, _ title: String) -> some View {
        Button { app.set(.string(calendar.rawValue), key: "notes.match") { selected = nil } } label: {
            Text(title).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background { if service.preferredMatch == calendar { Capsule().fill(theme.surface.opacity(0.6)).glassEffect(.regular.interactive(), in: .capsule) } }
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-match-" + calendar.rawValue)
    }
    private func hero(_ snapshot: DiaryHomeSnapshot) -> some View {
        let page = memory ?? snapshot.todayPage
        let image = page.photo.flatMap(UIImage.init(data:))
        let hasPhoto = image != nil && !typeSize.isAccessibilitySize
        return ZStack(alignment: .bottomLeading) {
            if let image, hasPhoto {
                GeometryReader { geometry in Image(uiImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                LinearGradient(colors: [.black.opacity(0.08), .black.opacity(0.62)], startPoint: .top, endPoint: .bottom)
            } else {
                theme.surface
                // Owner trial, 22 Oct 2026: a past page whose photos did not come with the import says so, instead of
                // «صفحة تنتظر ما تعيشه», which reads as if nothing was lived that day.
                let past = page.day != snapshot.today, missing = page.missingPhotos
                // A page with words lets its words lead; the centred note would sit under a long excerpt (tour 25 Oct).
                let worded = page.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
                if !worded {
                VStack(spacing: 12) {
                    Image(systemName: past && missing > 0 ? "photo.on.rectangle.angled" : "book.closed").font(.system(size: 46, weight: .ultraLight))
                    Text(past && missing > 0 ? (missing == 1 ? "صورة هذا اليوم لم تُنقل" : missing == 2 ? "صورتا هذا اليوم لم تُنقلا" : "صور هذا اليوم لم تُنقل") : past ? "من دفترك ذاك اليوم" : "صفحة تنتظر ما تعيشه").font(DiaryType.writing)
                }
                    .foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            VStack(alignment: .leading, spacing: 9) {
                if !snapshot.selection.days.isEmpty {
                    HStack(spacing: 5) {
                        ForEach(snapshot.selection.days, id: \.description) { day in
                            Capsule().fill(day == page.day ? (hasPhoto ? Color.white : theme.accent) : (hasPhoto ? Color.white.opacity(0.4) : theme.line)).frame(height: 3)
                        }
                    }.padding(.bottom, 1)
                    HStack(spacing: 7) {
                        ForEach(snapshot.selection.days, id: \.description) { day in
                            Button { selected = day } label: {
                                MadarDateLabel(yearTitle(day, snapshot: snapshot))
                                    .frame(minWidth: 42, minHeight: 36).padding(.horizontal, 4)
                                    .foregroundStyle(day == page.day ? theme.ink : hasPhoto ? .white : theme.ink)
                                    .background(day == page.day ? theme.surface : hasPhoto ? Color.black.opacity(0.62) : theme.background, in: .capsule)
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-year-" + day.description)
                        }
                        Spacer(minLength: 0)
                    }
                }
                Spacer(minLength: 90)
                HStack(spacing: 8) {
                    Text(snapshot.selection.days.isEmpty ? "صفحتك الأولى" : service.distance(page.day, snapshot.today)).font(DiaryType.label)
                        .padding(.horizontal, 9).padding(.vertical, 4).background(hasPhoto ? Color.black.opacity(0.3) : theme.background, in: .capsule)
                    Text(service.weekday(page.day)).font(DiaryType.label)
                }
                Text(service.dateTitle(page.day, calendar: app.diaryFirstCalendar)).font(DiaryType.title)
                Text(MadarInlineText.joined([service.dateTitle(page.day, calendar: app.diaryFirstCalendar == .gregorian ? .hijri : .gregorian)] + (page.place.map { [$0] } ?? [])))
                    .font(DiaryType.label).opacity(hasPhoto ? 1 : 0.8)
                Text(snapshot.selection.days.isEmpty && page.lines.isEmpty ? "اكتب ما تيسّر من يومك." : page.excerpt)
                    .font(DiaryType.writing).lineSpacing(8).lineLimit(4).fixedSize(horizontal: false, vertical: true)
            }.padding(16)
        }
        .foregroundStyle(hasPhoto ? .white : theme.ink)
        .frame(minHeight: 250)
        .frame(height: typeSize.isAccessibilitySize ? nil : app.string("notes.memorySize") == "medium" ? 280 : 403)
        .clipShape(.rect(cornerRadius: 30))
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("diary-memory")
        .gesture(DragGesture(minimumDistance: 30).onEnded { value in
            let days = snapshot.selection.days
            guard let index = days.firstIndex(of: page.day), days.count > 1 else { return }
            selected = days[(index + (value.translation.width < 0 ? 1 : days.count - 1)) % days.count]
        })
    }
    /// OR-10: «هذا اليوم عبر السنين». Newest year first; a year with neither words nor a photo is skipped; a card opens that day.
    private func years(_ snapshot: DiaryHomeSnapshot) -> some View {
        let pages = snapshot.selection.days.compactMap { day in snapshot.days.first { $0.day == day } }
            .filter { page in page.photo != nil || page.lines.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
        return LazyVStack(alignment: .leading, spacing: 0) {
            if pages.isEmpty {
                VStack(alignment: .leading, spacing: 8) {
                    Text("صفحتك الأولى").font(DiaryType.heading)
                    Text("اكتب ما تيسّر من يومك؛ ستجده هنا في مثل هذا اليوم من العام القادم.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).fixedSize(horizontal: false, vertical: true)
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line) }
            }
            ForEach(Array(pages.enumerated()), id: \.element.id) { index, page in
                HStack(alignment: .top, spacing: 12) {
                    // The thread that ties the years: a bead per year, the line running on to the next card.
                    VStack(spacing: 0) {
                        Circle().fill(index == 0 ? theme.accent : theme.surface).glassEffect(.regular.interactive(), in: .circle).frame(width: 11, height: 11).padding(.top, 22)
                        if index < pages.count - 1 { Rectangle().fill(theme.line).frame(width: 1.5).frame(maxHeight: .infinity) }
                    }.frame(width: 12).accessibilityHidden(true)
                    yearCard(page, snapshot: snapshot).padding(.bottom, 12)
                }
            }
        }
    }
    private func yearCard(_ page: DiaryDisplayDay, snapshot: DiaryHomeSnapshot) -> some View {
        return Button { reader = page.day } label: {
            HStack(alignment: .top, spacing: 12) {
                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(service.distance(page.day, snapshot.today)).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)).foregroundStyle(theme.color("accentText"))
                        Text(service.weekday(page.day)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    }
                    MadarDateLabel(app.dateLabels(page.day, compact: true)).foregroundStyle(theme.color("ink3Text"))
                    Text(page.excerpt).font(.custom("thmanyahseriftext-Regular", size: 18, relativeTo: .body)).lineSpacing(6).lineLimit(3).multilineTextAlignment(.leading).fixedSize(horizontal: false, vertical: true)
                    if let place = page.place { Label(place, systemImage: "mappin").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                    // Owner trial, 22 Oct: a photo the import did not carry is named, never invented.
                    if page.photo == nil, page.missingPhotos > 0 { Label(page.missingPhotos == 1 ? "صورة هذا اليوم لم تُنقل" : page.missingPhotos == 2 ? "صورتا هذا اليوم لم تُنقلا" : "صور هذا اليوم لم تُنقل", systemImage: "photo.on.rectangle.angled").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                }.frame(maxWidth: .infinity, alignment: .leading)
                if let data = page.photo, !typeSize.isAccessibilitySize {
                    DiaryDataThumbnail(data: data, maxPixel: 192) { image in
                        image.resizable().scaledToFill().frame(width: 76, height: 96).clipShape(.rect(cornerRadius: 14)).accessibilityHidden(true)
                    }.id(page.photoID?.uuidString ?? page.id).frame(width: 76, height: 96)
                }
            }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                .background(theme.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line) }
                .contentShape(.rect(cornerRadius: 22))
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-year-" + page.day.description)
    }
    private func thatDay(_ day: DiaryDisplayDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("ذاك اليوم").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)); Text("كتبه مدار وكتبته أنت").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")); Spacer() }
            ForEach(Array(day.lines.filter { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && (app.bool("notes.showAutoSections") || !["salah", "quran"].contains($0.kind)) }.prefix(3))) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(service.time(line.at, zone: line.tzID)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(width: 48, alignment: .leading)
                    Text(line.markdown == true ? DayOneMarkdown.plain(line.text) : line.text).font(.custom("thmanyahseriftext-Regular", size: 16, relativeTo: .body)).italic().lineSpacing(5).fixedSize(horizontal: false, vertical: true)
                        .foregroundStyle(line.kind == "normal" || line.kind == "late" ? theme.ink : theme.color("autoInkText"))
                    Spacer(minLength: 0)
                }
            }
            HStack(spacing: 8) {
                pill("افتح اليوم كاملًا", id: "diary-open-memory") { reader = day.day }
                pill("اكتب في هامشها", id: "diary-add-margin", ink: secondInk) { editor = .init(margin: day.day) }
            }
        }.padding(16).background(theme.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
    }
    private func since(_ day: DiaryDisplayDay) -> some View {
        let metrics = (try? service.comparisons(since: day.day)) ?? []
        return Group {
            if !metrics.isEmpty {
                VStack(alignment: .leading, spacing: 14) {
                    HStack { Text("منذ ذاك اليوم").font(MadarTypography.section()); Text(service.distance(day.day, snapshot?.today ?? day.day)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                    ForEach(metrics, id: \.0) { title, value in
                        Divider().overlay(theme.line)
                        VStack(alignment: .leading, spacing: 7) {
                            Text(title).font(MadarTypography.section())
                            Text(figure: value).font(DiaryType.label).foregroundStyle(theme.color("autoInkText")).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: .rect(cornerRadius: 24)).overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.line) }
            }
        }
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
    private var secondInk: Color {
        switch app.string("notes.secondInk") { case "green": theme.color("ghad"); case "brown": theme.color("autoInkText"); default: theme.color("pencil") }
    }
    private func nextMemory(_ snapshot: DiaryHomeSnapshot) {
        guard let memory, let index = snapshot.selection.days.firstIndex(of: memory.day) else { return }
        selected = snapshot.selection.days[(index + 1) % snapshot.selection.days.count]
    }
    private func marginBar(_ day: DiaryDisplayDay, target: GregorianDay) -> some View {
        HStack(spacing: 8) {
            HStack(spacing: 0) {
                Button { reader = day.day } label: {
                    VStack(alignment: .leading, spacing: 3) { Text("صفحة اليوم").font(MadarTypography.section()); Text(day.excerpt).font(DiaryType.label).lineLimit(2) }
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-today")
                Button { editor = .init(margin: nil) } label: { Image(systemName: "plus").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle) }
                    .buttonStyle(.madarPlain).accessibilityLabel("اكتب في صفحة اليوم").accessibilityIdentifier("diary-write")
            }.padding(.horizontal, 12).background(theme.surface, in: .capsule).glassEffect(.regular.interactive(), in: .capsule)
            Button { editor = .init(margin: target) } label: {
                Label("اكتب في هامشها", systemImage: "pencil").font(MadarTypography.caption()).padding(.horizontal, 15).frame(minHeight: 54).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-add-margin")
        }.padding(.horizontal, 14).padding(.vertical, 8).background(theme.background)
    }
    private func todayBar(_ day: DiaryDisplayDay) -> some View {
        // FB-39 (FB-28): with nothing written today the bar is one clear action that opens the editor; «صفحة اليوم» opened an empty reader.
        if day.lines.isEmpty && day.media.isEmpty && day.photo == nil && (try? service.travel(day.day)) == nil {
            return AnyView(Button { editor = .init(margin: nil) } label: {
                Label("اكتب سطرك الأول اليوم", systemImage: "pencil").font(MadarTypography.section())
                    .frame(maxWidth: .infinity, minHeight: 54).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-write")
                .padding(.horizontal, 14).padding(.vertical, 8).background(theme.background))
        }
        return AnyView(HStack(spacing: 10) {
            Button { reader = day.day } label: {
                VStack(alignment: .leading, spacing: 2) { Text("صفحة اليوم").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)); Text(day.lines.isEmpty ? "اكتب سطرك الأول" : "آخرها " + service.time(day.lines.last!.at)).font(DiaryType.label) }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(.horizontal, 18)
                    .background(theme.surface, in: .capsule).glassEffect(.regular.interactive(), in: .capsule)
            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-today")
            Button { editor = .init(margin: nil) } label: { Label("اكتب", systemImage: "pencil").font(MadarTypography.section()).padding(.horizontal, 22).frame(minHeight: 54).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }
                .buttonStyle(.madarPlain).accessibilityIdentifier("diary-write")
        }.padding(.horizontal, 14).padding(.vertical, 8).background(theme.background))
    }
    private func pill(_ title: String, id: String, ink: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(ink ?? theme.ink).overlay { Capsule().stroke(ink ?? theme.line, lineWidth: 1) } }
            .buttonStyle(.madarPlain).accessibilityIdentifier(id)
    }
    private var blocks: [String] { DiaryHomeLayout(app.values["notes.layout"]).order }
    private func hidden(_ block: String) -> Bool { app.values["notes.layout"]?.object?["hidden"]?.array?.contains(.string(block)) == true }
    private func yearTitle(_ day: GregorianDay, snapshot: DiaryHomeSnapshot) -> String {
        let labels = service.dateLabels(day)
        return labels.primary.split(separator: " ").suffix(2).joined(separator: " ") + "، " + labels.secondary.split(separator: " ").suffix(2).joined(separator: " ")
    }

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
            let shape = app.string("notes.homeShape")
            let initialPages = Dictionary(value.days.map { ($0.day.description, $0) }, uniquingKeysWith: { first, _ in first })
            let displayed = shape == "echoes" ? value.echoes.compactMap(\.day) : shape == "margin" ? [selected ?? preferredOpeningDay(in: value, pages: initialPages)].compactMap { $0 } : value.selection.days
            let changed = try await service.prepareClosedDays(Set(displayed))
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            if changed {
                value = try await service.homeOffMain()
                guard generation == refreshGeneration, !Task.isCancelled else { return }
            }
            let pages = Dictionary(value.days.map { ($0.day.description, $0) }, uniquingKeysWith: { first, _ in first })
            snapshot = value; defaultMemoryDay = preferredOpeningDay(in: value, pages: pages); failure = nil
            if let pendingFollowUps = try? await service.dueIntentionFollowUpsOffMain() {
                guard generation == refreshGeneration, !Task.isCancelled else { return }
                let next = pendingFollowUps.first
                intentionFollowUp = next
            }
        } catch {
            guard generation == refreshGeneration, !Task.isCancelled else { return }
            snapshot = nil
            defaultMemoryDay = nil
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
