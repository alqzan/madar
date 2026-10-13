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
| M1-V02 | S2 Light log | `salah/02-S2-Log.jpg`, `-s1` | `PrayerTodayLogSheet` | matched — awaiting owner | Heart question unless on (RP6). Friday noon records `fridayKind` explicitly (RP5). Sample times. «امسح التسجيل» (screenshot only: no clear command in the spec, and a tombstone would block logging again; see DECISIONS). | Room-styled sheet: lattice-arch thumbnail, «صلّيتَ العصر؟», one tap on «في جماعة / وحدي / قضاءً» records, inline heart row (only when `salah.askHeart`), Friday kind chips. «فاتتني» opens the make-up panel (S2b look) in the same sheet. Compare page: `Madar/Artifacts/compare/S2-Log.html`. Differences: iOS 26 floating sheet; only the states allowed by RP2 show (canonical shows all four on Asr before its window ends). |
| M1-V03 | S2b Missed and reminder | `salah/03-S2b-Missed.jpg`, `-s1` | `PrayerMakeUpSheet`, `PrayerGapResolutionSheet` | matched — awaiting owner | «فاتتني… نزلت في القضاء» before the prayer's window ends (RP2: before the end only «لم أصلّها بعد» or snooze). «فاتتني» in the +30 notification (RP2). Automatic aging (RP1). | Gap sheet «صلوات بلا تسجيل» rebuilt at the owner's request (room look, one-tap settle, by day, partial save). The S2b panel lives in the log sheet (M1-V02): «فاتتني» shows «نزلت في القضاء…», the citation bar, «قضيتُها الآن» / «لاحقًا» and saves nothing until a choice. The +30 notification has only the snooze action (no «فاتتني», RP2). Compare page: `Madar/Artifacts/compare/S2b-Missed.html`. Difference: the canonical shows the panel on Asr before its window ends, which RP2 forbids. |
| M1-V04 | S3 Hali | `salah/04-S3-Hali.jpg`, `-s1` | `PrayerStatisticsView` | matched — awaiting owner | Any ranking or superlative such as «أخشعُ صلواتك…» (RP6). Sample numbers. Balance-style picker (`salah.balanceView` is v2: beads only). | «حالي» rebuilt: back row «‹ الصلاة» and serif title, three figure cards with the Arabic plural («٠ أيام»، «يومان»), Mizan card (bead arc with thread, ratio over the last 25, «أوفيت · معلّقة», «الأقدم / الأحدث», «آخر ٢٥ فرضًا»), month card with a five-bead arch glyph per day and today highlighted, commitment bars with percentages and legend, heart card only when `salah.askHeart`. Compare page: `Madar/Artifacts/compare/S3-Hali.html`. Differences: sheet presentation instead of a pushed page; the «قُضيت ٢، عليك ٢» line is kept under the figures (spec text, not in the canonical); days before tracking start show faded. |
| M1-V05 | S4 Edit a past day | `salah/05-S4-Day.jpg`, `-s1` | day edit in `PrayerStatisticsView` (T05) | matched — awaiting owner | Sample data. | Day sheet over «حالي»: serif date, «٤ من ٥ جماعة», five rows with one-tap pills, the pending footer worded per RP1 (the canonical «ثم تُحسب فائتة» is not copied). Tapping a month day opens it; edits show in the figures at once; the prayer name opens the full log sheet (heart, Friday kind). Friday noon pills other than «وحدي» open the full sheet for its kind (RP5). Compare page: `Madar/Artifacts/compare/S4-Day.html`. Differences: unavailable states (RP2) are left out rather than disabled, so some rows have three pills. |
| M1-V06 | S5 Qada | `salah/06-S5-Qada.jpg`, `-s1` | `PrayerQadaListSheet`, `PrayerMakeUpSheet` | matched — awaiting owner | Counts outside the app unless opted in (RP9). Sample counts. | Not merged: the candidate branch `codex/m1-s4-prayer-settings-debt` (`c9bd527`) is superseded. Its grey full-history list was replaced by this sheet; its first-calendar qada dates and its T10 test (choose a specific qada, make it up, undo) were ported (T10 now `test_M1V06_QadaSheetChoosesSpecificPrayerAndUndoes`, default size). «الفوائت والقضاء»: big count with the plural phrase, cited text with its bar, every recorded qada oldest first (touch one to choose it), «اقضِ واحدة» and «أضِف فائتة قديمة»; the confirm step is a room sheet (Friday kind chips, RP5). Dates are words («الثلاثاء ٢٥ ربيع الآخر»), never ISO. Compare page: `Madar/Artifacts/compare/S5-Qada.html`. Differences: the count phrase is the home wording («فائتتان عليك، لم تُقضيا بعد»), no «فوائت أقدم» summary row (every item is listed instead). |
| M1-V07 | S6 Qiyam | `salah/07-S6-Qiyam.jpg`, `-s1` | `PrayerNightLoggingSheet` | matched — awaiting owner | Streak wording for qiyam (it is a footprint, not a streak). Sample rakaat. Differences: no «ورد القيام من محفوظك» row (Quran room not built); explicit save button and night picker kept; the night picker shows the older date title with ISO digits; the footprint strip is empty in the fixture.| 0...99 rakaat and witr already work (T07). |
| M1-V08 | S7 Night (dark) | `salah/08-S7-Night.jpg`, `-s1` | home after Isha | matched — awaiting owner | Day/night buttons (prototype only). Differences: no heart card (RP6: off by default); pending notice reads «تبقى معلّقة حتى تختار حالها» (RP1); figures come from the test fixture; the active arch uses the same shape as the light home. Compare page: `Madar/Artifacts/compare/S7-Night.html`.| Dark canonical: compare in dark mode. Night ordering puts qiyam near the top. |
| M1-V09 | S11 Mizan (beads) | `salah/12-S11-Mizan.jpg`, `-s1` | Hali beads | matched — awaiting owner | The style picker (v2). Built in M1-V04: variant A is the Mizan card in «حالي» (`Madar/Artifacts/m1-gap-shots/M1-V04-hali-L.png`, compare page `S3-Hali.html`). Variants B and C and the «أضف فائتة / أعِد» controls of the style picker are not built (v2). Differences: the arc here is wider and the centre figure follows the spec ratio over the last 25, not the sample 96%.| Beads view only. |
| M1-V10 | Customize prayer | `flex/06-K-Salah.jpg`, `-s1`; order and hide per `flex/12-Tahrir.jpg` | `App/PrayerSettingsView.swift` | matched — awaiting owner | v2 or deferred keys (see `settings-schema.json` `availability`). Hijri-offset stepper unless sighting is chosen (RL10). Built: `App/PrayerCustomizeView.swift` (room look; entry = sliders button on the home header), `salah.layout` order/hide wired in `PrayerTodayView`; the two shipping-check FAILs cleared (checker now knows the `map` and `time` controls). Differences: «الصلاة القادمة»/«الرواق» are fixed at the top with no arrows (DECISIONS); the mini phone is shape-only (11 pt minimum); the «رتّب» mode on the home itself (`flex/12-Tahrir`) is not built; `salah.pool`, `salah.fridayTallArch`, `salah.pendingDays`, `salah.qadaReminder` are not wired, so not shown. Old `PrayerSettingsView` kept unused. Compare page: `Madar/Artifacts/compare/K-Salah.html`.| `salah.layout` (block order and hide) is v1 and not wired in `PrayerTodayView` yet. Clear the shipping-check FAILs for `salah.offsets` and `notif.quietFrom`. |

