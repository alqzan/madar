# Madar reliability checklist

Run an item only when its trigger matches the diff. Each row names the incident or rule behind it. Add a row when a failure recurs; prune rows for removed features.

| # | Trigger in the diff | Check | Behind it |
|---|---|---|---|
| 1 | A new or changed scheduled time (notification, reminder, alert) | It passes through `SanctityGuard` (RP3); nothing fires from adhan to adhan +30 (Maghrib +20) | Prayer sanctity rule |
| 2 | A date shown to the user | Both calendars appear; primary follows `core.firstCalendar` (diary calendar: `notes.calendarFirst`) | Owner 15 Oct |
| 3 | A digit next to a separator in copy | `python3 Madar/scripts/check-number-separators.py`; no middle dot next to a digit | RU1 |
| 4 | A SwiftData model, migration, delete or purge | Tombstone with `deletedAt` + `deletionBarrierAt`, monotonic `updatedAt`, `writerID`; idempotent on a second run; test on a synthetic store | Persistence rules; 17 Nov prayer purge |
| 5 | `dayKey`, day boundary, prayer-day grouping | A stored `dayKey` is never recomputed; `core.dayStart` respected | Day boundary rule |
| 6 | Money amounts or the money engine | `Int` minor units; focused review before screens build on it | Money rule |
| 7 | A streak | Derived, never stored; longest kept after a break | Streak rule |
| 8 | A new entry point, button or option | Feature is v1; no disabled button or «قريبًا»; no entry point to a removed room | Availability rule |
| 9 | A new setting key | Default from `settings-schema.json`, reset, undo; listed in `supportedKeys` | Settings rule |
| 10 | Text under 24 pt, a colour pair | `*Text` colour variant; pair listed in `contrast.pairs`; ≥ 11 pt | Contrast rule |
| 11 | A custom drawing | List alternative from AX1 up | Dynamic Type rule |
| 12 | A widget or extension reading data | Reads JSON snapshots only; only the app opens the store | RA2 |
| 13 | `project.yml` targets, embedded apps or extensions | Release archive `Products/Applications` holds only `Madar.app`; embedded targets use `SKIP_INSTALL: YES` | 17 Nov: watch app archived as a second app, export failed («method» had no options) |
| 14 | `CURRENT_PROJECT_VERSION` or an upload | The number has no «Upload succeeded» in any `Madar/Artifacts/*TestFlight*/upload.log`; one upload per request | ITMS-90189, 10 Nov |
| 15 | Copy the user reads | Arabic, RTL; concrete amounts instead of multipliers; no repeated sentence on one screen | Owner UX rules |
| 16 | Removing a feature | Delete its tests (no `XCTSkip`), its entry points, settings keys, widgets, intents and feature-map rows in the same request | Verification practice, 17 Nov |
| 17 | Undo toast or its timing | Short, swipe-away, not repeated | Owner remarks (undo toast) |
| 18 | A fixed money limit changes to a percentage | Run `MoneyCategoriesUITests.testPercentLimitDisplaysHundredths`. A 4,000 limit on 15,000 income displays 26.66%. | Build 60 rounded a recurring decimal ratio to 0.01% on the simulator |
| 19 | Running UI tests (`build-for-testing` / `test-without-building`) | Build them ad-hoc signed: `CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES` (as `make test` and `verify-smoke.sh` do). In zsh pass a list of `-only-testing` flags as `${=LIST}`. | 22 Nov: an unsigned test build dropped the App Group, so all 39 lobby/habits UI tests opened on «تعذّر فتح مدار»; an unsplit zsh variable then ran zero tests |
| 20 | A UI test taps right after launch, a scroll, or a sheet closing, then types or taps again | Wait for the real ready state before acting: the store's content (a label that only loaded data shows), `isHittable`, or `app.keyboards.firstMatch` before `typeText`. Retry a tap once only when that ready signal did not appear. Never use sleeps. | 22–23 Nov: the lobby travel pill's first tap was dropped by iOS while the store was still loading and after a sheet closed; stale Foundation tests then tapped a scrolled-away search field |
| 21 | A UI test saves something (an expense, a plan, a rate, a setting) and then looks for «تراجع» / `undo-button` | FB-32 (owner, 5 Nov): only deletes and the page or global reset offer undo. After a save assert the undo is absent (`XCTAssertFalse(… .waitForExistence(timeout: 2))`) and check the saved result; reverse it through the same control when the test needs the old state. | 22–23 Nov: eleven money and foundation UI tests still waited for an undo after a save and failed |
| 22 | A `.sheet`/`.fullScreenCover` shows optional state, or a link/`openURL` action runs inside a sheet | Present from the optional itself (`item:` or `Binding(get: { x != nil } …)`), never a separate flag whose content reads a state `body` does not; set `openURL` on the `NavigationStack` (pushed pages take the stack's environment), and present another cover only after the sheet's `onDismiss`. Drive the flow by hand once. | 23 Nov: the trip reprice preview opened empty; the gallery's «مصروف» control opened the money room but iOS dropped the expense cover |
| 23 | Code adds or moves an error `.alert` bound to `session.errorMessage` (root, a room, a sheet or a cover) | Use `madarSheetErrorAlert(session)` on every sheet or cover so only the newest host on screen presents (`session.sheetErrorHosts`); the root alert stays quiet while any host is up. Check the flow with an injected error while a nested sheet or the Mihbara reader is open: the inner sheet must stay. | 23 Nov: with the Mihbara as a tab, a reading save error raised the root alert too and pushed the reader cover away, so the reader closed instead of offering a retry (`MihbaraHomeUITests` EPUB save-error test). |
