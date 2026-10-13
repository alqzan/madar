# Current milestone

**M1 Prayer: make the built screens match the approved design, then build what is missing.** Protocol: root `AGENTS.md` (owner revision, 13 October 2026). Full M0 and M1 are **not approved**: owner-iPhone acceptance and distribution are still not tested. RA1 (local only), RA2 (app-only store writes), RP1 (no automatic missed/qada), RU1 and data preservation stay mandatory.

# Last checked

2026-10-13, claude (Opus 5.5; effort not exposed). M1-V01 done on main. Owner decisions today: no enlarged-text (AX) testing, no reviews except a data-migration change; the script checks run only at a milestone gate. Known `check-shipping-sources.py` FAILs: `salah.offsets`, `notif.quietFrom` (M1-V10). `make build` fixed: the widget target now takes its sources from `project.yml`. Unmerged candidate: `codex/m1-s4-prayer-settings-debt` at `c9bd527`.

# Board

Status values: `ready` · `in progress` · `blocked: <reason>` · `matched — awaiting owner` · `approved` (owner only) · `done` (engines and flows without a screen).

Every screen card follows protocol §2: canonical files → default-size screenshots → `python3 Madar/scripts/compare-screens.py <board> <shots>` → fix → `matched — awaiting owner` (default text size only; no enlarged-text testing, owner 13 October 2026). Spec for every prayer card: §7.2 `docs/HANDOFF/sections/09-r-salah.md` (the part for that screen), §5 shapes `05-ds.md`, and the fixes listed.

## Section M1-V — prayer screens match the design (do in this order)

| Card | Screen | Canonical | Current code | Status | Do not copy (fixes and defaults win) | Notes |
|---|---|---|---|---|---|---|
| M1-V01 | S1 Home | `salah/01-S1-Home.jpg`, `-s1` | `App/PrayerTodayView.swift` | matched — awaiting owner | Moon day/night button (prototype only). «تبقى معلّقة ٦ أيام ثم تُحسب فائتة» (RP1). Heart labels (RP6). Heart card unless `salah.askHeart`. "·" next to a digit (RU1). Sample numbers. | Salah palette, lattice arches with reflection pool, verse divider, pending notice, Hali card with beads, qada card with citation and «مواضعها» list, qiyam footprint, spec date and RL7 countdown, plurals via `Prayer.xcstrings` (RU3). Compare page: `Madar/Artifacts/compare/S1-Home.html`. Open question: future/next arches show a line (spec text) where the canonical image shows stars. |
| M1-V02 | S2 Light log | `salah/02-S2-Log.jpg`, `-s1` | `PrayerTodayLogSheet` | ready | Heart question unless on (RP6). Friday noon records `fridayKind` explicitly (RP5). Sample times. | Must be a room-styled sheet, not a grey system form. |
| M1-V03 | S2b Missed and reminder | `salah/03-S2b-Missed.jpg`, `-s1` | `PrayerMakeUpSheet`, `PrayerGapResolutionSheet` | ready | «فاتتني… نزلت في القضاء» before the prayer's window ends (RP2: before the end only «لم أصلّها بعد» or snooze). «فاتتني» in the +30 notification (RP2). Automatic aging (RP1). | Gap sheet «صلوات بلا تسجيل» rebuilt at the owner's request (room look, one-tap settle, by day, partial save). Still to match: the S2b log/missed sheet. |
| M1-V04 | S3 Hali | `salah/04-S3-Hali.jpg`, `-s1` | `PrayerStatisticsView` | ready | Any ranking or superlative such as «أخشعُ صلواتك…» (RP6). Sample numbers. Balance-style picker (`salah.balanceView` is v2: beads only). | Seen defects: title shown twice; «٠ أيام» needs the Arabic plural rule (RU3); month grid lacks each day's bead glyph; Mizan card lacks «الأحدث / الأقدم» labels and the «آخر ٢٥ فرضًا» header. |
| M1-V05 | S4 Edit a past day | `salah/05-S4-Day.jpg`, `-s1` | day edit in `PrayerStatisticsView` (T05) | ready | Sample data. | A stored `dayKey` is never recomputed. |
| M1-V06 | S5 Qada | `salah/06-S5-Qada.jpg`, `-s1` | `codex/m1-s4-prayer-settings-debt` `c9bd527` | ready | Counts outside the app unless opted in (RP9). Sample counts. | First rerun the candidate's T10 UI test and merge it only if green, then match the design. Dates follow `core.firstCalendar`. |
| M1-V07 | S6 Qiyam | `salah/07-S6-Qiyam.jpg`, `-s1` | `PrayerNightLoggingSheet` | ready | Streak wording for qiyam (it is a footprint, not a streak). Sample rakaat. | 0...99 rakaat and witr already work (T07). |
| M1-V08 | S7 Night (dark) | `salah/08-S7-Night.jpg`, `-s1` | home after Isha | ready | Day/night buttons (prototype only). | Dark canonical: compare in dark mode. Night ordering puts qiyam near the top. |
| M1-V09 | S11 Mizan (beads) | `salah/12-S11-Mizan.jpg`, `-s1` | Hali beads | ready | The style picker (v2). | Beads view only. |
| M1-V10 | Customize prayer | `flex/06-K-Salah.jpg`, `-s1`; order and hide per `flex/12-Tahrir.jpg` | `App/PrayerSettingsView.swift` | ready | v2 or deferred keys (see `settings-schema.json` `availability`). Hijri-offset stepper unless sighting is chosen (RL10). | `salah.layout` (block order and hide) is v1 and not wired in `PrayerTodayView` yet. Clear the shipping-check FAILs for `salah.offsets` and `notif.quietFrom`. |

