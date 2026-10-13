# Current milestone

M0 lean software closure → M1 prayer implementation. **Full M0 NOT APPROVED: owner-iPhone acceptance is still not tested.** Owner revision 12 October 2026 separates software readiness from the device/distribution gate; after accepted lean dependencies, M1 software may proceed. Font permission is closed; RA1 local-only, RA2 app-only store writes, RP1 and data preservation remain mandatory.

Current model policy: **GPT-6 Luna max may implement production.** Sol is narrow escalation, not a default stop. Deliver a usable integrated slice or proven repair, reuse passing evidence, and preserve about 3–5% of the five-hour allowance. The current queue supersedes historical handovers and automation memory.

# Last checked

Checked clean main `3c877df`, latest handover, and retained T04 candidate `433cbf6`; main was merged into `codex/m1-s2-sanctity`. Reused prior unchanged notification/inbox lifecycle approval. The supposed §9/RL5 blocker is resolved by the explicit review-fix precedence: RL5 starts consume budget and respect quiet hours. New focused Core activity tests 2/2; signed simulator notification + ledger flow 2/2, isolated persisted ledger test 1/1. Scoped independent RL5 review: no actionable findings. Preflight 11 pinned resources pass, 0 copied. Actual ActivityKit start, owner iPhone and distribution remain not tested. Start usage 1% five-hour used, latest boundary 9%; no reset used.

# Board

Active sections: **M0-S2 shipping integration (software slice delivered)**; **M0-S3 lean software acceptance (software-ready; device gate pending)**; **M1-S1 prayer home/logging (delivered)**; **M1-S2 prayer sanctity and notifications (in progress)**. Prior accepted work stays accepted. Advanced backup/privacy/platform checks remain tracked below; they are not the default development queue.

