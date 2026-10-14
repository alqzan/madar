## Handover — M2 app adapter and Quran home — 2026-10-14 — Codex
Works now: D01 is done; V01 Quran tab/home has real coverage, levels, balance/step details, one start action, 14-day log and durable resume/partial commit. Daily minimum/recovery share stop after completion; the producer uses selected prayer offsets.
Verified: `swift test --package-path Madar/Packages/MadarQuran --filter 'DailyPlanningTests|SessionPlanningTests|QuranDailyCompletionTests'` 21/21; targeted MadarCommands Quran/one prayer checks 9/9; `xcodebuild ... -only-testing:MadarTests/QuranServiceIntegrationTests -only-testing:MadarUITests/QuranHomeUITests ... test` 3+1 passed at L/light; native build passed; `git diff --check` clean.
Differences left: RQ9 simplified labels; native status/tab bar; unbuilt tools and full-log/plan entries hidden. `compare-screens.py R18-Home` page generated and screenshots inspected; Codex open request queued; scrolled shot is supplementary because no Quran scrolled canonical exists.
Not verified: V02 coach visual match, later Quran screens, owner iPhone, human resource sample or distribution; screenshot data is an isolated fixture, never owner records.
Next: M2-V02 ready (`quran/04-R18-Hifz.jpg`); preserve the home shape and data contracts; V01 is awaiting owner, not approved.
Model/effort: Codex GPT-6; exact variant/effort not exposed.
Usage: 62% five-hour and 69% weekly at closing checkpoint; no reset used.
