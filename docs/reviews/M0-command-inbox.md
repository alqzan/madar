# M0 command inbox — scoped section review

**Current scoped verdict: approve at `9db4191` for transport/data code only.** The dated findings and earlier verdicts below remain as review history. AppSession lifecycle integration and the physical M0 gate are separate.

Verdict: **changes requested**. Fresh Codex reviewer, Top review task, 2026-10-10 18:53 UTC. Reviewed commit `846e1bb` on `m0-s1-command-inbox`, with inherited baseline `7a79d0f` after protocol `9386ea7`. Scope: M0-T02 and M0R-03–06; RA2; `docs/design/M0-local-inbox.md`; the command/inbox/receipt passages of `15-outside`, `16-tech`, `17-data`. This does not approve all M0-S1 or the M0 gate.

## Findings

| ID | Severity | Location | Finding and required fix |
|---|---|---|---|
| M0I-01 | High | `Madar/Packages/MadarInbox/Sources/MadarInbox/PendingInbox.swift:67` | Publication exclusivity applies only to `pending`. Once a delivery is in `processing`, `enqueue` accepts the same `deliveryID` again. The next `claimBatch` hits `EEXIST` at line 70 and throws before returning the resumed files, permanently blocking the entire inbox, including unrelated valid neighbors. Reproduced with both same-ID publications returning success and two consecutive consumer runs failing `duplicateDelivery`. Handle cross-folder delivery collisions without aborting the batch. Preserve both accepted records when their contents differ; identical content may be resolved only against the actual command identity/committed outcome. Do not overwrite/delete a conflicting accepted record. Add `test_M0S1_deliveryCollisionDoesNotBlockNeighbors` covering identical retry, conflicting command payload/ID, concurrent publication during claim, restart, and a valid neighbor. |
| M0I-02 | High | `Madar/Packages/MadarCommands/Sources/MadarCommands/InboxDrainer.swift:57` | Generation checks scope the transport stamp and completion marker, but the receipt replay at `DurableCommandAdapter.swift:77` is unscoped. After replacing the domain generation while retaining `Device.store`, a repeated deterministic notification command ID can be stamped from the new snapshot. It passes `active.permits`, replays the old generation's `applied` receipt, creates a new generation completion marker, and is acknowledged even though the restored domain has no corresponding fact. The existing test only rejects old/absent transport stamps; it never checks this new-stamped retry against a retained old receipt. Reproduced with one old fact/receipt, synthetic domain replacement omitting that fact, and the same command ID under a new generation: final rows=0, receipts=1, refreshes=1, unacknowledged=0, new-generation completion marker present. Namespace durable receipt identity by the generation in which its effect committed, and retain conflicting/unknown scope for resolution before replay/acknowledgement. Existing device-local metadata or versioned receipt blobs can carry this without adding a model field. Record the namespace in the same `ModelContext.save()` as mutation and receipt, so crash-before-refresh/completion-marker is safe; guard inherited receipts without scope. Add `test_M0S1_newGenerationCannotReplayOldReceipt`, including the save-before-refresh interruption. Never silently delete the receipt or reapply into the replacement generation. |
| M0I-03 | Medium | `Madar/Packages/MadarCommands/Sources/MadarCommands/InboxDrainer.swift:60` | An unknown command from `.widget` is returned by the bus as `needsApp` (`Commands.swift:104`) before its command-name switch, so it remains in `processing` indefinitely instead of being quarantined as the architecture requires for unknown records. Reproduced `unknown.command` with a valid envelope: consumer succeeds with rows=0, receipts=0, unacknowledged=1, processing=1, quarantine=0. Validate the command registry/name before authorization disposition, distinguish valid app-only commands from unknown/unavailable commands, quarantine unknowns with a fixed diagnostic, and keep genuine `needsApp`/`needsUnlock` deliveries recoverable. Add a regression beside a valid neighbor. |

Critical/High findings block merge. Keep the accepted source files and original command IDs; do not resolve collisions by arbitrary last-writer selection. After fixes, re-review only the fix diff and regression evidence.

## Verified by this reviewer

Commands executed in the isolated implementation worktree; no owner data was opened.

