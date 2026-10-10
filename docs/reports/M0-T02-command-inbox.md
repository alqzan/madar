# M0-T02 — app-only command inbox

Implementation tranche, Codex Standard high, 2026-10-10. This is not an M0 gate or section approval. Contracts: RA2; `docs/design/M0-local-inbox.md`; `16-tech.md` command/inbox rules; `17-data.md` receipt fields; findings M0R-03 through M0R-06.

## Changed

- `MadarInbox` is a separate value/file module. Its producer executable depends on `MadarCore` and `MadarInbox`, with no SwiftData/MadarData dependency. Files are immutable one-record JSONL records at `PendingInbox/pending/<deliveryID>.jsonl`. Publication synchronizes the temporary file, closes it, uses exclusive same-directory rename, then synchronizes directories. Temporary files are invisible to claim; claim resumes `processing`, malformed/unknown records quarantine, and failed I/O/cancellation preserve accepted records.
- The app-only drainer executes unchanged command IDs through `CommandBus`, saves no domain state itself, refreshes committed state, then records generation-scoped completion provenance and acknowledges. Pending/processing/unresolved identities pin expired receipts. A retry after its acknowledged receipt was collected stays unresolved rather than silently reapplying. No inverse expiry removes replay identity.
- A distinct natural-key duplicate now saves its own duplicate receipt without changing the fact's timestamp. Receipt replay precedes tombstone/natural-key checks. An ID with a different command name/payload is rejected. The original applied outcome retains its token identity after inverse invalidation; inverse usability remains governed by its separate deadline.
- `AppSession` serializes lifecycle drains and counts them as writers for backup quiescence. Launch, foreground and post-maintenance resume invoke the coordinator. Store generation metadata is separate from room snapshots; a replacement pointer refuses old-generation and unstamped deliveries despite surviving device receipts.
- Transport's embedded `source: app` is not authorization. Foundation settings/presets/onboarding/undo stay recoverable as needsApp in the inbox, even unlocked. `prayer.log` is the spec's blindWrite (§16 Authorize) and may apply with whole-app Face ID locked; physical protected-data unavailability still pauses. No diary/money/read action or new widget button is exposed. No optimistic product overlay is published by this M0 tranche, and diagnostics contain IDs/reason codes only.
- The old two-SQLite-writer script is explicitly historical, excluded from RA2 acceptance. `inbox-process-test.py` uses independent producers while no store exists, followed by one synthetic app consumer.

## Verified

Raw command tails are saved under `Madar/Artifacts/`.

- Fixtures first: `swift test --package-path Madar/Packages/MadarCommands` before adapter changes reported `Test run with 3 tests in 1 suite failed ... with 8 issues` (`command-replay-red.log`). This demonstrated the inherited replay defects.
- Final command/drainer package: `swift test --package-path Madar/Packages/MadarCommands` → `Test run with 11 tests in 2 suites passed after 0.491 seconds` (`command-inbox-tests.log`). Covers A/B/C replay, ID mismatch, undo/tombstone replay, expiry/reopen, save-before-refresh failure, cancellation-before-acknowledgement, maintenance/protection gating, duplicate drains, generation replacement, malformed neighbor, receipt pin/collection and spoofed app-source lock changes.
- Transport package: `swift test --package-path Madar/Packages/MadarInbox` → `Test run with 5 tests in 1 suite passed after 0.005 seconds` (`inbox-transport-tests.log`). Covers exclusive publication, unpublished partial files, claim/restart/read/ack, quarantine, retained old generations, and CLI/Foundation temporary-directory aliases.
- Core package: `swift test --package-path Madar/Packages/MadarCore` → `Test run with 20 tests in 0 suites passed after 0.004 seconds` (`command-core-tests.log`).
- `python3 Madar/scripts/inbox-process-test.py` → passed: no producer store files; producer links no SwiftData/CoreData; three deliveries/two command IDs; one consumer produces one PrayerLog/two applied-or-duplicate receipts/three refreshes/zero unacknowledged files (`inbox-process.json`). Refresh in this helper is explicitly synthetic; the app's real snapshot/history hook is separate.
- `xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS' -derivedDataPath /tmp/madar-inbox-app-build CODE_SIGNING_ALLOWED=NO build` → `BUILD SUCCEEDED` (`command-inbox-ios-build.log`). Locally ignored fonts were copied from this same project's primary checkout before regeneration, so the committed project preserves its font references.
- `git diff --check` → no output.

