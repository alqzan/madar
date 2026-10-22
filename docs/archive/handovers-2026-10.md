
## Handover — Mihbara word and footnote overlay clarity — 2026-10-21 — Codex
Works now: reader header/footer disappear while the word or footnote card is open and return after dismissal.
Verified: focused UI tests 2/2 on iPhone 17 Pro / iOS 26.5 (`M6-V08-V09-clear-overlay-final-20261021-r4.xcresult`); `git diff --check` clean; top/scrolled L/light captures and both comparisons generated (2 canonical / 2 actual each; open requests queued).
Differences left: canonical book text differs from the synthetic EPUB fixture; V08 uses the system dictionary action and real token colours instead of the sample gloss and saturated circles.
Not verified: owner iPhone, dark mode for this change, or system dictionary sheet contents; no owner visual acceptance claimed.
Next: no `ready` card on the live board; leave these screens awaiting owner acceptance and resume at the first ready card when one appears.
Model/effort: not exposed / not exposed.
Usage: 54% five-hour used / 46% weekly used at the final live check; no reset or credits used.

## Handover — PDF to flowing book and backup book budget — 2026-10-21 — Claude
Works now: PDF reader «اجعله كتابًا منسابًا» → Turath search prefilled with the title, or on-device conversion (text layer, OCR for scanned/garbled pages) into an EPUB through the normal import review (M6-T02). Encrypted backup leaves book files out above 256 MiB (Turath first), keeps device bytes on restore, and has a Madar paper screen (B-01).
Verified: MadarCommands PDF/Turath 19/19 + PDFBookEPUB 4/4; ManagedBackupTests 16/16; UI `testTextPDFConvertsOnDeviceIntoAFlowingBook` 1/1 (`PDF-flow-r1`); app build; `git diff --check` clean.
Differences left: no canonical screen exists for the conversion sheet; it reuses the Add Book source cards. The shelf shows the PDF and its EPUB with the same cover.
Not verified: owner iPhone; a long real Arabic PDF; EPUBCheck. `test_M0S2_BackupPasswordConfirmationAndFixtureIsolation` fails on the simulator software keyboard with both the new and the HEAD screen.
Next: owner trial of both features; incremental media by sha256 for backups; scheduled background backup.
Model/effort: claude-opus-5-5 / not exposed.
Usage: 45% five-hour / 22% weekly at the last check.

## Handover — real shelf, smart titles, five-room tab bar — 2026-10-21 — Claude
- **Works now:** the Mihbara shelf shows real spines: thickness from pages, each volume of a set numbered on a gilt label, finished books lying in loose piles, and no «على الطاولة» text. Titles come from `BookTitle.parts` (the editor, edition, «مطبوع ضمن» and «=» move to a note; long rhymed titles shorten to their known name). The tab bar is البهو، الصلاة، القرآن، المال، المحبرة, with the diary and «خصّص» in the glass accessory. «حمّسني» is removed. The card sheet (M5-C01) is committed. The EPUB review no longer pins its button over the shelf row.
- **Verified:** `swift test --filter BookTitleTests` 12/12; UI `testLiveTurathTenBooksAcrossEveryShelf` passed (227 s, shots in `Madar/Artifacts/shelf-21oct/`); `RoomGlyphUITests/testWalkBuiltRoomsWithNativeRoomGlyphs` passed; earlier this session: EPUB import, library and card tests passed.
- **Differences left / failing:** `QuranHomeUITests/testFirstUseShowsPlanActionWithoutZeroStreakOrDepthControls` fails at line 97: after opening the diary from the accessory, the «المال» tab is not found. Check whether the diary hides the tab bar, and fix the shortcut flow in `TabShell` (the `lastRoom` binding). The other ~80 UI tests that now use `tab-customize` were not rerun.
- **Not verified:** owner iPhone; dark mode of the spines; the tab change on iPad (sidebar).
- **Next (owner answered, all «yes» to the proposal):** M6-UX-R (merge «قديمًا» into «أنهيتها»; cabinet into «كل كتبي»; the desk becomes one open book with the wird), M6-UX-V (tapping a volume opens it), M6-UX-T (title edit and size at import).
- **Model/effort:** claude-opus-5-5, effort not exposed. **Usage:** about 83% of the five-hour window at handover.
