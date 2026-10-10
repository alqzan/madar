# Current milestone

M0 — reconciliation with review V1, before accepting the existing foundation. Full software objective M0–M7 remains active, iPhone first. Original handoff and earlier app work are preserved. M1 files exist as unintegrated scaffolding; later rooms are not complete.

# Last checked

Checked 9386ea7..b7bed94 — protocol/default metadata and RA1/RD2 reconciled. Top RA1/RD2 review approved; root MadarData passed 38 tests after integration. Simulator app compiled, lock persistence passed. Backup flow still failed matching/export after native Next; Top fix-only diagnostic rerun active. RA2/RA4/RA8 and physical M0 gate remain open; no whole milestone approved.

# Board

| Section | Status | Task | Owner | Scope and acceptance |
|---|---|---|---|---|
| M0-S0 Protocol and contracts | building | M0-T00 in-progress | root | Install protocol/fixes, 25 plain-text sections, decisions, owner runbook. Correct Before-M0 JSON only in the working copy, preserve source. RA4/5/6/9, RD2/5, RMI1, RQ8, RL5, RP6. |
| M0-S0 Architecture | building | M0-T01 done (Top) | architecture_review | Design note and changes-requested review committed 4e88a83. Eight findings; receipt identity/replay gaps added to M0-T02. RA1/RA2/RD2 fixes can now proceed, subject to scoped review. |
| M0-S1 Command inbox and replay | building | M0-T02 in-progress (Standard high) | command_inbox | Worktree m0-command-inbox, branch m0-s1-command-inbox. Atomic JSONL inbox and app drain, value-only transport, durable duplicate receipts/replay before tombstone/expiry. Read design note, 16-tech, 17-data, 15-outside; RA2 and M0R-03/04/05/06. Independent producers never link SwiftData. Root coordinates simulator tests. |
| M0-S1 Local factory and retention | building | M0-T03 done (Standard high; Top reviewed) | local_data | Agent 4297c8a reviewed approve scope-only, integrated 3718248. Root full MadarData rerun passed 38 tests in 3 suites (review-local-retention-integrated.log). No CloudKit factory choice; RD2 retains children and old tombstones. M3 arrow UI pending. |
| M0-S1 Model rename compatibility | building | M0-T07 in-progress (Standard high) | local_data | Reuse isolated m0-local-data worktree, new branch m0-s1-money-models from current main. RA4 MoneyTransaction; freeze old schema and staged migration before changing names. Read 17-data and compatibility design note. Old store/archive fixtures preserve IDs/FKs/timestamps/deletions/media. Separate from approved RD2. |
| M0-S2 Lean shell and times | building | M0-T04 needs-fix | unclaimed | Native glass only; hide cut settings, presets and cloud entry. Only built rooms visible. Defaults RD5/RQ8/RL5/RP6. Read 04-arch, 06-flex, 09-r-salah, 18-plan; RA3/8, RL8, RU1/3. Default/AX3 screenshots and meaningful UI checks. |
| M0-S2 Existing UI defects | building | M0-T05 in-progress (Top) | ui_debug | Worktree m0-ui-debug, branch m0-s2-backup-focus. Backup confirmation lost keyboard focus after prior attempts; diagnose real screenshot/log before fix. Root owns simulator and validation. Lock persistence passed. Preserve fixture isolation. Window-level sheet privacy remains required before private content ships. |
| M0-S3 Review and gate | building | M0-T06 todo (Top) | unclaimed | Fresh section reviews, J01–J18 room journey definitions before cited gates, M0 report. Build iPhone prayer times. Physical/signed checks marked not tested until runnable. |

Production tasks start after M0-T01. Separate agents own separate sections/files. No agent may switch this shared checkout's branch while another runs. Use separate managed worktrees for parallel production after a curated baseline exists. Read-only/design jobs may share the checkout. Do not broadly stage `output/`, `tmp/`, generated build products or user data.

# Later

- M1: prayer logging/unconfirmed gap review/excused, correct windows and sanctity, travel methods, independent timetable fixtures, notifications/device checks. Plan 2–4 sections after corrected M0.
- M2 Quran, M3 diary, M4 lobby/habits/widgets, M5 money, M6 Mihbara, M7 integration remain unfinished. No entry points until built.
- Reassess sync after M5. Developer membership, TestFlight and additional platforms await owner setup.
- Encrypted backup already exists; scalability RD4 and window-level privacy need review in the first relevant milestone. Retain code without implying all contracts passed.

# Handovers

## Handover — review files received — 2026-10-10 — root

Done: read all attachments; copied protocol and handoff; extracted 25 sections; RD2 conflict resolved by owner. Earlier automatic prayer aging, multi-process SQLite proof and visible disabled cloud setting now conflict with V1.

Verified: file reads, exact AGENTS/CLAUDE match, current git status (no commits). Earlier logs: services integration v3 passed 10 tests; first services UI run failed 2 tests; fixes exist but rerun pending. These are not current milestone acceptance.

Not verified: full new contract compliance, physical iPhone run, notifications/widgets/Live Activities, actual cloud sync, Quran licenses, real user migration. Prior agents ended with tool-reported usage errors; no reset was consumed.

Current check: updated defaults passed 34 tests, then integrated RA1/RD2 passed 38 tests (Artifacts/review-local-retention-integrated.log). Unfinished M2 QuranRoom.swift is preserved and excluded from M0 target. Lock persistence passed in actual simulator checks. Backup UI still fails matching/export at the first assertion (backup-fixture-check.log); named native-export attachments from that failed flow are failure-state images. Top reviewer requested changes, not acceptance. Fresh diagnostic fix is being tested with failure collection disabled to avoid the previous 600-second diagnostic stall. Production password rules are not weakened.

Baseline snapshot: preserve the inherited app source as a separate local commit to permit isolated branch/worktree review. This is a record of existing implementation, not acceptance of old contracts. Build products, font binaries, output/ and tmp/ stay excluded. Earlier builders' actual model tiers are not inferred from inherited files.

Next: Top architecture note, current build/UI check, then scoped data/inbox fixes. Recommended tiers: Sol xhigh for architecture/reviews; Sol high for production paths. Human instructions remain above attached documents.
