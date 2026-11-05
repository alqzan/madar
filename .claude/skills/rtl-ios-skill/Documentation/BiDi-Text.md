# BiDi Text & Formatters RTL Reference

Bidirectional (BiDi) text mixes RTL and LTR scripts in the same string.
This is common when displaying Arabic/Hebrew text mixed with Latin, numbers, URLs, or code.

## Table of Contents
1. [BiDi Fundamentals](#fundamentals)
2. [Unicode Control Characters](#unicode)
3. [Locale-Aware Number Formatting](#numbers)
4. [Date & Time Formatting](#dates)
5. [Currency Formatting](#currency)
6. [Phone Numbers & URLs](#phone)
7. [String Catalogs (Xcode 15+)](#string-catalogs)
8. [NSLocalizedString Patterns](#nslocalized)

---

## 1. BiDi Fundamentals {#fundamentals}

The Unicode BiDi algorithm determines display order for mixed strings. iOS applies it automatically, but you need to set the **base writing direction** correctly.

```swift
// ✅ Always set baseWritingDirection = .natural
// This lets the algorithm detect the first strong character
let style = NSMutableParagraphStyle()
style.baseWritingDirection = .natural

// For explicitly Arabic/Hebrew content:
style.baseWritingDirection = .rightToLeft

// For explicitly Latin content embedded in RTL context:
style.baseWritingDirection = .leftToRight
```

---

## 2. Unicode Control Characters {#unicode}

Insert these invisible characters to control BiDi rendering when the algorithm produces wrong results.

```swift
extension String {
    // Left-to-Right Embedding: wrap LTR content inside RTL text
    var ltrEmbedded: String { "\u{202A}\(self)\u{202C}" }

    // Right-to-Left Embedding: wrap RTL content inside LTR text
    var rtlEmbedded: String { "\u{202B}\(self)\u{202C}" }

    // Left-to-Right Mark: invisible LTR directional character
    static let ltrMark = "\u{200E}"

    // Right-to-Left Mark: invisible RTL directional character
    static let rtlMark = "\u{200F}"

    // Left-to-Right Isolate (preferred over embedding — no spillover)
    var ltrIsolated: String { "\u{2066}\(self)\u{2069}" }

    // Right-to-Left Isolate
    var rtlIsolated: String { "\u{2067}\(self)\u{2069}" }
}

// Example: Arabic text with an embedded English order ID
let text = "طلبك رقم \("ORD-12345".ltrIsolated) تم تأكيده"
```

---

## 3. Locale-Aware Number Formatting {#numbers}

Never format numbers manually for display. Always use `NumberFormatter` or Swift `FormatStyle`.

```swift
// ✅ Swift 5.5+ FormatStyle (preferred)
let price = 1234.5
let formatted = price.formatted(.number.locale(Locale(identifier: "ar_SA")))
// → "١٬٢٣٤٫٥" (Arabic-Indic digits)

let formatted_en = price.formatted(.number.locale(Locale(identifier: "en_US")))
// → "1,234.5"

// ✅ Current locale (adapts automatically)
let adaptive = price.formatted()  // uses user's locale

// ✅ NumberFormatter — more control
let formatter = NumberFormatter()
formatter.numberStyle = .decimal
formatter.locale = .current         // ← always use .current, not hardcoded
let result = formatter.string(from: NSNumber(value: price)) ?? ""
```

### Arabic-Indic vs Eastern Arabic Digits
```swift
// Arabic locale: ١٢٣ (Eastern Arabic / Arabic-Indic numerals)
// Arabic (Latin digits): 123 — use en_US-compatible locale

// If your design requires Latin digits even for Arabic users:
formatter.locale = Locale(identifier: "en_US")
// RTL: intentionally using Latin digits per design spec
```

---

## 4. Date & Time Formatting {#dates}

```swift
// ✅ Swift FormatStyle
let date = Date.now
let formatted = date.formatted(
    .dateTime
    .day().month(.wide).year()
    .locale(.current)   // ← adapts to user locale
)

// ✅ DateFormatter
let df = DateFormatter()
df.dateStyle = .long
df.timeStyle = .short
df.locale = .current    // ← always set locale
df.calendar = Calendar(identifier: .islamicUmmAlQura)  // for Saudi locale
let dateString = df.string(from: date)

// Calendar-aware date for Arabic users
func localizedDate(_ date: Date, locale: Locale = .current) -> String {
    date.formatted(.dateTime.locale(locale))
}
```

---

## 5. Currency Formatting {#currency}

```swift
// ✅ Swift FormatStyle (iOS 15+)
let amount = 250.0
let saudiRiyal = amount.formatted(.currency(code: "SAR").locale(Locale(identifier: "ar_SA")))
// → "٢٥٠٫٠٠ ر.س."

let usd = amount.formatted(.currency(code: "USD").locale(Locale(identifier: "en_US")))
// → "$250.00"

// ✅ Adaptive — follow user's locale & preferred currency
func format(amount: Double, currencyCode: String) -> String {
    amount.formatted(.currency(code: currencyCode).locale(.current))
}

// In UIKit / older targets:
let formatter = NumberFormatter()
formatter.numberStyle = .currency
formatter.currencyCode = "SAR"
formatter.locale = .current
```

---

## 6. Phone Numbers & URLs {#phone}

Phone numbers and URLs should generally be LTR even in RTL layouts:

```swift
// ✅ Wrap phone/URL in LTR isolate
let phone = "+966 50 123 4567"
label.text = phone.ltrIsolated   // from String extension above

// ✅ UILabel: force LTR for phone
phoneLabel.semanticContentAttribute = .forceLeftToRight // RTL: intentionally LTR

// For clickable links in attributed text:
let urlString = "https://example.com".ltrIsolated
```

---

## 7. String Catalogs (Xcode 15+) {#string-catalogs}

String Catalogs (`.xcstrings`) fully support RTL locales.

### Adding Arabic Localization
1. `File → New → String Catalog` (or add via Project settings → Localizations → `+`)
2. Select `Arabic (ar)`, `Hebrew (he)`, `Persian (fa)`, `Urdu (ur)` as needed
3. In `Localizable.xcstrings`, translations auto-appear from base strings

### Pluralization Rules
Arabic has 6 plural forms. String Catalog handles this:
```json
// Xcode generates these automatically for Arabic
"items_count" : {
  "localizations" : {
    "ar" : {
      "variations" : {
        "plural" : {
          "zero" : { "stringUnit" : { "state" : "translated", "value" : "لا توجد عناصر" } },
          "one"  : { "stringUnit" : { "state" : "translated", "value" : "عنصر واحد" } },
          "two"  : { "stringUnit" : { "state" : "translated", "value" : "عنصران" } },
          "few"  : { "stringUnit" : { "state" : "translated", "value" : "%lld عناصر" } },
          "many" : { "stringUnit" : { "state" : "translated", "value" : "%lld عنصرًا" } },
          "other": { "stringUnit" : { "state" : "translated", "value" : "%lld عنصر" } }
        }
      }
    }
  }
}
```

### Usage in Swift
```swift
// String Catalog (Swift 5.9 / Xcode 15)
Text("items_count \(count)", tableName: "Localizable")

// Or with String(localized:)
let message = String(localized: "items_count \(count)")
```

---

## 8. NSLocalizedString Patterns {#nslocalized}

```swift
// ✅ Standard pattern
let title = NSLocalizedString("profile.title", comment: "Profile screen title")

// ✅ With format arguments — use %@ for strings, %lld for integers
let greeting = String(
    format: NSLocalizedString("greeting.name %@", comment: "Greeting with user name"),
    userName
)

// ✅ Stringsdict for plurals (pre-Xcode 15)
// greeting.stringsdict:
// "items %lld" → NSStringFormatSpecTypeKey: NSStringPluralRuleType
// with keys: zero, one, two, few, many, other

// ✅ Swift String Interpolation macro (Xcode 15+)
let label = String(localized: "Hello, \(name)!")
```

### RTL-Specific Translation Notes
Add RTL context to comments so translators understand layout:
```swift
NSLocalizedString(
    "transaction.amount",
    comment: "Displayed at TRAILING edge of transaction row (right in LTR, left in RTL). Keep short."
)
```
