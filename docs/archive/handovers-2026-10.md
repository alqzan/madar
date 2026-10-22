
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
