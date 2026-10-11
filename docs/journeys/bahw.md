# Lobby and habits journeys — M4

References: 08-r-bahw, 15-outside, 19-qa; RL fixes. Apply [common states](README.md).

| ID / planned test | Steps and expected outcomes | State cases | Device requirement |
|---|---|---|---|
| J08 / test_J08_habitEvents | Create each supported recurrence and once/count/time/linked calculation; preview/cancel/save. Append progress events; simultaneous event deliveries add distinct values and replay same ID once. Correct/undo; fixed two-break policy, fewer supported policies. Linked room owns streak/log; never double-log. | 29/30 Hijri, leap day, large counts, missing linked source, lock, cancelled timer. | Engine/store/simulator; built intent/widget on iPhone. |
| J09 / test_J09_lobbyFixedWidgets | Add built-room block, reorder/resize/hide; cancel/save/undo/relaunch with position. Check fixed default widget families, empty/locked snapshots, opt-in private diary and dark tokens. Money/books absent before M5/M6; custom widget identity/shape controls hidden v2. | Hundreds of blocks/long labels, stale/malformed snapshot, error, all rooms locked. | Simulator + actual iPhone WidgetKit reload/actions. |

J10/J16/J17/J18 required. No iPad/Mac acceptance until those platforms enter scope.
