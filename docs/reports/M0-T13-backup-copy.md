# M0-T13 — retained backup count copy

Codex Sol, Standard high, 2026-10-11. Base `b7e5f7c`; branch `codex/m0-backup-copy`. Authority: T13, RU1 and RU3. Applied SwiftUI Expert localization guidance while reusing the existing Customization catalog mechanism.

First fix: restore-result and skipped-preview record phrases now use all six Arabic plural categories in the shipped String Catalog. Fixed expected fixtures cover 0/1/2/3/11/100; the three-record form is «٣ سجلات», with correct singular/dual/many/other forms. The UI retains raw restore-result counts and warnings until rendering, so later numeral presentation can redraw without changing restoration facts. This is transient presentation state, not a persistent schema change. Existing service/status/password/backup payload behavior, DEBUG fixture diagnostics and keyboard test helpers are preserved.

Verified:

```text
xcodebuild -project Madar.xcodeproj -scheme Madar -configuration Debug -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/madar-t13-copy-build CODE_SIGNING_ALLOWED=NO build-for-testing
** TEST BUILD SUCCEEDED **
python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
python3 Madar/scripts/check-number-separators.py
PASS: RU1 app numeric separator source check
git diff --check
(exit 0, no output)
```

Raw build evidence: `Madar/Artifacts/t13-plural-build-for-testing.log` in this worktree. Hosted fixtures are compiled but not executed by this author. Root owns host/UI execution and the simulator. Independent Standard review, actual runtime copy rendering, physical iPhone and the full M0 gate remain unverified. Date/calendar presentation is outside T13 and remains separately tracked.

Second fix: the reachable CustomizeMadar destination passes current `core.numerals` as an injected value. Backup saved-count labels, preview current/saved/addition/update/deletion counts, skipped-record copy and retained restore-result copy use that style. Passwords, warnings, dates, service status facts and backup payloads are untouched; warnings containing `123` remain exactly as received. Restore-result numerals are resolved from raw counts at render time rather than cached in a completed message.

The hosted grammar fixtures now assert every 0/1/2/3/11/100 category explicitly in Arabic-Indic and western styles, including bidi isolates. A separate complete-summary fixture redraws the same 3-restored/11-skipped result in both styles and verifies counts/warnings are unchanged. Added a bounded UI regression `FoundationUITests/test_fixPrevious_M0T13_BackupCountsHonorSelectedNumerals`: two fresh stores, the real selected western setting persisted across relaunch, real backup destination, explicit zero-count labels and retained screenshots. This is numeral-boundary evidence; restore-preview/result runtime flows remain unexecuted here.

Second-fix verification: the first generic build failed with `CustomizeMadar.swift:64: cannot find 'string' in scope`; correcting the reference to `session.string` made the single retry end `** TEST BUILD SUCCEEDED **`. Logs are `Madar/Artifacts/t13-numerals-build-for-testing.log` and `t13-numerals-build-for-testing-retry.log`. Contract88, RU1 and diff checks passed again. A byte-for-byte comparison against `b7e5f7c` passed for the DEBUG keyboard diagnostic block, complete backup-confirmation test and backup Form helpers. No simulator or host tests were run by this author; root validation and independent Standard review remain required before integration.
