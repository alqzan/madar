## Handover — استكمال الخصوصية بعد كلود — 2026-10-28 — Codex
- **Works now:** قفل التطبيق يمسح لقطات الغرف قبل الحفظ ويمنع إعادة نشرها أثناء الانتقال؛ يحذف إشعارات الغرف القديمة والمسلّمة، ويُبقي تنبيهات الصلاة العامة.
- **Verified:** اختبارات تكامل متسلسلة 4/4 (`codex-app-lock-redaction-20261028-r2.xcresult`)؛ `git diff --check`.
- **Differences left:** لا تغيير بصري؛ قبول المالك لـOR-04 ما زال معلّقًا.
- **Not verified:** التسليم الفعلي عبر مركز الإشعارات، iPhone المالك وiOS 27.
- **Next:** تابع أول بطاقة `ready` في `docs/PROGRESS.md`؛ سؤال تاريخ إيقاف الرحلة/العادات ما زال ينتظر جواب المالك.
- **Model/effort:** غير مكشوف / غير مكشوف؛ ثلاث مراجعات مستقلة للخصوصية، دون تشغيلها للاختبارات.
- **Usage:** آخر قراءة 96٪ مستخدم من الخمس ساعات؛ توقفت عند الاحتياطي المطلوب.

## Handover — تدقيق AU-04…AU-24 — 2026-10-28 — Claude
- **Session 2 (after Codex, 28 Oct night):** AU-23…AU-27 (AU-25 seasons/book progress, AU-26 misleading done states, AU-27 streak zeros, AU-28 widget maker saved note, AU-29 money goal/salary, AU-30 expense save hint, AU-31 qada title privacy, AU-32 lobby ring/all-hidden, AU-33 year «دون ١٪», AU-34 Quran/money sheet reasons, AU-35 backup/habits reasons, AU-36 Mihbara/diary errors, AU-37 prayer/money sheet errors, AU-38 no false calm, AU-39 sheet errors everywhere, AU-40 goal/salary/position, AU-41 make-up/gap close on success, AU-42 rules refusal, AU-43 settings/city/reconcile, AU-44 Hijri correction, AU-45 one photo button); AU-23 (Quran states: no «٠/٠»، no double zeros) and AU-24 (prayer, money, diary, Mihbara states; `MoneyCategoriesUITests` repaired: it failed on base because the limits button sat half under the bottom dimming). Next for the agent who follows: a UX walk of habits/lobby (findings 2, 3, 5, 6 in AU-24's walk were not applied: count shown three times in the habits room, year elapsed/remaining twice, empty «المواسم» filter, the return card's plan), and Mihbara findings 3–6 (library covers/rows, closed wird, notebook). Still open (29 Oct): streak option «ثلاث» lacks «مرات» (schema label); PrayerSettingsView is unused (PrayerRoom never instantiated); first-run «انتقل إلى المدينة» duplicates «لنبدأ» (pinned in five UI suites; product call); backup «النسخ المحفوظة: ٠ تلقائية…» (pinned by `test_fixPrevious_M0T13`). `testBackupFolderPickerCancellationKeepsLocalBackupSettings` fails at :1012 on base too (the system picker «إلغاء» never appears in this simulator).
- **Works now:** معاينة تخصيص المذكرات بأسماء أجزائها؛ سجل جلسات القرآن بطاقة لكل يوم مع «اليوم/أمس» وشارة التقييم و«في صدرك» بالأجزاء؛ صف «خطة الحفظ، من سورة …» أول بطاقة خطّتك؛ شلال الفائض بإشارات فوق الأعمدة؛ حالات فارغة تقود إلى فعل (الحسابات، السجل، القضاء)؛ نصوص المحبرة والمذكرات والعادات والقرآن والإعدادات مصحّحة (AU-05…AU-08)، والعادة الفائتة بوحدتها («فاتك يوم»)؛ العادة ذات التاريخ الثابت لا تظهر في المدار قبل يومها. AU-12…AU-15: نصوص الودجات، بيت الصلاة («آخر ٥ فروض»)، القرآن والبهو والمذكرات والنسخ الاحتياطي، وبقية شاشات المال والمحبرة، كلها بتطابق العدد وبالفصحى.
- **Verified:** DiaryCustomize (aud28i)، QuranHistory 1/1 (aud28j/p)، MoneyAccounts 6/6 + MoneyLog 1/1 (aud28k/l)، MoneyEnvelopes 5/5 (aud28m/n)، DiaryIntention 2/2 (aud28o)، QuranPlanSetup 2/2 (aud28q)، BahwYear 4/4 + Quran Drill/Free/Strength (aud28r)، Habits 15/15 (aud28t)، Lobby+Habits 27/27 (aud28v)، Qiyam 2/2 (aud28u)، إعدادات 6/6 (aud28w)، إشعارات 12/12 (aud28x، إصلاح خصوصية الملخّص تحت القفل)؛ WidgetMaker 3/3 (au12)، صلاة + قيام 5/5 (au13)، RoomWidgetSnapshot 8/8 + Habits 15/15 (au14)، QuranHome/BahwLobby/MoneySettings/DayOne/Intention 20/20 (au14c)، المال ٧ مجموعات + المحبرة 48/48 (au15).
- **Differences left:** أعمدة الدين المخطّطة في رئيسية المال (Z-R12-Home2)، شريط أجزاء «في صدرك» في السجل، ثيمات القارئ في الورقة الرئيسية (أُبقيت عمدًا).
- **Not verified:** `testPolarDayLetsMeRecordAPrayerManually` يفشل على الشيفرة الأساسية أيضًا (aud28za)، لم يُشخَّص؛ ورقة القضاء الفارغة ونصوص PDF/الباركود/المشاريع (لا اختبار يصلها)؛ الجهاز.
- **Disk:** حُذفت ستّ نسخ DerivedData قديمة في `Madar/Artifacts` (~15GB) لأن القرص امتلأ (198MB)؛ `owner-data` والمحاكيات لم تُمسّ.
- **Next:** بقايا AU-07 في نفس الصف (تسمية «يومك/يومياتك/اليومية» في المال)؛ قرار المالك في فكرة سطر دفتر المحبرة على الودجات (Ideas)؛ ثم مراجعة المالك لصفوف AU-04…AU-21. لم تُغيَّر «أبي أقرأها» ولا «٤٠ دقيقة» عمدًا (المواصفة).
- **Model/effort:** claude-opus-5-5، not exposed. Sonnet helpers للقراءة فقط.

## Handover — استكمال تسليم كلود — 2026-10-28 — Codex
- **Works now:** مسار تسجيل الصلاة بلا مواقيت واختيار «أمرّ» ثم السلاسل والسجل متحقق؛ الإصلاح في الاختبار فقط.
- **Verified:** `xcodebuild test … -parallel-testing-enabled NO -only-testing:MadarUITests/PrayerFirstDayUITests`، نتيجتان ناجحتان في `codex-au10-polar-r4.xcresult`؛ صور L/light فُحصت؛ `git diff --check`.
- **Differences left:** لا تغيير في الواجهة؛ تبقى موافقة المالك والفروق المسجلة في الصفوف.
- **Not verified:** الجهاز والتوزيع وCloudKit وiOS 27؛ بيانات المالك ومحاكيه لم تُستخدم.
- **Next:** بقايا AU-22 النحوية وAU-11 النصية ثم أعمدة الدين في AU-04.
- **Model/effort:** not exposed / not exposed؛ Luna للبحث فقط.
- **Usage:** آخر قراءة 10% مستخدم من الخمس ساعات، 32% أسبوعي؛ الجلسة مستمرة.
