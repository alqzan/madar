import Foundation

/// Owner, 30 Oct 2026 (AU-10 idea): «مدينة أخرى» asked for latitude, longitude, an English time-zone ID, a country and a
/// currency by hand. A searchable list of the cities Madar's readers most often live in or travel to fills all five.
/// The list is plain data, shipped in the app, and works offline.
struct CatalogCity: Identifiable, Equatable {
    let name: String
    let lat: Double, lon: Double
    let tz: String, country: String, currency: String
    var id: String { name + country }
}

enum CityCatalog {
    static let all: [CatalogCity] = [
        .init(name: "الرياض", lat: 24.7136, lon: 46.6753, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "جدة", lat: 21.5433, lon: 39.1728, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "مكة المكرمة", lat: 21.4225, lon: 39.8262, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "المدينة المنورة", lat: 24.4672, lon: 39.6024, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "الدمام", lat: 26.4207, lon: 50.0888, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "الخبر", lat: 26.2794, lon: 50.2083, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "الطائف", lat: 21.2703, lon: 40.4158, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "تبوك", lat: 28.3838, lon: 36.5550, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "أبها", lat: 18.2164, lon: 42.5053, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "بريدة", lat: 26.3260, lon: 43.9750, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "حائل", lat: 27.5114, lon: 41.7208, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "جازان", lat: 16.8892, lon: 42.5511, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "نجران", lat: 17.4933, lon: 44.1277, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "ينبع", lat: 24.0895, lon: 38.0618, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "الأحساء", lat: 25.3648, lon: 49.5875, tz: "Asia/Riyadh", country: "SA", currency: "SAR"),
        .init(name: "دبي", lat: 25.2048, lon: 55.2708, tz: "Asia/Dubai", country: "AE", currency: "AED"),
        .init(name: "أبوظبي", lat: 24.4539, lon: 54.3773, tz: "Asia/Dubai", country: "AE", currency: "AED"),
        .init(name: "الشارقة", lat: 25.3463, lon: 55.4209, tz: "Asia/Dubai", country: "AE", currency: "AED"),
        .init(name: "الدوحة", lat: 25.2854, lon: 51.5310, tz: "Asia/Qatar", country: "QA", currency: "QAR"),
        .init(name: "المنامة", lat: 26.2285, lon: 50.5860, tz: "Asia/Bahrain", country: "BH", currency: "BHD"),
        .init(name: "الكويت", lat: 29.3759, lon: 47.9774, tz: "Asia/Kuwait", country: "KW", currency: "KWD"),
        .init(name: "مسقط", lat: 23.5880, lon: 58.3829, tz: "Asia/Muscat", country: "OM", currency: "OMR"),
        .init(name: "صنعاء", lat: 15.3694, lon: 44.1910, tz: "Asia/Aden", country: "YE", currency: "YER"),
        .init(name: "عمّان", lat: 31.9454, lon: 35.9284, tz: "Asia/Amman", country: "JO", currency: "JOD"),
        .init(name: "القدس", lat: 31.7683, lon: 35.2137, tz: "Asia/Jerusalem", country: "PS", currency: "ILS"),
        .init(name: "بيروت", lat: 33.8938, lon: 35.5018, tz: "Asia/Beirut", country: "LB", currency: "LBP"),
        .init(name: "دمشق", lat: 33.5138, lon: 36.2765, tz: "Asia/Damascus", country: "SY", currency: "SYP"),
        .init(name: "بغداد", lat: 33.3152, lon: 44.3661, tz: "Asia/Baghdad", country: "IQ", currency: "IQD"),
        .init(name: "القاهرة", lat: 30.0444, lon: 31.2357, tz: "Africa/Cairo", country: "EG", currency: "EGP"),
        .init(name: "الإسكندرية", lat: 31.2001, lon: 29.9187, tz: "Africa/Cairo", country: "EG", currency: "EGP"),
        .init(name: "الخرطوم", lat: 15.5007, lon: 32.5599, tz: "Africa/Khartoum", country: "SD", currency: "SDG"),
        .init(name: "طرابلس", lat: 32.8872, lon: 13.1913, tz: "Africa/Tripoli", country: "LY", currency: "LYD"),
        .init(name: "تونس", lat: 36.8065, lon: 10.1815, tz: "Africa/Tunis", country: "TN", currency: "TND"),
        .init(name: "الجزائر", lat: 36.7538, lon: 3.0588, tz: "Africa/Algiers", country: "DZ", currency: "DZD"),
        .init(name: "الرباط", lat: 34.0209, lon: -6.8416, tz: "Africa/Casablanca", country: "MA", currency: "MAD"),
        .init(name: "الدار البيضاء", lat: 33.5731, lon: -7.5898, tz: "Africa/Casablanca", country: "MA", currency: "MAD"),
        .init(name: "إسطنبول", lat: 41.0082, lon: 28.9784, tz: "Europe/Istanbul", country: "TR", currency: "TRY"),
        .init(name: "أنقرة", lat: 39.9334, lon: 32.8597, tz: "Europe/Istanbul", country: "TR", currency: "TRY"),
        .init(name: "لندن", lat: 51.5072, lon: -0.1276, tz: "Europe/London", country: "GB", currency: "GBP"),
        .init(name: "باريس", lat: 48.8566, lon: 2.3522, tz: "Europe/Paris", country: "FR", currency: "EUR"),
        .init(name: "برلين", lat: 52.5200, lon: 13.4050, tz: "Europe/Berlin", country: "DE", currency: "EUR"),
        .init(name: "مدريد", lat: 40.4168, lon: -3.7038, tz: "Europe/Madrid", country: "ES", currency: "EUR"),
        .init(name: "روما", lat: 41.9028, lon: 12.4964, tz: "Europe/Rome", country: "IT", currency: "EUR"),
        .init(name: "موسكو", lat: 55.7558, lon: 37.6173, tz: "Europe/Moscow", country: "RU", currency: "RUB"),
        .init(name: "نيويورك", lat: 40.7128, lon: -74.0060, tz: "America/New_York", country: "US", currency: "USD"),
        .init(name: "لوس أنجلوس", lat: 34.0522, lon: -118.2437, tz: "America/Los_Angeles", country: "US", currency: "USD"),
        .init(name: "تورنتو", lat: 43.6532, lon: -79.3832, tz: "America/Toronto", country: "CA", currency: "CAD"),
        .init(name: "إسلام آباد", lat: 33.6844, lon: 73.0479, tz: "Asia/Karachi", country: "PK", currency: "PKR"),
        .init(name: "كراتشي", lat: 24.8607, lon: 67.0011, tz: "Asia/Karachi", country: "PK", currency: "PKR"),
        .init(name: "لاهور", lat: 31.5204, lon: 74.3587, tz: "Asia/Karachi", country: "PK", currency: "PKR"),
        .init(name: "نيودلهي", lat: 28.6139, lon: 77.2090, tz: "Asia/Kolkata", country: "IN", currency: "INR"),
        .init(name: "دكا", lat: 23.8103, lon: 90.4125, tz: "Asia/Dhaka", country: "BD", currency: "BDT"),
        .init(name: "كوالالمبور", lat: 3.1390, lon: 101.6869, tz: "Asia/Kuala_Lumpur", country: "MY", currency: "MYR"),
        .init(name: "جاكرتا", lat: -6.2088, lon: 106.8456, tz: "Asia/Jakarta", country: "ID", currency: "IDR"),
        .init(name: "سنغافورة", lat: 1.3521, lon: 103.8198, tz: "Asia/Singapore", country: "SG", currency: "SGD"),
        .init(name: "طوكيو", lat: 35.6762, lon: 139.6503, tz: "Asia/Tokyo", country: "JP", currency: "JPY"),
        .init(name: "سيدني", lat: -33.8688, lon: 151.2093, tz: "Australia/Sydney", country: "AU", currency: "AUD"),
    ]

    /// Letters that Arabic spellings vary on are folded together, and marks and tatweel are dropped, so «ابها» finds «أبها»
    /// and «القاهره» finds «القاهرة».
    static func fold(_ text: String) -> String {
        let map: [Character: Character] = ["أ": "ا", "إ": "ا", "آ": "ا", "ى": "ي", "ة": "ه", "ؤ": "و", "ئ": "ي"]
        let marks = Set<Unicode.Scalar>("ًٌٍَُِّْٰـ".unicodeScalars)
        var kept = String.UnicodeScalarView()
        kept.append(contentsOf: text.lowercased().unicodeScalars.filter { !marks.contains($0) })
        return String(String(kept).map { map[$0] ?? $0 }).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Cities whose name contains the typed words; an empty query lists nothing (the three presets stay on top).
    static func search(_ query: String) -> [CatalogCity] {
        let needle = fold(query)
        guard !needle.isEmpty else { return [] }
        let hits = all.filter { fold($0.name).contains(needle) }
        // Names that begin with the typed letters come first.
        return hits.sorted { (fold($0.name).hasPrefix(needle) ? 0 : 1) < (fold($1.name).hasPrefix(needle) ? 0 : 1) }
    }
}