## Section M1-F — prayer features not built yet (after M1-V)

| Card | Result | Canonical / spec | Status | Notes |
|---|---|---|---|---|
| M1-F01 | Friday screen with explicit Jumu'ah/Dhuhr choice and the tall Friday arch | `salah/09-S8-Friday.jpg`, `-s1`; RP5 | ready after V | `fridayKind` is already stored (T01). `salah.fridayTallArch` default true. |
| M1-F02 | Travel: ask once, method per trip, shorten/combine without pre-pairing | `salah/10-S9-Travel.jpg`, `-s1`; RP4, RP7 | ready after V | Show «خارج مدينتك» until answered. Fixtures: London with MWL, Istanbul with Turkey. Needs `Trip.calcMethod` (data change → one independent review). |
| M1-F03 | Edit the tracking start date once | §7.2 P04, `salah.trackingStart` | ready after V | |
| M1-F04 | Outside the app: next-prayer widget, lock-screen widgets, countdown | `salah/11-S10-Abwab.jpg`; §9; RL7, RP9, RU2 | ready after V | Widgets read JSON snapshots only. Default shows only the next prayer and its time. |
| M1-F05 | Import the old prayer history | §7.2, `Madar/docs/MIGRATION.md` | blocked: needs the owner's go and a synthetic fixture first | Never open or migrate the owner's real store without explicit permission. |
| M1-G | M1 gate on the owner's iPhone | §12/§13 M1, `docs/reports/M1.md` | blocked: needs the owner's iPhone run | Fill the gate table only at the gate. |

S0-Jard and S12-Khulasa are explainer boards (`kind: explainer`): use them for reference, don't build them.

## Done — software (integrated on main, visual acceptance pending in M1-V)

| Card | Result | Commit |
|---|---|---|
| M0 lean | Tokens and fonts, MadarDay, Hijri, prayer times, glass shell, M1 settings and models, app-only inbox, plain export | `95804a1`, `ea3e63d`; gate table `docs/reports/M0.md` |
| M1-T01 | Today's five prayers, next prayer, log Jamaah/Alone, Friday kind, change/undo/relaunch, v3 migration | `e6fbe75` |
| M1-T02 | Explicit missed and make-up, bulk gap resolution, no automatic aging | `1697c09` |
| M1-T03 | One pure sanctity guard for every scheduled time (Friday Dhuhr and Ramadan Isha windows) | `dc4d011` |
| M1-T04 | Guarded notification scheduling, snooze, cancel on log; Live Activity start budget | `433cbf6`, `e4ecf59` |
| M1-T05 | Hali ratio, streaks, editable Hijri-month history | `7769d6d` |
| M1-T06 | Optional heart answer (default off) | `e18601c` |
| M1-T07 | Qiyam night logging | `288ef7e` |
| M1-T08 | Calculation method, Asr, high latitude, offsets | `03347b6` |
| M1-T09 | Explicit old missed prayer and restoration | `03c304e` |

