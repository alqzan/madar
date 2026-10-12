# M0-T06 — Customization and shell source trace

12 October 2026 — bounded source trace of 51 inventory locations in reachable `CustomizeMadar` and `TabShell` code. Two `CustomizeRoom` template entries are compiled but have no M0 release route and are explicitly deferred by RA3. This reuses accepted T04/T10 evidence; no production build, test or screenshot was repeated.

## Routes and settings contract

`TabShell` provides only the foundation and customization tabs. `MadarRootView` chooses `FoundationHome` or `CustomizeMadar` by those IDs, applies the system/light/dark theme and Dynamic Type, and presents first-run separately. T11's root inventory excludes Prayer, Quran, presets, sync controls and the DEBUG gallery from release entry points. The backup link is rendered only when the service exists; search mode does not leave a disabled backup button.

`CustomizeMadar.filtered` intersects the schema with the nine `AppSession.supportedKeys`, conditionally hides `core.hijriOffset` unless sighting correction is selected, and searches normalized title/section/key text. The supported keys and schema defaults are:

| Key | Type | Default |
|---|---|---|
| `core.dayStart` | choice | `fajr` |
| `core.firstCalendar` | choice | `hijri` |
| `core.hijriSource` | choice | `ummAlQura` |
| `core.hijriOffset` | integer, −2…2 | `0` |
| `core.weekStart` | choice | `saturday` |
| `core.theme` | choice | `auto` |
| `core.numerals` | choice | `arabicIndic` |
| `core.homeCity` | place | Riyadh, SA, `24.7136, 46.6753`, `Asia/Riyadh`, SAR |
| `core.faceIDLock` | choice | `notesOnly` |

Each control writes the selected schema value by its definition key. Choice options expose their Arabic label, selected state and selection trait; option IDs come from the schema value. Boolean/int controls use typed accessors, with integer bounds read from schema. Place edits route to `CityEditor`. At accessibility Dynamic Type, choices use the vertical alternative and preview lines stack. Controls and reset targets use at least 44-point minimum height.

The changed-count preview counts only supported settings and uses the catalog-backed `CustomizationCopy` plural form plus the selected numeral style. Reset requires confirmation and calls `session.reset(AppSession.supportedKeys)`; the confirmation copy states data is untouched. Existing T04/settings UI evidence covers the reset/search/undo paths within its recorded scope; this trace does not claim every option was individually exercised.

## Appearance, action and error trace

The active screen uses named typography and theme roles, not color literals. Selected option text uses `ink` on `surface`; unselected text uses `ink2` on `bg`; the active theme uses declared light/dark token pairs. The reset/search controls and selected-state metadata retain the Arabic labels and identifiers shown in the source. `ContentUnavailableView.search` is the empty-result path.

The root shell drains the inbox and refreshes the local snapshot on launch/foreground. Failures are presented in a dismissible alert using a fixed Arabic prefix plus `error.localizedDescription`; that runtime error text is not proven localized by this source trace. The undo toast exists only while `undoToken` is present. Actual spoken VoiceOver, system Reduce Motion and OS Face ID behavior remain separate acceptance.

`CustomizeRoom`'s dynamic future-room title and footer (`CustomizeMadar.swift:202,206`) are included in the static inventory but have no call site in the M0 root. They are classified as deferred, not an M0 string/action defect or feature.

## Inventory coverage

| File locations | Disposition |
|---|---|
| `CustomizeMadar.swift:16,17,22,31–33,37–38,41,43` | Preview copy, city value, named typography/theme roles, changed-count label and paired reset control; default-size versus AX layout branch. |
| `CustomizeMadar.swift:50–53,63,65,72–73,85,88–89,95–99,103` | Search input and empty state, conditional backup route, reset confirmation, changed-key count/value lookup, option label/section selection and search normalization. |
| `CustomizeMadar.swift:133,147,149,158–164,172–183` | Section/control labels, scope badge, bool/int/place/choice writes, schema option identifiers, selected value/trait, dynamic type/layout and selected/unselected theme roles. |
| `CustomizeMadar.swift:202,206` | Future-room generic template title/footer; no M0 call site, deferred under RA3. |
| `TabShell.swift:46,57,64–65,69,76` | Root typography, app/foreground local maintenance error paths, dismissible Arabic-prefixed alert and error message. |

## Result

All 51 inventory locations across `CustomizeMadar.swift` and `TabShell.swift` now have a disposition: 49 belong to M0's reachable settings/shell source and two belong to the unentered future-room template. With the FoundationHome and onboarding/city traces, 96 of the 420 raw locations are documented; two are explicitly deferred. The strict checker remains at 420 because it does not consume these reports. No M0 approval follows: city-form execution, privacy UI, native alerts, spoken VoiceOver, T12 contrast and the remaining source/device gates are still open.

Sources: `Madar/App/CustomizeMadar.swift`; `Madar/App/TabShell.swift`; `Madar/App/AppSession.swift`; `Madar/Specification/settings-schema.json`; `Madar/Packages/MadarDesign/Sources/MadarDesign/Theme.swift`; `Madar/Packages/MadarDesign/Sources/MadarDesign/SharedComponents.swift`; `Madar/Tests/UI/FoundationUITests.swift`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E05/E06/E08/E14.
