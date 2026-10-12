# M0-T09 — actual system AX3 privacy cover

**Verdict: approve — bounded test-navigation repair and native system-AX3/light cover/readability result. No findings.**

12 October 2026 — independent review of the new `07d2ada..70939f5` test-only delta and new native evidence on `codex/m0-t09-system-ax3-navigation`. Authority: `14-shared.md` §8.10, the presentation-privacy design and current system-AX3 acceptance claim. Prior SwiftUI-only AX3 evidence did not establish UIKit/system scaling; this actual OS configuration supplied new evidence. No prior accepted source was reviewed again. This reviewer started no build or simulator run.

## Diagnosed failure and source repair

The first actual system-AX3 attempt at `07d2ada` reached genuine Face ID success and native archive sharing, then failed the Save to Files discovery assertion at `FoundationUITests.swift:362`: 1 test, 1 failure in 41.843s. Its native hierarchy exposes `ActivityListView` with `actionGroupCell` labelled **عرض المزيد**, while the Files row is not exposed. It never reached a switcher gesture/capture. The driver later timed out after 240s with exit 1; the partial xcresult and raw failure remain in `run-07d2ada-switcher-system-ax3-light/`. This was not evidence of a production cover defect.

The independently approved one-file repair retains the original ten-second Files wait. Only if Files is absent does it require one exact, unique, hittable native More cell, tap it once, capture before/after OS images and native hierarchies, then require the actual Files row. Authentication, full-card assertions, driver and production code are unchanged. `git diff --check 07d2ada..70939f5` passed. One diagnosed retry followed; earlier passing configurations were not repeated.

## Actual native result and restored setup

Raw evidence is retained under `Madar/Artifacts/t09-native-retirement-2026-10-12/run-70939f5-switcher-system-ax3-light/` (ignored), including setup/restore commands and readbacks, command/log/match JSON, xcresult and nine attachments. Independently inspected those outputs, all five original PNGs and the relevant four native hierarchies. Device: iPhone 17 Pro simulator `412F4437-7BD7-44D1-AA3D-2B7158090E14`, iOS 26.5 (`23F77`).

`setup-run-and-restore.json` records successful raw queries: original `content_size=large`, `appearance=light`; during the run `content_size=accessibility-extra-large`, `appearance=light`; after restoration `content_size=large`, `appearance=light`. Every setup/restore/query exits 0. Font preflight reports 11 matching resources, 0 copied. Native biometric JSON records a real simulated successful match; driver exits 0.

The pre-disclosure image/hierarchy shows the enlarged native More affordance. After its exact tap, `E111CAD7-7AA4-488D-8C46-170A445AA721.txt` exposes **حفظ في الملفات** at `(16, 578, 370, 87)`; the post-disclosure and authorized-share images show that native action and archive header.

Centered PNG `82774C13-1765-4F22-B596-845472B9F124.png` and hierarchy `F4B7D74E-A4F9-443B-9995-D3FE93BB9E44.txt` identify the full exact `com.alqzan.madar2` card, scene `D0D58FA5-1BB2-49A3-B7A3-78B83463F078`, frame `(63.3125, 128.9828, 275.3751, 598.7010)` inside the `402 × 874` screen. After one target-directed pan, the complete card has an opaque white cover. The lock and Arabic **محتوى مدار محمي** / **افتح القفل** are visibly enlarged, readable, separated and unclipped. No archive, underlying Settings, share controls or protected content is visible. The cropped immediate image is supplemental only.

```text
Executed 1 test, with 0 failures (0 unexpected) in 53.810 (53.811) seconds
** TEST SUCCEEDED **
```

## Boundary

Accepted: actual system AX3/light privacy cover/readability and native Files-affordance discovery after explicit disclosure. This does not prove spoken VoiceOver, AX5, other rooms' accessibility, the precise synchronous inactive boundary, true two-scene behavior, Files destination writes, physical owner-iPhone acceptance or full T09/integration/M0 approval. Prior accepted results retain their separate limits.
