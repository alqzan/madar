# M0-T12 contrast audit triage

12 October 2026 — Codex Standard. Read-only classification against the saved root result `Madar/Artifacts/run4-accessibility-top-integrated.xcresult` on the iPhone 17 Pro / iOS 26.5 simulator. No product build or test was repeated.

## Finding

The focus-bound failure in the combined run was the `43.99999999999994 < 44.0` floating-point assertion, already repaired with a `1e-9` point comparison allowance. The later focused run `run4-focus-rounding.log` confirms the repaired focus/search/heading-growth UI journey passed: one test, zero failures, 73.402 seconds. Do not rerun that unchanged case.

The remaining audit failure is isolated to **Settings, light appearance, system Dynamic Type**. In the combined run, home/light produced no audit callback, Settings/light produced one callback, and home/dark plus Settings/dark produced none. The callback was:

```text
Contrast failed for SwiftUI.AccessibilityNode
frame=nil; fullyVisible=nil; element=nil
```

`xcresulttool export attachments` shows 21 attachments for the audit test. The issue-specific text contains no further location or color detail. The associated screenshot is the Settings screen, but there is no highlighted target because the audit supplied no element. Visible secondary labels in `CustomizeMadar` use `theme.secondaryInk`; `RoomTheme.secondaryInk` resolves to `ink2`, whose approved light theme pairs are 4.68:1 on the background and 4.97:1 on the surface. This source/token trace makes those visible labels less likely as the cause, but it cannot identify the nil-element issue or establish its measured foreground/background pair. The XCTest helper prints and returns `false` for every issue, so this result was not allowlisted or suppressed.