## Section M1-F — prayer features not built yet (after M1-V)

| Card | Result | Canonical / spec | Status | Notes |
|---|---|---|---|---|
| M1-F01 | Friday screen with explicit Jumu'ah/Dhuhr choice and the tall Friday arch | `salah/09-S8-Friday.jpg`, `-s1`; RP5 | matched — awaiting owner | `fridayKind` is already stored (T01). `salah.fridayTallArch` default true. Built: the «جمعة مباركة» pill (no «الكهف في قسم القرآن» pointer: no entry to the Quran room yet), tall dome «الجمعة» arch, and the explicit Jumu'ah/Dhuhr choice in the log and make-up sheets (V02, V06). Fixture `homeShowcaseFriday` (UI-test only). Differences: the pill is narrower than the canonical (shorter text); pending notice comes from the fixture. Compare page: `Madar/Artifacts/compare/S8-Friday.html`.|
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

## Handover — M1-F01 Friday home — 2026-10-13 — claude

Works now: on a Friday the home shows «جمعة مباركة» and the tall dome «الجمعة» arch; the Jumu'ah/Dhuhr choice was already in the log and make-up sheets.
Verified: UI test F01 (Friday 2026-10-09 fixture) passed at default size; screenshots `Madar/Artifacts/m1-gap-shots/M1-F01-friday-L.png` and `-scrolled-L.png`.
Differences left: see the board row.
Not verified: owner iPhone; a Friday in a travel city; the Friday log flow on this fixture.
Next: M1-F02 (travel), M1-F03 (tracking start), M1-F04 (outside the app).
Model/effort: Claude Sonnet 5.5; effort not exposed. Usage: not exposed.

## Handover — M1-V10 customize prayer — 2026-10-13 — claude

Works now: sliders button on the prayer home opens «خصّص الصلاة» (live preview, search, order and hide of home blocks, collapsible groups for the wired settings); order and hide change the home at once, and reset restores the defaults.
Verified: UI test V10 (reorder qiyam, hide Hali, home follows) and V01/V07/V08 passed at default size; `check-shipping-sources.py` now ends `STATIC PASS`; screenshots `Madar/Artifacts/m1-gap-shots/M1-V10-*.png`.
Differences left: see the board row.
Not verified: owner iPhone; relaunch persistence of the layout; the notification-permission card inside the reminders group.
Next: M1-V11 or the next `ready` card on the board.
Model/effort: Claude Sonnet 5.5; effort not exposed. Usage: not exposed.

## Handover — M1-V09 Mizan beads — 2026-10-13 — claude

Works now: the beads Mizan (variant A of S11) is the card in «حالي», built in M1-V04; no code change.
Verified: no new run; V04 test and screenshot from the earlier commit are the evidence.
Differences left: see the board row.
Not verified: owner iPhone.
Next: M1-V10 (customize prayer, `flex/06-K-Salah`).
Model/effort: Claude Sonnet 5.5; effort not exposed. Usage: not exposed.

Earlier handovers: `docs/archive/PROGRESS-2026-10-13.md`.