| Card | Status | Accepted scope / evidence | Remaining / references |
|---|---|---|---|
| M0-T00 | done | Protocol, Before-M0 contract corrections | `docs/reports/M0-T00-protocol.md`; RA4 tracked T07 |
| M0-T01 Top | done | Architecture note and repair decisions | `docs/design/M0-local-inbox.md`; retain section/gate limits |
| M0-T02 | done | App-only inbox drain, atomic writes and replay; merged3e54a53 | `docs/reports/M0-T02-command-inbox.md`; RA2 suspended/first-unlock physical check remains |
| M0-T03 | done | Local factory/RD2 retention; merged3718248 | `docs/reviews/M0-local-retention.md`; no CloudKit |
| M0-T07 | done | RA4 compatibility/frozen fixtures; mergedcb57e68 | `docs/reports/M0-T07-review-fixes.md`; owner-data/device acceptance remains |
| M0-T08 | done | Plain portable export; merged12b49c2 | `docs/reports/M0-T08-plain-export.md`; real Files destination write remains |
| M0-T04 | done | Lean glass shell, built rooms only; merged596dc05 | `docs/reviews/M0-lean-shell.md`; RA3/RL8; presets/styles deferred |
| M0-T05 | done | Keyboard/password diagnostic repair | `docs/reports/M0-T05-keyboard-dispatch.md`; privacy separately T09 |
| M0-T10 | done | Read-only today prayer clocks; mergedb6556bb | `docs/reports/M0-T10-foundation-times.md`; no prayer-room logging/notifications |
| M0-T11 | done | Bounded shipping-source checker; merged3b273b5 | `docs/reports/M0-T11-source-checks.md`; source mapping is not runtime acceptance |
| M0-T13 | done | Arabic backup plural/numeral copy; merged1ee273e | `docs/reviews/M0-backup-copy.md`; no backup behavior change |
| M0-T14 | done | RA1 this-device-only restore warning; mergedd28c36a | `docs/reviews/M0-backup-copy-t14.md`; focused golden regression passes |
| M0-T15 | done | Verified missing-font preparation, Makefile guard, current startup docs | `docs/reviews/M0-workspace-preparation.md`; 11 resources checked, no binary publication/overwrite |
| M0-T09R Top | done | Top SDK fix b7cd5d1 + actual full centered OS card at L/light, native1/0 in31.396s; independent Top approve | Scope: replace unavailable coordinate helper using SDK-proven normalized endpoint API; §8.10 (`14-shared.md`), presentation-privacy design. Acceptance: independent SDK review and actual identified/full-card OS snapshot completed; `docs/reviews/M0-T09-switcher-native.md`. Out: production/privacy/clock/default changes. Failed history preserved; green candidate restored d28c8dc. |
| M0-T18 | done | Owner-requested outcome-first/Luna protocol, lean queue and automation alignment | Documentation delivery only; no app feature or gate pass. Root/nested AGENTS and CLAUDE identical. |
| M0-T16 | done | **Reviewed privacy repair integrated; authorized plain-export native share and dismissal work on current main** (`ea3e63d`) | Reused production approval `8876626`; selected simulator host privacy/presentation 15/0, `ManagedBackupTests` 13/0, and fresh synthetic-store Face ID/share/dismissal 1/0. Raw output retained under `Madar/Artifacts/m0-t16-20261012-main/`. Actual Files destination write, physical iPhone, and broader two-scene/device privacy remain untested. No owner data or auth bypass. |
| M0-T17 | done — lean software-ready | **Foundation settings and today's clocks are usable across city/numeral change, reset/undo, and relaunch** (`95804a1`) | Reused accepted day/clock/inbox/default evidence; new signed simulator journey 1/0 in 75.702s with L screenshots inspected. Preflight: 11 font/license resources pass, 0 copied. Checklist and evidence in `docs/reports/M0.md`; raw run under `Madar/Artifacts/m0-t17-20261012-main/`. Owner-iPhone and applicable RA2 device acceptance remain not tested; this is not full M0 approval. |
| M1-T01 | done | **Today's prayer home and persistent basic logging integrated on main** (`e6fbe75`): five computed prayers/next prayer, due prayer→Jamaah/Alone save, Friday kind, change/undo and relaunch persistence. Additive v3 migration preserves v2 data and undo receipts; no automatic missed/qada. | Focused domain/Core/command/migration tests and signed simulator save/relaunch/change/undo passed; default and AX3 screenshots inspected; independent migration review had no Critical/High/Medium findings. Synthetic stores only. §7.2 `09-r-salah.md`, §10 `16-tech.md`, data `17-data.md`, RP1/RP2/RP6/RU1. Owner-iPhone and distribution remain untested. |
| M1-T02 | done | **Explicit missed/make-up and pending recovery** integrated `1697c09`: explicit missed adds debt; one timestamped MakeUpPrayer updates log+QadaItem atomically/idempotently; undo restores both. Bulk gap review distinguishes missed, unrecorded, and excused; silence never ages automatically. | Core/Prayer/Commands tests and focused native flows passed; owner iPhone/distribution untested. §7.2/§10/§11, RP1/RP2. Out: automatic aging and notification/intent entry points. |
| M1-T03 | done — pure engine (`dc4d011`) | **One pure SanctityGuard for every scheduled notification time**, including prayer asks, snoozes, room reminders, digest and open-app nudge; apply the approved Friday Dhuhr (~60 min) and Ramadan Isha (~90 min) windows. | Full-year 2026 property coverage for Riyadh, Jeddah and Tromsø plus boundary/cascade tests; 27 Core tests passed. Independent RP3 review: no findings. Out: OS request lifecycle and Live Activity implementation. §7.2/§8.8, RP3. |
| M1-T04 | done — software slice; device proof pending | **Guarded iOS notification scheduling, tap-time snooze, cancellation after prayer logging, and a maintenance-safe inbox/notification lifecycle.** | Commands 14/14; selected simulator prayer-log + notification flow 2/2; independent lifecycle review found no actionable issue. RL5 precedence applied; new start budget/quiet/device gate and persisted ledger checks passed; scoped independent review no findings. Physical-device/ActivityKit start and distribution remain untested. §7.2/§8.8/§10/§11, RP3/RL5. |
| M1-T05 | done — software slice | **حالي and editable Hijri-month history**: actual month ratio, separate made-up/debt counts, derived prayer/mosque streaks, last 25 states, per-prayer commitment and day edit. Mosque streak can be hidden; default/AX3 layouts have real screenshots. | Native `test_M1T05_HaliGoldenRatioHistoryEditUndoAndAX3`: 1/0 in 93.443s, includes 87%→90%→undo 87%, relaunch and true AX3 semantic-list assertion; `/tmp/madar-t05-hali-wrap-20261013.xcresult`. Reuses unchanged §7.2 golden analytics. Synthetic data only; owner iPhone/distribution not tested. |
| M0-T09 | in-progress | Existing repaired privacy slice is input to T16; many bounded native results already approved | Remaining encrypted first-key/restore authorization, true two-scene and other private surfaces tracked for first exposed use; focused independent review + actual feature acceptance before claiming them. Do not restart completed plain/switcher matrix or hold independent M1 software for this entire backlog. |
| M0-T12 | needs-fix | Focus/search/title growth sourcec273bc4; nil-target contrast remains unsuppressed | Reuse approved focus diff only if needed by current screen. Diagnose actual element/pair when tooling can produce it; no identical rerun. A confirmed defect blocks acceptance of its affected screen, not unrelated implementation. VoiceOver/Reduce Motion/physical proof remain not tested. |
| M0-T06 | in-progress | Existing evidence is preserved in M0.md | Lean software decision recorded at T17; owner-iPhone shell/today clocks and applicable local-store acceptance remain a separate required device gate. No TestFlight/distribution or full milestone approval without actual proof. |

