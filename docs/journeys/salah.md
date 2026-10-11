# Prayer journeys — M1

References: 09-r-salah, 14-shared, 19-qa; RP1–RP6. Apply [common states](README.md).

| ID / planned test | Steps and expected outcomes | State cases | Device requirement |
|---|---|---|---|
| J02 / test_J02_logCorrectUndo | Open current prayer; save on-time/missed/excused or cancel; edit old day; undo/explicit restore. Send the same command from available UI/intent/notification/widget surfaces; one record and replay result, including interrupted drain/relaunch. Missed only after actual window end; unconfirmed gap pauses streak and never automatically creates debt. Review gaps in bulk; log qada explicitly. Test Friday/travel kinds and user precedence. | Empty/long history, invalid prayer/window, duplicate/different payload, old tombstone, expired auth; whole-app lock blind prayer generic result. | Engine/store/simulator plus real iPhone notification/widget actions. No unavailable surface counts as complete. |

J01/J10/J12/J16/J18 are also required at the relevant M1 gate. Heart and Live Activities default off; activation receives separate budget/sanctity/device evidence. PendingDays is a review horizon, never a missed/debt conversion timer.
