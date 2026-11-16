# MadarSync — local lifecycle and persistent history

Swift 6 package, iOS/macOS 27. ManagedSyncAdapter binds the existing
ManagedDataStore; it never creates a second live container. SwiftData contexts
are created and consumed on MainActor. Account checks return Sendable values.

## Root integration

Create ManagedSyncAdapter(manager:checkpointAndSuspend:activate:publishSnapshots:)
and SyncCoordinator(adapter:accountProvider:provisioning:). The activation closure
receives SyncActivationRequest with the old generation, requested account hash,
cloud mode, explicit keep-device/new-account choice, and verified checkpoint.
The device preference is the schema key core.iCloudSync; a preference of true
does not override unavailable provisioning.

The lifecycle closures use the manager's exact CommandBus.lock and maintenance
marker, suspend/drain app writers, verify an encrypted §11 backup, release old
contexts, perform the Data coordinator's atomic generation promotion, rebind the
app, rebuild snapshots and reset history before resuming. Checkpoint file hash
verification supplements (and does not replace) BackupCodec's
decrypt/manifest/count verification. Account identifiers are SHA-256 hashes of
container ID and CloudKit record name; raw names are never logged.

Account choice is required before crossing identities. The destination is checked
again when confirming a choice, since it can change while a sheet is visible.
Returning to the original account, or signing out during a pending choice,
requests a lifecycle activation that releases the pending suspension. The old
generation and checkpoint remain intact if activation fails.

## First account and first cloud attach

The first iCloud account observed for a local store is bound locally, even if the
saved device preference is already on; it does not start mirroring or ask the
person to choose between accounts. A later enable/refresh may attach that same
account to CloudKit. Before the first mirror bind, `AppSyncService` requires a
configured backup key and completes an automatic verified backup. The backup
must finish before `bindCloudMirror`; a missing key or failed export leaves the
mirror unattached. Reopening a store already bound to the same mirror does not
make a redundant backup. `MadarSync` tests verify the first bind stays local;
they do not emulate a signed CloudKit upload.

processHistory() holds the shared lease, refreshes the manager's current binding,
then drains actual SwiftData transactions from fresh contexts. Cursor JSON lives in
a device-only DeviceSetting, scoped by generation and physical storeIdentifier.
Corrupt, unsupported-version or different-generation cursors replay history.
RowMerger reconciles first; snapshots publish second; cursor advances only after
both succeed. Author-filtered cursor/reconciliation writes do not loop forever.
The implementation currently reads retained history to filter per-store tokens;
no unmeasured performance claim or automatic history deletion is made. HistoryDrain
has an OS signpost for profiling on a named Release device.

## Provisioning and cloud boundary

SyncProvisioning defaults to verifiedEntitlements = false. Root must establish
App Group access and verify the running signed target's CloudKit container,
private-database/environment entitlements before setting it true. No CloudKit
account network call occurs when provisioning is unavailable. The owner approved
proceeding with iCloud sync on 15 Nov 2026. The default app build remains local-only;
only a separately configured and signed build can open the CloudKit mirror.
A real mirrored-container teardown, account rotation and cloud delete propagation
are not inferred from opening SQLite again. Data deliberately rejects these
unsupported paths while preserving local stores.

startObserving()/stopObserving() forward CKAccountChanged and completed
NSPersistentCloudKitContainer mirror events. Import events are first queued with
the current generation, then checked under the shared store lease against the
active synced store identifier. A matching success drains SwiftData history so
RowMerger reconciles imported records and snapshots refresh; an empty drain still
reloads and publishes snapshots. If the lease is busy, the pending event is retried
and remains queued for the next ordinary history drain. Events for a stale store
or generation are discarded. Export success is reported only for a genuine event;
local history alone never proves CloudKit import/export. Quota and authentication
errors expose a clear state and allow local writes.

## Evidence, 2026-11-16

- Generic macOS 27, iOS Simulator 27 and watchOS builds succeeded. The CloudKit
  sources compile, but all three build logs use CODE_SIGNING_ALLOWED=NO.
- Sol accepted the Mac, Watch and CloudKit source/build diffs, then accepted Mac
  local runtime on the reported fixture evidence. Codex opened an EPUB fixture and
  a generated one-page PDF in the live Mac app with an isolated synthetic store;
  reader settings, word/quote cards, rendered local Arabic translation, PDFKit
  rendering and PencilKit ink persistence after close/reopen were manually verified.
  This does not verify cross-device restore, WatchConnectivity delivery or CloudKit
  development sync between synthetic stores.
- CloudKit signing failed at the time of this run: no matching Apple Development
  identity for team V8YZL4R65K and no profile for the then-current Mac ID
  `com.alqzan.madar2.mac`; Xcode reported no registered team devices from which
  to generate the profile. The owner later unified the Mac target to
  `com.alqzan.madar2` (see `../../docs/PROGRESS.md`). At the time of this run,
  App Store Connect container/platform state was not verified; macOS was later
  added to record `6830247088`, while the iCloud container remains unverified.
  No development sync or production
  schema deployment occurred; no owner data was opened.
- SwiftData CloudKit compatibility was reviewed at source level: no unique
  constraints or relationships, optional/defaulted fields, optional UUID links,
  and external storage for large attachment data. This is not schema validation.

## Historical test evidence, 2026-10-10

swift build --package-path Madar/Packages/MadarSync succeeded; swift test passed
8 Swift Testing cases on local arm64 macOS using Xcode's Swift 6 SDK:

- Real persistent SwiftData history, cursor persistence across reopen and own-author filtering.
- Sticky tombstone reconciliation and replay after snapshot failure.
- Corrupt cursor and generation mismatch recovery.
- Unprovisioned startup makes zero account calls and preserves a real PrayerLog.
- Encrypted BackupCodec checkpoint round-trip, excluding DeviceSetting rows.
- Destination changed while choice is visible is rejected; returning to A releases pending work.
- Shared maintenance marker blocks history access; tampered checkpoint/preflight rejection.

Evidence log: /tmp/madar-sync-tests.log. Probe activation tests verify protocol
decisions only; they deliberately do not open a CloudKit store. Untested at that
time: real CloudKit import/export, quota exhaustion, paid signing/provisioning,
two physical devices, account replacement with a live mirror, remote delete
propagation, Release launch/scroll performance, and iOS background history scheduling.
