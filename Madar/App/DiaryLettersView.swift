import SwiftUI
import MadarCore
import MadarDesign

/// §7.3 N04 «أرشيف الرسائل»: a mailbox. Sealed letters show an hourglass and when they open, never their text.
struct DiaryLettersPanel: View {
    @Bindable var app: AppSession
    var initialLetterID: UUID? = nil
    var initialLetterRequestID: UUID? = nil
    @Environment(\.roomTheme) private var theme
    @State private var letters: [DiaryLetterCard] = []
    @State private var composing = false
    @State private var opening: DiaryLetterCard?
    @State private var reading: DiaryLetterCard?
    @State private var rescheduling: DiaryLetterCard?
    @State private var failure: String?
    @State private var routeMessage: String?
    @State private var handledRouteID: UUID?
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) { Text("صندوق البريد").font(DiaryType.heading); Text("رسائل تكتبها اليوم، وتُفتح حين يحين وقتها").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                Spacer()
            }
            Button { composing = true } label: { Label("اكتب رسالة لنفسك", systemImage: "envelope").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .capsule) }
                .buttonStyle(.madarPlain).accessibilityIdentifier("diary-letter-compose")
            if let failure {
                VStack(alignment: .leading, spacing: 8) {
                    Text(failure).font(MadarTypography.body())
                    Button { Task { await load() } } label: { Text("أعِد المحاولة")
                        .font(DiaryType.label).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-letters-retry")
                }
            }
            if let routeMessage { Text(routeMessage).font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).accessibilityIdentifier("diary-letter-route-status") }
            let waiting = letters.filter { $0.state == .eligible }, orphaned = letters.filter { $0.state == .orphaned }
            let sealed = letters.filter { $0.state == .sealed }, opened = letters.filter { $0.state == .opened }
            if letters.isEmpty && failure == nil { Text("لا رسائل بعد. اكتب لنفسك في موعد أو بعد حدث.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 20) }
            ForEach(waiting) { letter in DiaryLetterWaitingCard(letter: letter, digitsTitle: service.diaryDates(letter.writtenDay)) { opening = letter } }
            ForEach(orphaned) { letter in
                VStack(alignment: .leading, spacing: 10) {
                    Text("هدف رسالتك حُذف").font(DiaryType.heading)
                    MadarDateLabel("كتبتها في " + service.diaryDates(letter.writtenDay) + ". لا تُفتح وحدها.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    HStack(spacing: 8) {
                        Button { opening = letter } label: { Text("افتحها الآن").frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }.accessibilityIdentifier("diary-letter-orphan-open")
                        Button { rescheduling = letter } label: { Text("اختر موعدًا").frame(maxWidth: .infinity, minHeight: 44).glassEffect(.regular.interactive(), in: .capsule) }.accessibilityIdentifier("diary-letter-orphan-date")
                    }.font(DiaryType.label).buttonStyle(.madarPlain)
                }.padding(16).background(theme.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line) }
            }
            if !sealed.isEmpty {
                Text("مختومة").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).padding(.top, 6)
                ForEach(sealed) { letter in
                    HStack(spacing: 14) {
                        DiaryEnvelope(sealed: true).frame(width: 64, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(letter.waitingFor).font(DiaryType.writing)
                            MadarDateLabel("كُتبت في " + service.diaryDates(letter.writtenDay)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                        }
                        Spacer(minLength: 0)
                        Image(systemName: "hourglass").foregroundStyle(theme.color("ink3Text")).accessibilityLabel("تنتظر")
                    }.padding(.vertical, 8).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }
                        .accessibilityElement(children: .combine).accessibilityIdentifier("diary-letter-sealed")
                }
            }
            if !opened.isEmpty {
                Text("فُتحت").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).padding(.top, 6)
                ForEach(opened) { letter in
                    Button { reading = letter } label: {
                        HStack(spacing: 14) {
                            DiaryEnvelope(sealed: false).frame(width: 64, height: 44)
                            VStack(alignment: .leading, spacing: 4) {
                                Text(letter.text ?? "").font(DiaryType.writing).lineLimit(2).multilineTextAlignment(.leading)
                                MadarDateLabel("من " + service.diaryDates(letter.writtenDay)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8).contentShape(.rect)
                    }.buttonStyle(.madarPlain).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }.accessibilityIdentifier("diary-letter-opened")
                }
            }
        }
        .task(id: app.prayerRevision) { await load() }
        .onChange(of: initialLetterID) { _, id in if let id, !letters.isEmpty { openRoutedLetter(id) } }
        .onChange(of: initialLetterRequestID) { _, requestID in
            guard requestID != nil, let initialLetterID else { return }
            handledRouteID = nil
            if !letters.isEmpty { openRoutedLetter(initialLetterID) }
        }
        .sheet(isPresented: $composing) { DiaryLetterComposer(app: app).environment(\.roomTheme, theme) }
        .sheet(item: $opening) { letter in DiaryLetterMoment(app: app, letter: letter).environment(\.roomTheme, theme) }
        .sheet(item: $reading) { letter in DiaryLetterReader(text: letter.text ?? "", written: service.diaryDates(letter.writtenDay)).environment(\.roomTheme, theme).presentationDetents([.medium, .large]) }
        .sheet(item: $rescheduling) { letter in DiaryLetterReschedule(app: app, letter: letter).environment(\.roomTheme, theme).presentationDetents([.medium]) }
    }
    private func load() async {
        do {
            try await service.refreshLetters()
            letters = try service.letters()
            failure = nil
            if let initialLetterID { openRoutedLetter(initialLetterID) }
        } catch { letters = []; failure = madarUserMessage(error) }
    }
    private func openRoutedLetter(_ id: UUID) {
        guard handledRouteID != id else { return }
        handledRouteID = id
        routeMessage = nil
        guard let letter = letters.first(where: { $0.id == id }) else {
            routeMessage = "هذه الرسالة لم تعد موجودة في صندوق البريد."
            return
        }
        switch letter.state {
        case .opened: reading = letter
        case .eligible, .orphaned: opening = letter
        case .sealed: routeMessage = "هذه الرسالة ما زالت مختومة؛ سيبقى نصّها مخفيًا حتى يحين موعد فتحها."
        }
    }
}

