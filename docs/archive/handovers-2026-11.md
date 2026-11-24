# Archived handovers — November 2026

## Handover — RV-01 مراجعة وإصلاحات — 2026-11-07 — Codex
- **Works now:** حفظ موضع القراءة يسبق إنهاء الكتاب؛ إلغاء معاينة PDF يوقف عملها؛ سلسلة عادة الورد من القرآن؛ حساب نسب المال ٠–١٠٠٪ يتحمل مبالغ كبيرة ضمن Int.
- **Verified:** `swift test` على MadarCore وMadarMoney وMadarData وMadarCommands وMadarPrayer وMadarQuran نجحت قبل الإصلاحات؛ بعدها HabitWird 1/1، PDFBookImport 8/8، BasisAndClose وCycleEngine 27/27. `xcodebuild test` على Madar 15 Pro Max، iOS 27.0: `testPDFLastPageAsksFinishedAndMovesTheBook` 1/1، النتيجة `codex-review-mihbara-r3-20261107.xcresult`.
- **Differences left:** لا تغييرات تصميم متعمدة ولا مقارنة مرئية جديدة.
- **Not verified:** iPhone المالك وTestFlight بالتغييرات الجديدة؛ إلغاء PDF أثناء النسخ نفسه لم يُختبر زمنيًا؛ لم يُفحص كل المشروع أو كل حدود المبالغ.
- **Next:** تحقق من حساب تنبيه حد الفئة عند المبالغ القصوى، ومن دلالة الحفظ الجزئي عبر وجهين في AppQuranService.swift؛ استكمل المراجعة والاختبارات على الجهاز.
- **Model/effort:** Codex؛ النموذج والجهد غير مكشوفين؛ مساعدون للبحث ومراجعة المال.
- **Usage:** غير مكشوف.

## Handover — PERF-02 بداية التطبيق وTestFlight — 2026-11-07 — Codex
- **Works now:** نشر الودجات يشارك قراءة العادات خلال النشر الواحد ويحتفظ بفشل القراءة؛ رقم البناء 11.
- **Verified:** `xcodebuild test` أربع حالات الودجات والخصوصية 4/4، `codex-startup-focused-20261107.xcresult`، على Madar 15 Pro Max/iOS 27.0؛ `git diff --check`.
- **Differences left:** لا تغيير مرئي مقصود.
- **Not verified:** تعليق البداية على iPhone المالك، أو أن التعديل وحده أزاله؛ الاتصال بالجهاز تجاوز المهلة. اختبار البهو القديم فشل متوقعًا تبويبًا باسم «البهو»؛ المجموعة الواسعة أُوقفت عند حالة طويلة.
- **Next:** أرشفة ورفع 0.1.0 (11) ثم تجربة المالك للبداية؛ إن استمر التعليق فقِس فتح المخزن ولقطات الودجات ومهام البهو على الجهاز.
- **Model/effort:** Codex؛ النموذج والجهد غير مكشوفين؛ مساعدون للبحث.
- **Usage:** ٨٥٪ من نافذة الخمس ساعات عند آخر فحص.


## Handover — تبسيط وآيباد وترتيب القواعد — 2026-11-09 — Claude
- **Works now:** جولة التبسيط (٨–٩ نوفمبر): نصوص الإعدادات تصف الخيار المختار، البهو يسمّي الأشياء الحقيقية، المال (الفائض الأحمر، الاحتياطي ١٢ عمودًا شهريًا، حدود الصرف «من X»، علامتا «٬/٫»). الآيباد له تخطيطه (شريط جانبي، البهو ٨ أعمدة، الغرف عمودان في الأفقي، المصحف وجهان، صفحات كاملة). كل زر ممتلئ يُضغط على كامل مساحته (218 زرًا). آخر رفع 0.1.0 (21) من `dcaf8563`. بعده: تسريع قراءة الصلاة وتراجع العادات (غير مرفوع).
- **Verified:** `MadarPrayer` 38/38؛ `MadarCommands` (Habit|Replay) 42/43؛ `ButtonEdgeTapUITests` يفشل على الكود القديم وينجح الآن؛ اختبارات التبسيط في صفوف 8–14 من اللوحة. القواعد: `cmp CLAUDE.md AGENTS.md` و`git diff --check`.
- **Differences left:** تصاميم المال والبهو والآيباد built — لم يرها المالك.
- **Not verified:** معالجة Apple للبناءات 16–21 وتثبيتها على iPhone المالك؛ آيباد حقيقي؛ قارئ المحبرة في الأفقي. فشل واجهة قائم: `PrayerFirstDayUITests/testPolarDayLetsMeRecordAPrayerManually` عند `reveal(streaks)` (بطاقة السلاسل ظاهرة لكن `isHittable` خاطئة والنقر لا يفتحها، ٤ محاولات بلا التزام).
- **Dead code (صف 16–17):** حُذف ١٩٢٢ سطرًا غير مستعمل والتطبيق يُبنى؛ الاختبارات الأربع الفاشلة كانت قديمة وصُحّحت (لا تغيير في المنتج)، وكل حزم الاختبار ناجحة: Core 184، Data 115، Commands 272، Prayer 38، Money 208.
- **Next:** حالة واجهة صلاة/عادات واحدة لتغيير التسريع؛ فشل السلاسل القطبي؛ ثم تدفقات الاستعمال (عدد النقرات في التسجيل والحقول الزائدة). البناء التالي لـTestFlight يضم التسريع وحذف الكود الميت.
- **Model/effort:** Claude Opus 5.5؛ الجهد غير مكشوف؛ مستشار واحد، بلا مساعدين.
- **Usage:** ٩ نوفمبر: الخمس ساعات ١٤٪ مستخدمة؛ الأسبوعي ٩٥٪ مستخدم (يبقى ٥٪، التوقف عند ٢٪).

