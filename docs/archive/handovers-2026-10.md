
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

## Handover — set titles across volumes, open a volume, rename and size — 2026-10-22 — Claude
- **Works now:** a set's volumes stand upright with the short name written once, large and horizontal, across all of them (owner's «زا في مجلد ثم د في مجلد»); tapping a volume opens it (saved place or its first chapter) and the reader header names it; «غيّر الاسم» on the shelf menu (`book.rename`, undoable); the import review shows the shelf name and the size. The diary welcome no longer hides the room bar (it trapped first-time users).
- **Verified:** `swift test` BookVolumesTests 4/4, BookMutationTests 10/10, BookTitleTests 12/12; UI `QuranHomeUITests/testFirstUseShows…` passed (it failed before), `testTurathSearchDownloadsABookIntoTheLibrary` passed, `testEPUBPreviewUsesFileMetadata…` with rename passed, `testTappingASecondVolumeOpensThatVolume` passed with its known gap marked; `git diff --check` clean.
- **Differences left:** a volume that begins mid-chapter opens at that chapter, not its first page (blocker in M6-UX-V). The spine title overlaps the 1 pt gap between volumes, as on a printed set.
- **Not verified:** owner iPhone; dark mode of the spines; long real sets of 8+ volumes.
- **Next:** owner looks at the shelf; M6-UX-V blocker; M6-UX-R needs two or three layout proposals before code.
- **Model/effort:** claude-opus-5-5, effort not exposed; helpers Haiku and Sonnet (read-only). **Usage:** not exposed.


## Handover — item 26 habits «ب مع ج» built — 2026-10-25 — Claude
- **Works now:** on main, item 26. `fc19557`: schema V12 adds `HabitEvent.entryID`. `1c2e5ab` and this commit: `habit.complete` takes an optional past `day` and `entryID`. A past day is logged in its own period; a day to come or before the start is refused; a remembered earlier day still counts for a once-habit already done. `HabitReading.times`/`lastTime`. «كل عاداتي» draws each rhythm (`App/HabitRhythmBands.swift`). A monthly or yearly habit opens on «منذ آخر مرة» (`App/HabitSinceView.swift`): both dates, rhythm line or «مرّت سنة ولم تفعلها», a timeline of times, diary lines of those days, and «فعلتها في يوم سابق» with a date picker and an optional line of that day. Period `end` is exclusive, so the room's «بقي …» no longer counts one day too many.
- **Verified:** HabitPersistenceTests 9/9; MadarCommands 210/210; MadarCore 156/156; HabitsUITests 3/3 (`Madar/Artifacts/I26-r3.xcresult`, then `I26-r5.xcresult` after the nudge); `git diff --check` clean.
- **Differences left:** there is no canonical board for B/C; the reference is the mockup artifact https://claude.ai/artifact/2TVXJFtf6x4h7XxgbwGr79. The daily band now shows the last seven days as steps (height = share of daily habits done), not today again (r7). On the timeline, the today mark sits on top of a time logged in the last few days.
- **Not verified:** the «مرّت سنة» nudge on screen (the fixture's last time is 240 days ago); the owner's iPhone; old-Madar habits after the move (they have no entryID).
- **Next:** (1) the owner reviews B/C; (2) item 24 native-wins is covered for prayer, Quran and money (`LegacyMoveNativeWinsTests` 3/3); habits had its own test; (3) a long-press on a room row now opens «فعلتها في يوم سابق» (r6).
- **Model/effort:** claude-opus-5-5, effort not exposed; no reviewer (no migration in this slice).
- **Usage:** five-hour ~85% used at handover time, weekly 74%. After this handover: native-wins tests for prayer, Quran and money (3/3), long-press for a past day, and the seven-day daily band.

## Handover — owner PDF quality, «الأصل», iCloud code — 2026-10-25 — Claude
- **Works now:** scanned PDFs convert at high quality: OCR now renders each page at 2048 px with a 6% white margin (before: native 72 dpi, lines and first letters lost); stray OCR symbols dropped without guessing letters; wordless pages (ornamented basmala) stay as their picture, blank pages vanish, the scanned cover becomes the book cover (max 40 pictures). A converted book's reader footer has «الأصل» → the original PDF at the same page (link via `urn:madar:pdf:<hash>`, no new field). iCloud: `CloudMirror.swift`, `ManagedDataStore.bindCloudMirror`, `AppSyncService` rewritten — store always opens locally, mirror attaches only after the account is confirmed, backup before first upload, account switch keeps data local and stops sync. Gated by `MADAR_CLOUDKIT_CONTAINER`: the default build shows no iCloud entry point; `make cloud-device TEAM=<id>` builds the CloudKit variant (`App/Madar-CloudKit.entitlements`).
- **Verified:** owner books trial `OwnerAllDataTrialUITests` 2/2 (`owner-data/books-trial-r3.xcresult`; PDF needs `TEST_RUNNER_MADAR_TRIAL_PDF`, EPUB `TEST_RUNNER_MADAR_TRIAL_BOOK`); «من ملف» file picker fixed (two stacked fileImporter modifiers, only the Goodreads one worked; now one per button) — build passed and the picker opened and previewed the owner's PDF by hand in the simulator; synthetic MihbaraImportUITests NOT rerun after the OCR render change (stopped so the owner could use the simulator); `swift test` MadarData store suites 49/49 incl. CloudKitSchemaTests 8/8, MadarSync 9/9, PDFBookEPUB+TextReader 15/15. One data review (iCloud): three High fixed (stale container, rollback, account switch).
- **Differences left:** bold parenthesised words in scans can still lose letters (Vision limit). The PDF's own front matter has a misprinted URL in the scan; kept as read.
- **Not verified:** anything against real CloudKit, the CloudKit build signing, owner iPhone.
- **Next (owner):** paid Apple Developer account → create container `iCloud.com.alqzan.madar2` + App Group for app and widget → `make cloud-device TEAM=<id>` on the iPhone (Development) → test two devices → deploy schema to Production in CloudKit Console before TestFlight; afterwards schema changes are additive only.
- **Model/effort:** claude-opus-5-5, effort not exposed; read-only helper agents only. **Usage:** not exposed.
