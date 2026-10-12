# M0-T06 — Remaining source inventory dispositions

12 October 2026 — final bounded source-map pass for the 57 locations not yet covered by the other T06 reports. A file-hash comparison matched these source files to the accepted T11 inventory on this evidence branch. Integrated main adds the separately reviewed, focused-tested T14 restore-copy helper in `CustomizationCopy.swift` (`d28c36a`); it does not change the four pre-existing inventory locations traced here. No further product file changed or product build/test/screenshot was repeated.

| Source | Locations | Disposition and existing evidence |
|---|---:|---|
| `CustomizationCopy.swift` | 4 | Catalog-backed six-category settings plural and the accepted backup result/skipped/summary copy. Golden count cases 0/1/2/3/11/100 and both numeral styles are recorded in E06/T13. RA1 replacement warning follow-up is integrated at `d28c36a` with its separate focused regression. |
| `Backup.swift`, `BackupCoordinator.swift`, `BackupKeyStore.swift`, `StoreLease.swift` | 16 | Portable/encrypted archive record and media paths, hashes, temporary files, keychain errors, and coordinated lease/cancellation locations map to E02, E07, E09–E11, and T13 coverage. This is source/test evidence, not Files write, physical file protection, owner-store restore or authenticated native-share acceptance. |
| `ManagedDataStore.swift`, `LegacyGenerationMigration.swift`, `GeneratedModels.swift`, `LegacyV1Models.swift`, `LegacyV1Reader.swift`, `RecordFingerprint.swift`, `RecordValidator.swift`, `Records.swift`, `RowMerger.swift` | 25 | Generation/adoption journal paths, legacy read-copy and migration safety/staging, stable record identity/validation and natural-key merge locations map to E02/E04 and T07. The four generated model declarations are not manually reviewed. Frozen fixture migrations do not establish owner-data migration or all 61 models' full future-room behavior. |
| `CalendarCore.swift` | 4 | `GregorianDay` key/description and Hijri date formatting map to independent J01 fixture expectations and T10's accepted local-clock presentation evidence (E02/E05). No astronomical/calibration claim or new fixture result is added. |
| `Notifications.swift` | 3 | Prayer/nudge/digest request identifiers and day keys map to existing pure J10 engine fixtures (E02). Real OS scheduling/delivery, sanctity lifecycle and physical-device behavior remain deferred to M1. |
| `SyncContracts.swift` | 2 | Remote blob availability/hash code is compiled only; RA1 keeps v1 local-only and the shipping inventory has no sync entry. Explicitly deferred; no sync behavior is accepted. |
| `MadarWidgets.swift` | 3 | The visible foundation widget is only an app-opening placeholder with Arabic app/open labels and an SF Symbol; it exposes no unbuilt room action. Package snapshot fixtures in E02 do not prove widget-family layout, timeline reload or physical rendering. |

All 57 locations now have an evidence/disposition pointer. Six are explicitly excluded from manual review/acceptance: four generated model declarations and two RA1-deferred sync-contract locations. The others link to already accepted scoped evidence while preserving each criterion's separate device/UI limit.

## Result

Across the T06 reports, all **420/420** raw manual-inventory locations now have a source disposition: **155 explicitly deferred** and **265 mapped to existing scoped sources/evidence**. “Mapped” is not synonymous with tested or passed. The strict T11 checker still prints `MANUAL TRACE REQUIRED: 420 source lines` because it does not consume these documentation dispositions; no checker behavior was changed. Native/action, VoiceOver/Reduce Motion, owner-device, licensing-source and complete M0 gate criteria remain open. M0 stays **NOT APPROVED**.

Sources: `Madar/scripts/m0-shipping-inventory.json`; T06 trace reports E15–E26; `docs/reports/M0-T02-command-inbox.md`; `docs/reports/M0-T07-review-fixes.md`; `docs/reports/M0-T08-plain-export.md`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E01–E14.
