# Madar — Handoff Review Fixes — V1

- **Who reads this:** coding agents (Codex and Claude Code).
- **What it reviews:** handoff bundle v3 (09/10/2026).
- **Human-readable version:** the owner's Arabic review document, «مراجعة ملف تسليم مدار (v3)».
- **Precedence:** this file overrides the handoff where the two conflict (see `AGENTS.md`).
- **If you received this file as an attachment:** put it in `docs/HANDOFF/` and follow `AGENTS.md` (or `CLAUDE.md`), which the owner attached with it. That file explains how Codex and Claude Code work on this repo together.

## How to use this file

- **Item format.** Each item has an ID, a tag, and the milestone that applies it. It states the problem (with a spec reference), what to do, and how to check it.
- **Tags.**
  - `[FIX]` corrects a defect. Apply it.
  - `[DEFAULT]` is a recommended change, applied by default. The owner may revert it; log any reversal in `docs/DECISIONS.md`.
- **Timing.** Apply each item in the milestone shown. Items marked **Before M0** are corrections to the spec and JSON files, made in task M0-T00.
- **Test names.** Name tests after the item, e.g. `test_RP1_unloggedNeverBecomesQada()`.
- **Doubts.** If an item is unclear or contradicts something you find, log it in `DECISIONS.md` and ask the owner. Don't guess.

## Index by milestone

| Milestone | Items |
|---|---|
| Before M0 | RA4, RA5, RA6, RA9, RD2, RD5, RMI1, RQ8, RL5, RP6 |
| M0 | RA1, RA2, RA3, RA8, RL8, RU1, RU3 |
| M1 Prayer | RP1–RP5, RP7–RP9, RA7, RL7 |
| M2 Quran | RQ1–RQ7, RQ9 |
| M3 Diary | RD1, RD3, RD4, RD6–RD8 |
| M4 Lobby, Habits, Widgets | RL1–RL4, RL6, RL9 |
| M5 Money | RM1–RM10 |
| M6 Mihbara | RMI2–RMI4 |
| Every milestone and screen | RL10, RU2, RU4, RU5, RU6 |

---

## Architecture and process (RA)

**RA1 · [DEFAULT] · M0 — The v1 store is local-only**

- **Problem:** §10 and §11 sync 55 models through SwiftData + CloudKit from M0.
  - Once a CloudKit schema is deployed to Production, its fields can't be removed or renamed, and TestFlight builds use Production. The handoff never mentions this.
  - The promise in §11 that the newest row wins (by `updatedAt`) is not something the app can control: the CloudKit mirror resolves conflicts outside the app's code, as §11 itself admits.
- **Do:**
  - Every store from the `MadarData` factory uses `cloudKitDatabase: .none` in v1.
  - Keep the code ready for sync: UUID IDs, optional or defaulted properties, no unique constraints, tombstones, natural keys.
  - Durability comes from the iOS device backup plus the encrypted export.
  - Never deploy a CloudKit schema to Production without the owner's approval.
  - Decide on sync again after M5. The options are SwiftData + CloudKit, or SQLite/GRDB + CKSyncEngine.
- **Check:** no build touches a CloudKit container. Export, then wipe, then import restores every row.

**RA2 · [FIX] · M0 — One writer: extensions never open the store**

- **Problem:**
  - §10 lets an App Intent open the store "in whichever process", and intents from interactive widgets and Live Activities run in the extension process.
  - A process suspended while holding SQLite locks in an App Group container is killed by iOS (0xdead10cc).
  - Without unique constraints, "check, then insert" from two processes creates duplicate rows.
- **Do:**
  - Only the app process opens the store.
  - Widget, Live Activity and Control intents:
    1. append a Command to the App Group `PendingInbox`, written as JSONL with atomic writes;
    2. update the snapshot optimistically;
    3. reload the timelines.
  - The app drains the inbox through the normal command path, idempotent by command ID.
- **Check:** with the app suspended, "one command from a notification and from a widget leaves one row" passes.

**RA3 · [DEFAULT] · M0 — A lean M0**

- **Problem:** §12 M0 has 19 deliverables and 13 gate items before any room exists. They include three tab-bar styles, the full customisation template, an encrypted backup, an arbiter tested on a synthetic week of rooms that don't exist yet, and all 61 models.
- **Do:** M0 builds only:
  - tokens and fonts
  - MadarDay (the day boundary)
  - the Hijri calendar
  - PrayerTimesEngine
  - the tab shell, glass style only (RL8)
  - SettingsStore with only the keys M1 uses
  - the M1 models
  - the command write path and the inbox (RA2)
  - a plain export

  Everything else is built in the first milestone that needs it.
- **Check:** M0 ends with a build on the owner's iPhone that shows the tab shell and today's prayer times.

