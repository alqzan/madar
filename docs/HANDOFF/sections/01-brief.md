1 · Agent Brief (read first)

Mission. Build Madar (مدار), a native iPhone app (SwiftUI) in Arabic, right-to-left, that is the center of one person's day: prayer, a daily diary, Quran memorization, personal finance, a reading/hadith study room, and a flexible home ("Lobby") of resizable widgets and habits. The design is finished and approved; your job is to build it exactly or better, never worse.

Non-negotiables

Arabic RTL first. .environment(\.layoutDirection, .rightToLeft) everywhere; Arabic-Indic digits (١٢٣) by default with Arabic grouping (٬) and decimal (٫). The primary date follows core.firstCalendar (Hijri first by default) everywhere, except the diary calendar (year wall / month sheet), which is Gregorian-first by approved decision (notes.calendarFirst, default gregorian). Middle dot rule: “·” is allowed only with a space on both sides between date parts (as in the approved designs: “… ١٤٤٨ · ٩ أكتوبر”); it must never touch a digit without a space (it would read as a zero).

One fact, recorded once. Every piece of data has one owner room. Other rooms read it (e.g., the Lobby habit “Jama'ah” reads PrayerLog; the diary's auto-lines are rendered from events, not copied text).

Every number has one meaning and one definition shared across the app (streaks, “day”, “available money”). Definitions are in §8. The day boundary core.dayStart governs every room; the single exception (prayer records are grouped by the prayer day) is stated once in §8.1.

The approved default is sacred. Every setting ships with the agreed default (see settings-schema.json) and a “Reset to agreed” with undo. Appearance never mutates data.

Prayer sanctity. No notification, sound, haptic nudge or Live Activity alert from adhan until the prayer window passes (adhan + 30 min; Maghrib + 20 min). This is not a setting.

No shaming tone. No red for failure except the specific “missed/overdue” clay colors defined per room; copy addresses the user gently (see §2).

Motion explains change, never decorates. Respect Reduce Motion. Quran and Prayer use the least motion.

Prototype-only controls are not features: per-screen day/night buttons, the phone frame, “scene panels” (time of day, Friday, travel simulators) and sample data in the screenshots (full list and precedence below).

Privacy: no third-party analytics, no server of our own. Data lives on device + the user's private iCloud (CloudKit private database).

Source-of-truth precedence & conflict decisions

The bundle is one frozen set: MADAR_HANDOFF.html, design-tokens.json, settings-schema.json, screens-index.json and screens/ are produced together by the lead's build and belong to the same version. Never mix files from different builds.

QuestionGovernsThenNever

Behaviour: rules, formulas, states, what a default means, what ships in v1Text (this document)JSON for the exact valueA screenshot never adds a feature, a rule, a number or a v1 commitment

Exact values: setting key / default / range, colour hex, type size, constantssettings-schema.json, design-tokens.json (the machine copy of the text)TextIf JSON and text disagree it is a bug: apply the text, log it (below), report it

Layout only: composition, spacing, illustration, hierarchy, tone of a screenScreenshot with status = canonical in screens-index.jsonRoom spec (§7.x)superseded screens are not built; deferred screens are not built in v1

Sample content in screenshots (numbers, names, dates, counts)Nothing: illustrative onlyFormulas in the text compute real values; worked examples become test fixtures (§13)Never hard-code a screenshot value

Prototype-only, never built: the per-screen day/night toggle, the phone frame and status-bar mock, “scene panels” (time of day, Friday, Ramadan, travel simulators), board titles, explainer boards (kind = explainer: R18-Sharh, R18-Map, S12-Khulasa, S0-Jard, Qawaid), and all sample data.

Known text ↔ screenshot / JSON conflicts and their final values (closed; do not re-decide while building):

#ItemTextScreenshot / JSON showedFinal valueState

1Mushaf and Hifz page textQCF V1 page glyphs, 15 linesUnreadable single letters (bad export)QCF V1 glyphs; screens re-exportedfixed by lead (D01)

2Prayer home archesFive horseshoe arches over the poolPool strip without arches in the home variantsArches + pool in every variant; re-exportedfixed by lead (D02)

3Heart presence in «حالي»Never counted, ranked, percent, streak or chartAnswer counts and a proportional heart barSentences only; counts and bar removedfixed by lead (D03)

4v2 entries on v1 screensReverse direction, voice recitation, Turath search / text-match are not v1Shown in Quran Setup, Hifz, Rev, Mushaf, Hurra, Sharh and Mihbara “add book”Removed from screens; the availability table in §12 governsfixed by lead (H02)

5Diary home«النافذة»Old home «أ · بسيطة»«النافذة»; old home is supersededclosed

6Turath / Shamela search & download (R10-Turath-Bahth)Needs written permissionA complete flowdeferred; not builtclosed

