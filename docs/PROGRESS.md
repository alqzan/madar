# Current milestone

M0 — reconciliation with review V1, before accepting the existing foundation. Full software objective M0–M7 remains active, iPhone first. Original handoff and earlier app work are preserved. M1 files exist as unintegrated scaffolding; later rooms are not complete.

# Last checked

Protocol installed in 9386ea7. No commits existed before receiving it. Checked the attachments and working-tree contracts on 2026-10-10; owner adopted RD2. Current MadarData baseline: 34 tests passed. Current simulator app compiled; whole-app lock test passed. Backup UI test failed to focus the confirmation field. Reconciliation and this UI defect remain open; no M0 gate passed.

# Board

| Section | Status | Task | Owner | Scope and acceptance |
|---|---|---|---|---|
| M0-S0 Protocol and contracts | building | M0-T00 in-progress | root | Install protocol/fixes, 25 plain-text sections, decisions, owner runbook. Correct Before-M0 JSON only in the working copy, preserve source. RA4/5/6/9, RD2/5, RMI1, RQ8, RL5, RP6. |
| M0-S0 Architecture | building | M0-T01 in-progress (Top) | architecture_review | Fresh design note: local single-writer/inbox, stale receipts, tombstones, safe export/restore and existing stores. Read 16-tech, 17-data, 18-plan, 19-qa; RA1/2/3/8 and RD2. Must review before production changes to these paths. |
| M0-S1 Local data and commands | building | M0-T02 todo (Standard high) | unclaimed | Factory never opens CloudKit, no extension SQLite, atomic JSONL inbox and app drain, receipt replay. Read 16-tech, 17-data, 15-outside; RA1/2. Tests independent concurrent producers and retry-after-save. |
| M0-S1 Data corrections | building | M0-T03 todo (Standard high) | unclaimed | RD2 row-merger preserves margins/sessions/highlights; RA4 MoneyTransaction migration preserves old stores/backups. Read 17-data, 10-r-notes; RD2/RA4. Behavioral and migration fixtures before acceptance. |
| M0-S2 Lean shell and times | building | M0-T04 needs-fix | unclaimed | Native glass only; hide cut settings, presets and cloud entry. Only built rooms visible. Defaults RD5/RQ8/RL5/RP6. Read 04-arch, 06-flex, 09-r-salah, 18-plan; RA3/8, RL8, RU1/3. Default/AX3 screenshots and meaningful UI checks. |
| M0-S2 Existing UI defects | building | M0-T05 needs-fix | root | Rerun backup keyboard and lock accessibility tests after existing fixes; document results, preserve fixture isolation. Window-level privacy for presented sheets remains a future required fix. |
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

Current check: MadarData baseline passed 34 tests (Artifacts/review-data-baseline.log). First UI rerun could not start: unfinished M2 QuranRoom.swift references missing QuranSettingsUIService. Preserved that scaffold and excluded it from the M0 app target (project.yml); no placeholder service or visible room was added. Second run compiled and passed whole-app lock persistence; backup test failed at confirmation keyboard focus (Artifacts/review-ui-fixed.log). This is a Top debugging card after earlier UI fix attempts; no rollback to a nonexistent old green commit.

Baseline snapshot: preserve the inherited app source as a separate local commit to permit isolated branch/worktree review. This is a record of existing implementation, not acceptance of old contracts. Build products, font binaries, output/ and tmp/ stay excluded. Earlier builders' actual model tiers are not inferred from inherited files.

Next: Top architecture note, current build/UI check, then scoped data/inbox fixes. Recommended tiers: Sol xhigh for architecture/reviews; Sol high for production paths. Human instructions remain above attached documents.
