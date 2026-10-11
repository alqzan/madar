# M0-T07 — RA4 compatibility section review

Verdict: **approve** for the scoped RA4 implementation and fixes. M0R4-01/02/03 are closed; no new findings in the fix diff. Required current app-host inbox migration checks remain unverified, so this approval does not mark full RA4 acceptance or the M0 gate complete.

## Fix-only re-review — 2026-10-11

Reviewed only `42cd6e6..c0502c1`, commit by commit, with the new regressions and `docs/reports/M0-T07-review-fixes.md`:

- **M0R4-01 closed in `68af424`:** existing restore journals are validated before conversion. The pending cleanup obligation is persisted in SchemaMigration.json before migration replaces its hooks journal, and survives copy/staging/hooks-journal/pointer interruption and reopen. Committed ordinary restores clear schedules/drafts/jobs; uncommitted restores preserve device rows and remove abandoned staging. Mismatched journal IDs reject without source/pointer changes. Receipts remain preserved.
- **M0R4-02 closed in `dfe3923`:** flat adoption preflights the chosen device stamp before target/journal writes and rechecks under the read lease. Newer, zero, negative and malformed stamps reject with byte-identical sources and absent targets/journals; an absent stamp remains compatible.
- **M0R4-03 closed in `c0502c1`:** preview display counts derive from converted records, while the validated original manifest, V1 Transaction path and hashes remain unchanged. The authenticated V1 transaction-only fixture shows two MoneyTransaction rows; V2 counts remain unchanged.

Inspected the implementation's exact full-run output `/tmp/madar-ra4-fixes-full.log` (reported exit 0):

```
✔ Suite ManagedBackupTests passed after 12.161 seconds.
✔ Test run with 49 tests in 4 suites passed after 12.161 seconds.
```

No full review or test run was repeated for this fix-only pass. `git diff --check` passed. **Still required before full RA4 acceptance:** root app-host verification of current structured `sys.commandReceiptScope:<receipt UUID>` namespaces and pinned old-generation pending transports across V1 migration, including pending restore cleanup. That test has not been implemented or run. App build/simulator/owner-device boundaries remain as recorded below.

Independent review of `a4b3a4a..b3a809d`, read commit by commit (`c99659a`, `65ac6ec`, `b3a809d`). Scope: M0-T07 card, RA4, the compatibility contract in `docs/design/M0-local-inbox.md`, and §11/17-data schema/backup rules. Generated/frozen model bodies were excluded from semantic review; provenance was verified. No owner data, simulator, shared-root branch or production source was modified.

## Original findings — all closed by the fix-only pass above

1. **M0R4-01 — High — Preserve pending restore cleanup across schema migration.** [LegacyGenerationMigration.swift:82](</Users/abdulrahman/.codex/worktrees/m0-arabic-plurals/بناء مدار 2.0/Madar/Packages/MadarData/Sources/MadarData/LegacyGenerationMigration.swift:82>) unconditionally overwrites `RestoreJournal.json` with `preserveDeviceRows:true`, before `ManagedDataStore.init` calls `recoverInterruptedOperation`. When the last V1 restore already promoted its pointer but died before its hooks, its schedules/drafts/jobs still refer to the replaced facts. Migration loses that restore's cleanup obligation; `recoverPendingLifecycle()` then succeeds, skips all three deletions and removes the journal. Reproduced with the frozen V1 fixture and a committed V1 restore journal: PageSchedule=1, SessionDraft=1, ProcessingJob=1 after recovery, where all three must be zero. **Fix:** validate/settle existing restore journal state before conversion, or carry its pending cleanup obligation into the migrated generation. Preserve device rows only when no committed ordinary restore still requires invalidation. Cover preparing/ready before promotion, committed after-pointer/after-hooks, mismatched journal rejection, migration interruption/reopen, and a regression named `test_M0S1_RA4_pendingCommittedRestoreRetainsRequiredInvalidation`.

