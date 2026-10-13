# Current milestone

**M1 Prayer: make the built screens match the approved design, then build what is missing.** Protocol: root `AGENTS.md` (owner revision, 13 October 2026). Full M0 and M1 are **not approved**: owner-iPhone acceptance and distribution are still not tested. RA1 (local only), RA2 (app-only store writes), RP1 (no automatic missed/qada), RU1 and data preservation stay mandatory.

# Last checked

2026-10-13 — Claude (Opus 5.5). S1 «حالي» streak redesigned per the owner's answer («سلسلة بسيطة عادية بالأيام، ما يحتاج تكرر»): one day streak «سلسلتك ١٢ يومًا» plus a short qualifier naming only what differs («كلها في جماعة»، «كلها في وقتها، وآخر يومين في جماعة»). The five rejected mockups and Codex's three-arch code are replaced. Codex's uncommitted F04/F05/S4/streak-engine work was checked (package tests pass) and committed with it. «سلاسلك» is now a stone arch (30 stones per layer, a month) plus a details sheet. Awaiting the owner's look.

# Board

Status values: `ready` · `in progress` · `blocked: <reason>` · `matched — awaiting owner` · `approved` (owner only) · `done` (engines and flows without a screen).

Every screen card follows protocol §2: canonical files → default-size screenshots → `python3 Madar/scripts/compare-screens.py <board> <shots>` → fix → `matched — awaiting owner` (default text size only; no enlarged-text testing, owner 13 October 2026). Spec for every prayer card: §7.2 `docs/HANDOFF/sections/09-r-salah.md` (the part for that screen), §5 shapes `05-ds.md`, and the fixes listed.

## Section M1-V — prayer screens match the design (do in this order)