```text
swift test --package-path Madar/Packages/MadarCommands
✔ Test run with 11 tests in 2 suites passed after 0.453 seconds.

swift test --package-path Madar/Packages/MadarInbox
✔ Test run with 5 tests in 1 suite passed after 0.005 seconds.

python3 Madar/scripts/inbox-process-test.py
"producerStoreFiles": 0, "producerLinksSwiftData": false,
"deliveries": 3, "commandIDs": 2,
"counts": {"receipts": 2, "refreshes": 3, "rows": 1,
           "statuses": ["applied", "duplicate"], "unacknowledged": 0},
"passed": true

git diff --check
(no output)
```

Additional reproductions used the compiled production `MadarInboxProducer`/`MadarInboxConsumer` executables against disposable temporary directories:

1. Collision: publish A; move its file from `pending` to `processing` to model a completed claim/interruption; publish A again with the same delivery ID, then publish valid neighbor B. All three enqueue processes exited 0. Two consecutive drains failed `MadarInbox.InboxError.duplicateDelivery`; pending=2, processing=1. This confirms no recoverable resumed batch reaches execution.
2. Generation scope: drain old-generation A; remove only the synthetic fixture's `ZPRAYERLOG` domain row while retaining `Device.store`; republish the same deterministic command ID with a fresh delivery ID and new generation. Before: rows=1, receipts=1, refreshes=1, unacknowledged=0. After: rows=0, receipts=1, refreshes=1, unacknowledged=0; the new generation marker exists. This is a controlled domain-replacement fixture, not an actual restore/pointer-switch test.
3. Unknown name: publish a valid widget envelope, replace its command name with `unknown.command` in the fixture, then drain. Final: rows=0, receipts=0, refreshes=0, unacknowledged=1, processing=1, quarantine=0.

The existing passing tests meaningfully verify durable duplicate receipts, replay before tombstones, payload/name identity mismatch, retained receipt replay after expiry/reopen, refresh failure and cancellation recovery, malformed JSON neighbors, protection/maintenance gating, and duplicate drainer serialization. The producer dependency graph and link check keep the producer free of SwiftData/CoreData; the widget target still links snapshot data only. Preserve those improvements.

## Not tested / ownership boundary

No simulator, app lifecycle flow, UI/dark/AX3 comparison, iPhone, physical suspended-app notification/widget action, before-first-unlock protection, kill-at-fsync checkpoint, actual restore with a concurrent producer, or new app build was run by this reviewer. The branch's earlier app build evidence was read but is not a newly executed reviewer check. Root owns the app/session runtime flows and section integration. This review changed only this review document; no production source, branch, commit, or merge was changed.

## Fix-only re-review — 66d9af2, 653b9e6, 17db156

Verdict: **changes requested**. 2026-10-10. Reviewed only the three fix commits atop `846e1bb` and their new regression fixtures. This verdict concerns data/transport code; AppSession host integration and cold/foreground lifecycle are independently pending.

- **M0I-01 resolved:** claim collision handling now preserves both immutable records under physical suffixes, leaves logical delivery/command IDs intact, and returns resumed/neighbor records. Read/GC/quarantine support the suffix, including restart and conflicting records. The command and transport collision regressions pass.
- **M0I-03 resolved:** one implemented-name registry is checked before authorization, so unknown/later command names quarantine while valid app-only and locked prayer commands remain recoverable. The neighbor regression passes.
- **M0I-02 partly resolved, still High:** existing `DeviceSetting.valueJSON` stores a versioned namespace associated with receipt row ID. Namespace, fact and receipt are inserted into the same context before its single save. Old-generation/inherited-unknown receipts fail closed, including interrupted save-before-refresh and reopen. No model field was added. However, `DurableCommandAdapter.swift:275` removes that namespace with seven-day receipt GC, while `InboxDrainer.swift:59` checks completion provenance only for the active generation. An old completed marker survives GC in the old generation. A new-stamped retry of its same deterministic notification command ID then has neither a receipt nor an active-generation marker, and re-applies stale data to the replacement generation.

