# Plan 003: The lobby reads «القادم» and the year block once per store generation, not on every render

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/App/AppBahwService.swift Madar/App/AppSession.swift Madar/Tests/Integration/BahwPrayerIntegrationTests.swift`
> If any of these files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

The lobby (البهو) is the app's home screen and redraws often: once a minute
from its timeline, and after every write anywhere in the app. Two of its blocks
do real work inside the view body each time: the upcoming-days block opens a new
database context, fetches every `UpcomingDay` row and runs calendar maths per
row; the year block recomputes Hijri landmarks. The owner reported freezes on
this screen before, and the Quran and diary blocks were already fixed by caching
their result per store generation, day and minute. This plan gives the two
remaining blocks the same treatment. Nothing the user sees changes.

## Current state

All paths are relative to the repository root. The repository root folder name
contains Arabic characters and a space: always quote it in shell commands.

- `Madar/App/AppBahwService.swift` — `@MainActor struct AppBahwService`
  (line 66), created freshly by views; holds `session: AppSession`.
- `Madar/App/BahwBlocks.swift` — the lobby blocks. Read-only context: line 595
  calls `service.upcoming(limit: ...)` and line 536 calls `service.year()`,
  both inside `@ViewBuilder` computed properties, i.e. on every body evaluation.
- `Madar/App/AppSession.swift` — the app-wide `@Observable` session object.

The existing cache this plan copies, `AppBahwService.swift:169-189`:

```swift
    /// FB-32 (owner: no freezes): the lobby body asks for these on every render; the Quran snapshot and the diary day
    /// are read once per store generation, day and minute, not on each frame.
    private static var quranCache: (key: String, value: BahwQuranModel?)?
    private static var diaryCache: (key: String, value: BahwDiaryModel?)?
    private var cacheKey: String { "\(session.storeGeneration):\(today):\(Int(session.prayerNow().timeIntervalSince1970 / 60))" }
    ...
    func diary() -> BahwDiaryModel? {
        let key = cacheKey
        if let cached = Self.diaryCache, cached.key == key { return cached.value }
        let value = readDiary(); Self.diaryCache = (key, value); return value
    }
    private func readDiary() -> BahwDiaryModel? {
```

The two uncached reads, `AppBahwService.swift:195-205`:

```swift
    func year() -> BahwYearModel {
        let days = calendarDays, day = today
        return .init(hijri: MadarYear.hijriYear(day, days), gregorian: MadarYear.gregorianYear(day), ...
                     ..., ramadanIn: MadarYear.ramadanIn(day, days), landmarks: MadarYear.landmarks(day, days))
    }
    /// User days (stored rules) and the seasons as read models; a user day with the same title and date hides the automatic one.
    /// `outside`: the widget snapshot; the salary day stays in the app when money is hidden outside it (`core.hideMoneyOutside`).
    func upcoming(limit: Int, outside: Bool = false) -> [BahwUpcomingItem] {
        let days = calendarDays, day = today
        var items: [BahwUpcomingItem] = []
        if let rows = try? ModelContext(session.container).fetch(FetchDescriptor<UpcomingDay>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })) {
```

`upcoming` ends (around line 229) with
`return Array(items.sorted { ... }.prefix(limit))`.

Why the generation key is safe, `AppSession.swift:283-286`:

```swift
    /// Bumped on every store reload (after each write and each return to the app): derived read caches key on it.
    @ObservationIgnored private(set) var storeGeneration = 0
    func reload() throws {
        storeGeneration &+= 1
```

Every write in the app goes through a command and ends in `reload()`, so a
cache keyed on `storeGeneration` is refreshed after any change to upcoming
days, settings or money.

Why the new cache must live on the session and not in `static` storage: the
integration tests create many `AppSession` objects with different stores in one
process (for example `Madar/Tests/Integration/RoomWidgetSnapshotTests.swift:67`
calls `AppBahwService(session:app,evaluationDate:instant)`); a static cache
keyed only on generation, day and minute could return another test's rows.

Test fixture to copy, `Madar/Tests/Integration/BahwPrayerIntegrationTests.swift:36-43`:

```swift
        let root = FileManager.default.temporaryDirectory.appending(path: "HabitOrbitClock-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let context = ModelContext(container), settings = try SettingsStore(context: context)
        _ = try settings.stage(["core.dayStart": .string("midnight"), "core.firstCalendar": .string("gregorian"), "core.weekStart": .string("saturday")])
        try context.save()
        let app = try AppSession(container: container, groupDirectory: root)
        let service = AppBahwService(session: app, evaluationDate: ISO8601DateFormatter().date(from: "2026-10-15T20:00:00+03:00")!)
```

The stored model, `Madar/Packages/MadarData/Sources/MadarData/GeneratedModels.swift:212-226`
(read-only): `UpcomingDay` has `title: String = ""`, `calendar: String = "hijri"`,
`year: Int? = nil`, `month: Int = 1`, `day: Int = 1`, `repeats: String = "none"`,
plus the usual `deletedAt` / `mergedInto` optionals.

## Commands you will need

Run from the repository root unless a `cd` is shown.

| Purpose | Command | Expected on success |
|---|---|---|
| Is the simulator busy? | `pgrep -fl xcodebuild` | no output (if there is output, wait and retry; see STOP conditions) |
| Run the lobby integration tests | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=390840AD-4FF0-476F-8E1D-E0C521A58E45' -derivedDataPath DerivedData -resultBundlePath Artifacts/results/PLAN003-lobby-$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test -only-testing:MadarTests/BahwPrayerIntegrationTests -only-testing:MadarTests/RoomWidgetSnapshotTests` | `** TEST SUCCEEDED **`, 0 failures |
| Whitespace | `git diff --check` | no output |

Use only the simulator id shown above. Never create, erase or reset a
simulator, and never run `xcodegen` or `make generate` for this plan (no file
is added).

## Scope

**In scope** (the only files you may modify):
- `Madar/App/AppBahwService.swift`
- `Madar/App/AppSession.swift` — one added stored property only
- `Madar/Tests/Integration/BahwPrayerIntegrationTests.swift`

**Out of scope** (do NOT touch):
- `Madar/App/BahwBlocks.swift`, `BahwLobbyView.swift` — callers stay as they are.
- `AppSession.reload()` — do not change what it assigns or when. In particular
  do NOT add "assign only if changed" guards to `values` or `container`: other
  screens may depend on that invalidation to refresh after a write, and that
  change needs measurement first (it is tracked separately in `plans/README.md`).
- The existing `quranCache` / `diaryCache` statics — leave them.
- Any file whose name contains `Money`, `Bank` or `Turath`; `docs/PROGRESS.md`,
  `docs/DECISIONS.md`, `CLAUDE.md`, `AGENTS.md`, `Madar/Madar.xcodeproj`.

## Git workflow

- Work on `main` (the repository protocol forbids a branch per task) unless your
  operator placed you in a worktree.
- One commit:
  `[OWNER] <what is now true, with test counts and the result bundle name> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`.
- Do NOT push, and do not archive or upload a build.

## Steps

### Step 1: Add the failing test

In `BahwPrayerIntegrationTests.swift`, add a method
`testUpcomingIsReadOncePerStoreGeneration` to the existing test class, using
the fixture lines quoted above (give the temp folder its own name):

1. `let first = service.upcoming(limit: 50)`.
2. Insert a row behind the session's back, without a command:
   `let row = UpcomingDay(); row.title = "يوم الاختبار"; row.calendar = "gregorian"; row.month = 3; row.day = 9; row.repeats = "yearly"`,
   insert it into a new `ModelContext(app.container)` and `save()`.
3. `XCTAssertEqual(service.upcoming(limit: 50).map(\.id), first.map(\.id))` —
   same store generation, so the cached list is returned.
4. `try app.reload()` then
   `XCTAssertTrue(service.upcoming(limit: 50).contains { $0.title == "يوم الاختبار" })` —
   a new generation re-reads.
5. Also assert that a different limit is not served from the wrong entry:
   `XCTAssertEqual(service.upcoming(limit: 1).count, 1)`.

**Verify**: run the lobby integration tests command → `** TEST FAILED **`, with only the new test failing, at assertion 3 (today the list is re-read and already contains the new row).

### Step 2: Add a session-scoped cache holder

In `AppBahwService.swift`, above `struct AppBahwService`, add:

```swift
/// Lobby reads that the view body asks for on every render; kept on the session so stores never share them.
@MainActor final class BahwReadCache {
    var key = ""
    var upcoming: [String: [BahwUpcomingItem]] = [:]
    var year: BahwYearModel?
}
```

In `AppSession.swift`, next to the `storeGeneration` declaration (line 284), add
one line:

```swift
    @ObservationIgnored let bahwReads = BahwReadCache()
```

**Verify**: `grep -c "bahwReads" Madar/App/AppSession.swift` → 1.

### Step 3: Route `upcoming` and `year` through the cache

In `AppBahwService.swift`:

1. Rename the existing `func year() -> BahwYearModel` to
   `private func readYear() -> BahwYearModel` and the existing
   `func upcoming(limit: Int, outside: Bool = false) -> [BahwUpcomingItem]` to
   `private func readUpcoming(limit: Int, outside: Bool) -> [BahwUpcomingItem]`.
   Keep their doc comments on the new public functions below. Do not change
   their bodies.
2. Add:

```swift
    private var reads: BahwReadCache {
        let cache = session.bahwReads, key = cacheKey
        if cache.key != key { cache.key = key; cache.upcoming = [:]; cache.year = nil }
        return cache
    }
    func year() -> BahwYearModel {
        let cache = reads
        if let cached = cache.year { return cached }
        let value = readYear(); cache.year = value; return value
    }
    func upcoming(limit: Int, outside: Bool = false) -> [BahwUpcomingItem] {
        let cache = reads, slot = "\(limit):\(outside)"
        if let cached = cache.upcoming[slot] { return cached }
        let value = readUpcoming(limit: limit, outside: outside); cache.upcoming[slot] = value; return value
    }
```

**Verify**: run the lobby integration tests command → `** TEST SUCCEEDED **`, 0 failures, including the new test and every `RoomWidgetSnapshotTests` case.

## Test plan

- New: `testUpcomingIsReadOncePerStoreGeneration` (cached within a generation,
  re-read after `reload()`, separate entries per limit).
- Regression: `RoomWidgetSnapshotTests` and the rest of
  `BahwPrayerIntegrationTests` (they build several sessions and services in one
  process and must not see each other's rows).
- Pattern: the habit-orbit test at `BahwPrayerIntegrationTests.swift:36-46`.

## Done criteria

- [ ] The lobby integration tests command prints `** TEST SUCCEEDED **` with 0 failures; report the executed test count and the result bundle path
- [ ] `grep -c "func readUpcoming\|func readYear" Madar/App/AppBahwService.swift` prints 2
- [ ] `git diff 83c5e5b7 -- Madar/App/AppSession.swift | grep -c "^[+-][^+-]"` prints 1 (one added line, nothing else)
- [ ] `git diff --check` prints nothing
- [ ] `git status --short` shows no modified file outside the three in-scope files (files already modified before you started do not count; list them in your report)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" do not match the live code.
- `pgrep -fl xcodebuild` still shows another build or test after you waited 15
  minutes (another session shares this simulator; do not run alongside it and
  do not kill its process).
- `BahwUpcomingItem` or `BahwYearModel` cannot be stored in the cache class as
  written (for example a compiler error about `Sendable` or isolation that the
  `@MainActor` annotation does not resolve).
- The new test passes already in Step 1 (before your change). That means the
  inserted row is not visible in the list at all, so the test proves nothing:
  report it instead of weakening the assertions.
- Any existing test in the two test classes fails after Step 3.
- You find a write path that changes `UpcomingDay` rows without calling
  `AppSession.reload()` (search: `grep -rn "UpcomingDay()" Madar/App Madar/Packages/MadarCommands/Sources`);
  report it instead of adding invalidation yourself.
- The build fails for a reason unrelated to your files (another session may
  have uncommitted work in the tree); report the first error, do not fix it.

## Maintenance notes

- The cache holds values for one generation/day/minute key and is cleared when
  the key changes, so it cannot grow without bound.
- A reviewer should confirm `evaluationDate` (used by tests and the widget
  snapshot) still behaves: `cacheKey` is built from `today` and
  `session.prayerNow()`, exactly as for the existing Quran and diary caches.
- Deferred on purpose: `AppSession.reload()` reassigns the whole settings
  dictionary after every write, which re-renders every view that reads any
  setting. Fixing that could change which screens refresh after a write, so it
  needs an Instruments measurement and a per-screen check first.