2. **M0R4-02 — High — Reject unsupported flat device-store versions before adoption.** [ManagedDataStore.swift:72](</Users/abdulrahman/.codex/worktrees/m0-arabic-plurals/بناء مدار 2.0/Madar/Packages/MadarData/Sources/MadarData/ManagedDataStore.swift:72>) checks only the synced version. `LegacyV1Reader` ignores `DeviceSchemaVersion.json`, and the new target receives a fresh V1 stamp. A flat V1 synced store with device stamp 999 is silently accepted and promoted, unlike the equivalent managed source. This bypasses the version barrier and can decode a future device store through frozen V1 types, dropping unsupported fields/records in the adopted target. Reproduced with fixture stamp 999: adoption returned `ManagedDataStore` instead of `DataError.newerStore`. **Fix:** preflight the source device stamp using the same supported range as managed migration before reading or publishing any target. Cover newer, invalid and malformed stamps with source-byte/pointer equality and no adopted target; retain absent-stamp compatibility. Add `test_M0S1_RA4_flatAdoptionRejectsNewerDeviceSchema`.

3. **M0R4-03 — Medium — Show migrated transaction counts in legacy-backup preview.** [AppBackupService.swift:108](</Users/abdulrahman/.codex/worktrees/m0-arabic-plurals/بناء مدار 2.0/Madar/App/AppBackupService.swift:108>) now sums only `MoneyTransaction`, but `BackupCoordinator.preview` returns the original authenticated V1 manifest counts, whose key is `Transaction`. Decoded rows are converted, so the preview understates money records by the old transaction count and hides the room for a transaction-only archive. **Fix:** use counts derived from validated converted records for the current-schema preview, or map a separate display-count dictionary; preserve the original manifest and hashes for authentication. Verify a V1 transaction-only archive shows its actual saved money count and V2 counts remain unchanged.

## Verified

`swift test --package-path Madar/Packages/MadarData > /tmp/madar-ra4-independent-review-data.log 2>&1` — exit 0:

```
✔ Suite ManagedBackupTests passed after 9.170 seconds.
✔ Test run with 45 tests in 4 suites passed after 9.170 seconds.
```

Temporary fixture-only probes, removed from the worktree after execution; source is `/tmp/madar-ra4-independent-review-probe.swift`. `swift test --package-path Madar/Packages/MadarData --filter ReviewProbeTests > /tmp/madar-ra4-independent-review-probes.log 2>&1` — exit 1, expected red evidence:

```
✘ Test test_M0S1_RA4_pendingCommittedRestoreRetainsRequiredInvalidation() failed after 0.379 seconds with 3 issues.
✘ Test test_M0S1_RA4_flatAdoptionRejectsNewerDeviceSchema() failed after 0.103 seconds with 1 issue.
✘ Test run with 2 tests in 1 suite failed after 0.482 seconds with 4 issues.
```

Provenance: all four fixture SHA-256 values match README; frozen V1 retains all 61 original model property bodies and all 61 record/apply bodies exactly from committed `7c2acad` (only namespace/extension placement changes). Expected V2 fixture has 65 rows and exactly four explicit name/tag deltas; no timestamp, UUID, foreign-key value or media delta. All three dictionary copies differ structurally only by RA4 model-name replacement. `git diff --check` passed.

Archive mapping happens after original AES-GCM authentication, exact V1 model-set/path/count checks and original file hashes. Source generations and flat stores are read through clones; existing tests prove original synced/flat bytes unchanged at covered checkpoints and rejection of a newer managed device stamp. These passing paths do not cover the findings above.

## Current inbox compatibility and remaining evidence

The unchanged current adapter checks preserved per-receipt `sys.commandReceiptScope:<receipt UUID>` namespaces against the active generation and returns `needsApp` for old/unknown scope even when an envelope carries today's stamp. Current inbox generation rejects old-generation transport, and receipt collection pins unresolved command IDs. Migration reads every device row and reopens the fixed `Device.store`, preserving rows and identities. No automatic reapply or receipt deletion was found in those paths. The fixture has an older unsuffixed `sys.commandReceiptScope` string, so it does not itself prove current structured scope plus pinned transport integration.

Not tested by this reviewer: app build, simulator/UI flows, V1 preview UI count, current host inbox replay through migrated-generation recovery, signed/iPhone run, or owner store migration. Root owns those checks after the fixes. This is a scoped section review, not the M0 gate.