## Handover — متابعة كلود وصحة القراءة الكسولة — 2026-11-09 — Codex
- **Works now:** فشل قراءة جداول الصلاة لا يُعرض كسجل فارغ ولا يُحفظ في الذاكرة؛ الخطأ يصل إلى المستدعي، وإعادة المحاولة تنجح. حساب المكان والمواقيت وحده يبقى بلا قراءة سجل. لا تغيير مخطط أو قواعد أو بيانات مالك. صُحّحت بيانات ومسارات اختبارات الترحيب القطبي والسنة والعادات؛ توحيد عقد «صافي رصيدك» وفحص العقود مع قرارات ٦–٩ نوفمبر. حذف العوائق القديمة من الطابور اعتمادًا على أدلة كلود الأحدث. رُفع 0.1.0 (22) داخليًا من `9044e1fc` مع زيادة رقم البناء مرة واحدة؛ يضم تسريع كلود وحذف الكود الميت وإصلاح القراءة وتحسين الألوان.
- **Verified:** حزمة الصلاة 42/42، أوامر Prayer|Replay 26/26؛ اختبارات حقن فشل القراءة تفشل على السلوك السابق ثم تنجح بعد الإصلاح. `OWNER-continue-flows-20261109-r4.xcresult`: واجهة السنة والعادات 2/2؛ التكامل فيه 1 نجاح/1 فشل لتوقع «الفجر» القديم. `OWNER-prayer-final-20261109-r5.xcresult`: 4/4 (قراءة الخلفية، فجر غدًا، روابط الإشعارات، تسجيل قطبي وتعديل الأمس). البناء الأصلي للاختبارات نجح على Xcode 27.2 ومحاكي iPhone المحدد/iOS 27.0. العقود 87/87، نسخ القواعد متطابقة، `git diff --check` سليم. مراجعتان مركزتان للقراءة فقط (المستودع وتحسين الألوان): لا ملاحظات قابلة للإجراء. دفعة الألوان `OWNER-colour-clarity-20261109-r1.xcresult` 2/2، وفحص المصادر الساكن صار STATIC PASS: 464 مصدرًا، 4 كتالوجات، 38 زوجًا محسوبًا؛ لا تخفيف للفاحص. إعادة التكامل بعزل صريح للمضيف `TEST_RUNNER_MADAR_UI_STORE_ID=OWNER-integration-host-20261109` نجحت 3/3 في `OWNER-isolated-integration-final-20261109.xcresult`؛ تأكد إنشاء مجلد UITestStores المسمّى. Release archive والتوقيع والتصدير والرفع نجحت في `OWNER-TestFlight-22/`؛ التطبيق والودجت 22/iOS 27/هاتف وآيباد، ولا صلاحيات iCloud؛ Apple أكدت بدء المعالجة.
- **Differences left:** تحسينان مرئيان مقصودان، built — awaiting owner: شاشة الفتح فاتحة/داكنة بألوان البهو، وتقدّم صورة الكتاب فوق سطح مكتب معتم معتمد التباين. الدليل `OWNER-colour-clarity-20261109-r1-shots/OWNER-launch-{light,dark}-L.png` و`FB36-book-card-L.png`؛ فُحصت الصور. لا canonical أصلي لهاتين الحالتين ولا ادعاء مطابقة. صور اختبارات المنطق السابقة اختيارية بـ`MADAR_SHOT_DIR`.
- **Not verified:** فشل الألوان التسعة في `OWNER-shipping-source-gate-20261109.log` تاريخي وصُحّح في صف 19؛ `OWNER-shipping-source-gate-final-20261109.log` ينجح ساكنًا، لكنه ما زال يطلب تتبّعًا يدويًا لـ6051 سطرًا، فلا ادعاء باكتمال المراجعة العامة أو قبول M0. r1–r3 تحوي إخفاقات قديمة محفوظة. r2 توقف اختبار العادات قبل التدفق بسبب امتداد الودجت داخل مسار محاكي `System/Dead`؛ المكدس ExtensionFoundation بلا إطار مصدر مدار، ونجح التدفق بعد تشغيل المحاكي مجددًا. لا تحقق من جهاز المالك أو أدائه، آيباد حقيقي، أو اكتمال معالجة Apple للبناء 22. محاولة المتصفح للقراءة توقفت عندما عاد المالك لاستخدامه؛ البحث المحدد في البريد المتصل لم يجد إشعار Apple مطابقًا، فلا ادعاء باكتمال المعالجة.
- **Next:** بعد اكتمال المعالجة: قبول المالك على iPhone/iPad للبناء 22. المتابعة من طلب التبسيط الحالي بتدفق محدد ذي تحسّن ملموس؛ لا تكرار لمراجعة عامة أو اختبارات نجحت بلا سبب جديد. التتبّع اليدوي للمصادر وقياس الأداء على الجهاز ما زالا منفصلين، وFX العام ينتظر قرار قاعدة/بيانات. لا حاجة لإعادة رفع الكود نفسه؛ النشر العام منفصل.
- **Model/effort:** Codex؛ النموذج والجهد غير مكشوفين؛ مساعدان للقراءة فقط بإعدادات موروثة غير مكشوفة. كل التعديلات والبناء والمحاكي والالتزام من الوكيل الرئيسي.
- **Usage:** المتبقي عند إقفال الدفعة: الخمس ساعات 32%، الأسبوعي 24%. حد هذه الجلسة 20% متبقية؛ لم تُستخدم أرصدة إعادة ضبط.

