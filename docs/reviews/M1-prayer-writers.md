# M1 prayer writers — scoped independent review

## T06 — prayer.setHeart — 2026-10-13

Reviewed working production diff over `7769d6d`: `Commands.swift`, `DurableCommandAdapter.swift`, AppSession bridge and opt-in heart UI. Reused unchanged auth/store lifecycle approval. Independent reviewer requested GPT-6 Luna/max; actual reviewer identity/effort not exposed. Static result: no actionable findings; reviewer did not run tests or use simulator.

Strict canonical payload, app-only transport, existing recorded prayer requirement, same-key tombstone protection, nil clear and durable inverse/replay are consistent with RA2/RP6. Only heart changes; prayer status and qada remain untouched. Bundled askHeart stays false; no ranking, numerical heart score or persistent arch label.

Author check: `swift test --package-path Madar/Packages/MadarCommands --filter test_M1T06`: 1/1. Native `test_M1T06_OptionalHeartSaveSkipUndoAndRelaunch`: 1/0 in 129.873s, L + actual AX3 screenshots inspected; `/tmp/madar-t06-heart-target-20261013.xcresult`. Full-row tap target was repaired; test now asserts selection before saving and sheet closure before undo. No writer changes after review.

Not verified: owner iPhone, external-release wording review or distribution.

## T07 — manual qiyam and explicit restoration — 2026-10-13

Fresh independent reviewer requested GPT-6 Luna/max; actual identity/effort not exposed. Scope: production diff over `e18601c`, including new Core/adapter operation, existing qiyam stage, repository projection and app bridge/UI. Initial finding: existing 0...1000 stage/parser bound contradicted the approved QiyamNight.rakaat 0...99 contract. Author repaired parser/stage/UI/registry and added rejecting-100/accepting-99 regression. Final static review: no actionable findings remain.

P05 uses Isha–Fajr and seven eligible nights; fractional/future/out-of-window values are rejected. Replay/undo remain durable. Normal saves reject tombstones; confirmed restoration retains the barrier and advances restoredAt. quranSessionID remains untouched; no Quran sessions/pages are written. Reused unchanged app-only store/notification lifecycle approvals.

Author evidence: `swift test --package-path Madar/Packages/MadarPrayer --filter qiyamRakaatContract`: 1/1; Commands `--filter test_M1T07`: 1/1 after bound repair. Native `test_M1T07_QiyamSaveRelaunchUndoRestoreAndAX3`: 1/0 in 76.606s, `/tmp/madar-t07-qiyam-range-20261013.xcresult`; earlier same flow 1/0 in 77.370s. L/AX3 screenshots inspected. Reviewer did not run tests or use simulator.

Not verified: owner iPhone, cross-room Quran integration or distribution.
