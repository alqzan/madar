# UIKit RTL Reference

## Table of Contents
1. [Auto Layout — Semantic Constraints](#autolayout)
2. [SemanticContentAttribute](#semantic)
3. [UILabel & Text Alignment](#labels)
4. [UITableView & UICollectionView](#tableview)
5. [UINavigationController](#navigation)
6. [Custom Cells](#cells)
7. [UIStackView](#stackview)
8. [Custom Drawing (Core Graphics)](#drawing)
9. [View Transforms & Animations](#animations)

---

## 1. Auto Layout — Semantic Constraints {#autolayout}

Always use `leadingAnchor` / `trailingAnchor`. Never use `leftAnchor` / `rightAnchor` unless you 
explicitly need absolute (non-flipping) positioning (maps, video players).

```swift
// ❌ Wrong — doesn't flip in RTL
NSLayoutConstraint.activate([
    label.leftAnchor.constraint(equalTo: view.leftAnchor, constant: 16),
    label.rightAnchor.constraint(equalTo: view.rightAnchor, constant: -16),
])

// ✅ Correct — flips automatically
NSLayoutConstraint.activate([
    label.leadingAnchor.constraint(equalTo: view.leadingAnchor, constant: 16),
    label.trailingAnchor.constraint(equalTo: view.trailingAnchor, constant: -16),
])
```

### Interface Builder
In IB/Storyboard: set constraint type to **"Leading"** and **"Trailing"** in the dropdown.
Uncheck "Relative to margin" only when you have a specific reason.

---

## 2. SemanticContentAttribute {#semantic}

Controls whether a view flips its content in RTL.

```swift
// Default — respects locale (use this everywhere possible)
view.semanticContentAttribute = .unspecified

// Force RTL flip (rarely needed)
view.semanticContentAttribute = .forceRightToLeft

// Force LTR — for maps, video, logos, etc.
mapView.semanticContentAttribute = .forceLeftToRight        // RTL: intentionally LTR
videoPlayerView.semanticContentAttribute = .forceLeftToRight // RTL: intentionally LTR

// Spatial — for controls like sliders (value goes left→right regardless of locale)
slider.semanticContentAttribute = .spatial

// Playback — for media transport controls
playbackBar.semanticContentAttribute = .playback
```

### Check effective direction at runtime
```swift
let dir = view.effectiveUserInterfaceLayoutDirection  // .leftToRight or .rightToLeft
let isRTL = dir == .rightToLeft
```

---

## 3. UILabel & Text Alignment {#labels}

```swift
// ✅ .natural — follows paragraph's base direction
label.textAlignment = .natural

// ✅ .justified with natural base direction
label.textAlignment = .justified

// ❌ Avoid hardcoding
label.textAlignment = .left   // breaks in RTL
label.textAlignment = .right  // breaks in RTL
```

### Attributed Strings with BiDi
```swift
let style = NSMutableParagraphStyle()
style.baseWritingDirection = .natural        // ← critical for mixed text
style.alignment = .natural

let attrs: [NSAttributedString.Key: Any] = [
    .font: UIFont.systemFont(ofSize: 16),
    .paragraphStyle: style
]
label.attributedText = NSAttributedString(string: text, attributes: attrs)
```

---

## 4. UITableView & UICollectionView {#tableview}

Table / collection views inherit direction from their parent automatically.

```swift
class ContactsViewController: UITableViewController {

    override func viewDidLoad() {
        super.viewDidLoad()
        // ✅ No special RTL setup needed — UITableView inherits from the view hierarchy
        tableView.register(ContactCell.self, forCellReuseIdentifier: "ContactCell")
    }
}
```

### Swipe Actions — use semantic edges

```swift
// ✅ Trailing swipe (semantic) — appears on the RTL-correct side
override func tableView(
    _ tableView: UITableView,
    trailingSwipeActionsConfigurationForRowAt indexPath: IndexPath
) -> UISwipeActionsConfiguration? {
    let delete = UIContextualAction(style: .destructive, title: "حذف") { _, _, completion in
        self.deleteItem(at: indexPath)
        completion(true)
    }
    return UISwipeActionsConfiguration(actions: [delete])
}
```

---

## 5. UINavigationController {#navigation}

`UINavigationController` handles RTL automatically — back button flips, swipe-to-go-back works.

### Custom Back Button
```swift
let backImage = UIImage(systemName: "chevron.backward")?
    .imageFlippedForRightToLeftLayoutDirection()  // RTL: mirror chevron

navigationItem.leftBarButtonItem = UIBarButtonItem(
    image: backImage,
    style: .plain,
    target: self,
    action: #selector(goBack)
)
```

### Push Transition — RTL Custom Transition
```swift
final class RTLPushAnimator: NSObject, UIViewControllerAnimatedTransitioning {
    let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
    let isPush: Bool

    init(isPush: Bool) {
        self.isPush = isPush
        super.init()
    }

    func animateTransition(using ctx: UIViewControllerContextTransitioning) {
        guard let toView = ctx.view(forKey: .to) else { return }
        let width = ctx.containerView.bounds.width
        let direction: CGFloat = isRTL ? -1 : 1
        let startX = isPush ? direction * width : 0
        let endX = isPush ? 0 : direction * -width

        toView.transform = CGAffineTransform(translationX: startX, y: 0)
        ctx.containerView.addSubview(toView)

        UIView.animate(withDuration: 0.35, animations: {
            toView.transform = CGAffineTransform(translationX: endX, y: 0)
        }, completion: { _ in
            ctx.completeTransition(!ctx.transitionWasCancelled)
        })
    }

    func transitionDuration(using _: UIViewControllerContextTransitioning?) -> TimeInterval { 0.35 }
}
```

---

## 6. Custom Cells {#cells}

```swift
final class TransactionCell: UITableViewCell {

    private let amountLabel = UILabel()
    private let titleLabel = UILabel()
    private let iconView = UIImageView()

    override init(style: UITableViewCell.CellStyle, reuseIdentifier: String?) {
        super.init(style: style, reuseIdentifier: reuseIdentifier)
        setupViews()
    }

    private func setupViews() {
        // RTL: Always use leading/trailing — never left/right
        NSLayoutConstraint.activate([
            iconView.leadingAnchor.constraint(equalTo: contentView.leadingAnchor, constant: 16),
            iconView.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
            iconView.widthAnchor.constraint(equalToConstant: 40),
            iconView.heightAnchor.constraint(equalToConstant: 40),

            titleLabel.leadingAnchor.constraint(equalTo: iconView.trailingAnchor, constant: 12),
            titleLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),

            amountLabel.trailingAnchor.constraint(equalTo: contentView.trailingAnchor, constant: -16),
            amountLabel.centerYAnchor.constraint(equalTo: contentView.centerYAnchor),
        ])

        titleLabel.textAlignment = .natural   // RTL: .natural respects locale
        amountLabel.textAlignment = .natural
    }

    func configure(with transaction: Transaction) {
        titleLabel.text = transaction.title
        // RTL: Use locale-aware number formatter (see bidi-text.md)
        amountLabel.text = transaction.formattedAmount
        iconView.image = UIImage(systemName: transaction.icon)
        // RTL: Don't flip transaction category icons
        iconView.semanticContentAttribute = .unspecified
    }
}
```

---

## 7. UIStackView {#stackview}

```swift
let spacer = UIView()
spacer.setContentHuggingPriority(.defaultLow, for: .horizontal)

let stack = UIStackView(arrangedSubviews: [iconView, labelStack, spacer, chevron])
stack.axis = .horizontal
stack.alignment = .center
stack.spacing = 12
// ✅ UIStackView respects semantic layout direction automatically
// The order of arrangedSubviews is semantic (leading → trailing)
// and automatically reverses in RTL.
```

If you need a view on the absolute left (not semantic), use `leftAnchor` with a comment:
```swift
// RTL: intentionally LTR — watermark always bottom-left of media
watermarkView.leftAnchor.constraint(equalTo: mediaView.leftAnchor, constant: 8) // RTL: LTR only
```

---

## 8. Custom Drawing (Core Graphics) {#drawing}

Core Graphics uses absolute coordinates — you must flip manually.

```swift
override func draw(_ rect: CGRect) {
    guard let ctx = UIGraphicsGetCurrentContext() else { return }

    let isRTL = effectiveUserInterfaceLayoutDirection == .rightToLeft

    if isRTL {
        // Flip the coordinate system horizontally
        ctx.translateBy(x: rect.width, y: 0)
        ctx.scaleBy(x: -1, y: 1)
    }

    // Now draw as if LTR — it will flip for RTL
    let startX: CGFloat = 16
    ctx.move(to: CGPoint(x: startX, y: rect.midY))
    ctx.addLine(to: CGPoint(x: rect.width - 16, y: rect.midY))
    ctx.strokePath()
}
```

---

## 9. View Transforms & Animations {#animations}

```swift
// RTL: Mirror sliding animations
func slideIn(view: UIView, fromLeading: Bool) {
    let isRTL = UIApplication.shared.userInterfaceLayoutDirection == .rightToLeft
    let screenWidth = UIScreen.main.bounds.width

    // In RTL, "leading" is the right side of the screen
    let startOffset = fromLeading
        ? (isRTL ? screenWidth : -screenWidth)
        : (isRTL ? -screenWidth : screenWidth)

    view.transform = CGAffineTransform(translationX: startOffset, y: 0)
    UIView.animate(withDuration: 0.3, delay: 0, options: .curveEaseOut) {
        view.transform = .identity
    }
}
```
