import SwiftUI
import MadarData
import MadarDesign

struct CityEditor: View {
    @Bindable var session: AppSession
    @Environment(\.dismiss) private var dismiss
    @State private var name = ""
    @State private var latitude = ""
    @State private var longitude = ""
    @State private var timeZone = ""
    @State private var country = ""
    @State private var currency = ""
    @State private var validationError: String?
    @State private var query = ""
    @StateObject private var locator = CityLocator()
    var body: some View {
        Form {
            Section {
                Button("الرياض") { use(.riyadh) }
                Button("مكة المكرمة") { use(.makkah) }
                Button("المدينة المنورة") { use(.madinah) }
            } header: { Text("المدن") } footer: { Text("اختيار إحداها يحفظها مباشرة، ويضبط البلد والعملة والمنطقة الزمنية على السعودية.") }
            Section {
                TextField("ابحث عن مدينة", text: $query).accessibilityIdentifier("city-search")
                ForEach(CityCatalog.search(query)) { city in
                    Button(city.name) { use(city) }.accessibilityIdentifier("city-hit-" + city.name)
                }
                if !query.isEmpty && CityCatalog.search(query).isEmpty { Text("لا مدينة بهذا الاسم في القائمة؛ اكتب بياناتها في الأسفل.").font(.footnote).foregroundStyle(.secondary) }
                Button { locator.start(fill) } label: { Label(locator.working ? "أبحث عن موقعك…" : "استخدم موقعي", systemImage: "location") }
                    .disabled(locator.working).accessibilityIdentifier("city-locate")
                if let message = locator.message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            } header: { Text("ابحث أو استخدم موقعك") } footer: { Text("المدينة التي تختارها من القائمة تُحفظ مباشرة. وموقعك يُقرأ مرة واحدة عند الضغط، ويعرف النظام اسم مدينتك بإرساله إلى Apple، ولا يحفظ مدار إلا ما تؤكده بـ«احفظ المدينة».") }
            Section("مدينة أخرى") {
                TextField("اسم المدينة", text: $name).accessibilityIdentifier("city-name")
                TextField("خط العرض", text: $latitude).keyboardType(.numbersAndPunctuation).environment(\.layoutDirection, .leftToRight)
                TextField("خط الطول", text: $longitude).keyboardType(.numbersAndPunctuation).environment(\.layoutDirection, .leftToRight)
                TextField("المنطقة الزمنية", text: $timeZone).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection, .leftToRight)
                TextField("رمز البلد", text: $country).textInputAutocapitalization(.characters).environment(\.layoutDirection, .leftToRight)
                TextField("العملة", text: $currency).textInputAutocapitalization(.characters).environment(\.layoutDirection, .leftToRight)
            }
            if let validationError { Section { Text(validationError) } }
            Section { Button("احفظ المدينة") { save() }.accessibilityIdentifier("city-save") }
        }.navigationTitle("مدينتك")
            .onAppear { load() }
            // AU-43: an old complaint goes as soon as the user edits.
            .onChange(of: [name, latitude, longitude, timeZone, country, currency]) { validationError = nil }
    }
    private func load() {
        let city = session.homeCity
        name = session.cityName
        if case .number(let v) = city["lat"] { latitude = String(v) }
        if case .number(let v) = city["lon"] { longitude = String(v) }
        if case .string(let v) = city["tz"] { timeZone = v }
        if case .string(let v) = city["country"] { country = v }
        if case .string(let v) = city["currency"] { currency = v }
    }
    static func number(_ raw: String) -> Double? {
        let map: [Character: Character] = ["٠":"0","١":"1","٢":"2","٣":"3","٤":"4","٥":"5","٦":"6","٧":"7","٨":"8","٩":"9","٫":".","−":"-"]
        return Double(String(raw.trimmingCharacters(in: .whitespaces).map { map[$0] ?? $0 }))
    }
    private func use(_ city: CatalogCity) {
        name = city.name; latitude = String(city.lat); longitude = String(city.lon)
        timeZone = city.tz; country = city.country; currency = city.currency; save()
    }
    /// A located city fills the form for the reader to read and confirm.
    private func fill(_ found: CityLocator.Found) {
        name = found.name; latitude = String(found.lat); longitude = String(found.lon)
        timeZone = found.tz; country = found.country; currency = found.currency
    }
    private func use(_ city: KnownCity) {
        name = city.name; latitude = String(city.lat); longitude = String(city.lon)
        timeZone = "Asia/Riyadh"; country = "SA"; currency = "SAR"; save()
    }
    private func save() {
        // AU-43: one specific sentence for the first wrong field; Arabic digits are accepted.
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty || name.count > 80 { validationError = "اكتب اسم المدينة، ٨٠ حرفًا على الأكثر."; return }
        guard let lat = Self.number(latitude), lat.isFinite, (-90...90).contains(lat) else { validationError = "خط العرض رقم بين −٩٠ و٩٠، مثل ٢٤٫٧١"; return }
        guard let lon = Self.number(longitude), lon.isFinite, (-180...180).contains(lon) else { validationError = "خط الطول رقم بين −١٨٠ و١٨٠، مثل ٤٦٫٦٧"; return }
        guard TimeZone(identifier: timeZone) != nil else { validationError = "المنطقة الزمنية بالإنجليزية، مثل Asia/Riyadh"; return }
        guard Locale.Region.isoRegions.map(\.identifier).contains(country.uppercased()) else { validationError = "رمز البلد حرفان، مثل SA"; return }
        guard Locale.Currency.isoCurrencies.map(\.identifier).contains(currency.uppercased()) else { validationError = "رمز العملة ثلاثة أحرف، مثل SAR"; return }
        session.set(.object(["name": .string(trimmed), "country": .string(country.uppercased()), "lat": .number(lat), "lon": .number(lon), "tz": .string(timeZone), "currency": .string(currency.uppercased())]), key: "core.homeCity") { dismiss() }
    }
}

private struct KnownCity {
    let name: String; let lat: Double; let lon: Double
    static let riyadh = Self(name: "الرياض", lat: 24.7136, lon: 46.6753)
    static let makkah = Self(name: "مكة المكرمة", lat: 21.4225, lon: 39.8262)
    static let madinah = Self(name: "المدينة المنورة", lat: 24.4672, lon: 39.6024)
}
