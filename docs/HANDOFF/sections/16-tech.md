10 · Technical architecture (SwiftUI)

Principles

Engines are pure. PrayerTimesEngine, QuranEngine, MoneyEngine, HabitEngine, StreakEngine, MadarDay, NotificationArbiter take value types in and return value types out. No SwiftUI, no SwiftData imports. 100% unit-tested with the worked examples in this document. PrayerTimesEngine returns PrayerTimes? — nil when the sun does not rise/set — and every consumer (NotificationArbiter, the widget snapshot, habit windows) handles nil.

Owner writes, others read. Each room package owns its models and exposes a read-only …Snapshot used by Lobby, widgets, diary lines and search. Writes from every surface go through one CommandBus (below). Snapshot contracts, the Command envelope and every model's types are in data-dictionary.json.

Theme by environment. @Environment(\.roomTheme) provides tokens; every shared component reads tokens, never literals. Tokens are generated from design-tokens.json by a build script (do not hand-type colors).

Settings are data. SettingsStore is the single facade (§6) over two stores: keys with scope = sync live in Setting (synced, one row per key, a row exists only once the value differs from the default); keys with scope = device live in DeviceSetting in the deviceOnly configuration and never leave the device. UserDefaults is not used for settings. Each schema key has scope, default, owner, preset, and (for composite types) contract; generated from settings-schema.json v3.

Layout is data. Each room home is one LayoutState { room, blocksJSON } row whose Codable payload is LayoutPayload {v, blocks, pinned, hidden, sizes} — the only layout store (never duplicated in Setting). pinned blocks can move but not be hidden. For notes, blocks/sizes apply to the window home shape only, while hidden applies to every shape (it is the only owner of «ذاك اليوم» thatDay and «أيامك» days). Edit mode mutates only this model.

One container, two configurations. One ModelContainer factory in MadarData builds two configurations in the App Group container: synced (Madar.store, CloudKit private DB, the 55 synced models) and deviceOnly (Device.store, cloudKitDatabase: .none: DeviceSetting, NotificationLedger, CommandReceipt, PageSchedule, SessionDraft, ProcessingJob). A model type belongs to exactly one configuration. Factory preflight (fails closed with a readable screen): App Group URL resolves; CloudKit entitlement present; the store's schema version ≤ the app's (a newer store from a later build is never opened — «حدّث مدار»); core.iCloudSync is read from Device.store alone before the full container is built. Widget views and timelines never open the store — they read JSON snapshots. App Intent perform(), in whichever process the system runs it, opens the store only through the factory and writes only through the CommandBus. If an intent cannot open the store (device locked / data protection), it appends the Command envelope to AppGroup/PendingInbox.jsonl and returns; the app drains it through the CommandBus on the next foreground (same commandID → idempotent). Before the first unlock after a reboot even this may fail — recovery is bulk paste; the locked behaviour is verified on device in M5, not assumed. M0 includes a concurrent-write test (app + intent writing the same natural key: one row, no crash).

Streaks are derived. StreakEngine is a pure function of logs + policy; streak values are never persisted or synced (a device-local cache is allowed).

Day keys follow §11 “Day keys and event provenance”: computed once at write, stored with their time zone and policy, never recomputed implicitly.

Commands — one write path for every surface

App screens, App Intents (Siri, Shortcuts, Spotlight), interactive widget buttons, Controls, notification actions and system jobs all build the same value and call CommandBus.execute(_:). UNNotificationAction does not become an App Intent automatically: the UNUserNotificationCenterDelegate didReceive handler builds a Command(source: .notification), awaits execute, then calls the completion handler.

Command { commandID: UUID // idempotency key
name: String // "prayer.log", "habit.complete", "diary.appendLine", "money.logExpense", …
payload: JSON // strict Codable per command; unknown keys rejected
source: app|widget|control|siri|shortcut|notification|spotlight|system
issuedAt: Date; schemaVersion: Int = 1 }
CommandResult { status: applied|duplicate|rejected|needsUnlock|needsApp; reason: String?
undoToken: UUID?; affected: [(room, dayKey)] }

