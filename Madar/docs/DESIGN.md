# مدار — التصميم في M0

واجهة أصلية عربية RTL تبدأ من مكونات الأساس؛ لا تظهر الغرف التي لم تُنفذ، ولا أرقام النماذج المصوّرة. تظهر تهيئة البداية بجملتها ومدينتها فقط لأن الإشعارات والقفل ونقل بيانات الغرف تأتي مع مرحلتها.

## مصدر الهوية

`Specification/design-tokens.json` v3 هو مصدر الألوان. `MadarDesign/GeneratedTokens.swift` يولّد جميع قيم rooms/widgetIdentity بالأرقام الفعلية دون تعديل يدوي. ملف JSON نفسه مضمّن كمورد. RoomTheme يطبق calmPaper على أدوار الهوية فقط ويحافظ على الدلالات الخاصة بكل غرفة. النص الصغير في البهو يستخدم accentText، والأزرار الممتلئة accentFill/onAccent.

تمت مشاهدة المرجع الأصلي كامل الدقة لشاشات flex/01-Main و03-Tab-A و04-Tab-B و05-Tab-C: الورق الدافئ، البطاقات البيضاء الدافئة بزوايا 24، رؤوس Serif، الاختيارات المقسمة، والمظهر الهادئ. وجود غرف المستقبل في نموذج المصدر لا يجيز إظهارها في M0. يستخدم التنقل تبويبات iOS القابلة للتكيّف والتخصيص مع اختصارات زجاجية مباشرة للغرف الأخرى؛ يظل كل مقصد مبنيًا على لمسة واحدة، ويصغر الشريط مع التمرير.

## الإعدادات

مكونات CustomizeMadar/CustomizeRoom/CustomizationTemplate تعيد استخدام مخطط البيانات فعليًا: العناوين والاختيارات والنطاقات والقيم الافتراضية من SettingsSchema. البحث يطبع العربية، وتصحيح الهجري يظهر فقط مع اختيار الرؤية. مفاتيح الغرف والسياسات غير الموصولة مخفية. جميع الكتابات تمر عبر AppSession ثم CommandBus؛ تستعاد الواجهة من المخزن بعد نجاح الحفظ، والتراجع فوري. نمط محفوظ يراجع الفرق قبل التطبيق. مهلة التراجع عن النمط 60 ثانية وفق docs/archive/START-M0.md.

لا تخزن الواجهة قيم الإعدادات في UserDefaults. صفحة المدينة تدعم الرياض ومكة والمدينة ومدخلًا يدويًا مُتحققًا للاسم والبلد والإحداثيات والمنطقة الزمنية والعملة. البحث والملاحة غير الموصولة بغرفة لم تُنفذ لا تظهر.

## الوصول

الحجم النسبي لكل خط يتبع Dynamic Type. جميع الاختيارات تتحول من الصف إلى قائمة عمودية عند أحجام الوصول. لا يخفض إعداد حجم الخط حجم الوصول الذي اختاره المستخدم في النظام. التصميم يستخدم اتجاهات leading/trailing، أزرارًا حقيقية، وخطوطًا تبدأ من 11 نقطة. النسخ المرسومة داخل مكونات التحرير تعطي إشارة إطار متقطع، ويحافظ الهيكل على واجهة أوامر hide/reorder التي تربطها الغرف لاحقًا.

## خطوط الواجهة

وجدت ملفات OTF الفعلية مثبتة في Library/Fonts وضمن حزمة التنزيل المحلية. تحققت أسماء PostScript بواسطة CoreText؛ ثمانية ملفات مطابقة البايتات من Sans وSerif Display وSerif Text في App/Resources/Fonts، تُضمّن في .app المحلي عبر UIAppFonts. لم تُغير أو تُقسم أو يُعدل أي ملف.

الأدلة: `font-provenance.json` يسجل مصدر كل ملف وSHA-256، ونسخة رسمية مؤرخة محفوظة من https://font.thmanyah.com/licenses في `thmanyah-license-2026-10-10.html` مع بصمتها. مصدر الترخيص الرسمي الحالي يسمح بالتضمين في تطبيق معبأ ويمنع الإتاحة المستقلة أو الاستضافة العامة. الملفات مستثناة من Git ولا تُنشر.

**بوابة التوزيع ما زالت غير مكتملة:** حزمة التنزيل الموجودة لا تحتوي نص الترخيص المشحون الأصلي، وكان أميري غائبًا محليًا في الجولة الأولى. أُغلق هذا الجزء لاحقًا بتنزيل الإصدار الرسمي Amiri 1.003 من aliftype/amiri، مع Regular/Bold وOFL المشحون مطابق البصمة في حزمة التطبيق. النسخة الرسمية المؤرخة لا تعادل إثبات الملف المشحون. لا تدّعي هذه الوثيقة اكتمال بوابة الخطوط أو الإذن بالتوزيع.

## حدود التحقق

