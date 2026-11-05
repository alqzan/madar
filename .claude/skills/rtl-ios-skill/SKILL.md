---
name: rtl-ios-skill
description: >
  Expert Right-to-Left (RTL) layout implementation for iOS apps (Swift/SwiftUI/UIKit).
  Use this skill whenever the user wants to: add RTL support, localize for Arabic/Hebrew/Farsi/Urdu,
  fix mirrored layouts, handle bidirectional text, implement locale-aware UI, audit an existing project
  for RTL issues, configure semantic content attributes, handle RTL in UITableView/UICollectionView,
  fix navigation direction for RTL languages, or ensure proper String Catalog / NSLocalizedString
  integration with RTL. Trigger even for adjacent topics like "internationalization", "i18n", "Arabic support",
  "Hebrew layout", "BiDi text", "flipped UI", or "mirror my views" — this skill covers all of it.
---

# RTL iOS Skill

You are an iOS RTL specialist. Your job is to help implement production-quality Right-to-Left layout
support across SwiftUI, UIKit, and hybrid apps. You understand the nuances of semantic layout,
BiDi text, locale detection, and Apple's RTL APIs deeply.

---

## Quick Decision Tree

```
User wants RTL support?
├── SwiftUI project?         → See: Documentation/SwiftUI-RTL.md
├── UIKit project?           → See: Documentation/UIKit-RTL.md
├── Hybrid (SwiftUI+UIKit)?  → Read both Documentation files
├── Text / BiDi issue?       → See: Documentation/BiDi-Text.md
├── Audit existing project?  → Run: Tools/rtl_audit.sh
└── Full integration setup?  → Follow INTEGRATION CHECKLIST below
```

---

## Core Principles (Always Apply)

### 1. Semantic Layout Over Absolute Positioning
Never use `.left` / `.right`. Always use `.leading` / `.trailing`.

```swift
// ❌ Wrong
stackView.alignment = .left

// ✅ Correct
stackView.alignment = .leading
```

### 2. Semantic Content Attribute (UIKit)
```swift
// RTL: intentionally LTR — map/video/logo views
imageView.semanticContentAttribute = .forceLeftToRight

// Default — always prefer:
imageView.semanticContentAttribute = .unspecified
```

### 3. RTL Detection

#### UIKit — Detection Methods

Pick the right method for the right context. Using the wrong one produces incorrect results when `semanticContentAttribute` overrides are in play.

```swift
// ✅ PREFERRED — view-level (layout code inside layoutSubviews, cells, etc.)
// Most accurate: respects semanticContentAttribute overrides on the view or its ancestors.
let isRTL = someView.effectiveUserInterfaceLayoutDirection == .rightToLeft

// ✅ PREFERRED — trait-based (inside UIViewController or UIView subclasses)
// Safe to call in traitCollectionDidChange(_:). Propagates through the hierarchy.
let isRTL = traitCollection.layoutDirection == .rightToLeft
// Or from any view:
let isRTL = view.traitCollection.layoutDirection == .rightToLeft

// ⚠️ APP-LEVEL ONLY — reflects the global app language setting.
// Does NOT respect per-view semanticContentAttribute overrides.
// Use for app-wide decisions (analytics, initial config) — not inside layout code.
let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft

// ℹ️ LOCALE-BASED — language writing direction, not UI direction.
// Use for text/string logic (e.g. BiDi isolation). Does not guarantee the UI is RTL.
let lang = Locale.current.language.languageCode?.identifier ?? ""
let isRTL = Locale.characterDirection(forLanguage: lang) == .rightToLeft

// ℹ️ TEXT-ONLY — for NSAttributedString / TextKit rendering only, not layout.
let str = "مرحبا بالعالم"
let writingDir = str.dominantLanguageWritingDirection // iOS 16+
```

**Quick rule:**
| Context | Use |
|---|---|
| `layoutSubviews`, cell config, constraint setup | `view.effectiveUserInterfaceLayoutDirection` |
| Inside `UIViewController` / `UIView` subclass | `traitCollection.layoutDirection` |
| App-wide checks, logging, feature flags | `UIApplication.shared.userInterfaceLayoutDirection` |
| Text/string direction logic | `Locale.characterDirection(forLanguage:)` |
| `NSAttributedString` / TextKit rendering | `NSWritingDirection` / `dominantLanguageWritingDirection` |

#### SwiftUI — Environment-Based Detection

