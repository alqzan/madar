# RTL Testing Reference

## Table of Contents
1. [Simulator Setup](#simulator)
2. [Launch Arguments](#launch-args)
3. [SwiftUI Previews](#previews)
4. [XCTest — UI Testing](#xctest)
5. [Snapshot Testing](#snapshots)
6. [Manual QA Checklist](#qa)

---

## 1. Simulator Setup {#simulator}

### Switch to an RTL locale in Simulator
1. **Settings → General → Language & Region**
2. Set **iPhone Language** to `العربية` (Arabic), `עברית` (Hebrew), `فارسی` (Persian), or `اردو` (Urdu)
3. Set **Region** to an RTL region, e.g., `Saudi Arabia` (ar_SA), `UAE` (ar_AE), `Iran` (fa_IR), or `Pakistan` (ur_PK)
4. Restart the app

### Faster: Use Scheme Launch Arguments (no restart needed)
See section below.

---

## 2. Launch Arguments {#launch-args}

Add to **Product → Scheme → Edit Scheme → Run → Arguments → Arguments Passed on Launch**:

```
-AppleLanguages (ar)
-AppleLocale ar_SA
```

Or for Hebrew:
```
-AppleLanguages (he)
-AppleLocale he_IL
```

Or for Persian (Farsi):
```
-AppleLanguages (fa)
-AppleLocale fa_IR
```

### In code (for debug builds only):
```swift
#if DEBUG
func forceRTLForTesting() {
    UserDefaults.standard.set(["ar"], forKey: "AppleLanguages")
    UserDefaults.standard.set("ar_SA", forKey: "AppleLocale")
    // Restart required for full effect, but layout direction updates immediately:
    UIView.appearance().semanticContentAttribute = .forceRightToLeft
}
#endif
```

---

## 3. SwiftUI Previews {#previews}

```swift
#Preview("Arabic RTL") {
    ContentView()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "ar_SA"))
}

#Preview("Hebrew RTL") {
    ContentView()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "he_IL"))
}

#Preview("Persian RTL") {
    ContentView()
        .environment(\.layoutDirection, .rightToLeft)
        .environment(\.locale, Locale(identifier: "fa_IR"))
}

#Preview("English LTR") {
    ContentView()
        .environment(\.layoutDirection, .leftToRight)
        .environment(\.locale, Locale(identifier: "en_US"))
}

// Macro-style (pre-iOS 17)
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
                .previewDisplayName("Arabic RTL")
            ContentView()
                .environment(\.layoutDirection, .leftToRight)
                .previewDisplayName("English LTR")
        }
    }
}
```

---

## 4. XCTest — UI Testing {#xctest}

```swift
final class RTLUITests: XCTestCase {

    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = [
            "-AppleLanguages", "(ar)",
            "-AppleLocale", "ar_SA"
        ]
        app.launch()
    }

    func testProfileScreenRTLLayout() {
        // Navigate to profile
        app.tabBars.buttons["profile"].tap()

        // Verify RTL: avatar should be on trailing side (right in LTR, left in RTL)
        let avatar = app.images["profile_avatar"]
        let nameLabel = app.staticTexts["profile_name"]

        XCTAssertTrue(avatar.exists)
        XCTAssertTrue(nameLabel.exists)

        // In RTL, leading = right side of screen (higher x values).
        // Avatar (leading) flips to the right; name appears to its left.
        XCTAssertGreaterThan(avatar.frame.minX, nameLabel.frame.maxX,
            "In RTL layout, avatar should appear to the RIGHT of name (leading = right in RTL)")
    }

    func testNavigationBackButtonRTL() {
        app.tables.cells.firstMatch.tap()
        let backButton = app.navigationBars.buttons.firstMatch
        XCTAssertTrue(backButton.exists, "Back button should exist")
        // In RTL, back button is on the right side of the nav bar
        let navBar = app.navigationBars.firstMatch
        XCTAssertGreaterThan(backButton.frame.midX, navBar.frame.midX,
            "In RTL, back button should be on the right/trailing side")
    }

    func testSwipeBackGestureRTL() {
        app.tables.cells.firstMatch.tap()
        // In RTL, swipe-to-go-back originates from the LEFT edge (a right swipe gesture)
        app.swipeRight()   // UIKit swipe gesture auto-adapts
        XCTAssertTrue(app.tables.firstMatch.exists, "Should have navigated back")
    }
}
```

---

## 5. Snapshot Testing {#snapshots}

Using [swift-snapshot-testing](https://github.com/pointfreeco/swift-snapshot-testing):

```swift
import SnapshotTesting

final class RTLSnapshotTests: XCTestCase {

    func testHomeScreenLTR() {
        let vc = HomeViewController()
        assertSnapshot(of: vc, as: .image(on: .iPhone16Pro))
    }

    func testHomeScreenRTL() {
        let vc = HomeViewController()
        // Inject RTL environment
        vc.view.semanticContentAttribute = .forceRightToLeft
        vc.view.setNeedsLayout()
        vc.view.layoutIfNeeded()

        assertSnapshot(
            of: vc,
            as: .image(on: .iPhone16Pro),
            named: "rtl"   // creates HomeScreenRTL.rtl.png reference
        )
    }

    // SwiftUI snapshot
    func testTransactionCardRTL() {
        let view = TransactionCard(amount: 250, title: "تسوق")
            .environment(\.layoutDirection, .rightToLeft)
            .frame(width: 390)

        assertSnapshot(of: view, as: .image)
    }
}
```

---

## 6. Manual QA Checklist {#qa}

Run this on both Arabic and Hebrew locales:

### Layout
- [ ] All text reads right-to-left
- [ ] Leading padding appears on the right
- [ ] Icons/avatars appear on correct (trailing → left in RTL) side
- [ ] List row chevrons point LEFT (←)
- [ ] Navigation bar title is on the right
- [ ] Back button is on the right side of nav bar

### Navigation
- [ ] Swipe-to-go-back works from the LEFT edge
- [ ] Push animation slides from LEFT
- [ ] Pop animation slides to RIGHT
- [ ] Tab bar items are in correct order (can be LTR or RTL depending on design)

### Text
- [ ] Arabic/Hebrew text renders correctly
- [ ] Mixed BiDi text (e.g., "Order #123 طلب") displays correctly
- [ ] Numbers use correct numeral system (Arabic-Indic if required)
- [ ] Dates formatted per locale
- [ ] Currency shows correct symbol and position

### Non-Flipping Views (must stay LTR)
- [ ] Maps do NOT flip
- [ ] Video player controls do NOT flip
- [ ] Progress bars that represent time do NOT flip (use `.playback`)
- [ ] Brand logos do NOT flip
- [ ] Mathematical expressions do NOT flip

### Edge Cases
- [ ] Empty states look correct
- [ ] Long strings don't break layout
- [ ] Modal sheets slide from correct edge
- [ ] Action sheets and alerts render correctly
- [ ] Keyboard appears correctly for Arabic input
