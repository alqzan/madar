# M0-T12 contrast audit triage

12 October 2026 — Codex Standard. Read-only classification against the saved root result `Madar/Artifacts/run4-accessibility-top-integrated.xcresult` on the iPhone 17 Pro / iOS 26.5 simulator. No product build or test was repeated.

## Finding

The focus-bound failure in the combined run was the `43.99999999999994 < 44.0` floating-point assertion, already repaired with a `1e-9` point comparison allowance. The later focused run `run4-focus-rounding.log` confirms the repaired focus/search/heading-growth UI journey passed: one test, zero failures, 73.402 seconds. Do not rerun that unchanged case.

The remaining audit failure is isolated to **Settings, light appearance, system Dynamic Type**. In the combined run, home/light produced no audit callback, Settings/light produced one callback, and home/dark plus Settings/dark produced none. The callback was:

```text
Contrast failed for SwiftUI.AccessibilityNode
frame=nil; fullyVisible=nil; element=nil
```

`xcresulttool export attachments` shows 21 attachments for the audit test. The issue-specific text contains no further location or color detail. The associated screenshot is the Settings screen, but there is no highlighted target because the audit supplied no element. Several secondary labels are visibly muted; the image cannot identify which text pair triggered the issue or establish its measured contrast. The XCTest helper prints and returns `false` for every issue, so this result was not allowlisted or suppressed.

Apple documents [`XCUIAccessibilityAuditIssue.element`](https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityauditissue) as optional and defines contrast auditing as a check of overlapping elements in its [accessibility audit guide](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app). A nil element therefore explains the absent locator, but it does not prove the audit result is spurious. The correct classification is **unresolved possible contrast defect**, not a verified false positive and not a source-localized defect.

## Next evidence needed

Keep M0-T12 `needs-fix`. Use Accessibility Inspector on the light/system Settings screen to obtain the affected element, highlight and measured foreground/background pair. If it still reports no element, collect an actionable platform audit trace before changing colors or the current audit handler. Do not weaken or suppress `.all` based on this xcresult alone. Spoken VoiceOver and physical-device acceptance remain separate.

Sources: `Madar/Artifacts/run4-accessibility-top-integrated.log` lines 436–438; exported `Complete Issue Description.txt` and `App Screenshot` from the same xcresult; `Madar/Artifacts/run4-focus-rounding.log` lines 1293–1299; `docs/reviews/M0-accessibility-fixes.md`.