نجح `swift build` لحزمة MadarDesign على macOS. فحوص التطبيق والمحاكيات والصور والوصول الوظيفي تسجل مركزيًا في docs/archive/madar-docs/M0-STATUS.md بعد الدمج؛ لا يُعد هذا الوصف دليل نجاحها.

فحص مستقل: طابقت 359 قيمة لون مولدة مع أصل JSON (بفارق التقريب الرقمي أقل من 1e-11)، وطابقت بصمات ملفات الخطوط الثمانية. وفي التحقق النهائي نجحت اختبارات البداية والتخصيص، وصُورت الواجهة والمكونات عند L وAX3 وAX5 في المظهرين. بعد مراجعة الصور تحول النموذج الحي وخطوط المعاينة وصفوف التحرير والتراجع إلى ترتيب عمودي عند أحجام الوصول. نجح اختبار حفظ المظهر بعد إغلاق التطبيق ثم إعادة الافتراضي والتراجع. الصور الفعلية وأدلة الاختبار في `Artifacts/preview.html` و`docs/archive/madar-docs/M0-STATUS.md` (من جذر المستودع)؛ هذا لا يثبت VoiceOver أو الأداء على جهاز فعلي.

### M1 prayer interface handoff (2026-10-10)

`App/PrayerRoom.swift` and `App/PrayerSettingsView.swift` define main-actor service contracts. Every displayed time, prayer-day key, eligibility, count, streak, debt and night comes from the domain projection. No screenshot example statistics, fabricated availability or successful write simulation is present. The app adapter must route mutations through durable CommandBus receipts. A qada log with an optional heart answer is one transaction. A successful command followed by a failed reload is reported as a saved change with a read error; the projection is cleared to prevent repeating an already committed action.

The home uses the approved salah palette, five horseshoe arches, diamond lattice, eight-point status stars, optional reflections, a taller Friday arch, current place dates, next prayer and three functional balance styles. At accessibility sizes the arches and beads become labelled rows. Heart summaries remain qualitative. Deferred Quran, sunna and adhkar links are absent. A service-provided capability set controls settings and actual notification authorization. Tracking date bounds and date-picker time zones come from the active place.

Direct Swift 6 typecheck against the iOS 26 simulator SDK passed after the final modal routing, balance style, time-zone and commit/read failure changes. Runtime behavior remains an integration responsibility until root wires the services; no runtime pass is claimed by this interface handoff.

Root smoke sequence for connected services:

1. Fresh isolated store: verify five actual local times and next prayer; no summary before five eligible prayers, no earlier debt, and no placeholder data. At Friday dhuhr verify the title/tall option; at Tromso polar summer verify the nil caption, manual logging eligibility, no invented pending or notifications.
2. Open `prayer-arch-<code>`, choose `prayer-log-status-jamaah`, answer `prayer-heart-present`, save with `prayer-log-save`. Relaunch and inspect one natural-key PrayerLog. Mark missed, verify the sheet stays open and a single owed QadaItem appears. Use `prayer-makeup-now`, then global undo: both PrayerLog and QadaItem return together. Correct missed to alone and confirm debt tombstone.
3. `prayer-history` -> a past row -> correction. `prayer-pending` -> select explicit rows -> `prayer-unrecorded` -> confirm; these alone become unrecordedHistory, excluded from debt/ratio/streak. Undo restores them. Do not infer the choice from absence.
4. `prayer-qiyam` -> change eligible night, step rakaat, toggle witr, save. Inspect one QiyamNight without fabricated Quran pages. The service must map 23:30 and 02:10 to one night and refuse future nights. Relaunch and compare the 30-night footprint.
5. Active travel: `prayer-pair-dhuhrAsr` -> save taqdim and undo: exactly two linked logs then none. Edit one partner: both pairIDs clear and the other status survives. End trip and verify the next unlogged prayer uses home-city times. Friday offers recorded Jumua or shortened dhuhr without advice.
6. Settings: change each method/asr/high-latitude/offset and verify actual recalculated times. Change pool/Friday height/balance and verify visible effect. Hide/reorder optional blocks; pinned next/riwaq stay visible. Tracking edit succeeds once within supplied bounds, second edit rejected. Reset preserves logs/tracking. Permission denial leaves honest notification state; request success reflects actual OS status. Unsupported Live Activity controls are absent.
7. Capture connected light/dark screenshots at Large, AX3 and AX5: main, log, qada, history, qiyam, and settings. Verify no truncation, touch targets at least 44pt, and VoiceOver status labels use the actual backend state.

M0 service smoke additions: encrypted manual export must create a real `.madarbackup` before ShareLink appears; wrong passwords/corruption never reach restore confirmation; preview counts/date range/skipped warnings match backend; cancellation during staging preserves active store, while a committed restore still reports success. Merge vs replace must match preview and retain a safety backup. Local unsigned sync shows local-build state, not CloudKit availability. Account-choice sheet appears only for an observed identity change after an actual safety backup. App lock must remove protected model rows/snippets/snapshots and invalidate search/notification disclosure before unlock; returning after sixty seconds requires real device-owner authentication. Background during authentication and redaction errors stay fail-closed.
