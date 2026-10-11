# Quran journeys — M2

References: 11-r-quran, 19-qa; RQ fixes. Apply [common states](README.md). QCF edition/maps and licensed resources are prerequisites; unlicensed tafsir has no entry.

| ID / planned test | Steps and expected outcomes | State cases | Device requirement |
|---|---|---|---|
| J03 / test_J03_sessionResume | Start one proposed session; record partial ayah, hints and actual mistakes separately; pause/background/kill and resume saved position. Finish → quiet daily closure; undo/delete/explicit restore. Verify weak due/recovery floor and all 604 pages for khatm; no completion from partial/duplicate session. | Empty plan, large mistakes, missing resource/map, save error, lock; rest day and third face. | Independent engine fixtures/store/simulator; iPhone smallest supported layout/resource/offline rendering. |
| J04 / test_J04_planSafety | Open current plan; change forward plan/rest day/28-day pace with safety copy; preview, cancel or save; reopen and compare assignments; restore safety copy explicitly. No reverse/voice/tafsir entry without availability. | New/existing/large history; invalid target, failure/cancel mid-change; prior completed sessions. | Engine/store/simulator; iPhone accessibility. |

J16/J18 also required; current excluded scaffold is not a completed room or journey.
