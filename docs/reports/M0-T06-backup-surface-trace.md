# M0-T06 — Backup and restore surface source trace

12 October 2026 — bounded source trace of the 44 `BackupSettingsView.swift` locations and one app backup-service path in the accepted T11 inventory. This maps the currently integrated M0 backup UI and separates it from the unmerged P1b privacy candidate. No product test or screenshot was rerun.

| Locations | Source disposition | Acceptance limit |
|---|---|---|
| `BackupSettingsView.swift:87,152,174–190` | Schedule/status rows use typed service results; saved counts format with selected numerals. Plain export has a separate unencrypted path, and ShareLink appears only after a file URL exists. The copy says settings and app lock are excluded. | T08 data and pre-P1b native share are accepted within their scoped format/layout. E11 is a failed P1b native run before successful OS authentication; it does not accept the P1b share path. Files destination write remains untested. |
| `:192–205,232–247` | Encrypted export uses two secure fields and `canExport` requires at least ten matching characters. Restore import, passphrase, inspect, cancel and keyboard accessory are identifiable. DEBUG input diagnostics are gated to a UUID-scoped fixture and expose counts/match state, never password contents. | P1b's export/key privacy changes are on an unmerged branch. The simulator has not established OS-authenticated native share success/refusal, inactive/switcher privacy or two-scene behavior. |
| `:213–229,264–280` | Progress/cancel/results, preview counts/dates/warnings, merge/replace mode and explicit confirmation are data-driven. Inspection previews without writing; restore runs only after confirmation. `AppBackupService.swift:60` creates an import cache name with a fresh UUID. | Existing data/host coverage is synthetic and is not owner-store or physical-device acceptance. Actual Files import/save, local file protection and full UI journeys remain open. |
| `:180,176,265,267,269,271,273` | Automatic/manual counts, last-success/preview dates, record counts, additions/updates/deletions and skipped counts are dynamic user-visible formats. `BackupCopy` covers restore/skipped Arabic plurals; several other count/date phrases remain manual language/numeral traces. | Do not infer all plural, locale or selected-numeral combinations from source alone. M0-21 still requires those remaining traces. |

## RA1 copy mismatch

The integrated UI's replace confirmation currently says `سيتغيّر هذا على كل أجهزتك`. The approved RA1 override makes the v1 store local-only and explicitly defers sync. `BackupCoordinator` already qualifies its related warning with “after enabling sync,” but the UI confirmation omits that condition. Apply the precedence rule to this user-facing copy: replacement in v1 changes data on this device. Track the repair separately as `[fix-previous]`; no store, restore or sync behavior needs to change.

## Result

All 45 inventory locations across the backup UI and app import-cache path have source dispositions. The RA1 wording mismatch is a concrete copy defect and remains open on this report's source revision until a focused fix/regression check is accepted. The T09 P1b candidate remains unmerged and separately awaits native acceptance. M0 remains NOT APPROVED.

Sources: `Madar/App/BackupSettingsView.swift`; `Madar/App/AppBackupService.swift`; `Madar/App/CustomizationCopy.swift`; `Madar/Packages/MadarData/Sources/MadarData/BackupCoordinator.swift`; `docs/reports/M0-T08-plain-export.md`; `docs/reports/M0-T09-P1b-candidate.md`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E07/E10/E11.