**RA4 · [FIX] · Before M0 — Rename the `Transaction` model**

- **Problem:** the name collides with `SwiftUI.Transaction` and `StoreKit.Transaction`.
- **Do:** rename it to `MoneyTransaction` in `data-dictionary.json`, §11, and every reference.

**RA5 · [FIX] · Before M0 — Journeys cited but not defined**

- **Problem:**
  - The gates in §13 cite journeys "J01–J18", but J03, J04 and J05 appear nowhere.
  - J06, J09, J11, J13, J14 and J16 are tags without steps.
  - §12 cites "the seven tests of §11", but §11 lists eight.
- **Do:**
  - Before each gate, write the journeys it cites in `docs/journeys/<room>.md`: steps, data states, and whether a device is needed. Otherwise, remove the reference.
  - Correct the count.

**RA6 · [FIX] · Before M0 — Owner runbook**

- **Problem:** the handoff never covers:
  - Apple Developer Program enrolment, which is paid and required for TestFlight and CloudKit
  - bundle IDs, the App Group and iCloud container IDs, and the capabilities for each target
  - the Info.plist usage strings and the privacy manifest
  - TestFlight groups
- **Do:** write `docs/OWNER-RUNBOOK.md`: the owner's steps in order, and what the agent needs back from the owner after each one.

**RA7 · [FIX] · M1 — Independent prayer-time fixtures**

- **Problem:** the golden rows in §7.2 were produced with adhan-swift and adhanpy, so they test the library against itself. An independent recomputation agreed to within one minute, so the values are right.
- **Do:** add two or three rows for Riyadh copied from the official Umm al-Qura timetable.

**RA8 · [DEFAULT] · M0 — Fewer settings in v1**

- **Problem:** 127 keys, of which 64 are included in presets and 22 switch between alternate designs.
- **Do:**
  - Ship about 60 settings in v1, with no saved presets.
  - Mark the cut keys `availability: v2` in `settings-schema.json`. Keep them in the file, and hard-code their defaults:
    - `tabbar.style`, `tabbar.labels`, `tabbar.openOn`, `tabbar.minimizeOnScroll`
    - `bahw.habitsView`, `bahw.yearView`, `bahw.upcomingView`, `bahw.smartPresence`, `bahw.iphoneWidgetFamily`, `bahw.widgetIdentity`, `bahw.widgetScope`
    - `core.fontScale`, `core.motion`, `core.roomIdentity`
    - `salah.balanceView`, `quran.toolsOrder`, `notif.roomPriority`, `notes.echoDistances`
    - `mihbara.shape`, `mihbara.sunnahPlace`, `mihbara.pageStyle`, `mihbara.motivateStyle`, `mihbara.notebookStyle`

**RA9 · [FIX] · Before M0 — An agent-readable spec**

- **Problem:** the 760 KB HTML file can't be held in context during a task.
- **Do:**
  - Split it into `docs/HANDOFF/sections/NN-<name>.md`: one file per §, text only, no content changes.
  - Task cards cite these files.

---

## Prayer (RP)

**RP1 · [FIX] · M1 — Never turn an unlogged prayer into a debt**

- **Problem:**
  - In §7.2 (rules, `AgePendingPrayers`), once `pendingDays` (7) pass, any prayer without a log is written as `missed` and gets a QadaItem.
  - After a three-week gap, the owner comes back to about 70 prayers shown as «عليك», with a daily reminder. «لم أسجّل هذه الفترة» only appears on the return sheet, after the aging has already run.
  - The app is deciding a religious status for the user, which breaks §2 rule 6 («يعرض ولا يفتي»).
  - There is no status for a prayer that is not owed.
- **Do:**
  - Remove `AgePendingPrayers`.
  - An unlogged prayer past `pendingDays` is derived as `unconfirmed`, with no row. Such a prayer:
    - creates no QadaItem
    - is excluded from the ratio
    - is never shown as «عليك»
    - pauses the streak («غير مكتمل التسجيل») rather than breaking it, until resolved
  - On return, one sheet resolves the whole gap. For each prayer the user picks one of:
    - prayed (jamaah or alone)
    - missed, which creates qada
    - not recorded (`unrecordedHistory`)
    - excused
  - Add `excused` to `PrayerLog.status`. An excused prayer is neither due nor owed, and is excluded from the ratio and from streaks.
- **Check:** tests for a three-week gap that creates zero QadaItems, for resolving a gap in bulk, and for excused.

**RP2 · [FIX] · M1 — "Missed" and qada only after the prayer's window ends**

- **Problem:**
  - In screen S2b-Missed it is 4:20 pm, Asr has not ended, yet Asr is already marked «فاتتني… نزلت في القضاء، وهي عليك».
  - The notification at +30 also offers «فاتتني».
  - The spec never defines when a prayer's window ends.