## Handover — المذكرات: المراجعة النقدية كاملة والأفكار المختارة (الدفعات A–C) — 2026-11-12 — Claude (Sonnet ينفّذ، Opus يراجع)

- **Works now:** الملاحظات الـ٢٤ من المراجعة النقدية مصلحة (الدفعة A). الرئيسية تعرض اليوم أولًا مع شريط السنين، وفيها مكان كتابة واحد يكبر بنص منسّق حقيقي (عريض ومائل وعنوان، ويُخزَّن Markdown)، والرجوع بالسحب يعمل (الدفعة B). اليوم مقسوم بالصلوات مع أوقاتها، وفي التقويم صور مصغّرة، وفيه وضع القراءة «اقرأ»، و«محاسبة اليوم» عند الطلب فقط، وبنك أسئلة عربي بلا ترجمة، وتفريغ حي من ملف المسجّل نفسه (الدفعة C، ومعها إصلاح المخزن المؤقت f5ea64b3). التاريخ لم يعد يتكرر تحت عنوان الرئيسية. لا وسوم ولا قفل ولا قلم ولا Siri، بقرار المالك.
- **Verified** (Madar 15 Pro Max، iOS 27.0): تشغيل المذكرات الكامل، ١٧ صنف واجهة و١٣ صنف تكامل: ١٠٦ نجح، ٤ متخطاة، ٠ فشل (`Madar/Artifacts/CLAUDE-diary-final.xcresult`). بعد تعديل الرئيسية: DiaryHomeTodayUITests وDateLabelsUITests وDiaryCustomizeUITests ١٠/١٠ (`Madar/Artifacts/CLAUDE-diary-home-date.log`). MadarCore: DiaryPrayerPeriodsTests ٦، DiaryQuestionBankTests ٤، DiaryRichTextTests ٩/٩، DiaryVoiceRecoveryTests ٢/٢. فحص بصري على عيّنة `periods`: بطاقة اليوم وعناوين فترات الصلاة مع أوقاتها.
- **Differences left:** الكتاب السنوي والتصدير يقرآن على الخيط الرئيسي (اختيار مقصود). `notes.homeShape` باقٍ في المخطط ويُتجاهَل.
- **Not verified:** الكتابة بالكيبورد العربي، والميكروفون الحقيقي والتفريغ الحي على جهاز، وتخطيطات الآيباد للدفعات الجديدة، ومسار اختيار الأسئلة بالنموذج المحلي، ووضع القراءة بأحجام AX، ورابط «محاسبة اليوم» بعد العشاء في وقته الحقيقي، وقبول المالك على جهازه.
- **Delivery:** نسخة 0.1.0 (41): الأرشيف نجح (ARCHIVE SUCCEEDED، CFBundleVersion 41)، والرفع إلى TestFlight الداخلي نجح («Upload succeeded» الساعة 13:55:37)، والسجلات في `Madar/Artifacts/OWNER-TestFlight-41/`. لم ننتظر معالجة Apple بقرار المالك، ولم يُقبل بعد على جهاز المالك. قاعدة جديدة في البروتوكول: نسخة واحدة في آخر كل طلب، ثم دفع `main` إلى GitHub.
- **Next:** يجرّب المالك المذكرات على الآيفون ويعطي ملاحظاته. لقطات الآيباد لصفحة اليوم والرئيسية. تذكير المالك بتغيير «المشاريع» بعد FB-27.
- **Model/effort:** التنفيذ Sonnet 5.5 بجهد medium، والمراجعة والتحقق النهائي Opus 5.5 والجهد غير معروض.
- **Usage** (قبل الأرشفة): حد الخمس ساعات ٦٠٪ مستخدم (يبقى ٤٠٪)، والأسبوعي ٦٤٪ مستخدم (يبقى ٣٦٪).