Required remaining fix for M0I-02: inspect retained provenance across generations before execution when a scoped receipt is absent (or retain equivalent lightweight namespace metadata after receipt collection). A matching old-generation command identity must remain unresolved; a newly authorized action with a fresh command ID remains eligible. Preserve the namespace at the save-before-refresh interruption boundary. Add a regression with virtual receipt expiry/GC, generation replacement excluding the old fact, same deterministic ID stamped with the new generation, and a fresh-ID neighbor. Do not classify the old ID as a fresh action solely because its transport stamp is current.

Fresh reviewer evidence:

```text
swift test --package-path Madar/Packages/MadarCommands --filter test_M0S1
✔ Test run with 5 tests in 1 suite passed after 0.296 seconds.

swift test --package-path Madar/Packages/MadarInbox --filter test_M0S1_deliveryCollisionDoesNotBlockNeighbors
✔ Test run with 1 test in 1 suite passed after 0.008 seconds.
```

Additional compiled-CLI fixture at `17db156`: seed and acknowledge old-generation A; remove only the temporary domain fact and the temporary device receipt/scope rows to model replacement plus the inspected GC deletion; leave the old completion marker; resend the same notification command ID with a fresh delivery and new generation. Before: rows=1, receipts=1, refreshes=1, unacknowledged=0. After: rows=1, receipts=1, refreshes=1, unacknowledged=0; both old and new completion markers exist. The old fact was recreated and the delivery acknowledged. This is controlled synthetic deletion equivalent to the relevant GC/replacement effect, not an actual timed purge, restore or pointer-switch run.

No further Critical/High finding was found in the reviewed collision/name fix diff. No simulator or production mutation was performed. Full package/process reruns being completed by the fixer do not cover the remaining expiry-plus-replacement case until its new fixture exists.

## Final fix-only re-review — 9db4191

Verdict: **approve**, scoped to the inbox transport/data implementation through `9db4191`. Fresh reviewer check on 2026-10-10 19:05 UTC. Reviewed only `17db156..9db4191`; no unchanged implementation was reviewed again.

**M0I-02 resolved.** When a receipt is absent, the drainer now checks persisted completion provenance across all generations before executing. A current snapshot stamp cannot convert the same old command ID into a fresh action. The record remains unresolved, while a new command ID remains eligible. Existing scoped receipt replay retains priority for save-before-refresh recovery. Completion metadata validates its version, command ID and generation filename before it is trusted. No model/schema field was added, and the earlier same-context receipt namespace save remains intact.

The new `test_M0S1_newGenerationCannotReplayCollectedReceipt` uses the actual `purgeExpiredReceipts` method with virtual time and the production `BackupCoordinator.rotateLocalStore` staging/pointer switch, retaining the same `Device.store`. It proves the old-ID/new-stamp retry leaves the replacement domain empty, creates no replacement receipt/marker, stays unresolved and performs no refresh. A fresh-ID neighbor subsequently creates one fact and its receipt without resolving the old delivery. This replaces the previous manually deleted-row reproduction with meaningful production-path regression evidence.

Executed by this reviewer:

```text
swift test --package-path Madar/Packages/MadarCommands --filter 'test_M0S1_newGenerationCannotReplayCollectedReceipt|test_M0S1_scopedReceiptReopensAfterSaveBeforeRefresh|test_M0R06_pendingPinsExpiredReceiptAndAcknowledgedRetryIsUnresolvedAfterGC'
✔ Test test_M0R06_pendingPinsExpiredReceiptAndAcknowledgedRetryIsUnresolvedAfterGC() passed after 0.075 seconds.
✔ Test test_M0S1_scopedReceiptReopensAfterSaveBeforeRefresh() passed after 0.044 seconds.
✔ Test test_M0S1_newGenerationCannotReplayCollectedReceipt() passed after 0.360 seconds.
✔ Test run with 3 tests in 1 suite passed after 0.479 seconds.

git diff --check
(no output)
```

All three original findings are closed; no remaining Critical/High blocker was found in this scoped fix diff. The root separately reports all 17 Commands/6 Inbox tests and the process proof green, plus 14 simulator app-host tests (including four AppSession flows) in its validation worktree at `0519cfa`; those runs were not executed by this reviewer. Root must perform its final integration/lifecycle checks after merging. This scoped approval does not claim physical suspended-app notification/widget behavior, protected-data device checks, a signed iPhone build, UI parity or the M0 gate. No production source, branch, commit, merge or simulator was changed by this reviewer.