## Next results, in order

1. **M1-T04**: integrated `e4ecf59`; actual ActivityKit start and owner-device acceptance remain separate.
2. **M1-T05 — delivered, see board — حالي + editable history**: show the existing engine's Hijri-month ratio, independent qada/debt counts and derived streaks, plus last 25 states and a selectable history day. Changing a past missed record and undo updates the ratio. §7.2 `09-r-salah.md` (حالي/القواعد/السجل), RP1/RP2/RP5/RP6/RU1; canonical S3-Hali. Out: travel, heart collection and qiyam.
3. **M1-T06 — optional heart answer**: explicit opt-in, optional answer with save/skip/undo; no ranking or persistent home labels. §7.2 التسجيل/حضور القلب, RP6, §10 commands. Out: external-release wording approval.
4. **M1-T07 — qiyam night logging**: record rakaat/witr for an eligible night with save/relaunch/undo, using the approved Isha–Fajr nightKey and qualitative 30-night footprint. §7.2 قيام الليل/P05, §10/§11. Out: unbuilt Quran entry points or cross-room Quran writes.

## Instructions for the next agent

- Start from the current queue, root protocol and latest handover. T04's prior command/native notification and lifecycle results are retained; do not repeat unchanged green checks. Before native work run `python3 Madar/scripts/prepare-workspace.py`.
- RL5 is a [FIX] overriding §9: no new owner decision is required. Notification start budgeting has focused new tests and needs its scoped independent review before integration. Preserve actual-device and ActivityKit proof as untested.
- Keep owner-iPhone acceptance, actual Files destination write, T12 contrast, broader privacy/accessibility and distribution separate. Unchanged historical refs: `docs/reports/M0-retained-branches.md`. Historical advice is superseded by this queue.

# Later

M1-S2 notification/sanctity + relevant physical RA2 checks; M1-S3 remaining prayer flows/statistics/travel and room gate. M2 Quran; M3 diary; M4 lobby/habits/widgets; M5 money; M6 Mihbara; M7 final integration. Plan each next section only when ready. Preserve existing scaffolding; shipping later features requires their actual acceptance and licensing.

# Handovers

## Handover — M1-T04 guarded notification candidate — 2026-10-13 — codex

Works now: Candidate `433cbf6` on `codex/m1-s2-sanctity` schedules prayer notifications through the sanctity path, handles tap-time snooze/cancellation after prayer logging, and keeps notification store access suspended until maintenance and inbox draining complete.
Verified: `python3 Madar/scripts/prepare-workspace.py` passed 11 pinned resources, 0 copied. `swift test --filter InboxDrainTests` passed 14/14. Selected `xcodebuild` run passed `test_M1T04_RealAppNotificationSchedulingSnoozeAndCancellation` and `test_M1T01_PrayerLogPersistsChangeUndoAndAX3` (2/2) on iPhone 17 Pro simulator, iOS 26.5; xcresult: `/tmp/madar-m1-t04-derived/Logs/Test/Test-Madar-final-maintenance-gate.xcresult`. Independent static review of the maintenance/drain lifecycle found no actionable issue. `git diff --check` passed before the candidate commit.
Not verified: physical iPhone behavior, an actual Live Activity start, the unresolved Live Activity budget rule, or distribution. This candidate is not integrated; full M0 remains NOT APPROVED.
Next concrete result: owner decision on whether Live Activity starts count against the per-device notification budget, then finalize the affected behavior and integrate the selected T04 slice. Keep device acceptance distinct from simulator results.
Active branch/worktree/tip: clean `main` at `f320836`; unmerged candidate `codex/m1-s2-sanctity` at `433cbf6`; no worktree created.
Model/effort: root model and effort not exposed; independent review result is static only.
Usage: latest reading 33% five-hour used / 67% remaining, 5% weekly used / 95% remaining; no reset used.