Validate the payload against §11 “Units and validation”; every FK must resolve (through mergedInto) to a live row, else rejected.

Authorize. blindWrite commands (log a prayer, complete a habit, toggle travel) reveal nothing and may run in the background with a generic result («سُجّلت»). read commands (show a room's content, start a Quran session) on a room covered by core.faceIDLock return needsApp and open the app behind the lock gate. Diary and money writes additionally require an unlocked device (IntentAuthenticationPolicy.requiresAuthentication; UNNotificationActionOptions.authenticationRequired). Siri/Spotlight dialogs never speak locked content.

Dedupe. Same commandID → return the stored CommandReceipt, no write. Upserts are idempotent on the natural key (equal values → no write, updatedAt untouched). Appends: same name + payload hash from any source within 10 s → duplicate. Notification actions use commandID = UUIDv5(seedNS, requestID + "." + actionIdentifier), so a repeated delivery is the same command; other surfaces mint a fresh UUID per perform().

Apply in one ModelContext.save(); write a CommandReceipt (device-only, 7 days) with the inverse operation.

Post-commit (same order everywhere): cancel the pending request salah.<dayKey>.<prayer> when relevant → regenerate the affected snapshots → WidgetCenter reload of the affected kinds → Spotlight update (if enabled and not locked) → DayEventBus invalidation.

Undo: system.undo {undoToken} through the same bus within 10 minutes (toasts show it for 4–6 s); after that, edit in the room.

URLs never issue commands: a madar:// URL either navigates (read) or prefills a sheet; the user confirms and the app issues the command with source: app. The v1 registry (names, App Intent names such as MakeUpPrayer, AgePendingPrayers, LogPrayerPair, CompleteQiyamWird, CommitQuranSession, ResolveMissedDay, RaisePages, payloads, auth class, upsert/append and idempotency key) is in data-dictionary.json › command.registryV1; rooms add commands only there. M0 acceptance: the same prayer.log sent from a notification action and a widget leaves one PrayerLog; replaying a notification action is duplicate; a locked diary returns needsApp from Siri, Control, widget and Spotlight; a money URL only prefills.

Snapshots and the day bus

Snapshots are a pure function of the store, never of an event stream. Files: AppGroup/Snapshots/<name>.json with envelope {name, schemaVersion, generatedAt, validUntil, dayKey, tzID, privacy, payload}, written with Data.write(to:options: .atomic) (temp file + rename), so a reader sees the whole old file or the whole new one. A widget that cannot decode a file, or sees an unknown schemaVersion, shows its placeholder («افتح مدار») — never partial data. Values hidden by privacy (core.hideMoneyOutside, a locked diary) are omitted from the file, not masked. Definitions: PrayerTodaySnapshot, QuranHomeSnapshot, MoneyNowSnapshot, HabitsTodaySnapshot, DiaryTodaySnapshot, MihbaraSnapshot, YearSnapshot, UpcomingSnapshot (all v1, fields in data-dictionary.json › snapshots).

DayEventBus is invalidation only (“room R, day D changed”), carrying {eventKind, eventID, dayKey} where eventID is the source row's id. Diary lines are rendered at display time from queries (DiaryLineRenderer), so no line text is ever persisted or lost. Sources of invalidation: (1) the CommandBus post-commit step; (2) SwiftData persistent history (fetchHistory with the last HistoryToken, stored in DeviceSetting sys.historyToken) processed on launch, on foreground and on remote-change notifications — this covers CloudKit imports and writes made by another process; (3) a full rebuild of today's snapshots on every launch. If the token is missing or history was pruned, do a full rebuild and store a fresh token.

Why history, not an append-only DayEvent model: history is already durable, already includes remote imports and deletions (tombstones are updates), and adds no second source of truth that would itself need dedupe and sync.

M0 acceptance: kill the app between save() and the snapshot write → next launch shows the correct state; a CloudKit import on device B regenerates B's lines/snapshots without opening the room; replaying the same history twice changes nothing.

CloudKit lifecycle (device settings, account, quota)

Device-only values (core.theme, core.fontScale, core.motion, core.faceIDLock, core.spotlightIndex, core.iCloudSync, core.backup, and internal sys.*) are rows in DeviceSetting; because that model is only in the deviceOnly configuration, no code path can sync it.

iCloud off (core.iCloudSync = false): the factory rebuilds the synced configuration with cloudKitDatabase: .none on the same file. Nothing is deleted locally or in iCloud; other devices keep their copy. Turning it back on re-mirrors, then reconciliation runs.

No iCloud account / restricted: the app works local-only; Settings › البيانات shows «iCloud غير متاح — بياناتك على هذا الجهاز فقط». No nagging.

Account switch: detected by a change of FileManager.ubiquityIdentityToken (hash in sys.iCloudTokenHash) or .CKAccountChanged. Before rebuilding the container Madar writes an automatic local backup (§11 Backup). Then a one-time sheet: «تغيّر حساب iCloud» → “keep this device's data in the new account” (restore the backup into the new account's store if the system purged it) or “use the new account's data” (the backup stays available). Data from account A never appears in account B unless the user chooses it.

