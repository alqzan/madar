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
