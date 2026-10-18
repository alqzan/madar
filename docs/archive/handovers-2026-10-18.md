# Archived handovers — 2026-10-18

## Handover — M6-T01 Turath / Shamela — 2026-10-18 — Claude
- **Works now:** Mihbara › أضف كتابًا › «من تراث · المكتبة الشاملة»: search 8,593 books by title or author, tap to download, the book becomes a local EPUB (page numbers, index, notes, edition page) and goes through the normal review into the library.
- **Verified:** `swift test --filter TurathBookTests` 3/3; a throwaway run on the real صيد الخاطر JSON passed inspection (395 index entries); UI `testTurathSearchDownloadsABookIntoTheLibrary` passed twice (32 s) on the iPhone 17 Pro simulator. Regression `testEPUBPreviewUsesFileMetadataAndAddsAnOfflineBook` is unconfirmed: one run hung at launch on the Quran tab spinner (main thread idle) before reaching Mihbara; rerun it first.
- **Differences left:** no canonical screen (new feature); the reader opens on the edition page first.
- **Not verified:** live network download inside the app; owner iPhone.
- **Next:** a live download on the owner's iPhone; V11/V22 wait for RMI2.
- **Model/effort:** claude-opus-5-5, effort not exposed. **Usage:** five-hour ≈75%, weekly ≈91%.

## M6 reader and PDF checkpoint — Codex
Works now: V17 import clears its arrival; V15 Sunnah drawer and status-bar clipping are committed; X01 reading arc uses real book progress. PDF reader work is preserved uncommitted.
Verified: swift test package checks Money145, Quran76, Prayer25, selected Core102 and Commands122 passed; final Core filter MihbaraReadingTests15/15 and Commands PDFBookImportTests|BookMutationTests14/14; native V17 UI2/2, V15 UI1/1, X01 integration/widget14/14; git diff --check clean.
Differences left: V06 EPUB body still intermittently blank; V18 reference images show import preview rather than active reader. Owner visual acceptance remains open.
Not verified: V18 PDF resume UI FAILED in M6-V18-PDF-persistence despite build success; no PDF commit. Owner iPhone, actual OS placement, long sessions/process termination and frozen areas unverified.
Next: diagnose final PDF resume UI failure in preserved work, then resolve V06 drawing and owner settings-contract decisions; do not repeat prior passes as full acceptance.
Model/effort: main not exposed; scoped helper implementation/diagnosis gpt-6-sol / high.
Usage: reserve reached at95%; final verification consumed more than planned, final live check99% used /1% remaining; no reset used.

## M6 reader and PDF checkpoint — Codex — earlier
Works now: PDF preview confirms only detected metadata and adds Book/Media together with blob-clearing undo; reader queues newer same-session locators during an in-flight write.
Verified: focused Commands suites 12/12; `MihbaraReadingTests` 15/15; combined native UI flow 1/1 (`M6-V17-preview-verified.xcresult`) and build succeeded; `compare-screens.py R10-Milaf-Yafham` generated; `git diff --check` clean.
Differences left: V17 paper palette/type rhythm and content below canonical; V06 EPUB body is blank. Neither screen is visually accepted.
Not verified: Money behavior tests, V06 process-termination recovery, other user PDFs, OCR, V18 reader, owner iPhone; reopening a successful recent PDF reaches duplicate rejection.
Next: refine V17 to canonical, then continue in board order; keep V06 blocked until its body renders.
Model/effort: not exposed / not exposed.
Usage: 95% used / 5% remaining at final check; no reset used.

## M6-V06 reader rendering blocker — Codex — archived 2026-10-18
Works now: local EPUB opens; locator, printed page label and session tracking are wired. The reader shows its header and footer; contents and size settings open, and the shelf return works.
Verified: Apple Silicon simulator `xcodebuild build` succeeded; focused `MihbaraHomeUITests/testLocalEPUBOpensInArabicReaderAndClosesBackToItsShelf` passed 1/1; `git diff --check` clean. Default L/light screenshot and `compare-screens.py R9-Qari-Turath` show an empty reading body.
Differences left: EPUB body is blank in the screenshot; canonical text, section heading, footnote marker and red progress remain unmatched. Accessibility exposes the fixture text.
Not verified: Arabic TTS voice availability, dark mode, other imported EPUBs, owner iPhone. No visual acceptance or card commit.
Next: M6-V07 is next by queue; diagnose the shared Readium rendering blocker before accepting either reader screen.
Model/effort: not exposed / not exposed.
Usage: 23% used / 77% remaining at final check; stopped after two evidence-based repair attempts as the repository protocol requires. No reset used.

