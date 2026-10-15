import SwiftUI
import MadarCore
import MadarDesign

/// §7.3 N04 «أرشيف الرسائل»: a mailbox. Sealed letters show an hourglass and when they open, never their text.
struct DiaryLettersPanel: View {
    @Bindable var app: AppSession
    @Environment(\.roomTheme) private var theme
    @State private var letters: [DiaryLetterCard] = []
    @State private var composing = false
    @State private var opening: DiaryLetterCard?
    @State private var reading: DiaryLetterCard?
    @State private var rescheduling: DiaryLetterCard?
    @State private var failure: String?
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 4) { Text("صندوق البريد").font(DiaryType.heading); Text("رسائل تكتبها اليوم، وتُفتح حين يحين وقتها").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")) }
                Spacer()
            }
            Button { composing = true } label: { Label("اكتب رسالة لنفسك", systemImage: "envelope").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .capsule) }
                .buttonStyle(.plain).accessibilityIdentifier("diary-letter-compose")
            if let failure { Text(failure).font(MadarTypography.body()) }
            let waiting = letters.filter { $0.state == .eligible }, orphaned = letters.filter { $0.state == .orphaned }
            let sealed = letters.filter { $0.state == .sealed }, opened = letters.filter { $0.state == .opened }
            if letters.isEmpty { Text("لا رسائل بعد. اكتب لنفسك في موعد أو بعد حدث.").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(.vertical, 20) }
            ForEach(waiting) { letter in DiaryLetterWaitingCard(letter: letter, digitsTitle: service.dateTitle(letter.writtenDay, calendar: .gregorian)) { opening = letter } }
            ForEach(orphaned) { letter in
                VStack(alignment: .leading, spacing: 10) {
                    Text("هدف رسالتك حُذف").font(DiaryType.heading)
                    Text("كتبتها في " + service.dateTitle(letter.writtenDay, calendar: .gregorian) + ". لا تُفتح وحدها.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    HStack(spacing: 8) {
                        Button { opening = letter } label: { Text("افتحها الآن").frame(maxWidth: .infinity, minHeight: 44).foregroundStyle(theme.background).background(theme.ink, in: .capsule) }.accessibilityIdentifier("diary-letter-orphan-open")
                        Button { rescheduling = letter } label: { Text("اختر موعدًا").frame(maxWidth: .infinity, minHeight: 44).overlay { Capsule().stroke(theme.line) } }.accessibilityIdentifier("diary-letter-orphan-date")
                    }.font(DiaryType.label).buttonStyle(.plain)
                }.padding(16).background(theme.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.line) }
            }
            if !sealed.isEmpty {
                Text("مختومة").font(DiaryType.label).foregroundStyle(theme.color("ink3Text")).padding(.top, 6)
                ForEach(sealed) { letter in
                    HStack(spacing: 14) {
                        DiaryEnvelope(sealed: true).frame(width: 64, height: 44)
                        VStack(alignment: .leading, spacing: 4) {
                            Text(letter.waitingFor).font(DiaryType.writing)
                            Text("كُتبت في " + service.dateTitle(letter.writtenDay, calendar: .gregorian)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
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
                                Text("من " + service.dateTitle(letter.writtenDay, calendar: .gregorian)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                            }
                            Spacer(minLength: 0)
                        }.padding(.vertical, 8).contentShape(.rect)
                    }.buttonStyle(.plain).overlay(alignment: .bottom) { Rectangle().fill(theme.line).frame(height: 1) }.accessibilityIdentifier("diary-letter-opened")
                }
            }
        }
        .task(id: app.prayerRevision) { await load() }
        .sheet(isPresented: $composing) { DiaryLetterComposer(app: app).environment(\.roomTheme, theme) }
        .sheet(item: $opening) { letter in DiaryLetterMoment(app: app, letter: letter).environment(\.roomTheme, theme) }
        .sheet(item: $reading) { letter in DiaryLetterReader(text: letter.text ?? "", written: service.dateTitle(letter.writtenDay, calendar: .gregorian)).environment(\.roomTheme, theme).presentationDetents([.medium, .large]) }
        .sheet(item: $rescheduling) { letter in DiaryLetterReschedule(app: app, letter: letter).environment(\.roomTheme, theme).presentationDetents([.medium]) }
    }
    private func load() async {
        do { try await service.refreshLetters(); letters = try service.letters(); failure = nil } catch { failure = error.localizedDescription }
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
                    Text("كتبتها في " + digitsTitle).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                }
                Spacer(minLength: 0)
                Image(systemName: "chevron.backward").font(.caption)
            }.padding(16).background(theme.surface, in: .rect(cornerRadius: 16)).overlay { RoundedRectangle(cornerRadius: 16).stroke(theme.accent.opacity(0.5)) }.contentShape(.rect)
        }.buttonStyle(.plain).accessibilityIdentifier("diary-letter-waiting")
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
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    Text("رسالة كتبتها في " + service.dateTitle(letter.writtenDay, calendar: .gregorian)).font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if let text {
                        Text(text).font(.custom("thmanyahseriftext-Regular", size: 21, relativeTo: .body)).lineSpacing(10).frame(maxWidth: .infinity, alignment: .leading)
                            .padding(22).background(theme.surface, in: .rect(cornerRadius: 6)).overlay { RoundedRectangle(cornerRadius: 6).stroke(theme.line) }
                            .textSelection(.enabled).transition(.opacity.combined(with: .move(edge: .bottom))).accessibilityIdentifier("diary-letter-text")
                    } else {
                        DiaryEnvelope(sealed: true).frame(width: 220, height: 150).padding(.top, 30)
                        Button { Task { do { let value = try await service.openLetter(letter.id); withAnimation(.easeOut(duration: 0.5)) { text = value } } catch { failure = error.localizedDescription } } } label: {
                            Text("افتح الرسالة").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 52).foregroundStyle(theme.background).background(theme.dark ? theme.accent : theme.ink, in: .capsule)
                        }.buttonStyle(.plain).accessibilityIdentifier("diary-letter-open")
                    }
                    if let failure { Text(failure).font(MadarTypography.body()) }
                }.padding(22)
            }.background(theme.background).foregroundStyle(theme.ink)
                .toolbar { ToolbarItem(placement: .topBarLeading) { Button("تم") { dismiss() }.accessibilityIdentifier("diary-letter-done") } }
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
    @State private var failure: String?
    @State private var saving = false
    private var service: AppDiaryService { .init(app: app) }
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    TextEditor(text: $text).font(DiaryType.writing).scrollContentBackground(.hidden).frame(minHeight: 200)
                        .padding(12).background(theme.surface, in: .rect(cornerRadius: 14)).overlay { RoundedRectangle(cornerRadius: 14).stroke(theme.line) }
                        .overlay(alignment: .topLeading) { if text.isEmpty { Text("إلى نفسي…").font(DiaryType.writing).foregroundStyle(theme.color("ink3Text")).padding(20).allowsHitTesting(false) } }
                        .accessibilityIdentifier("diary-letter-text-input")
                    Text("متى تُفتح؟").font(DiaryType.heading)
                    ForEach(choices) { item in
                        Button { choice = item } label: {
                            HStack { Text(item.title).font(DiaryType.writing); Spacer(); Image(systemName: choice == item ? "largecircle.fill.circle" : "circle").foregroundStyle(choice == item ? theme.accent : theme.color("ink3Text")) }.frame(minHeight: 44).contentShape(.rect)
                        }.buttonStyle(.plain).accessibilityIdentifier("diary-letter-trigger-" + item.id).accessibilityAddTraits(choice == item ? .isSelected : [])
                    }
                    if choice?.trigger == .date || choice?.trigger == .hijriDate {
                        DatePicker("اليوم", selection: $date, in: Date().addingTimeInterval(86_400)..., displayedComponents: .date)
                            .environment(\.calendar, Calendar(identifier: choice?.trigger == .hijriDate ? .islamicUmmAlQura : .gregorian)).font(DiaryType.writing)
                    }
                    Text("لا يدخل نصّها البحث ولا الودجات ولا الإشعارات قبل أن تُفتح.").font(DiaryType.label).foregroundStyle(theme.color("ink3Text"))
                    if let failure { Text(failure).font(MadarTypography.body()) }
                }.padding(18)
            }.background(theme.background).foregroundStyle(theme.ink)
                .navigationTitle("رسالة لنفسك").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("إلغاء") { dismiss() } }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("اختمها") { Task { guard let choice else { return }; saving = true; defer { saving = false }
                            do { try await service.sealLetter(text, choice: choice, date: date); dismiss() } catch { failure = error.localizedDescription } } }
                            .disabled(saving || choice == nil || text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty).accessibilityIdentifier("diary-letter-seal")
                    }
                }.toolbarBackground(theme.background, for: .navigationBar).tint(theme.accent)
                .task { do { choices = try service.letterChoices(); choice = choice ?? choices.first } catch { failure = error.localizedDescription } }
        }
    }
}

struct DiaryLetterReschedule: View {
    @Bindable var app: AppSession
    let letter: DiaryLetterCard
    @Environment(\.roomTheme) private var theme
    @Environment(\.dismiss) private var dismiss
    @State private var date = Date().addingTimeInterval(7 * 86_400)
    @State private var failure: String?
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("اختر موعدًا لرسالتك").font(DiaryType.heading)
            DatePicker("اليوم", selection: $date, in: Date().addingTimeInterval(86_400)..., displayedComponents: .date).font(DiaryType.writing)
            if let failure { Text(failure).font(MadarTypography.body()) }
            Button { Task { do { try await AppDiaryService(app: app).rescheduleLetter(letter.id, to: date); dismiss() } catch { failure = error.localizedDescription } } } label: {
                Text("احفظ الموعد").font(MadarTypography.section()).frame(maxWidth: .infinity, minHeight: 50).foregroundStyle(theme.background).background(theme.ink, in: .capsule)
            }.buttonStyle(.plain).accessibilityIdentifier("diary-letter-reschedule-save")
        }.padding(22).frame(maxHeight: .infinity, alignment: .top).background(theme.background).foregroundStyle(theme.ink)
    }
}
