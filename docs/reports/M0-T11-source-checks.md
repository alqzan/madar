# M0-T11 — Bounded shipping-source checks

Codex Sol Standard high, 2026-10-11. Base `587c57a` on `codex/m0-source-checks`, worktree `m0-foundation-times`. Tooling, negative fixtures and inventory only; no app, engine, generated token/model, settings/default or production resource changes. This is a task self-check, not a section review or M0 gate.

`Madar/scripts/check-shipping-sources.py` reads the actual PBX sources/resources phases for Madar and its embedded MadarWidgets target, resolves their seven local package library products to Sources/<target>, and reads declared catalog resources. It fails closed on missing files, unresolved/ambiguous products, synchronized/custom package groups or computed resource declarations. Test/probe executable targets, excluded QuranRoom and external Adhan source are outside the list. Generated MadarDesign token/metric declarations alone are exempt from literal checks; their canonical/runtime JSON is checked instead. No unchanged generated implementation was reviewed.

Coverage:

- 60 actual shipping Swift files (19 App/Intent, 1 widget, 40 local-package files), one shipped String Catalog. Default values/types for 127 schema definitions, nine literal supported keys and their availability/control types; 15 recognized literal source setting keys, accessor type and bounded literal-write type checks. Computed dictionary/key/option accesses remain explicit manual traces; no claim of a complete Swift type/call-graph analysis.
- All shipped catalog leaves and plural variants scanned for numeric middle dots, six Arabic plural categories checked; source literal/Unicode numeric separators scanned throughout shipping sources. Dynamic formatted/interpolated strings are inventoried, including count-phrase candidates. Regex does not prove every rendered format or linguistic inflection. `Customization/customization.changes` has all six categories and existing hosted independent expectations; backup count phrases remain findings below.
- Canonical/specification/shipped token JSON equality, numeric typeScale minimum >=11pt, 38 declared M0 bahw light/dark pairs independently recomputed with sRGB alpha compositing, WCAG luminance and appropriate 4.5/3 thresholds. All actual thresholds pass. Unrounded math decides threshold acceptance. For metadata parity, independent RGB8-rounded compositing also matches the declared ink2 ratios (e.g. light ink2 on bg: unrounded 4.6587, RGB8 4.6817, declared 4.68); this does not relax thresholds. Nontext outlines are measured independently where required. Other rooms' pair use is deferred to their shipping milestone.
- Handwritten colour constructors/named colour values and explicit font sizes <11 flagged; foreground/background/font/action source lines emitted for inheritance tracing. JSON contrast success is not proof that every live text element uses an allowed pair or font. Native system colours/typography, opacity and runtime text require manual/visual evidence.
- `Madar/scripts/m0-shipping-inventory.json` names actual root paths: lock/root, foundation/customize tabs, first run/city, filtered settings/reset/search/undo, plain export and retained encrypted backup/import/share, open-app Intent and foundation widget. It separately marks compiled PrayerRoom/PrayerSettingsView, sync/presets/generic room template and DEBUG gallery; these do not reinstate M1 or cut v2 entry points. Source anchors/guards are checked, but runtime reachability and dynamic actions are not inferred from the JSON alone.

## Findings for a separate production fix

1. **Medium — RU3**, `Madar/App/BackupSettingsView.swift:124` and `:251`: success/skipped summaries append invariant `سجلًّا` to arbitrary counts using interpolation. For 3 the expected noun is `سجلات`; one/two/other cases also require their agreed categories. Move these user-facing count phrases to String Catalog plural variants and test 0/1/2/3/11/100 independently. The new lint reports both source lines and exits 1; they have not been fixed in this tooling task.
2. **Medium — selected numerals**, `Madar/App/BackupSettingsView.swift:260` and `:263`: both count helpers format with fixed `ar_SA` and do not consult `core.numerals`. Changing the in-app numeral setting cannot select the formatting path used by saved/current/addition/restored counts. Carry the selected style into this view/service presentation and test both styles; do not change data. Source evidence only; no new UI reproduction was run.

`BackupSettingsView.swift:175` automatic/manual summaries also need linguistic cases traced; lines245/247 use labels plus counts and need numeral/bidi runtime evidence. File names, localized errors, date formats, imported warnings and generic formatter output remain manual inventory, not automatically marked passing. These are documented limits rather than a manufactured all-green lint.

## Actual outputs

