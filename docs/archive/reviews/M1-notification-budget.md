# M1-T04 RL5 budget review — 2026-10-13

Scope: current production diff over candidate `433cbf6`, after merging main `3c877df`; `PrayerNotifications.swift`, `PrayerActivityAttributes.swift`, `MadarCore/Notifications.swift` and affected tests. Reused unchanged prior lifecycle approval.

Independent reviewer: fresh subagent requested GPT-6 Luna/max. Result: no actionable findings. Static review only; no simulator control or tests by reviewer.

RP3 uses the same clamped instant for ActivityKit and ledger. RL5 checks quiet hours, device opt-out and remaining Madar-day budget. Local ledger reservation precedes the OS request, failed requests cancel it, duplicate natural IDs count once, and refresh serialization protects allocation. Submitted starts remain budgeted after their time; no delivery inference.

Author verification: Core `swift test --package-path Madar/Packages/MadarCore --filter liveActivity`: 2/2. Signed iPhone 17 Pro/iOS 26.5 selected native notification flow plus persisted ledger test: 2/2, `/tmp/madar-t04-budget-20261013.xcresult`. Isolated persisted ledger test after removing OS attachment: 1/1, `/tmp/madar-t04-budget-isolated-20261013.xcresult`. Preflight 11/11, 0 copied. `git diff --check` passed.

Not verified: actual physical ActivityKit scheduled start, owner-iPhone acceptance or distribution. Existing conservative 12-hour display lifetime gate remains; no activity is permitted to extend into Isha.
