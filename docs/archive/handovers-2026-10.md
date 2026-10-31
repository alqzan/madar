
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

# Handovers moved from docs/PROGRESS on 2026-11-01

## Handover — روابط المحبرة وتحديثات القرآن AU-95 — 2026-10-31 — Claude
- **Works now:** رابط المحبرة الجذري يغلق ورقتي الكتاب والحديث؛ أي رابط محبرة يصل وفي المحبرة ورقة مفتوحة (الدفتر مثلًا) ينتظر إغلاقها فلا تضيع مسودة ولا يُهمل الرابط؛ تحديث شاشة القرآن الذي يصل أثناء عملية جارية يُعاد بعد انتهائها.
- **Verified:** القرآن `AU95-r4` ١٣/١٣؛ المحبرة `AU95-r5` ٥٠/٥١ على iPhone 17 Pro / iOS 26.5، والفاشل نجح منفردًا في `AU95-r6` ١/١؛ الاختبار الجديد للحديث نجح. بناء generic-simulator نجح.
- **Differences left:** لا فرق بصري.
- **Not verified:** سبب فشل `testMissingPDFRestoresToItsOriginalBookAndOpens` في الدفعة الكاملة؛ ما جرّبت قبل/بعد على نسخة قبل تعديل المحبرة. سلوك الانتظار مع مسودة دفتر حقيقية لم يُختبر.
- **Next:** حواجز الرسائل/المشاريع/السنة/التصدير؛ القالب في المحبرة لروابط الدفتر؛ ثم تجربة الودجة على iPhone المالك.
- **Model/effort:** claude-sonnet-5-5 / غير مكشوف؛ مساعدو Haiku قراءة فقط. الاختبار الخارجي: القرص ممتلئ (٤ جيجا) — حُذف كاشا DerivedData-check وDerivedData-mihbara (يُعاد توليدهما)؛ `Madar/Artifacts` يشغل ٦٤ جيجا.
- **Usage:** ٢٥٪ من نافذة الخمس ساعات قبل هذه الجولة؛ غير مكشوف بعدها.

## Handover — طابور تعثر القرآن وودجة الصانع AU-95 — 2026-10-31 — Claude
- **Works now:** تعثر يُضغط عليه أثناء حفظ آخر لا يسقط بل يُحفظ بعده؛ ضغط «أنهِ» مرتين لا يعيد تشغيل الإنهاء؛ رابط قالب صانع الودجة يفتح ودجة جديدة ولا يغيّر المحفوظة؛ تأكيد الحذف يحذّر من تعديل غير محفوظ؛ إيصال الميزانية وتصنيف الحركة يؤخران رابط جذر المال أثناء حفظهما.
- **Verified:** `AU95-r3.xcresult` — ١٢/١٢ على iPhone 17 Pro / iOS 26.5 (صانع الودجة ٥، مراجعة القرآن ٥، جذرا المال والقرآن ٢)، منها الاختبار الجديد `testTemplateRouteStartsANewWidgetInsteadOfOverwritingTheSavedOne`. بناء generic-simulator نجح.
- **Differences left:** لا فرق بصري.
- **Not verified:** دفعة سابقة (قبل إصلاح `where`) فشل فيها اختباران من مراجعة القرآن ونجحا بعدها بلا تغيير مقصود فيهما — فشل متقطع غير مفسَّر؛ لا اختبار UI يضغط كلمة أثناء حفظ جارٍ؛ `QuranHomeView.run` يهمل صامتًا ما يصله أثناء الانشغال؛ روابط المحبرة وحواجز الرسائل/المشاريع/السنة/التصدير.
- **Next:** بقية AU-95 أعلاه ثم تجربة الودجة على iPhone المالك.
- **Model/effort:** claude-sonnet-5-5 / غير مكشوف؛ مساعد Haiku للقراءة فقط.
- **Usage:** ٢١٪ من نافذة الخمس ساعات قبل هذه الجولة؛ غير مكشوف بعدها.

## Handover — جذرا القرآن والمال AU-95 — 2026-10-31 — Claude
- **Works now:** `madar://quran` و`madar://mal` يعيدان إلى جذر الغرفة. القرآن يغلق الفهرس والمصحف والأسبوع والخطة والقوة ويُبقي الجلسة والإعداد والقراءة الحرة؛ المال يغلق الشاشات الداخلية وينتظر إن كان في مصروف مسودة (`moneyRootDraftBlockers`).
- **Verified:** `AU95-roots-r1.xcresult` — اختباران جديدان 2/2 على iPhone 17 Pro / iOS 26.5 (`testQuranRootLinkClosesTheOpenIndexAndReturnsHome`, `testMoneyRootLinkClosesTheOpenScreenAndReturnsHome`).
- **Differences left:** لا فرق بصري؛ تغيير مسار فقط.
- **Not verified:** لم يُجرَّب الاختبار أحمر قبل التعديل؛ أوراق المال الداخلية الأخرى (حساب/بطاقة) غير محمية بحاجز مسودة؛ حفظ خطأ القرآن أثناء الانشغال وقالبا القرآن/المال في صانع الودجة؛ روابط المحبرة وحواجز الرسائل/المشاريع/السنة/التصدير.
- **Next:** بقية AU-95 كما في بند «Not verified»؛ ثم تجربة الودجة على iPhone المالك.
- **Model/effort:** claude-sonnet-5-5 / غير مكشوف.
- **Usage:** غير مكشوف.