| Card | Screen | Canonical | Current code | Status | Do not copy (fixes and defaults win) | Notes |
|---|---|---|---|---|---|---|
| M1-V01 | S1 Home | `salah/01-S1-Home.jpg`, `-s1` | `App/PrayerTodayView.swift` | in progress | Moon day/night button (prototype only). «تبقى معلّقة ٦ أيام ثم تُحسب فائتة» (RP1). Heart labels (RP6). Heart card unless `salah.askHeart`. "·" next to a digit (RU1). Sample numbers. The home streak meaning is three layers per owner direction; no day count. S3 Mizan beads remain. | Hali streak (owner, 13 Oct): one day count, «سلسلتك N», the completion streak; under it one qualifier that names only the part on time or in congregation (the three layers nest, so nothing repeats). Home card «سلاسلك» (owner, 13 Oct: arches, full at a month): three nested horseshoe arches in the home-arch shape (`PrayerHorseshoe`, legs to the floor, star inside) — congregation inside, on time, completion outside; each is one continuous smooth line filling right to left with the streak (up the right leg, over the crown, down to the left foot at 30 days) (gentle fill animation, none under Reduce Motion); legend beside it (name, short meaning, days); no month %. Tap opens the «سلاسلك» sheet (meaning, last seven days, the day and reason of any break) with «حالي: سجلّ الشهر» to S3. One engine definition: `PrayerStreaks`. Captures: `Madar/Artifacts/m1-streak-rtl-shots/` (fixtures `streakShowcase`, `streakShowcaseMonth`). Awaiting the owner's look. Preserve the rest of S1 scope: verse divider, pending notice, qada card with citation and «مواضعها» list, qiyam footprint, spec date and RL7 countdown, plurals via `Prayer.xcstrings` (RU3). Compare page: `Madar/Artifacts/compare/S1-Home.html`; actual L captures: `Madar/Artifacts/m1-s1-streak-shots/`. Design and visual acceptance remain open; main S1 scrolled alignment and V05 scrolled capture remain unresolved. |
| M1-V02 | S2 Light log | `salah/02-S2-Log.jpg`, `-s1` | `PrayerTodayLogSheet` | approved | Heart question unless on (RP6). Friday noon records `fridayKind` explicitly (RP5). Sample times. «امسح التسجيل» (screenshot only: no clear command in the spec, and a tombstone would block logging again; see DECISIONS). | Room-styled sheet: lattice-arch thumbnail, «صلّيتَ العصر؟», one tap on «في جماعة / وحدي / قضاءً» records, inline heart row (only when `salah.askHeart`), Friday kind chips. «فاتتني» opens the make-up panel (S2b look) in the same sheet. Compare page: `Madar/Artifacts/compare/S2-Log.html`. Differences: iOS 26 floating sheet; only the states allowed by RP2 show (canonical shows all four on Asr before its window ends). |
| M1-V03 | S2b Missed and reminder | `salah/03-S2b-Missed.jpg`, `-s1` | `PrayerMakeUpSheet`, `PrayerGapResolutionSheet` | approved | «فاتتني… نزلت في القضاء» before the prayer's window ends (RP2: before the end only «لم أصلّها بعد» or snooze). «فاتتني» in the +30 notification (RP2). Automatic aging (RP1). | Gap sheet «صلوات بلا تسجيل» rebuilt at the owner's request (room look, one-tap settle, by day, partial save). The S2b panel lives in the log sheet (M1-V02): «فاتتني» shows «نزلت في القضاء…», the citation bar, «قضيتُها الآن» / «لاحقًا» and saves nothing until a choice. The +30 notification has only the snooze action (no «فاتتني», RP2). Compare page: `Madar/Artifacts/compare/S2b-Missed.html`. Difference: the canonical shows the panel on Asr before its window ends, which RP2 forbids. |
| M1-V04 | S3 Hali | `salah/04-S3-Hali.jpg`, `-s1` | `PrayerStatisticsView` | approved | Any ranking or superlative such as «أخشعُ صلواتك…» (RP6). Sample numbers. Balance-style picker (`salah.balanceView` is v2: beads only). | «حالي» rebuilt: back row «‹ الصلاة» and serif title, three figure cards with the Arabic plural («٠ أيام»، «يومان»), Mizan card (bead arc with thread, ratio over the last 25, «أوفيت · معلّقة», «الأقدم / الأحدث», «آخر ٢٥ فرضًا»), month card with a five-bead arch glyph per day and today highlighted, commitment bars with percentages and legend, heart card only when `salah.askHeart`. The congregation streak label now says «الجماعة» per owner terminology; the detailed Mizan bead arc stays. Compare page: `Madar/Artifacts/compare/S3-Hali.html`. Differences: sheet presentation instead of a pushed page; the «قُضيت ٢، عليك ٢» line is kept under the figures (spec text, not in the canonical); days before tracking start show faded. |
| M1-V05 | S4 Edit a past day | `salah/05-S4-Day.jpg`, `-s1` | day edit in `PrayerStatisticsView` (T05) | in progress | Sample data. | Day sheet over «حالي»: serif date, «٤ من ٥ جماعة», five rows with one-tap pills, the pending footer worded per RP1 (the canonical «ثم تُحسب فائتة» is not copied). Tapping a month day opens it; edits show in the figures at once; the prayer name opens the full log sheet (heart, Friday kind). Friday noon pills other than «وحدي» open the full sheet for its kind (RP5). Compare page: `Madar/Artifacts/compare/S4-Day.html`. Existing qada stays visible. Per owner request, status pills use distinct markers/colors: Jamaah accent star, alone gold star with accent outline, qada ink2 hourglass, missed terracotta arch. Preview: `Madar/Artifacts/compare/S4-Day-state-colors.png`. Owner approved the updated qada icon on 2026-10-13; the actual scrolled `-s1` capture is still missing. |
| M1-V06 | S5 Qada | `salah/06-S5-Qada.jpg`, `-s1` | `PrayerQadaListSheet`, `PrayerMakeUpSheet` | approved | Counts outside the app unless opted in (RP9). Sample counts. | Not merged: the candidate branch `codex/m1-s4-prayer-settings-debt` (`c9bd527`) is superseded. Its grey full-history list was replaced by this sheet; its first-calendar qada dates and its T10 test (choose a specific qada, make it up, undo) were ported (T10 now `test_M1V06_QadaSheetChoosesSpecificPrayerAndUndoes`, default size). «الفوائت والقضاء»: big count with the plural phrase, cited text with its bar, every recorded qada oldest first (touch one to choose it), «اقضِ واحدة» and «أضِف فائتة قديمة»; the confirm step is a room sheet (Friday kind chips, RP5). Dates are words («الثلاثاء ٢٥ ربيع الآخر»), never ISO. Compare page: `Madar/Artifacts/compare/S5-Qada.html`. Differences: the count phrase is the home wording («فائتتان عليك، لم تُقضيا بعد»), no «فوائت أقدم» summary row (every item is listed instead). |
| M1-V07 | S6 Qiyam | `salah/07-S6-Qiyam.jpg`, `-s1` | `PrayerNightLoggingSheet` | approved | Streak wording for qiyam (it is a footprint, not a streak). Sample rakaat. Differences: no «ورد القيام من محفوظك» row (Quran room not built); explicit save button and night picker kept; the night picker shows the older date title with ISO digits; the footprint strip is empty in the fixture.| 0...99 rakaat and witr already work (T07). |
| M1-V08 | S7 Night (dark) | `salah/08-S7-Night.jpg`, `-s1` | home after Isha | approved | Day/night buttons (prototype only). Differences: no heart card (RP6: off by default); pending notice reads «تبقى معلّقة حتى تختار حالها» (RP1); figures come from the test fixture; the active arch uses the same shape as the light home. Compare page: `Madar/Artifacts/compare/S7-Night.html`.| Dark canonical: compare in dark mode. Night ordering puts qiyam near the top. |
| M1-V09 | S11 Mizan (beads) | `salah/12-S11-Mizan.jpg`, `-s1` | Hali beads | approved | The style picker (v2). Built in M1-V04: variant A is the Mizan card in «حالي» (`Madar/Artifacts/m1-gap-shots/M1-V04-hali-L.png`, compare page `S3-Hali.html`). Variants B and C and the «أضف فائتة / أعِد» controls of the style picker are not built (v2). Differences: the arc here is wider and the centre figure follows the spec ratio over the last 25, not the sample 96%.| Beads view only. |
| M1-V10 | Customize prayer | `flex/06-K-Salah.jpg`, `-s1`; order and hide per `flex/12-Tahrir.jpg` | `App/PrayerSettingsView.swift` | approved | v2 or deferred keys (see `settings-schema.json` `availability`). Hijri-offset stepper unless sighting is chosen (RL10). Built: `App/PrayerCustomizeView.swift` (room look; entry = sliders button on the home header), `salah.layout` order/hide wired in `PrayerTodayView`; the two shipping-check FAILs cleared (checker now knows the `map` and `time` controls). Differences: «الصلاة القادمة»/«الرواق» are fixed at the top with no arrows (DECISIONS); the mini phone is shape-only (11 pt minimum); the «رتّب» mode on the home itself (`flex/12-Tahrir`) is not built; `salah.pool`, `salah.fridayTallArch`, `salah.pendingDays`, `salah.qadaReminder` are not wired, so not shown. The displayed `salah.showMosqueStreak` title is now «سلسلة الجماعة» per owner decision; its setting key and behavior stay the same. Old `PrayerSettingsView` kept unused. Compare page: `Madar/Artifacts/compare/K-Salah.html`.| `salah.layout` (block order and hide) is v1 and not wired in `PrayerTodayView` yet. Clear the shipping-check FAILs for `salah.offsets` and `notif.quietFrom`. |

