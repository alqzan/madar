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
    var body: some View {
        Form {
            Section("المدن") {
                Button("الرياض") { use(.riyadh) }
                Button("مكة المكرمة") { use(.makkah) }
                Button("المدينة المنورة") { use(.madinah) }
            }
            Section("مدينة أخرى") {
                TextField("اسم المدينة", text: $name).accessibilityIdentifier("city-name")
                TextField("خط العرض", text: $latitude).environment(\.layoutDirection, .leftToRight)
                TextField("خط الطول", text: $longitude).environment(\.layoutDirection, .leftToRight)
                TextField("المنطقة الزمنية", text: $timeZone).textInputAutocapitalization(.never).autocorrectionDisabled().environment(\.layoutDirection, .leftToRight)
                TextField("رمز البلد", text: $country).textInputAutocapitalization(.characters).environment(\.layoutDirection, .leftToRight)
                TextField("العملة", text: $currency).textInputAutocapitalization(.characters).environment(\.layoutDirection, .leftToRight)
            }
            if let validationError { Section { Text(validationError) } }
            Section { Button("احفظ المدينة") { save() }.accessibilityIdentifier("city-save") }
        }.navigationTitle("مدينتك")
            .onAppear { load() }
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
    private func use(_ city: KnownCity) {
        name = city.name; latitude = String(city.lat); longitude = String(city.lon)
        timeZone = "Asia/Riyadh"; country = "SA"; currency = "SAR"; save()
    }
    private func save() {
        guard let lat = Double(latitude), let lon = Double(longitude), lat.isFinite, lon.isFinite, (-90...90).contains(lat), (-180...180).contains(lon), TimeZone(identifier: timeZone) != nil,
              !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, name.count <= 80,
              Locale.Region.isoRegions.map(\.identifier).contains(country.uppercased()), Locale.Currency.isoCurrencies.map(\.identifier).contains(currency.uppercased()) else {
            validationError = "تحقّق من الاسم والإحداثيات ورموز البلد والعملة والمنطقة الزمنية."; return
        }
        session.set(.object(["name": .string(name), "country": .string(country.uppercased()), "lat": .number(lat), "lon": .number(lon), "tz": .string(timeZone), "currency": .string(currency.uppercased())]), key: "core.homeCity") { dismiss() }
    }
}

private struct KnownCity {
    let name: String; let lat: Double; let lon: Double
    static let riyadh = Self(name: "الرياض", lat: 24.7136, lon: 46.6753)
    static let makkah = Self(name: "مكة المكرمة", lat: 21.4225, lon: 39.8262)
    static let madinah = Self(name: "المدينة المنورة", lat: 24.4672, lon: 39.6024)
}
