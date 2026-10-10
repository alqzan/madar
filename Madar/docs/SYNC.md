# MadarSync — local lifecycle and persistent history

Swift 6 package, iOS/macOS 26. `ManagedSyncAdapter` binds the existing
`ManagedDataStore`; it never creates a second live container. SwiftData contexts
are created and consumed on MainActor. Account checks return Sendable values.

## Root integration

Create `ManagedSyncAdapter(manager:checkpointAndSuspend:activate:publishSnapshots:)`
and `SyncCoordinator(adapter:accountProvider:provisioning:)`. The activation closure
receives `SyncActivationRequest` with the old generation, requested account hash,
cloud mode, explicit keep-device/new-account choice, and verified checkpoint.
The device preference is the schema key **core.iCloudSync**; a preference of true
does not override unavailable provisioning.

The lifecycle closures must use the manager's exact CommandBus.lock and maintenance
marker, suspend/drain app writers, verify an encrypted §11 backup, release old
contexts, perform the Data coordinator's atomic generation promotion, rebind the
app, rebuild snapshots and reset history before resuming. Device.store stays
outside generations. Checkpoint file hash verification supplements (and does not
replace) BackupCodec's decrypt/manifest/count verification. Account identifiers are
SHA-256 hashes of container ID and CloudKit record name; raw names are never logged.

Account choice is required before crossing identities. The destination is checked
again when confirming a choice, since it can change while a sheet is visible.
Returning to the original account, or signing out during a pending choice,
requests a lifecycle activation that releases the pending suspension. The old
generation and checkpoint remain intact if activation fails.

`processHistory()` holds the shared lease, refreshes the manager's current binding,
then drains actual SwiftData transactions from fresh contexts. Cursor JSON lives
in a device-only DeviceSetting, scoped by generation and physical storeIdentifier.
Corrupt, unsupported-version or different-generation cursors replay history.
RowMerger reconciles first; snapshots publish second; cursor advances only after
both succeed. Author-filtered cursor/reconciliation writes do not loop forever.
The implementation currently reads retained history to filter per-store tokens;
no unmeasured performance claim or automatic history deletion is made. HistoryDrain
has an OS signpost for profiling on a named Release device.

## Provisioning and cloud boundary

`SyncProvisioning` defaults to `verifiedEntitlements = false`. Root must establish
App Group access and verify the running signed target's CloudKit container,
private-database/environment entitlements before setting it true. No CloudKit
account network call occurs when provisioning is unavailable. The present owner
workflow is iPhone-only and the paid Apple Developer subscription is deferred;
cloud mirroring remains unavailable. A real mirrored-container teardown, account
rotation and cloud delete propagation are not inferred from opening SQLite again.
Data deliberately rejects these unsupported paths while preserving local stores.

`startObserving()`/`stopObserving()` forward CKAccountChanged. SwiftData history is
not evidence of a cloud import/export. Root may call `observeCloudImportSuccess`
and `observeCloudExportSuccess` only for a genuine observed mirror event. Without
one the UI says «لا معلومات عن آخر مزامنة». Quota and authentication errors expose
a clear state and allow local writes. No remote-update event bridge is fabricated.

## Evidence, 2026-10-10

`swift build --package-path Madar/Packages/MadarSync` succeeded; `swift test` passed
8 Swift Testing cases on local arm64 macOS using Xcode's Swift 6 SDK:

- Real persistent SwiftData history, cursor persistence across reopen and own-author filtering.
- Sticky tombstone reconciliation and replay after snapshot failure.
- Corrupt cursor and generation mismatch recovery.
- Unprovisioned startup makes zero account calls and preserves a real PrayerLog.
- Encrypted BackupCodec checkpoint round-trip, excluding DeviceSetting rows.
- Destination changed while choice is visible is rejected; returning to A releases pending work.
- Shared maintenance marker blocks history access; tampered checkpoint/preflight rejection.

Evidence log: `/tmp/madar-sync-tests.log`. Probe activation tests verify protocol
decisions only; they deliberately do not open a CloudKit store. Untested: real
CloudKit import/export, quota exhaustion, paid signing/provisioning, two physical
devices, account replacement with a live mirror, remote delete propagation,
Release launch/scroll performance, and iOS background history scheduling.
