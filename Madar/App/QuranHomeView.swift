import SwiftUI
import MadarCore
import MadarDesign
import MadarQuran
import Combine

/// R18 Home. RQ9 keeps one line per step and one start action; tools enter only with their screen cards.
struct QuranHomeView: View {
    let service: AppQuranService
    @Environment(\.colorScheme) private var colorScheme
    @Environment(\.dynamicTypeSize) private var dynamicType
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.roomVisit) private var roomVisit
    @Environment(\.isFrontRoom) private var isFrontRoom
    @State private var state: QuranRoomState?
    @State private var error: String?
    @State private var detail: HomeDetail?
    @State private var active: QuranUISessionState?
    @State private var busy = false
    /// A refresh asked for while another operation runs is replayed once it ends, so the home never stays stale.
    @State private var refreshPending = false
    @State private var showDayClose = false
    /// The page travels with the presentation: an `isPresented` cover read `readerPage` stale, so links opened page 1.
    @State private var mushaf: QuranMushafRequest?
    @State private var reference: QuranWirdReferenceRequest?
    @State private var showOutside = false
    @State private var showWeek = false
    @State private var logInitialTab: QuranLogTab = .week
    @State private var logInitialSessionID: UUID?
    @State private var logRouteRequestID: UUID?
    @State private var showPlan = false
    @State private var showPlanSetup = false
    @State private var showSetup = false
    @State private var showFree = false
    @State private var showIndex = false
    @State private var indexInitialUnit: QuranUIIndexUnit = .surah
    @State private var indexInitialItemID: String?
    @State private var indexRouteRequestID: UUID?
    @State private var showStrength = false
    @State private var showQiyam = false
    @State private var pendingQuranRoute: Route?
    @State private var pendingQuranRouteRequestID: UUID?
    @State private var failedQuranRouteRequestID: UUID?
    @State private var quranRouteDismissalRequestID: UUID?
#if DEBUG
    @State private var injectedRunHold = false
    @State private var injectedRouteDismissalHold = false