Apple documents [`XCUIAccessibilityAuditIssue.element`](https://developer.apple.com/documentation/xcuiautomation/xcuiaccessibilityauditissue) as optional and defines contrast auditing as a check of overlapping elements in its [accessibility audit guide](https://developer.apple.com/documentation/accessibility/performing-accessibility-audits-for-your-app). A nil element therefore explains the absent locator, but it does not prove the audit result is spurious. The correct classification is **unresolved possible contrast defect**, not a verified false positive and not a source-localized defect.

## Next evidence needed

Keep M0-T12 `needs-fix`. Use Accessibility Inspector on the light/system Settings screen to obtain the affected element, highlight and measured foreground/background pair. If it still reports no element, collect an actionable platform audit trace before changing colors or the current audit handler. Do not weaken or suppress `.all` based on this xcresult alone. Spoken VoiceOver and physical-device acceptance remain separate.

Sources: `Madar/Artifacts/run4-accessibility-top-integrated.log` lines 436–438; exported `Complete Issue Description.txt` and `App Screenshot` from the same xcresult; `Madar/Artifacts/run4-focus-rounding.log` lines 1293–1299; `Madar/App/CustomizeMadar.swift`; `Madar/Packages/MadarDesign/Sources/MadarDesign/Theme.swift`; `docs/HANDOFF/design-tokens.json` light ink2 pairs; `docs/reviews/M0-accessibility-fixes.md`.

## Live Mac follow-up — 2026-10-12

The Mac is now available. Device Hub shows a booted iPhone 17 Pro / iOS 26.5 simulator. I launched installed bundle `com.alqzan.madar2`, completed its local Riyadh first-run screen, and opened Customize. Device Hub's accessibility tree exposes `settings-search` with value `ابحث في إعدادات مدار…`; the light screenshot shows the stock placeholder in a pale gray. The installed bundle's exact source revision was not established, so this observation does not identify the remaining candidate failure.

Accessibility Inspector was opened from the active Xcode installation and targeted `Simulator > مدار`. Its Audit view showed `Run Audit`, but both an accessibility-index click and a coordinate click left the results pane empty. The Xcode installation has Device Hub but no standalone `Simulator.app` under `Contents/Developer/Applications`; Device Hub is the active simulator surface. This is not a new pass, actionable contrast measurement, or proof that the earlier nil-element issue is a false positive. No code, audit handler, theme token, or color was changed. Keep T12 `needs-fix` and preserve the existing `.all` failure.

Next: use the candidate-specific accessibility UI test or another actionable platform trace to identify the measured element/pair; keep the finding open if it remains nil. Do not change colors or suppress the audit without that evidence. Current focused green UI output remains reusable; it was not rerun.


## Isolated Settings diagnostic attempt — 12 October 2026

A narrow source patch was prepared at `/tmp/madar-t12-settings-only-materialized.patch`: it launches Settings directly with a fresh store and light appearance, captures the pre-audit accessibility hierarchy and screenshot, and invokes `performAccessibilityAudit(for: .all)` without suppressing any issue. Independent GPT-6.1 Sol High source review approved with no findings. The test omits `MADAR_UI_SIZE`, so it follows the simulator's current Dynamic Type setting; this does not prove the simulator is at L. Runtime remains unverified.

The first focused build exited 65 before XCTest because nine ignored font resources were absent from the candidate worktree. Those nine files were copied from the main checkout after matching their hashes. The second build still exited 65 before XCTest: `Amiri-Bold.ttf` remained missing, and the log also reports `Ld Madar.app/__preview.dylib` failure. The saved `.xcresult` and log contain no further linker diagnosis. Zero tests ran; no third attempt was made under the two-attempt limit. A read-only inventory confirms that the main checkout has `Amiri-Bold.ttf`, the candidate worktree does not, and the other nine font/license resources are present.

Next: perform read-only resource and linker-diagnostic preflight before authorizing a new isolated run. The visible tab-bar overlap is not yet tied to the nil-element contrast callback. Keep T12 `needs-fix`; make no color or suppression change without an actionable target and measured pair.


## Top follow-up after verified workspace preparation — 12 October 2026

Mandatory GPT-6.1 Sol xhigh diagnosis inspected the saved failed build/xcresult without rerunning: the preview-link task failed in .00650394s with only a generic error, overlapping the missing-font copy. Cancellation was plausible, not proven. Main/candidate project, scheme and project.yml matched; no preview-disable or linker override was introduced.

M0-T15 helper validated all11 font/license inputs and copied only the missing pinned `Amiri-Bold.ttf` (SHA256 `8cfed49b66de57e360ac61631d882dddfa23095d3ddb39fc2133eaf93892e79a`). The already independently approved diagnostic patch was preserved at `bfa878b` on the existing T12 branch. One Top attempt used the same destination, signing and derivedData settings with new `/tmp/madar-t12-preflight-top.log` and `.xcresult`.

Result: the font copy, preview linking and codesigning passed; XCTest ran the isolated Settings audit. The unsuppressed callback remains `Contrast failed for SwiftUI.AccessibilityNode; frame=nil; fullyVisible=nil; element=nil`. `Executed 1 test, with 1 failure ... in 13.339 seconds`; command exit65 is now an audit failure, not the prior build blocker. Device: iPhone17Pro/iOS26.5 simulator; system Dynamic Type was unchanged and is not proven L. No second attempt or product color/audit-suppression change.

Acceptance disposition: workspace resource/build blockage resolved for this run; T12 remains needs-fix because contrast target/pair is unidentified. Obtain an actionable platform trace; do not repeat this unchanged diagnostic or call it an accepted accessibility result. Owner-device, VoiceOver/Reduce Motion and whole M0 gate remain separate.

Durable local copy: `Madar/Artifacts/workflow-repair-2026-10-12/madar-t12-preflight-top.log`, matching `.xcresult` and `madar-t12-preflight-top-attachments/`. Preserved outside `/tmp`, ignored by Git; this adds no new test execution.

Root inspected the preserved failure screenshot `9A8CF555-98C8-4042-863A-D6A3CC3EFCB5.png`: Settings/light is visible, with no highlighted audit target. The floating bar overlays lower visible content; this does not identify the contrast callback or justify a color change.
