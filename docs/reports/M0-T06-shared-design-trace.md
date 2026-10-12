# M0-T06 — Shared design components and theme trace

12 October 2026 — bounded source trace of 24 raw manual-inventory locations in MadarDesign shared components/theme and the DEBUG gallery. Source hashes match accepted T11 inventory: `SharedComponents.swift` `c2634beb3623d61ce1fe1db25ef7e6ec57cab41bb3e37c76926cbe4124e43e3c`; `Theme.swift` `f68151554e39e46e24fd7aba70c62e12a8c770fe11a89758a53c1844ff88b36a`; `MadarComponentGallery.swift` `92e2f00bda83a72e2c75055e79b1ab6d8fa50010dd45d32a8636fbab39871d10`.

## Disposition

| Source | Locations | Disposition | Acceptance limit |
|---|---:|---|---|
| `SharedComponents.swift` | 15 | `UndoToast` and `CustomizationTemplate` are used by M0 settings/shell and map to Arabic action/copy, named type roles, `theme.ink` on `theme.surface/background`, and 44-point undo targets. The six `EditModeContainer` locations have no M0 route; that editor remains deferred by RA3. | Existing T04/T10 settings and undo evidence covers only its documented flows. No complete Dynamic Type/VoiceOver acceptance follows from source. |
| `Theme.swift` | 5 | Dynamic role paths resolve via `MadarToken`; core aliases and calm-paper normalization map to declared Bahw roles. `MadarCard` uses surface/line; `MadarPrimaryButton` uses `onAccent` on `accentFill`. Named typography sizes come from `MadarMetric`. | T11 independently measures the declared M0 Bahw pairs; that does not identify every runtime inherited/native/opacity combination or close T12's nil-element system callback. |
| `MadarComponentGallery.swift` | 4 | Entire file is inside `#if DEBUG`; gallery-only sample copy and component rendering are not release UI. | Four locations are deferred test surface, not product-screen acceptance. |

## Result

Fourteen locations map to reachable shared M0 components/theme; ten are deferred (six generic edit-mode controls and four DEBUG gallery locations). Existing L/AX3/AX5 and dark-mode evidence is reused from E05/E06; no product build, test or screenshot was repeated. Across T06, 342 of 420 raw manual inventory locations have a source disposition, 146 are explicitly deferred and 78 remain undispositioned. The strict T11 checker continues to report the full 420 because it does not consume these reports. M0 remains NOT APPROVED.

Sources: the three files above; `Madar/App/CustomizeMadar.swift`; `Madar/App/TabShell.swift`; `Madar/scripts/m0-shipping-inventory.json`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E05/E06/E08/E18.