## Handover — العادات بدل الصلاة — 2026-11-17 — Claude

### Works now
- «العادات» is the first tab on iPhone and Mac, in place of the prayer tab; `madar://salah` and `madar://prayer` open habits. Prayer screens, widgets, controls, Live Activity, Siri shortcuts, the watch prayer card, the night-review prayer line, legacy prayer import and prayer-only settings have no entry point. The prayer-time engine stays («المواقيت» in Settings) for prayer-anchored habit times. `PrayerNotificationCoordinator.prayerLoggingRemoved = true` switches off prayer requests and ends any countdown activity.
- Every launch tombstones all live `PrayerLog` and `QadaItem` rows with a deletion barrier (`PrayerHistoryMaintenance.removeAllPrayerRecords`), on the owner's explicit order «امسح كل شي خلاص معاد ابيه».
- `HabitJamaahConversion` turns a Jama'a-linked habit into the user's own daily habit «صليت كل الصلوات بجماعة» (push, Isha +60…+240 min, new rule from today; older rules kept). The habits room offers it as a ready preset; the editor no longer offers the Jama'a source.
- Quran wird: with «بعد الفجر», a second request `quran.<day>.again` comes after Isha while the wird is still not done.
- Streak capsule «ب» (`HabitFlame`): room colour and a lit flame when done, grey when waiting, red tint, unlit flame and hourglass when missed once. One final alert `habits.<day>.final.<id>` 90 min after Isha on the second day. Room-coloured tags and orbit beads (`habitRoomColour`). `HabitType` sets the habits room in Thmanyah Serif Text and Serif Display Black.
- Ideas: 1 (per-habit notification category with the goal, half the goal and «كمية ثانية» text input), 5 (Friday lobby note), 6 (30/100/365 milestone line), 19 (one-at-a-time note in the new-habit editor), 20 (ending a habit shows its summary first).

### Verified
- iOS Simulator build and test build succeeded (iOS 27.0, `Madar 15 Pro Max`).
- `swift test`: PrayerHistoryMaintenanceTests 2/2; HabitJamaahConversionTests and HabitWirdTests 2/2.
- MadarTests (integration) full run: 296 executed, 15 assertion failures in 6 tests, all from prayer removal. After the fixes the affected suites ran 41 tests, 0 failures, 4 skipped on purpose (`XCTSkip`: AppInboxLifecycle ×2 and CaptureIntent ×2 assert prayer facts and need rewriting on a habit command). Quran/notifications 19/19.
- Build 0.1.0 (53): ARCHIVE SUCCEEDED, EXPORT SUCCEEDED, «Upload succeeded» at 17:31 Riyadh, 17 Nov (`Madar/Artifacts/OWNER-TestFlight-53/upload.log`). Apple processing not awaited. The first export failed («method» had no options) because the Codex watch app was archived as a second top-level app; `MadarWatchApp` now has `SKIP_INSTALL: YES`, so it ships only inside Madar.app.

### Differences left
- No screenshots captured of the new habits look (capsule, tags, fonts). The period cards keep their old layout with the new fonts.
- Prayer views, intents and widget structs are still compiled but unreachable. `PrayerFirstDayUITests`, `PrayerCountdownUITests` and the other prayer UI tests were not run and will fail; remove or rewrite them.

### Not verified
- UI tests were not run (HabitsUITests was updated for the new end-habit confirmation). Owner-device acceptance and notification delivery on a real device are not verified.

