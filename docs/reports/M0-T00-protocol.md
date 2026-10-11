# M0-T00 protocol reconciliation

2026-10-11. Scope: contracts/docs only; RA4 has a separate migration acceptance report.

Root and app AGENTS/CLAUDE are identical. Review V1 is installed beside the bundle. The 25 section extracts match their original indexed SHA-256 values; they are historical text inputs, with Review V1 and DECISIONS precedence. Output source copies remain untouched.

Before-M0 corrections: RD2 owner retention is reflected in accepted data tests; RD5 keyboard first, RP6 heart off, RL5 activities off, RQ8 tafsir off/licence gate and RMI1 hints off/v2 exist in all three settings copies. The stale activity note now agrees with RL5. RA8 cut keys remain v2. RA5 has explicit J01–J18 procedures, states/device requirements, and the working HTML reconciliation count is eight. RA6 owner runbook exists; these instructions do not imply external setup was completed. RA4 is tracked independently in T07; no model rename is accepted by this document.

HANDOFF's working dictionary now records the already implemented deletionBarrierAt/restoredAt, sourceBranch and receipt undo metadata from Runtime v3. This is documentation parity, not a new persistence field or a migration. The frozen extracts and source copies remain unchanged.

`python3 Madar/scripts/check-review-contracts.py` → `PASS: 86 amended contract checks (read-only; device acceptance not tested)`. The optional `--require-ra4` adds rename checks after T07 integration. This bounded lint verifies protocol equality, frozen extracts, settings copy equality/defaults/availability, runtime dictionary copy equality, journey presence, count and board/runbook structure. It is not a full colour/string/UI lint or proof of a room flow.

Quick check on a4b3a4a before these documentation edits: app simulator build `BUILD SUCCEEDED`; hosted `Executed 16 tests, with 0 failures`, `TEST SUCCEEDED`; Core21, Data38, Commands17, Inbox6, Prayer12, Snapshots3, Sync8 all passed. Raw logs: Madar/Artifacts/run2-*. No physical iPhone, owner data, license confirmation, notification/widget device flow, whole-M0 gate or deployment tested here.
