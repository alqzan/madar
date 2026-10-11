# M0-T10 — Today prayer clocks

Codex Sol, Standard high, 2026-10-11. Branch `m0-s2-foundation-times`, base `451289e`. Authority: RA3 and the claimed T10 card. Applied the SwiftUI Expert skill for native layout, Dynamic Type and accessibility. This is a task self-check, not a section review or milestone gate.

The foundation now displays the five prayer names and today's calculated clocks for the active place's Gregorian civil day. Its native card uses the existing room typography/colours, Arabic RTL and selected Arabic-Indic/western numerals; each clock is isolated for bidi layout. At accessibility sizes each row stacks its name and time, with a single Arabic VoiceOver label. No prayer-room route, logging, sunrise addition or notification was added. A failed calculation retains the existing unavailable warning and shows no fabricated rows.

Calculation uses the stored method, Asr convention, high-latitude rule, per-prayer offsets and Hijri options. Each Timeline evaluation calculates today once and yesterday once, then reuses them for the existing date headers and unavailable state. Changes in day/place/settings redraw the presentation; no stored day key or model is changed.

Verified:

```text
xcodebuild -project Madar/Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath Madar/DerivedData CODE_SIGNING_ALLOWED=NO build-for-testing
** TEST BUILD SUCCEEDED **
python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
python3 Madar/scripts/check-number-separators.py
PASS: RU1 app numeric separator source check
git diff --check
(no output)
```

Raw build log: candidate `Madar/Artifacts/M0-T10-build-for-testing.log` (ignored evidence, also `/tmp/madar-m0t10-build.log`). Both simulator architectures and test bundles compiled. The only build warning is inherited AppIntents metadata extraction being skipped for a target without that dependency.

Not executed here: host/UI tests, simulator interaction/screenshots, VoiceOver interaction, physical iPhone or full M0 gate. Root owns the simulator.

For root validation:

- `AppServiceIntegrationTests/test_M0T10_FoundationPrayerClocksUseGoldenDayNumeralsAndZone`: fixed approved Riyadh 2026-10-09 clocks, both numeral styles, local-day selection across UTC midnight, explicit UTC display conversion and a five-minute Fajr offset. Expected clocks are copied from the existing handoff fixture, not engine output.
- `AppServiceIntegrationTests/test_M0T10_UnavailablePrayerClocksNeverFabricateRows`: polar no-result case has no clock rows.
- `FoundationUITests/test_M0T10_TodayPrayerTimesAtDefaultAX3AX5AndDark`: fresh synthetic stores, L/light, AX3/light, AX5/light and L/dark; each semantic prayer row has an Arabic name and clock, remains read-only, and first/last rows produce retained screenshot attachments.

Fresh independent Standard section review and root runtime/visual checks are required before merge. RA7's official independent timetable fixtures remain M1 work. Owner-iPhone shell/today-times acceptance remains untested. Root owns PROGRESS/main handover; this branch contains only the task and this report.

Root validation follow-up: root reports 20 host tests passed with zero failures. The first UI run failed while waiting for the first offscreen row before scrolling; its initial accessibility hierarchy contained the header and introduction only. A separate test-only repair now waits for the existing ScrollView and swipes that container up, at most 12 times per row, until the row exists and is hittable before checking its label. `git diff --check` passed with no output. The repaired UI runtime and screenshot checks remain pending root's retry; no production code changed in this repair.