Quota full / export errors: local writes always succeed; Settings › البيانات shows «مساحة iCloud ممتلئة — آخر مزامنة: …»; the mirror retries on its own. Sync status is read from CloudKit container events when SwiftData delivers them; if a status is not observable the line says «لا معلومات عن آخر مزامنة». No data path depends on this status.

M0 acceptance: theme/Face ID/Spotlight set on iPhone do not change on iPad; with iCloud off, signed out, or switched account, no row is lost (verify with backup fixture counts before/after).

Navigation

RootView
└─ TabShell (style A: TabView + Liquid Glass | B/C: custom bar overlay)
├─ Tab(.bahw) NavigationStack → LobbyView → HabitsRoom, YearRoom, WidgetMaker
├─ Tab(slot1..4) NavigationStack → room home → room screens
└─ Tab(role: .search) [optional] → GlobalSearch
Sheets: QuickLog (prayer), Capture, Settings (CustomizeMadar, CustomizeRoom(room))
Deep links: madar://<room>/<screen>?… (also used by widgets, notifications, Spotlight)
— one RouteRegistry (parse → validate → lock guard → fetch → navigate); full table and fallback rules in p3 §4 «سجلّ المسارات»;
URLs are read or prefill only, never commands.

Key implementation notes

RTL: set .environment(\.layoutDirection, .rightToLeft) at root; the app's development language is Arabic (ar) with CFBundleDevelopmentRegion = ar. Charts: time runs right→left (oldest on the right) — flip x-axes explicitly in Swift Charts.

Numbers: one MadarNumberFormatter honoring core.numerals; Arabic grouping “٬”, decimal “٫”, percent “٪”. Wrap signed amounts in Unicode isolates. Count words via ported countPages/countDays (Arabic dual/plural rules).

Fonts: UIAppFonts lists UI fonts only (app + widget targets); map them to Font.custom(_:size:relativeTo:). QCF V1 page fonts (604 files) are registered lazily with CTFontManagerRegisterFontsForURL(…, .process), in the app only — never in the widget extension; cache 5 pages around the current one. Every bundled font/data file is listed with source, version and SHA-256 in provenance.json.

Mushaf layout: fixed 15 lines; each line = glyph string in its page font; lines stretch to fill height (GeometryReader + flexible spacing). Word hit-testing via word map for “tap ayah → tafsir” and “hide/reveal words”.

Lobby grid: custom Layout implementing dense first-fit on a 4-column grid; drag with .draggable/.dropDestination or a gesture-based reorder; resize handle snaps to 1×1, 2×2, 4×2, 4×4. Animate with .timingCurve(0.2, 0.85, 0.25, 1, duration: 0.38) (design-tokens motion.rearrange; Reduce Motion: 0.2 s crossfade).