## Section M1-F — prayer features not built yet (after M1-V)

| Card | Result | Canonical / spec | Status | Notes |
|---|---|---|---|---|
| M1-F01 | Friday screen with explicit Jumu'ah/Dhuhr choice and the tall Friday arch | `salah/09-S8-Friday.jpg`, `-s1`; RP5 | approved | `fridayKind` is already stored (T01). `salah.fridayTallArch` default true. Built: the «جمعة مباركة» pill (no «الكهف في قسم القرآن» pointer: no entry to the Quran room yet), tall dome «الجمعة» arch, and the explicit Jumu'ah/Dhuhr choice in the log and make-up sheets (V02, V06). Fixture `homeShowcaseFriday` (UI-test only). Differences: the pill is narrower than the canonical (shorter text); pending notice comes from the fixture. Compare page: `Madar/Artifacts/compare/S8-Friday.html`.|
| M1-F02 | Travel: ask once, method per trip, shorten/combine without pre-pairing | `salah/10-S9-Travel.jpg`, `-s1`; RP4, RP7 | approved | Done 13 Oct: engine methods with fixtures; `salah.tripMethod` (no migration); `core.travelKm` default 80 km beyond the city edge (`TravelRule`, edge ≈ 25 km radius); location (when-in-use) + «خارج مدينتك» pill + ask-once sheet with suggested local method; `prayer.startTrip/endTrip/logPair` routed through the bus; trip pill «مسافر · المدينة · قصرٌ وجمع», «قصر · جمع»/«مع الظهر»/«مع المغرب» under arches, pair sheet, end-trip sheet. Not built: «يدويًا» mode entry (mode manual disables detection); paired arches are labelled, not redrawn as joined; Isha arch not dimmed. Do not copy: sample city/times. Owner approved the screen; real-device location verification remains pending. |
| M1-F03 | Edit the tracking start date once | §7.2 P04, `salah.trackingStart` | approved | Built in «خصّص الصلاة» → التسجيل: the start in words, one edit (date picker up to 30 days before first run), confirm dialog, then «اكتمل التعديل الوحيد». New command `prayer.editTrackingStart` is now accepted by the command bus (it was parsed but not routed); undo is available for ten minutes. No canonical screen exists for this row, so there is no compare page. |
| M1-F04 | Outside the app: next-prayer widget, lock-screen widgets, countdown | `salah/11-S10-Abwab.jpg`; §9; RL7, RP9, RU2 | blocked: a `LiveActivityIntent` needs a budget reservation shared with the app; the current ledger is SwiftData and the extension must not open it (RA2) | Slices 1–4 are implemented: next-prayer JSON snapshot and widgets; reminder notification; Shortcuts `LogPrayerIntent`; configurable `PrayerLogControl`. Both intents enqueue through `PendingInbox`, and the app alone opens SwiftData. Regression fixes: the snapshot retains today's Fajr and occurred prayer times; Friday «الجمعة + وحدي» is rejected before enqueue with a clear Arabic error. The app's scheduled Live Activity path uses `SanctityGuard` and `NotificationArbiter`. Remaining: design and test an atomic cross-process budget reservation before adding the RL5 `LiveActivityIntent`; RP9 remains times-only by default (no qada/streak values outside the app); shortcut/control/widget and scheduled-start device checks remain pending. The Control action has not been exercised on iPhone.
| M1-F05 | Import the old prayer history | §7.2, §11, `Madar/docs/MIGRATION.md` | deferred (owner, 13 Oct): not needed; no import, owner store never opened | Preview maps explicit statuses, leaves post-start `لم` derived, maps pre-start unlogged history to `unrecordedHistory`, flags required timestamps, and never writes. Never open or migrate the owner's real store without explicit permission. |
| M1-G | M1 gate on the owner's iPhone | §12/§13 M1, `docs/reports/M1.md` | blocked: owner-iPhone acceptance has not been run; M1 is not approved | Agent-side prechecks do not close the gate. Complete the iPhone acceptance checks before recording an M1 pass. Fill the gate table only at the gate. |

