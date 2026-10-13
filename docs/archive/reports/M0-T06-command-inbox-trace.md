# M0-T06 — Command inbox and durable replay trace

12 October 2026 — bounded source trace of 21 raw manual-inventory locations across the app inbox transport, durable command adapter, and core command envelope. All four hashes match the accepted T11 inventory.

| Source | Locations | Disposition |
|---|---:|---|
| `PendingInbox.swift` (`c0c39d7829c1418c4f958086a964ea9c271e2df72db19db4df9ff263008757a9`) | 10 | Inbox paths are derived from delivery/command UUIDs; claim, resume, quarantine, completion markers and temporary files remain within the app-managed inbox folders. T02 tests cover immutable publication, processing recovery, malformed-record quarantine and generation markers. This is package evidence, not a physical extension write. |
| `DurableCommandAdapter.swift` (`6d3218905be70c2e83a88e26ac03b882bac1b3b8e22fcdac5981460a55f05426`) | 9 | Command identity and generation select receipt scope; stable identities, undo freshness, and receipt/scope lifecycle map to T02. The preset-only guard at `:217` is deferred by RA3. The `PrayerLog` identity at `:141` is covered only as T02 inbox infrastructure; it does not accept M1 prayer logging behavior or expose a user route. |
| `Commands.swift` (`67067c2b1502326130a5eab6383f4e1f85c4098ba33ab352247bf9667fd02dff`) | 1 | Canonical command data has a deterministic SHA-256 identity; envelope/receipt behavior is covered by the T02 core/adapter fixtures. |
| `PrayerCommands.swift` (`56d6f7260871f8b0eb0e1ffe368efadc9d34858a019ffa209fec2256ca1d0f70`) | 1 | The prayer payload string accessor is compiled command scaffolding for M1. It is not a M0 logging entry point or prayer-room acceptance. |

## Existing evidence and limits

The T02 report and E03 document the separate producer/app roles, app-owned transaction/receipt path, duplicate/replay boundaries and local generation provenance. Existing accepted evidence includes the current Core **22**, Commands **17**, Inbox **6**, and host suite **22** package/app outputs and the controlled app `@main` launch/relaunch result. No test or build was repeated for this documentation-only trace.

Physical widget/notification producer delivery, suspended-app delivery, first-unlock protection, kill inside durable file/store checkpoints, and M1 Prayer UI/action acceptance remain untested. `source: app` alone is not authorization, and this report does not add a release entry for any deferred command.

## Result

Eighteen locations map to accepted M0 inbox/replay infrastructure; three are explicitly deferred (the preset guard, `PrayerLog` user behavior and M1 prayer-command payload). Across T06, 363 of 420 raw manual inventory locations have a source disposition, 149 are deferred, and 57 remain undispositioned. The strict checker still reports all 420 because it does not consume these reports. M0 remains NOT APPROVED.

Sources: the four files above; `docs/reports/M0-T02-command-inbox.md`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E02/E03.