- **Do:**
  - Window ends: Fajr at sunrise, Dhuhr at Asr, Asr at Maghrib, Maghrib at Isha, Isha at the next Fajr. These are the latest permissible ends. Any earlier end is an owner setting, never the app's judgement.
  - Before the end, offer only «لم أصلّها بعد» or snooze.
  - Remove «فاتتني» from the +30 notification.
- **Check:** edge tests at the window end for all five prayers.

**RP3 · [FIX] · M1 — One sanctity guard for every path**

- **Problem:** §8 item 8 delays only room reminders out of a sanctity window. These paths bypass it:
  - The «ذكّرني بعد ساعة» snooze. The Maghrib question comes at +30, so its snooze fires at +90, which is the Isha adhan.
  - `salah.askAfterAdhanMin` = 90 at Maghrib.
  - The digest, when quiet hours start early.
  - The "open Madar" nudge.
  - In Ramadan, the Isha question (+30) and possibly the digest, which land during tarawih.
- **Do:**
  - `SanctityGuard.clamp(_:) -> Date` is the last step for every notification request, including snoozes created at tap time, and for every Live Activity start.
  - It loops until the time is clear of every window, including the next prayer's.
  - Proposed values, which the owner may tune:
    - On Friday, the Dhuhr window runs about 60 minutes (khutbah).
    - In Ramadan, the Isha window runs about 90 minutes (tarawih).
- **Check:** a property test over a full year for Riyadh, Jeddah and one high-latitude city shows no request inside any window.

**RP4 · [FIX] · M1 — Calculation method per trip**

- **Problem:**
  - `salah.method` is one global setting with three options, and `Trip` has no method.
  - Umm al-Qura's fixed Isha (Maghrib +90) differs from local methods by about 30 minutes in London in winter and in Istanbul in summer.
- **Do:**
  - Add `Trip.calcMethod`, plus an Asr school if needed.
  - When a trip starts outside Saudi Arabia, ask once and suggest the local method. adhan-swift includes Muslim World League, Turkey, North America (ISNA), Dubai, Kuwait, Qatar and others.
  - Show the method and city under the arches.
  - The Ramadan +120 rule applies only with Umm al-Qura.
- **Check:** fixtures for London with Muslim World League and for Istanbul with Turkey.

**RP5 · [FIX] · M1 — Record Friday explicitly**

- **Problem:**
  - §7.2 infers Jumu'ah from "Dhuhr, in congregation, not shortened, on a Friday".
  - So a Dhuhr prayed in congregation after missing Jumu'ah can't be recorded, and a missed Jumu'ah becomes a "Jumu'ah qada".
- **Do:** add `PrayerLog.fridayKind` = `jumuah | dhuhr` for the Friday noon slot.

**RP6 · [DEFAULT] · Before M0 — Heart presence**

- **Problem:**
  - «حالي» ranks prayers: «أخشعُ صلواتك الفجر، وأشردُها العصر» (S3-Hali-s1). §15 #16 forbids ranking.
  - «خاشع» shows under the arches every day.
  - `salah.askHeart` is on by default.
- **Do:**
  - Set `salah.askHeart` to false by default.
  - No superlatives and no ranking.
  - No persistent heart label on the home arches.
  - Reflective sentences appear only if the owner turns the question on.
  - A qualified reviewer checks the wording before any external release.

**RP7 · [FIX] · M1 — Ask about travel; don't assume it**

- **Problem:** any trip over 300 km shows «مسافر · قصرٌ وجمع» and pairs Isha with Maghrib before Maghrib is even logged.
- **Do:**
  - Show «خارج مدينتك» until the owner answers one question at the start of the trip.
  - No pre-pairing.

**RP8 · [FIX] · M1 — A user's own entry beats a generated row**

- **Problem:** with "latest update wins" for each row, a generated row can overwrite what the user entered on another device.
- **Do:** a row with `source = user` always wins over a generated row, whatever their `updatedAt`. Implement this in the merger now; it matters once sync exists.

**RP9 · [FIX] · M1 — Prayer in the privacy matrix**

- **Problem:** §8 item 10 has no prayer rows, so lock-screen widgets show «عليك ٣ فوائت» and streaks.
- **Do:**
  - By default, outside the app shows only the next prayer and its time.
  - Qada counts and streaks appear outside the app only if the owner opts in.

---

## Quran (RQ)

**RQ1 · [FIX] · M2 — Review capacity must grow with what's memorised**

- **Problem:**
  - Daily review N is fixed at 4, 8, 12 or 22 pages by day level (§7.4 «مقدار اليوم: الأسبقية»), with recent pages served first. At «متوسط» about 3 slots are left for due pages.
  - With 284 pages memorised and a longest interval of 84 days, the due load is at least 284 ÷ 84 ≈ 3.4 pages a day, even if every page sits at its longest interval.
  - So the backlog grows, and «الميزان» cuts new hifz to half a wird on most days. A rough simulation of the written rules gave 347 of 365 days.
