# Archived handovers

## Handover — M5 X00 flexible schedules, V14 analysis, M3-V09 Day One, card art, Quran Hijri-first — 2026-10-17 — Claude
Works now: obligations repeat every N days/weeks/months/years from a free first date (schema V7), subscriptions shelf, optional reason on the budget stamp; «التحليل» screen; Day One JSON-ZIP import with preview and undo; gold/navy card art; the Quran room is Hijri first; log over-limit red arch in a shot.
Verified: packages on merged main — MadarCore 108, MadarData 67, MadarCommands 104, MadarMoney 106 passed; make build succeeded; X00/V14/V09 UI tests passed in their worktrees (agent reports). Migration and Day One reviewed read-only: no Critical/High.
Differences left: V11 digits/«ينتظر يرجع لك» unreviewed; V12 dates under the cash axis are one row; no owner-iPhone, dark mode or compare-screens run for the card art.
Not verified: UI tests on merged main; a real Day One export; owner iPhone. In flight (worktree branches, not merged): V15 reconciliation, V16 cashback jar.
Next: merge V15/V16, then V17 record an expense → V24, X01; Opus UX review of M5; apply owner's Day One review mediums (undo→re-import duplicate, wrong failure message).
Model/effort: Claude Sonnet 5.5 + Opus 5.5 agents / not exposed. Usage: not exposed.

## Handover — M5 V11–V13 visual review and fixes — 2026-10-16 — Claude
Works now: log arches turn red with an amount spike when the day passes its limit, plus a «خط <limit>» label; cards «متى يخرج النقد» is a real axis (today line, red statement dot, «يقفل» tick, green line to the purchase-due date).
Verified: UI MoneyLogUITests 1/1 (M5-V13-fix2.xcresult) and MoneyCardsUITests testFourTabsSourcesAndDebit 1/1 (M5-V12-fix.xcresult); commit 84ec026. Native build succeeded.
Differences left: red arch not seen in a shot (fixture has no over-limit day); dates under the axis are one detached row; card art plain vs gold/navy etched design; V11 digits/«ينتظر يرجع لك» not reviewed; amount font and separator unchanged.
Not verified: compare-screens.py not run; owner iPhone; dark mode.
Next: red-day fixture + shot, dates under markers, card art, V11 gaps.
Model/effort: Claude Sonnet 5.5 / not exposed. Usage: not exposed.

## Handover — M5-V11 stamp, V12 cards, V13 log and diary search — 2026-10-16 — Codex
Works now: budget stamp / lift / exact split and refund restoration; four card tabs with source sheets, uncertain-date estimates, shared-budget due/cash reminders; log arcade/month, saved-day totals, source/search/filter/month controls; earlier-room improvement: diary empty-search retry.
Verified: swift test MadarMoney 102/102; MadarCommands 90/90 before final V11 fixtures, final stamp/refund 5/5; core RoomReminders 8/8. xcodebuild native data/card-notification slices 3/3; card UI, hidden/empty, diary retry and log basic flow passed (Artifacts/M5-V12-verified, M5-V12-notifications, M5-V12-and-diary, M5-V13-delivery .xcresult). Extended log filter/month/search/source controls 1/1 passed (M5-V13-controls-verified); diff --check clean.
Differences left: generic budget seal (reason/person fields absent; no receivables RM10); paired-date card timing lanes; first-calendar log month and dual dates add height, real partial data, no red. Compare Z-R19-ign/-ign-b, Z-R19-cards-1/2/3/4, Z-R18-log-4/-4x; L/light shots in m5-v11-final-shots, m5-v12-shots, m5-v13-shots, diary-search-recovery.
Not verified: owner iPhone, actual delivered card reminders, real bank texts, dark mode, milestone gate. No owner store/schema migration. The one V11 data-deletion review found a High repeated-target refund issue, fixed and tested; no other review passes.
Next: M5-V14 analysis. Stopped at the requested weekly 1% reserve; no V14 work started.
Model/effort: not exposed / not exposed. Usage: final checked weekly 99% used (1% left), five-hour 66% used (34% left).