S0-Jard and S12-Khulasa are explainer boards (`kind: explainer`): use them for reference, don't build them.

## M2 preflight — RQ2, before porting the Quran engine

| Card | Task | Inputs | Status | Result and remaining |
|---|---|---|---|---|
| M2-RQ2 | Audit the pinned Quran engine before porting | `[FIX] RQ2`; §7.4; My-dream `aba0c1b18a3bf3fc070395a40595e939c3b73aa3` | done — source audit and test disposition; M2 paused by owner | The interval/ease, due-risk, adaptive-cap, legacy backlog and smart-test rules are documented; all 12 Quran tests are KEEP/REWRITE/DROP classified. The delegated decisions are recorded in `docs/DECISIONS.md`: `PageSchedule.stage` is removed because it is derived from `intervalDays`; RQ1 computed-need formula and simulation targets are defined. Owner confirms the Mushaf license is obtained and M2 has been paused since the outset. No Quran runtime route is integrated. Any separate tafsir-license check is deferred until M2 resumes; no current owner action is requested. |

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

1. After M1-V01/V05 screenshot comparisons are complete, run M1 acceptance on your iPhone using `docs/OWNER-RUNBOOK.md`. The S4 qada icon and the other supplied screen images are approved.

# Later

Finish the remaining M1-V01/V05 screenshot comparisons, then the owner-iPhone M1 acceptance. M1-F04 remains blocked on a safe shared budget reservation for an RL5 LiveActivityIntent. M2 remains paused per owner direction; the Mushaf license is obtained, and no Quran runtime route exists. Recheck any separate tafsir license only if M2 resumes. No M1 or M2 gate is claimed closed.