## Handover — M1-T02/T03 prayer recovery and sanctity engine — 2026-10-13 — codex

Works now: Main `dc4d011` includes M1-T02 explicit missed/make-up and review of pending gaps, plus M1-T03's single pure guard that moves all planner candidates outside overlapping prayer sanctity windows. Friday Dhuhr and Ramadan Isha use the approved extensions; prayer days carry the calculated Hijri date so Ramadan rules are selected from the active Hijri source. Silence still never creates missed/qada automatically.
Verified: T02 Core/Prayer/Commands suites passed 23/23, 17/17 and 20/20; signed iPhone 17 Pro/iOS 26.5 tests `test_M1T02_MissedMakeUpUndoAndRelaunch` and `test_M1T02_BulkPendingRecoveryAtAX3` each passed. Default and AX3 screenshots inspected. T03 `cd Madar/Packages/MadarCore && swift test`: 27 passed, 0 failed; focused sanctity cases include boundaries, cascades, request paths, and a 2026 property sweep for Riyadh, Jeddah and Tromsø. Independent RP3 review: no findings. T03 `git diff --check` passed before commit.
Not verified: native `UNUserNotificationCenter` request lifecycle, tap-time OS snoozes, cancellation after logging, actual Live Activity starts, owner-iPhone acceptance, or distribution. Tests used synthetic stores; no owner data was opened. Full M0 remains NOT APPROVED.
Next concrete result: M1-T04: connect the existing pure guard to real iOS request scheduling, tap-time snoozes, cancellation, and Live Activity starts; verify the selected simulator flow and preserve separate device/distribution gates.
Active branch/worktree/tip: `main` production tip `dc4d011`; section branch `codex/m1-s2-sanctity` contains the same T03 source tip. The progress handover will be committed separately on main. Prior refs and worktrees are preserved.
Model/effort: root model and effort not exposed; independent RP3 review completed with no findings.
Usage: latest boundary reading 15% five-hour used / 85% remaining, 2% weekly used; reset credits unused. Continue useful authorized M1 work while preserving the owner's final 3–5% reserve.

## Handover — M1-T01 prayer home and logging — 2026-10-12 — codex

Works now: Main `e6fbe75` shows today's five computed prayers and next prayer; recording a due prayer as Jamaah/Alone, Friday kind, change, undo and relaunch persistence work. Additive v3 migration preserves synthetic v2 prayer data and undo receipts. No automatic missed/qada.
Verified: `prepare-workspace.py` passed 11/11 pinned resources, 0 copied. In their package directories: Prayer `swift test --filter 'fridayNoonRequiresKind|fridayUnrecordedHistory|oldFridayMissed'` 3/3; Core `swift test --filter fridayPrayerMutationCommands` 1/1; Commands `swift test --filter 'ReplayTests|SchemaMigrationUndoTests'` 5/5; Data `swift test --filter schemaV2` 3/3. From `Madar/`, signed simulator command `xcodebuild -quiet -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=412F4437-7BD7-44D1-AA3D-2B7158090E14' -only-testing:MadarUITests/FoundationUITests/test_M1T01_PrayerLogPersistsChangeUndoAndAX3 test` succeeded; xcresult: 1 passed, 0 failed. Default and AX3 screenshots inspected. Independent narrow migration/domain review: no Critical/High/Medium findings.
Not verified: owner-iPhone acceptance, migration against owner data, distribution, full M0 approval, and T12 contrast. All stores used for this migration check were synthetic.
Next concrete result: M1-T02 explicit missed/make-up and pending recovery; preserve RP1, atomic/idempotent log+QadaItem updates, undo, and no automatic aging.
Active branch/worktree/tip: clean `main` after this handover commit; retained `codex/m1-t01-prayer-logging` at `e6fbe75`. Existing T16/T17 refs preserved; [historical branch/worktree inventory](docs/reports/M0-retained-branches.md).
Model/effort: root model and effort not exposed; do not infer Luna/max. Independent review was limited to the new migration/domain slice.
Usage: latest account reading before handover was 33% five-hour used and 98% weekly used; reset credits unused. Weekly limit is near its cap, so no further card was started.

