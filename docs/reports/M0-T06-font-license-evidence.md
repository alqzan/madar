# M0-T06 bundled UI font evidence

12 October 2026 — Codex Standard, read-only source/artifact inventory on main. No font, product source, build or test was changed or run. This records evidence present in the checkout; it is not a legal opinion or distribution approval.

| Font/source | Evidence present | Remaining limit |
|---|---|---|
| Thmanyah UI fonts (8 files) | `Madar/docs/font-provenance.json` records each filename, SHA-256 and `modified: false`. The local official page snapshot `Madar/docs/thmanyah-license-2026-10-10.html` has SHA-256 `084945240b72fadd4f0a9f2e53ec50179529c36aecead111648288c7f75fd462`. The eight local app font files are ignored by Git; their bundle mapping is documented in `Madar/docs/DESIGN.md`. | Provenance explicitly sets `licenseFromExactDownloadPackage: null` and the gate to local development until the original shipped licence is obtained. The archived official page is not the licence text from the exact package that supplied these font files. Keep distribution status unresolved; do not infer permission from the current-page snapshot. |
| Amiri UI fonts (Regular/Bold) | Provenance identifies Amiri 1.003 and the upstream release. The tracked `Madar/App/Resources/Fonts/Amiri-OFL.txt` SHA-256 is `72de68e5954f4fdd24702292ef5a32f003ca960ec9330d86e5eefb5dffb9b22`, matching both font entries in provenance. `Amiri-Regular.ttf` and `Amiri-Bold.ttf` hashes are recorded there. | This verifies the checked-in OFL text/hash against the manifest, not a full package-build inclusion check. |

## Gate result

M0-02 remains **not tested / distribution gate open**. The missing item is the original Thmanyah package licence plus its recorded hash, not all font information: current official terms and their retrieval date/hash, eight font hashes, Amiri's version/source and OFL text/hash are present. Obtain and compare the exact Thmanyah package licence before any distribution decision; update provenance only when that source evidence exists. The owner remains the decision-maker for licensing, and no distribution was attempted here.

Sources: `Madar/Specification/design-tokens.json:13–25`; `Madar/docs/font-provenance.json:1–5,6–86`; `Madar/docs/DESIGN.md` “خطوط الواجهة”; `Madar/App/Resources/Fonts/Amiri-OFL.txt`; `docs/HANDOFF/sections/14-shared.md` RA6 and `AGENTS.md` distribution/license rules.
