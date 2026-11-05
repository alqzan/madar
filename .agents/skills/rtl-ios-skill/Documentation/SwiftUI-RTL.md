# SwiftUI RTL Reference

## Table of Contents
1. [Layout Direction Environment](#layout-direction)
2. [Text & Typography](#text)
3. [Stack Views](#stacks)
4. [Navigation](#navigation)
5. [Custom Modifiers](#modifiers)
6. [Animations & Transitions](#animations)
7. [Lists & Grids](#lists)
8. [Common Pitfalls](#pitfalls)

---

## 1. Layout Direction Environment {#layout-direction}

SwiftUI automatically flips `.leading`/`.trailing` in RTL. You only need to read the environment
when making conditional logic.

```swift
struct ContentView: View {
    @Environment(\.layoutDirection) var layoutDirection

    var isRTL: Bool { layoutDirection == .rightToLeft }

    var body: some View {
        VStack(alignment: .leading) {         // ✅ auto-flips
            Text("Hello / مرحبا")
                .padding(.leading, 16)        // ✅ auto-flips
        }
    }
}
```

### Injecting Direction (for previews / testing)
```swift
struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            ContentView()
                .environment(\.layoutDirection, .leftToRight)
                .previewDisplayName("LTR")

            ContentView()
                .environment(\.layoutDirection, .rightToLeft)
                .previewDisplayName("RTL")
        }
    }
}
```

---

## 2. Text & Typography {#text}

```swift
// ✅ Correct — .leading respects direction
Text("مرحبا بالعالم")
    .multilineTextAlignment(.leading)
    .frame(maxWidth: .infinity, alignment: .leading)

// ❌ Wrong — hardcoded
Text("Hello")
    .multilineTextAlignment(.trailing)
    .frame(maxWidth: .infinity, alignment: .right)
```

### Mixed BiDi Text (Arabic + English numbers)
```swift
// Use NSAttributedString for fine-grained BiDi control
let paragraph = NSMutableParagraphStyle()
paragraph.baseWritingDirection = .natural   // ← key
let attributed = NSAttributedString(
    string: "Order #١٢٣",
    attributes: [.paragraphStyle: paragraph]
)
Text(AttributedString(attributed))
```

---

## 3. Stack Views {#stacks}

HStack with leading alignment works correctly automatically:

```swift
// ✅ This is all you need — SwiftUI handles the flip
HStack(alignment: .top) {
    Image(systemName: "person.circle")
    VStack(alignment: .leading) {
        Text("Name").bold()
        Text("Subtitle").foregroundStyle(.secondary)
    }
    Spacer()
    Image(systemName: "chevron.forward")           // mirrors automatically
        .flipsForRightToLeftLayoutDirection(true)
}
.padding(.horizontal)
```

### When to Use `flipsForRightToLeftLayoutDirection`
```swift
// Mirror: directional icons
Image(systemName: "arrow.right").flipsForRightToLeftLayoutDirection(true)
Image(systemName: "chevron.right").flipsForRightToLeftLayoutDirection(true)
Image(systemName: "arrowshape.right.fill").flipsForRightToLeftLayoutDirection(true)

// Do NOT mirror: logos, avatars, maps, media controls
Image("app_logo").flipsForRightToLeftLayoutDirection(false)  // RTL: intentionally LTR
Image(systemName: "play.fill").flipsForRightToLeftLayoutDirection(false) // RTL: intentionally LTR
```

---

## 4. Navigation {#navigation}

SwiftUI `NavigationStack` handles RTL natively — back button and swipe gesture automatically flip.

```swift
NavigationStack {
    List(items) { item in
        NavigationLink(value: item) {
            ItemRow(item: item)   // ✅ just build the row semantically
        }
    }
    .navigationTitle("قائمة")
    .navigationBarTitleDisplayMode(.large)
}
```

### Custom Back Button
```swift
.navigationBarBackButtonHidden(true)
.toolbar {
    ToolbarItem(placement: .navigationBarLeading) {  // ✅ semantic placement
        Button(action: dismiss) {
            HStack(spacing: 4) {
                Image(systemName: "chevron.backward")
                    .flipsForRightToLeftLayoutDirection(true)  // RTL: mirror arrow
                Text("رجوع")
            }
        }
    }
}
```

---

## 5. Custom View Modifiers {#modifiers}

```swift
// MARK: - RTL Conditional Modifier

struct RTLConditional: ViewModifier {
    @Environment(\.layoutDirection) var direction
    let ltr: (AnyView) -> AnyView
    let rtl: (AnyView) -> AnyView

    func body(content: Content) -> some View {
        if direction == .rightToLeft {
            rtl(AnyView(content))
        } else {
            ltr(AnyView(content))
        }
    }
}

extension View {
    func rtlConditional(
        ltr: @escaping (AnyView) -> AnyView,
        rtl: @escaping (AnyView) -> AnyView
    ) -> some View {
        modifier(RTLConditional(ltr: ltr, rtl: rtl))
    }
}

// Usage:
Text("Amount")
    .rtlConditional(
        ltr: { AnyView($0.padding(.leading)) },
        rtl: { AnyView($0.padding(.trailing)) }
    )
```

### Direction-Aware Padding
```swift
extension View {
    func leadingPadding(_ value: CGFloat = 16) -> some View {
        self.padding(.leading, value)   // SwiftUI auto-flips — this is enough
    }

    /// Use ONLY when you need different LTR vs RTL values
    func directionalPadding(leading: CGFloat, trailing: CGFloat) -> some View {
        self.padding(.leading, leading).padding(.trailing, trailing)
    }
}
```

---

## 6. Animations & Transitions {#animations}

SwiftUI slide transitions need manual RTL correction:

```swift
struct SlideTransitionModifier: ViewModifier {
    @Environment(\.layoutDirection) var direction
    let isVisible: Bool

    var slideEdge: Edge {
        isVisible ? (direction == .rightToLeft ? .trailing : .leading)
                  : (direction == .rightToLeft ? .leading : .trailing)
    }

    func body(content: Content) -> some View {
        content.transition(.move(edge: slideEdge))
    }
}

// Usage
SidePanel()
    .modifier(SlideTransitionModifier(isVisible: showPanel))
```

---

## 7. Lists & Grids {#lists}

```swift
// List — works automatically with semantic layout
List(contacts) { contact in
    HStack {
        ContactAvatar(contact)           // ✅ leading
        VStack(alignment: .leading) {
            Text(contact.name)
            Text(contact.phone).foregroundStyle(.secondary)
        }
        Spacer()
        Text(contact.lastSeen)           // ✅ trailing
            .foregroundStyle(.tertiary)
    }
}

// Swipe actions — flipped automatically in RTL
.swipeActions(edge: .trailing) {          // ✅ semantic edge
    Button(role: .destructive) { delete() } label: {
        Label("حذف", systemImage: "trash")
    }
}

// LazyVGrid
let columns = [GridItem(.flexible()), GridItem(.flexible())]
LazyVGrid(columns: columns, alignment: .leading) {
    // content auto-flows RTL
}
```

---

## 8. Common Pitfalls {#pitfalls}

| Pitfall | Fix |
|---------|-----|
| `.frame(alignment: .left)` | `.frame(alignment: .leading)` |
| `.padding(.right, 8)` | `.padding(.trailing, 8)` |
| `Spacer()` on wrong side | Layout is semantic — re-evaluate logic |
| Custom `GeometryReader` with absolute x | Use `%` of width or leading anchors |
| Hardcoded `offset(x: 20)` | Use `padding` or `alignment` |
| `transition(.slide)` wrong direction | Use `SlideTransitionModifier` above |
| SF Symbol not mirrored | Add `.flipsForRightToLeftLayoutDirection(true)` |