### Next
- Remaining approved ideas: 2 (weekly behaviour suggestion, applied only on approval), 4 (one notification for habits done back to back), 8 (a goal that grows gradually), 9 (a reminder that learns the usual logging time), 10 (a habit you quit, counted as days since), 12 (an earned rest day every 30 days), 14 (Health sleep and workouts), 16 (Ramadan mode), 17 (Monday/Thursday fasting asked the night before: weekly weekdays [2,5] with a Fajr-anchored window starting about −480 min). 8, 12 and 16 touch the habit rule or engine, so they need engine tests from the spec.
- Rewrite the 4 skipped tests on a habit command, and delete or rewrite the prayer UI tests.

### Follow-up the same day (build 54) — Sonnet built, Claude reviewed
- Built by Sonnet on the owner's order, reviewed and re-verified by Claude:
  - Period cards redesigned (ring, title, «x من y»).
  - 17: a «صيام الإثنين والخميس» preset, asked the night before. Claude made the night-before ask a plain question with no log button (`habits.<day>.eve.<id>`), so it can no longer log Sunday.
  - 4: reminders within 15 minutes arrive as one notification.
  - 9: a push habit with no window is reminded at the median of its last 14 logged times (needs 3 logs).
  - 2: a Saturday lobby suggestion for a daily habit met fewer than 3 of 7 days. It opens the habit and changes nothing.
  - 14: sleep and workout units from Health (HealthKit queries compile only, not verified on a device).
  - 12: one earned rest day per 30 met days.
  - 16: Ramadan presets (qiyam after Isha, wird before Suhoor), shown in Ramadan only.
  - Prayer UI tests deleted.
  - HabitsUITests repaired. Claude made `testAtRiskFixedHabitsStayHiddenBeforeTheirDates` match only `habit-row-` rows; it had matched the orbit beads.
- Not built:
  - 10 (a habit you quit). Needs a new `HabitMeasure.abstain` and many surfaces; no schema change.
  - 8 as a user feature. The engine already handles dated rule versions; `habit.save` must write future-dated steps.
  - 16 for existing habits shifting their times. Needs a per-policy Ramadan window field.
- Verified by Claude:
  - MadarCore 251/251 and MadarCommands 325/325.
  - App integration slice 28 executed, then RoomNotificationsIntegrationTests 18/18 after the eve fix.
  - MadarUITests/HabitsUITests 25/25 (`Artifacts/review-1794929621.xcresult`).
  - Screenshots `Madar/Artifacts/verify/habits-showcase.png` and `habits-atRisk.png`.
- Untracked `.codex/` and `.agents/skills/verify/` appeared from an outside copy of the verify setup (not from this session) and were left uncommitted.

### Second follow-up (build 55): «كملها كلها»
- Built by Sonnet and reviewed by Claude. No schema change.
- Idea 10, a habit you quit (`HabitMeasure.abstain`):
  - The streak is clean days since the last slip. Only an explicit «زلّة» with confirmation logs.
  - Excluded from reminders, the lobby, widgets, intents and the orbit.
- Idea 8, a goal that grows («يكبر تدريجيًا»): `HabitSchedule.plan` writes future-dated policy steps in the same `habit.save`.
- Ramadan times for any windowed habit: policies dated 1 Ramadan and 1 Shawwal, from the Hijri calendar.
- Review fix by Claude: a later save had tombstoned all future steps, even on a rename. Now an edit that leaves the rule unchanged re-sends the planned steps; only a change to the goal or time replaces them, and the editor copy says so.
- Data safety: future steps are tombstoned with `deletedAt` and `deletionBarrierAt`, restored rows get `restoredAt`, and undo goes through the inverse change list.
- Verified by Claude:
  - MadarCore 258/258 and MadarCommands 330/330.
  - App integration 53/53 and HabitsUITests 26/26 (`Artifacts/review3-1794932729.xcresult`).
  - `verify-smoke.sh` passed on its first real run.
  - The editor's Ramadan controls were checked on the simulator.
  - Not visually checked: the quit-habit hero and the next-step line.

### Third follow-up (build 56): «Yes, match it» — the room now follows the approved canvas
- The owner asked if the room matched the approved design (`Habits.dc.html`, artifact 4Gvv3Bz9ckqtkonPq6q7bZ). It did not, and Claude said so. This build fixes it. Sonnet built it and Claude reviewed it.
- Room order, top to bottom:
  - the period cards
  - the daily habits
  - the longer-period habits
  - archived habits
  - the selected habit's story card (`habit-story`; selecting a habit scrolls to it)
  - the orbit, in room colours
  - the analysis cards from the new pure `HabitRoomInsights` (MadarCore, 13 tests): trend, weekday pattern, best and worst month
  - «عادة صغيرة جديدة»
  - the room tags
  - the hadith footer
