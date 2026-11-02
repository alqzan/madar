11 · Data model (SwiftData, CloudKit-compatible)

CloudKit rules: no unique constraints, every stored property has an inline default (or is optional), relationships are optional (Madar uses optional UUID foreign keys, not @Relationship), deletes are soft (deletedAt tombstones that sync and are kept). Enums are stored as String raw values. Avoid dictionaries in models (use rows or a versioned Data blob); arrays of primitives are allowed but never used in #Predicate. Quran text, word maps, line maps and page fonts are bundled read-only resources, not SwiftData. Machine-readable source of truth: data-dictionary.json (types, units, ranges, optional/default, owner room, natural key, FKs, delete policy, configuration, merge rule, snapshots, commands) — generated from the same source as the listing below.

Common fields (every @Model)

var id: UUID = UUID() // seeded/singleton rows: UUIDv5(seedNS, "<Model>:<slug>"), seedNS = 2103b223-aa33-4c73-bab6-b2adaed8603e
var createdAt: Date = Date()
var updatedAt: Date = Date() // every write: max(now, previous updatedAt + 1 ms) — an edit always supersedes what it edited
var deletedAt: Date? = nil // tombstone; rows are never hard-deleted (Media drops its blob, keeps the row)
var writerID: String = "" // install id of the last writer (DeviceSetting sys.writerID) — deterministic tie-break
var mergedInto: UUID? = nil // alias: set on a reconciliation loser = winner id

These six are implied on every model in the listing and never redeclared (Media no longer repeats createdAt/deletedAt). Foreign keys are UUID?, never defaulted to a random UUID, and are always resolved through mergedInto. Seeded rows (reserve and surplus envelopes, default categories, the «المتفق عليه» preset, ZakatProfile) use deterministic ids so two devices that seed offline produce the same logical row.

Units and validation

KindStored asValidation on write (reject)

MoneyInt in the minor unit of its currency, suffix Minor, with an ISO 4217 currency (home = core.currency = "SAR"); the exponent comes from the bundled currency-minor-units.json (SAR/USD 2, JPY 0, KWD/BHD/OMR 3; pinned in provenance.json). A foreign Transaction also stores homeAmountMinor frozen at write.0 … 10¹³; sign never stored (direction from kind) except fields marked signed (carryAdjustMinor, envelope balance); currency ∈ Locale.Currency.isoCurrencies

Percent / rateInt basis points, suffix Bp (1% = 100)0 … 10 000 (APR 0 … 100 000)

FX rateDecimal stored as a canonical String (ASCII digits, "." separator) = home units per 1 foreign unit (Trip.fxRateToHome, Transaction.rateAtTime); never Doubleparses as Decimal, > 0, ≤ 12 fraction digits

DurationInt seconds, suffix S; settings keep their named unit (…Min, …Days, …Km)≥ 0

Habit quantitiesInt in HabitPolicy.unit (count label, minutes, pages, steps, exerciseMinutes)target > 0 unless once; 0 < minimum ≤ target

Instant + zoneDate (absolute) + tzID (IANA) wherever the local day mattersTimeZone(identifier:) != nil

Day / period keys"yyyy-MM-dd" ASCII Gregorian; week = dayKey of the week start; month "g:yyyy-MM" | "h:yyyy-MM"; year "g:yyyy" | "h:yyyy"; Hijri date "h:yyyy-MM-dd"pattern + real calendar date

Clock time (settings)"HH:mm" 24-hour ASCII00:00 … 23:59

Placelat/lon Double degrees; country ISO 3166-1 alpha-2lat −90…90, lon −180…180; “unknown” = optional nil, never (0, 0)

QuranayahId 1…6236, page 1…604, wordIndex 0-based in the bundled word map (nil = whole ayah)fromAyah ≤ toAyah; wordIndex < words(ayahId); grade ∈ mastered|good|needs; plan amount > 0

Book positionlocatorJSON (source of truth); currentPage is a display cache; progression Double 0…11 ≤ currentPage ≤ pages; fromPage ≤ toPage; progression only moves forward within a session

Enum stringsraw values listed in the dictionarymust be listed and not availability: v2

Listsarrays of ids/raw valuesunique; items from the allowed set; maxItems / permutation per schema contract

JSON blobs (…JSON: Data)a Codable type with field vstrict decode; unknown keys rejected

Texttrimmed Stringnames ≤ 80, bank message ≤ 2 000, diary line from a command ≤ 2 000 characters

Null vs zero: nil = not set/unknown, 0 = a real zero (e.g. limitMinor = nil no known limit, 0 a zero limit). On read, an unknown enum/version or invalid value falls back to the schema default (settings) or a read-only placeholder (blobs) and is logged once — never coerced into a plausible value and never overwritten silently. Composite setting values (place, offsets, daily allowance, reader, lists, layouts) carry their contract in settings-schema.json.

Day keys and event provenance