## Handover — أبعاد تطبيق مدار وودجة الأيام القادمة — 2026-10-31 — Codex
- **Works now:** فُحصت حدود الغرف والودجات، وأُصلحت معاينة «الأيام القادمة» الصغيرة. خُفّفت النصوص المكررة في الصلاة والقرآن واليومية والمال والعادات والبهو والمحبرة ومعرض الودجات.
- **Verified:** اختبار الحدود نجح على iPhone 17 Pro و17e؛ بعد الاختصار نجحت اختبارات الواجهات المختارة ١١/١١، واختبار معاينة الودجة الصغيرة ١/١ على iPhone 17 Pro / iOS 26.5. `git diff --check` نظيف. [قبل](../Madar/Artifacts/owner-review/M4-W01-upcoming-small-17e-L.png) · [بعد](../Madar/Artifacts/owner-review/M4-W01-upcoming-small-copy-after-L.png).
- **Differences left:** لم أجرِ مقارنة canonical شاملة لمسح النصوص؛ لا قصّ ظاهر في معاينة الودجة بعد التعديل.
- **Not verified:** لم تُجرّب إضافة الودجة أو تحديثها على iPhone المالك. أُوقف زحف الأزرار الشامل لأنه لا يقيس حدود الواجهة.
- **Next:** تجربة الودجة على iPhone المالك؛ تبقى M4-W01 «approved — pending owner trial» حتى ذلك.
- **Model/effort:** غير مكشوف / غير مكشوف.
- **Usage:** غير مكشوف.

## Handover — مراجعة عمل Claude في هدف القراءة — 2026-10-31 — Codex
- **Works now:** جلسات القراءة المؤرخة بعد الآن لا تؤثر في تقدير الوتيرة ذي الثلاثين يومًا أو وقت القراءة المعتاد؛ بقيت تقديرات الإنهاء مبنية على الأيام المسجلة.
- **Verified:** `swift test --package-path Madar/Packages/MadarCore --filter ReadingPaceTests` — 5/5؛ اختبارات واجهة هدف القراءة المحددة — 2/2 على iPhone 17 Pro / iOS 26.5 ببيانات اصطناعية (`Artifacts/codex-review-m6-fg-20261031.xcresult`)؛ `git diff --check` نظيف.
- **Differences left:** لا فروق بصرية سجّلها المالك؛ اعتمد لقطة المحاكي في 31 أكتوبر، ولا تعدّ إثباتًا على جهازه.
- **Not verified:** سجل قراءة حقيقي على جهاز المالك؛ إعادة تشغيل حزمة M6-NB كاملة أو مسارات AU-95 غير المرتبطة بالهدف.
- **Next:** أكمل AU-95: جذرا القرآن والمال مع حفظ المسودات، ثم حواجز الروابط المتبقية.
- **Model/effort:** غير مكشوف / غير مكشوف؛ مساعدو Luna للقراءة فقط.
- **Usage:** ٢٪ مستخدم من نافذة الخمس ساعات، ٩٥٪ أسبوعيًا.

## Handover — مراجعة ربط مدار والأزرار AU-95 — 2026-10-30 — Codex
- **Works now:** `.madarPlain` يلتقط النقر على مساحة الزر كاملة؛ تأكيدات إغلاق مسودة التفريغ الصوتي وفهرس المحبرة والمصروف تحفظ المدخل أو تتجاهله صراحة؛ التقاط المصروف ينتظر التأكيد ويرتب الطلبات FIFO؛ وجهات المال والتنبيهات المقصودة تعمل؛ جذرا الصلاة والمحبرة يعيدان إلى الشاشة الأصلية بمسار الإغلاق المعتاد؛ جذر البهو ينتظر إغلاق مسودات العادات؛ `madar://notes` يغلق البحث وينتظر انتهاء محرر النص دون إسقاط المسودة.
- **Verified:** `AU95-diary-root-r4` اختبار UI 1/1: فتح البحث وإغلاقه بالرابط، إبقاء محرر اليوم مفتوحًا أثناء الطلب، ثم الحفظ والتحقق من ظهور النص؛ `git diff --check` نظيف. وتبقى إثباتات هذه البطاقة: `r90` 5/5؛ `r91` FIFO/dedupe 1/1؛ `r86–r89` محرر التفريغ وفهرس المحبرة 1+1+1+2؛ `r67` الصلاة 1/1؛ `r62` المحبرة 1/1؛ `r92` العادات 2/2؛ `r93` Quran Drill 1/1؛ `r94` عادات 1/1؛ `AU95-past-day-root-r2` 1/1.
- **Differences left:** لم تُطابق هذه الجولة كل الشاشات مع canonical؛ تغيير المسار لا يغير الشكل. فُحصت سابقًا لقطة تأكيد المصروف فقط؛ لا قبول مالك.
- **Not verified:** R1–R3 لا تُحسب: harness استخدم `madar://diary` وهو مضيف غير مسجل؛ R4 استخدم المسار الصحيح `madar://notes`. الزحف الكامل للبهو، FIFO UI المتتابع، روابط Widgets/الإشعارات من النظام، iPhone المالك، وحواجز جذر الرسائل/المشاريع/السنة/التصدير لم تثبت. أثر تغيير اليوم في محرر مفتوح لا يزال يحتاج UI proof. لا مقارنة canonical شاملة.
- **Next:** أكمل AU-95: أصلح جذري القرآن والمال وفتح أوراق المحبرة من الرابط، واختبر حواجز جذر الرسائل/المشاريع/السنة/التصدير. ثم أكمل زحف التنقلات والأزرار ومطابقة الشاشات. لا تغيّر بيانات المالك.
- **Model/effort:** غير مكشوف / غير مكشوف؛ مساعدو البحث للقراءة فقط.
- **Usage:** آخر قراءة قبل هذا الاختبار كانت ٣٤٪ نافذة الخمس ساعات و٩٤٪ أسبوعيًا؛ أعد قياس المتبقي قبل المتابعة. العمل غير مكتمل.
