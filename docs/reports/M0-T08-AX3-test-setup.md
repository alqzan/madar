# M0-T08 — Top AX3 test setup repair

2026-10-11, codex, Top. Test-only repair after the two Standard setup attempts (`2ba96a7`, `62bdde3`). Production export remains unchanged and has scoped Top approval `3492af4`; root reports 17 host tests passed.

Inspected `Madar/Artifacts/run2-plain-ui-retry.log` and its xcresult. The default/light flow completed export, native ShareLink, Files-option visibility and dismissal. The AX3 flow reached the backup screen, then failed at FoundationUITests.swift:311 while waiting for `plain-export-now`. Its captured hierarchy has a CollectionView with the export-section header at y=833.7 and no loaded export button. Waiting alone cannot materialize the offscreen cell. No export operation ran in that AX3 failure.

Reverted the failed `requirePassword` change to the shared `openBackupSettings` helper, retaining every unrelated UI test unchanged. Split plain setup into its own helper: wait for the observed backup navigation bar and Form CollectionView, then perform at most 12 collection-view swipes until the export button exists and is hittable. The plain test now uses this helper. Existing export/share assertions are retained.

Verified theme input from source: DEBUG `MadarRootView.forcedColorScheme` recognizes `MADAR_UI_THEME=dark`, and `.preferredColorScheme(forcedColorScheme)` applies it; `MADAR_UI_SIZE=AX3` selects `.accessibility3`. No settings workaround is needed. Screenshot evidence remains pending for the dark iteration, which the earlier failure never reached.

Native filename/labels remain source and observation based: coordinator emits `Madar-<date>-plain.zip`; observed share title omits `.zip` and shows `Madar-2026-10-11-plain`, with `حفظ في الملفات`. Existing predicates cover that title and the observed Files label. The test continues to distinguish native share/Files-option/dismissal from an actual successful Files write.

Verified here: scoped diff and `git diff --check`. **Not run:** build, UI test, simulator interaction or new screenshot. Root owns one rerun of `test_M0T08_PlainExportNativeShareAtDefaultAX3AndDark`; report each size/theme and retain attachments. No production changes or simulator commands were made by this agent.
