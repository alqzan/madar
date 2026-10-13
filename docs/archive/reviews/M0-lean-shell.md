# M0-S2 lean shell — M0-T04

Verdict: **approve — scoped M0-T04 UI changes**.

Reviewed production commit `137afc0` and focused regression tests `8cc230f` on `m0-s2-lean-shell`, against `main` (`0a31987`). This is a scoped review of the changed production code in `AppSession.swift`, `CustomizeMadar.swift`, and `TabShell.swift`; it is not acceptance of all inherited M0 code or the milestone gate.

## Static review

No newly introduced static findings.

- `Madar/App/AppSession.swift:36` removes the RA8 cut keys from the supported settings and settings-route allowlist.
- `Madar/App/CustomizeMadar.swift:61` retains only backup navigation; saved presets and cloud sync have no entry point in this view. Search, counts and resets use the supported-key set.
- `Madar/App/TabShell.swift:19` uses only the native `TabView`; `:26` fixes minimize-on-scroll to the agreed `true` default. `:40` exposes only the built foundation and customization destinations.
- `Madar/App/TabShell.swift:39`, `:79`, and `:91` ignore previously stored cut appearance values and use the agreed per-room identity, full motion with system Reduce Motion honored, and system Dynamic Type defaults.
- The host app supplies Arabic locale and RTL. All three working schema copies already mark the cut keys `availability: v2` and agree on the defaults (`glass`, `all`, `bahw`, `true`, `system`, `full`, `perRoom`), so this commit does not need a schema edit.

Read the task card, RA3/RA8/RL8/RU1/RU3, and the relevant navigation/customization/M0 text in `04-arch`, `06-flex`, `09-r-salah`, and `18-plan`. The fixes override the original multi-style/preset/customization content.

## Runtime and visual evidence

The coordinator ran the simulator on the reviewed branch. This reviewer inspected its actual artifacts; the reviewer did not independently operate the simulator. `Madar/Artifacts/automation-shell-review.log` ends with `Executed 3 tests, with 0 failures (0 unexpected) in 115.800 (115.803) seconds` and `** TEST SUCCEEDED **`. The tests cover first-run/settings, light/dark at L/AX3/AX5, and theme persistence/reset/undo.

Viewed the L and AX3 home/settings in light, L home/settings in dark, and AX3 settings in dark. The mapped screenshots are under `Madar/Artifacts/automation-shell-images/` (see `manifest.json`): light settings `3657C49C-9B78-4EEF-8628-326AA373D589.png`, light AX3 settings `DD9CED89-B243-44C9-A6AC-330B4CEF899C.png`, dark settings `904DD25B-358E-4103-BCCA-1B4C7B4E5873.png`, dark AX3 settings `715FB987-5764-4687-8E9B-2AE18EC26972.png`, and the corresponding home captures `939D0152-4880-4F3A-8A98-ABB025A30815.png`, `C634936D-E3F0-46CC-A199-199D1868F22E.png`, `C8AAD60B-6861-42AB-BB9A-6B0CD22C2AE1.png`.

Compared the surviving settings layout with `docs/HANDOFF/screens/flex/01-Main.jpg` and the bar with `docs/HANDOFF/screens/flex/03-Tab-A.jpg`. RA3/RA8 justify removing the mock rooms/presets/cut controls; those removed mock elements are not a visual mismatch. RTL, Arabic-Indic digits, serif headings, paper/card tone, and native bar selection are present. The AX3 preview changes to a readable vertical list without visible clipping. Dark is derived from the agreed tokens; there is no dark canonical screenshot for these screens. No newly introduced visual finding in the inspected images. `02-Sharit-s2.jpg` is a scroll continuation of the cut tab settings, not the glass-bar visual.

Added two narrowly scoped tests at the coordinator's request: `test_M0S2_CutSettingsAndDeferredEntryPointsStayHidden` checks every cut-key/preset/sync query with a shipped-theme positive control and captures before/after-scroll images; `test_M0S2_LegacyCutSettingsRemainStoredWithoutAvailableRoutes` preserves nondefault legacy rows while refusing their routes. `Madar/Artifacts/automation-shell-availability.log` shows the integration test passed (1 test, 0 failures, 0.117 seconds) and the UI test passed (1 test, 0 failures, 138.478 seconds), ending `** TEST SUCCEEDED **`. Preservation of legacy data is intentional; this review does not claim session values are rewritten to defaults.

Viewed `Madar/Artifacts/automation-shell-availability-images/48871359-8850-40FD-8E84-ABDACA0E73DE.png` (before) and `5B19E51C-D5E8-425F-AFB0-945D0436C5B4.png` (after). The native bar changes from two labeled destinations to the compact selected-tab circle after scrolling; minimization is visually verified. This is an image comparison, not an asserted public XCTest minimization property.

Not tested by this scoped review: physical iPhone, VoiceOver interaction, runtime presentation of a simulator app seeded with legacy cut values, or the whole M0 gate. Fixed presentation independent of those stored values is established by the changed view code; preservation and route exclusion have an executed integration regression.

## Outside this change

`Madar/App/CustomizeMadar.swift:84` still builds the count phrase by interpolation instead of String Catalog plural variants (RU3). This is unchanged in `137afc0` and is a previous-session issue, not a finding introduced by this diff. Fix it in a separate scoped `[fix-previous]` task. The unbuilt prayer room's RU1 issue is also outside this three-file diff.
