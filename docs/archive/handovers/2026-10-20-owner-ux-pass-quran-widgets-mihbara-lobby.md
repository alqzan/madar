## Handover — owner UX pass: Quran flexibility, widgets, Mihbara, lobby habits — 2026-10-20 — Claude
Works now: any open Quran step starts from its sheet; review adapts per page (mastered page: «سمّعته كاملًا» one tap; far page: ayah by ayah); widget/reminder copy in Arabic agreement; reminder preview matches the notification; day-path widget line; Mihbara audit (counts, shelf moves by long press, «أنت هنا», cleaner EPUB preview); lobby habits block shows one period at a time; hero money figures draw «٬/٫».
Verified: QuranReviewUITests 4/4, QuranHomeUITests step test 1/1, QuranOutsideUITests 2/2, RoomWidgetSnapshotTests 7/7, RoomNotificationsIntegrationTests 10/10, Mihbara reader 3/3 + library/shelf 2/2 + motivation 1/1, BahwLobbyUITests 9/9, MoneyHomeUITests 4/4, HabitsUITests 2/2 (simulator 412F4437, iOS 26.5); `git diff --check` clean.
Differences left: Thmanyah fonts lack «٬/٫», so non-hero amounts still fall back (owner decision listed); prayer widget countdown keeps RL7's «١:٢٠» form; upcoming medium widget shows no date.
Not verified: owner iPhone, real OS widgets/notifications, the far-page caption (no far page in fixtures), dark mode for the new controls.
Next: owner decision on the font glyphs; Quran quick day actions on «مسار اليوم» if the owner still finds the day rigid; Step 10 device run when the iPhone is connected.
Model/effort: claude-opus-5-5 lead with two claude-sonnet helpers (widgets, Mihbara) / not exposed.
Usage: 29% five-hour used / 12% weekly used at the last live check.