- **Do:**
  - Today's review = recent pages + all due pages (weakest first) + the recovery share.
  - The user's level sets a minimum, not a cap.
  - The half-wird threshold is relative to the computed need, not to a fixed N.
  - Add a fixed-cycle mode (one juz a day, or seven manzils a week) alongside spaced review.
- **Check:** a 365-day load simulation at 100, 300 and 604 pages, run with 100% «متقن» and with 35% «جيد». Half-wird days must be ≤ 10%. That target is a proposal; the owner may change it.

**RQ2 · [FIX] · Before M2 — Write the engine down before porting it**

- **Problem:**
  - `provenance.json` says the legacy repo (My-dream @ `aba0c1b`) was not readable when the spec was written, yet rows are marked «مطابق».
  - These are undefined in the bundle:
    - `BACKLOG_FACTOR`, `adaptiveReviewCap`, `CONSISTENCY_WINDOW`, `nextEase`
    - the size of `smartTestPortion`
    - what «جيد» and «يحتاج» do to a page's stage
    - why `PageSchedule.stage` runs from 0 to 12
  - The M2 gate requires every legacy `*.test.ts` to pass, although parts of that logic were changed on purpose.
- **Do:**
  - Read the legacy code at the pinned commit.
  - Write every formula and constant into the Quran room spec.
  - Mark each legacy test keep, rewrite or drop.
  - Rebase date fixtures onto MadarDay, where the day starts at Fajr.

**RQ3 · [FIX] · M2 — Learning peeks are hints, not mistakes**

- **Problem:**
  - Every reveal tap in the coach is recorded as a MistakeEvent and feeds the wird grade.
  - A grade of «يحتاج» forces «تثبيت» and stops new hifz the next day.
- **Do:**
  - Grade only slips in blind recitation.
  - Record reveals during the learning stages as hints, and keep them out of «أخطائي».

**RQ4 · [FIX] · M2 — One definition of "far"**

- **Problem:**
  - "Far" means not reviewed for 30 days; the Mansub screen says 20.
  - The scheduler deliberately spaces mastered pages 30–84 days apart.
  - So healthy pages get flagged and pulled early, and an early review can't advance a page's stage.
- **Do:**
  - Far = overdue by at least one full interval, or strength below 50.
  - Use one constant everywhere.

**RQ5 · [FIX] · M2 — Partial pages and khatm**

- **Problem:**
  - Memorised ayat on the current, incomplete page are never reviewed until the page is complete.
  - «ختمت» counts only from the user's starting position to page 604, so a user who started at An-Naba' is told they finished the Quran after juz 30.
- **Do:**
  - Add those ayat to «القريب».
  - Khatm means all 604 pages are memorised.

**RQ6 · [FIX] · M2 — Internal contradictions**

- **«وزّعه»:** the text says +⅓ page a day for 3 days. The Khitta screen says «نصف وجه زيادة في يومين». The text wins; fix the copy.
- **Pace window:** the text says 28 days; Sijil-All shows 60 days and 8 weeks. Use 28 days everywhere.
- **Rest day:** the week screen shows «٥ من ٦» and the home «٥ من ٧». Use one rule.
- **Review order:** it is described three different ways. Define one: recent pages first, then due pages from the lowest strength up.

**RQ7 · [FIX] · M2 — One Mushaf edition for all data**

- **Problem:**
  - Juz boundaries differ between Tanzil metadata and King Fahd Complex data, for example at juz 4 and 11.
  - The current King Fahd Complex layout differs from the 1405 layout (the QCF V1 fonts) on about 25 pages.
- **Do:**
  - Take the page, line and word maps and the juz/hizb boundaries all from the same 1405 dataset as the QCF V1 fonts.
  - Run the CI checks against that dataset only.

**RQ8 · [FIX] · Before M0 — Tafsir stays off until licensed**

- **Problem:**
  - `quran.tapForTafsir` defaults to true with no availability gate.
  - The Mushaf hint «المس الآية لتفسيرها» and the VoiceOver tafsir action appear unconditionally.
- **Do:**
  - Set the default to false.
  - Gate it behind the M2 licence check.
  - Hide the hint and the action until then.

**RQ9 · [DEFAULT] · M2 — Home density**

- **Problem:** «مسار اليوم» carries about 25 labels, against the §5 scan rule of at most 4 secondary labels per card.
- **Do:**
  - One line per step, with a single «ابدأ». Details sit behind a tap.
  - «عميق» and «محكم» should say what they mean: ×1½ and ×2 the amount.