# Handovers

## Handover — M1-V01 «سلاسلك» stone arch — 2026-10-13 — Claude

Works now: home «سلاسلك» is three nested horseshoe arches in the home-arch shape (congregation inside, on time, completion outside), each one continuous line filling right to left and complete at a month; tap opens the details sheet (meaning, last seven days, break reason) and from it «حالي». Codex's pending F04/F05/S4 work committed earlier (`7182082`).
Verified: MadarPrayer `swift test` 25 passed; UI tests V01 home, streak sheet, streak month (9/16/24), V04 passed; V05, T05, T06 passed after the route change.
Differences left: no bead arc or month % on the home card (owner decision); S1 scrolled alignment and V05 `-s1` capture open.
Not verified: owner look; owner iPhone; dark-mode capture of the arch.
Next: owner reviews the arch; then V05 `-s1` and the S1 compare page.
Model/effort: Claude Opus 5.5; effort not exposed. Usage: not exposed.

## Handover — M1-V01 rejected visuals and redesign assignment — 2026-10-13 — codex

Works now: the five visual alternatives were shown and rejected; none is approved. The three meanings remain الجماعة / الصلاة في وقتها بلا قضاء / إتمام الصلوات الخمس, with no day count. Latest mockups did not change app code.
Verified: no build or tests run for this documentation update. The earlier simulator pass applies to the previous implementation only and is not visual approval.
Differences left: the streak shape and final S1 visual design are unresolved; main S1 scrolled alignment and V05 scrolled capture are still open.
Not verified: a Claude Opus 5.5 design has not yet been produced; owner-iPhone acceptance or distribution.
Next: Claude Opus 5.5 designs a fresh S1 Hali streak visual; show that screen to the owner, then implement after its visual direction is accepted. Continue S1/V05 comparisons.
Model/effort: Codex, effort not exposed. Requested design model: Claude Opus 5.5 (not yet run). Usage: not exposed.


## Handover — M2-RQ1/RQ2 delegated decisions — 2026-10-13 — Claude

Works now: `PageSchedule.stage` is removed; the computed-need rule and 100/300/604-page simulation targets are recorded in `docs/DECISIONS.md` and the Quran extract. Commit: `e72966a`.
Verified: commit changes five documentation/data-dictionary files; no engine code was ported. No tests or load simulation were run in this decision-only task.
Differences left: Quran runtime is not integrated; M2 remains paused per owner direction. The Mushaf license is obtained; any separate tafsir-license check is deferred until M2 resumes. M1-F04 still needs a safe shared budget reservation.
Not verified: Quran engine/screen integration or M1 owner-iPhone acceptance; no owner store was opened.
Next: finish M1-V01/V05 screenshot comparisons, then owner-iPhone acceptance. Do not resume Quran work unless the owner asks; review any separate tafsir licensing then.
Model/effort: Claude Sonnet 5.5; effort not exposed. Usage: not exposed.