struct DiaryLetterWaitingCard: View {
    let letter: DiaryLetterCard
    let digitsTitle: String
    let open: () -> Void
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Button(action: open) {
            HStack(spacing: 14) {
                DiaryEnvelope(sealed: true).frame(width: 72, height: 50)
                VStack(alignment: .leading, spacing: 4) {
                    Text("رسالة من الماضي تنتظرك").font(DiaryType.heading)
                    MadarDateLabel("كتبتها في " + digitsTitle).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.backward").font(.caption)
            }.padding(16).background(theme.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.5)) }.contentShape(.rect)
        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-letter-waiting")
    }
}

/// An envelope with a wax seal (sealed) or an open flap.
struct DiaryEnvelope: View {
    let sealed: Bool
    @Environment(\.roomTheme) private var theme
    var body: some View {
        Canvas { context, size in
            let r = CGRect(origin: .zero, size: size).insetBy(dx: 1, dy: 1)
            context.fill(Path(roundedRect: r, cornerRadius: 3), with: .color(theme.surface))
            context.stroke(Path(roundedRect: r, cornerRadius: 3), with: .color(theme.color("ink3Text")), lineWidth: 1)
            var flap = Path(); flap.move(to: .init(x: r.minX, y: r.minY))
            flap.addLine(to: .init(x: r.midX, y: r.midY + 2)); flap.addLine(to: .init(x: r.maxX, y: r.minY))
            context.stroke(flap, with: .color(theme.color("ink3Text")), lineWidth: 1)
            if !sealed {
                // Opened: the flap is folded back and a sheet shows above the fold.
                var sheet = Path(); sheet.addRect(.init(x: r.minX + r.width * 0.18, y: r.minY + 3, width: r.width * 0.64, height: r.height * 0.32))
                context.fill(sheet, with: .color(theme.background)); context.stroke(sheet, with: .color(theme.color("ink3Text")), lineWidth: 0.8)
            }
            if sealed {
                let d = min(size.width, size.height) * 0.36
                context.fill(Path(ellipseIn: .init(x: r.midX - d / 2, y: r.midY + 2 - d / 2, width: d, height: d)), with: .color(theme.color("seal")))
            }
        }.accessibilityHidden(true)
    }
}

