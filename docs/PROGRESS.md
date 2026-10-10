# Current milestone

M0 — reconciliation with review V1, before accepting the existing foundation. Full software objective M0–M7 remains active, iPhone first. Original handoff and earlier app work are preserved. M1 files exist as unintegrated scaffolding; later rooms are not complete.

# Last checked

Checked aac7014..3e54a53 — 2026-10-10 automation: 3 inherited prayer/number defects fixed (7291d02, df44c20, cbaa7e2). Scoped M0-T04 review approved/merged 596dc05; Top M0-T02 transport/data fixes approved/merged 3e54a53. Current main: Core 21, Commands 17, Inbox 6, Prayer 12 passed; simulator app build + 15 host integration tests passed. Shell UI 4 + legacy-route integration passed with default/AX3/dark comparison and native minimize. Actual cold launch/relaunch drained two synthetic sources to one fact/two receipts/no pending files. Data 38/Snapshots 3/Sync 8 baseline passed; those files are unchanged. RA4, backup UI, complete lint and physical M0 gate remain open.

# Board

| Section | Status | Task | Owner | Scope and acceptance |
|---|---|---|---|---|
| M0-S0 Protocol and contracts | building | M0-T00 in-progress | root | Install protocol/fixes, 25 plain-text sections, decisions, owner runbook. Correct Before-M0 JSON only in the working copy, preserve source. RA4/5/6/9, RD2/5, RMI1, RQ8, RL5, RP6. |
| M0-S0 Architecture | building | M0-T01 done (Top) | architecture_review | Design note and changes-requested review committed 4e88a83. Eight findings; receipt identity/replay gaps added to M0-T02. RA1/RA2/RD2 fixes can now proceed, subject to scoped review. |
| M0-S1 Command inbox and replay | building | M0-T02 done (Standard high; Top reviewed), merged 3e54a53 | codex Sol | Atomic inbox, app-only drain and scoped durable replay accepted. M0I-01/02/03 closed, including collisions, receipt GC across replacement, and unknown commands. Read docs/reviews/M0-command-inbox.md and docs/reports/M0-T02-command-inbox.md. Current root host + cold-launch checks passed; physical suspended-app notification/widget and before-first-unlock checks not tested. Full M0-S1 still awaits RA4/T07 and export/gate. |
| M0-S1 Local factory and retention | building | M0-T03 done (Standard high; Top reviewed) | local_data | Agent 4297c8a reviewed approve scope-only, integrated 3718248. Root full MadarData rerun passed 38 tests in 3 suites (review-local-retention-integrated.log). No CloudKit factory choice; RD2 retains children and old tombstones. M3 arrow UI pending. |
| M0-S1 Model rename compatibility | building | M0-T07 in-progress (Standard high) | codex money_compat | Reuse isolated m0-local-data worktree, new branch m0-s1-money-models from current main. RA4 MoneyTransaction; freeze old schema and staged migration before changing names. Read 17-data and the compatibility passage in docs/design/M0-local-inbox.md. Old store/archive fixtures preserve IDs/FKs/timestamps/deletions/media. Separate from approved RD2. |
| M0-S2 Lean shell and times | approved | M0-T04 done; merged 596dc05 (Standard high reviewed) | claude + codex reviewer | Native glass only; hide cut settings, presets and cloud entry. Only built rooms visible. Defaults RD5/RQ8/RL5/RP6. Read 04-arch, 06-flex, 09-r-salah, 18-plan; RA3/8, RL8, RU1/3. Default/AX3/dark screenshot comparison and native minimize verified; 3 UI tests + availability UI/legacy-route integration tests passed. Scope-only approval; M0-T05 remains open. |
| M0-S2 Existing UI defects | building | M0-T05 in-progress (Top) | ui_debug | Worktree m0-ui-debug, branch m0-s2-backup-focus. Backup confirmation lost keyboard focus after prior attempts; diagnose real screenshot/log before fix. Root owns simulator and validation. Lock persistence passed. Preserve fixture isolation. Window-level sheet privacy remains required before private content ships. |
| M0-S3 Review and gate | building | M0-T06 todo (Top) | unclaimed | Fresh section reviews, J01–J18 room journey definitions before cited gates, M0 report. Build iPhone prayer times. Physical/signed checks marked not tested until runnable. |

Production tasks start after M0-T01. Separate agents own separate sections/files. No agent may switch this shared checkout's branch while another runs. Use separate managed worktrees for parallel production after a curated baseline exists. Read-only/design jobs may share the checkout. Do not broadly stage `output/`, `tmp/`, generated build products or user data.

