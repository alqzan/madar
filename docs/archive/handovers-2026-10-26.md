# Handovers moved off docs/PROGRESS.md on 27 Oct 2026 (verbatim, newest first)

## Handover — owner-data tour, the reader's index on the phone's OCR, converted-book polish — 2026-10-26 — Claude
- **Works now:** the converted «مشروع العمر» index lists إضاءة, المقدمة and all 22 chapters with their topics, each with its own title (reader TOC ids were `depth-href`, so entries sharing a page repeated one title — now `MihbaraTOCItem.order`). `PDFBookEPUB.printedContents` splits titles OCR merged on one line, shortens a leader-zero number that runs past the next one («٠٧٠٠» → ٧), lets a misread number yield to an earlier heading, and stops at the first text page. The book's printed contents page reads as linked contents (`madar-contents`); section breaks read as «* * #»/«#» become one centred «* * *»; OCR drops ornament Latin letters glued to words and short Latin-only lines on Arabic pages. Conversions ask iOS for background time, resume from page one when the room opens after iOS closed the app (`PDFConversions/pending.json`), and the card shows time left.
- **Verified:** `swift test --filter 'PDFBook|TextReader|Turath|EPUBBookImport'` 40/40; on simulator DAA1805E: `testOwnerAllDataTrial` passed (852 s, r4), `testOwnerPDFConvertsAndReads` passed (r8, 299 s; asserts chapters ١، ٨، ٩، ١٠, «المقدمة» text, and that the printed contents page's chapter ١ link opens file page ١٢), `MihbaraImportUITests` conversion 30 s and resume-after-close 159 s passed. Logs in `Madar/Artifacts/owner-data/` (local only).
- **Differences left:** none new.
- **Not verified:** iOS OCR differs from the Mac's: the iOS dump is `Artifacts/owner-data/books/mashrou-alumr-pages-ios.json` (`xcodebuild test -scheme MadarCommands-Package -destination <sim> -only-testing:'MadarCommandsTests/OwnerPDFDumpTests/dumpOwnerPDFPages()'` with `TEST_RUNNER_MADAR_TRIAL_PDF`/`_DUMP`). Honorific glyphs OCR as noise (idea row «Honorifics in scanned books», waits for the owner). Superseded by Codex 26 Oct: latest main built and installed on 412F4437; normal launch reached Face ID, conversion/TOC UI passed 1/1 in an isolated store.
- **Next:** the owner's long notes from the whole-app trial; row 30e («صفحة ٩٤») needs the owner to say where it showed.
- **Model/effort:** claude-opus-5-5, effort not exposed. **Usage:** five-hour about 74% at handover.

## Handover — PDF converts in the background, one book, the book's own index — 2026-10-25 (late) — Claude
- **Works now:** adding a PDF asks «نحوّله كتابًا منسابًا؟»; «حوّله» runs the conversion in `App/MihbaraConversions.swift` while the app is used (progress card on the Mihbara home, «إيقاف», then «افتحه»); the EPUB is added to the PDF's shelf and the PDF leaves the shelves but stays the book's «الأصل» (`MihbaraHomeReading.originals`, link cache `PDFConversions/links.json`, derived from the EPUB identifier). The index of a bookmark-less PDF comes from its printed contents page (`PDFBookEPUB.printedContents`); headings and short last lines no longer glue onto the previous page's paragraph. «من ملف» opens the picker (commit 2c7ecbe).
- **Verified:** `swift test` PDFBookEPUB/TextReader/Turath/EPUBBookImport 32/32 (two new hand-worked tests); owner book dump → all 22 chapters on their heading pages (`OwnerPDFDumpTests`, local only, needs `MADAR_TRIAL_PDF`+`MADAR_TRIAL_PDF_DUMP` or `MADAR_TRIAL_PDF_PAGES`); app build passed; MihbaraImportUITests PDF flows 4/4 on a second simulator (iPhone 17, `Artifacts/pdf-bg-r2.xcresult`): offer → background conversion → «افتحه» → one book on the shelf + «الأصل»; keep-as-PDF import/undo/resume.
- **Differences left:** no canonical for the offer alert or progress card (system alert + MadarCard).
- **Not verified:** `OwnerAllDataTrialUITests/testOwnerPDFConvertsAndReads` still drives the old review flow and must be updated to the offer → «افتحه» flow (same steps as `MihbaraImportUITests/testTextPDFConvertsOnDeviceIntoAFlowingBook`); conversion stops if iOS suspends or kills the app (no resume yet); owner's «صفحة ٩٤» not reproduced (row 30e); unclear bold words (30f).
- **Next:** rows 30e/30f after the owner's notes, 31 Turath quote card, 32 owner-data walk; the owner is trying the whole app and will send long notes.
- **Model/effort:** claude-opus-5-5, effort not exposed. **Usage:** five-hour about 55% at handover.

## Handover — continued app improvements across rooms — 2026-10-26 — Codex
- **Works now:** prayer polar-day manual logging, future prayers stay locked on a valid trip from a polar home, input-keyed Quran forecasts, same-day home-only travel freezes, PDF conversion checkpoints, and the lobby’s locally saved three-day return plan.
- **Verified:** `MadarCore` return-plan tests 3/3; `BahwLobbyUITests/testThreeDayReturnPlanPersistsLocallyAndOpensItsRooms` 1/1 on iPhone 17 Pro/iOS 26.5, including Quran/habits routes and app relaunch; prior focused prayer, Quran, habits, and PDF checks remain as recorded; `git diff --check` clean.
- **Differences left:** no canonical screenshot for the return state; default L/light evidence is in `Artifacts/codex-bahw-return-final-shots/`. Prayer engine fix has no visual change or canonical; PDF progress capture remains `Artifacts/codex-mihbara-checkpoint-r5-export/D0B359E0-234A-44C9-8A81-676C877E302C.png`.
- **Not verified:** owner visual/device acceptance for the new card, CloudKit, signed release, or diary freeze-boundary behavior after prayer-setting changes.
- **Next:** continue scanning item 27 for reproducible journey gaps; J05 freeze-boundary field decision still awaits the owner. No `ready` card is listed.
- **Model/effort:** not exposed / not exposed. Helpers did bounded read-only scans of lobby return storage and dates; no owner data was delegated.
- **Usage:** live check: 28% used in the five-hour window and 15% weekly; continue until about 5% allowance remains, preserving commit/handover reserve.


## Handover — حماية رصيد الحساب المخفي، متابعة مدار — 2026-10-26 — Codex
- **Works now:** محرر الحساب لا يعرض رصيد البداية المحمي قبل «أظهر الأرقام»؛ وبعد الإظهار يبقى رصيد نقطة التحقق الثابتة غير قابل للتحرير.
- **Verified:** `MoneyAccountsUITests` 2/2 على iPhone 17 Pro / iOS 26.5 (`codex-money-account-hidden-reveal-20261026-r1.xcresult`)، وصور الحالتين المحجوبة والمكشوفة محفوظة؛ فحص `git diff --check`.
- **Differences left:** الورقة المحجوبة لا تملك صورة معيارية؛ قبول المالك البصري لم يحدث.
- **Not verified:** تجربة جهاز المالك. وجد الفحص أن هدف الاحتياطي المحفوظ يعبأ في حقل `MoneyReserveTargetView` مع إخفاء الأرقام.
- **Next:** عالج تسريب `reserveTargetMinor` في M5-V03: لا تعرض الحقل ولا تسمح بالحفظ قبل الإظهار؛ أضف حالة اختبار مركبة، ثم ارجع لمواصلة مسح التطبيق.
- **Model/effort:** Codex، غير مكشوف. **Usage:** 34% مستخدم من نافذة 5 ساعات و25% أسبوعيًا عند التسليم؛ أوقف العمل بطلب المالك.