## Frozen — do not work on until the owner unfreezes

M0-T06 (device acceptance paperwork), M0-T09 (encrypted backup and privacy matrix), M0-T12 (contrast inspector), app lock/Face ID, app-switcher privacy, sync. The code stays; it is not extended or re-tested. Earlier evidence: `docs/archive/reports/`, `docs/archive/reviews/`.

## Waiting on the owner

1. Approve or reject each screen marked `matched — awaiting owner`.
2. Run the app on your iPhone (steps: `docs/OWNER-RUNBOOK.md`) when M1-V is done.
3. The Codex automation now uses `docs/AUTOMATION-PROMPT.md` but is still **paused**; resume it from Codex when you want.

# Later

M1 gate, then M2 Quran, M3 Diary, M4 Lobby + Habits + Widgets, M5 Money, M6 Mihbara, M7 integration. Plan each milestone as screen cards in this same format when its turn comes; no entry point to an unbuilt room.

# Handovers

## Handover — gap sheet redesign — 2026-10-13 — claude

Works now: «صلوات بلا تسجيل» replaces the grey «مراجعة الفترة» form (room look, «صلّيتها كلها» and «لم أسجّل هذه الفترة» settle everything in one tap with undo, prayers grouped by day with «اليوم كله», save whatever is chosen). The home «سجِّلها» opens every pending prayer, not only the first. 20 merged branches deleted at the owner's go.
Verified: `test_M1T02_BulkPendingRecovery`, `test_M1T02_MissedMakeUpUndoAndRelaunch`, `test_M1V01_HomeMatchesCanonical`: passed; screenshot `Madar/Artifacts/m1-gap-shots/M1-T02-recovery-sheet-L.png`.
Not verified: owner iPhone.
Next: M1-V02, the log sheet matching `02-S2-Log.jpg`.
Model/effort: Claude Opus 5.5; effort not exposed. Usage: not exposed.

## Handover — M1-V01 prayer home — 2026-10-13 — claude

Works now: the prayer home matches `01-S1-Home` in layout, palette and wording (compare page `Madar/Artifacts/compare/S1-Home.html`); whole cards are tappable (the «أضف فائتة قديمة» card and «مواضعها» used to respond only on their text).
Verified: `PrayerCopyTests` and the prayer UI set (V01, T01, T02 ×2, T05, T07, T09: 9 passed; T04 permission passes after uninstalling the app, because the simulator keeps the earlier grant) at default size; MadarPrayer `swift test` 18/18.
Not verified: owner iPhone; enlarged text (no longer tested, owner decision).
Next: M1-V02, the log sheet matching `02-S2-Log.jpg`.
Model/effort: Claude Opus 5.5; effort not exposed. Usage: not exposed.

## Handover — repository reorganized — 2026-10-13 — claude

Works now: the app is unchanged. New protocol (visual acceptance, no report work, frozen list), this board with one card per prayer screen, `Madar/scripts/compare-screens.py`, history moved to `docs/archive/`.
Verified: `check-review-contracts.py` PASS; `python3 -m unittest discover -s Madar/scripts/tests` OK; `compare-screens.py` produced S1-Home with valid embedded images; `cmp` shows both protocol pairs identical; `git diff --check` clean.
Differences left: all prayer screens, see M1-V01…V10.
Not verified: no app build or test run (no app source changed). `check-shipping-sources.py` shows the same 3 FAILs as unchanged main (assigned to M1-V01 and M1-V10).
Next: M1-V01, the prayer home matching `01-S1-Home.jpg`.
Model/effort: Claude Opus 5.5; effort not exposed.
Usage: not exposed.

Earlier handovers: `docs/archive/PROGRESS-2026-10-13.md`.