```swift
@Environment(\.layoutDirection) var layoutDirection
var isRTL: Bool { layoutDirection == .rightToLeft }
```

---

### 4. Text Alignment
```swift
// SwiftUI
Text("مرحبا").multilineTextAlignment(.leading)

// UIKit
label.textAlignment = .natural
```

### 5. Image Mirroring
```swift
// SwiftUI
Image(systemName: "chevron.right")
    .flipsForRightToLeftLayoutDirection(true)

// UIKit
imageView.image = UIImage(systemName: "chevron.right")?
    .imageFlippedForRightToLeftLayoutDirection()
```

---

## Integration Checklist

- [ ] **1. Enable RTL in scheme** — Launch arg: `-AppleLanguages (ar)`
- [ ] **2. Audit layout** — `Tools/rtl_audit.sh /path/to/project`
- [ ] **3. Fix hardcoded directions** — `.left`/`.right` → `.leading`/`.trailing`
- [ ] **4. Fix text alignment** — `.natural` UIKit, `.leading` SwiftUI
- [ ] **5. Mirror directional icons** — `flipsForRightToLeftLayoutDirection(true)` / `imageFlippedForRightToLeftLayoutDirection()`
- [ ] **6. Navigation stack** — Verify back gesture and transition direction
- [ ] **7. Custom transitions** — Use `RTLPushAnimator` from Documentation/UIKit-RTL.md
- [ ] **8. String Catalog** — Add `ar`, `he`, `fa`, `ur` (see Documentation/BiDi-Text.md)
- [ ] **9. Number/Date formatting** — Use locale-aware formatters (see Documentation/BiDi-Text.md)
- [ ] **10. Test on simulator** — Set region to an RTL locale (e.g., Saudi Arabia `ar_SA`, UAE `ar_AE`, Iran `fa_IR`)

---

## Common Patterns — Quick Reference

### RTL-aware HStack (SwiftUI)
```swift
struct RTLHStack<Content: View>: View {
    @Environment(\.layoutDirection) var direction
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        HStack {
            if direction == .rightToLeft {
                Spacer()
                content
            } else {
                content
                Spacer()
            }
        }
    }
}
```

### RTLLayoutHelper (UIKit)
```swift
final class RTLLayoutHelper {
    /// Uses traitCollection where a view is available — fall back to UIApplication only when not.
    static func isRTL(in view: UIView) -> Bool {
        view.effectiveUserInterfaceLayoutDirection == .rightToLeft
    }

    /// App-level check — use only outside of view/layout context.
    static var isRTLApp: Bool {
        UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
    }

    static func mirrorTransform(in view: UIView) -> CGAffineTransform {
        isRTL(in: view) ? CGAffineTransform(scaleX: -1, y: 1) : .identity
    }

    static func directionalX(_ value: CGFloat, in view: UIView) -> CGFloat {
        isRTL(in: view) ? -value : value
    }
}
```

### BiDi string helpers
```swift
extension String {
    var ltrIsolated: String { "\u{2066}\(self)\u{2069}" }  // embed LTR in RTL text
    var rtlIsolated: String { "\u{2067}\(self)\u{2069}" }  // embed RTL in LTR text
}

// Locale-aware number/date formatting
let price = 1234.5.formatted(.number.locale(.current))
let date  = Date.now.formatted(.dateTime.locale(.current))
let currency = 250.0.formatted(.currency(code: "SAR").locale(.current))  // iOS 15+
```

---

## Reference Files

| File | When to Read |
|------|-------------|
| `Documentation/SwiftUI-RTL.md` | SwiftUI layouts, modifiers, transitions, lists |
| `Documentation/UIKit-RTL.md` | UIKit constraints, cells, nav, Core Graphics |
| `Documentation/BiDi-Text.md` | BiDi text, formatters, String Catalogs |
| `Documentation/Testing-RTL.md` | Simulator setup, XCTest, snapshots, QA checklist |

---

## Output Format

When generating RTL integration code:
1. **Use native UIKit/SwiftUI APIs** — no external dependencies required
2. **Show before/after** for any fixes
3. **Comment RTL-specific decisions** with `// RTL:`
4. **Flag intentionally non-flipping views** with `// RTL: intentionally LTR`
5. **Include a test snippet** for non-trivial RTL behavior
6. **Wrap Swift 5.9+ features** in `#if swift(>=5.9)` / `#else` with a fallback
7. **Wrap iOS 15+ APIs** with `@available(iOS 15, *)` and a `NumberFormatter` fallback