---

## Money (RM)

**RM1 · [FIX] · M5 — Debit (mada) cards**

- **Problem:**
  - `Card` has no kind.
  - The movement table books every card purchase as credit-card debt («عليك»).
  - "mada" appears nowhere in the spec.
  - So most Saudi card spending, including Apple Pay on mada, would show up as unpaid credit-card debt.
- **Do:**
  - Add `Card.kind` = `debit | credit | prepaid`.
  - A debit purchase posts to the linked account: cash goes down, debt is unchanged.
  - Add mada and Apple Pay SMS samples to the test corpus.

**RM2 · [FIX] · M5 — The headline must answer "how much can I spend today?"**

- **Problem:**
  - «لك الآن» accumulates from the start of the cycle, yet «تجاوزت يومك بـ٤٢٠» is built on it, while the log judges each day against the daily amount.
  - The home screen shows three "available" numbers: «لك الآن», «لك فعلًا» and «متاح». The last one includes future daily allowances.
  - A pending big expense is left out of all three without any notice.
- **Do:**
  - The top line reads «اليوم: صرفت X من Y», alongside the cumulative «لك الآن».
  - "Over today" and "over the cycle" get different wording.
  - Move «المتاح» to the basis screen and rename it «غير مخصّص».
  - Show a badge for pending decisions.
- **Note:** the layout change is `[DEFAULT]`; the wording semantics are `[FIX]`.

**RM3 · [FIX] · M5 — One funding model for plans**

- **Problem:**
  - §7.5 defines the daily amount as the allowance minus the plans' daily share.
  - But `EnvelopePlan.source` only allows salary, surplus or reserve.
  - The Tamara instalment is reserved from salary and also taken from the daily amount, so it is reserved twice.
- **Do:**
  - `EnvelopePlan` gets a `source` (salary, daily, surplus or reserve), a `period` (per cycle or per day) and a `start`.
  - BNPL instalments have one funding path.

**RM4 · [FIX] · M5 — Obligations aren't counted twice**

- **Problem:**
  - Bills are reserved in «المحجوز» and in the salary report.
  - Paying them is then charged to the daily amount by default.
  - The parser has no class for bill payments.
- **Do:**
  - Any transaction linked to an obligation is budget-neutral.
  - Add a `billPayment` (SADAD) class that links to the obligation automatically by biller.

**RM5 · [FIX] · M5 — Transfers between own accounts, and wallets**

- **Problem:**
  - Each side of a transfer arrives as its own SMS.
  - `Account` has no identifier beyond sender IDs, which every account at the same bank shares.
  - No rule pairs the two sides, so the outgoing side is charged to the daily amount.
  - Wallets (STC Pay, urpay) have no kind.
- **Do:**
  - Add account identifiers: the last 4 digits of the account or IBAN.
  - Pairing rule: same amount, opposite sides, both accounts owned, within N minutes. A match is an internal transfer.
  - Add `wallet` to `Account.kind`, with a tracked or untracked policy.

**RM6 · [FIX] · M5 — Complete the SMS parser**

- **Problem:**
  - Classes are missing:
    - declined and reversed transactions
    - refunds, linked to the original purchase
    - salary and other income
    - SADAD payments
    - fees
    - Tamara and Tabby instalments
  - `eventAt` is when the message arrived, not the time printed in it.
  - OTP messages are "discarded" in one place, but "the raw text of every message is kept" in another, and messages sync.
- **Do:**
  - A complete class list.
  - `eventAt` comes from the SMS text whenever it carries a time.
  - OTP text is never stored.
  - Per-bank fixtures from the owner's anonymised messages.
  - An accuracy target on the test corpus: proposed at ≥ 95%.

**RM7 · [FIX] · M5 — Zakat without silent fiqh choices**

