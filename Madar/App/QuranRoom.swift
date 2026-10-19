import SwiftUI
import UIKit
import Observation
import MadarDesign

// This projection contains domain results and validated read-only resources.
// UI never invents coverage, a grade, a verse, a draft position or a resource license.
enum QuranUILevel: String, CaseIterable, Identifiable, Sendable {
    case simple, medium, deep, max
    var id: String { rawValue }
    var title: String { switch self { case .simple: "بسيط"; case .medium: "متوسط"; case .deep: "عميق"; case .max: "مُحكَم" } }
}
enum QuranUIKind: String, Sendable { case bridge, hifz, review, free, qiyam, drill }
enum QuranUIGrade: String, CaseIterable, Identifiable, Sendable {
    case mastered, good, needs
    var id: String { rawValue }
    var title: String { switch self { case .mastered: "متقن"; case .good: "جيد"; case .needs: "يحتاج إتقانًا" } }
}
enum QuranUIUnit: String, CaseIterable, Identifiable, Sendable {
    case ayah, quarter, half, page
    var id: String { rawValue }
    var title: String { switch self { case .ayah: "آيات"; case .quarter: "ربع وجه"; case .half: "نصف وجه"; case .page: "وجه" } }
}
enum QuranUIRhythm: String, CaseIterable, Identifiable, Sendable {
    case light, balanced, intense
    var id: String { rawValue }
    var title: String { switch self { case .light: "خفيف"; case .balanced: "متوازن"; case .intense: "مكثّف" } }
}
enum QuranUIMissChoice: String, CaseIterable, Identifiable, Sendable {
    case spread, double, skip
    var id: String { rawValue }
    var title: String { switch self { case .spread: "وزّعه على ثلاثة أيام"; case .double: "ضاعف اليوم"; case .skip: "تجاوزه" } }
}
struct QuranUIRange: Sendable { var fromPage: Int; var toPage: Int }
struct QuranUISurah: Identifiable, Sendable { var id: Int; var title: String; var firstAyah: Int; var ayahCount: Int }
struct QuranUIPlanInput: Sendable { var startAyah: Int; var unit: QuranUIUnit; var amount: Double; var rhythm: QuranUIRhythm; var restDay: String; var missPolicy: String }
struct QuranUIForecast: Sendable { var title: String; var assumptions: String; var warning: String?; var portions: [String] }
struct QuranUIPlan: Sendable { var title: String; var input: QuranUIPlanInput; var forecast: QuranUIForecast; var nextAyah: Int; var versionLabel: String }
struct QuranUIStep: Identifiable, Sendable { var id: String; var title: String; var detail: String; var kind: QuranUIKind; var completed: Bool; var available: Bool; var range: QuranUIRange? }
struct QuranUIHeatDay: Identifiable, Sendable { var id: String; var title: String; var hifzFraction: Double; var reviewFraction: Double; var accessibilityLabel: String }
struct QuranUIDraft: Identifiable, Sendable { var id: UUID; var title: String; var isPastDay: Bool }
struct QuranUIHistorySession: Identifiable, Sendable { var id: UUID; var title: String; var dateLabel: String; var detail: String; var grades: [QuranUIPageGrade]; var warning: String? }
struct QuranUIPageGrade: Identifiable, Sendable { var page: Int; var title: String; var grade: QuranUIGrade; var explanation: String; var id: Int { page } }
struct QuranUIHistory: Sendable { var weekSummary: [String]; var yearSummary: [String]; var allSummary: [String]; var days: [QuranUIHeatDay]; var coverage: [QuranUIIndexItem]; var sessions: [QuranUIHistorySession] }
enum QuranUIIndexUnit: String, CaseIterable, Identifiable, Sendable {
    case surah, ayah, juz, hizb, page
    var id: String { rawValue }
    var title: String { switch self { case .surah: "السور"; case .ayah: "الآيات"; case .juz: "الأجزاء"; case .hizb: "الأحزاب"; case .page: "الأوجه" } }
    var icon: String { switch self { case .surah: "line.3.horizontal.decrease"; case .ayah: "rosette"; case .juz: "square.grid.2x2"; case .hizb: "square.grid.3x3"; case .page: "doc" } }
}
struct QuranUIIndexItem: Identifiable, Sendable { var id: String; var title: String; var subtitle: String; var firstPage: Int; var fraction: Double; var memorized: Bool; var reviewed: Bool; var due: Bool; var isToday: Bool }
struct QuranUIStrength: Identifiable, Sendable { var id: Int; var title: String; var value: Int?; var pageDetails: [String]; var canRaise: Bool; var reviewRange: QuranUIRange? }
struct QuranUIRecovery: Sendable { var distantLabel: String; var activeTitle: String?; var canCreate: Bool; var previews: [Int: QuranUIForecast] }
struct QuranUIQiyamPreview: Sendable { var rakaat: Int; var nightKey: String; var title: String; var assignments: [String]; var canBegin: Bool }
struct QuranUIErrorSpot: Identifiable, Sendable { var id: String; var title: String; var detail: String; var isToday: Bool; var closed: Bool; var canDrill: Bool }
struct QuranRoomState: Sendable {
    var coverageTitle: String
    var coverageFraction: Double
    var percentageLabel: String
    var streakLabel: String
    var balanceTitle: String
    var balanceExplanation: String
    var hifzLevel: QuranUILevel
    var reviewLevel: QuranUILevel
    var steps: [QuranUIStep]
    var recentDays: [QuranUIHeatDay]
    var plan: QuranUIPlan?
    var surahs: [QuranUISurah]
    var draft: QuranUIDraft?
    var missedDayKey: String?
    var missedDayTitle: String?
    var summary: [String]
    var history: QuranUIHistory
    var strengthTitle: String
    var strength: [QuranUIStrength]
    var recovery: QuranUIRecovery
    var errors: [QuranUIErrorSpot]
    var toolsOrder: [String]
    var availableTools: Set<String>
    var blockOrder: [String]
    var hiddenBlocks: Set<String>
    var sessionUnavailableReason: String?
    var readerUnavailableReason: String?
    var numeralLocale: String
}
enum QuranUICommand: Sendable {
    case setTodayLevel(kind: QuranUIKind, level: QuranUILevel)
    case forceNewHifz
    case savePlan(QuranUIPlanInput)
    case resolveMissed(dayKey: String, choice: QuranUIMissChoice)
    case editSessionGrade(sessionID: UUID, page: Int, grade: QuranUIGrade)
    case deleteSession(UUID)
    case createRecovery(days: Int)
    case cancelRecovery
    case raisePages(juz: Int)
}
struct QuranUILine: Identifiable, Sendable { var id: Int; var glyphs: String; var semanticText: String }
struct QuranUIPage: Sendable {
    var page: Int
    var title: String
    var postScriptName: String // registered, hash/glyph checked QCF V1 for THIS page
    var lines: [QuranUILine]
    var semanticAyat: [QuranUIVerse]
}
struct QuranUIVerse: Identifiable, Sendable { var id: Int; var title: String; var text: String; var hidden: Bool; var canReveal: Bool }
struct QuranUIAnswer: Identifiable, Sendable { var id: String; var text: String }
struct QuranUISimilar: Sendable { var title: String; var left: String; var right: String; var explanation: String }
enum QuranUISessionStage: String, Sendable { case repetition, lineStarts, recall, covered, grading, review, drill, qiyam }
enum QuranUISessionAction: Sendable {
    case advance
    case reveal(ayahID: Int, wordIndex: Int?)
    case mistake(ayahID: Int, wordIndex: Int?)
    case chooseAnswer(String)
    case grade(page: Int, grade: QuranUIGrade)
    case changeMethod(String)
    case commit, commitPartial, discard, saveProgress
}
struct QuranUISessionState: Identifiable, Sendable {
    var id: UUID
    var title: String
    var segmentTitle: String
    var stage: QuranUISessionStage
    var progress: Double
    var prompt: String
    var verses: [QuranUIVerse]
    var page: QuranUIPage?
    var answers: [QuranUIAnswer]
    var grades: [QuranUIPageGrade]
    var primaryTitle: String
    var primaryAction: QuranUISessionAction
    var canAdvance: Bool
    var mistakeAyahID: Int?
    var method: String
    var availableMethods: [String: String]
    var similar: QuranUISimilar?
    var resourceError: String?
}
enum QuranUISessionResult: Sendable { case active(QuranUISessionState), completed(summary: [String]), discarded }
@MainActor protocol QuranUIService: AnyObject {
    func load() async throws -> QuranRoomState
    func perform(_ command: QuranUICommand) async throws
    func previewPlan(_ input: QuranUIPlanInput) async throws -> QuranUIForecast
    func index(_ unit: QuranUIIndexUnit) async throws -> [QuranUIIndexItem]
    func page(_ page: Int) async throws -> QuranUIPage
    func qiyamPreview(rakaat: Int) async throws -> QuranUIQiyamPreview
    func start(kind: QuranUIKind, stepID: String?, range: QuranUIRange?, rakaat: Int?, spotID: String?) async throws -> QuranUISessionState
    func resume(draftID: UUID) async throws -> QuranUISessionState
    // Every action saves SessionDraft before returning. Commit checks commitID and is atomic.
    func session(draftID: UUID, action: QuranUISessionAction) async throws -> QuranUISessionResult
}
@MainActor @Observable final class QuranRoomModel {
    let service: any QuranUIService
    var state: QuranRoomState?
    var session: QuranUISessionState?
    var busy = false
    var error: String?
    var completion: [String]?
    init(service: any QuranUIService) { self.service = service }
    func refresh() async { guard !busy else { return }; do { state = try await service.load() } catch { self.error = error.localizedDescription } }
    func perform(_ command: QuranUICommand) async -> Bool {
        guard !busy else { return false }; busy = true; error = nil; defer { busy = false }
        do { try await service.perform(command) } catch { self.error = error.localizedDescription; return false }
        do { state = try await service.load() } catch { state = nil; self.error = "حُفظ التغيير، وتعذّرت إعادة القراءة: " + error.localizedDescription }
        return true
    }
    func begin(kind: QuranUIKind, stepID: String? = nil, range: QuranUIRange? = nil, rakaat: Int? = nil, spotID: String? = nil) async -> Bool {
        guard !busy else { return false }; busy = true; error = nil; defer { busy = false }
        do { session = try await service.start(kind: kind, stepID: stepID, range: range, rakaat: rakaat, spotID: spotID); return true } catch { self.error = error.localizedDescription; return false }
    }
    func resume(_ draft: QuranUIDraft) async {
        guard !busy else { return }; busy = true; defer { busy = false }
        do { session = try await service.resume(draftID: draft.id) } catch { self.error = error.localizedDescription }
    }
    func advance(_ action: QuranUISessionAction) async {
        guard !busy, let id = session?.id else { return }; busy = true; error = nil; defer { busy = false }
        do { switch try await service.session(draftID: id, action: action) { case .active(let next): session = next; case .completed(let summary, _): session = nil; completion = summary; state = try await service.load(); case .discarded: session = nil; state = try await service.load() } } catch { self.error = error.localizedDescription }
    }
}

