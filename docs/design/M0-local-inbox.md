# M0 architecture: local store and PendingInbox

Date: 2026-10-10. Author: Codex, GPT-6.1 Sol xhigh (Top architecture step). Status: design note; implementation and gate remain pending.

Authority: root `AGENTS.md`, `docs/DECISIONS.md`, handoff extracts `16-tech`, `17-data`, `18-plan`, `19-qa`; corrections RA1/RA2/RA3/RA8 and RD2. The owner's current RD2 decision preserves Entry margins and replaces the earlier cascade in `START-M0.md`. Original handoff excerpts remain historical inputs where the corrections override them.

## Keep the foundation; change ownership

Reuse `CommandEnvelope`, `CommandBus`, `DurableCommandAdapter`, `ManagedDataStore`, its generation promotion/recovery, `SettingsStore`, and atomic `SnapshotStore`. Keep existing encrypted backups and model types for compatibility; their existence does not make the removed M0 requirements mandatory. Do not discard models, stores, generations, exports or previous evidence to make M0 smaller.

In v1 every `MadarData` factory configuration is `.none`, including staging, adoption and reopening an existing generation. An old pointer's CloudKit identifier and `core.iCloudSync` preference are readable compatibility metadata, never permission to open a container. Preserve the existing local store locations. Remove production constructors' ability to choose `.private`; do not add iCloud capabilities or account-change work to M0.

Only the application target imports the writable data/command adapter. Extensions link the value envelope, snapshot and inbox modules; their dependency graph must not transitively link SwiftData, `MadarData`, or the store-opening probe. Notification actions delivered to the app may execute the same bus directly. Widget/Control/Live Activity actions always enqueue. There is no fallback from a failed inbox write to SQLite.

## Small transport API

The following are proposed APIs, not declarations that already exist:

```swift
// Foundation/value types only; a separate target from the SwiftData adapter.
struct InboxRecord: Codable, Sendable {
    let transportVersion: Int
    let deliveryID: UUID
    let expectedGenerationID: UUID? // read from the latest app snapshot
    let command: CommandEnvelope
}
struct InboxTicket: Sendable { let deliveryID: UUID; let commandID: UUID }
struct PendingInbox: Sendable {
    func enqueue(_ record: InboxRecord) throws -> InboxTicket
    func claimBatch() throws -> [URL] // called only by the app coordinator
    func acknowledge(_ claimedFile: URL) throws
}
@MainActor final class InboxDrainer {
    func drain() async throws
}
```

`enqueue` is a durable transport acceptance, not an applied `CommandOutcome`. Do not tell the user that the store was saved until the app has applied it. Keep the command ID unchanged on every retry; notification IDs retain the request/action deterministic rule. A delivery ID is only a file identity and never replaces command identity.

Use `AppGroup/PendingInbox/pending/<deliveryID>.jsonl`: one complete JSON record plus LF per immutable file. This is an atomic JSONL spool: adding a command publishes another file. It implements RA2's append without a shared read/modify/write file that two producers can overwrite. Write a unique temporary sibling, synchronize and close it, rename in the same directory, then synchronize the directory. Readers ignore unpublished temporary files. No producer takes the application store lease; no lock or open file spans an actor suspension. The directory layout is an implementation choice, not a new product rule.

The app atomically renames a published file to `processing/`, validates the outer version and strictly validates its unchanged command through the normal bus. On restart it resumes `processing/` before claiming additional files. A single drainer runs at a time. Process batches in a deterministic order using issue time and stable IDs; a pending command never acquires a different day key from the later drain date. Malformed/unknown records move to `quarantine/` with a diagnostic; valid commands in other files still run. I/O errors, protected-data unavailability, `needsUnlock`, `needsApp` and cancellation leave commands recoverable.

After a successful enqueue, a surface may publish a privacy-filtered optimistic projection and request timeline reload. Use a separate pending overlay or a shared serializable file publisher so an extension cannot overwrite the app's canonical snapshot with an older base. This is disposable UI state, keyed by command ID; the store remains authoritative. Rejected commands remove their overlay when the app publishes the authoritative result. Sensitive diary/money payloads will require their mandated authentication and stronger protection when their rooms arrive; M0 does not expose those writes. Before first unlock after reboot, failure remains explicit and device-tested later.

## Transaction and recovery rules

