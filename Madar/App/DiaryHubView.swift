import SwiftUI
import ImageIO
import MadarCore
import MadarDesign

struct DiaryHubView: View {
    @Bindable var app: AppSession
    var initialTab: String? = nil
    var initialLetterID: UUID? = nil
    var initialProjectID: UUID? = nil
    var initialLetterRequestID: UUID? = nil
    var initialProjectRequestID: UUID? = nil
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var archive: DiaryArchiveSnapshot?
    @State private var contentPosition = ScrollPosition(edge: .top)
    @State private var year: Int?
    @State private var month: Int?
    @State private var tab = "calendar"
    @State private var reader: GregorianDay?
    @State private var travelDays: Set<GregorianDay> = []
    @State private var searchOpen = false
    @State private var exportOpen = false
    @State private var bookOpen = false
    @State private var failure: String?
    @State private var loadAttempt = 0
    @State private var memoryReadFailurePending = false
    /// The memories read runs once per data change, not once per redraw of the open tab (a plain box: filling it must not redraw).
    @State private var memoryCache = MemoryReadBox()
    #if DEBUG
        @State private var injectedMemoryReadFailure = false
    #endif
    @State private var injectedArchiveReadFailure = false
    @State private var initialRouteApplied = false
    @State private var aiComposerOpen = false
    @State private var aiAvailability: MadarAIAvailability = .checking
    private var service: AppDiaryService { .init(app: app) }
    private var grid: DiaryCalendarGrid { service.diaryCalendar }
    private var canReadDiary: Bool { app.protectedDataAuthorized }
    private var selectedYear: Int {
        year ?? archive.map { grid.parts($0.today).year ?? $0.today.year } ?? grid.parts(
            GregorianDay.containing(.now, in: app.activePlace.timeZone)
        ).year ?? Calendar.current.component(.year, from: .now)
    }
    private let tabs = [
        ("calendar", "الشهر"), ("timeline", "الأيام"), ("memories", "الذكريات"), ("photos", "الصور"),
        // Owner, 5 Nov 2026: «اي شي له علاقه بالمشاريع احذفه… معاد ابيه». The tab left; stored projects stay untouched.
        ("letters", "الرسائل"), ("index", "الفهرس"),
    ]
    var body: some View {
        NavigationStack {
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("أيامك").font(DiaryType.title);
                }.padding(.horizontal, 18).padding(.bottom, 12)
                ScrollView(.horizontal) {
                    HStack(spacing: 16) {
                        ForEach(tabs, id: \.0) { id, title in
                            Button {
                                tab = id
                            } label: {
                                Text(title).font(MadarTypography.caption()).frame(minHeight: 44).foregroundStyle(
                                    tab == id ? theme.ink : theme.color("ink3Text")
                                ).overlay(alignment: .bottom) {
                                    if tab == id { Rectangle().fill(theme.accent).frame(height: 2) }
                                }
                            }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-hub-" + id)
                        }
                    }
                }.scrollIndicators(.hidden).padding(.horizontal, 18)
                Divider().overlay(theme.line)
                ScrollView {
                    VStack(alignment: .leading, spacing: 18) {
                        if let archive {
                            switch tab {
                            case "calendar": calendar(archive)
                            case "photos": photos(archive)
                            case "memories": memories(archive)
                            case "index": index(archive)
                            case "letters":
                                DiaryLettersPanel(
                                    app: app, initialLetterID: initialLetterID,
                                    initialLetterRequestID: initialLetterRequestID)
                            case "projects":
                                DiaryProjectsPanel(
                                    app: app, initialProjectID: initialProjectID,
                                    initialProjectRequestID: initialProjectRequestID)
                            default: timeline(archive.days)
                            }
                        } else if let failure {
                            VStack(spacing: 12) {
                                Text(failure).font(DiaryType.heading).multilineTextAlignment(.center)
                                    .accessibilityIdentifier("diary-hub-error")
                                Button { loadAttempt += 1 } label: { Text("أعد المحاولة")
                                    .frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-hub-retry")
                            }.frame(maxWidth: .infinity).padding(.vertical, 28)
                        } else {
                            ProgressView("تُفتح أيامك…")
                        }
                        // Nothing to bind into a yearbook or export until a day has been written (owner, 4 Nov 2026).
                        if archive?.days.isEmpty == false {
                            Button {
                                bookOpen = true
                            } label: {
                                Label("كتاب السنة", systemImage: "book.closed").font(DiaryType.label).frame(minHeight: 44)
                            }.accessibilityIdentifier("diary-yearbook")
                            Button {
                                exportOpen = true
                            } label: {
                                Label("تصدير المذكرات", systemImage: "square.and.arrow.up").font(DiaryType.label).frame(
                                    minHeight: 44)
                            }.accessibilityIdentifier("diary-export")
                        }
                    }.padding(18)
                }
                .scrollPosition($contentPosition)
                .onChange(of: month) { contentPosition.scrollTo(edge: .top) }
                .onChange(of: selectedYear) { contentPosition.scrollTo(edge: .top) }
                .onChange(of: tab) { _, value in
                    contentPosition.scrollTo(edge: .top)
                    #if DEBUG
                        let environment = ProcessInfo.processInfo.environment
                        if value == "memories", !injectedMemoryReadFailure,
                            environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
                            environment["MADAR_UI_DIARY_MEMORIES_READ_FAILURE_ONCE"] == "1"
                        {
                            injectedMemoryReadFailure = true
                            memoryReadFailurePending = true
                        }
                    #endif
                }
            }.background(theme.background).foregroundStyle(theme.ink)
                .fullScreenCover(isPresented: $bookOpen) { DiaryYearbookView(app: app).environment(\.roomTheme, theme) }
                .fullScreenCover(isPresented: $exportOpen) { DiaryExportView(app: app).environment(\.roomTheme, theme) }
                .fullScreenCover(isPresented: $searchOpen) { DiarySearchView(app: app).environment(\.roomTheme, theme) }
                .sheet(isPresented: $aiComposerOpen) {
                    MadarAIAnalysisSheet(app: app, kind: .diary, initialScope: .all)
                        .environment(\.roomTheme, theme)
                }
                .toolbar {
                    if canReadDiary, aiAvailability == .ready || aiAvailability == .needsDownload {
                        ToolbarItem(placement: .topBarTrailing) {
                            Button { aiComposerOpen = true } label: { Image(systemName: "sparkles") }
                                .accessibilityLabel("اسأل يومياتك")
                                .accessibilityIdentifier("diary-hub-ai")
                        }
                    }
                    ToolbarItem(placement: .topBarTrailing) {
                        Button {
                            searchOpen = true
                        } label: {
                            Image(systemName: "magnifyingglass")
                        }.accessibilityLabel("ابحث في مذكراتك")
                    };
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            dismiss()
                        } label: {
                            Label("المذكرات", systemImage: "chevron.backward")
                        }.accessibilityIdentifier("diary-hub-close")
                    }
                }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .task(id: "\(app.prayerRevision)-\(canReadDiary)") {
                    guard canReadDiary else { aiAvailability = .checking; aiComposerOpen = false; return }
                    aiAvailability = await MadarAIAvailabilityChecker.check()
                }
                .onChange(of: canReadDiary) { _, canRead in
                    if !canRead { aiComposerOpen = false; aiAvailability = .checking }
                }
                .sheet(isPresented: Binding(get: { reader != nil }, set: { if !$0 { reader = nil } })) {
                    if let reader {
                        DiaryDayView(app: app, day: reader).environment(\.roomTheme, theme).madarSheetErrorAlert(app)
                    }
                }
                .onChange(of: initialTab) { _, target in
                    if let target, tabs.contains(where: { $0.0 == target }) { tab = target; initialRouteApplied = true }
                }
                .task(id: "\(app.prayerRevision)-\(loadAttempt)") {
                    failure = nil
                    do {
                        #if DEBUG
                            let environment = ProcessInfo.processInfo.environment
                            if !injectedArchiveReadFailure,
                                environment["MADAR_UI_DIARY_HUB_READ_FAILURE_ONCE"] == "1",
                                environment["MADAR_UI_DIARY_FIXTURE"] == "letters",
                                environment["MADAR_UI_STORE_ID"] != nil
                            {
                                injectedArchiveReadFailure = true
                                throw CocoaError(.fileReadUnknown)
                            }
                        #endif
                        archive = try service.archive()
                        travelDays = (try? service.travelDays()) ?? []
                        failure = nil
                        if !initialRouteApplied, let initialTab, tabs.contains(where: { $0.0 == initialTab }) {
                            tab = initialTab
                            initialRouteApplied = true
                        }
                    } catch {
                        archive = nil
                        travelDays = []
                        failure = "تعذّر فتح سجل اليوميات."
                    }
                }
        }
    }
    private func calendar(_ archive: DiaryArchiveSnapshot) -> some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Button {
                    year = selectedYear - 1
                } label: {
                    Image(systemName: "chevron.forward").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                }.accessibilityLabel("السنة السابقة").accessibilityIdentifier("diary-year-previous")
                VStack(alignment: .leading, spacing: 3) {
                    Text(service.digits.string(selectedYear)).font(DiaryType.title).accessibilityIdentifier(
                        "diary-hub-year");
                    Text(alternateYearTitle).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }
                Button {
                    year = selectedYear + 1
                } label: {
                    Image(systemName: "chevron.backward").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                }.accessibilityLabel("السنة التالية")
                Spacer()
                HStack(spacing: 0) {
                    scaleButton(
                        title: "السنة", accessibilityLabel: "السنة على الجدار", selected: month == nil,
                        identifier: "diary-calendar-scale-year"
                    ) {
                        month = nil
                    }
                    scaleButton(
                        title: "الشهر", accessibilityLabel: "ورقة الشهر", selected: month != nil,
                        identifier: "diary-calendar-scale"
                    ) {
                        if month == nil { month = grid.parts(archive.today).month }
                    }
                }
                .padding(2)
                .glassEffect(.regular.interactive(), in: .capsule)
            }.buttonStyle(.madarPlain)
            if let month {
                monthPage(archive, month: month)
            } else if typeSize.isAccessibilitySize {
                ForEach(1...12, id: \.self) { month in
                    Button { self.month = month } label: { Text(grid.monthName(year: selectedYear, month: month)).font(
                        DiaryType.heading
                    ).frame(minHeight: 44).contentShape(Rectangle()) }
                }
            } else {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 16), count: 3), spacing: 16) {
                    ForEach(1...12, id: \.self) { month in miniMonth(archive, month: month) }
                }
            }
            Text("الأغمق كتابة أكثر. افتح أي شهر لترى ورقته.").font(DiaryType.label).foregroundStyle(
                theme.color("ink3Text"))
            if travelDays.contains(where: { grid.parts($0).year == selectedYear }) {
                HStack(spacing: 8) {
                    DiaryAirmailFrame(lineWidth: 1.4, dash: 3).frame(width: 16, height: 16);
                    Text("الإطار البريدي: أيام السفر").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }
                .accessibilityElement(children: .combine).accessibilityIdentifier("diary-calendar-travel-legend")
            }
            HStack(spacing: 8) {
                Text("التقويم").font(DiaryType.label)
                ForEach([FirstCalendar.gregorian, .hijri], id: \.rawValue) { value in
                    Button {
                        app.set(.string(value.rawValue), key: "notes.calendarFirst") {
                            year = nil; month = nil
                        }
                    } label: { Text(value == .gregorian ? "الميلادي" : "الهجري").font(DiaryType.label).frame(minHeight: 44).padding(.horizontal, 8).contentShape(Rectangle()) }.overlay {
                        Capsule().stroke(grid.first == value ? theme.accent : theme.line)
                    }.contentShape(Capsule()).accessibilityIdentifier("diary-calendar-" + value.rawValue)
                }
            }
        }
    }
    private func scaleButton(
        title: String, accessibilityLabel: String, selected: Bool, identifier: String, action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Text(title)
                .font(DiaryType.label)
                .foregroundStyle(selected ? theme.onAccent : theme.secondaryInk)
                .padding(.horizontal, 10)
                .frame(minWidth: 54, minHeight: 40)
                .background { if selected { Capsule().fill(theme.accent) } }
                .contentShape(Capsule())
        }
        .buttonStyle(.madarPlain)
        .accessibilityLabel(accessibilityLabel)
        .accessibilityValue(selected ? "محدد" : "غير محدد")
        .accessibilityAddTraits(selected ? .isSelected : [])
        .accessibilityIdentifier(identifier)
    }
    private var alternateYearTitle: String {
        alternateYearTitle(for: selectedYear)
    }
    private func alternateMonthTitle(_ month: Int) -> String {
        service.alternateMonthTitle(year: selectedYear, month: month)
    }
    private func miniMonth(_ archive: DiaryArchiveSnapshot, month: Int) -> some View {
        let days = grid.days(year: selectedYear, month: month),
            counts = Dictionary(uniqueKeysWithValues: archive.days.map { ($0.day, $0.writings) })
        let current = grid.parts(archive.today)
        return Button {
            self.month = month
        } label: {
            VStack(alignment: .leading, spacing: 8) {
                Text(grid.monthName(year: selectedYear, month: month)).font(
                    .custom("thmanyahseriftext-Bold", size: 13, relativeTo: .caption))
                Text(alternateMonthTitle(month)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                    .lineLimit(1).minimumScaleFactor(0.7)
                LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 2) {
                    ForEach(0..<grid.leading(days), id: \.self) { _ in Color.clear.aspectRatio(1, contentMode: .fit) }
                    ForEach(days, id: \.description) { day in
                        RoundedRectangle(cornerRadius: 1).fill(
                            theme.ink.opacity(
                                day > archive.today
                                    ? 0.015
                                    : (counts[day] ?? 0) == 0 ? 0.06 : min(0.85, 0.25 + Double(counts[day] ?? 0) * 0.15)
                            )
                        )
                        .aspectRatio(1, contentMode: .fit).overlay {
                            if day == archive.today {
                                RoundedRectangle(cornerRadius: 1).stroke(theme.accent)
                            } else if travelDays.contains(day) {
                                DiaryAirmailFrame(lineWidth: 1, dash: 2)
                            }
                        }
                    }
                }.frame(maxHeight: .infinity, alignment: .top)
            }.padding(4).frame(maxWidth: .infinity, minHeight: 96, alignment: .topLeading)
                .overlay {
                    RoundedRectangle(cornerRadius: 12).stroke(
                        current.year == selectedYear && current.month == month ? theme.ink : .clear)
                }
        }.buttonStyle(.madarPlain).accessibilityLabel(
            grid.monthName(year: selectedYear, month: month) + " " + service.digits.string(selectedYear) + "، "
                + alternateMonthTitle(month)
        ).accessibilityIdentifier("diary-month-" + String(month))
    }
    private func monthPage(_ archive: DiaryArchiveSnapshot, month: Int) -> some View {
        let days = grid.days(year: selectedYear, month: month),
            written = Set(archive.days.filter { $0.writings > 0 || !$0.photoIDs.isEmpty }.map(\.day))
        return VStack(alignment: .leading, spacing: 16) {
            HStack {
                Button {
                    if month > 1 { self.month = month - 1 } else { year = selectedYear - 1; self.month = 12 }
                } label: {
                    Image(systemName: "chevron.forward").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                };
                VStack(alignment: .leading, spacing: 3) {
                    Text(grid.monthName(year: selectedYear, month: month)).font(DiaryType.heading);
                    Text(alternateMonthTitle(month)).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
                }; Spacer();
                Button {
                    if month < 12 { self.month = month + 1 } else { year = selectedYear + 1; self.month = 1 }
                } label: {
                    Image(systemName: "chevron.backward").frame(width: 44, height: 44).glassEffect(.regular.interactive(), in: .circle)
                }
            }.buttonStyle(.madarPlain)
            LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 2), count: 7), spacing: 6) {
                ForEach(0..<grid.leading(days), id: \.self) { _ in Color.clear.frame(height: 44) }
                ForEach(days, id: \.description) { day in
                    Button {
                        reader = day
                    } label: {
                        VStack(spacing: 3) {
                            Text(service.digits.string(grid.parts(day).day ?? day.day)).font(MadarTypography.body());
                            Text(
                                service.digits.string(
                                    grid.first == .gregorian
                                        ? HijriCalendar.date(
                                            for: day.date(in: grid.zone).addingTimeInterval(43200), timeZone: grid.zone,
                                            source: HijriSource(rawValue: app.string("core.hijriSource")) ?? .ummAlQura,
                                            sightingOffset: grid.offset
                                        ).day : day.day)
                            ).font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk);
                            Circle().fill(written.contains(day) ? theme.accent : .clear).frame(width: 4, height: 4)
                        }
                        .frame(maxWidth: .infinity, minHeight: 44).background(
                            day == archive.today ? theme.surface : .clear, in: .rect(cornerRadius: 10)
                        )
                        .overlay {
                            if travelDays.contains(day) { DiaryAirmailFrame(lineWidth: 1.6, dash: 4).padding(2) }
                        }
                    }.buttonStyle(.madarPlain).disabled(day > archive.today).accessibilityLabel(
                        service.bothDates(day, calendar: grid.first) + (travelDays.contains(day) ? "، يوم سفر" : "")
                    ).accessibilityIdentifier("diary-calendar-day-" + day.description)
                }
            }
            timeline(
                archive.days.filter {
                    let parts = grid.parts($0.day); return parts.year == selectedYear && parts.month == month
                })
        }
    }
    private func timeline(
        _ days: [DiaryDaySummary], empty: String = "لا كتابة في هذه الفترة. يمكنك فتح أي يوم من التقويم."
    ) -> some View {
        LazyVStack(alignment: .leading, spacing: 0) {
            if days.isEmpty { Text(empty).font(DiaryType.writing).padding(.vertical, 24) }
            ForEach(days) { day in
                Button {
                    reader = day.day
                } label: {
                    VStack(alignment: .leading, spacing: 7) {
                        Text(service.weekday(day.day) + "، " + service.bothDates(day.day, calendar: grid.first)).font(
                            DiaryType.label
                        ).foregroundStyle(theme.color("ink3Text"));
                        Text(day.excerpt).font(DiaryType.writing).lineLimit(3).multilineTextAlignment(.leading)
                    }.padding(16).frame(maxWidth: .infinity, alignment: .leading)
                }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-hub-day-" + day.id)
                Divider().overlay(theme.line)
            }
        }.background(theme.surface, in: .rect(cornerRadius: 18))
    }
    private func photos(_ archive: DiaryArchiveSnapshot) -> some View {
        let days = archive.days.filter { !$0.photoIDs.isEmpty }
        return VStack(alignment: .leading, spacing: 14) {
            if days.isEmpty {
                Text("لا صور بعد. أضف صورة إلى صفحة يومك لتظهر هنا.").font(DiaryType.writing).padding(.vertical, 24)
            }
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 14) {
                ForEach(days) { day in
                    ForEach(day.photoIDs, id: \.self) { id in
                        DiaryArchiveThumbnail(service: service, id: id) { photo in
                            Button {
                                reader = day.day
                            } label: {
                                VStack(spacing: 8) {
                                    photo.resizable().scaledToFill().frame(height: 135).clipped();
                                    MadarDateLabel(service.dateLabels(day.day, first: grid.first))
                                }.padding(7).background(theme.surface).rotationEffect(.degrees(-1))
                            }.buttonStyle(.madarPlain).accessibilityLabel(
                                "افتح يوم الصورة " + service.bothDates(day.day, calendar: grid.first))
                        }
                    }
                }
            }
        }
    }
    private func memories(_ archive: DiaryArchiveSnapshot) -> some View {
        let loaded: Result<DiaryHomeSnapshot, Error>
        if memoryReadFailurePending {
            loaded = .failure(CocoaError(.fileReadUnknown))
        } else {
            let key = "\(app.prayerRevision)-\(loadAttempt)"
            if memoryCache.key == key, let cached = memoryCache.result { loaded = cached }
            else {
                loaded = Result { try service.home() }
                if case .success = loaded { memoryCache.key = key; memoryCache.result = loaded }
            }
        }
        let home = try? loaded.get()
        return VStack(alignment: .leading, spacing: 14) {
            Text("رف الذكريات").font(DiaryType.heading)
            Text(home?.selection.match == .echo ? "أقرب ما كتبتَه إلى اليوم" : "من مثل هذا اليوم").font(DiaryType.label)
                .foregroundStyle(theme.color("ink3Text"))
            // A read that failed says so; «لا ذكريات» is only for a day that truly has none.
            if case .failure(let error) = loaded {
                Text(madarUserMessage(error)).font(DiaryType.writing).accessibilityIdentifier("diary-hub-memory-error")
                // A real failure leaves the flag false already: bumping the attempt is what reads again.
                Button { memoryReadFailurePending = false; loadAttempt += 1 } label: { Text("أعد المحاولة")
                    .frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-hub-memories-retry")
            } else {
                timeline(
                    archive.days.filter { home?.selection.days.contains($0.day) == true },
                    empty: "حين تكتب في أيام مثل هذا اليوم، تعود إليك صفحاتها هنا مع السنين.")
            }
        }
    }
    private func index(_ archive: DiaryArchiveSnapshot) -> some View {
        let years = Set(archive.days.map { grid.parts($0.day).year ?? $0.day.year }).sorted(by: >)
        return VStack(alignment: .leading, spacing: 12) {
            Text("فهرس الأيام").font(DiaryType.heading)
            if years.isEmpty { Text("يبدأ فهرسك من أول صفحة تكتبها.").font(DiaryType.writing) }
            ForEach(years, id: \.self) { year in
                let labels = indexYearLabels(year)
                DisclosureGroup {
                    timeline(archive.days.filter { grid.parts($0.day).year == year })
                } label: {
                    MadarDateLabel(labels, primaryFont: DiaryType.heading, secondaryFont: MadarTypography.fine())
                }
                .font(DiaryType.heading).padding(12).background(theme.surface, in: .rect(cornerRadius: 16))
                .accessibilityElement(children: .combine).accessibilityLabel(labels.combined)
                .accessibilityIdentifier("diary-hub-index-year-" + String(year))
            }
        }
    }
    private func indexYearLabels(_ year: Int) -> MadarDateLabels {
        let primary = service.digits.string(year) + (grid.first == .gregorian ? " م" : " هـ")
        return .init(primary: primary, secondary: alternateYearTitle(for: year))
    }
    private func alternateYearTitle(for year: Int) -> String {
        guard let first = grid.days(year: year, month: 1).first, let last = grid.days(year: year, month: 12).last else {
            return ""
        }
        let start = service.dateLabels(first, first: grid.first).secondary.split(separator: " ").suffix(2).joined(
            separator: " ")
        let end = service.dateLabels(last, first: grid.first).secondary.split(separator: " ").suffix(2).joined(
            separator: " ")
        return start == end ? start : start + " – " + end
    }
}


/// A photo of the archive grid: the file is read when its cell appears and shrunk off the main thread, so scrolling never decodes a full-size photo in `body`.
private struct DiaryArchiveThumbnail<Content: View>: View {
    let service: AppDiaryService
    let id: UUID
    @ViewBuilder let content: (Image) -> Content
    @State private var image: UIImage?
    var body: some View {
        Group {
            if let image { content(Image(uiImage: image)) } else { Color.clear.frame(height: 150) }
        }.task(id: id) {
            guard image == nil, let data = try? service.archivePhoto(id) else { return }
            image = await Task.detached(priority: .utility) { () -> UIImage? in
                let options: [CFString: Any] = [kCGImageSourceCreateThumbnailFromImageAlways: true, kCGImageSourceCreateThumbnailWithTransform: true, kCGImageSourceThumbnailMaxPixelSize: 600]
                guard let source = CGImageSourceCreateWithData(data as CFData, nil), let cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary) else { return UIImage(data: data) }
                return UIImage(cgImage: cg)
            }.value
        }
    }
}

@MainActor private final class MemoryReadBox {
    var key = ""
    var result: Result<DiaryHomeSnapshot, Error>?
}
