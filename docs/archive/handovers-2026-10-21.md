# Handover archived on 2026-10-21

Works now: first incoming salary choice is confirmed through the existing cycle report; the confirmed counterparty then marks later incoming drafts «راتب مقترح», with normal-income choice and undo preserved.
Verified: MadarMoney `SalarySourceMatcherTests` 1/1; MadarCommands `confirmingIncomingTransferLearnsSourceAndUndoRemovesIt` 1/1; iPhone 17 Pro / iOS 26.5 UI 1/1 (`M5-V27-ui-r5.xcresult`); `compare-screens.py Z-R18-msg-1`; `git diff --check` clean.
Differences left: live fixture values and floating room navigation below the first viewport; the canonical has no scrolled companion.
Not verified: owner visual approval, owner iPhone, real bank corpus through this flow.
Next: port the remaining My-dream parser cases, then run the private corpus guide and simulator screen trial in queue order.
Model/effort: not exposed / not exposed.
Usage: 10% five-hour used / 2% weekly used at the last live check; reserve remains.

## Handover — Thmanyah «٬/٫», prayer/diary/habits/money polish — 2026-10-21 — Claude
Works now: money amounts (about 90 places), the money widget and lobby rows draw «٬/٫» from Thmanyah's own «،/,» (its licence forbids editing the files); the Quran plan date shows both calendars; prayer day line without «٠ من ٥ ·»; number settings show their unit («٣٠ دقيقة»); echo cards without a repeated date; full-width habit editor; habit page in its own period; obligation lanterns that no longer overlap; «بقي ٨ أكواب».
Verified: MoneyHome 4/4, Salary 1/1, Since 1/1, Analysis 2/2, EnvelopeDetail 1/1, Log 1/1, Obligations 4/4, Envelopes 2/2, QuranJourney 1/1, RoomWidgetSnapshotTests 7/7, PrayerFirstDay 1/1, PrayerCountdown 1/1, DiaryEchoes 1/1, Habits 2/2, BahwLobby 9/9 (simulator 412F4437); `git diff --check` clean.
Differences left: «٬/٫» outside the money room (e.g. Quran in Amiri, which has them) unchanged; tiny chart axis dates show one calendar; the diary microphone-denial message is still blocked (item 15).
Not verified: owner iPhone, VoiceOver reading of the composed figures on a device, dark mode.
Next: diary microphone denial on a real device; continue the UX pass in Mihbara and the money sheets.
Model/effort: claude-opus-5-5 / not exposed.
Usage: 59% five-hour used / 16% weekly used at the last live check.