7Hijri offset range−2…+2, only when core.hijriSource = sightingSource design said ±1−2…+2closed

8Small text colourText under 24pt uses *Text tokens (≥ 4.5:1)Some screens use base accents for small text*Text tokens; a screenshot colour is not a contrast exceptionclosed (text wins)

9System widget at large Dynamic TypeThe OS chooses a widget's family (§9)“Widgets step up a size” (old wording) and screenshots at default sizeLobby blocks may grow a size; a system widget keeps its family and drops lower-priority itemsclosed (I03)

10Mihbara dark desk, navy, notebookYellow—derive: placeholders in design-tokens.jsonFinal dark values are in design-tokens.json v3 (no derive: value remains, checked 2026-10-09)fixed by B1 (D05)

11Sample amounts and counts (money, Quran, prayer)Computed by the enginesVisible in screenshotsUsed only as fixtures where the text names them as worked examplesclosed

A new conflict found while building: apply the precedence above, add a row (item · text · screenshot/JSON · final · why) to docs/DECISIONS.md, and continue. Stop and ask the owner only if it changes a rule, an M0 field, or a licence (§15).

Availability (v1 / v2 / deferred)

Every visible action, option, import source and Intent parameter has one availability in the table in §12. No v1 build shows an entry point to a non-v1 feature: no disabled button, no “coming soon”, no setting option, no Shortcut parameter. Settings marked "availability":"v2" in the schema are absent from Customize and from settings search. Hiding a non-v1 entry must not remove the v1 function beside it (local file import stays when Turath search is hidden). A room that is not built yet (before its milestone) has no entry anywhere, including widgets, controls and Capture routing.

Stack (decided)

AreaChoiceNotes

UI: SwiftUI, iOS 27 SDK, deployment target iOS 27.0. Liquid Glass tab bar (TabView + .tabBarMinimizeBehavior(.onScrollDown)). Use system materials; custom identity per room on top. Version policy: iOS 27.0 is the minimum supported version; use iOS 27 APIs directly without iOS 26 compatibility paths.

StateObservation (@Observable), unidirectional per roomEngines are pure Swift, UI-free, and tested for behaviour against golden fixtures (§13 test plan).

PersistenceSwiftData with CloudKit private DBCloudKit rules: no @Attribute(.unique), all properties optional or defaulted, all relationships optional (§11 “Common fields” + “Natural keys and reconciliation”). One container, two configurations: one ModelContainer factory in MadarData builds synced (CloudKit private DB) and deviceOnly (cloudKitDatabase: .none) stores in the App Group container, used by the app and by App Intents; widget views read JSON snapshots only. Device-only settings live in DeviceSetting in the deviceOnly configuration (never synced); UserDefaults is not used for settings. Money amounts are Int minor units (halalas).

WidgetsWidgetKit + App Intents (interactive), ControlWidget (Control Center/Action button); ActivityKit only under the narrow rules in §9One widget extension; App Group shared container for read-only JSON snapshots. The next-prayer countdown is a WidgetKit timeline (Text(timerInterval:)), not a Live Activity. Activity.request(…start:) is in the iOS 26 SDK (Apple documentation); how reliably a scheduled start is shown is verified on an iOS 27 device at the M1 gate. The countdown never depends on it.

Prayer timesadhan-swift (Batoul Apps, MIT) or an equivalent audited implementationUmm al-Qura method default; Asr standard; manual minute offsets. Isha = Maghrib + 90 min, and + 120 min in Ramadan (Hijri month 9) — implemented in our engine, not taken from the library. Acceptance: the golden times table in §7.2 (tolerance ≤ 1 minute). verify library Umm al-Qura output against that table.

HijriCalendar(identifier: .islamicUmmAlQura) + user offset −2…+2 days recommendationThe source design said ±1; the range is kept at −2…+2. The offset applies only when core.hijriSource = sighting (Umm al-Qura + offset); the UI hides it otherwise.

Quran textQCF V1 page fonts (Madina Mushaf, old print, 604 pages) + word/line map (Quran.com code_v1/line_number or QUL)Approved Mushaf. License contact required before App Store (§14).

FontsThmanyah Sans / Serif Display / Serif Text (bundled), Amiri, Amiri Quran, Reem Kufi, Aref Ruqaa (OFL); reader fonts Literata, Source Serif 4, Atkinson Hyperlegible, IBM Plex Serif, Scheherazade New (OFL — verify each)Thmanyah licence (official page font.thmanyah.com/licenses, read 2026-10-09): embedding in mobile/web/software products is allowed only inside a bundled/packaged/obfuscated product; redistributing, uploading, hosting or making the font files downloadable on their own is forbidden; no modification. In Madar: app + widget extension bundle only; never inside exported files or templates; never in a public repo; licence file + SHA-256 recorded in provenance.json before the first TestFlight build (see design-tokens.json fonts.display.license). UIAppFonts lists UI fonts only; the 604 QCF page fonts are registered lazily with CTFontManagerRegisterFontsForURL(…, .process), in the app only (never in the widget extension).

