# M0-T12 narrow accessibility repair — runtime pending

2026-10-11, Codex Sol xhigh (Top). Split from green `b7e5f7c` on `codex/m0-accessibility-top` after the bounded Standard attempts. Failed candidate `97a1577` remains preserved on `codex/m0-accessibility-audit`; it was not merged or cherry-picked wholesale. This is an author self-check, not an independent review or M0 acceptance.

Authority: root AGENTS, §5 design-system touch/accessibility passages (05-ds:190/194/294), 19-qa:13, and SwiftUI expert skill's latest-API/accessibility references. Read the five root `run4-accessibility-*` logs and inspected the actual initial row and natural-system home/settings/failure images, exporting the latter from the existing xcresult without controlling the simulator.

## Evidence-led scope

- Initial Fajr semantic row failed native hit-region audit. An outside 44pt frame alone still failed; the rectangular row content shape moved that first finding to contrast. Reserve a 44pt row in layout plus its rectangular focus region, retaining the Arabic label/unique ID and read-only behavior.
- All-issues log reports reset's actual native button node height **17.7pt**, despite its outer frame. Move minimum 44×44 and content shape inside the button label. Hide the purely decorative preview/magnifier symbols; the full search field name supplies the meaning.
- Natural-system audit reports the long search placeholder may clip at larger sizes. Keep the native single-line TextField and its full accessible name, use the visible short prompt «ابحث» and approved `ink2` instead of the stock pale placeholder. No query behavior/data/default changes.
- The fine preview label already used a Dynamic Type-aware custom font relative to caption2; the native result was **partially unsupported**, not proof that all scaling failed. Assign this small heading the existing caption role and header trait, and add explicit height-growth assertions at L/AX3/AX5. No token or global font change; actual runtime growth remains to be verified.
- Inherited native edge fading reduced legibility in the all-issues captures. The known narrow edge-effect modifier is retained on the two scroll views, while native glass tabs/minimization stay in place. It did **not** resolve home footer contrast in the previous natural-system run: those labels were at y840/869 on an 874pt viewport, physically under the floating bar/edge. The new audit scrolls the footer fully into the measured viewport first, rather than treating that clipped observation as whole-screen contrast proof.

The previous natural-system run had **8 failures / TEST FAILED**. Its settings contrast issue had `element=nil` and a blank attachment; its origin is unresolved. The new prompt is a legibility repair, not a claim that it explains that unidentified issue. Every issue in the new `.all` audit still returns **false**, including clipped, occluded and nil-element issues; detailed description, frame and viewport membership are logged. No issue allowlist or expected-failure masking is used.

## Regressions for root

- `FoundationUITests/test_M0T12_FocusBoundsAndSearchAtDefaultAX3AX5AndDark`: measure native Fajr/reset bounds, read-only semantics, hidden preview decoration, short/full search names, heading growth; four fixture variants and retained screenshots.
- `FoundationUITests/test_M0T12_FoundationAndSettingsAccessibilityAudit`: system-driven `.all` audit under light/dark, no `MADAR_UI_SIZE` override. Expose home footer above the native bar, then audit settings. Every issue remains a failure. Scope is these settled screen states, not a proof of every scroll position or spoken VoiceOver journey.

## Actual self-check output

```text
xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/madar-t12-top-derived CODE_SIGNING_ALLOWED=NO build-for-testing
** TEST BUILD SUCCEEDED **
(exit 0; /tmp/madar-t12-top-build.log)
python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
python3 Madar/scripts/check-number-separators.py
PASS: RU1 app numeric separator source check
git diff --check
(exit 0, no output)
```

The isolated managed checkout required exact copies of the owner's existing ignored bundled fonts for compilation; no new font or licence was introduced. Only generic simulator **compilation** ran here, including the UI test target; no simulator, hosted test or UI test was executed by this author. Root must run the two targets, inspect L/AX3/AX5/dark images and classify remaining native audit results. Fresh independent review is required before merge. Nil-element/edge measurement limits, VoiceOver, Reduce Motion and physical iPhone acceptance remain explicitly open.

## Root runtime checkpoint — still not accepted

Independent narrow source review851c6cd approves d3fc0cc; integrated56ab32a on the root candidate has signed simulator runtime evidence. run4-accessibility-top-integrated:2tests/2failures45.684s / TEST FAILED. Geometry first stopped at43.99999999999994<44.0 (floating-point representation); system-driven .all separately failed Contrast failed for SwiftUI.AccessibilityNode with frame=nil/element=nil. The audit handler still suppresses nothing. Earlier run4-accessibility-top compile failure was a root merge-conflict assembly mistake; no runtime occurred in that command.

Test-only repairc273bc4 uses1e-9pt tolerance on native44pt assertions, far below a display pixel; no production or audit change. run4-focus-rounding:1test,0failures73.402s / TEST SUCCEEDED, acrossL/AX3/AX5/light andL/dark; all8actual prayer/search screenshots inspected at root (manifest run4-focus-rounding-images). Reset bounds, search prompt/accessibility name and preview height growth passed. Clipped offscreen content in a scroll viewport is not a full-layout acceptance claim. No second .all run was needed for a test-only precision edit: the unresolved nil-element contrast failure remains open. Candidate stays offmain; do not manufacture global accessibility approval.
