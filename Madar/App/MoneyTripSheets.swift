import SwiftUI
import SwiftData
import MadarData
import MadarCommands
import MadarCore
import MadarDesign
import MadarMoney

struct MoneyTripRateSheet: View {
    let app: AppSession
    let reading: MoneyTravelReading
    let visible: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var currency = ""
    @State private var preview: MoneyTripReprice?
    @State private var previewOpen = false
    @State private var raw = ""
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    private var service: AppMoneyService { .init(app: app) }
    private var rate: String? { currency == app.string("core.currency") ? "1" : TravelBudget.canonicalRate(raw) }
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) {
            HStack { Text("عملة الرحلة وسعرها").font(MadarTypography.cardTitle()); Spacer(); Button("إغلاق") { dismiss() }.madarWaitsForSave().frame(minHeight: 44).accessibilityIdentifier("money-trip-rate-close") }
            Picker("عملة البلد", selection: $currency) { ForEach(CurrencyExponents.specified.exponents.keys.sorted(), id: \.self) { code in Text(service.currencyName(code) + " (" + code + ")").tag(code) } }.accessibilityIdentifier("money-trip-currency")
            if currency != app.string("core.currency") {
                Text("كل وحدة من " + service.currencyName(currency) + " تساوي، بعملة البيت:").font(MadarTypography.body())
                TextField("سعر الصرف", text: $raw).keyboardType(.decimalPad).focused($focused).font(.title2).padding(12).background(theme.surface).accessibilityIdentifier("money-trip-rate-input")
                if let rate, let example = try? FX.homeAmount(amountMinor: 100 * scale(currency), currency: currency, rate: rate, home: app.string("core.currency")) { Text(figure: service.digits.string(100) + " " + service.currencyName(currency) + " = " + service.amount(example) + " " + service.currencyName(app.string("core.currency"))).font(MadarTypography.caption()).accessibilityIdentifier("money-trip-rate-preview") }
            }
            if let at = reading.rateAt { VStack(alignment: .leading, spacing: 3) { Text("آخر سعر أدخلته").font(MadarTypography.caption()); MadarDateLabel(app.dateLabels(.containing(at, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine()); Text(service.time(at)).font(MadarTypography.fine()) }.foregroundStyle(theme.secondaryInk) }
            Text("السعر يدوي. يُحفظ مع كل حركة وقت تسجيلها؛ تغيير هذا السعر لا يغيّر مصروفاتك السابقة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            if let failure { Text(failure).font(MadarTypography.caption()) }
            // AU-34: hidden numbers say why save waits.
            if !visible { Text("أرقامك مخفية؛ أظهرها من صفحة الرحلة لتحفظ").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-trip-hidden-hint") }
            Button { save() } label: { Text(saving ? "جارٍ الحفظ…" : "احفظ السعر").frame(maxWidth: .infinity, minHeight: 50).background(theme.ink).foregroundStyle(theme.background) }.disabled(saving || rate == nil || !visible).accessibilityIdentifier("money-trip-rate-save")
            if reading.currency != app.string("core.currency"), reading.rate != nil {
                Button("معاينة تطبيق السعر المحفوظ على حركات الرحلة") {
                    do { preview = try MoneyRepository(context: ModelContext(app.container)).previewTripReprice(id: reading.id, rate: reading.rate!, at: app.prayerNow()); previewOpen = true }
                    catch { failure = "تعذّرت المعاينة. افتح الورقة من جديد وحاول مرة أخرى." }
                }.disabled(!visible || saving).font(MadarTypography.caption()).frame(minHeight: 44).accessibilityIdentifier("money-trip-reprice-preview")
            }
        }.padding(22) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain).scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { focused = false }.accessibilityIdentifier("money-trip-keyboard-done") } }
            .sheet(isPresented: $previewOpen) { if let preview { repricePreview(preview) } }
            .task { currency = reading.currency ?? app.string("core.currency"); raw = reading.rate.map(service.localizedRate) ?? "" }
            .madarSheetLock(saving: saving)
        }
    }
    private func repricePreview(_ p: MoneyTripReprice) -> some View {
        ScrollView { VStack(alignment: .leading, spacing: 14) {
            HStack { Text("قبل تطبيق السعر").font(MadarTypography.cardTitle()); Spacer(); Button("إغلاق") { previewOpen = false }.disabled(saving).frame(minHeight: 44).accessibilityIdentifier("money-trip-reprice-close") }
            Text("هذه القيم بعملة البيت. المبلغ الأصلي ويوم الحركة لا يتغيّران.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            ForEach(p.lines) { row in HStack { Text(row.title); Spacer(); Text(figure: service.amount(row.beforeMinor) + " ← " + service.amount(row.afterMinor)) }.font(MadarTypography.body()) }
            if p.excludedCount > 0 { Text("تبقى الحركات ذات سعر البنك وتقارير الدورات المغلقة وخطط السداد المعتمدة على أرقامها المحفوظة.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk) }
            if p.lines.isEmpty { Text("لا توجد حركات مؤهلة لإعادة التحويل.").font(MadarTypography.body()) }
            Button {
                saving = true
                Task { do { try await app.executeMoneyCommand("money.repriceTrip", payload: ["id": .string(reading.id.uuidString), "rate": .string(reading.rate!), "signature": .string(p.signature)]); previewOpen = false; dismiss() } catch { failure = "تغيّرت الحركات منذ المعاينة؛ أعد فتحها قبل التطبيق."; previewOpen = false; saving = false } }
            } label: { Text(saving ? "جارٍ التطبيق…" : "طبّق على الحركات المعروضة").frame(maxWidth: .infinity, minHeight: 50).background(theme.ink).foregroundStyle(theme.background) }.disabled(saving || p.lines.isEmpty).accessibilityIdentifier("money-trip-reprice-apply")
        }.padding(22) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain).madarSheetLock(saving: saving)
    }
    private func scale(_ code: String) -> Int { (0..<(CurrencyExponents.specified.exponent(code) ?? 2)).reduce(1) { n, _ in n * 10 } }
    private func save() {
        guard let rate else { return }; saving = true; focused = false
        let p: [String: MadarCore.JSONValue] = ["id": .string(reading.id.uuidString), "currency": .string(currency), "rate": currency == app.string("core.currency") ? .null : .string(rate), "expectedRate": reading.rate.map(MadarCore.JSONValue.string) ?? .null, "expectedCurrency": reading.currency.map(MadarCore.JSONValue.string) ?? .null]
        Task { do { try await app.executeMoneyCommand("money.configureTrip", payload: p); dismiss() } catch { failure = "لم يُحفظ السعر. أعد فتح الورقة وحاول مرة أخرى."; saving = false } }
    }
}

struct MoneyTripFundingSheet: View {
    let app: AppSession
    let reading: MoneyTravelReading
    let visible: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @State private var raw = ""
    @State private var source = "surplus"
    @State private var due = Date()
    @State private var saving = false
    @State private var failure: String?
    @FocusState private var focused: Bool
    private var service: AppMoneyService { .init(app: app) }
    private var minor: Int? { MoneyAmountInput.minor(raw, exponent: CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2) }
    private var available: Int { source == "surplus" ? reading.surplusMinor : reading.reserveMinor }
    private var sourceTitle: String { source == "surplus" ? "الفائض" : "الاحتياطي" }
    private var fundingHint: String? {
        guard visible else { return nil }
        if available <= 0 { return "لا يوجد مبلغ متاح في " + sourceTitle + " الآن. اختر مصدرًا آخر." }
        guard !raw.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
        guard let minor, minor > 0 else { return "اكتب مبلغًا صحيحًا أكبر من صفر." }
        return minor > available ? "المبلغ أكبر من المتاح في " + sourceTitle + ". خفّضه أو اختر مصدرًا آخر." : nil
    }
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment: .leading, spacing: 16) {
            HStack { Text("مظروف رحلة " + reading.city).font(MadarTypography.cardTitle()); Spacer(); Button("إغلاق") { dismiss() }.madarWaitsForSave().frame(minHeight: 44).accessibilityIdentifier("money-trip-fund-close") }
            Text("انقل من مالك المخصّص إلى الرحلة. المجموع لا يتغيّر.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            Text("المبلغ بعملة البيت، " + service.currencyName(app.string("core.currency"))).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            TextField("المبلغ", text: $raw).keyboardType(.decimalPad).focused($focused).font(.title2).padding(12).background(theme.surface).accessibilityIdentifier("money-trip-fund-input")
            Picker("من أين؟", selection: $source) { Text("الفائض").tag("surplus"); Text("الاحتياطي").tag("reserve") }.pickerStyle(.segmented).accessibilityIdentifier("money-trip-fund-source")
            Text(figure: "في " + sourceTitle + " " + (visible ? service.amount(available) : "•••") + " " + service.currencyName(app.string("core.currency")))
                .font(MadarTypography.caption()).accessibilityIdentifier("money-trip-fund-available")
            if let fundingHint {
                Text(fundingHint).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    .fixedSize(horizontal: false, vertical: true).accessibilityIdentifier("money-trip-fund-hint")
            }
            DatePicker("آخر يوم في خطة الرحلة", selection: $due, in: app.prayerNow()..., displayedComponents: .date).accessibilityIdentifier("money-trip-fund-date")
            MadarDateLabel(app.dateLabels(.containing(due, in: app.activePlace.timeZone)), primaryFont: MadarTypography.caption(), secondaryFont: MadarTypography.fine())
            if let amount = minor, amount > 0, amount <= available, let daily = TravelBudget.dailyMinor(targetMinor: (reading.targetMinor ?? 0) + amount, durationDays: MadarCalendarDays.distance(from: reading.start, to: .containing(due, in: app.activePlace.timeZone)) + 1, day: MadarCalendarDays.distance(from: reading.start, to: reading.today) + 1) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("خطة اليوم بعد النقل").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
                    Text(figure: (visible ? service.amount(daily) : "•••") + " " + service.currencyName(app.string("core.currency"))).font(MadarTypography.cardTitle())
                }
                Text("هذا موعد للخطة فقط؛ عودتك الفعلية تُنهي حالة السفر لكل الغرف.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            }
            if let failure { Text(failure).font(MadarTypography.caption()) }
            // AU-34: hidden numbers say why save waits.
            if !visible { Text("أرقامك مخفية؛ أظهرها من صفحة الرحلة لتحفظ").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk).accessibilityIdentifier("money-trip-hidden-hint") }
            Button { save() } label: { Text(saving ? "جارٍ النقل…" : "انقل للمظروف").frame(maxWidth: .infinity, minHeight: 50).background(theme.ink).foregroundStyle(theme.background) }.disabled(saving || !visible || minor.map { $0 > 0 && $0 <= available } != true).accessibilityIdentifier("money-trip-fund-save")
        }.padding(22) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.madarPlain).scrollDismissesKeyboard(.interactively)
            .toolbar { ToolbarItemGroup(placement: .keyboard) { Spacer(); Button("تمّ") { focused = false }.accessibilityIdentifier("money-trip-keyboard-done") } }
            .task { due = max(app.prayerNow(), reading.due?.date(in: app.activePlace.timeZone) ?? reading.today.adding(days: 3).date(in: app.activePlace.timeZone)); if reading.surplusMinor <= 0 { source = "reserve" } }
            .madarSheetLock(saving: saving)
        }
    }
    private func save() {
        guard let minor else { return }; saving = true; focused = false
        Task { do { try await app.executeMoneyCommand("money.fundTrip", payload: ["id": .string(reading.id.uuidString), "amountMinor": .string(String(minor)), "source": .string(source), "due": .string(ISO8601DateFormatter().string(from: due)), "expectedBalanceMinor": .string(String(reading.balanceMinor))]); dismiss() } catch { failure = "لم يُنقل المبلغ. قد يكون الرصيد تغيّر؛ أعد فتح الورقة."; saving = false } }
    }
}
