## Handover — M4-F02 shared reminders and budget — 2026-10-16 — Claude
Works now: qada reminder after the chosen prayer's sanctity while something is owed, push-habit reminders at their window start, Quran reminders, all under one per-device budget with a digest that names kinds only; the stale nudge follows its setting; whole-app lock keeps text generic; a tap opens the reminder's room; completing a habit cancels its reminder.
Verified: swift test MadarCore 88/88; xcodebuild RoomNotificationsIntegrationTests 4/4, QuranOutsideIntegrationTests 2/2, AppServiceIntegrationTests 7/7, CaptureIntentIntegrationTests 3/3; make build succeeded; git diff --check clean.
Differences left: none visual (no canonical screen). Diary kinds wait for M3-V12; iPad default for this-device reminders not applied; habit reminders schedule today and tomorrow's window only.
Not verified: real delivery, the device week (M4-G), owner iPhone.
Next: M3-V12 generic diary reminders, then the improvement share.
Model/effort: Claude Opus 5.5; effort not exposed. Usage: five-hour 29% at handover.
