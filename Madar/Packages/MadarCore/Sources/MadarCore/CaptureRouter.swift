import Foundation

/// §9 single capture: one free sentence goes to the room that owns it. Routing follows the built rooms only.
public enum CaptureRoute: Equatable, Sendable {
    public enum LineKind: String, Sendable { case line, idea }
    /// A complete prayer report: prayer and congregation state were both said.
    case logPrayer(prayer: Prayer, status: String, shortened: Bool?, fridayKind: FridayPrayerKind?)
    /// A prayer was named without its state. Madar never guesses the state; the log sheet opens prefilled.
    case choosePrayerStatus(prayer: Prayer, fridayKind: FridayPrayerKind?)
    /// Anything else is a line on today's diary page, kept exactly as written.
    case diaryLine(text: String, kind: LineKind)
    /// An explicit «فكرة:» goes to Mihbara's private notebook after the foreground app gate.
    case mihbaraIdea(text: String)
    /// Amount is a decimal major-unit string; the app applies its chosen home currency.
    case moneyExpense(amount: String, merchant: String)
    case empty
    case tooLong
}

public enum CaptureRouter {
    public static let maximumLength = 2000

    public static func route(_ raw: String) -> CaptureRoute {
        let text = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return .empty }
        guard text.count <= maximumLength else { return .tooLong }
        if let prayer = prayerReport(text) { return prayer }
        if let expense = moneyReport(text) { return expense }
        if let colon = text.firstIndex(of: ":"), fold(String(text[..<colon])).trimmingCharacters(in: .whitespacesAndNewlines) == "فكره" {
            let idea = String(text[text.index(after: colon)...]).trimmingCharacters(in: .whitespacesAndNewlines)
            return idea.isEmpty ? .empty : .mihbaraIdea(text: idea)
        }
        return .diaryLine(text: text, kind: .line)
    }

    private static func moneyReport(_ text: String) -> CaptureRoute? {
        guard let regex = try? NSRegularExpression(pattern: #"^(.{1,80}?)\s+([0-9٠-٩۰-۹]+(?:[٫.][0-9٠-٩۰-۹]+)?)$"#),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let merchantRange = Range(match.range(at: 1), in: text), let amountRange = Range(match.range(at: 2), in: text) else { return nil }
        var merchant = String(text[merchantRange]), folded = fold(merchant)
        let explicit = folded.hasPrefix("مصروف:") || folded.hasPrefix("مصروف ")
        if explicit { merchant = String(merchant.dropFirst(6)).trimmingCharacters(in: .whitespacesAndNewlines); folded = fold(merchant) }
        let names = ["قهوه", "بقاله", "بنزين", "مطعم", "مواقف", "مواصلات", "فطور", "غداء", "عشاء", "صيدليه", "مشتريات"]
        guard !merchant.isEmpty, explicit || names.contains(where: { folded == $0 || folded.hasPrefix($0 + " ") }) else { return nil }
        return .moneyExpense(amount: String(text[amountRange]), merchant: merchant)
    }

    /// Strict on purpose: a sentence with words beyond the prayer report («مع أبي») keeps its
    /// meaning as a diary line instead of being reduced to a prayer status.
    private static func prayerReport(_ text: String) -> CaptureRoute? {
        let words = fold(text).split(whereSeparator: { $0.isWhitespace || "،,.!؟?".contains($0) }).map(String.init)
        guard words.count >= 2, ["صليت", "صلينا"].contains(words[0]) else { return nil }
        let names: [String: (Prayer, FridayPrayerKind?)] = [
            "الفجر": (.fajr, nil), "الصبح": (.fajr, nil), "الظهر": (.dhuhr, nil), "الجمعه": (.dhuhr, .jumuah),
            "العصر": (.asr, nil), "المغرب": (.maghrib, nil), "العشاء": (.isha, nil), "العشا": (.isha, nil)
        ]
        guard let (prayer, named) = names[words[1]] else { return nil }
        let congregation: Set<String> = ["جماعه", "بجماعه", "بالمسجد", "المسجد", "بالجامع", "الجامع", "بالحرم", "الحرم"]
        let alone: Set<String> = ["وحدي", "لوحدي", "بمفردي", "منفرد", "منفردا", "فرادي", "فرادى"]
        let shortening: Set<String> = ["قصر", "قصرا", "مقصوره"]
        let filler: Set<String> = ["في", "فى", "و", "الحمد", "لله", "الحمدلله", "اليوم"]
        var status: String?, shortened: Bool?
        for word in words.dropFirst(2) {
            if congregation.contains(word) { guard status != "alone" else { return nil }; status = "jamaah" }
            else if alone.contains(word) { guard status != "jamaah" else { return nil }; status = "alone" }
            else if shortening.contains(word) { shortened = true }
            else if !filler.contains(word) { return nil }
        }
        if shortened == true, prayer == .fajr || prayer == .maghrib || named == .jumuah { return nil }
        if named == .jumuah {
            // Jumu'ah is congregational by definition; saying «وحدي» contradicts it.
            guard status != "alone" else { return nil }
            return .logPrayer(prayer: .dhuhr, status: "jamaah", shortened: nil, fridayKind: .jumuah)
        }
        guard let status else { return .choosePrayerStatus(prayer: prayer, fridayKind: nil) }
        return .logPrayer(prayer: prayer, status: status, shortened: shortened, fridayKind: nil)
    }

    /// Spoken and typed Arabic vary in marks and hamza forms; compare on a folded copy only.
    public static func fold(_ text: String) -> String {
        var scalars = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x064B...0x065F, 0x0670, 0x0640: continue
            case 0x0623, 0x0625, 0x0622, 0x0671: scalars.append("ا")
            case 0x0629: scalars.append("ه")
            case 0x0649: scalars.append("ي")
            default: scalars.append(scalar)
            }
        }
        return String(scalars)
    }
}
