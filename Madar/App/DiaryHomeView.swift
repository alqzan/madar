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
        Group {
            if let lock = app.lockController {
                MadarLockGate(controller: lock, feature: .notes) { DiaryLaunchView(app: app) }
            } else { Text("المذكرات مقفلة").frame(maxWidth: .infinity, maxHeight: .infinity) }
        }
        .environment(\.roomTheme, RoomTheme(room: "notes", dark: outerTheme.dark, calmPaper: app.string("core.roomIdentity") == "calmPaper"))
    }
}
private struct DiaryEditorTarget: Identifiable {
    var id: String { margin?.description ?? "write" }
    let margin: GregorianDay?
    var day = "today"
}
struct DiaryHomeView: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dynamicTypeSize) private var typeSize
    @State private var snapshot: DiaryHomeSnapshot?
    @State private var selected: GregorianDay?
    @State private var customizing = false
    @State private var archiveOpen = false
    @State private var editor: DiaryEditorTarget?
    @State private var reader: GregorianDay?
    @State private var failure: String?
    private var service: AppDiaryService { AppDiaryService(app: app) }
    private var memory: DiaryDisplayDay? {
        guard let snapshot else { return nil }
        return snapshot.days.first { $0.day == (selected ?? snapshot.selection.days.first) }
    }
    var body: some View {
        VStack(spacing: 0) {
            header.padding(.horizontal, 14).padding(.top, 8)
            ScrollView {
            VStack(alignment: .leading, spacing: 14) {
                if let snapshot {
                    if app.string("notes.homeShape") == "echoes" {
                        DiaryEchoesView(snapshot: snapshot, service: service, open: { reader = $0 })
                        if !hidden("days") { recentDays(snapshot) }
                    } else if app.string("notes.homeShape") == "margin", let memory {
                        DiaryMarginView(page: memory, snapshot: snapshot, service: service, showAuto: app.bool("notes.showAutoSections"), showLines: !hidden("thatDay"), ink: secondInk,
                            another: snapshot.selection.days.count > 1 ? { nextMemory(snapshot) } : nil, open: { reader = memory.day })
                        if !memory.dayOne, !hidden("sinceThatDay") { since(memory) }
                        if !hidden("days") { recentDays(snapshot) }
                    } else {
                    HStack {
                        Text(snapshot.selection.match == .echo ? "أقرب صدى" : "في مثل هذا اليوم").font(DiaryType.heading)
                        Spacer()
                        HStack(spacing: 2) {
                            calendarButton(.gregorian, "بالميلادي")
                            calendarButton(.hijri, "بالهجري")
                        }.padding(3).background(theme.ink.opacity(0.06), in: .capsule)
                    }
                    ForEach(blocks, id: \.self) { block in
                        switch block {
                        case "memory": hero(snapshot)
                        case "thatDay": if let memory, !hidden(block) { thatDay(memory) }
                        case "sinceThatDay": if let memory, !memory.dayOne, !hidden(block) { since(memory) }
                        case "days": if !hidden(block) { recentDays(snapshot) }
                        default: EmptyView()
                        }
                    }
                    }
                } else if let failure { Text(failure).font(DiaryType.writing) }
                else { ProgressView("تُفتح صفحتك…") }
            }.padding(.horizontal, 14).padding(.top, 8).padding(.bottom, 12)
            }
        }
        .background(theme.background).foregroundStyle(theme.ink)
         .safeAreaInset(edge: .bottom, spacing: 0) {
            if let snapshot {
                if app.string("notes.homeShape") == "margin", let memory { marginBar(snapshot.todayPage, target: memory.day) }
                else { todayBar(snapshot.todayPage) }
            }
        }
        .toolbarVisibility(.hidden, for: .navigationBar)
        .task(id: app.prayerRevision) { await refresh() }
        .task {
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(30)) } catch { break }
                if let previous = snapshot?.today, let current = try? service.currentDay(), current != previous {
                    try? await service.prepareClosedDay(previous)
                    await refresh()
                }
            }
        }
        .onChange(of: selected) { _, day in if let day { Task { try? await service.prepareClosedDay(day); await refresh() } } }
        .fullScreenCover(isPresented: $archiveOpen) { DiaryHubView(app: app).environment(\.roomTheme, theme) }
        .sheet(isPresented: $customizing, onDismiss: { selected = nil; Task { await refresh() } }) { DiaryCustomizeView(app: app).environment(\.roomTheme, theme) }
        .sheet(item: $editor) { target in DiaryTextEditor(app: app, margin: target.margin, initialDay: target.day).environment(\.roomTheme, theme) }
        .sheet(isPresented: Binding(get: { reader != nil }, set: { if !$0 { reader = nil } })) {
            if let reader { DiaryDayView(app: app, day: reader).environment(\.roomTheme, theme) }
        }
        .onChange(of: app.diaryRoute, initial: true) { _, route in
            guard let route else { return }; app.diaryRoute = nil
            if route.path.first == "write" { editor = .init(margin: nil, day: route.parameters["day"] ?? "today") }
            else if route.path.first == "day", let key = route.path.last, let day = try? GregorianDay(key) { reader = day }
            else if route.path.first == "today" { reader = try? service.currentDay() }
        }
    }
    private var header: some View {
        HStack(alignment: .center, spacing: 10) {
            VStack(alignment: .leading, spacing: 3) {
                Text("المذكرات").font(DiaryType.title).accessibilityIdentifier("diary-home-title")
                if let snapshot {
                    Text(service.dateTitle(snapshot.today, calendar: FirstCalendar(rawValue: app.string("core.firstCalendar")) ?? .hijri)
                        + " · " + service.dateTitle(snapshot.today, calendar: app.string("core.firstCalendar") == "gregorian" ? .hijri : .gregorian))
                        .font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }
            }.frame(maxWidth: .infinity, alignment: .leading)
            Button { archiveOpen = true } label: { Image(systemName: "calendar").frame(width: 44, height: 44) }.buttonStyle(.plain).accessibilityLabel("أيامك").accessibilityIdentifier("diary-days")
            Button { customizing = true } label: { Image(systemName: "slider.horizontal.3").frame(width: 44, height: 44).overlay { Circle().stroke(theme.line) } }
                .buttonStyle(.plain).accessibilityLabel("خصّص المذكرات").accessibilityIdentifier("diary-customize")
        }.padding(.vertical, 4)
    }
    private func calendarButton(_ calendar: FirstCalendar, _ title: String) -> some View {
        Button { app.set(.string(calendar.rawValue), key: "notes.match") { selected = nil } } label: {
            Text(title).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
                .padding(.horizontal, 10).frame(minHeight: 36)
                .background(service.preferredMatch == calendar ? theme.surface : .clear, in: .capsule)
        }.buttonStyle(.plain).accessibilityIdentifier("diary-match-" + calendar.rawValue)
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
                VStack(spacing: 12) { Image(systemName: "book.closed").font(.system(size: 46, weight: .ultraLight)); Text("صفحة تنتظر ما تعيشه").font(DiaryType.writing) }
                    .foregroundStyle(theme.color("ink3Text")).frame(maxWidth: .infinity, maxHeight: .infinity)
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
                                Text(yearTitle(day, snapshot: snapshot)).font(.custom("thmanyahsans-Bold", size: 12, relativeTo: .caption))
                                    .frame(minWidth: 42, minHeight: 36).padding(.horizontal, 4)
                                    .foregroundStyle(day == page.day ? theme.ink : hasPhoto ? .white : theme.ink)
                                    .background(day == page.day ? theme.surface : hasPhoto ? Color.black.opacity(0.62) : theme.background, in: .capsule)
                            }.buttonStyle(.plain).accessibilityIdentifier("diary-year-" + day.description)
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
                Text(service.dateTitle(page.day, calendar: snapshot.selection.match == .hijri ? .hijri : .gregorian)).font(DiaryType.title)
                Text(service.dateTitle(page.day, calendar: snapshot.selection.match == .hijri ? .gregorian : .hijri) + (page.place.map { " · " + $0 } ?? ""))
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
    private func thatDay(_ day: DiaryDisplayDay) -> some View {
        VStack(alignment: .leading, spacing: 13) {
            HStack { Text("ذاك اليوم").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)); Text("كتبه مدار وكتبته أنت").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")); Spacer() }
            ForEach(Array(day.lines.filter { app.bool("notes.showAutoSections") || !["salah", "quran"].contains($0.kind) }.prefix(3))) { line in
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    Text(service.time(line.at)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).frame(width: 48, alignment: .leading)
                    Text(line.text).font(.custom("thmanyahseriftext-Regular", size: 16, relativeTo: .body)).italic().lineSpacing(5).fixedSize(horizontal: false, vertical: true)
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
                            Text(value).font(DiaryType.label).foregroundStyle(theme.color("autoInkText")).fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }.padding(18).frame(maxWidth: .infinity, alignment: .leading)
                    .background(theme.surface, in: .rect(cornerRadius: 24)).overlay { RoundedRectangle(cornerRadius: 24).stroke(theme.line) }
            }
        }
    }
    private func recentDays(_ snapshot: DiaryHomeSnapshot) -> some View {
        let days = snapshot.days.filter { $0.day < snapshot.today }.prefix(5)
        return VStack(alignment: .leading, spacing: 10) {
            HStack {
                Button { archiveOpen = true } label: { HStack { Text("أيامك").font(DiaryType.heading); Image(systemName: "arrow.left").font(.caption) } }.buttonStyle(.plain)
                Spacer()
                Text(service.monthTitle(snapshot.today)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
            }.padding(.top, 4)
            VStack(spacing: 0) {
                ForEach(Array(days)) { day in
                    Button { reader = day.day } label: {
                        HStack(spacing: 14) {
                            VStack(spacing: 2) {
                                Text(service.digits.string(day.day.day)).font(.custom("thmanyahseriftext-Regular", size: 24, relativeTo: .title2))
                                Text(service.weekday(day.day)).font(.custom("thmanyahsans-Regular", size: 11, relativeTo: .caption2)).foregroundStyle(theme.color("ink3Text"))
                            }.frame(minWidth: 35)
                            Text(day.excerpt).font(.custom("thmanyahseriftext-Regular", size: 17, relativeTo: .body)).frame(maxWidth: .infinity, alignment: .leading).multilineTextAlignment(.leading)
                            if let data = day.photo, let image = UIImage(data: data) { Image(uiImage: image).resizable().scaledToFill().frame(width: 38, height: 38).clipShape(.rect(cornerRadius: 8)) }
                        }.padding(16)
                    }.buttonStyle(.plain).accessibilityIdentifier("diary-recent-" + day.day.description)
                    if day.id != days.last?.id { Divider().overlay(theme.line) }
                }
                if days.isEmpty { Text("أيامك تبدأ من هنا.").font(DiaryType.writing).padding(24) }
            }.background(theme.surface, in: .rect(cornerRadius: 22)).overlay { RoundedRectangle(cornerRadius: 22).stroke(theme.line, lineWidth: 1) }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("diary-recent-days")
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
                    VStack(alignment: .leading, spacing: 3) { Text("صفحة اليوم").font(MadarTypography.section()); Text(day.excerpt).font(DiaryType.label).lineLimit(1) }
                        .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading)
                }.buttonStyle(.plain).accessibilityIdentifier("diary-today")
                Button { editor = .init(margin: nil) } label: { Image(systemName: "plus").frame(width: 44, height: 44).overlay { Circle().stroke(theme.line) } }
                    .buttonStyle(.plain).accessibilityLabel("اكتب في صفحة اليوم").accessibilityIdentifier("diary-write")
            }.padding(.horizontal, 12).background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line) }
            Button { editor = .init(margin: target) } label: {
                Label("اكتب في هامشها", systemImage: "pencil").font(MadarTypography.caption()).padding(.horizontal, 15).frame(minHeight: 54).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
            }.buttonStyle(.plain).accessibilityIdentifier("diary-add-margin")
        }.padding(.horizontal, 14).padding(.vertical, 8).background(theme.background)
    }
    private func todayBar(_ day: DiaryDisplayDay) -> some View {
        HStack(spacing: 10) {
            Button { reader = day.day } label: {
                VStack(alignment: .leading, spacing: 2) { Text("صفحة اليوم").font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)); Text(day.lines.isEmpty ? "اكتب سطرك الأول" : "آخرها " + service.time(day.lines.last!.at)).font(DiaryType.label) }
                    .frame(maxWidth: .infinity, minHeight: 54, alignment: .leading).padding(.horizontal, 18)
                    .background(theme.surface, in: .capsule).overlay { Capsule().stroke(theme.line, lineWidth: 1) }
            }.buttonStyle(.plain).accessibilityIdentifier("diary-today")
            Button { editor = .init(margin: nil) } label: { Label("اكتب", systemImage: "pencil").font(MadarTypography.section()).padding(.horizontal, 22).frame(minHeight: 54).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }
                .buttonStyle(.plain).accessibilityIdentifier("diary-write")
        }.padding(.horizontal, 14).padding(.vertical, 8).background(theme.background)
    }
    private func pill(_ title: String, id: String, ink: Color? = nil, action: @escaping () -> Void) -> some View {
        Button(action: action) { Text(title).font(.custom("thmanyahsans-Bold", size: 13, relativeTo: .subheadline)).frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(ink ?? theme.ink).overlay { Capsule().stroke(ink ?? theme.line, lineWidth: 1) } }
            .buttonStyle(.plain).accessibilityIdentifier(id)
    }
    private var blocks: [String] { DiaryHomeLayout(app.values["notes.layout"]).order }
    private func hidden(_ block: String) -> Bool { app.values["notes.layout"]?.object?["hidden"]?.array?.contains(.string(block)) == true }
    private func yearTitle(_ day: GregorianDay, snapshot: DiaryHomeSnapshot) -> String { String(service.dateTitle(day, calendar: snapshot.selection.match == .hijri ? .hijri : .gregorian).split(separator: " ").last ?? "") }
    private func refresh() async {
        do {
            var value = try service.home()
            let displayed = app.string("notes.homeShape") == "echoes" ? value.echoes.compactMap(\.day) : [selected ?? value.selection.days.first].compactMap { $0 }
            for day in Set(displayed) { try await service.prepareClosedDay(day) }
            value = try service.home()
            snapshot = value; failure = nil
        } catch { failure = error.localizedDescription }
    }
}