SpeechDiary dictation: prefer iOS 26 SpeechAnalyzer/SpeechTranscriber when the device reports an Arabic locale as supported and its assets installed (checked at runtime; assets may need a one-time download); otherwise SFSpeechRecognizer with requiresOnDeviceRecognition when supportsOnDeviceRecognition is true verify per device and OS languageIf Arabic is not available on-device, show “يُرسل الصوت إلى Apple للتحويل” before first use. Quran recitation recognition is v2/verify.

Bank SMSApp Intent IngestBankMessageIntent called by a Shortcuts personal automationiOS apps cannot read SMS; this is how the current app already works.

Build machine: Xcode 27 is reported to run only on Apple-silicon Macs (macOS Tahoe 26.6+). The owner has a new 2026 Apple-silicon Mac, so build, simulator and device runs happen locally. Xcode Cloud or a hosted runner is optional for CI. Cloud agents without macOS write code and tests only; compile and verify on the owner's Mac.

Repository layout to create

Madar/
Madar.xcodeproj
App/ // @main, TabShell, routing, onboarding
Packages/
MadarCore/ // Day boundary, Hijri, PrayerTimes, Travel, Seasons, StreakEngine,
// EventBus ("day writes itself"), NotificationArbiter, Settings, Search
MadarDesign/ // tokens (generated from design-tokens.json), fonts, components
MadarData/ // ModelContainer factory (App Group store), SwiftData models, migrations, CloudKit, import from old Madar
RoomBahw/ RoomSalah/ RoomNotes/ RoomQuran/ RoomMal/ RoomMihbara/
Widgets/ // WidgetKit (timelines read JSON snapshots) + Controls (+ Live Activity under §9 rules)
Intents/ // App Intents (Siri, Shortcuts, widgets, bank messages)
docs/ DECISIONS.md HANDOFF/ (this bundle)
Tests/ // engine unit tests + snapshot tests (RTL, Arabic digits, dark, Dynamic Type)

Build order (each ends with a runnable TestFlight build)

§12 (plan) is canonical; the names below are copied from it.

M0 Foundation — design system, settings store, day boundary, Hijri, prayer times, tab shell, migration skeleton, plus the shared plumbing every later room needs: the widget-extension skeleton + App Group snapshot writer, NotificationArbiter, and DayEventBus (no-op subscribers). First-run steps appear as each room lands.

M1 Prayer — the clock every room depends on; logging from notification.

M2 Quran — memorization engine + sessions (used daily).

M3 Diary (المذكرات) — today page, editor+dictation, memories, auto-lines.

M4 Lobby + Habits + Widgets → v1 usable daily, deliberately partial: widgets, controls and Capture routing exist only for rooms already built (prayer, Quran, diary, habits, year, upcoming).

M5 Money — bank-message ingestion, cycle, envelopes, cards, plus money's widget cells, control and intents.

M6 Mihbara — shelf, desk, hadith ward, reader, notebook, plus Mihbara's widget cells.

M7 Polish & launch — final integration gate: all Live Activity states, 4×6 widget, Spotlight, store page, privacy nutrition label, scholarly review of texts, two-device and performance runs. Licences, accessibility and restore are checked at each room's gate (§12), not first here.

Definition of done (every screen)

Pixel-close to its screenshot in light and dark; RTL; Arabic digits; Dynamic Type through AX5 without clipping; at AX1–AX5 every custom drawing switches to its list alternative (p3 §5 accessibility table); in-app Lobby blocks step up a size instead of truncating; system widgets keep their OS-chosen family and drop secondary lines by priority (§9); only the Mushaf page text is fixed-size (it offers zoom and a semantic ayah layer).

Text smaller than 24pt uses the *Text color variants (≥ 4.5:1); base accent colors are for shapes and large text only (§5).

All states in the room spec exist (empty, first day, normal, overdue, travel, Friday, Ramadan, night, after absence).

VoiceOver labels in Arabic for every control; touch targets ≥ 44pt.

Settings that affect it are wired to the shared SettingsStore and appear in that room's “خصّص” page and search index.

Engine rules covered by behavioural tests whose expected values come from the worked examples in this document (golden fixtures, §13); no coverage-percentage target, and no claim that something was tested without a test report.

Every visible action is v1 in the availability table (§12); nothing non-v1 has an entry point.

When to stop and ask the owner

Only for items tagged open in §15, for anything that changes a rule written here, or for licensing. Everything else: follow this document; if you find something better, implement it behind the same interface and log it in docs/DECISIONS.md.