- Removed: the extra «سجّل الماء» card and the segmented switch. Neither is in the canvas.
- A new `history` fixture backs the analysis cards in tests. `HabitRepository` now records `loggedAt`.
- Lobby UI tests brought up to date with removed features (no XCTSkip):
  - Deleted `testLobbyLeadsWithNextPrayerBeforeAdhanAndIsQuietInsideTheWindow` and `testNextFajrAfterIsha`. They tested the lobby's next-prayer block and suggestion, which ended with the prayer room on 17 Nov. Sanctity itself stays covered by the engine tests.
  - The arrange, greeting and tab-bar tests now use the habits block and the remaining room tabs.
  - The diary test now saves with «تمّ». There has been no cancel for new words since 14 Nov (T10).
- Not visually checked: the quit-habit hero, dark mode, Hijri-first, iPad.
- Build 0.1.0 (56): archive succeeded, upload succeeded on 17 Nov 2026 (`Madar/Artifacts/OWNER-TestFlight-56/upload.log`). Apple processing was not awaited.

### Model/effort
- claude-opus-5-5, effort not exposed. Helper: Sonnet (owner's order) for all three follow-ups.

### Usage
- Five-hour window 63% used at commit time (37% left); weekly 10% used.


## Handover — حركات وإيموشنز من منشور مكتبات الواجهات — 2026-11-22 — Claude

### Works now

- Owner sent an X post (15 web UI repos and a video) with «مليان ايموشنز وتحريكات… خذ منها», then approved all three mockups («تم اعتمدها كلها»). Native SwiftUI, each motion runs once on an event; Reduce Motion gives the end state. Queue row 32 lists all ten pieces.
- Habit ring (`HabitRingGlyph`, `HabitMiniRing`): fills smoothly; on completion one light circles the ring, a small bloom and a success tap (`App/MadarMotion.swift`).
- Lobby: tiles press and spring back, enter one after another on the first lobby view of a launch, habit counts roll, the lead «الآن» card gets one pass of light when a new step leads and the steps slide into order. Habits room month bars grow from the right.
- Undo: one pill everywhere (`AppSession.undoToast()`): sized to its words, a hairline drains over its seconds, the removal before it peeks behind dimmed. In the Quran session log and the Mihbara notebook the deleted item stays in place struck through with «تراجع», then folds away.
- «ابحث في مدار» (`App/MadarSearchView.swift`): magnifier beside «رتّب» (pull-down stays the refresh). Finds habits, surahs, books, diary lines and money movements (names only, no amounts), opens each in its room. Read-only.
- Lobby money tile: figures roll, the period line draws from the right, today's spend bar grows in. Home-screen widgets unchanged (`MoneyWidgetContent.animated` defaults to false).

### Verified

- iPhone build and Mac build passed. RU1 separator check passed. `git diff --check` clean.
- UI, ad-hoc signed, Madar 15 Pro Max iOS 27.0, synthetic stores: `CLAUDE-motion-20261122-r2.xcresult` BahwLobbyUITests 13/13 + HabitsUITests 26/26; `-r4.xcresult` BahwLobbyUITests 14/14 (new `testLobbySearchFindsAHabitAndOpensIt`), QuranHistoryUITests 3/3 (in-row undo), BahwCustomize 7/8, DiaryCustomize 1/2, QuranPlan 3/4, MoneyExpense 6/7, Mihbara undo slice 4/8 run (3 skipped, 1 failed).
- The 5 failures fail identically without this change (`CLAUDE-motion-baseline-20261122.xcresult`, 5/5 failed on the stashed baseline): their asserts predate FB-32 (undo only after a removal) and the 22 Nov reset-undo decision.
- Real app (`verify-smoke.sh`, lobbySix): logged three habits from the lobby; frame strip `Madar/Artifacts/verify/motion-sweep-frames.png` (from `motion-sweep.mov`) shows press, fill, travelling light, bloom. Search sheet opened from the lobby.
- r1 (all 39 failed) was my unsigned test build: the App Group was missing, so the app opened on «تعذّر فتح مدار». Checklist row 19 committed separately.
- Owner «كل شي اصلحه»: the five stale UI tests now assert today's rules, and a new test covers the Mihbara in-row undo. `CLAUDE-undo-tests-20261122-r1.xcresult` 5/6 passed: DiaryCustomize reset-undo, Mihbara reader reset-undo, new `testDeletedNoteOffersUndoInItsOwnRow`, MoneyExpense (no undo after a save, same figure reopens), QuranPlan (Hijri secondary, no undo for a settings change). `-r3.xcresult` BahwCustomize `testHabitReminderDefaultUndoAndNewHabit` 1/1 passed: linked source is now «ورد الحفظ» (prayer source left on 17 Nov) and a saved habit opens through «التفاصيل».

### Differences left

- All built — awaiting owner. No canonical images for these motion states.

### Not verified

- Arabic typing in search on the simulator (the UI test types it). iPad, owner device, Apple processing.

### Next

- Owner tries build 0.1.0 (63) (logs `Madar/Artifacts/OWNER-TestFlight-63/`); 62 carried the motion, 63 adds only the test repairs.

### Model/effort

- Claude, claude-opus-5-5, effort not exposed. No helpers.

### Usage

- Start: five-hour 2% used, weekly 39% used. Mid-run: five-hour 17%, weekly 41%.


## Handover — «اكمل… طور كل مايحتاج» — 2026-11-22/23 — Claude

### Works now

- Queue row 33. Owner: «اكمل متاكد فيه اشياء باقي بالامكان تطويرها», then «أكمل شغل الين مايبقى من اليوزج الا ٥٪» (protocol updated, DECISIONS row).
- Travel is back (`App/BahwTravel.swift`): since 17 Nov nothing could start a trip, so home-only habits, travel prayer times, diary travel lines and the money trip budget were dead. A pill under the lobby greeting opens «هل أنت مسافر؟» (local method suggested) or the open trip (stops, «أنهِ الرحلة»). Ending a trip far from home counts as «مقيم هنا» for that place.
- Habits room offers split into «من غرف مدار» (counted) and «عادات جاهزة» (asked). Quran plan forecast: one footnote, preview note only while previewing. Mihbara empty «أبي أقرأها» shelf has «أضف كتابًا». Quran «سجلّك» empty state no longer repeats its summary.
- 23 Nov (row 33 items 8–15): «فاتك وِرد» names the portion; accounts page and money log lose repeated lines; settings pages of one section no longer repeat their title («اختياراتك»); year page strip no longer repeats the hero, «رأس السنة ١٤٤٨هـ»; money grammar and dot fixes; reader «بقي نحو …».
- Stale UI tests repaired: FoundationUITests (2 of 3), MoneyGoalUITests, MoneyObligationsUITests, MoneyReconcileUITests (settings home no longer has `money-open`; FB-32 removed save undo; calendar opens on the default first due month). Checklist row 20 (wait for a real ready state before a tap).

### Verified

- iPhone and MadarMac builds succeeded. UI ad-hoc signed, Madar 15 Pro Max iOS 27.0, synthetic stores: `CLAUDE-travel-20261122-r7.xcresult` 6/6 (two new travel tests ×3); `-r4` BahwLobbyUITests 15/16 (the failure was the new resident test, which found the pill-stays bug, fixed in r7); `CLAUDE-polish-20261122-r1` HabitsUITests 26/26 + QuranPlanUITests 4/4; `-r2` Mihbara want-shelf 2/2 + QuranHistoryUITests 3/3. Travel flow also driven by hand (question, start, trip sheet, resident).
- Earlier in this session: five stale undo tests repaired + Mihbara in-row undo test, build 63 uploaded.
- 23 Nov: MoneyLog 4/4, QuranYear 3/3 (new missed-day test), MoneyAccounts 14/14, CustomizeSearch + BahwCustomize 9/9, Foundation 2 of 3 repaired pass, BahwYear 4/4, MoneyGoal 3/3, MoneyObligations 7/7, MoneyReconcile 4/4; verify-smoke passed.

### Differences left

- Travel pill and sheets have no canonical; built — awaiting owner (`OWNER-22nov-travel-question-L`, `OWNER-22nov-trip-sheet-L` in the r7 bundle).

### Not verified

- Real location on a device (the simulator uses `MADAR_UI_TRAVEL_FIX`); multi-stop trip («وصلت إلى …؟») not driven; iPad layout of the pill not captured; owner device; Apple processing.
- A tap made while a sheet is still closing is dropped by iOS (seen for every lobby sheet); not changed.

### Next

- **Open defect:** on a pushed settings page (backup), a focused field near the bottom is covered by the floating tab bar, which rides up with the keyboard strip (`TabShell.phoneBody` overlay on `rooms`). Two keyboard-notification attempts did not change it on the simulator and were reverted; `FoundationUITests.test_M0S2_SecurePasswordTypingTransport` still fails there. Measure the rooms' frame with the keyboard up, or host the bar outside the keyboard-avoiding container.
- Other UI test classes may still use stale settings paths (`money-open` without the search, «الإشعارات» as a settings button); run a class before relying on it.
- Not applied: dead «jamaah» branches in the habits editor (converted at launch); year page empty states without a button (filter «المواسم»).
- Then: build 64 (bump `CURRENT_PROJECT_VERSION`, archive, upload, push).

### Model/effort

- Claude, claude-opus-5-5, effort not exposed. Read-only Sonnet helpers inspected habits, Quran/Mihbara, diary and money.

### Usage

- Start: 5-hour 36% used, weekly 43%. After the travel and polish batches: 5-hour 59%, weekly 46%. After the window reset (23 Nov, 01:40): 5-hour 16%, weekly 51%.


## Handover — حركات في كل زاوية، إشعارات أذكى، مراجعة أخيرة — 2026-11-23 — Claude

### Works now

- Rows 34–36. The owner rejected the six room redesigns («ولا وحده اعتمدها… بس تحسن الموجود»), then approved every UI-Moments motion («في كل مكان وكل زاوية»). Built inside the current designs; Reduce Motion stops each one and shows its end state. Details in row 35 and DECISIONS (23 Nov).
- New shared pieces in `App/MadarPlainButtonStyle.swift`:
  - `MadarInkToggleStyle`, set at the root, so every switch fills with the room's ink. A hidden label gives only the track. `.accessibilityRepresentation { Toggle }` lets UI tests still see a switch. Tests must tap the element itself when it has no inner switch (MoneySettingsUITests now does).
  - `madarSwipeConfirm`, used for the Mihbara trash purge and the year-page day delete. UI tests use `app.slideToConfirm()` (helper at the bottom of BahwYearUITests.swift).
- Notifications (row 36):
  - A line written, edited or deleted re-plans the evening line reminder at once. A new day re-plans while the app is open.
  - The wird reminder names the portion (or the faces due), worded from the plan's own snapshot.
  - Diary reminders keep fixed offsets behind the Quran reminder, so they no longer pile into one minute.
  - Bill timing is in words. Retired salah leftovers are removed.
- Final review: the owner asked for Fable, but Fable needs paid usage credits and extra usage is off, so the review ran on Opus. All its High and Medium findings and most Low ones were fixed (listed in row 35).

### Verified

- MadarCore package: 264/264 (`swift test`), including the new diary offset golden test.
- iPhone UI and integration (ad-hoc signed, Madar 15 Pro Max iOS 27.0, synthetic stores):
  - `r35` 44/44 and `r36` 56/56.
  - `r37` 36 passed, 28 skipped (old FB-33 Quran home skips).
  - `r38` 130/137: SecurePassword known failure; MoneySettings flexible switch, fixed later; 5 skipped.
  - `r39` 112/131: the new wird test's diacritics, test fixed; 18 skipped (FB-34 Mihbara, Photos fixture).
  - `r40` 79/83: the review's `.toggleStyle(.switch)` gave a zero-frame switch, reverted; the wird text cache leaked between sessions, now keyed per session.
  - `r41` 41/41: Quran outside and room notification integration, MoneySettings flexible, RoomWidgets opt-in, BahwYear, BahwCustomize, DiaryCustomize.
- `verify-smoke.sh` passed (showcase habits). The ink switch was driven on and off by hand (`Artifacts/verify/OWNER-23nov-ink-switch-on.png` / `-off.png`).

### Differences left

- The motions have no canonical; built — awaiting owner. Card and bill names stay off the lock screen on purpose (M5-V12 test, RU2). Quiet hours stay off by default (schema).

### Not verified

- iPad layout of the new sheet and switch, owner device, Apple processing.
- The paper plane, card fan, tide and seal were checked by building and by the screens' UI tests, not frame by frame.
- `FoundationUITests.test_M0S2_SecurePasswordTypingTransport` still fails (open defect below).

### Next

- Open defect from the previous handover: on a pushed settings page, the floating tab bar covers a focused field near the bottom (SecurePassword test).
- Obsolete skipped tests (FB-33 Quran home, FB-34 Mihbara desk) should be deleted with a reason, not kept as skips.

### Model/effort

- Claude, claude-opus-5-5, effort not exposed. Read-only helpers: a Sonnet notification map and an Opus final review (Fable unavailable: needs usage credits).

### Usage

- After the motion and notification batches: 5-hour 61%, weekly 75%. Delivery: build 64 archived and uploaded to internal TestFlight (`Artifacts/OWNER-TestFlight-64`, «Upload succeeded»); Apple processing not awaited.