# Later

- [fix-previous] RU3 in-progress: codex plurals owns isolated m0-arabic-plurals worktree, Standard high. Replace CustomizeMadar count phrase with Arabic String Catalog variants and verify 0/1/2/few/many/other in both numeral styles. Money compatibility continues independently in preserved m0-local-data; root owns simulator and integration.

- M1: prayer logging/unconfirmed gap review/excused, correct windows and sanctity, travel methods, independent timetable fixtures, notifications/device checks. Plan 2–4 sections after corrected M0.
- M2 Quran, M3 diary, M4 lobby/habits/widgets, M5 money, M6 Mihbara, M7 integration remain unfinished. No entry points until built.
- Reassess sync after M5. Developer membership, TestFlight and additional platforms await owner setup.
- Encrypted backup already exists; scalability RD4 and window-level privacy need review in the first relevant milestone. Retain code without implying all contracts passed.

# Handovers

## Handover — M0-T02/T04 and previous fixes — 2026-10-10 — codex (Sol)

Done: resumed the board; baseline check; separate [fix-previous] commits repair Prayer tests, make legacy aging a no-op under RP1, and replace numeric middle dots under RU1. Standard-high execution and independent Sol xhigh review closed all three inbox findings (including receipt-GC/pointer replacement). Independent Standard-high shell review approved M0-T04; both scoped tasks merged. Root did not begin the next section or claim all M0 approved.
Verified: `swift test` Core → `21 tests ... passed`; Prayer → `12 tests ... passed`; Commands → `17 tests in 2 suites passed`; Inbox → `6 tests ... passed`. `xcodebuild ... -only-testing:MadarTests test` on main 3e54a53 → `Executed 15 tests, with 0 failures`, `** TEST SUCCEEDED **` (Artifacts/automation-main-integration.log). Shell UI → `Executed 3 tests, with 0 failures` plus cut-query UI → `1 test, 0 failures`; legacy preserved-values/deep-link test → `1 test, 0 failures`. Actual default/AX3/dark captures and native bar minimization reviewed. Root process proof → `producerStoreFiles: 0`, `producerLinksSwiftData: false`, one fact/two receipts/three refreshes/no unacknowledged files, `passed: true`. Actual @main cold launch/relaunch → `rows: 1, receipts: 2, unacknowledged: 0`, refreshed foundation JSON. Raw logs/results and fixture IDs: Madar/Artifacts/automation-*. Baseline unchanged Data 38, Snapshots 3, Sync 8 passed. `git diff --check` clean; AGENTS/CLAUDE identical.
Not verified: backup password/export UI remains failed from earlier work (not retried here); physical iPhone, genuine suspended-app notification/widget actions, before-first-unlock protection, VoiceOver interactions, complete general string/colour/availability lint, old owner-data migration, or whole M0 gate. Cold-launch deliveries were external synthetic JSON records, not real extensions. Candidate host run (14 tests) is superseded by current main's 15-test run.
For the next agent: first fix inherited RU3 plural copy in CustomizeMadar as a separate [fix-previous] task, then resume M0-T07 and M0-T00 in their preserved scope. Do not overwrite the dirty money-model worktree or stage the inherited untracked docs/journeys/ blindly. Quick-check main from 3e54a53; docs-only changes after it need no product re-review. RA4 needs exact old-store/archive migration fingerprints and a fresh Top data review before merge. Backup diagnostic branch has already had repeated attempts; follow the two-attempt stop rule rather than looping the same UI test. No new prayer-room entry point ships.
Branches/worktrees: m0-s1-money-models at 7c2acad in /Users/abdulrahman/.codex/worktrees/m0-local-data/بناء مدار 2.0 has preserved uncommitted RA4 code/fixtures; needs completion/tests/Top review. m0-s2-backup-focus at e1ae006 in /Users/abdulrahman/.codex/worktrees/m0-ui-debug/بناء مدار 2.0 is unmerged/unverified; inspect its diagnostic diff before any integration. m0-s1-command-inbox at 76bab3c in /Users/abdulrahman/.codex/worktrees/m0-command-inbox/بناء مدار 2.0 is merged; duplicate current review remains untracked there and canonical committed review is on main. m0-fix-previous-prayer at 9e4e6f9 and m0-inbox-lifecycle-tests at 169d4e5 are cherry-picked/integrated equivalents, not additional unfinished production; their temporary managed worktree m0-previous-prayer was archived after preserving logs in the primary checkout. m0-s1-local-retention at 4297c8a is already integrated as 3718248. m0-s2-lean-shell at ef6e0b0 is merged. Shared checkout is main with no tracked changes; inherited untracked docs/journeys/ intentionally remains.
Next: RU3, finish RA4/T07 and remaining protocol/export scope, then fresh full section/gate reviews. Stop at this scoped review/integration boundary.
Next session: Standard (GPT-6.1 Sol high) for production fixes; delegate fresh Top (Sol xhigh) for data section review and M0 gate. Never infer physical acceptance from software tests.

