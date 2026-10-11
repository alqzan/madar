# Diary journeys — M3

References: 10-r-notes, 14-shared, 19-qa; RD1–RD7 and latest owner RD2 retention. Apply [common states](README.md).

| ID / planned test | Steps and expected outcomes | State cases | Device requirement |
|---|---|---|---|
| J05 / test_J05_captureFreezeMargin | One-tap write; keyboard default; cancel/save; optional available dictation with notice and short chunks. Freeze 24h after day end, retain original revision when edited. Add margin in its own day; delete original and undo: margin remains, dead-origin arrow absent. | Empty/long text, transcript editing, saved/cancelled failure; old frozen day, missing original, lock. | Store/simulator and actual iPhone dictation availability/permissions. |
| J06 / test_J06_importMediaProjectsLetters | Preview Day One, import twice, resolve same/independent retained copy IDs; preserve tags, zones and available media. Cancel mid-import; retry missing media. Add 20 images with limited/denied permission, remove/undo. Use four project entry routes, remove progress link. Write/seal letter, choose time/event, cancel; open only when eligible, deleted trigger remains handled. Return position. | Large diary/media, source duplicate, corrupted file, denied permission, missing media after restore, deleted event. | Isolated store/simulator; actual iPhone photos/audio/permissions. |
| J07 / test_J07_diaryPrivacy | Open day/letter sheet; activate lock, background, refuse auth; test search/deep link/VoiceOver/widget/pending notification. Sealed content never exposed; reject/cancel retains lock; unlock restores route. Private widget explicit opt-in. | All states; origin-deleted margin, stale snapshots; date/event letter not eligible. | Simulator plus real iPhone privacy surfaces; cross-reference J17. |

J16/J17/J18 required. No automatic user-data import or speech-server use is implied by these planned tests.