#endif
    #if DEBUG
    @State private var injectedRouteReadFailure = false
    #endif
    @ViewBuilder private func planContent(_ state: QuranRoomState) -> some View {
                    if let draft = state.draft {
                        Button(draft.isPastDay ? "راجع ما تمّ في جلستك السابقة" : "تابع جلستك") {
                            run { active = try await service.resume(draftID: draft.id) }
                        }.font(bodyFont(14, bold: true)).foregroundStyle(theme.ink).padding(14)
                            .frame(maxWidth: .infinity).background(theme.color("hifzTint"), in: .rect(cornerRadius: 16))
                            .disabled(busy).accessibilityIdentifier("quran-resume")
                    }
                    if let key = state.missedDayKey {
                        // Owner trial: the card said only «لو فاتك يوم» with three plain lines; it now names the day and asks.
                        card { VStack(alignment: .leading, spacing: 10) {
                            Text(state.missedDayTitle ?? "فاتك وِرد").font(bodyFont(16, bold: true)).fixedSize(horizontal: false, vertical: true)
                            Text("ماذا نفعل بنصيبه؟").font(bodyFont(13)).foregroundStyle(theme.secondaryInk)
                            HStack(spacing: 8) {
                                ForEach(QuranUIMissChoice.allCases) { choice in
                                    Button(choice.shortTitle) { run { try await service.perform(.resolveMissed(dayKey: key, choice: choice)); try await refresh() } }.disabled(busy)
                                        .font(bodyFont(13, bold: true)).frame(maxWidth: .infinity, minHeight: 44)
                                        .foregroundStyle(theme.color("reviewText")).background(theme.color("reviewTint"), in: Capsule())
                                        .accessibilityLabel(choice.title).accessibilityIdentifier("quran-missed-" + choice.rawValue)
                                }
                            }
                        } }
                    }
                    if state.plan == nil { Button("ابدأ خطة الحفظ") { showSetup = true }.font(bodyFont(16, bold: true)).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.onAccent).background(theme.accent, in: Capsule()).contentShape(Capsule()).accessibilityIdentifier("quran-start-plan") }
                    if state.plan != nil || !state.steps.isEmpty { path(state) }
    }
    private enum HomeDetail: Identifiable {
        case step(QuranUIStep), hadith
        var id: String { switch self { case .step(let step): "step-" + step.id; case .hadith: "hadith" } }
    }
    private var theme: RoomTheme { RoomTheme(room: "quran", dark: colorScheme == .dark) }
    private var next: QuranUIStep? { state?.steps.first { !$0.completed && $0.available } }
    var body: some View {
        ScrollView {
            if let error {
                VStack(alignment: .leading, spacing: 12) {
                    Text(error).font(bodyFont(14)).fixedSize(horizontal: false, vertical: true)
                    Button("حاول مرة أخرى") {
                        if pendingQuranRoute != nil {
                            acknowledgeError(retryRoute: true)
                        } else { acknowledgeError(refreshIfNeeded: true) }
                    }
                    .font(bodyFont(14, bold: true))
                    .accessibilityIdentifier("quran-home-retry")
                }
                .padding(16)
                .frame(maxWidth: .infinity, alignment: .leading)
                .foregroundStyle(theme.ink)
            }
            if let state {
                VStack(alignment: .leading, spacing: 24) {
                    header(state)
                    ForEach(RoomHomeLayout(session: service.app, key: "quran.layout").visible, id: \.self) { id in
                        switch id {
                        case "sadr": coverage(state)
                        case "path": planContent(state)
                        case "log14": log(state)
                        case "tools": tools(state)
                        default: EmptyView()
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 20).padding(.bottom, 36)
            } else if error == nil { ProgressView().frame(maxWidth: .infinity).padding(60) }
        }
        .clipped()
        .background(theme.background.ignoresSafeArea())
        .foregroundStyle(theme.ink)
        .toolbarVisibility(.hidden, for: .navigationBar)
        .environment(\.roomTheme, theme)
        .accessibilityIdentifier("quran-home")
        .task(id: roomVisit) { do { try await refresh() } catch { self.error = quranUserMessage(error) } }
        // Back from the lock screen or past midnight, «مسار اليوم» and a missed day reflect the day it is now.
        .onChange(of: scenePhase) { _, phase in if phase == .active, active == nil, isFrontRoom { run(refresh: true) { try await refresh() } } }
        .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in if active == nil { run(refresh: true) { try await refresh() } } }
        .refreshesAtMadarDay(service.app) { if active == nil { run(refresh: true) { try await refresh() } } }
        .onChange(of: service.app.quranRoute, initial: true) { _, route in
            guard let route else { return }
            service.app.quranRoute = nil
            pendingQuranRoute = route
            let requestID = UUID()
            pendingQuranRouteRequestID = requestID
            failedQuranRouteRequestID = nil
            dispatchPendingRoute()
        }
        .onChange(of: busy) { _, isBusy in
            if !isBusy { dispatchPendingRoute() }
        }
        .onChange(of: showPlanSetup) { _, presented in
            if !presented { dispatchPendingRoute() }
        }
        .sheet(item: $detail) { item in
            switch item {
            case .hadith:
                QuranCoverageHadithSheet(theme: theme)
                    .environment(\.layoutDirection, .rightToLeft)
            case .step(let step):
            VStack(alignment: .leading, spacing: 18) {
                Text(step.title).font(serif(22))
                Text(step.detail).font(bodyFont(14))
                if let range = step.range { Text(pagesRange(range.fromPage, range.toPage)).font(bodyFont(13)).foregroundStyle(theme.secondaryInk) }
                // §7.4: mistake locations are their own session entry, not only after the review step.
                if step.kind == .drill, step.available, state?.draft == nil {
                    Button("ابدأ التدريب") { detail = nil; run { active = try await service.start(kind: .drill, stepID: step.id, range: nil, rakaat: nil, spotID: nil) } }.disabled(busy)
                        .font(bodyFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(theme.onAccent).background(theme.color("accent"), in: Capsule()).contentShape(Capsule())
                        .disabled(busy).accessibilityIdentifier("quran-drill-start")
                    Button("تمّ") { detail = nil }.font(bodyFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).foregroundStyle(theme.ink)
                } else if step.available, !step.completed, state?.draft == nil {
                    // Owner 20 Oct: the day's order is a suggestion, not a gate; any open step can start now.
                    Button(step.id == next?.id ? "ابدأ" : "ابدأ بها الآن") { detail = nil; run { active = try await service.start(kind: step.kind, stepID: step.id, range: step.range, rakaat: nil, spotID: nil) } }.disabled(busy)
                        .font(bodyFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(theme.onAccent).background(theme.color("accent"), in: Capsule()).contentShape(Capsule())
                        .disabled(busy).accessibilityIdentifier("quran-step-start")
                    Button("تمّ") { detail = nil }.font(bodyFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 44).contentShape(Rectangle()).foregroundStyle(theme.ink)
                } else {
                Button("تمّ") { detail = nil }.font(bodyFont(14, bold: true)).frame(maxWidth: .infinity, minHeight: 48).foregroundStyle(theme.onAccent).background(theme.color("accent"), in: Capsule()).contentShape(Capsule())
                }
            }.padding(24).frame(maxWidth: .infinity, alignment: .leading).background(theme.surface)
                .presentationDetents([.height(step.kind == .drill || (step.available && !step.completed && state?.draft == nil) ? 300 : 260)]).presentationDragIndicator(.visible)
                .environment(\.layoutDirection, .rightToLeft)
            }
        }
        .fullScreenCover(item: $active, onDismiss: { run(refresh: true) { try await refresh() } }) { initial in
            QuranHomeSessionFlow(service: service, state: Binding(get: { active ?? initial }, set: { active = $0 }), close: { active = nil })
                .environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(isPresented: $showDayClose, onDismiss: { run(refresh: true) { try await refresh() } }) {
            QuranDayCloseView(service: service, close: { showDayClose = false })
                .environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(item: $mushaf) { request in
            QuranMushafView(service: service, initialPage: request.page, close: { mushaf = nil })
                .environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(item: $reference) { request in
            QuranWirdReferenceView(request: request, digits: service.numerals, app: service.app, close: { reference = nil })
                .environment(\.roomTheme, theme)
        }
        .fullScreenCover(isPresented: $showOutside) { QuranOutsideView(service: service, close: { showOutside = false }).environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft) }
        .fullScreenCover(isPresented: $showQiyam, onDismiss: { run(refresh: true) { try await refresh() } }) { QuranQiyamView(service: service, close: { showQiyam = false }).environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft) }
        .fullScreenCover(isPresented: $showStrength, onDismiss: { run(refresh: true) { try await refresh() } }) { QuranStrengthView(service: service, close: { showStrength = false }).environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft) }
        .fullScreenCover(isPresented: $showIndex, onDismiss: clearIndexRoute) {
            QuranIndexView(service: service, initialUnit: indexInitialUnit, initialItemID: indexInitialItemID) {
                showIndex = false
                clearIndexRoute()
            }.environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft).id(indexRouteRequestID)
        }
        .fullScreenCover(isPresented: $showFree, onDismiss: { run(refresh: true) { try await refresh() } }) { QuranFreeView(service: service, close: { showFree = false }).environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft) }
        .fullScreenCover(isPresented: $showSetup, onDismiss: { run(refresh: true) { try await refresh() } }) { QuranPlanSetupView(service: service, close: { showSetup = false }).environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft) }
        .fullScreenCover(isPresented: $showPlan, onDismiss: { run(refresh: true) { try await refresh() } }) {
            QuranPlanView(service: service, close: { showPlan = false }, onSetupPresentationChange: { showPlanSetup = $0 })
                .environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft)
        }
        .fullScreenCover(isPresented: $showWeek, onDismiss: clearLogRoute) {
            QuranLogView(service: service, close: { showWeek = false }, initialTab: logInitialTab, initialSessionID: logInitialSessionID)
                .environment(\.roomTheme, theme).environment(\.layoutDirection, .rightToLeft).id(logRouteRequestID)
        }
        .alert("تعذّر إتمام العملية", isPresented: Binding(get: { error != nil }, set: { if !$0 { acknowledgeError() } })) {
            if pendingQuranRoute != nil, pendingQuranRouteRequestID == failedQuranRouteRequestID {
                Button("حاول مرة أخرى") {
                    acknowledgeError(retryRoute: true)
                }
            }
            Button("تمّ") { acknowledgeError() }
        } message: { Text(error ?? "") }
    }
    /// «الوجه ٥»، «الوجهان ٥ و٦»، «الأوجه ٥ إلى ٩»: a one- or two-page step is not «الأوجه».
    private func pagesRange(_ from: Int, _ to: Int) -> String {
        let n = service.numerals
        if from == to { return "الوجه " + n.string(from) }
        if to == from + 1 { return "الوجهان " + n.string(from) + " و" + n.string(to) }
        return "الأوجه " + n.string(from) + " إلى " + n.string(to)
    }
    private func serif(_ size: CGFloat) -> Font { .custom("Amiri-Bold", size: size, relativeTo: size > 26 ? .largeTitle : .title2) }
    private func bodyFont(_ size: CGFloat, bold: Bool = false) -> Font { .custom(bold ? "thmanyahsans-Bold" : "thmanyahsans-Regular", size: size, relativeTo: .body) }
    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        content().padding(.horizontal, 16).padding(.vertical, 20).frame(maxWidth: .infinity, alignment: .leading)
            .background(theme.surface, in: .rect(cornerRadius: 24))
            .shadow(color: theme.ink.opacity(0.05), radius: 18, x: 0, y: 10)
    }
    private func header(_ state: QuranRoomState) -> some View {
        HStack(alignment: .center) {
            Text("القرآن").font(serif(28))
            Spacer()
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_QURAN_ROUTE_FAILURE_HARNESS"] == "1",
               ProcessInfo.processInfo.environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil {
                Button("اختبر الوجه") { service.app.open(URL(string: "madar://quran/page/2")!) }
                    .font(bodyFont(11, bold: true)).accessibilityIdentifier("ui-test-quran-page-route-during-save")
                Button("اختبر التحديث") { run(refresh: true) { try await refresh() } }
                    .font(bodyFont(11, bold: true)).accessibilityIdentifier("ui-test-quran-refresh-during-save")
            }
#endif
            if state.streakDays > 0 {
            Button { showPlan = true } label: { HStack(spacing: 6) { Circle().fill(theme.color("hifz")).frame(width: 7, height: 7); Text(state.streakLabel).font(bodyFont(12, bold: true)) }
                .padding(.horizontal, 13).padding(.vertical, 9).background(theme.color("hifzTint"), in: Capsule())
                }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-streak")
            } else if state.plan != nil {
                Button { showPlan = true } label: { Label("خطّتك", systemImage: "slider.horizontal.3").font(bodyFont(12, bold: true)).frame(minHeight: 44) }
                    .buttonStyle(.madarPlain).accessibilityIdentifier("quran-open-plan")
            }
        }.padding(.horizontal, 8)
    }
    private func coverage(_ state: QuranRoomState) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Button { detail = .hadith } label: {
                Text(QuranMemorizationHadith.text)
                    .font(.custom("Amiri-Regular", size: 21, relativeTo: .title2))
                    .lineSpacing(3).multilineTextAlignment(.leading)
                    .foregroundStyle(theme.color("hifzText"))
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
                    .padding(.vertical, 2).contentShape(Rectangle())
            }.buttonStyle(.madarPlain)
                .accessibilityHint("عرض مصدر الحديث")
                .accessibilityIdentifier("quran-coverage-hadith")
            VStack(alignment: .leading, spacing: 6) {
                Text("في صدرك").font(bodyFont(13)).foregroundStyle(theme.secondaryInk)
                    .accessibilityIdentifier("quran-coverage-label")
                HStack(alignment: .firstTextBaseline, spacing: 12) {
                    Text(state.coverageTitle).font(serif(34)).fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("quran-coverage-title")
                    Spacer(minLength: 0)
                    // Improvement 16 Oct: «أول الطريق» already says nothing is memorized yet; «٪٠» beside it only repeated it as a zero.
                    if state.coverageFraction > 0 { Text(state.percentageLabel + " من القرآن").font(bodyFont(12)).foregroundStyle(theme.secondaryInk) }
                }
            }
            GeometryReader { proxy in
                Capsule().fill(theme.color("track"))
                    .overlay(alignment: .leading) { Capsule().fill(theme.color("review")).frame(width: proxy.size.width * state.coverageFraction) }
            }.frame(height: 6).accessibilityLabel("في صدرك").accessibilityValue(state.percentageLabel)
        }.padding(.horizontal, 8)
    }
    private func path(_ state: QuranRoomState) -> some View {
        card {
            VStack(alignment: .leading, spacing: 18) {
                Text("مسار اليوم").font(bodyFont(13)).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity, alignment: .leading)
                if state.plan != nil {
                level("الحفظ الجديد", kind: .hifz, value: state.hifzLevel, color: theme.color("hifz"), text: theme.color("hifzText"), badge: "الآن", progress: progress(state, kinds: [.bridge, .hifz]))
                HStack(spacing: 7) {
                    Text("الميزان: " + state.balanceTitle).font(bodyFont(12, bold: true)).foregroundStyle(theme.color("reviewText"))
                        .padding(.horizontal, 10).padding(.vertical, 6).background(theme.color("reviewTint"), in: Capsule())
                    Spacer(minLength: 0)
                    if state.balanceTitle == "نصف ورد" || state.balanceTitle == "تثبيت" || state.balanceTitle == "يوم راحة" {
                        Button("زِد حفظك") { run { try await service.perform(.forceNewHifz); try await refresh() } }.disabled(busy).font(bodyFont(12, bold: true)).foregroundStyle(theme.color("hifzText"))
                    }
                }
                }
                let hifzSteps = state.steps.filter { $0.kind == .bridge || $0.kind == .hifz }
                VStack(spacing: 18) { ForEach(hifzSteps) { step in stepRow(step, color: theme.color("hifzText")) } }
                    .background(alignment: .leading) { if !hifzSteps.isEmpty { Rectangle().fill(theme.color("track")).frame(width: 1.5).padding(.vertical, 16).padding(.leading, 10) } }
                if state.plan != nil { level("المراجعة", kind: .review, value: state.reviewLevel, color: theme.color("review"), text: theme.color("reviewText"), badge: "بعد الحفظ", progress: progress(state, kinds: [.review, .drill])) }
                let reviewSteps = state.steps.filter { $0.kind == .review || $0.kind == .drill }
                VStack(spacing: 18) { ForEach(reviewSteps) { step in stepRow(step, color: theme.color("reviewText")) } }
                    .background(alignment: .leading) { if !reviewSteps.isEmpty { Rectangle().fill(theme.color("track")).frame(width: 1.5).padding(.vertical, 16).padding(.leading, 10) } }
                if state.dayCloseAvailable {
                    Button("ختام اليوم") { showDayClose = true }
                        .font(bodyFont(14, bold: true)).foregroundStyle(theme.color("reviewText"))
                        .frame(maxWidth: .infinity, minHeight: 44)
                        .accessibilityIdentifier("quran-day-close-open")
                }
            }
        }
    }
    private func level(_ title: String, kind: QuranUIKind, value: QuranUILevel, color: Color, text: Color, badge: String, progress: String) -> some View {
        VStack(spacing: 15) {
            HStack(spacing: 7) {
                if !progress.isEmpty { Text(progress).font(bodyFont(11, bold: true)).padding(7).background(theme.color("track"), in: Circle()) }
                Circle().fill(color).frame(width: 8, height: 8)
                Text(title).font(bodyFont(16, bold: true)); Spacer(); Text(badge).font(bodyFont(11, bold: true)).foregroundStyle(text)
            }
            if dynamicType.isAccessibilitySize {
                Picker(title, selection: Binding(get: { value }, set: { selected in run { try await service.perform(.setTodayLevel(kind: kind, level: selected)); try await refresh() } })) {
                    ForEach(QuranUILevel.allCases) { Text($0.title).tag($0) }
                }.pickerStyle(.menu).disabled(busy)
            } else {
                HStack(spacing: 0) {
                    ForEach(QuranUILevel.allCases) { selected in
                        levelOption(selected, kind: kind, value: value, color: color, text: text)
                    }
                }
            }
        }
    }
    private func levelOption(_ selected: QuranUILevel, kind: QuranUIKind, value: QuranUILevel, color: Color, text: Color) -> some View {
        let index = QuranUILevel.allCases.firstIndex(of: selected)!
        let current = QuranUILevel.allCases.firstIndex(of: value)!
        let isSelected = selected == value
        let left: CGFloat = selected == .max ? 24 : 0
        let right: CGFloat = selected == .simple ? 24 : 0
        let size: CGFloat = isSelected ? 20 : 12
        let subtitle: String
        if kind == .review { subtitle = service.faceCount(QuranDayLevel(rawValue: selected.rawValue)!.reviewMinimum) }
        else { subtitle = state?.hifzAmounts[selected.rawValue] ?? "" }
        return Button {
            run { try await service.perform(.setTodayLevel(kind: kind, level: selected)); try await refresh() }
        } label: {
            VStack(spacing: 7) {
                ZStack {
                    Rectangle().fill(theme.color("track")).frame(height: 4).padding(.leading, right).padding(.trailing, left)
                    if index <= current { Rectangle().fill(color).frame(height: 4).padding(.leading, right).padding(.trailing, left) }
                    Circle().fill(index <= current ? color : theme.surface).frame(width: size, height: size)
                        .overlay { Circle().stroke(isSelected ? color : theme.color("track"), lineWidth: 2) }
                }.frame(height: 22)
                Text(selected.title).font(bodyFont(12, bold: isSelected)).foregroundStyle(isSelected ? theme.ink : theme.secondaryInk)
                Text(subtitle).font(bodyFont(11)).foregroundStyle(text).lineLimit(2).multilineTextAlignment(.center).frame(minHeight: 28, alignment: .top)
            }.frame(maxWidth: .infinity).contentShape(Rectangle())
        }.buttonStyle(.madarPlain).disabled(busy).accessibilityIdentifier("quran-level-\(kind.rawValue)-\(selected.rawValue)")
            .accessibilityLabel((kind == .hifz ? "الحفظ" : "المراجعة") + "، " + selected.title + "، " + subtitle)
            .accessibilityValue(isSelected ? "محدد" : "غير محدد")
            .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
    private func progress(_ state: QuranRoomState, kinds: [QuranUIKind]) -> String {
        let steps = state.steps.filter { kinds.contains($0.kind) }
        // AU-23: a section with no steps today shows no «٠/٠» chip.
        guard !steps.isEmpty else { return "" }
        return service.numerals.string(steps.filter(\.completed).count) + "/" + service.numerals.string(steps.count)
    }
    private func stepRow(_ step: QuranUIStep, color: Color) -> some View {
        HStack(spacing: 10) {
            ZStack {
                Circle().fill(theme.surface).frame(width: 16, height: 16)
                    .overlay { Circle().stroke(theme.color("track"), lineWidth: 2) }
                if step.id == next?.id { Circle().stroke(color.opacity(0.7), lineWidth: 2).frame(width: 18, height: 18) }
            }.frame(width: 20, height: 72).accessibilityHidden(true)
            HStack(spacing: 10) {
            Button { detail = .step(step) } label: {
                HStack(spacing: 10) {
                    Text(step.title).font(bodyFont(12, bold: true)).foregroundStyle(color)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(step.detail).font(serif(19)).foregroundStyle(theme.ink).fixedSize(horizontal: false, vertical: true)
                        // DA-07: the step in hand says where it starts and what it is for, as R18 Home does.
                        if step.id == next?.id, let range = step.range, step.kind == .bridge || step.kind == .hifz {
                            Text("من الوجه " + service.numerals.string(range.fromPage) + (step.kind == .bridge ? "، تمهيد للورد" : ""))
                                .font(bodyFont(12)).foregroundStyle(theme.secondaryInk).lineLimit(1)
                                .accessibilityIdentifier("quran-step-start")
                        }
                    }
                    Spacer(minLength: 0)
                    if step.completed { Image(systemName: "checkmark").foregroundStyle(color) }
                }.frame(minHeight: 50).strikethrough(step.completed).opacity(step.completed ? 0.55 : 1).contentShape(Rectangle())
            }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-step-" + step.id)
            if step.id == next?.id, state?.draft == nil {
                Button("ابدأ") { run { active = try await service.start(kind: step.kind, stepID: step.id, range: step.range, rakaat: nil, spotID: nil) } }.disabled(busy)
                    .font(bodyFont(14, bold: true)).foregroundStyle(theme.onAccent).padding(.horizontal, 20).frame(minHeight: 44)
                    .background(theme.color("accent"), in: Capsule()).contentShape(Capsule()).contentShape(.capsule).disabled(busy).accessibilityIdentifier("quran-begin")
            }
            if step.kind == .hifz, let ayahRange = step.ayahRange {
                Button { reference = QuranWirdReferenceRequest(range: ayahRange) } label: {
                    Label("تفسير الورد", systemImage: "book.closed")
                        .font(bodyFont(11, bold: true)).padding(.horizontal, 10).frame(minHeight: 44)
                        .foregroundStyle(theme.color("hifzText"))
                        .background(theme.color("hifzTint"), in: Capsule())
                }
                .buttonStyle(.madarPlain)
                .accessibilityLabel("مراجع الورد، " + step.detail)
                .accessibilityIdentifier("quran-step-reference-" + step.id)
            }
            }.padding(.horizontal, step.id == next?.id ? 10 : 0).padding(.vertical, step.id == next?.id ? 6 : 0)
                .overlay { if step.id == next?.id { RoundedRectangle(cornerRadius: 24).stroke(color.opacity(0.65), lineWidth: 1).allowsHitTesting(false) } }
        }
    }
    private func log(_ state: QuranRoomState) -> some View {
        card {
            VStack(alignment: .leading, spacing: 14) {
                HStack { Text("سجلّك").font(serif(22)); Spacer(); Button("الأسبوع") { showWeek = true }.font(bodyFont(13, bold: true)).frame(minHeight: 44).accessibilityIdentifier("quran-week-open") }
                Text(state.history.weekSummary.first ?? "آخر أربعة عشر يومًا").font(bodyFont(13)).foregroundStyle(theme.secondaryInk)
                if state.recentDays.isEmpty {
                    Text("سجّل جلسة اليوم، فتظهر هنا أيام حفظك ومراجعتك.").font(bodyFont(13)).foregroundStyle(theme.secondaryInk)
                } else if dynamicType.isAccessibilitySize {
                    ForEach(state.recentDays) { day in Text(day.accessibilityLabel).font(bodyFont(14)) }
                } else {
                    heatRow("الحفظ", days: state.recentDays, color: theme.color("hifz"), value: \.hifzFraction)
                    heatRow("المراجعة", days: state.recentDays, color: theme.color("review"), value: \.reviewFraction)
                    HStack(spacing: 2) { ForEach(state.recentDays) { day in Text(day.title).font(bodyFont(11)).foregroundStyle(theme.secondaryInk).frame(maxWidth: .infinity) } }
                    HStack(spacing: 4) { Text("أقل").font(bodyFont(11)); ForEach([0.15, 0.35, 0.55, 0.8, 1.0], id: \.self) { alpha in RoundedRectangle(cornerRadius: 3).fill(theme.color("review").opacity(alpha)).frame(width: 14, height: 9) }; Text("أكثر").font(bodyFont(11)) }.foregroundStyle(theme.secondaryInk)
                }
            }
        }.accessibilityElement(children: .contain).accessibilityIdentifier("quran-log14")
    }
    private func heatRow(_ title: String, days: [QuranUIHeatDay], color: Color, value: KeyPath<QuranUIHeatDay, Double>) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) { RoundedRectangle(cornerRadius: 3).fill(color).frame(width: 9, height: 9); Text(title).font(bodyFont(12, bold: true)) }
            HStack(spacing: 3) { ForEach(days) { day in
                RoundedRectangle(cornerRadius: 5).fill(color.opacity(day[keyPath: value] <= 0 ? 0.14 : min(1, 0.32 + day[keyPath: value] * 0.5)))
                    .frame(maxWidth: .infinity).frame(height: 30)
                    .overlay { if day.id == days.last?.id { RoundedRectangle(cornerRadius: 5).stroke(color, lineWidth: 1.4) } }
                    .accessibilityLabel(day.accessibilityLabel)
            } }
        }
    }
    private func tools(_ state: QuranRoomState) -> some View {
        card {
            VStack(spacing: 12) {
                HStack(alignment: .top, spacing: 4) {
                    tool("المصحف", icon: "book", id: "mushaf") { mushaf = .init(page: state.steps.first(where: { $0.kind == .hifz })?.range?.fromPage ?? 1) }
                    tool("الفهرس", icon: "line.3.horizontal.decrease", id: "index") { showIndex = true }
                    tool("مراجعة حرة", icon: "arrow.left.arrow.right", id: "free") { showFree = true }
                    tool("منسوب الحفظ", icon: "chart.bar", id: "strength") { showStrength = true }
                }
                Divider().overlay(theme.line)
                Button { showOutside = true } label: { Label("التذكير والودجات", systemImage: "bell").font(bodyFont(14)).frame(maxWidth: .infinity, minHeight: 44) }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-outside")
            }
        }
    }
    private func tool(_ title: String, icon: String, id: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { VStack(spacing: 8) { Image(systemName: icon).font(.system(size: 18)).frame(height: 24); Text(title).font(bodyFont(11, bold: true)).multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true) }.frame(maxWidth: .infinity, minHeight: 74, alignment: .top).contentShape(Rectangle()) }.buttonStyle(.madarPlain).accessibilityIdentifier("quran-tool-" + id)
    }
    private func refresh() async throws {
        let previous = state?.hifzAmounts ?? [:]
        var loaded = try await service.loadState(deferHifzAmounts: true)
        loaded.hifzAmounts = previous
        state = loaded
        // Level amounts follow the first paint; the previous ones stay on screen meanwhile.
        if let unit = loaded.plan?.input.unit {
            Task {
                try? await Task.sleep(for: .milliseconds(60))
                if let amounts = try? service.hifzAmounts(for: unit), state?.plan?.input.unit == unit { state?.hifzAmounts = amounts }
            }
        }
    }
    private func clearIndexRoute() { indexInitialUnit = .surah; indexInitialItemID = nil; indexRouteRequestID = nil }
    private func clearLogRoute() { logInitialTab = .week; logInitialSessionID = nil; logRouteRequestID = nil }
    /// Keep stateful Quran flows open until the user finishes them. Read-only route covers can be
    /// replaced, but SwiftUI needs the old full-screen presentation to finish dismissing first.
    private var hasProtectedQuranPresentation: Bool {
        active != nil || showDayClose || showSetup || showFree || showQiyam || showPlanSetup
    }
    private var hasReplaceableQuranPresentation: Bool {
        detail != nil || mushaf != nil || reference != nil || showOutside || showWeek || showPlan || showIndex || showStrength
    }
    private func dismissReplaceableQuranPresentations() {
        detail = nil
        mushaf = nil
        reference = nil
        showOutside = false
        showWeek = false
        showPlan = false
        showIndex = false
        showStrength = false
    }
    private func dispatchPendingRoute() {
        guard !busy, !refreshPending,
              error == nil,
              let route = pendingQuranRoute,
              let requestID = pendingQuranRouteRequestID,
              failedQuranRouteRequestID != requestID,
              !hasProtectedQuranPresentation else { return }

        if hasReplaceableQuranPresentation || quranRouteDismissalRequestID != nil {
            guard quranRouteDismissalRequestID != requestID else { return }
            quranRouteDismissalRequestID = requestID
            if hasReplaceableQuranPresentation { dismissReplaceableQuranPresentations() }
            let dismissalDelay = quranRouteDismissalDelayMilliseconds()
            Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(dismissalDelay))
                guard quranRouteDismissalRequestID == requestID else { return }
                quranRouteDismissalRequestID = nil
                dispatchPendingRoute()
            }
            return
        }

        run {
            do {
                try await consume(route)
                if pendingQuranRouteRequestID == requestID {
                    pendingQuranRoute = nil
                    pendingQuranRouteRequestID = nil
                    failedQuranRouteRequestID = nil
                }
            } catch {
                if pendingQuranRouteRequestID == requestID { failedQuranRouteRequestID = requestID }
                throw error
            }
        }
    }
    private func quranRouteDismissalDelayMilliseconds() -> Int {
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if !injectedRouteDismissalHold,
           environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           let raw = environment["MADAR_UI_QURAN_ROUTE_DISMISS_HOLD_MS"],
           let milliseconds = Int(raw), (1...5000).contains(milliseconds) {
            injectedRouteDismissalHold = true
            return milliseconds
        }
#endif
        return 450
    }
    private func consume(_ route: Route) async throws {
        #if DEBUG
        let environment = ProcessInfo.processInfo.environment
        if !injectedRouteReadFailure,
           environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           environment["MADAR_UI_QURAN_ROUTE_READ_FAILURE_ONCE"] == "1" {
            injectedRouteReadFailure = true
            throw CocoaError(.fileReadUnknown)
        }
        #endif
        if state == nil { try await refresh() }
        if route.path.isEmpty {
            // The room link returns to the home; sessions, setup and free reading keep their own save paths.
            detail = nil; mushaf = nil; reference = nil; showOutside = false; showIndex = false; showWeek = false; showPlan = false; showStrength = false
        }
        else if route.path.first == "page", let number = Int(route.path.last ?? "") { mushaf = .init(page: number) }
        else if route.path.first == "fihris" { indexInitialUnit = .surah; indexInitialItemID = nil; indexRouteRequestID = UUID(); showIndex = true }
        else if route.path.first == "juz", let number = route.path.last {
            indexInitialUnit = .juz
            indexInitialItemID = number
            indexRouteRequestID = UUID()
            showIndex = true
        }
        else if route.path.first == "history", let rawID = route.path.last, let id = UUID(uuidString: rawID) {
            logInitialTab = .sessions
            logInitialSessionID = id
            logRouteRequestID = UUID()
            showWeek = true
        }
        else if route.path.first == "session" {
            if route.path.last == "qiyam" { return }
            else if let draft = state?.draft { active = try await service.resume(draftID: draft.id) }
            else if let kind = QuranUIKind(rawValue: route.path.last == "wird" ? "hifz" : route.path.last ?? "") { active = try await service.start(kind: kind, stepID: nil, range: nil, rakaat: nil, spotID: nil) }
        }
    }
    private func run(refresh isRefresh: Bool = false, _ operation: @escaping @MainActor () async throws -> Void) {
        guard !busy else { if isRefresh { refreshPending = true }; return }; busy = true
#if DEBUG
        let environment = ProcessInfo.processInfo.environment
        let runHold: Int
        if !injectedRunHold,
           environment["MADAR_UI_STORE_ID"].flatMap(UUID.init(uuidString:)) != nil,
           let raw = environment["MADAR_UI_QURAN_RUN_HOLD_MS"], let milliseconds = Int(raw), (1...5000).contains(milliseconds) {
            injectedRunHold = true
            runHold = milliseconds
        } else { runHold = 0 }
#else
        let runHold = 0
#endif
        Task {
            error = nil
            defer {
                busy = false
                if refreshPending, error == nil {
                    refreshPending = false
                    run(refresh: true) { try await refresh() }
                } else {
                    dispatchPendingRoute()
                }
            }
            do {
                if runHold > 0 { try await Task.sleep(for: .milliseconds(Int64(runHold))) }
                try await operation()
            } catch { self.error = quranUserMessage(error) }
        }
    }
    private func acknowledgeError(retryRoute: Bool = false, refreshIfNeeded: Bool = false) {
        guard error != nil || retryRoute || refreshIfNeeded else { return }
        if retryRoute { failedQuranRouteRequestID = nil }
        error = nil
        Task { @MainActor in
            await Task.yield()
            if refreshPending || refreshIfNeeded {
                refreshPending = false
                run(refresh: true) { try await refresh() }
            } else {
                dispatchPendingRoute()
            }
        }
    }
}

struct QuranMushafRequest: Identifiable { let id = UUID(); let page: Int }

/// AU-79: the Quran screens follow the Madar day (`core.dayStart`), not only civil midnight.
struct QuranMadarDayRefresh: ViewModifier {
    let app: AppSession
    let refresh: () -> Void
    @State private var shownKey: String?
    func body(content: Content) -> some View {
        content.task {
            shownKey = app.currentMadarDayKey()
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                guard let key = app.currentMadarDayKey(), key != shownKey else { continue }
                shownKey = key
                refresh()
            }
        }
    }
}
extension View {
    func refreshesAtMadarDay(_ app: AppSession, _ refresh: @escaping () -> Void) -> some View { modifier(QuranMadarDayRefresh(app: app, refresh: refresh)) }
}
