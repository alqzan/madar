# Review V1 application status

This table distinguishes corrected documents from working app behavior. Original output/ sources and extracted section text are preserved. Latest owner decision explicitly accepts RD2 Entry margin retention.

| Item | Working contract | Runtime / acceptance |
|---|---|---|
| RA1 | core.iCloudSync default false, availability deferred | Factory/reopen corrections in M0-T03; no claim yet that all constructors are local. |
| RA2 | Top architecture note specifies atomic JSONL spool and app-only store | Implementation in M0-T02; old multi-process SQLite evidence is historical. |
| RA3 / RA8 / RL8 | 23 named cut keys marked availability v2; glass remains tabbar.style default | Forced read/write defaults, route filtering and hidden presets/cloud entry still required in M0-T04. No arbitrary extra settings are removed to reach a target count. |
| RA4 | Model name still legacy Transaction pending tested conversion | M0-T07 must freeze old schema, migrate old store and decode authenticated old archives before regeneration. Simple rename would lose compatibility. |
| RA5 | Test count/journey correction still pending | Define cited journeys with actual room states before each gate; no invented acceptance steps. |
| RA6 | OWNER-RUNBOOK.md written from current project IDs and official Apple steps | Membership and signed device/TestFlight setup deferred by owner; no external action taken. |
| RA9 | 25 section text extracts plus index/hashes | Extraction completed; review overrides remain separate. |
| RD2 | Owner retention decision documented | RowMerger and working delete policies in M0-T03. Deleted-origin arrow UI test remains M3 (room unbuilt). |
| RD5 | notes.dictationFirst default false in three working copies | Speech feature unbuilt; no mic entry or server use claimed. |
| RMI1 | readerEn.arabicHints default none; fieldAvailability v2 | Reader unbuilt; custom dictionary/side-by-side/edition matching remain excluded. |
| RQ8 | tapForTafsir default false, M2 licence gate annotated | Quran scaffold excluded from M0 target; no licensed resource or visible action claimed. |
| RL5 | salah.liveActivity default false | Starts/budget/sanctity/device duration tests pending M1. |
| RP6 | salah.askHeart default false | No heart ranking/UI acceptance claimed; Prayer UI remains unintegrated scaffolding. |

Settings changes are identical in `docs/HANDOFF/settings-schema.json`, `Madar/Specification/settings-schema.json` and the package resource. Persisted preferences are preserved; hiding a setting must not erase user rows. Factory and UI enforcement require separate tests.
