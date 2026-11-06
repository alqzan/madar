# Archived handovers (moved 6 Nov 2026)

## Handover — تجهيز TestFlight وتنظيف تحذيرات Release — 2026-11-02 — Codex
- **Works now:** سؤال عربي للمذكرات والمال، تصنيف المصروف واقتراحات التاجر؛ نظّفت واجهات API المهجورة وحافظت على تنسيق سطر المذكرة. ألوان القلم والمظلّل صارت قيم تصميم مولدة كما كانت، وحدّثت تعريف الاتجاهات لـiPhone وiPad. الأرشيف المحلي `Madar/Artifacts/TestFlightPrep/Madar-0.1.0-1-cleanup-r6.xcarchive`.
- **Verified:** `xcodegen generate --spec project.yml` و`xcodebuild archive ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → `ARCHIVE SUCCEEDED` بلا أخطاء أو تحذيرات؛ زال تحذير الاتجاهات. 0.1.0 (1)، التطبيق والودجة بمعرّفاتهما الصحيحة، الحد الأدنى iOS 27.0، وCloudKit فارغ. `plutil -lint`, تزامن ملفات tokens الثلاثة، و`git diff --check` نجحت.
- **Differences left:** الأرشيف غير موقّع؛ لا provisioning profiles محلية. `supportURL` و`privacyPolicyURL` ما زالا فارغين لعدم وجود نطاق أو جهة دعم مؤكدة. لم أعد تشغيل `check-shipping-sources.py` خارج بوابة المرحلة، والتتبع اليدوي للمصادر لم يكتمل.
- **Not verified:** لا رفع إلى TestFlight أو تجربة iPhone؛ لا تجربة Foundation Models/Translation على جهاز؛ لم تُشغّل حزم اختبارات في هذه الجولة.
- **Next:** بعد اعتماد Apple وتفعيل فريق App Store Connect، أنشئ ملفات التوقيع للتطبيق والودجة مع `group.com.alqzan.madar2` ثم أرشف وارفع النسخة. يلزم قبل الإرسال للنشر نطاق الخصوصية والدعم، جهة المراجعة وملصق الخصوصية؛ وتبقى أدلة الجهاز وRelease ضمن بوابة M7.
- **Model/effort:** Codex GPT-6؛ الجهد غير مكشوف.
- **Usage:** غير مكشوف في متابعة تجهيز TestFlight هذه.

## Handover — متابعة بوابة ما قبل TestFlight — 2026-11-02 — Codex
- **Works now:** قفل التطبيق اختياري ومطفأ افتراضيًا، وإلغاء تحديث خطط المال عند مغادرة الغرفة لا يظهر كخطأ. جولة بيانات المالك r2 وصلت إلى money-log-open وزارت الغرف السبع.
- **Verified:** OwnerAllDataTrial r2 1/1 خلال 903.150 ثانية (TF-02-owner-data-final-27.0-r2-20261102.xcresult); لا مطالبة رمز في الجولة. المحبرة لم تعرض تنبيه الإلغاء. فحص المتجر النظيف 1/1، AU-67 15/15، review contracts 86، وstatic shipping scan 450 ملفًا.
- **Differences left:** لا تغيير بصري جديد. بحث المذكرات استغرق نحو 60 ثانية؛ استيراد ودمج السجل المحلي بطيئان على بيانات المالك.
- **Not verified:** r3 أوقفه المالك عند 448.979 ثانية (TEST INTERRUPTED، ليس نجاحًا). مصدر مطالبة رمز النظام ما زال غير محسوم؛ أرقام كل شاشة لم تُقارن بمرجع مستقل؛ TF-03 إعادة التثبيت وتسليم BGTask الحقيقي، وTF-05 Release على الشيفرة الحالية والتتبع اليدوي، وقبول iPhone غير متحققة.
- **Next:** استكمل TF-02 من r2 عند استئناف العمل، ثم تابع TF-03 وTF-05. لا تنشئ محاكيًا أو runtime إضافيًا.
- **Model/effort:** GPT-6؛ الجهد غير مكشوف.
- **Usage:** غير مكشوف.
