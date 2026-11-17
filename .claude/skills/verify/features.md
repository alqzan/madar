# Madar feature map — what to run for each area

The user's view of each room: where it is, the end-to-end test that drives it, and what a working smoke run shows.
Run the UI class for every area the diff touches. Smoke env pairs are passed to `Madar/scripts/verify-smoke.sh` as `KEY=VALUE`.

| Area (files) | Where the user meets it | End-to-end (MadarUITests) | Integration / package | Smoke env | Works when |
|---|---|---|---|---|---|
| Lobby `BahwLobbyView`, `BahwBlocks`, `AppBahwService`, `TabShell` | Home tab «البهو», room blocks, suggestions | `BahwLobbyUITests`, `FoundationUITests`, `BahwCustomizeUITests` | `BahwAttentionTests` | `MADAR_UI_HABIT_FIXTURE=lobbySix` | Lobby opens, blocks show today's state, a tap opens its room |
| Habits `Habit*.swift`, `HabitEngine`, `HabitRepository`, `HabitMutationHandler` | Tab «العادات» (first room tab) | `HabitsUITests`, `HabitsOwnerTrialUITests` | `HabitRhythmTests`, `LegacyHabitTrialTests`; `swift test` in MadarCore (HabitEngine) and MadarCommands (`Habit*Tests`) | `MADAR_UI_HABIT_FIXTURE=showcase` (also `atRisk`, `since`) | Period cards, today list, a once-habit ring logs and sinks, streak capsule (hourglass on `atRisk`), detail opens |
| Habit and room notifications `RoomNotificationContent`, `PrayerNotifications` (coordinator), `RoomReminders`, `SanctityGuard` | Reminders, final streak alert, amount buttons | `NotificationBudgetUITests` | `RoomNotificationsIntegrationTests`, `QuranOutsideIntegrationTests`; MadarCore `RoomRemindersTests` | — | No request inside a sanctity window; ids and copy as the tests expect |
| Quran `Quran*.swift`, `AppQuranService*`, `QuranProgressEngine` | Tab «القرآن» | `QuranHomeUITests` plus the class named after the screen (`QuranPlanUITests`, `QuranMushafUITests`, `QuranReviewUITests`, …) | `QuranOutsideIntegrationTests`; MadarCore Quran tests | `MADAR_UI_QURAN_FIXTURE=<fixture used by the UI class>` | Today's wird, session, mushaf page open |
| Diary `Diary*.swift`, `AppDiaryService`, `DiaryLineRenderer` | Tab «المذكرات» | `DiaryRootUITests`, `DiaryTodayUITests` plus the screen's class | Diary integration tests; MadarCommands diary tests | `MADAR_UI_DIARY_FIXTURE=<fixture used by the UI class>` | Today page, writing a line, both dates shown |
| Money `Money*.swift`, `AppMoneyService`, money engine | Tab «المال» | `MoneyHomeUITests` plus the screen's class | Money integration tests; MadarCore money tests (focused review required by protocol) | `MADAR_UI_MONEY_FIXTURE=<fixture used by the UI class>` | Home totals, add expense, amounts in minor units |
| Mihbara `Mihbara*.swift`, `AppMihbaraService` | Tab «المحبرة» | `MihbaraHomeUITests`, `MihbaraImportUITests` | Mihbara integration tests | `MADAR_UI_MIHBARA_FIXTURE=<fixture used by the UI class>` | Stand, current book, reader opens |
| Settings / customize `SettingsHome`, `CustomizeMadar`, `RoomSettingsIndex` | Settings, «خصّص» | `CustomizeSearchUITests`, `BahwCustomizeUITests` | Settings tests in MadarData | — | Each setting has default, reset, undo |
| Widgets, controls, watch `Widgets/`, `WatchApp/`, `AppRoomWidgetSnapshots` | Home Screen widgets, watch | `RoomWidgetsUITests`, `WidgetMakerUITests` | `RoomWidgetSnapshotTests` | — | Snapshots JSON only; routes reach built rooms |
| iPad layout (any `Pad*`, size-class code) | iPad sidebar and wide pages | `PadLayoutUITests` on `Madar iPad Pro 13` | — | `SIMULATOR=85FA4D17-2DBF-46D6-837E-9221597B89DD` | Sidebar, no stretched iPhone layout |
| Data, sync, backup `Packages/MadarData`, `MadarSync`, `AppSession` startup | Launch, restore | `FoundationUITests` | `AppInboxLifecycleTests`, MadarData `swift test` | any | App opens without the startup alert; tombstones, no hard deletes |
| Intents and deep links `Intents/`, `MadarIntentHandoff`, routes | Shortcuts, `madar://` links | — | `CaptureIntentIntegrationTests`; `python3 Madar/scripts/deep-link-test.py` | — | Each link opens a built room, never a removed one |
| Project / delivery `project.yml`, signing, versions | TestFlight | — | `xcodegen generate`; Release archive; check `Products/Applications` holds only `Madar.app` | — | Archive exports; build number never reused |

Removed (owner, 17 Nov 2026): the prayer room. Its UI tests (`PrayerFirstDayUITests`, `PrayerCountdownUITests`) are not part of any area; delete them when touched.