## Handover — M0-T04 lean shell — 2026-10-10 — claude (Sonnet, standard)

Done: quick check of Codex work (see Last checked). M0-T04 on branch `m0-s2-lean-shell` (not merged): glass-only native `TabView` (RL8); cut keys (`core.fontScale`, `core.motion`, `core.roomIdentity`, `tabbar.*`) removed from `AppSession.supportedKeys` and hard-coded to defaults in `TabShell.swift`; entry points to saved presets and sync settings removed from `CustomizeMadar.swift` (code kept for compatibility, `savePreset` unreachable). Stored values of cut keys are now ignored.
Verified: `xcodebuild ... generic/platform=iOS Simulator build` → `** BUILD SUCCEEDED **`. UI tests testFirstRunAndSettingsRenderWithoutUnbuiltRooms, testThemePersistenceResetAndUndoThroughUI, testLightDarkAndAccessibilityScreenshots → `Executed 3 tests, with 0 failures`, `** TEST SUCCEEDED **`.
Not verified: AX3 screenshot compared against canonical design by eye; physical iPhone; settings-schema `availability: v2` flags in the JSON were not changed here; `savePreset`/PresetsView files still exist.
For the next agent:
1. Section review of `m0-s2-lean-shell` (Standard), then merge. Possible merge conflict in `AppSession.swift` with the inbox branch.
2. Top-tier review of `m0-s1-command-inbox` (846e1bb) before merging: concurrency and data path. It reports its tests pass but no simulator run.
3. [fix-previous] `Packages/MadarPrayer/Tests/MadarPrayerTests/PrayerTests.swift` lines 22, 43, 84, 104: `#require(apply(...))` lacks `try`, so the package does not build its tests. Line ~58-66 asserts aging to missed, which RP1 forbids; remove `.agePending` (PrayerMutationHandler.swift) as part of M1 RP1 work. `PrayerRoom.swift:364` has "·" next to a digit (RU1).
4. Backup UI test: stop after two more attempts, test the model logic and verify by hand on the phone.
Next: Top (Sol xhigh or Opus, high) for item 2, then M0-T07 and M0-T06.

## Handover — review files received — 2026-10-10 — root

Done: read all attachments; copied protocol and handoff; extracted 25 sections; RD2 conflict resolved by owner. Earlier automatic prayer aging, multi-process SQLite proof and visible disabled cloud setting now conflict with V1.

Verified: file reads, exact AGENTS/CLAUDE match, current git status (no commits). Earlier logs: services integration v3 passed 10 tests; first services UI run failed 2 tests; fixes exist but rerun pending. These are not current milestone acceptance.

Not verified: full new contract compliance, physical iPhone run, notifications/widgets/Live Activities, actual cloud sync, Quran licenses, real user migration. Prior agents ended with tool-reported usage errors; no reset was consumed.

Current check: updated defaults passed 34 tests, then integrated RA1/RD2 passed 38 tests (Artifacts/review-local-retention-integrated.log). Unfinished M2 QuranRoom.swift is preserved and excluded from M0 target. Lock persistence passed in actual simulator checks. Backup UI still fails matching/export at the first assertion (backup-fixture-check.log); named native-export attachments from that failed flow are failure-state images. Top reviewer requested changes, not acceptance. Fresh diagnostic fix is being tested with failure collection disabled to avoid the previous 600-second diagnostic stall. Production password rules are not weakened.

Baseline snapshot: preserve the inherited app source as a separate local commit to permit isolated branch/worktree review. This is a record of existing implementation, not acceptance of old contracts. Build products, font binaries, output/ and tmp/ stay excluded. Earlier builders' actual model tiers are not inferred from inherited files.

Next: Top architecture note, current build/UI check, then scoped data/inbox fixes. Recommended tiers: Sol xhigh for architecture/reviews; Sol high for production paths. Human instructions remain above attached documents.
