# M0-T07 — M0R4 review fixes

Codex Sol, Standard high, 2026-10-11. Candidate worktree: `/Users/abdulrahman/.codex/worktrees/m0-arabic-plurals/بناء مدار 2.0`, branch `m0-s1-money-integration`, based on reviewed `42cd6e6`. Only M0R4-01/02/03 from `docs/reviews/M0-money-models.md` were fixed. Root owns PROGRESS/main handover and integration; independent fix-only Top review remains required.

- M0R4-01 (`68af424`): read and validate any pre-existing restore journal before conversion. A committed ordinary restore still requires schedule/draft/job invalidation; an uncommitted restore preserves device rows and its abandoned staging is removed. Save this obligation in SchemaMigration.json before replacing the hooks journal. It survives migration interruption after copy, staging, hooks-journal write before pointer promotion, and pointer promotion. Mismatched restore IDs are rejected before migration writes. Two permanent regression tests went from 22 red issues to green; all source generation bytes and command receipts remain preserved.
- M0R4-02 (`dfe3923`): shared device-version preflight checks the chosen flat source before adoption writes its target/journal, and rechecks while reading. Newer/zero/negative/malformed stamps reject; absent stamp remains compatible. The permanent regression went from 10 red issues to green and checks source hashes plus absent target/journal.
- M0R4-03: preview display counts derive from converted records. The validated original V1 manifest, Transaction path and hashes remain unchanged. A synthetic AES-GCM authenticated transaction-only V1 archive contains exactly 2 transactions; its preview now shows 2 MoneyTransaction rows. The permanent regression went from 2 red issues to green and also verifies V2 counts are unchanged.

Exact scoped commands:

```text
swift test --package-path Madar/Packages/MadarData --filter M0R4_01
✔ Test run with 2 tests in 1 suite passed after 3.390 seconds.
swift test --package-path Madar/Packages/MadarData --filter M0R4_02
✔ Test run with 1 test in 1 suite passed after 0.216 seconds.
swift test --package-path Madar/Packages/MadarData --filter M0R4_03
✔ Test run with 1 test in 1 suite passed after 0.434 seconds.
swift test --package-path Madar/Packages/MadarData
✔ Suite ManagedBackupTests passed after 12.161 seconds.
✔ Test run with 49 tests in 4 suites passed after 12.161 seconds.
```

Each green implementation passed first attempt. The preceding red runs were intentional reproduction tests, not failed repair attempts. Raw local evidence: `/tmp/madar-ra4-fix01-red.log`, `/tmp/madar-ra4-fix01-green.log`, analogous fix02/fix03 files, and `/tmp/madar-ra4-fixes-full.log`. `git diff --check` is clean.

Not tested here: app build, simulator/physical iPhone, preview UI rendering, signed/device gates, real owner migration, or the proposed app-host current structured receipt namespace + pending transport test across V1 migration. The root cancelled that extra test before implementation because the weekly usage limit reached 99%; no host-test WIP exists. Existing frozen fixture has only the older unsuffixed receipt scope. Root should carry this integration gap forward explicitly.

## Root integration acceptance — 2026-10-11

Fresh Top fix-only approval c45a953 closes M0R4-01/02/03. New current namespace/pinned-transport app-host regression2fc39ab passed on candidate (`test_M0S1_RA4_CurrentReceiptScopeAndPendingTransportSurviveMigration`,1.150s); full hosted17tests0failures / TEST SUCCEEDED. Integrated production+test changes into current baseline cb57e68 without conflicts or diagnostic ancestors. Root rerun: MadarData49tests4suites passed13.143s; Commands17tests2suites passed1.192s; signed simulator app+host17tests0failures / TEST SUCCEEDED; contract lint with --require-ra4:88checks passed. Logs Madar/Artifacts/run3-integrated-{data,commands,host}.log and run3-ra4-host-candidate.log.

The host regression uses a synthetic V1 store: exact per-receipt namespace and expired receipt survive; queued old-generation and same-ID/new-generation deliveries remain unresolved with unchanged fact/receipt; a fresh new-generation command applies once, replays and reopens with stable fingerprints. Migration source/archive fixtures remain independent committed pre-rename captures. These checks accept scoped RA4 software compatibility, not owner-data migration, physical iPhone protection, actual extensions or the full M0 gate.
