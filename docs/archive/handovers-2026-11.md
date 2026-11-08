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