- **Problem:**
  - The nisab uses gold only (85 g × the user's price), although §7.5 says «بلا ترجيح». Silver (595 g) is a recognised basis. With gold priced at 80–100 times silver, the silver nisab is about 11–14 times lower.
  - The karat is unspecified, so entering a 21K price understates the nisab by 12.5%.
  - "Deduct everything owed" leaves out the loan.
  - Screen 32-Z-R19-zak has no «تقريبي» label, and says the gold price «يُحدَّث من مصدر», although v1 is manual only.
- **Do:**
  - The nisab basis is an explicit user choice: gold (24K) or silver.
  - Label the price field "per gram of 24K".
  - Define the debt options, including the loan.
  - Label every result «تقريبي» and phrase it «لو حال الحول اليوم».
  - Manual price only.

**RM8 · [FIX] · M5 — Dedupe**

- **Problem:**
  - The fingerprint includes the minute. A Shortcut row uses the run time, while a pasted row uses the time parsed from the text, so the acceptance case "Shortcut, then paste → one row" fails.
  - A bank resending the same message a minute later is not caught.
- **Do:**
  - Fingerprint = sender + normalised text (+ an occurrence number).
  - Near-duplicate rule (same account, amount and merchant, within ±10 minutes): ask the user.

**RM9 · [FIX] · M5 — Cycle edges and runway**

- **Problem:**
  - A salary credited between midnight and Fajr gets the previous day's `dayKey`.
  - There is no setting for the salary day or for the cycle calendar (Hijri or Gregorian).
  - An early salary (before a weekend or Eid) changes the daily amount in percent mode.
  - «تكفيك ٨ أشهر و١٠ أيام» ignores obligations: 3,660 per cycle, which makes it about 6.3 months.
  - How «لك فعلًا» treats the loan is never stated.
- **Do:**
  - A cycle starts at the salary's `eventAt`.
  - Add settings for the salary day and the cycle calendar.
  - Define how an early salary is handled.
  - The runway subtracts obligations.
  - State how the loan is treated.

**RM10 · [FIX] · M5 — Screens that break the rules**

- **Red for overspent days:** only the clay colour, and only for debt envelopes, is allowed (the no-shaming rule).
- **Amounts on the lock screen** (13-Z-R18-a80-1): `core.hideMoneyOutside` defaults to true, so this screen is wrong.
- **Features with no spec text:** receivables, a 78/100 score, and an essential/luxury split. Don't build them (§1 precedence).
- **Copy:** «يمديك» and «تجاهل هالمرة» are dialect. Rewrite them in فصحى قريبة (RU4).

---

## Diary (RD)

**RD1 · [FIX] + [DEFAULT] · M3 — The read-only past**

- **[FIX]:**
  - **Problem:** the moment an entry freezes is undefined. An entry written at 03:50 freezes at Fajr. Dictation errors become permanent.
  - **Do:**
    - An entry freezes 24 hours after its day ends.
    - The transcript of a voice entry stays editable, because the audio is the original.
    - Auto-lines freeze when the day closes, as a snapshot, so later edits to their source don't rewrite past pages.
- **[DEFAULT]:**
  - **Do:** after the freeze, allow edits with a visible «عُدّل» mark and keep the original revision, instead of margins only.
  - **Owner:** may restore strict read-only (§2 rule 4).

**RD2 · [FIX] · Before M0 — Delete policies in `data-dictionary.json`**

- **Problem:**
  - `Entry` soft-cascades to `MarginNote`. §7.3 says «حذف المدخلة الأصل ← يبقى الهامش في يومه بلا سهم».
  - `Book` soft-cascades to `ReadingSession` and `Highlight`. That wipes the reading history the habits and the diary's auto-lines rely on.
- **Do:**
  - Deleting an entry keeps its margins, orphaned.
  - Deleting a book tombstones it with a snapshot of its title and keeps its sessions and highlights.
  - "Delete file" (to free space) is a separate action from "delete book".

**RD3 · [DEFAULT] · Before any sync — Encrypt diary text in the cloud**

- **Problem:** there is no decision on CloudKit field encryption, while Day One offers end-to-end encryption.
- **Do:**
  - When sync is turned on, every free-text field in the diary uses encrypted values (`allowsCloudEncryption`). That covers entries, margins, letters, the day's intention and evening text, notebook notes, and question answers.
  - Decide this before any Production schema exists.

**RD4 · [FIX] · M3 — Backups that scale**

- **Problem:**
  - Each backup is one encrypted file holding every media file and every book file, and a single book file can be 500 MB.
  - It runs weekly and keeps 4 automatic copies plus all manual ones (§11).
- **Do:**
  - Back up media incrementally, by sha256.
  - Leave out book files that can be imported again.
  - Show the backup size before the user turns it on.
  - Cap the total size.

**RD5 · [DEFAULT] · Before M0 — Keyboard first**

- **Problem:**
  - `notes.dictationFirst` is true by default.
  - Arabic support in SpeechAnalyzer is unverified.
  - The server-based recogniser stops after about a minute of audio per request, and it sends the audio to Apple.
- **Do:**
  - Set the default to false.
  - Dictation is tap to start and tap to stop.
  - Split server audio into chunks shorter than 60 seconds.
  - When recognition is not on the device, show the notice that the audio is sent to Apple.

**RD6 · [FIX] · M3 — No "smart" features without written rules**

- **Problem:** these have no rules:
  - The question of the day and the yearly question. There is no question bank, and `DayPage` stores no question ID.
  - «لِغد… مدار يقترح».
  - Extracting names in the index, such as «عميل المقاولات».
- **Do:** build them only once the rules are written: a question bank plus a question ID. Until then, they are not in v1. No LLM calls.

**RD7 · [FIX] · M3 — Settings and widgets follow the lock**

- **Problem:**
  - There are three different designs for diary settings (notes-app 10/11, N4, flex/09).
  - N4 shows «بلا قفل», but `core.faceIDLock` defaults to `notesOnly`.
  - The diary widget (notes-app/16-outside) shows text and a photo under the default lock.
- **Do:**
  - Build diary settings only from the shared «خصّص» template (flex).
  - Showing content in the widget is opt-in and uses `.privacySensitive()`.

**RD8 · [FIX] · M3 — Day One import**

- **Problem:**
  - Tags are dropped.
  - How media referenced inside the text is handled is undefined.
  - The time-zone rule differs: §7.3 uses the entry's original zone, §11 the home zone.
- **Do:**
  - Keep tags, as projects or as a tag field.
  - Resolve inline media.
  - Use the entry's original zone.
  - Test a round trip with a real export sample.

---

## Mihbara (RMI)

**RMI1 · [FIX] · Before M0 — Remove v2 items from v1 screens and settings**

- **Problem:**
  - Arabic hints appear above English words (12-R9-Reader-En, 13-R9-Reader-En-Aa and its -s1 scroll, 14-R9-Reader-En-Word). The English reader's default in `settings-schema.json` is `arabicHints: "hard"`, yet §12 and §15 #21 say this is v2 and hidden.
  - «الاثنان» shows the printed page beside the text (19-R10-Milaf-PDF-s1).
  - «نطابقها مع طبعتك» (25-R10-Bitaqa-Waraqi).
  - The custom meaning cards can't be built from the system dictionary.
- **Do:**
  - `arabicHints`: availability v2, default off.
  - Remove «الاثنان» and the edition matching.
  - Word meanings come only through the system Look Up UI.

**RMI2 · [DEFAULT] · M6 — The minimal room first**

- **Build first:**
  - a shelf: reading, want, finished
  - import of EPUB, text PDF, scanned PDF (shown as page images) and txt; Goodreads CSV; paper books
  - a reader with 3 themes, text size, 2 fonts, highlights and notes, and active-time sessions
  - Nawawi's Forty, one hadith a day, with «فهمته / أرجع له»
  - a notebook with private notes
- **Later tasks:** OCR, listening, auto-scroll, focus mode, «حمّسني», and the four desk shapes.

**RMI3 · [FIX] · M6 — Rights**

- **Problem:**
  - «حمّسني» quotes from modern copyrighted books.
  - «شرح ابن عثيمين» is shown as a bundled layer (15-R9-Durj-Iqra), with no provenance row.
- **Do:**
  - «حمّسني» uses only the owner's own highlights and notes, plus public-domain text.
  - No bundled commentary without a provenance row and confirmed rights.

**RMI4 · [FIX] · M6 — Legibility on the wood desk**

- **Problem:**
  - The `wood` colour is marked decorative, yet labels sit on it at about 3.3–3.9:1.
  - Page headers and page numbers are about 9–10 pt; the minimum is 11.
- **Do:** text on wood uses only a listed contrast pair, at 11 pt or larger.

---

## Lobby, habits and widgets (RL)

**RL1 · [DEFAULT] · M4 — Labelled rings first**

- **Problem:** the habits orbit (01-F1-Nihai) has about 20 unlabelled beads of about 12 pt, some overlapping, identified only by touch («المس حبّة لتعرفها»).
  - It breaks the 44 pt touch rule.
  - It breaks the scan rule of at most 3 unlabelled icons.
  - The "frozen" state is shown by colour alone.
- **Do:**
  - The Lobby default is the labelled rings (02-W1-Bahw).
  - The orbit lives in the Habits room, with labels.
  - No state is shown by colour alone.

**RL2 · [FIX] · M4 — HabitEvent instead of max-merge**

- **Problem:**
  - `HabitLog` holds one row per period and merges with "value = max".
  - `habit.complete` adds to the value.
  - So +1 on each of two devices, starting from 2, gives 3 instead of 4.
- **Do:**
  - Store append-only `HabitEvent` rows.
  - The value is the sum of the period's events.
  - This also records the actual day a weekly habit was done.

**RL3 · [FIX] · Before M4 — Define the habit rules**

- **Undefined today:**
  - Does «أقل القليل» count toward «٤ من ١٠»?
  - There are two sources for a target: `HabitPolicy` and the designated days.
  - Which period does a frequency change apply to?
  - What is the target of the transitional week, which lasts 7–13 days?
  - What are the limits on freezes, and can they be backdated?
- **Streak setting:** `bahw.streakBreakAfter` (1|2|3) rewrites history, although policies are never retroactive, and the visuals assume 2.
- **Do:**
  - Write these rules down, with J08 fixtures.
  - `[DEFAULT]`: fix `streakBreakAfter` at 2 in v1 and remove the setting.

**RL4 · [FIX] · M4 — One streak per fact**

- **Problem:** the linked «الجماعة» habit and «سلسلة المسجد» compute different streaks for the same prayers.
- **Do:** a linked habit shows the streak of the room that owns the data.

**RL5 · [FIX] · Before M0 — Live Activities**

- **Problem:**
  - According to Apple's documentation, a scheduled start (`Activity.request(…, start:)`):
    - needs an `AlertConfiguration`, which means it alerts the user
    - can only be requested from the foreground or from a `LiveActivityIntent`
  - Activities also have a maximum duration of about 8 hours.
  - §9 treats the scheduled start as silent, and `salah.liveActivity` is on by default.
- **Do:**
  - Set `salah.liveActivity` to off by default.
  - Start activities only from the app, a Control, or a `LiveActivityIntent`.
  - Starts count against the notification budget and respect quiet hours.
  - No activity runs from Isha to Fajr.
  - Verify all of this on a device at M1.

**RL6 · [DEFAULT] · M4 — No widget maker in v1**

- **Problem:**
  - The maker offers size and placement choices that iOS doesn't allow.
  - It promises widgets that «تختفي إذا لا شيء يهمّ», which is impossible once a widget is placed.
- **Do:**
  - Ship fixed widgets for each room, configured through an AppIntent.
  - Defer the maker.

**RL7 · [FIX] · M1 — Countdown format**

- **Problem:** `Text(timerInterval:)` shows h:mm:ss and updates every second. The design shows «١:٢٠».
- **Do:**
  - Use a two-field format: for example `SystemFormatStyle.Timer` with a maximum field count, per Apple's documentation (verify).
  - Or use a relative style that matches the design.

**RL8 · [DEFAULT] · M0 — One tab bar**

- **Problem:**
  - Two of the three styles are custom overlays. They would have to rebuild what the native bar already gives: minimise on scroll, the search tab, and accessibility.
  - 02-Sharit-s1 already shows an option that the schema forbids.
- **Do:** use only the native glass `TabView`.

**RL9 · [FIX] · M4 — Settings without defined behaviour aren't built**

- **Undefined options:**
  - `tabbar.openOn` = byTime
  - the levels of `bahw.smartPresence`
  - `core.fontScale`, on top of Dynamic Type
  - `core.motion` = calm
- **Do:** hide them until their behaviour is written.

**RL10 · [FIX] · Every milestone — Screens that contradict defaults**

| Screen | Shows | Schema default |
|---|---|---|
| 04-W3-Sana | The day measured «من منتصف الليل» | `core.dayStart` = fajr |
| Several boards | Weeks starting on Sunday | `core.weekStart` = saturday |
| flex/01-Main | «الإشعارات: ٦ في اليوم» | 4 |
| flex/01-Main | The Hijri offset stepper while Umm al-Qura is selected | Stepper shown only for sighting |

- **Do:** the schema default wins. Never copy these values.

---

## Every screen (RU)

**RU1 · [FIX] · M0 lint — Never put "·" next to a digit**

- **Problem:**
  - The Arabic-Indic zero «٠» is a dot, so "·" reads as a zero even with spaces around it.
  - «١٤٤٨ · ٧ أكتوبر» looks like «١٤٤٨ ٠ ٧».
  - In «١٢ صفحة · ١٨ دقيقة», you can't tell 18 minutes from 180.
- **Do:**
  - Next to numbers, use «،» or a line break.
  - Add a unit test that scans every String Catalog value and every formatted string for "·" adjacent to a digit, with or without a space.

**RU2 · [FIX] · Privacy on every surface outside the app**

- **Rule:** by default, the lock screen, widgets, notifications, Live Activities and Spotlight never show money amounts, prayer debts, or diary text.
- **Screenshots that show them are wrong:** mal/13-Z-R18-a80-1 and notes-app/16-outside.

**RU3 · [FIX] · Arabic plurals**

- **Do:**
  - Use String Catalog plural variants (zero, one, two, few, many, other).
  - No hand-built count phrases. For example, «٨ شهرًا» must be «٨ أشهر».

**RU4 · [FIX] · Tone**

- **Do:**
  - Use فصحى قريبة everywhere.
  - No dialect in UI copy.
  - No exclamation marks, no emoji, none of the banned words (§2).

**RU5 · [FIX] · The colour of failure**

- **Do:** no red for failure. The only exception is each room's defined clay tokens.

**RU6 · [DEFAULT] · Dark mode and snapshots**

- **Problem:** only 7 of the 189 canonical screens are dark.
- **Do:**
  - Build dark mode from the design tokens.
  - Keep reference snapshots in both modes only for the shared components and each room's home screen.