## Handover without a title (no-op run) — Codex
Works now: No product files changed this run; existing unstaged M6-V18 PDFKit, command, and UI work is preserved.
Verified: Read current AGENTS.md, board and latest handover, relevant DECISIONS; inspected git status/log; no ready card exists. Usage was 99% at start, then naturally reset to 0% at 09:24 UTC.
Differences left: M6-V18 remains blocked on the native PDF resume UI check; M6-V06 remains blocked by blank EPUB drawing.
Not verified: No build, UI test, screenshot, or canonical comparison rerun this run; owner-device evidence remains open.
Next: No ready card is available; preserve the current worktree and blockers until the board exposes ready work.
Model/effort: not exposed / not exposed.
Usage: Started at 99% used; natural five-hour reset reached 0% at 09:24 UTC; no manual reset or credits used.

## Handover — M6-V23, PDF OCR comparison, and M1 reflection — 2026-10-18 — Codex
Works now: Paper-book cards retain the scanned PDF as page images; the attached file opened at page ١ من ١٦٣ in a synthetic store. M1 home has a still glint at the waterline. Local Vision OCR provides a stronger Arabic/English extraction proof, outside Madar.
Verified: V23 focused UI 1/1; `xcodebuild test ... -only-testing:MadarUITests/FoundationUITests/test_M1V01_HomeMatchesCanonical` passed 1/1; `compare-screens.py S1-Home` and `git diff --check` clean. `swift /tmp/madar_vision_ocr_full.swift`: 84,341 chars from 143/163 pages; 20 pages yielded no text. `ar-SA=false`, `en-US=true` for FoundationModels on this Mac.
Differences left: V23 progress extends the canonical and awaits owner review; M1 glint is static. App preview does not index OCR; Vision still misreads the stylized cover title.
Not verified: OCR accuracy against a gold transcript, in-app grounded summaries/posts/video, owner iPhone, and V18 resume remain unverified or blocked.
Next: No M6 card is `ready`; preserve V18's uncommitted work. The output choice (written result, video, or both) determines the UI.
Model/effort: not exposed / not exposed.
Usage: 34% five-hour used / 36% weekly at latest check; no reset or credits used.

## Handover — M4-V01 and M6-V06 — 2026-10-18 — Codex
Works now: M4-V01 wide/small habit blocks show real period counts, next steps and missed-period warnings; commit `7a34592`. A signed app-group-only run displayed Arabic text from a synthetic EPUB; conversion research is recorded for Claude.
Verified: `testLobbyBuiltBlocksArrangeAndOpen` 1/1 and `testHabitWideAndSmallBlocksShowAtRisk` 1/1; `compare-screens.py R9-Qari-Turath` generated (1 canonical/1 actual); `git diff --check` clean.
Differences left: M4 large habit view still differs from its canonical orbit. V06's last visual assertion still fails (14/15 bundle); synthetic run's printed page is unknown, so V06 remains blocked.
Not verified: no new V06 UI test; root cause remains unknown. One simulator app launch without fixture was immediately terminated; no evidence of owner-store read/write, and no further store inspection was made.
Next: no card is ready. Keep V06 blocked pending a signed isolated UI proof; solve PDF-to-EPUB with Claude as a separate scoped topic. Preserve all dirty PDF work.
Model/effort: Codex not exposed; Sol `gpt-6-sol` / high.
Usage: 91% five-hour used / 9% remaining at latest check; no reset or credits used. Stopped simulator work and retained the 5% reserve.