struct QuranRoom: View {
    @State private var model: QuranRoomModel
    @State private var sheet: QuranSheet?
    @Environment(\.roomTheme) private var parentTheme
    @Environment(\.scenePhase) private var scenePhase
    let settingsService: any QuranSettingsUIService
    init(service: any QuranUIService, settingsService: any QuranSettingsUIService) { _model = State(initialValue: QuranRoomModel(service: service)); self.settingsService = settingsService }
    private var theme: RoomTheme { RoomTheme(room: "quran", dark: parentTheme.dark, calmPaper: parentTheme.calmPaper) }
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                if let state = model.state {
                    HStack { Text("القرآن").font(MadarTypography.title()); Spacer(); Button(state.streakLabel) { sheet = .plan }.font(MadarTypography.caption()).frame(minHeight: 44) }
                    if let draft = state.draft { MadarCard { VStack(alignment: .leading, spacing: 12) { Text(draft.title).font(MadarTypography.section()); Button(draft.isPastDay ? "احفظ ما تمّ أو تجاهل المسودة" : "تابع جلستك") { Task { await model.resume(draft) } }.accessibilityIdentifier("quran-resume") } } }
                    if let day = state.missedDayKey { missedCard(day: day, title: state.missedDayTitle ?? "لو فاتك يوم") }
                    if let reason = state.sessionUnavailableReason { MadarCard { Label(reason, systemImage: "info.circle").font(MadarTypography.caption()) } }
                    if state.plan == nil { Button("ابدأ خطة الحفظ") { sheet = .setup }.buttonStyle(MadarPrimaryButton()).accessibilityIdentifier("quran-start-plan") }
                    ForEach(blocks(state), id: \.self) { block in roomBlock(block, state: state) }
                } else { ContentUnavailableView("القرآن", systemImage: "book.closed", description: Text("تُقرأ خطة الحفظ وسجلّك من الجهاز.")); Button("حاول مجددًا") { Task { await model.refresh() } } }
            }.padding(16).frame(maxWidth: 700).frame(maxWidth: .infinity)
        }.background(theme.background).foregroundStyle(theme.ink).font(MadarTypography.body()).environment(\.roomTheme, theme)
        .navigationTitle("القرآن").navigationBarTitleDisplayMode(.inline)
        .toolbar { ToolbarItem(placement: .topBarTrailing) { NavigationLink { QuranSettingsView(service: settingsService) } label: { Image(systemName: "slider.horizontal.3") }.accessibilityLabel("خصّص القرآن").accessibilityIdentifier("quran-settings") } }
        .task { await model.refresh() }.refreshable { await model.refresh() }
        .onChange(of: scenePhase) { _, phase in if phase == .active { Task { await model.refresh() } } }
        .sheet(item: $sheet) { route in NavigationStack { sheetBody(route).toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { sheet = nil } } }.quranErrorAlert(model) }.environment(\.roomTheme, theme) }
        .fullScreenCover(item: Binding(get: { model.session }, set: { if $0 == nil { model.session = nil } })) { _ in QuranSessionView(model: model).environment(\.roomTheme, theme) }
        .sheet(isPresented: Binding(get: { model.completion != nil }, set: { if !$0 { model.completion = nil } })) { NavigationStack { QuranSummaryView(lines: model.completion ?? []).toolbar { ToolbarItem(placement: .confirmationAction) { Button("تم") { model.completion = nil } } } }.environment(\.roomTheme, theme) }
        .quranErrorAlert(model).disabled(model.busy)
    }
    private func blocks(_ state: QuranRoomState) -> [String] { ["sadr", "path", "log14", "tools"].sorted { (state.blockOrder.firstIndex(of: $0) ?? 99) < (state.blockOrder.firstIndex(of: $1) ?? 99) }.filter { !state.hiddenBlocks.contains($0) || ["sadr", "path"].contains($0) } }
    @ViewBuilder private func roomBlock(_ block: String, state: QuranRoomState) -> some View {
        switch block {
        case "sadr": VStack(alignment: .leading, spacing: 14) { Text("في صدرك").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Text(state.coverageTitle).font(MadarTypography.title()); ProgressView(value: state.coverageFraction).tint(theme.color("memorized")); Text(state.percentageLabel).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }.accessibilityIdentifier("quran-coverage")
        case "path": MadarCard { VStack(alignment: .leading, spacing: 18) { Text("مسار اليوم").font(MadarTypography.cardTitle()); levelControl("الحفظ الجديد", kind: .hifz, value: state.hifzLevel, color: theme.color("hifzText")); Text(state.balanceTitle).font(MadarTypography.section()); Text(state.balanceExplanation).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk); Button("زِد حفظك رغم ذلك") { Task { _ = await model.perform(.forceNewHifz) } }.frame(minHeight: 44).accessibilityIdentifier("quran-force-new"); ForEach(state.steps.filter { [.bridge, .hifz].contains($0.kind) }) { step in stepRow(step) }; levelControl("المراجعة", kind: .review, value: state.reviewLevel, color: theme.color("reviewText")); ForEach(state.steps.filter { ![.bridge, .hifz].contains($0.kind) }) { step in stepRow(step) }; if !state.summary.isEmpty { Button("ختام اليوم") { sheet = .summary }.frame(minHeight: 44).accessibilityIdentifier("quran-summary") } } }
        case "log14": MadarCard { VStack(alignment: .leading, spacing: 14) { HStack { Text("سجلّك").font(MadarTypography.cardTitle()); Spacer(); Button("السجلّ كاملًا") { sheet = .history }.accessibilityIdentifier("quran-history") }; QuranHeatMap(days: state.recentDays) } }
        case "tools": tools(state)
        default: EmptyView()
        }
    }
    private func levelControl(_ title: String, kind: QuranUIKind, value: QuranUILevel, color: Color) -> some View { VStack(alignment: .leading, spacing: 12) { Text(title).font(MadarTypography.section()).foregroundStyle(color); Picker(title, selection: Binding(get: { value }, set: { level in Task { _ = await model.perform(.setTodayLevel(kind: kind, level: level)) } })) { ForEach(QuranUILevel.allCases) { Text($0.title).tag($0) } }.pickerStyle(.segmented).accessibilityIdentifier("quran-today-level-" + kind.rawValue) } }
    private func stepRow(_ step: QuranUIStep) -> some View { Button { Task { _ = await model.begin(kind: step.kind, stepID: step.id, range: step.range) } } label: { HStack { VStack(alignment: .leading, spacing: 7) { Text(step.title).font(MadarTypography.cardTitle()).strikethrough(step.completed); Text(step.detail).font(MadarTypography.caption()) }; Spacer(); Image(systemName: step.completed ? "checkmark.circle" : "arrow.forward.circle.fill") }.frame(minHeight: 56).opacity(step.completed ? 0.55 : 1) }.disabled(!step.available || step.completed || model.state?.sessionUnavailableReason != nil).accessibilityIdentifier("quran-step-" + step.id) }
    private func tools(_ state: QuranRoomState) -> some View { MadarCard { LazyVGrid(columns: [GridItem(.adaptive(minimum: 90))], spacing: 14) { ForEach(state.toolsOrder.filter { state.availableTools.contains($0) }, id: \.self) { tool in Button { switch tool { case "mushaf": sheet = .reader(1); case "fihris": sheet = .index; case "free": sheet = .free; case "retention": sheet = .retention; case "qiyam": sheet = .qiyam; default: break } } label: { VStack(spacing: 8) { Image(systemName: toolIcon(tool)).frame(width: 44, height: 44).background(theme.color("reviewTint"), in: .rect(cornerRadius: 14)); Text(toolTitle(tool)).font(MadarTypography.caption()) }.frame(minHeight: 74) }.accessibilityIdentifier("quran-tool-" + tool) } } } }
    private func missedCard(day: String, title: String) -> some View { MadarCard { VStack(alignment: .leading, spacing: 12) { Text(title).font(MadarTypography.cardTitle()); ForEach(QuranUIMissChoice.allCases) { choice in Button(choice.title) { Task { _ = await model.perform(.resolveMissed(dayKey: day, choice: choice)) } }.frame(minHeight: 44).accessibilityIdentifier("quran-missed-" + choice.rawValue) } } } }
    @ViewBuilder private func sheetBody(_ route: QuranSheet) -> some View {
        switch route {
        case .setup: QuranPlanWizard(model: model)
        case .plan: QuranPlanView(model: model, edit: { sheet = .setup })
        case .history: QuranHistoryView(model: model)
        case .summary: QuranSummaryView(lines: model.state?.summary ?? [])
        case .index: QuranIndexView(service: model.service, read: { sheet = .reader($0) })
        case .reader(let page): QuranReaderView(service: model.service, initialPage: page)
        case .free: QuranFreeView(model: model, close: { sheet = nil })
        case .retention: QuranRetentionView(model: model)
        case .qiyam: QuranQiyamView(model: model, close: { sheet = nil })
        }
    }
    private func toolTitle(_ key: String) -> String { switch key { case "mushaf": "المصحف"; case "fihris": "الفهرس"; case "free": "مراجعة حرة"; case "retention": "منسوب الحفظ"; case "qiyam": "ورد القيام"; default: key } }
    private func toolIcon(_ key: String) -> String { switch key { case "mushaf": "book"; case "fihris": "line.3.horizontal.decrease"; case "free": "arrow.left.arrow.right"; case "retention": "chart.bar"; case "qiyam": "moon"; default: "circle" } }
}
private enum QuranSheet: Identifiable { case setup, plan, history, summary, index, reader(Int), free, retention, qiyam; var id: String { switch self { case .setup: "setup"; case .plan: "plan"; case .history: "history"; case .summary: "summary"; case .index: "index"; case .reader(let page): "page-\(page)"; case .free: "free"; case .retention: "retention"; case .qiyam: "qiyam" } } }
private extension View {
    func quranErrorAlert(_ model: QuranRoomModel) -> some View { alert("تعذّر إتمام العملية", isPresented: Binding(get: { model.error != nil }, set: { if !$0 { model.error = nil } })) { Button("حسنًا") { model.error = nil } } message: { Text(model.error ?? "") } }
}
