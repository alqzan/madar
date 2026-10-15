## Handover — M1-F04 shared device budget and external countdown — 2026-10-15 — Codex
Works now: M2-V01–V17/prayer-Quran link approved by owner; M1-F04 software blocker resolved with atomic shared JSON budget, LiveActivityIntent, countdown Control/Shortcut, minute-only native countdown and legacy device-ledger seeding. No owner-store access/schema migration.
Verified: `swift test --package-path Madar/Packages/MadarInbox --filter NotificationBudgetTests` 7/7; independent producer process scenario 42 clients/4 slots/no SwiftData; scoped `xcodebuild … test` activity data 4/4 + save/relaunch/undo UI 1/1 (`M1-F04-validation`); Quran outside 2/2 and ledger 1/1 in prior targeted run; final `xcodebuild … build` app/widget PASS (`M1-F04-final-build.log`); `git diff --check` clean.
Differences left: S10 is OS-composited; no fake OS comparison. Native timer uses Arabic hours/minutes wording (RL7), no seconds or private counts. Existing room-styled settings captured at L/light in `Artifacts/m1-f04-shots/`.
Not verified: actual Control/Siri/widget gallery invocation, ActivityKit start/delivery, owner-iPhone, release resource human sample, distribution or milestone gates; Simulator UI is unavailable to computer-use tools. No frozen work or enlarged-text runs.
Next: M3 Diary is next; open its ordered cards from approved §7.3/§12 with RD fixes before coding. M1/M2 device gates remain deferred until whole app completion; no ready M2 screen remains.
Model/effort: Codex GPT-6; exact variant/effort not exposed.
Usage: 16% five-hour and 18% weekly at closing checkpoint; no reset used.