/// «لحظة الفتح»: the envelope first, then the text, once.
struct DiaryLetterMoment: View {
    @Bindable var app: AppSession
    let letter: DiaryLetterCard
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text: String?
    @State private var failure: String?
    @State private var opening = false
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    MadarDateLabel("رسالة كتبتها في " + service.diaryDates(letter.writtenDay)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if let text {
                        Text(text).font(.custom("thmanyahseriftext-Regular", size: 21, relativeTo: .body)).lineSpacing(10).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22).background(theme.surface, in: .rect(cornerRadius: 6)).overlay { RoundedRectangle(cornerRadius: 6).stroke(theme.line) }
                            .textSelection(.enabled).transition(.opacity.combined(with: .move(edge: .bottom))).accessibilityIdentifier("diary-letter-text")
                    } else {
                        DiaryEnvelope(sealed: true).frame(width: 220, height: 150).padding(.top, 30)
                        Button { guard !opening else { return }; opening = true; Task { defer { opening = false }; do { let value = try await service.openLetter(letter.id); withAnimation(.easeOut(duration: 0.5)) { text = value } } catch { failure = madarUserMessage(error) } } } label: {
                            Text("افتح الرسالة").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .capsule)
                        }.buttonStyle(.madarPlain).accessibilityIdentifier("diary-letter-open")
                    }
                    if let failure { Text(failure).font(MadarTypography.body()) }
                }.padding(22)
            }.background(theme.background).foregroundStyle(theme.ink)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تمّ") { dismiss() }.accessibilityIdentifier("diary-letter-done") } }
                .toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
        }
    }
}

struct DiaryLetterReader: View {
    let text: String
    let written: String
    @Environment(\.roomTheme) private var theme
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("من " + written).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                Text(text).font(DiaryType.writing).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .leading)
            }.padding(22)
        }.background(theme.background).foregroundStyle(theme.ink)
    }
}

struct DiaryLetterComposer: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var choices: [DiaryLetterChoice] = []
    @State private var choice: DiaryLetterChoice?
    @State private var date = Date().addingTimeInterval(30 * 86_400)
    @State private var confirmDiscard = false
    @State private var failure: String?
    @State private var saving = false
    private var service: AppDiaryService { .init(app: app) }
    private var blocksRootRoute: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || saving }
    private var pickerOffset: Int { choice?.trigger == .hijriDate ? service.letterPickerOffset : 0 }
    private var pickerDate: Binding<Date> {
        Binding(get: { service.letterPickerDate(date, by: pickerOffset) },
                set: { date = service.letterPickerDate($0, by: -pickerOffset) })
    }
    private var firstDate: Date {
        let today = (try? service.currentDay()) ?? GregorianDay.containing(app.prayerNow(), in: app.activePlace.timeZone)
        return service.letterPickerDate(today.adding(days: 1).date(in: app.activePlace.timeZone), by: pickerOffset)
    }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
#if DEBUG
                    if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                        Button("اختبر الجذر") { app.open(URL(string: "madar://notes")!) }
                            .accessibilityIdentifier("diary-letter-root-route")
                    }
