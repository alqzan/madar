# Journey register — RA5

Version 1, 2026-10-10. These are acceptance procedures, not completed test results. The original section extracts remain unchanged; Review V1 overrides conflicting steps. Each room adds a row for every further v1 function before its gate. A referenced journey without implemented tests and recorded evidence remains **not tested**.

Every UI row runs empty, large, error and locked data states; Arabic RTL, L/AX3/AX5, light/dark, safe areas and keyboard; save/cancel/error/retry/back and return position. “Large” means long Arabic/mixed text, hundreds of rows and seven-digit amounts where applicable. Tests use synthetic fixtures, never the owner's live data. Engine tests do not count as physical surface tests.

| ID | Definition | First gate |
|---|---|---|
| J01 | [Shared day boundary](shared.md) | M0 |
| J02 | [Prayer command and correction](salah.md) | M1 |
| J03 | [Quran session/resume](quran.md) | M2 |
| J04 | [Quran plan change](quran.md) | M2 |
| J05 | [Diary capture/freeze/margin](notes.md) | M3 |
| J06 | [Diary import/media/projects/letters](notes.md) | M3 |
| J07 | [Diary lock and sealed letter](notes.md) | M3 |
| J08 | [Habit recurrence/events](bahw.md) | M4 |
| J09 | [Lobby layout and fixed widgets](bahw.md) | M4 |
| J10 | [Notification arbitration](shared.md) | M1/M4; existing engine coverage retained |
| J11 | [Money review and reconciliation](money.md) | M5 |
| J12 | [Travel and currency](shared.md) | M1; M5 money |
| J13 | [Book import/reader/recovery](mihbara.md) | M6 |
| J14 | [Book history/private notes/Goodreads](mihbara.md) | M6 |
| J15 | [Future two-device synchronization](shared.md) | Deferred by RA1 and owner |
| J16 | [Encrypted backup/restore](shared.md) | First relevant room; existing M0 coverage retained |
| J17 | [Cross-surface privacy](shared.md) | First private room and M7 |
| J18 | [Availability and offline entries](shared.md) | Every gate; M7 final |

J03/J04/J05 receive explicit IDs here because the handoff did not assign them. This numbering adds traceability; it adds no product feature. Test names below are **required/planned identifiers**, not assertions that a test exists. Current results belong in `docs/reports/` with device/OS, revision and fixture version.

RA5 also corrects §12's count: the §11 reconciliation list contains **eight** tests. The amended working HTML says eight; source copies under `output/` and text-only section extracts preserve the original wording.

Under RA3, M0 requires the lean foundation and plain export. J10 and J16 remain defined for retained tests and the milestones that need them; the old gate wording does not reinstate the synthetic arbiter week or encrypted backup as mandatory new M0 deliverables. J15 is deferred. J01 and J18 apply to the actual lean shell; physical iPhone prayer-times acceptance remains required.