## Handover — M0-T16/T17 lean software delivery — 12/10/2026 — codex

Works now: T16's reviewed privacy repair is integrated on main; a fresh synthetic store completes Face ID authorization, creates the plain export, opens the native share sheet, and dismisses back to the recovered app. T17's foundation flow changes city/numerals, persists across relaunch, resets and undoes settings, then relaunches to five current prayer clocks. Lean M0 software readiness is recorded; full M0 remains NOT APPROVED.
Verified: main `95804a1` includes T16 `ea3e63d` and T17 `95804a1`. `python3 Madar/scripts/prepare-workspace.py`: 11 resources pass, 0 copied. Selected signed simulator host tests: 15/0 (`/tmp/madar-t16-20261012-4e69691-host.log`); `swift test --filter ManagedBackupTests`: 13/0. `python3 scripts/native-export-biometric-test.py --device 412F4437-7BD7-44D1-AA3D-2B7158090E14 --derived-data /tmp/madar-t16-20261012-4e69691-native-derived --output-dir /tmp/madar-t16-20261012-4e69691-native`: 1/0 in 43.607s. T17 signed simulator UI test: 1/0 in 75.702s; default/Makkah-western/today-clock screenshots inspected. Ignored raw evidence is retained in `Madar/Artifacts/m0-t16-20261012-main/` and `Madar/Artifacts/m0-t17-20261012-main/`.
Not verified: actual Files destination write, owner-iPhone build/acceptance, physical RA2 transport/protected-data behavior, full VoiceOver/Reduce Motion, unresolved T12 contrast, complete route/privacy/two-scene matrices, full M0 approval and distribution.
Next concrete result: M1-T01 today's prayer display and persistent basic logging, including save/relaunch/change/undo against a synthetic local store; reject future logging and never auto-create missed/qada.
Active branch/worktree/tip: clean `main` `95804a1`; retained T16 `codex/m0-t16-curated-export` `ea3e63d` and T17 `codex/m0-t17-lean-readiness` `95804a1`. No worktree created or archived.
Model/effort: root model and effort not exposed; cannot claim Luna/max ran. No independent review needed for T17 test-only change; reused T16 production approval `8876626` for unchanged reviewed source.
Usage: latest at the T17 boundary 13% five-hour used / 87% remaining, weekly 95% used / 5% remaining; reset credits unused. The documentation checkpoint read 16% five-hour used / 84% remaining, weekly 95% used / 5% remaining. Weekly allowance may end this session early.

## Handover — owner correction: usable deliveries and Luna max — 12/10/2026 — codex

Works now: root/nested agent protocols and startup queue use outcome-first development, Luna max production permission, scoped review/escalation, grouped small cards until about5% reserve, and lean software/device separation. This is the owner's requested process correction, not app delivery.
Verified: paired root/nested protocols identical; five handovers/current card queue and spec references checked; git diff --check passed. Automation tool update/readback: gpt-6-luna/max, PAUSED, unchanged five-hour schedule/local project. No product build/test repeated. The first whitespace check found one trailing blank line and it was removed; the host Python lacks tomllib, so readback uses its built-in regex without installs.
Not verified: Luna performance on production work, T16 integration, T17 software readiness, M1 logging and owner-iPhone/full M0 acceptance. No guarantee that every future session succeeds.
Next concrete result: FIRST T16 integrate reviewed existing export/privacy repair and deliver ordinary authorized native share on main; then T17 lean software flow; then M1-T01 persistent prayer logging. No extended encrypted/Inspector loop as the default queue.
Active branch/worktree/tip: main process docs only; T09 `codex/m0-t09-system-ax3-navigation`70939f5 in m0-p1b-fixes; T12bfa878b unchanged. Historical refs listed in retained inventory; nothing deleted.
Model/effort: future automated author GPT-6 Luna max; current root identity/effort not exposed. Sol escalation only for a concrete unresolved problem.
Usage: setup reading5% five-hour used/95%remaining, weekly94%used. This specific documentation/process request does not authorize unrelated coding just to consume the allowance; future development sessions keep the owner's approximately5% reserve and multi-card target. Final reading9% five-hour used/91%remaining, weekly94%used; this process-only task did not target spending the allowance. No reset used.
