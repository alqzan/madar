# Archived handovers (moved 6 Nov 2026)

## Handover — تجهيز TestFlight وتنظيف تحذيرات Release — 2026-11-02 — Codex
- **Works now:** سؤال عربي للمذكرات والمال، تصنيف المصروف واقتراحات التاجر؛ نظّفت واجهات API المهجورة وحافظت على تنسيق سطر المذكرة. ألوان القلم والمظلّل صارت قيم تصميم مولدة كما كانت، وحدّثت تعريف الاتجاهات لـiPhone وiPad. الأرشيف المحلي `Madar/Artifacts/TestFlightPrep/Madar-0.1.0-1-cleanup-r6.xcarchive`.
- **Verified:** `xcodegen generate --spec project.yml` و`xcodebuild archive ... CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` → `ARCHIVE SUCCEEDED` بلا أخطاء أو تحذيرات؛ زال تحذير الاتجاهات. 0.1.0 (1)، التطبيق والودجة بمعرّفاتهما الصحيحة، الحد الأدنى iOS 27.0، وCloudKit فارغ. `plutil -lint`, تزامن ملفات tokens الثلاثة، و`git diff --check` نجحت.
- **Differences left:** الأرشيف غير موقّع؛ لا provisioning profiles محلية. `supportURL` و`privacyPolicyURL` ما زالا فارغين لعدم وجود نطاق أو جهة دعم مؤكدة. لم أعد تشغيل `check-shipping-sources.py` خارج بوابة المرحلة، والتتبع اليدوي للمصادر لم يكتمل.
- **Not verified:** لا رفع إلى TestFlight أو تجربة iPhone؛ لا تجربة Foundation Models/Translation على جهاز؛ لم تُشغّل حزم اختبارات في هذه الجولة.
- **Next:** بعد اعتماد Apple وتفعيل فريق App Store Connect، أنشئ ملفات التوقيع للتطبيق والودجة مع `group.com.alqzan.madar2` ثم أرشف وارفع النسخة. يلزم قبل الإرسال للنشر نطاق الخصوصية والدعم، جهة المراجعة وملصق الخصوصية؛ وتبقى أدلة الجهاز وRelease ضمن بوابة M7.
- **Model/effort:** Codex GPT-6؛ الجهد غير مكشوف.
- **Usage:** غير مكشوف في متابعة تجهيز TestFlight هذه.

