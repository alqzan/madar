import SwiftUI
import MadarCore
import MadarDesign
import MadarMoney
import MadarCommands

struct MoneyZakatEditor: View {
    let app: AppSession
    let reading: MoneyZakatReading
    let basis: NisabBasis
    let chosen: Bool
    let debt: ZakatDebtsPolicy
    let visible: Bool
    @Environment(\.dismiss) private var dismiss
    @Environment(\.roomTheme) private var theme
    @FocusState private var focused: Bool
    @State private var gold = ""
    @State private var silver = ""
    @State private var goldWeight = ""
    @State private var silverWeight = ""
    @State private var other = ""
    @State private var hasHawl = false
    @State private var date = Date()
    @State private var saving = false
    @State private var failure: String?
    @State private var selectedBasis = NisabBasis.gold
    @State private var selectedDebt = ZakatDebtsPolicy.unset
    @State private var basisChosen = false
    private var service: AppMoneyService { .init(app: app) }
    private var exponent: Int { CurrencyExponents.specified.exponent(app.string("core.currency")) ?? 2 }
    private func money(_ raw: String) -> Int? { raw.isEmpty ? nil : MoneyAmountInput.minor(raw, exponent: exponent) }
    private var valid: Bool {
        basisChosen && (gold.isEmpty || money(gold).map { $0 > 0 } == true) && (silver.isEmpty || money(silver).map { $0 > 0 } == true)
            && MoneyAmountInput.minor(goldWeight, exponent:3).map { $0 > 0 } == true && MoneyAmountInput.minor(silverWeight, exponent:3).map { $0 > 0 } == true && money(other) != nil
    }
    var body: some View {
        NavigationStack { ScrollView { VStack(alignment:.leading,spacing:16) {
            HStack { Text("بيانات الزكاة").font(MadarTypography.cardTitle());Spacer();Button("إغلاق"){dismiss()}.frame(minHeight:44) }
            Text("أساس النصاب").font(MadarTypography.section())
            HStack { Button("ذهب ٢٤ قيراطًا") { selectedBasis = .gold; basisChosen = true }.accessibilityIdentifier("money-zakat-editor-gold");Spacer();Button("فضة") { selectedBasis = .silver; basisChosen = true }.accessibilityIdentifier("money-zakat-editor-silver") }.font(MadarTypography.body())
            if basisChosen { Text(selectedBasis == .gold ? "اخترت الذهب عيار ٢٤" : "اخترت الفضة").font(MadarTypography.caption()).foregroundStyle(theme.color("reserveText")) }
            if selectedBasis == .gold { field("سعر غرام الذهب عيار ٢٤، بعملة البيت", $gold, "gold-price"); field("وزن النصاب بالغرام", $goldWeight, "gold-weight") }
            else { field("سعر غرام الفضة، بعملة البيت", $silver, "silver-price"); field("وزن النصاب بالغرام", $silverWeight, "silver-weight") }
            Button("أعد وزني النصاب إلى المتفق عليهما") { goldWeight=service.moneyInput(85000,exponent:3);silverWeight=service.moneyInput(595000,exponent:3) }.font(MadarTypography.caption()).frame(minHeight:44)
            Text("المظاريف داخل الحسابات أصلًا").font(MadarTypography.section())
            field("أموال أخرى تُزكّى، بعملة البيت", $other, "other")
            Text("ذهب أو أسهم أو ديون مرجوّة لك؛ أدخل مجموعها مرة واحدة.").font(MadarTypography.fine()).foregroundStyle(theme.secondaryInk)
            Picker("الديون",selection:$selectedDebt) { Text("لم أختر").tag(ZakatDebtsPolicy.unset);Text("لا أخصم ديونًا").tag(ZakatDebtsPolicy.none);Text("المستحق الآن").tag(ZakatDebtsPolicy.dueNow);Text("عليك دون القرض").tag(ZakatDebtsPolicy.allOwed);Text("عليك وباقي القرض").tag(ZakatDebtsPolicy.allOwedAndLoan) }.accessibilityIdentifier("money-zakat-editor-debts")
            Toggle("اخترت تاريخًا للحساب السنوي",isOn:$hasHawl).font(MadarTypography.body()).accessibilityIdentifier("money-zakat-editor-hawl")
            if hasHawl {
                DatePicker("تاريخك المختار",selection:$date,displayedComponents:.date).environment(\.calendar,Calendar(identifier:.islamicUmmAlQura)).accessibilityIdentifier("money-zakat-hawl-date")
                MadarDateLabel(app.dateLabels(.containing(date,in:app.activePlace.timeZone)),primaryFont:MadarTypography.caption(),secondaryFont:MadarTypography.fine())
            }
            Text("مدار لا يستنتج اكتمال الحول من الرصيد؛ هذا تاريخ تختاره للمحاسبة السنوية.").font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk)
            if let failure {Text(failure).font(MadarTypography.caption())}
            Button(action:save) {Text(saving ? "جارٍ الحفظ…" : "احفظ بيانات الحساب").font(MadarTypography.body()).frame(maxWidth:.infinity,minHeight:50).background(theme.ink).foregroundStyle(theme.background)}.disabled(saving || !valid || !visible).accessibilityIdentifier("money-zakat-save")
        }.padding(22) }.background(theme.background.ignoresSafeArea()).foregroundStyle(theme.ink).buttonStyle(.plain).scrollDismissesKeyboard(.interactively)
            .toolbar {ToolbarItemGroup(placement:.keyboard){Spacer();Button("تم"){focused=false}.accessibilityIdentifier("money-zakat-keyboard-done")}}
            .task {let i=reading.input;selectedBasis=basis;basisChosen=chosen;selectedDebt=debt;gold=i.goldPricePerGramMinor.map{service.moneyInput($0)} ?? "";silver=i.silverPricePerGramMinor.map{service.moneyInput($0)} ?? "";goldWeight=service.moneyInput(i.nisabMg,exponent:3);silverWeight=service.moneyInput(i.nisabSilverMg,exponent:3);other=service.moneyInput(i.otherAssetsMinor);hasHawl = !(i.hawlStartHijri ?? "").isEmpty;date=MoneyHawl.read(i.hawlStartHijri ?? "",app:app)?.chosen.date(in:app.activePlace.timeZone) ?? app.prayerNow()}
        }
    }
    private func field(_ title:String,_ binding:Binding<String>,_ id:String)->some View {VStack(alignment:.leading,spacing:5){Text(title).font(MadarTypography.caption()).foregroundStyle(theme.secondaryInk);TextField("اختياري",text:binding).font(MadarTypography.body()).keyboardType(.decimalPad).focused($focused).padding(10).background(theme.surface).accessibilityIdentifier("money-zakat-"+id)}}
    private func save(){
        guard valid else{return};focused=false;saving=true
        let h=HijriCalendar.date(for:date,timeZone:app.activePlace.timeZone,source:HijriSource(rawValue:app.string("core.hijriSource")) ?? .ummAlQura,sightingOffset:Int(app.number("core.hijriOffset")))
        let key=hasHawl ? String(format:"h:%04d-%02d-%02d",h.year,h.month,h.day) : ""
        let p:[String:MadarCore.JSONValue] = ["signature":.string(reading.signature),"basis":.string(selectedBasis.rawValue),"debts":.string(selectedDebt.rawValue),"goldPriceMinor":money(gold).map{.string(String($0))} ?? .null,"silverPriceMinor":money(silver).map{.string(String($0))} ?? .null,"goldMg":.string(String(MoneyAmountInput.minor(goldWeight,exponent:3) ?? 85000)),"silverMg":.string(String(MoneyAmountInput.minor(silverWeight,exponent:3) ?? 595000)),"otherMinor":.string(String(money(other) ?? 0)),"hawl":.string(key)]
        Task{do{try await app.executeMoneyCommand("money.saveZakat",payload:p);dismiss()}catch{failure="لم تُحفظ البيانات. افتح الورقة من جديد وحاول مرة أخرى.";saving=false}}
    }
}
