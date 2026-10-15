## Handover — Codex M2 recheck, M2-V04 drill and open items — 2026-10-14 — Claude
Works now: drill screen (tabs, 3/5/8 allowance, hidden word/ayah, reveal, answer, next spot); word slips by long press in blind recitation and covered review; plan «وزّعه/ضاعف/تجاوزه» applied once without asking; «القريب» = most recently memorised faces; plan start follows core.dayStart; forecast uses the habitual level; «تثبيت» the day after «يحتاج»; random day-stable old-test page; undone day choices/allotments can be chosen again.
Verified: `swift test` MadarQuran 75 (RQ1 simulation 3/3, old rule fails), MadarCommands 35, MadarData 63, Core 30, Prayer 25, Snapshots 9, Inbox 10; `xcodebuild … test` Quran integration 11 + home/coach/review/drill UI 5 = 16/16; app builds; `git diff --check` clean; Quran contrast 90/90.
Differences left: V04 — allowance-driven segment count, «،» beside digits (RU1), no moon button, per-word gold blur for a whole ayah. Shots `Madar/Artifacts/m2-v04-drill/`, comparison `Madar/Artifacts/compare/R18-Drill.html`.
Not verified: owner visual approval (V01–V04); owner iPhone not required now (owner, 14 Oct). Deferred by the owner: متشابه choice; M1-F02 travel test (passes on 4E0D782E, fails on 412F4437, not pursued).
Next: M2-V05 day close is ready.
Model/effort: Claude Opus 5.5 (one Sonnet audit agent); effort not exposed.
Usage: not exposed.