## Handover — M6-V06, M6-V18 unblocked — 2026-10-18 — Claude
Works now: Arabic EPUB reader shows its text in the chosen font (Amiri default, Thmanyah Naskh/Sans by owner request) at the canonical size with «ص ٤٥٣ من ٤٥٤ في المطبوع»; scanned PDFs reopen at the saved page. Fixed: percent passed as Readium multiplier; book CSP blocking `readium://assets` CSS/fonts (why no reader setting applied); PDFKit's startup page-1 notification overwriting the locator. Codex's earlier blank state was not isolated.
Verified: reader font choice UI 1/1 (`M6-reader-font-*`), MadarData reader-font test 1/1; EPUB reader UI 3/3 iterations (`M6-V06-x3-*`, each shot shows text); Mihbara Home+Import UI 11/12 then the stale wird test updated for V23's card and passed 1/1; PDF resume 1/1 (`M6-V18-final-*`); MihbaraReadingTests 16/16; PDF/Book Commands 14/14; `compare-screens.py R9-Qari-Turath`; `git diff --check` clean.
Differences left: V06 sample text, paragraph and chapter numbers come from the fixture; thinner progress bar. V18 has no active-reader canonical.
Not verified: owner iPhone; anchor resolution across multi-page RTL chapters; EPUB reopen position; real large EPUB/PDF files; dark reader.
Next: M6-V08 (word and highlight) is the first ready card. V07 Aa sheet is built with the owner-approved page options. MadarData `settingsDefaultsPersistenceAndInvalidRejection` still expects 132 settings while the schema has 137 (stale since M5, untouched).
Model/effort: Claude Opus 5.5 / not exposed. Usage: not exposed.

## Handover — M6-V08 word and highlight — 2026-10-18 — Claude
Works now: in the Arabic reader a long press on a word opens the word card (system dictionary, three-colour paragraph highlight, page note, copy with citation). Highlights draw as an opaque band behind the text, reopen on tap, and undo repaints the page.
Verified: `swift test --filter "HighlightCommandTests|BookCommand"` 5/5; UI word-card flow 1/1 (`M6-V08-*.xcresult`, shots in `Artifacts/M6-V08-shots`); V06 reader UI 1/1 regression; `compare-screens.py R9-Qari-Kalima`; `git diff --check` clean. A no-op type annotation in `PrayerStreaksView` unblocked a compiler type-check timeout.
Differences left: reader header/footer stay visible under the card; dictionary button in place of the sample gloss; token colours for the circles.
Not verified: dark reader, Look Up sheet content, highlights across several pages/resources, owner iPhone.
Next: M6-V09 (verses and footnotes) is the next ready card; it owns «حاشيتها» on word touch.
Model/effort: Claude Opus 5.5 / not exposed. Usage: not exposed.

## Handover — M6-V09 verses and footnotes — 2026-10-18 — Claude
Works now: Qur'an quotations (﴿…﴾) draw in the verse colour; note markers are accent circles; tapping one opens the footnote card in place. The V08 highlight band now follows a paragraph across a page break (per-line bands).
Verified: UI V09 1/1, V06 reader 1/1, V08 word-card flow 1/1 after the band fix; `compare-screens.py R9-Qari-Riyad`; `git diff --check` clean.
Differences left: «حاشية الكتاب» instead of «حاشية المحقق»; highlight band also fills the blank space under a page's last line.
Not verified: dark reader, other footnote markup patterns, owner iPhone.
Next: M6-V10 (night scroll): a brief is ready (the reader `theme` key is never read; there is no theme row in Aa; colours are hard-coded by colorScheme).
Model/effort: Claude Opus 5.5 / not exposed; Sonnet 5.5 Explore agent for the V10 brief. Usage: five-hour 51% at last check.

## Handover — M6-V10 reader themes — 2026-10-18 — Claude
Works now: six reader themes from the Aa sheet (auto, paper, warm, calm, night, black) colour the whole reader; night + scroll matches the canonical and keeps the place.
Verified: UI V10 1/1; V06, V08, V09 reader UI rerun (see commit); `compare-screens.py R9-Qari-Tamrir`; `git diff --check` clean.
Differences left: content-driven parts of the canonical (paragraph numbers, per-page footnote block); no 0.2 s theme cross-fade (an animation inside the reader timeline caused a redraw loop).
Not verified: warm/calm/black visuals, owner iPhone.
Next: M6-V11 (focus reader) is the next ready card; focus mode is RMI2 "later", so check scope before building.
Model/effort: Claude Opus 5.5 / not exposed. Usage: five-hour ~60% at last check.