#endif
                    TextEditor(text: $text).font(DiaryType.writing).scrollContentBackground(.hidden).frame(minHeight: 200)
                        .padding(12).background(theme.surface, in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line) }
                        .overlay(alignment: .topLeading) { if text.isEmpty { Text("إلى نفسي…").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(20).allowsHitTesting(false) } }
                        .disabled(saving).accessibilityIdentifier("diary-letter-text-input")
                    Text("متى تُفتح؟").font(DiaryType.heading)
                    ForEach(choices) { item in
                        Button { choice = item } label: {
                            HStack { Text(item.title).font(DiaryType.writing); Spacer(); Image(systemName: choice == item ? "largecircle.fill.circle" : "circle").foregroundStyle(choice == item ? theme.accent : theme.color("ink3Text")) }.frame(minHeight: 44).contentShape(.rect)
                        }.buttonStyle(.madarPlain).disabled(saving).accessibilityIdentifier("diary-letter-trigger-" + item.id).accessibilityAddTraits(choice == item ? .isSelected : [])
                    }
                    if choice?.trigger == .date || choice?.trigger == .hijriDate {
                        DatePicker("اليوم", selection: pickerDate, in: firstDate..., displayedComponents: .date)
                            .environment(\.calendar, service.letterPickerCalendar(hijri: choice?.trigger == .hijriDate))
                            .environment(\.timeZone, app.activePlace.timeZone).font(DiaryType.writing).disabled(saving)
                            .accessibilityIdentifier("diary-letter-date")
                        MadarDateLabel(app.dateLabels(GregorianDay.containing(date, in: app.activePlace.timeZone)))
                    }
                    Text("لا يدخل نصّها البحث ولا الودجات ولا الإشعارات قبل أن تُفتح.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if let failure { Text(failure).font(MadarTypography.body()) }
                    // AU-95: without its choices «اختمها» stayed dim and the written letter had nowhere to go.
                    if choices.isEmpty, failure != nil {
                        Button { loadChoices() } label: { Text("أعِد المحاولة").font(MadarTypography.section()).frame(minHeight: 44).contentShape(Rectangle()) }.accessibilityIdentifier("diary-letter-choices-retry")
                    }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("رسالة لنفسك").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { dismiss() } else { confirmDiscard = true } }.madarWaitsForSave().accessibilityIdentifier("diary-letter-cancel") }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("اختمها") {
                            guard !saving, let choice else { return }; saving = true
                            Task { defer { saving = false }
                                do { try await service.sealLetter(text, choice: choice, date: date); dismiss() } catch { failure = madarUserMessage(error) } }
                        }
                            .disabled(saving || choice == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("diary-letter-seal")
                    }
                }.toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .task { loadChoices() }
                // A letter in progress is not lost to a stray swipe or cancel.
                .madarSheetLock(saving: saving, draft: !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .alert("تتجاهل رسالتك؟", isPresented: $confirmDiscard) {
                    Button("تجاهل الرسالة", role: .destructive) { dismiss() }
                    Button("أكمل الكتابة", role: .cancel) {}
                }
        }.diaryRootDraftBlocking(app, isBlocking: blocksRootRoute)
    }
    private func loadChoices() {
        do { choices = try service.letterChoices(); choice = choice ?? choices.first; failure = nil } catch { failure = madarUserMessage(error) }
    }
}

struct DiaryLetterReschedule: View {
    @Bindable var app: AppSession
    let letter: DiaryLetterCard
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(7 * 86_400)
    @State private var failure: String?
    @State private var rescheduling = false
    @State private var originalDay: GregorianDay?
    @State private var dateChanged = false
    private var blocksRootRoute: Bool { dateChanged || rescheduling }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
#if DEBUG
            if ProcessInfo.processInfo.environment["MADAR_UI_DIARY_ROOT_ROUTE_HARNESS"] == "1" {
                Button("اختبر الجذر") { app.open(URL(string: "madar://notes")!) }
                    .accessibilityIdentifier("diary-letter-reschedule-root-route")
            }
#endif
            Text("اختر موعدًا لرسالتك").font(DiaryType.heading)
            DatePicker("اليوم", selection: $date, in: Date().addingTimeInterval(86_400)..., displayedComponents: .date).font(DiaryType.writing)
            MadarDateLabel(app.dateLabels(GregorianDay.containing(date, in: app.activePlace.timeZone)))
            if let failure { Text(failure).font(MadarTypography.body()) }
            Button { guard !rescheduling else { return }; rescheduling = true; Task { defer { rescheduling = false }; do { try await AppDiaryService(app: app).rescheduleLetter(letter.id, to: date); dismiss() } catch { failure = madarUserMessage(error) } } } label: {
                Text("احفظ الموعد").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
            }.buttonStyle(.madarPlain).disabled(rescheduling).accessibilityIdentifier("diary-letter-reschedule-save")
        }.padding(22).frame(maxHeight: .infinity, alignment: .top).background(theme.background).foregroundStyle(theme.ink)
            .madarSheetLock(saving: rescheduling, draft: dateChanged)
            .onAppear { originalDay = GregorianDay.containing(date, in: app.activePlace.timeZone) }
            .onChange(of: date) { _, value in
                let selectedDay = GregorianDay.containing(value, in: app.activePlace.timeZone)
                dateChanged = originalDay.map { $0 != selectedDay } ?? false
            }
            .diaryRootDraftBlocking(app, isBlocking: blocksRootRoute)
    }
}