```text
python3 -m unittest discover -s Madar/scripts/tests -v
Ran 8 tests ... OK
python3 Madar/scripts/check-shipping-sources.py --json-output /tmp/madar-m0-shipping-sources.json
FAIL: Madar/App/BackupSettingsView.swift:124: RU3 hand-built record count phrase requires catalog plurals
FAIL: Madar/App/BackupSettingsView.swift:251: RU3 hand-built record count phrase requires catalog plurals
STATIC FAIL: 60 shipping Swift files, 1 catalogs, 38 independently measured M0 token pairs
MANUAL TRACE REQUIRED: 418 source lines; no complete string/key/colour/action or M0 acceptance claim
```

Negative fixtures exercise fabricated contrast ratios, deficient actual alpha contrast, invalid token/use/minimum types, missing underlying alpha colour, every catalog plural leaf/missing categories, bad key/read/write types, literal colour/small font, RU1/RU3 errors, unlisted source exclusion, unknown PBX source trees and incomplete-manual-mode refusal. `--require-complete` returns 2 when static findings are empty but manual traces remain; this behavior is tested. Normal exit 0 means only bounded static checks pass, never complete acceptance. Current real findings correctly produce exit 1 in either mode.

Existing guards also ran: `check-review-contracts.py --require-ra4` → `PASS: 88 amended contract checks (read-only; device acceptance not tested)`; `check-number-separators.py` → `PASS: RU1 app numeric separator source check`. Staged `git diff --check` produced no output. These successes do not override the new RU3 failures.

Reproducible detailed inventory: `/tmp/madar-m0-shipping-sources.json` includes source paths/hashes, measured ratios, literal/supported keys, every catalog value, findings, source snippets and 418 manual locations. Do not commit generated bulk output; root can regenerate it at the final integrated commit. The count is diagnostic inventory size, not 418 identified defects. The source scanner is intentionally conservative; raw/multiline strings and unfamiliar formats remain trace items or fail closed.

Not run: Xcode/app/package builds (production unchanged), simulator/UI/VoiceOver/Reduce Motion, physical device, runtime contrast measurement, complete manual tracing or M0 gate. Root's current home/settings matrix evidence is separate; no repeated production review was performed. Next: separate backup copy/numeral fix with catalog/host evidence and targeted root UI; then trace reachable M0 dynamic styles/keys/actions and take the remaining accessibility/motion checks into the fresh Top gate.

## M0L-01 fix follow-up

Independent Top review `946c87d` identified that an extra same-package Main → Helper dependency could disappear from enumeration. A separate tooling-only fix now validates each root target's dependency declaration before accepting its source/resource scope: current literal dependencies whose package products are already enumerated by PBX are supported, and the expressly excluded pinned Adhan product is recognized. Additional same-package targets, computed dependency lists, unknown package products and other product/target/conditional expression forms fail closed with a scope-support error. This intentionally bounds the parser to supported manifests rather than claiming a complete SwiftPM graph evaluator.

New negative fixtures reproduce Main → Helper, place a known red-colour violation in Helper/File.swift and require `build_files` to reject the incomplete scope. Unsupported/computed dependency forms are also rejected. Actual `python3 -m unittest discover -s Madar/scripts/tests -v` → `Ran 10 tests ... OK`. Re-running the complete checker on this preserved T11 baseline still produces exactly the two known backup RU3 findings, with 60 sources/one catalog/38 pairs/418 manual lines; T13 is a separate branch and was not folded into this finding fix. No production file changed. `git diff --check` passes. Next is fresh fix-only review of this dependency guard; root integrates and rechecks against accepted T13 later.

## Final integrated root check — 2026-10-11

Top dependency-boundary repair54579a3/3ade5a5 independently approveda399b1f; merged main3b273b5. T13 production fixes are now present. Actual current-main output:

```text
Ran 12 tests in 0.008s
OK
STATIC PASS: 60 shipping Swift files, 1 catalogs, 38 independently measured M0 token pairs
MANUAL TRACE REQUIRED: 420 source lines; no complete string/key/colour/action or M0 acceptance claim
```

Normal checker exit0; strict --require-complete exit2, expected while manual coverage remains. The two historical backup RU3 findings above are closed by T13, not open current-main defects. Full trace size420 is an inventory, not a defect count. JSONs can be regenerated; current raw outputs /tmp/madar-final-shipping.json and /tmp/madar-final-shipping-complete.json. No production changes or repeated app/package run were needed for this tooling-only merge.
