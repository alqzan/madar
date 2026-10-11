# M0-T07 — WIP compatibility handover

## Top helper repair — 2026-10-10 19:25 UTC

For the next agent: the narrow helper defect below is repaired; independent fresh Top review and root-baseline integration checks remain required before accepting RA4. Root owns shared `main`, its handover, app build and simulator; this worktree remains on `m0-s1-money-models` and is unmerged.

Reverted the failed symlink/pathComponents helper approach and split the repair from all production migration work. `FileManager.enumerator(atPath:)` supplies relative String keys directly. Every previous source-byte assertion remains; invalid-device rejection now also requires the sole permitted new artifact to be an empty root `CommandBus.lock`. A nested file with that name stays in the comparison. No production source, legacy fixture, schema or expected records changed.

Added `test_M0S1_RA4_fileHashesKeepSourcePathsRelativeAndOnlyExcludeRootLock`, with literal SQLite/sidecar, pointer, stamp, generation metadata and media paths and hard-coded SHA-256 vectors for `hello` and empty bytes. The regression failed against the old helper (four key/exclusion issues), then passed after the repair. It also confirms a metadata-byte change remains detectable after the root-lock exclusion.

Verified (all green commands exit 0):
```
swift test --package-path Madar/Packages/MadarData --filter SchemaCompatibilityTests > /tmp/madar-ra4-helper-focused-20261010-a9d8.log 2>&1
✔ Suite SchemaCompatibilityTests passed after 2.141 seconds.
✔ Test run with 7 tests in 1 suite passed after 2.141 seconds.

swift test --package-path Madar/Packages/MadarData > /tmp/madar-ra4-helper-full-20261010-a9d8.log 2>&1
✔ Suite ManagedBackupTests passed after 8.641 seconds.
✔ Test run with 45 tests in 4 suites passed after 8.642 seconds.
```
`git diff --check` passed. Regression red log: `/tmp/madar-ra4-helper-red-20261010-a9d8.log` (exit 1, expected before repair). Not tested: root-baseline command replay integration, app build, simulator, signed/iPhone run or owner data. Next session: independent reviewer, Top GPT-6.1 Sol xhigh.

## Original Standard WIP record

Recorded 2026-10-10, codex GPT-6.1 Sol Standard high. Do not merge this WIP before the smaller Top repair and independent Top review.

For the next agent: repair only the test helper `SchemaCompatibilityTests.fileHashes` (around line 55). Its derived dictionary keys still include `ManagedV1/`, so excluding exactly `CommandBus.lock` fails even though source stores/pointer/stamps are byte-identical. Two Standard repair attempts (symlink resolution, then pathComponents) were unsuccessful; no further helper attempt was made. Suggested separate Top card: use FileManager.enumerator(atPath:) relative String paths. Tests show the sole remaining failure is the lock-file exclusion expectation at line 118.

Scope: freeze real V1 schema/models, rename current money entity to MoneyTransaction/schema 2, authenticated V1 archive decode before mapping, read-only legacy clones, flat-store adoption, staged managed-generation conversion with safety records/hash and atomic pointer. Device.store stays fixed. Migration journals mark preserveDeviceRows so ordinary restore cleanup does not delete PageSchedule/SessionDraft/ProcessingJob during rename. App flat V1 startup uses selected group directory, and money backup count uses the new tag. Every factory remains local only. Old non-money rows, media, identity/stamps and FK UUID values are preserved.

Verified command: `swift test --package-path Madar/Packages/MadarData --filter SchemaCompatibilityTests > /tmp/madar-ra4-focused.log 2>&1`.
Latest tail:
```
✔ Test test_M0S1_RA4_managedMigrationRecoversAtEveryCommitBoundary(_:) with 3 test cases passed after 1.084 seconds.
✘ Test test_M0S1_RA4_invalidDeviceStampNeverPromotesOrChangesOldSource() recorded an issue at SchemaCompatibilityTests.swift:118:9: Expectation failed: after == hashes
✔ Test test_M0S1_RA4_flatSourceIsByteIdenticalAndNeverOpenedByCurrentFactory() passed after 0.096 seconds.
✘ Test run with 6 tests in 1 suite failed after 2.131 seconds with 1 issue.
```
The three real-oldstore interruption cases (afterCopy/afterStaging/afterPointer), reopening/idempotence and lifecycle-hook recovery passed, preserving all 65 expected rows. Original global-type SQLite reader, authenticated archive conversion and current V2 export also passed. Existing draft before new fixtures/tests passed all 41 package tests; that is not final task acceptance.

Fixture provenance is in Tests/MadarDataTests/Resources/LegacyV1/README.md. It was produced with pre-rename committed code 7c2acad in a disposable package; expected-v2-records.json has four explicit RA4 field/tag deltas only. No owner migration was tested.

App build: `xcodebuild -project Madar.xcodeproj -scheme Madar -destination generic/platform=iOS -derivedDataPath /tmp/MadarRA4-build CODE_SIGNING_ALLOWED=NO build > /tmp/madar-ra4-build.log 2>&1`. First run failed because six ignored thmanyah font binaries were absent in this isolated worktree; no Swift compiler errors were observed. Root fonts are copied only if present, never committed. All six fonts were copied from the root checkout into ignored worktree paths. A retry issued from the wrong cwd did not run an app build (exit 66); root owns the candidate build after Top repair.

Integration: based on 7c2acad. Root must cherry-pick this task only into its current baseline; do not merge backup diagnostic ancestors or replace newer ManagedDataStore receipt-scope/provider changes. Preserve sys.commandReceiptScope and fixed-device receipts; verify inbox replay under renamed-generation recovery on the current root baseline. Pending preexisting RestoreJournal interactions need a targeted Top review. Root owns working handoff HTML/DECISIONS RA4 override (verbatim extracted sections and frozen V1 history remain intact). No simulator run was attempted; root owns simulator. Physical iPhone, owner store migration and signed run remain not tested.

Next session: Top GPT-6.1 Sol xhigh for narrow helper repair, then independent fresh Top schema/migration review and current host/inbox checks before merge.