A narrow failure exceeded two Standard attempts: recovery assertion URL identity and the CLI consumer's `invalidLocation`. The root's fresh Top reviewer isolated Foundation's `/var` versus `/private/var` aliases and directory URL slash identity. The production fix compares canonical parent path strings while retaining regular-file/non-symlink checks; the recovery test proves the actual resumed file is readable. This was not resolved by weakening a file-count expectation.

## Not verified / integration notes

No simulator was launched by this agent. No physical widget/notification action, suspended-app delivery, before-first-unlock protection, kill-at-fsync/rename checkpoint, or real restore-with-concurrent-producer run was performed. Recovery/restore/protection fixtures use controlled failure or injected generation state, and are not physical-device proof. No new UI was added, so no visual comparison is claimed. The inherited integration suite's one-receipt assertion was corrected to two, but that simulator suite must run after root integration.

Unresolved/quarantine files are retained for explicit app review; this tranche does not invent a resolver UI or silently discard them. An unreadable quarantined identity conservatively blocks receipt collection until resolved. Generation-scoped completion markers intentionally preserve identity provenance beyond receipt retention; they store no command payload. Future room actions must add their reviewed authorization and post-commit invalidations/scheduled-request handling before surfacing an entry point.

For the root: merge the narrow `MadarApp` lifecycle hooks with M0-T05's backup-key initializer patch, regenerate the project with the existing fonts, run actual launch/foreground tests with isolated inbox stores, and include this diff in the Top M0-S1 section review. `CommandEnvelope.schemaVersion == 1` / inbox transportVersion 1 are independent from the data-store schema migration. Next session: Top (Sol xhigh) section review/gate evidence; production additions remain Standard high.

## Root reconciliation and integration — 2026-10-10

Accepted scope: independent Top review `docs/reviews/M0-command-inbox.md` now approves transport/data through 9db4191. Initial collision, cross-generation receipts and unknown-command findings were fixed separately; a fix-only follow-up also covers retained completion provenance after receipt/scope GC. No model field was added. Freshly authorized IDs still apply; stale deterministic IDs remain unresolved across replacement. Branch with host tests 76bab3c merged on main as 3e54a53. M0-S1 and whole M0 remain open for RA4/export/gate.

Current main evidence:

```text
swift test --package-path Madar/Packages/MadarCore
Test run with 21 tests ... passed.
swift test --package-path Madar/Packages/MadarCommands
Test run with 17 tests in 2 suites passed.
swift test --package-path Madar/Packages/MadarInbox
Test run with 6 tests ... passed.
xcodebuild -project Madar/Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=412F4437-7BD7-44D1-AA3D-2B7158090E14' -only-testing:MadarTests test
Executed 15 tests, with 0 failures (3.058 seconds).
** TEST SUCCEEDED **
python3 Madar/scripts/inbox-process-test.py
producerStoreFiles=0, producerLinksSwiftData=false,
rows=1, receipts=2, refreshes=3, unacknowledged=0, passed=true.
```

Raw commands (including signing/derived-data/result arguments) and output: `Madar/Artifacts/automation-main-integration.log`, `automation-final-{core,commands,inbox,process}.log`. Four real AppSession tests cover deferred two-source drain/snapshot refresh, same-ID replay, writer quiescence/resume and actual encrypted-backup replacement while retaining device receipts. The final main suite also includes the preserved-value/hidden-route regression.

The coordinator installed the final main simulator app and launched its actual @main process with fresh fixture `automation-inbox-ce07176d-9126-4628-aad0-ac7acbefe685`. Before launch, two external synthetic JSONL producers left no store files. Cold launch produced one PrayerLog/two receipts/zero pending or processing deliveries; a same-ID re-delivery followed by process relaunch preserved those counts and the foundation snapshot. `automation-cold-launch.json` records tested revision 3e54a53 and `automation-cold-launch.log` records the app launches. Test driver retained at `/tmp/madar-inbox-cold-launch.py`; this is controlled simulator evidence, not a physical extension/notification delivery.

Not tested: actual background-to-foreground delivery, physical iPhone surfaces, before-first-unlock protection, process kill inside fsync/CoreData save, VoiceOver, real-owner-data migration or whole milestone acceptance. UI backup password/export failure remains separately open; host-level backup restore success does not close it.
