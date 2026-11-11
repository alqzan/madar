import Foundation

/// Owner, 11 Nov 2026 (phase 3): one key for one merchant however a bank prints it. «Starbucks», «ستاربكس», «SQ *STARBUCKS #204 RIYADH SA»
/// and «Starbucks 1234» are the same place. The key is only for comparing and grouping (recurring charges, refunds, learned
/// categories, merchant rules); it is never shown and never replaces the name the bank printed.
///
/// `BankDedupe.normalize` is deliberately left alone: message fingerprints and due natural keys are derived from it and stored.
public enum MerchantKey {
    /// The comparison key; empty when the text names nothing.
    public static func key(_ text: String?) -> String {
        guard let text else { return "" }
        var t = fold(BankMessageParser.clean(text).lowercased())
        t = t.replacingOccurrences(of: "\n", with: " ")
        // «PAYPAL *NETFLIX», «SQ *CAFE», «TAMARA - NOON»: the payment gateway or instalment provider is not the merchant.
        t = t.replacingOccurrences(of: #"^\s*(?:paypal|pp|sq|sp|tst|stripe|hyperpay|moyasar|paytabs|geidea|tap|payfort|checkout|2c2p|ipay|google|amzn)\s*\*\s*"#,
                                   with: "", options: .regularExpression)
        t = t.replacingOccurrences(of: #"^\s*(?:tamara|tabby|تمارا|تابي)\s*[\*\-–]\s*"#, with: "", options: .regularExpression)
        // Branch and store numbers, then web suffixes.
        t = t.replacingOccurrences(of: #"#\s*\d+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\b(?:branch|br|store|no|number|فرع|رقم)\.?\s*\d+"#, with: " ", options: .regularExpression)
        t = t.replacingOccurrences(of: #"\.(?:com|sa|net|org|co)\b(?:/\w+)?"#, with: " ", options: .regularExpression)
        var tokens = t.unicodeScalars.map { CharacterSet.letters.contains($0) || CharacterSet.decimalDigits.contains($0) ? Character($0) : " " }
            .reduce(into: "") { $0.append($1) }.split(separator: " ").map(String.init)
        // Arabic article on each word: «الدانوب» and «دانوب».
        tokens = tokens.map { $0.count > 4 && $0.hasPrefix("ال") ? String($0.dropFirst(2)) : $0 }
        let leading: Set<String> = ["شركه", "موسسه", "al", "el"]
        while tokens.count > 1, let first = tokens.first, leading.contains(first) { tokens.removeFirst() }
        let trailing: Set<String> = ["sa", "sau", "ksa", "saudi", "arabia", "ar", "riyadh", "jeddah", "jed", "ryd", "dammam", "khobar",
                                     "makkah", "mecca", "madinah", "medina", "الرياض", "جده", "الدمام", "الخبر", "مكه", "المدينه", "السعوديه",
                                     "co", "ltd", "llc", "est", "inc", "company", "branch", "br"]
        var changed = true
        while changed, tokens.count > 1 {
            changed = false
            if let last = tokens.last, trailing.contains(last) || last.allSatisfy(\.isNumber) { tokens.removeLast(); changed = true }
        }
        let compact = tokens.joined()
        guard !compact.isEmpty else { return "" }
        // An alias applies when the whole key equals a variant, or the first word is a distinctive brand word. Common words and
        // names (كريم، زين، دواء، apple ...) match only as the whole key, so a person or shop that starts with one is never merged.
        for alias in aliases where alias.whole.contains(compact) || alias.brand.contains(compact)
            || tokens.first.map({ alias.brand.contains($0) }) == true { return alias.canonical }
        return compact
    }

    /// Two names are one merchant when their keys agree. A key shorter than three characters never matches by containment.
    public static func matches(_ lhs: String?, _ rhs: String?) -> Bool {
        let a = key(lhs), b = key(rhs)
        return !a.isEmpty && a == b
    }

    private static func fold(_ text: String) -> String {
        var out = String.UnicodeScalarView()
        for scalar in text.unicodeScalars {
            switch scalar.value {
            case 0x0623, 0x0625, 0x0622, 0x0671: out.append(Unicode.Scalar(0x0627)!)   // أ إ آ ٱ → ا
            case 0x0629: out.append(Unicode.Scalar(0x0647)!)                           // ة → ه
            case 0x0649: out.append(Unicode.Scalar(0x064A)!)                           // ى → ي
            case 0x0624: out.append(Unicode.Scalar(0x0648)!)                           // ؤ → و
            case 0x0626: out.append(Unicode.Scalar(0x064A)!)                           // ئ → ي
            default: out.append(scalar)
            }
        }
        return String(out)
    }

    /// Well-known merchants printed in Arabic and Latin. Variants are already folded and compact (no spaces). `brand` words are unambiguous
    /// and also match as the first word; `whole` variants match only the entire key.
    private static let aliases: [(canonical: String, brand: [String], whole: [String])] = [
        ("starbucks", ["starbucks", "ستاربكس"], []),
        ("mcdonalds", ["mcdonalds", "mcdonald", "ماكدونالدز", "ماكدونالد"], []),
        ("kfc", ["kfc", "كنتاكي"], []),
        ("albaik", ["albaik"], ["بيك", "البيك"]),
        ("hungerstation", ["hungerstation", "هنقرستيشن"], ["هنقر"]),
        ("jahez", [], ["jahez", "جاهز"]),
        ("careem", ["careem"], ["كريم"]),
        ("uber", ["uber"], ["اوبر"]),
        ("noon", [], ["noon", "نون"]),
        ("amazon", ["amazon", "امازون"], []),
        ("netflix", ["netflix", "نتفلكس", "نتفليكس"], []),
        ("spotify", ["spotify", "سبوتيفاي"], []),
        ("apple", [], ["apple", "ابل"]),
        ("danube", ["danube"], ["دانوب"]),
        ("panda", [], ["panda", "بنده"]),
        ("jarir", ["jarir"], ["جرير"]),
        ("extra", [], ["extra", "اكسترا"]),
        ("nahdi", [], ["nahdi", "نهدي"]),
        ("aldawaa", [], ["aldawaa", "dawaa", "دواء"]),
        ("stcpay", [], ["stcpay"]),
        ("mobily", ["mobily", "موبايلي"], []),
        ("zain", [], ["zain", "زين"])
    ]
}
