# M0-T06 — Compiled view exclusion trace

12 October 2026 — source-backed disposition of 70 manual-inventory locations in three compiled views. This does not inspect or accept their feature behavior.

| Source | Inventory | Disposition | Boundary |
|---|---:|---|---|
| `PrayerSettingsView.swift` (`914eeffa3c64ded258d93cf444a5584ff2361d37ef17fc01ad6409b1dfb6ac4f`) | 28 | Deferred with the M1 prayer room. The only construction site is the `NavigationLink` nested inside `PrayerRoom.swift`; the accepted M0 root does not construct `PrayerRoom`. | No prayer-setting, RP1, accessibility, copy or layout acceptance. |
| `SyncSettingsView.swift` (`ad643f360feceaa7b392cf4212e13f96a253b2be654fb6385222e7f86b0e7780`) | 16 | No release entry in v1; RA1 is local-only. T11's accepted inventory lists `SyncSettingsView / AppSyncService` as compiled without release entry. | No sync UI or service acceptance; preserve the local-only boundary. |
| `PresetsView.swift` (`49b1fcc016ff8ca5009606da8d01d8a7028b4308ff3b6d448796c38fae02b18f`) | 26 | No root release entry; T11 explicitly defers `PresetsView / savePreset / CustomizeRoom` under RA3. | No preset action, dynamic count or generic-room acceptance. |

The current source search finds each view's type declaration only, except the prayer-settings construction nested in `PrayerRoom`; it finds no root construction of `PrayerRoom`, `SyncSettingsView` or `PresetsView`. The accepted inventory's route records provide the scope decisions; absence from source references alone is not treated as a complete call-graph proof.

## Result

These 70 locations are classified as deferred scope, not reviewed or passed. With the previous T06 reports, 269 of 420 raw manual inventory locations have a source disposition; 130 are explicitly deferred (the 58 PrayerRoom locations, these 70, and 2 generic template locations). 151 locations remain undispositioned. The strict T11 checker still reports the full 420 because it does not consume these reports. M0 remains NOT APPROVED.

Sources: `Madar/scripts/m0-shipping-inventory.json`; the three views above; `Madar/App/PrayerRoom.swift`; `Madar/App/TabShell.swift`; `docs/reports/M0-T11-source-checks.md`.