Write: dayKey = MadarDay.key(eventAt, zone, policy) where zone = the active place at eventAt (the trip's tzID if eventAt ∈ [trip.start, trip.end), else home) and policy = core.dayStart at write time. Dated events store eventAt, tzID and dayPolicy ("<rule>@<version>", e.g. fajr@1): PrayerLog, HifzSession (its instant field is endedAt), Entry, Transaction, HabitLog, QiyamNight, ReadingSession, MarginNote. Day containers (DayPage, Niyya, QuranDayState, QuranAllotment) are keyed by dayKey only.

prayerDay ≠ MadarDay: PrayerLog.dayKey is the civil date of the prayer's own adhan time at the place (dayPolicy = prayerDay@1), independent of core.dayStart.

Never recomputed on a policy change, time-zone change, travel, sync, restore or migration. Changing core.dayStart affects new events only; past days do not move.

Explicit edit: only when the user edits an event's time/date is its dayKey recomputed — with the row's own tzID (unless the user also changes the place) and the current policy, re-stamping dayPolicy. Both the old and new day are invalidated. If the new key collides with a natural key (e.g. HabitLog for that period exists) the edit is refused with «هذه الفترة مسجّلة — عدّلها هناك».

Travel across zones / the date line: dayKeys are labels. A date lived twice (westward) collects events under one key, and each prayer of it is due once (the first occurrence); a skipped date (eastward/date line) has no due prayers and is never marked missed. Due prayers are computed from prayer times that actually occurred along the place timeline.

DST: day boundaries are computed per date with Calendar in tzID; never “start + 24 h”.

Migration/import: a legacy dayKey is copied verbatim with dayPolicy = legacy@0; if missing it is computed once from the record's time in the home zone.

Acceptance (M0, MadarDay tests): events at Fajr−1 min/+1 min, Maghrib±1, 23:59/00:01 under each policy; a DST transition day; Riyadh→London and Riyadh→Tokyo trips; a date-line crossing; switching dayStart at 01:00 — no past event changes key, no prayer is due twice, no skipped day becomes missed.

Natural keys and reconciliation

Unique constraints are unavailable under CloudKit, so the logical identity of a row is enforced in code. The logical key of a row is its natural key below, or its id for id-only models (two records can share an id after a restore on two devices or offline seeding). Conditional keys (“when non-nil”) apply only to rows that have the value; a model with two keys (Entry) groups rows that share either key. Device-only keys are local and never merged across devices.

ModelNatural keyModelNatural key

Setting(key)LayoutState(room)

ImportLink(source, sourceModel, sourceID)PrayerLog(dayKey, prayer)

QadaItem(prayer, originalDayKey)QiyamNight(nightKey)

HifzPlan(version)HifzSession(commitID) when non-nil; otherwise id

PageGrade(sessionID, page)MistakeSpot(ayahId, wordIndex) — nil is its own value

QuranDayState(dayKey)QuranAllotment(origin, originDayKey, dayKey, kind)

DayPage(dayKey)Niyya(dayKey, order)

Entry(source, sourceID) when sourceID ≠ nil; (pinnedEventKind, pinnedEventID) when pinned; otherwise idHiddenAutoLine(eventKind, eventID)

Media(sourceID) when non-nil; otherwise idStatement(cardID, closeDay(closeDate))

Allocation(idempotencyKey) when non-empty; otherwise idBankMessage(fingerprint, occurrence)

Cycle(startDay(start))CyclePolicy(cycleID, effectiveFromDayKey)

Envelope(role) for reserve and surplus onlyInstallmentItem(obligationID, seq)

CategoryLimit(categoryID)ZakatProfilesingleton (fixed id)

Book(sourceGoodreadsID) when non-nil; otherwise idHadithProgress(collectionID, number)

UserWord(language, normalized(word)) — Arabic normalization of §6 searchHabitPolicy(habitID, effectiveFrom)

HabitLog(habitID, periodKey)DeviceSetting (device)(key)

NotificationLedger (device)(requestID)CommandReceipt (device)(commandID)

PageSchedule (device)(page)

Algorithm RowMerger.run() (named so to avoid confusion with the money Reconciliation model) — runs only in the app process on one ModelActor: on launch, after each processed batch of remote history, and after restore/merge/migration. Intents never reconcile; they upsert by natural key through aliases.

For each synced model in data-dictionary.json › reconcileOrder (parents before children), load all rows with mergedInto == nil — tombstones included — and group them by logical key (union of the applicable keys).

In each group of ≥ 2, order by updatedAt desc, then writerID desc, then id.uuidString desc. The first row is the winner, whether live or tombstoned: a newer tombstone beats older live duplicates (a stale offline copy cannot resurrect a deleted row); a live row edited after the delete wins (later intent).

Every loser gets mergedInto = winner.id and deletedAt = deletedAt ?? winner.updatedAt; its updatedAt is not bumped. Rows with mergedInto are never winners, never shown and never revived.

Apply the listed field exceptions (below) onto the winner.

FK remap: for every FK field that targets this model (from the dictionary), rewrite loser.id → winner.id in children. A remap may create child duplicates (e.g. two PageGrade for one page), which the child's own pass resolves; if a remap touches a model already processed in this run (FK cycles such as InstallmentItem.paidTransactionID), that model is processed again — at most 3 passes. Merged ImportLinks also merge their targets.

Invariant repairs: one open Trip (keep the latest start, close the others with end = winner.start); one active HifzPlan (greatest live version); one live reserve and one live surplus Envelope; one active RecoveryPlan (keep the latest startDayKey, cancel the others).

Recompute derived caches touched by the run (HifzPlan.frontierAyah, Envelope.balanceMinor = Σ Allocation, the Cycle fields cached from the current CyclePolicy), then one save(); the device-local PageSchedule is rebuilt afterwards. On any error the context is rolled back and nothing is written; the next run starts over. Then regenerate affected snapshots and post bus invalidations.

Restore is explicit only: “restore” sets the winner's deletedAt = nil and updatedAt = now. Nothing else revives a tombstone. Automatic dedupe has no undo (it only removes logical duplicates); user-triggered merges (restore-merge, migration) take an automatic backup first.

Conflict policy: row-level last-writer-wins by updatedAt, tie-break by writerID (lexicographic) then id. Field-level merge only where listed: HabitLog.value = max of live duplicates; Account.(balanceMinor, balanceAt) taken together from the latest balanceAt; HadithProgress.understood = OR, layersOpened = union, understoodDayKey and readAt = earliest. Settings never conflict as a blob: one row per key. Money events (Transaction, CashbackEntry) are id-only and never merged by content — duplicates are prevented upstream by BankMessage (fingerprint, occurrence), Allocation.idempotencyKey and ImportLink. Limit (stated, not hidden): two devices editing the same record are resolved by the CloudKit mirror, outside Madar's code. M0 includes a characterization test (status edited on A, heart on B, both offline) whose observed result is recorded in the decisions log; for a single user this is accepted.

Acceptance (M0): (1) A deletes a row; B, offline, holds an older duplicate with another UUID → after both sync, it stays deleted on both; only explicit restore revives it. (2) Equal updatedAt → the same winner on both devices. (3) Two copies of a HifzSession/Book/Account merged → no grade, highlight or transaction lost; children point to the winner. (4) Running the reconciler twice → the second run writes nothing. (5) Crash during a run → no partial state. (6) Device B with a clock 1 h behind edits a row last written by A → B's edit wins (monotonic updatedAt). (7) Two devices seed offline → one reserve, one surplus, one ZakatProfile, one set of default categories. (8) The same Day One entry imported on two devices → one Entry (conditional key).

Single owners

DecisionOnly ownerRemoved duplicate / rule

Hifz plan (direction, unit, amount, rhythm, days, miss policy)HifzPlan (active = greatest live version)settings quran.plan, quran.missPolicy removed. A plan change inserts version n+1 (old gets supersededAt); sessions keep their planID, so history survives. frontierAyah is a cache of coverage (§7.4).

Quran rest day / hifz daysquran.restDayhifz days = the 7 weekdays minus the rest day; HifzPlan stores no days.

Review schedule per pagederived from HifzSession + PageGrade + plan rhythmPageSchedule is a device-local cache.

Mistake spot summaryMistakeEvent (+ legacy base on MistakeSpot)count/streak/closed are derived.

Habit rules per periodHabitPolicy (effectiveFrom) + HabitPauseHabit holds identity only.

Envelope balanceΣ AllocationEnvelope.balanceMinor is a cache.

Book positionBook.locatorJSONcurrentPage is a display cache.

«ذاك اليوم» / «أيامك» visibilityLayoutState(notes).hiddennotes.showThatDay, notes.showDays removed.

Money lines in the diarynotes.autoLines.mal (shown in both customize pages) ∧ Transaction.showInDiary per rowmal.expenseInDiary removed.

Habit reminderHabit.reminderbahw.reminder is only the default for new habits.

Active tripthe single open Tripat most one; repaired by reconciliation.

Reserve / surplusthe seeded Envelope rows (fixed ids)one each; role singletons.

Zakat profileZakatProfile (fixed id)singleton.

Layout of any roomLayoutStateschema layout entries are its defaults only.

Presets (§6): PresetPayload v1 = {v, settings: {key: value}, layouts: {room: LayoutPayload}}, where settings holds only keys with "preset": true. Apply = validate → diff preview (unknown keys from a newer version are ignored and listed) → one save() across Setting, DeviceSetting (this device only) and LayoutState → the previous values are kept in a CommandReceipt so “undo last preset” works until the next apply. Locks, sync, backup, notifications, data rules and system permissions are never in a preset. Acceptance: a preset made on iPad changes on iPhone exactly the listed keys and layouts, in order, and leaves core.faceIDLock, core.iCloudSync, core.backup and every notification key unchanged.

Models (61: 55 synced + 6 device-only)

// ---------- Core ----------
@Model Setting { key = ""; valueJSON: Data = Data() }
// A row exists only after the user changes the key; no row = schema default. One row per key.
@Model LayoutState { room = "" /*bahw|salah|quran|mal|notes|mihbara*/; blocksJSON: Data = Data() }
@Model Preset { name = ""; payloadJSON: Data = Data(); locked = false }
@Model Trip { city = ""; country = ""; currency: String?; lat = 0.0; lon = 0.0; tzID = ""; fxRateToHome: String?;
fxSetAt: Date?; mode = "auto" /*auto|manual*/; dismissed = false /*"not travelling"*/; start: Date?;
end: Date?; homeKm: Double? }
@Model UpcomingDay { title = ""; calendar = "hijri" /*hijri|greg*/; year: Int? /*one-off only; nil when repeating*/;
month = 1; day = 1; repeats = "none" /*none|yearly|monthly*/; countFromDayKey = "" }
// stores the RULE; next occurrence derived (p5); Hijri day 30 in a 29-day month → 29; Feb 29 → Feb 28
@Model ImportBatch { kind = "dayOne" /*dayOne|bankBulk|goodreads|migration*/; fileName = ""; fileHash = "";
startedAt = Date(); finishedAt: Date?; status = "running" /*running|done|partial|failed|cancelled*/;
summaryJSON: Data = Data() /*counts, missing media, duplicates*/;
optionsJSON: Data = Data() /*e.g. Goodreads cutoffYear*/ }
// one provenance record per imported file (Day One, bank bulk paste, Goodreads, migration)
@Model ImportLink { source = "myDream" /*myDream*/; sourceModel = ""; sourceID = ""; targetModel = ""; targetID: UUID?;
importBatchID: UUID?; unmappedJSON: Data?; importedAt = Date() }
// migration (myDream) key for every model; Day One/Goodreads use native source fields

// ---------- Prayer ----------
@Model PrayerLog { dayKey = ""; prayer = "fajr" /*fajr|dhuhr|asr|maghrib|isha — Jumu'ah is derived from the date*/;
status = "jamaah" /*jamaah|alone|qada|missed|unrecordedHistory — qada = prayed after its time, always with a made-up QadaItem of the same key; unrecordedHistory = import OR the explicit «لم أسجّل هذه الفترة» action only*/;
heart: String? /*distracted|present|khashi — skip («أمرُّ») = nil*/; eventAt = Date(); tzID = "";
dayPolicy = ""; loggedAt: Date?;
source = "app" /*app|notification|widget|siri|control|import|aging — aging = written by AgePendingPrayers*/;
tripID: UUID?;
pairID: UUID? /*exactly 2 non-deleted logs of an allowed pair (dhuhr+asr | maghrib+isha) on the same prayer day; a lone pairID is cleared after import*/;
shortened: Bool? /*true only for dhuhr|asr|isha; Friday-while-travelling «الظهر قصرًا» = dhuhr + shortened*/ }
// pending/future are DERIVED: no row + prayer time reached (within pendingDays) = pending; not yet reached = future
@Model QadaItem { prayer = "fajr" /*fajr|dhuhr|asr|maghrib|isha*/; originalDayKey = ""; madeUpAt: Date? }
@Model QiyamNight { nightKey = ""; rakaat = 0; witr = false; quranSessionID: UUID?; tzID = ""; dayPolicy = "" }

// ---------- Quran ----------
@Model HifzPlan { version = 1; direction = "forward" /*forward|reverse — reverse = v2, hidden in v1*/; startAyah = 1;
unit = "page" /*ayah|quarter|half|page — identical to legacy HifzUnit raw values; quarter = quarter PAGE*/;
amount = 1.0; rhythm = "balanced" /*light|balanced|intense*/;
missPolicy = "ask" /*ask|spread|double|skip*/;
frontierAyah: Int? /*cache = first ayah ≥ startAyah not in coverage; legacy frontierId meaning unchanged*/;
activeFrom = Date(); supersededAt: Date? }
// The ONLY owner of plan and missPolicy (settings quran.plan / quran.missPolicy removed). Rest day stays in quran.restDay.
@Model HifzSession { planID: UUID?; dayKey = ""; endedAt = Date(); tzID = ""; dayPolicy = "";
kind = "hifz" /*hifz|review|free|qiyam|drill*/; fromAyah = 1; toAyah = 1; pages: [Int] = [];
mistakes = 0 /*new sessions: count of MistakeEvent(kind = mistake); imported: legacy count*/;
method = "coach" /*coach|completeAyah|gradual|next|link|continuous*/; source = "app" /*app|import*/;
commitID: UUID? /*= SessionDraft id; a second commit with the same id is a no-op*/;
nightKey: String? /*kind = qiyam only*/ }
@Model PageGrade { sessionID: UUID?; page = 1; grade = "good" /*mastered|good|needs*/;
role = "regular" /*regular|test — test = periodic old-memorization test*/ }
// rows with nil or deleted session are ignored by every computation
@Model MistakeSpot { ayahId = 1; wordIndex: Int? /*nil = whole ayah*/; legacyHits = 0; legacyLastDrillAt: Date?;
legacyStreak = 0 }
// summary (count, streak, closed) is DERIVED from MistakeEvent + legacy base
@Model MistakeEvent { ayahId = 1; wordIndex: Int?; sessionID: UUID?; at = Date();
kind = "mistake" /*mistake|drillPass|drillFail*/ }
// tombstoned/restored with its session
@Model QuranDayState { dayKey = ""; hifzLevel: String? /*simple|medium|deep|max*/;
reviewLevel: String? /*simple|medium|deep|max*/; forceNewHifz = false; testPages: [Int] = [] }
@Model QuranAllotment { dayKey = ""; kind = "hifzExtra" /*hifzExtra|reviewExtra*/; amount = 0.0 /*plan units, hifzExtra*/;
pages: [Int] = [] /*reviewExtra*/; origin = "missPolicy" /*missPolicy|raise*/; originDayKey = "" }
// a day target, not a debt (not carried over)
@Model RecoveryPlan { startDayKey = ""; days = 7 /*5|7|14*/; pages: [Int] = []; cancelledAt: Date? }

// ---------- Diary (المذكرات) ----------
@Model DayPage { dayKey = ""; questionAnswer: String?; photoMediaID: UUID?; origin = "native" /*native|dayOne*/;
hiddenFromMemories = false }
@Model Niyya { dayKey = ""; order = 0; text = ""; result: String? /*done|partial|notEasy — nil = unanswered*/ }
@Model Entry { dayKey = ""; eventAt = Date(); tzID = ""; dayPolicy = ""; text = "";
textFormat = "plain" /*plain|markdown*/;
ink = "normal" /*normal|late|ghad — "late" ink covers late-written*/; mediaID: UUID? /*voice note*/;
attachmentMediaIDs: [UUID] = []; projectID: UUID?; place: String?; lat: Double?; lon: Double?;
source = "native" /*native|dayOne|migration|autoPinned*/; sourceID: String?; sourceJournal: String?;
sourceTimeZone: String?; sourceModifiedAt: Date?; sourceHash: String?; importBatchID: UUID?;
pinnedEventKind: String?; pinnedEventID: UUID? /*pinned auto line = historical text*/ }
@Model HiddenAutoLine { eventKind = "";
eventID: UUID? /*required in practice; nil rows are ignored and tombstoned by the merge*/; dayKey = "" }
// a display preference, never deletes the event
@Model MarginNote { targetDayKey = ""; targetEntryID: UUID?; text = ""; writtenAt = Date(); writtenDayKey = ""; tzID = "";
dayPolicy = "" }
@Model Letter { text = ""; openAt: Date?;
triggerKind = "date" /*date|hijriDate|tripStart|tripEnd|khatma|bookFinished|projectFinished|ramadanStart*/;
triggerTargetID: UUID?; triggerValue: String? /*e.g. "1448-09-01"*/;
state = "sealed" /*sealed|eligible|opened|orphaned — never moves backwards*/; eligibleAt: Date?;
openedAt: Date? }
// sealed text is excluded from search/Spotlight/widgets/notifications
@Model Project { name = ""; intention = ""; keyword: String?; finishedAt: Date?; reflection: String? }
@Model Media { kind = "photo" /*photo|audio|video|doc*/; contentType = "";
data: Data? /*@Attribute(.externalStorage)*/; sizeBytes = 0; sha256 = ""; durationS: Int?;
sourceID: String? /*Day One media id/md5*/;
state = "ok" /*ok|missing — a missing file is recorded, never invented*/; importBatchID: UUID? }
// common fields only once (createdAt/deletedAt are NOT redeclared)

// ---------- Money ----------
@Model Account { name = ""; bank = ""; kind = "current" /*current|savings|cash — cash = wallet*/; ownerName: String?;
ownership = "mine" /*mine|notMine*/; zakatInclude = true; currency = "SAR"; balanceMinor = 0;
balanceAt: Date?; parentID: UUID?; senderIDs: [String] = [] /*bank SMS sender ids*/ }
@Model Card { name = ""; bank = ""; last4 = ""; aliases: [String] = []; holderName: String?; network = "";
limitMinor: Int?; cashbackBp: Int?; aprBp: Int?; accountID: UUID?;
fieldSourcesJSON: Data = Data() /*per-field source: message / inferred / entered*/ }
// identity = (bank, last4) + aliases
@Model Statement { cardID: UUID?; closeDate = Date(); closeDateSource = "estimated" /*estimated|message|entered*/;
periodStart: Date?; dueDate: Date?; statementMinor = 0; minimumDueMinor = 0; messageID: UUID? }
// a second statement within 5 days of an estimated close → possible-duplicate review, not a second row
@Model CashbackEntry { cardID: UUID?; eventAt = Date(); amountMinor = 0; kind = "earned" /*earned|redeemed*/;
transactionID: UUID? }
@Model MoneyTransaction { dayKey = ""; eventAt = Date(); tzID = ""; dayPolicy = "";
kind = "expense" /*expense|income|salary|cardPayment|transfer|refund|cashback|withdrawal|repayment|adjustment*/;
amountMinor = 0 /*always positive; kind gives the direction*/; currency = "SAR"; homeAmountMinor = 0;
homeCurrency = "SAR"; rateAtTime: String? /*nil when same currency*/;
rateSource: String? /*message|trip|manual*/; merchant: String?; counterparty: String?;
categoryID: UUID?; categorySource: String? /*manual|learned|rule; prior rows without provenance nil*/; method = "cash" /*cash|card|bnpl|transfer*/; fromAccountID: UUID?;
toAccountID: UUID?; cardID: UUID?;
relatedTransactionID: UUID? /*refund → original, adjustment → reconciliation*/; obligationID: UUID?;
installmentID: UUID?; cycleID: UUID?; ignoredFromBudget = false; source = "bank" /*bank|manual*/;
messageID: UUID?; tripID: UUID?; showInDiary = true;
reviewState = "ok" /*ok|needsLook|possibleDuplicate*/ }
// two legs in one row; envelope/daily effects live in Allocation
@Model Allocation { transactionID: UUID?; groupID: UUID?; target = "daily" /*daily|envelope|reserve|surplus|goal*/;
targetID: UUID?; amountMinor = 0; kind = "spend" /*spend|fund|refund|offset|repay|adjust*/;
cycleID: UUID?; idempotencyKey = "" }
// Envelope.balanceMinor = Σ allocations (derived cache)
@Model Reconciliation { accountID: UUID?; cardID: UUID?; at = Date(); expectedMinor = 0; observedMinor = 0; deltaMinor = 0;
resolution = "adjust" /*adjust|unrecordedSpend|leave*/; adjustmentTransactionID: UUID?;
beforeJSON: Data = Data(); note: String? }
// balance reconciliation record (money); unrelated to the row merge in §11; undo restores both
@Model BankMessage { sender = ""; text = ""; normalizedText = ""; receivedAt = Date();
receivedAtSource = "device" /*device|parsedFromText|batch*/;
fingerprint = "" /*SHA-256 of sender + normalizedText + receivedAt rounded to the minute*/;
occurrence = 1; channel = "shortcut" /*shortcut|bulk|migration|manual*/; importBatchID: UUID?;
kind = ""; parsedJSON: Data?; parseVersion = 1;
status = "ok" /*ok|needsLook|ignored|possibleDuplicate*/ }
@Model Cycle { start = Date(); end: Date?; expectedEnd: Date?; closedAt: Date?; salaryTransactionID: UUID?;
incomeMinor = 0; mode = "fixed" /*fixed|percent*/; percentBp: Int?; dailyAllowanceMinor = 0;
carryAdjustMinor = 0; closedReportJSON: Data?; reportVersion = 0 }
@Model CyclePolicy { cycleID: UUID?; effectiveFromDayKey = ""; mode = "fixed" /*fixed|percent*/; allowanceMinor = 0;
percentBp: Int?; dailyRateMinor = 0; lastDayRemainderMinor = 0 }
@Model Envelope { name = ""; role = "general" /*general|surplus|reserve|goal|trip*/;
balanceMinor = 0 /*cache = Σ Allocation*/; targetMinor: Int?; due: Date? }
@Model EnvelopePlan { envelopeID: UUID?; kind = "fund" /*fund|repay*/; source = "salary" /*salary|surplus|reserve*/;
perPaycheckMinor = 0; untilDate: Date? }
@Model Obligation { kind = "bill" /*loan|bill|installment*/; name = ""; provider: String?; amountMinor = 0; totalMinor = 0;
currency = "SAR"; dueDay: Int?; remainingCount: Int?; purchaseTransactionID: UUID?;
sourceMessageID: UUID? /*pinned from a bank message*/ }
@Model InstallmentItem { obligationID: UUID?; seq = 1; dueDate = Date(); amountMinor = 0; paidMinor = 0;
paidTransactionID: UUID?; paidAt: Date? }
@Model Category { name = ""; icon = ""; color = ""; order = 0 }
@Model CategoryLimit { categoryID: UUID?; mode = "fixed" /*none|fixed|percent*/; limitMinor = 0; percentBp: Int?;
base = "income" /*income|allowance*/;
alert80CycleID: UUID? /*cycle in which the 80% alert already fired*/ }
@Model MerchantRule { pattern = ""; categoryID: UUID?; ignore = false }
@Model ZakatProfile { hawlStartHijri = "" /*e.g. "h:1447-09-01"*/; goldPricePerGramMinor: Int? /*entered manually in v1*/;
goldPriceSetAt: Date?; nisabMg = 85000; debtsPolicy = "unset" /*unset|none|dueNow|allOwed*/;
otherAssetsMinor = 0; lastPaidAt: Date? }

// ---------- Mihbara ----------
@Model Book { title = ""; author = ""; editor: String?; edition: String?;
kind = "paper" /*paper|ebook|turath|file — turath = reserved v2, not written in v1*/;
format: String? /*epub|pdf|pdfScanned|txt|html*/; shelf = "want" /*reading|want|finished|old*/;
pages: Int?; locatorJSON: Data?;
currentPage: Int? /*paper-page display cache; 1 ≤ currentPage ≤ pages*/; tocJSON: Data?;
language = "ar"; mediaID: UUID?; fileHash: String?; isbn13: String?; sourceGoodreadsID: String?;
importBatchID: UUID?; turathID: Int? /*reserved v2*/; finishedAt: Date?; rating: Int?; review: String?;
readCount = 0 }
@Model ReadingSession { bookID: UUID?; start = Date(); end: Date?; activeSeconds = 0; fromPage = 0; toPage = 0;
startLocatorJSON: Data?; endLocatorJSON: Data?; startProgression = 0.0; endProgression = 0.0;
pagesCounted = 0; source = "reader" /*reader|timer|manual*/; dayKey = ""; tzID = ""; dayPolicy = "" }
// progress counts forward only
@Model Highlight { bookID: UUID?; locatorJSON: Data = Data(); pageLabel: String?; color = ""; note: String? }
@Model NotebookNote { text = ""; link = "general" /*page|bookStart|bookEnd|hadith|idea|general|fromDiary*/; targetID: UUID?;
page: Int?; locatorJSON: Data?; isPrivate = false }
// fromDiary stores targetID = Entry id and no copied text; it inherits the diary lock
@Model HadithProgress { collectionID = ""; number = 0; editionID = ""; readAt: Date?; understood = false;
understoodDayKey: String?; returnTo = false; layersOpened: [String] = [] }
@Model UserWord { word = ""; language = "ar" /*ar|en*/; meaning: String?;
meaningSource = "none" /*none|user|translation*/; bookID: UUID?; bookTitle = ""; locatorJSON: Data?;
context = ""; savedAt = Date() }
// «كلماتي» survives sync and book deletion

// ---------- Habits (Lobby) ----------
@Model Habit { name = ""; icon = ""; color = ""; kind = "custom" /*custom|linked*/;
linkedSource: String? /*jamaah|review|reading|hadith|diaryLine|withinDay|walking*/;
reminder = "dot" /*dot|push|none*/; homeOnly = false; startDate = Date(); order = 0;
archivedAt: Date? /*soft delete; restorable*/ }
// identity only; rules live in HabitPolicy
@Model HabitPolicy { habitID: UUID?; effectiveFrom = "" /*applies from the period containing it*/;
frequency = "daily" /*daily|weekly|monthly|yearly*/; weekdays: [String]?; monthDays: [Int]?;
monthCalendar: String? /*hijri|gregorian — governs monthly AND yearly*/; yearMonth: Int?; yearDay: Int?;
measure = "once" /*once|count|duration|health*/;
unit: String? /*count: free label; duration: "minutes"; reading: "minutes"|"pages"; walking: "steps"|"exerciseMinutes"*/;
target: Int?; minimum: Int?; restWeekdays: [String]?;
windowAnchor: String? /*fajr|dhuhr|asr|maghrib|isha — nil = clock*/; windowStartMin: Int?;
windowEndMin: Int? }
// editing today never reinterprets past periods
@Model HabitPause { habitID: UUID?; fromDayKey = ""; toDayKey: String? /*nil = open*/;
reason = "freeze" /*freeze|trip|vacation*/; tripID: UUID? }
// unfreeze sets toDayKey, never deletes; homeOnly-during-trip pauses are derived from Trip
@Model HabitLog { habitID: UUID?; periodKey = ""; value = 0; eventAt = Date(); tzID = ""; dayPolicy = "" }
@Model WidgetConfig { name = "";
familyID: String? /*small|medium|large|extraLargePortrait|accessoryCircular|accessoryRectangular|accessoryInline — app-level id, maker preview only; the OS chooses the family of a placed widget*/;
items: [String] = [] /*priority-ordered; each family shows the first N by its capacity (§9)*/;
styleJSON: Data = Data() /*"family" key = visual identity (manuscript|glass|ink), not WidgetFamily; other keys: font, numerals, density, color, showArt, smartBundle, hideWhenEmpty, hideMoney, iftarCountdown, interactive*/ }

// ---------- Device-only (separate ModelConfiguration "deviceOnly", cloudKitDatabase: .none — never synced, never backed up) ----------
@Model DeviceSetting { key = ""; valueJSON: Data = Data() }
// same SettingsStore facade as Setting
@Model NotificationLedger{ dayKey = ""; requestID = ""; room = ""; kind = ""; requestClass = "" /*prayer|room|digest|nudge*/;
scheduledFor = Date();
state = "submitted" /*submitted|cancelled|dropped|digested|observed — budget counts submitted*/;
reason: String? /*budget|quiet|cap|off — for dropped*/ }
@Model CommandReceipt { commandID: UUID?; name = ""; payloadHash = "";
source = "app" /*app|widget|control|siri|shortcut|notification|spotlight|system*/; issuedAt = Date();
status = "applied" /*applied|duplicate|rejected|needsUnlock|needsApp*/; undoJSON: Data?;
expiresAt = Date() }
// I02 idempotency + undo
@Model PageSchedule { page = 1; memorizedAt: Date?; stage = 0; ease = 1.0; nextDue: String?; lastReviewedAt: Date?;
lastGrade: String? /*mastered|good|needs*/; scheduleVersion = 0 }
@Model SessionDraft { kind = "hifz" /*hifz|review|free|qiyam|drill*/; dayKey = ""; startedAt = Date();
portionJSON: Data = Data() /*from/to ayah, pages, testPages*/;
cursorJSON: Data = Data() /*page, ayahId, coach stage*/;
provisionalJSON: Data = Data() /*grades, mistakes*/ }
// id = draftID = HifzSession.commitID
@Model ProcessingJob { bookID: UUID?; kind = "ocr" /*ocr|convert*/;
state = "queued" /*queued|running|paused|done|failed|cancelled*/; totalPages = 0; donePages = 0;
checkpoint = 0; engine = ""; error: String? }
// resumable OCR

Backup and restore (contract)

File Madar-yyyy-MM-dd.madarbackup: a plaintext header {magic: "MADARBK", formatVersion: 1, appVersion, storeSchemaVersion, createdAt, kdf: {alg: "PBKDF2-HMAC-SHA256", iterations: 600000, salt: 16 bytes}, cipher: "AES-256-GCM", chunkSize: 1 MiB, chunkCount}, then the body as AES-GCM chunks (CryptoKit AES.GCM; nonce = 4-byte random file prefix + 8-byte chunk counter; AAD = header bytes + chunk index + final flag), so truncation, reordering and tampering fail authentication. PBKDF2 comes from CommonCrypto (CCKeyDerivationPBKDF); CryptoKit has no password KDF.

Plaintext = an Apple Archive (AppleArchive framework, no third-party zip) with manifest.json {formatVersion, storeSchemaVersion, createdAt, counts: {Model: n}, files: [{path, bytes, sha256}]}, data/<Model>.jsonl (every row of the 55 synced models, tombstones and aliases included) and media/<mediaID>. Device-only stores are not backed up: PageSchedule is rebuilt after restore; drafts and processing jobs are discarded.

Key: passphrase chosen at the first backup (≥ 10 characters); the derived key and salt are kept in the Keychain (…ThisDeviceOnly) so scheduled backups run unattended. Losing the passphrase makes backups unreadable — the UI says so once. A new passphrase gets a new salt.

Where and when: iCloud Drive app folder Backups/ (falls back to local Documents with «النسخة على الجهاز فقط»); keep the last 4 automatic plus all manual ones. core.backup weekly/daily is best effort: BGProcessingTask plus a foreground catch-up when the last success is older than the interval; sys.lastBackupAt/sys.lastBackupResult are shown («آخر نسخة ناجحة: …») with «انسخ الآن». Cancelling deletes the partial file and keeps the previous backup. Automatic backups are also taken before restore-replace, a migration, a plan change and an account switch.

Restore never touches the live store until the last step: read header (unknown formatVersion or a storeSchemaVersion newer than the app → refuse) → decrypt into a staging directory (wrong passphrase fails on chunk 0; a missing final chunk or checksum mismatch aborts and deletes staging) → decode and validate every row (§ Units) → older schema versions mapped forward in memory → preview: counts per room vs current, date range, skipped rows. Merge = upsert by id keeping the backup's timestamps, then reconciliation. Replace = automatic backup of the current store, then restored rows upserted with updatedAt = now and current rows absent from the backup tombstoned (the preview warns «سيتغيّر هذا على كل أجهزتك»). One save(); media are staged before it; snapshots fully rebuilt and the history token reset after it.

M0 acceptance (before any room ships): a fixture with ≥ 1 row of every synced model, a tombstone, an alias, a photo and an audio note → export → replace into an empty store → every row equal and every media SHA-256 equal; wrong passphrase, truncated file, one flipped byte, newer storeSchemaVersion, missing media file → rejected with the live store byte-identical; merging the same backup twice → the second merge writes nothing.

Migration from old Madar (My-dream) — one-time tool

Pinned reference: alqzan/My-dream at commit aba0c1b18a3bf3fc070395a40595e939c3b73aa3 (full SHA; see provenance.json). Any later commit is a deliberate change: a provenance diff plus a re-run of the port tests (§7 engine tables, the money bug corpus, this field map). The coding agent must request repo access from the owner; legacy field names below are the ones already cited in this document — everything else is read at that SHA and filled into the map before the room's milestone.

Rules. Input = the old encrypted backup (password from the user) or the sync store; the original file is kept device-local in Imports/ until the user deletes it. The run is one ImportBatch(kind: migration); every imported record gets an ImportLink(source: myDream, sourceModel, sourceID) (legacy id, or SHA-256 of the canonical record JSON when it has none), so re-running the same file adds zero rows. Models with native source fields (Entry, Media) also get source = migration and the same sourceID — one immutable value in two places, never two different keys. Legacy timestamps are kept (createdAt/updatedAt/eventAt), dayKeys copied verbatim (legacy@0), amounts converted to minor units by rounding half away from zero at 2 decimals (values with more decimals are listed). Legacy tombstones import as tombstones. A record that fails validation is skipped and listed — never half-written; each room imports in one transaction. Fields with no home are archived in ImportLink.unmappedJSON, never silently dropped. Preview with counts, skipped records and unmapped field names → “merge” or “replace” (as in Backup).

Legacy (at the pinned SHA)MadarFateNotes / decision

Prayer recordsPrayerLogmovestatus enum mapped 1:1 to jamaah|alone|qada|missed after reading the legacy enum decision-needed (unknown values archived). Unrecorded days before salah.trackingStart → unrecordedHistory (never pending or missed); the user may move trackingStart back up to 30 days before first run so those days become pending instead (P04).

Per-page schedule (src/lib/quran/: INTENSITY, nextInterval, nextEase, applyRating)PageSchedulemovestage, ease, next due, last review, last grade; memorizedAt rebuilt from sessions (cache).

Hifz sessions and reviews (updateHifzSession, updateHifzReview, gradeByPage)HifzSession + PageGrademoveone PageGrade per page grade; legacy deletions (deleteHifzSession tombstones) imported as tombstones; planID = migrated plan v1.

Hifz plan (startHifzPlan, updateHifzPlan, HifzUnit, intensity) and frontierIdHifzPlan v1move / derivevalue-level rules (unit raw values, startAyah conversion, frontierId meaning, coverage gap row, grade mapping) are owned by the §7.4 legacy table: unit raw values copy 1:1; grade1/2/3 → mastered/good/needs (verified against the legacy enum; unknown values excluded and counted in the preview); legacy percentages are not imported (recomputed from coverage); if imported sessions do not reach the legacy frontier, one HifzSession(kind = hifz, source = import) covers the gap. Intensity → rhythm light|balanced|intense.

Mistake drills (recordMistakeDrill, MISTAKE_MASTERY)MistakeSpotmoveper §7.4 «مواضع الخطأ»: whole-ayah legacy spots → wordIndex = nil; legacy hits/last drill/streak → MistakeSpot.legacy*; a word position that cannot be matched to the bundled word map is archived, not guessed.

Recitation khatma—excluderemoved from scope by owner decision (§3).

Diary entries, photos, voiceEntry, DayPage, Mediamoveentry time → eventAt; media SHA-256 computed; a late-written flag (if present) → ink = late.

Diary tags / mood (if present)—archivedecision-needed; default: archived, not shown (same rule as Day One).

Day One pages already in the old appDayPage(origin: dayOne), Entrymovethrough the Day One importer contract (§7.3).

AccountsAccountmovebalance → balanceMinor + balanceAt.

Envelopes and their funding (carryAdjust, fundingPerDay)Envelope, EnvelopePlan, Cycle.carryAdjustMinormove / deriveroles mapped to reserve|surplus|goal|general (one reserve, one surplus); legacy due date was never saved → nil. The 14 legacy bugs (§7.5) are not ported.

TransactionsTransactionmovekind mapped to the v1 enum; unknown kinds → skipped and listed.

Raw bank messagesBankMessage (+ Statement, Card, Obligation via the parser)move + re-parsethe parser only fills nil fields; a migrated transaction/statement never changes a confirmed value — differences go to «راجع» with a preview.

BooksBook (+ ReadingSession if a reading log exists)moveshelf mapped to reading|want|finished|old.

Habits and their logsHabit + one HabitPolicy(effectiveFrom = startDate), HabitPause, HabitLogmovelegacy freeze → HabitPause; periodKey copied if already in Madar format, else computed once from the stored date in the home zone.

SettingsSettingmove / excludeonly keys with an exact equivalent; the rest listed in the preview.

Any other legacy entity or fieldImportLink.unmappedJSONarchivelisted by name and count in the preview.

Acceptance (per room milestone): a legacy fixture where every field of the room appears → the map gives each field a fate (CI check: fixture field set = mapped ∪ archived ∪ excluded); importing it twice → zero additions; totals, dates, media hashes, mistake spots and sessions equal before/after; a re-parse never changes a confirmed amount without preview.

Old unrecorded prayers (default applied, open in §15): the app must not issue rulings, and the old app had many days that were prayed but never logged. So nothing is converted to missed/qada. Unrecorded prayers before salah.trackingStart (default = first-run day) are stored as historical status = unrecordedHistory — never pending or missed (P04); only if the user moves trackingStart back (max 30 days) do those days become pending. Historical rows get no QadaItem, are excluded from percentages and streaks, no notification. This status exists for import only.
