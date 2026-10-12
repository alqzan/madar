# M0-T06 — Settings state and command source trace

12 October 2026 — bounded source trace of 36 raw manual-inventory locations in `SettingsStore.swift` and `AppSession.swift`. Both file hashes match the accepted T11 inventory (`SettingsStore`: `df35ffcb97d8be28e93d284ee4defb06a2dc8d9d026458a4e3dcba5cbdd21238`; `AppSession`: `aceb5637875cb4cacc784bd361ffbc03789ff8f05df870b2c7dfb6e88aaa95cf`).

## Data read and write path

`SettingsStore` decodes the bundled schema and selects definitions by key. Reads choose active, non-merged rows in the appropriate `Setting`, `DeviceSetting` or `LayoutState` scope. Missing values return the schema default; malformed or invalid stored values also return that default and log the key once. Non-default writes validate against the setting definition before encoding canonical JSON. Reset writes the schema default, tombstoning shared settings with a deletion barrier. Device-scoped values and layout rows use their respective models.

The write transaction stages sorted setting changes, captures inverse values, stores the command receipt/undo payload, and saves once; failure rolls back. Undo checks both the expiry and that no later edit replaced the current values before staging the prior values and marking the receipt undone. The actual M0 controls route through `AppSession.set`/`setMany` and the `settings.set` command, then reload state and publish a snapshot. Reset derives defaults only for requested schema keys and deliberately excludes `core.faceIDLock`, whose change uses its privacy lifecycle. Search uses schema labels and only `AppSession.supportedKeys`, as separately mapped in `M0-T06-settings-navigation-trace.md`.

## Inventory disposition and evidence limits

| Source | Locations | Disposition |
|---|---:|---|
| `SettingsStore.swift` | 24 | Reachable M0 settings behavior maps to schema validation, scoped read/default fallback, staging, reset, transaction and explicit undo. The `applyPreset` validation points at `:151–152` are compiled but deferred under RA3. |
| `AppSession.swift` | 12 | Typed settings reads, core settings deep-link filtering, normal writes, reset, onboarding, undo and snapshot/error paths map to M0 shell behavior. The `applyPreset`/`savePreset` path at `:128,140` is compiled without a release route and deferred under RA3. |

Existing acceptance is reused, not rerun: E02 records `settingsDefaultsPersistenceAndInvalidRejection` and `batchDependentSettingsAndUndoAreAtomic`; E05/E06 record the bounded reset/search/undo UI flows. This source trace does not establish every setting's individual UI value, spoken VoiceOver, system alert localization or device persistence. The four preset-only inventory locations are deferred, not behaviorally accepted.

## Result

These 36 locations now have a source disposition, including four deferred preset locations. Across the T06 reports, 305 of 420 raw manual inventory locations are mapped; 134 are explicitly deferred and 115 remain undispositioned. The strict T11 checker still reports the complete 420 because it does not consume these reports. M0 remains NOT APPROVED.

Sources: `Madar/Packages/MadarData/Sources/MadarData/SettingsStore.swift`; `Madar/App/AppSession.swift`; `Madar/Specification/settings-schema.json`; `Madar/scripts/m0-shipping-inventory.json`; `docs/reports/M0-T06-settings-navigation-trace.md`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E02/E05/E06.