1. Validate a command's structural identity, then look up its durable receipt **before** natural-key/tombstone checks. Reusing an ID with a different name or payload is rejected; never return another operation's success.
2. Under the app's serialized transaction, decide, mutate the domain, and save its receipt in one `ModelContext.save()`. An equal natural-key upsert does not bump the fact's `updatedAt`, but it still records this distinct command ID's duplicate result. Otherwise its later replay can overwrite a newer edit.
3. Finish the existing post-commit sequence: cancel affected prayer requests, regenerate snapshots, reload widget kinds, update allowed indexes, and invalidate affected days. Remove the processing file only after durable commit and successful required refresh. Crash after save or during refresh leaves a file whose retry returns its receipt; it does not apply again. A launch also rebuilds today's snapshots from the store.
4. Keep the seven-day receipt retention and the existing undo windows separate. Do not filter away an on-disk receipt solely because its inverse has expired. Pin dedupe metadata while a pending/processing transport still needs it; purge a receipt only after the transport has durably acknowledged completion. A genuinely ambiguous legacy delivery whose receipt has already been removed must remain unresolved for app review, not be silently treated as a fresh append. No new automatic age limit for valid user commands is introduced by this note.
5. During export/restore, pause the drainer and quiesce app writers. Producers may continue publishing immutable files. The store lease remains useful for app maintenance/recovery, but it no longer coordinates extension SQLite access. Do not hold the inbox publication path while a long backup runs.
6. A restore replaces the data generation while `Device.store` persists. A command carrying the old generation must not be acknowledged by an old device receipt as if its effect exists in the restored generation. Retain it for explicit app resolution; do not automatically replay into the new generation or discard it. Old transport files without a generation need the same safe resolution after a replacement. Clear old optimistic overlays and undo UI on promotion, rebind, rebuild snapshots, and then resume eligible work.

## Deletion and compatibility

`deletionBarrierAt` remains dominant until a deliberate restore with a later `restoredAt`; a normal edit, import or reconciliation cannot revive a row. Merged aliases remain aliases, including after import.

RD2 changes only ownership: deleting Entry keeps its MarginNotes and each note's stored day. Its optional UUID may retain historical provenance to the tombstone; the display resolver offers no arrow to a deleted origin. Deleting Book keeps ReadingSession/Highlight and the title on its tombstone; preserve the existing ReadingSession `bookTitle` snapshot. File deletion remains a separate future room action. Do not automatically revive children previously tombstoned by the old cascade: their deletion provenance is ambiguous and explicit restoration is still required. Shared media is never removed solely because one referring Entry was deleted; a retained live margin is another reference when media ownership is checked.

RA4's `MoneyTransaction` correction must not be implemented by regenerating and opening the current version-1 store with a different entity set. Freeze the old schema as a real version, provide a tested forward conversion, and retain a read-only legacy decode path. Legacy archives use `data/Transaction.jsonl` and exact manifest model sets; authenticate/hash those original bytes first, then map the model name/FK target declarations in the decoded records. Preserve row UUIDs, amounts, currencies, day keys, alias/deletion/restore stamps, media and all non-money rows. Export the new name only in the new format/schema. The present empty migration plan and exact-current-schema backup decoder are insufficient evidence for this conversion.

For existing managed generations, retain the active pointer and fixed device settings/receipts, perform migration in staging with a rollback-safe pointer switch, and test interruption/reopen. Adopt a legacy store only from the chosen isolated directory, never from another Madar application or the global group when a UI fixture directory was selected. A newer store/backup fails closed without writing its schema stamp. Keep the source copy and a verified safety export until row fingerprints/counts match.

## Lean completion plan and required evidence

The root board owns task IDs. Complete three sections: (1) local factory, inbox and replay correctness; (2) RD2/RA4 compatibility plus a simple plain export; (3) native glass shell, only M1 settings/models and prayer/day engines, followed by review/gate. Retain unused existing code behind availability instead of rewriting it. No saved-preset, alternate-tab-style, cloud, or unbuilt-room entry point ships. Plain export uses a versioned manifest and explicit model counts; it is not a copy of live SQLite and does not export device receipts, lock state or installation identity. Existing encrypted export/restore coverage must survive the scoped changes.

Write behavioural fixtures before changing transaction or migration code:

- Two independent producer processes enqueue notification/widget commands while no app store is open; one app drain leaves one PrayerLog. Different command IDs get durable applied/duplicate receipts; same ID replays one result.
- Crash before rename, after claim, after save, before snapshot, and before acknowledgement; retry/reopen loses no accepted command and makes no second domain mutation.
- A duplicate ID after a later conflicting edit remains duplicate; replay after undo/deletion returns its prior receipt without restoring the fact; a mismatched payload under the same ID is rejected.
- Receipt expiry with an unacknowledged delivery, a malformed record beside a valid one, protected-data failure, maintenance contention and duplicate foreground drains.
- Restore while a producer publishes: old-generation commands remain visible for app resolution, new-generation commands apply once; snapshots converge from the committed store.
- Entry deletion retains margins/day keys and suppresses the arrow; Book deletion retains sessions/highlights/title; reconciliation twice makes no further writes; stale live imports cannot resurrect deletions.
- Open a copied version-1 store and restore a copied version-1 encrypted archive through the MoneyTransaction conversion; compare exact user-row fingerprints, UUIDs and media hashes, then reopen and rerun reconciliation. Never point fixtures at owner data.
- Golden MadarDay/Hijri/prayer checks from the cited handoff examples; current lint; app build and package tests; default/AX3 glass-shell screenshots; iPhone prayer-times acceptance and suspended-app widget/notification flow on a physical device.

Verification for this note: source/spec reads and line-level comparison only. No build, package test, simulator flow, physical-device test or migration was run by this reviewer. The root session's independent command output must be attached to its handover; it cannot substitute for unimplemented RA2/RD2/RA4 acceptance.
