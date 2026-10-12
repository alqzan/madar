# M0-T06 — Compiled prayer room exclusion trace

12 October 2026 — bounded scope trace of the 58 raw manual-inventory locations in `Madar/App/PrayerRoom.swift`. This records why the compiled M1 room is excluded from M0 source acceptance; it does not review or accept the prayer room's behavior.

## Route disposition

The accepted T11 inventory names `PrayerRoom / PrayerSettingsView` as compiled scaffolding with no M0 tab/route, and states that M0 exposes only foundation and customization, per RA3. A source search of `Madar/App` finds no `PrayerRoom(` construction beyond the type declaration; the only `PrayerSettingsView` construction is inside `PrayerRoom` itself. `MadarRootView` builds a `TabShell` with only `foundation` and `customize`, routing to `FoundationHome` and `CustomizeMadar`. Therefore the 58 PrayerRoom source locations have no M0 user entry point and are deferred with the M1 Prayer milestone.

| Inventory | Disposition | Gate boundary |
|---|---|---|
| 58 `PrayerRoom.swift` locations, source hash `11ef2fc1e0e0616a6fb46c36f97a16026a712e03eb514060407b39682a587937` | Out of M0 scope: compiled prayer-room scaffolding, unreachable from the accepted M0 root. | No M0 claim about room copy, prayer record actions, settings, color/contrast, counts or layout. The deferred M1 section must trace and test the shipped prayer flows against RP1 and the room specification. |

## Result

These 58 locations are dispositioned as deferred scope, not as behaviorally reviewed or passed. Across the existing bounded T06 traces, 199 of the 420 raw manual inventory locations now have a source disposition; 60 are explicitly deferred (58 here and two generic future-room template entries). The remaining 221 locations, actual reachable-action evidence and the M0 device/accessibility gates remain open. The strict T11 checker still reports all 420 because it does not consume these reports.

Sources: `Madar/scripts/m0-shipping-inventory.json`; `Madar/App/PrayerRoom.swift`; `Madar/App/PrayerSettingsView.swift`; `Madar/App/TabShell.swift`; `Madar/App/MadarApp.swift`; `docs/reports/M0-T11-source-checks.md`.