Edit mode: shared EditModeContainer — long press 0.52s, wiggle ±0.7°, “−” hide, drawer of hidden, “Done”. Disabled interactions inside blocks while editing.

Notifications: UNUserNotificationCenter with categories per action set. NotificationArbiter plans and reschedules within the 64-pending limit and respects sanctity windows from PrayerTimesEngine; the prayer ask is scheduled at max(salah.askAfterAdhanMin, sanctityEnd) (sanctity = 30 min, Maghrib 20 min; constants.sanctityMinutes). Mechanics:

Every write path cancels the pending request salah.<dayKey>.<prayer> — implemented once, in the CommandBus post-commit step.

Digest text is static (“لديك ٣ تذكيرات”) unless an app run rewrites it.

Prayer asks are scheduled 3–4 days ahead (about 20 of the 64 slots); budgeted notifications 48h ahead. If the app is not opened for 48h, one final “افتح مدار” reminder fires at the end of the horizon.

NotificationLedger (device-only, not CloudKit) records each request with requestClass (prayer|room|digest|nudge) and state submitted | cancelled | dropped | digested | observed (+ reason budget|quiet|cap|off for dropped). Delivery is not observable for every background notification, so the budget counts submitted.

Background: BGAppRefreshTask to refresh prayer times, reschedule notifications and update widget snapshots; BGProcessingTask for the scheduled backup. It never starts a Live Activity.

Countdown & Live Activities: the next-prayer countdown on the Lock Screen/Home Screen is a WidgetKit timeline (one entry per prayer time, Text(timerInterval:)); no push needed. A Live Activity may be started only from the foreground, from a LiveActivityIntent (Control/Shortcut/button), or scheduled with Activity.request(…start:) (iOS 26) at the end of the sanctity window — never at adhan. Max ~8h active (+4h on the Lock Screen). verify the iOS 26 scheduled start.

Location: default When-In-Use. Travel distance is checked on foreground launch (requestLocation()) and when widgets refresh. An optional “Always” upgrade enables automatic detection (significant location changes) and is explained in the permission text. Without Always, travel mode behaves as “ask me” on the next open. Widgets never request location (no widget location permission); they read the prayer snapshot (7 days of times + place + tz + accuracy flag). Prayer times use the IANA tz of the active place, never the device tz. Manual cities come from a bundled list (name, country, lat, lon, IANA tz) whose source and licence are recorded in provenance.json.

Widgets: no hard-coded point sizes — layouts read WidgetFamily and GeometryReader. Guard the 4×6 family with #available and fall back to systemLarge. Support fullColor, accented and vibrant rendering (widgetAccentable()); timers follow .environment(\.locale).

Version policy: deployment target iOS 26.0; iOS 27-only features sit behind #available with an iOS 26 fallback.

HealthKit: read-only stepCount (default) and appleExerciseTime for the walking habit (optional permission; exercise minutes are labelled as all exercise).

Speech: diary dictation decides per language at runtime: SpeechTranscriber if the locale is supported on this device and its assets are installed (offer the download) → SFSpeechRecognizer with on-device recognition → Apple server recognition only after explicit consent (notes.serverDictationConsent) → record-only. Audio is saved before transcription; cancelling keeps the audio. Arabic on-device support is recorded per device in M3, not assumed.

Performance budgets: cold start < 1.2s to Lobby on iPhone 13; Mushaf page turn < 16ms frame; widgets timeline under memory limits (no images > 1MB).

Testing: XCTest for engines; snapshot tests (swift-snapshot-testing) for each screen in light/dark × Dynamic Type L/AX3/AX5 × RTL with Arabic digits; UI tests for the daily paths (log prayer from notification, complete wird, write a line, review bank messages). M0 also ships the schema harness: build all 61 models with the factory and both configurations, run the CloudKit-rule check (defaults/optionals, no unique, no required relationships) and the invariant checks below — this proves the schema, not the whole app.
