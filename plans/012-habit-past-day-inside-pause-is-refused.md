# Plan 012: A habit cannot be logged on a past day that was inside a pause

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/Packages/MadarCommands/Sources/MadarCommands/HabitRepository.swift Madar/Packages/MadarCommands/Sources/MadarCommands/HabitMutationHandler.swift Madar/App/HabitSinceView.swift Madar/Packages/MadarCommands/Tests/MadarCommandsTests/HabitPersistenceTests.swift`
> If any changed, compare the "Current state" excerpts against the live code
> before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW-MED (a command rule gets stricter)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

«فعلتها في يوم سابق» lets the owner log a habit on an earlier day. Logging
**today** is refused while the habit is paused. Logging a **past** day that
was inside a pause is accepted: the event is stored, the toast appears and
«آخر مرة» shows the day. But the habit engine ignores every event on a paused
day, so the period's count and the streak do not move. The owner sees a saved
action that silently counts for nothing. For a daily habit the day is already
refused (a fully paused period has target 0); the gap is weekly, monthly and
interval habits, where the period still has other eligible days. After this
plan the command refuses such a day and the screen does not offer it.

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell).

`Madar/Packages/MadarCommands/Sources/MadarCommands/HabitRepository.swift:8-25`:

```swift
public struct HabitReading: Identifiable, Sendable {
    public let id: UUID
    ...
    public let summary: HabitSummary
    public let firstEffectiveFrom: GregorianDay
    public let paused: Bool
    public let isNow: Bool
    /// Days the habit was done, newest first, each with the diary line linked to it (item 26 «منذ آخر مرة»).
    public var times: [HabitTime] = []
    public var lastTime: HabitTime? { times.first }
```

The struct has no explicit initializer (memberwise, declaration order).
`HabitRepository.swift:110-120` builds `var breaks: [HabitBreak]` per habit
(manual pauses, plus trips for a home-only habit), passes it to the engine at
line 205, and line 223 creates the reading:

```swift
            result.append(.init(id: habit.id, ..., paused: breaks.contains { $0.contains(today) }, isNow: ..., times: times))
```

`HabitBreak` (`Madar/Packages/MadarCore/Sources/MadarCore/HabitEngine.swift:50-55`)
is `Sendable`, with `public func contains(_ day: GregorianDay) -> Bool`.

`Madar/Packages/MadarCore/Sources/MadarCore/HabitEngine.swift:142` drops paused facts:

```swift
        for (index, fact) in facts.enumerated() where fact.day >= first.effectiveFrom && fact.day <= today && !pauses.contains(where: { $0.contains(fact.day) }) {
```

`Madar/Packages/MadarCommands/Sources/MadarCommands/HabitMutationHandler.swift:51-60`:

```swift
            if let day, day != today {
                // A past day is logged in the period that held it; a day after today or before the habit began is refused.
                guard day < today else { throw DataError.invalidValue("لا يُسجّل يوم لم يأتِ بعد") }
                guard let reading, day >= reading.firstEffectiveFrom,
                      let period = reading.summary.periods.last(where: { $0.start <= day && day < $0.end }), period.target > 0 else { throw DataError.invalidValue("هذا اليوم قبل بداية العادة") }
                target = period; logDay = day
                ...
            } else {
                guard let reading, !reading.paused, let current = reading.summary.current, current.target > 0 else { throw DataError.invalidValue("العادة مستثناة اليوم") }
```

`Madar/App/HabitSinceView.swift:141`:

```swift
    private var hasSelectedTarget: Bool { day >= reading.firstEffectiveFrom && (selectedPeriod?.target ?? 0) > 0 }
```

Test exemplar: `Madar/Packages/MadarCommands/Tests/MadarCommandsTests/HabitPersistenceTests.swift`
— `pastDayBeforeWeeklyHabitStartIsRejectedInsideItsFirstPeriod` (line 115) for
the fixture shape, and `pauseResumeAndPolicyEditsAreDatedAndUndoable`
(line 135) for `habit.pause` / `habit.resume`. The suite's fixed clock is
`now = 2026-10-15T20:00:00+03:00`; `payload(_:_:)` builds a `habit.save` payload.

## Commands you will need

Run from the repository root. Before any `xcodebuild`, run
`pgrep -fl xcodebuild`; if another build is running, wait for it (never kill it).

| Purpose | Command | Expected on success |
|---|---|---|
| Habit command tests | `swift test --package-path Madar/Packages/MadarCommands --filter HabitPersistenceTests` | exit 0 |
| Other constructions | `grep -rn "HabitReading(" Madar/App Madar/Packages Madar/Tests Madar/Widgets Madar/Intents` | lists every place that builds a reading by hand |
| App compiles | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |
| Whitespace | `git diff --check` | no output |

## Scope

**In scope**: `HabitRepository.swift` (one new property and line 223),
`HabitMutationHandler.swift` (the past-day branch only), `HabitSinceView.swift`
(line 141 only), `HabitPersistenceTests.swift` (one new test).

**Out of scope**: `HabitEngine.swift` (the engine is right); how `times` is
built at `HabitRepository.swift:221-222` (it lists days that were really done;
a later retroactive pause must not erase them); the today branch; habit
editing; every schema file.

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Write the failing test first

Add to `HabitPersistenceTests` (dates: habit weekly from Mon 12 Oct; paused
14 and 15 Oct; logging happens on 17 Oct):

```swift
    /// A paused day does not count (the engine drops it); logging it later must be refused, not stored and ignored.
    @Test func pastDayInsideAPauseIsRejectedAndNothingIsStored() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HabitPastPause-\(UUID())"); defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root)
        let bus = CommandBus(adapter: DurableCommandAdapter(container: container, lockDirectory: root, transactionClock: { $0 }))
        func run(_ name: String, _ p: [String: MadarCore.JSONValue], at date: Date) async throws -> CommandOutcome {
            try await bus.execute(.init(name: name, payload: .object(p), issuedAt: date), now: date)
        }
        let habit = UUID(), id: MadarCore.JSONValue = .string(habit.uuidString), later = now.addingTimeInterval(2 * 86400)
        var rule = HabitRule(effectiveFrom: try GregorianDay("2026-10-12")); rule.frequency = .weekly
        #expect(try await run("habit.save", payload(habit, rule), at: now).status == .applied)
        #expect(try await run("habit.pause", ["id": id, "from": .string("2026-10-14")], at: now).status == .applied)
        #expect(try await run("habit.resume", ["id": id], at: now.addingTimeInterval(86400)).status == .applied)
        // 14 and 15 Oct were paused; 13 Oct was not.
        #expect(try await run("habit.complete", ["id": id, "day": .string("2026-10-14")], at: later).status == .rejected)
        #expect(try await run("habit.complete", ["id": id, "day": .string("2026-10-13")], at: later).status == .applied)
        let events = try ModelContext(container).fetch(FetchDescriptor<HabitEvent>()).filter { $0.delta != 0 }
        #expect(events.map(\.dayKey) == ["2026-10-13"])
    }
```

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter HabitPersistenceTests`
→ the new test **fails** on the `.rejected` expectation (today it is `.applied`).
If it passes before Step 2, or fails on an earlier line, that is a STOP condition.

### Step 2: Expose the breaks and refuse the day

- `HabitRepository.swift`: add, directly after the `times` property,

```swift
    /// Every pause and home-only trip freeze of this habit; a day inside one never counts.
    public var breaks: [HabitBreak] = []
```

  and at line 223 append `, breaks: breaks` after `times: times` inside the
  `.init(…)` call.
- Run the "Other constructions" command. Places that build a `HabitReading`
  by hand keep compiling because the new property has a default; do not edit them.
- `HabitMutationHandler.swift`, past-day branch: after the existing
  `guard let reading, day >= reading.firstEffectiveFrom, …` line, add

```swift
                guard !reading.breaks.contains(where: { $0.contains(day) }) else { throw DataError.invalidValue("العادة كانت موقوفة في هذا اليوم") }
```

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter HabitPersistenceTests`
→ exit 0, with one more test than before Step 1.

### Step 3: Do not offer the day on the screen

`HabitSinceView.swift:141`: change to

```swift
    private var hasSelectedTarget: Bool { day >= reading.firstEffectiveFrom && (selectedPeriod?.target ?? 0) > 0 && !reading.breaks.contains { $0.contains(day) } }
```

**Verify**: the app build command → `** BUILD SUCCEEDED **`.

## Test plan

The new test's expectations come from the rule «a paused day does not count»,
not from the code's output. All existing `HabitPersistenceTests` must still
pass, in particular `pastDayIsLoggedInItsOwnPeriodWithItsDiaryLine` and
`endingTripResumesItsLinkedHabitPauseThatDay`.

## Done criteria

- [ ] The new test failed before Step 2 and passes after it
- [ ] `swift test --package-path Madar/Packages/MadarCommands --filter HabitPersistenceTests` exits 0; report the executed count
- [ ] `swift test --package-path Madar/Packages/MadarCommands --filter InboxDrainTests` exits 0 (it also drives habit commands)
- [ ] The app build prints `** BUILD SUCCEEDED **`
- [ ] `git diff --check` prints nothing; only the four in-scope files are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The new test fails before Step 2 on a line other than the `.rejected`
  expectation (for example `habit.pause` refuses a start one day back): report
  the line and the error; do not change the dates by guesswork.
- `HabitReading` has an explicit initializer after all, or adding the property
  breaks a call site outside the four files.
- An existing habit test fails after Step 2.

## Maintenance notes

- Events already stored on paused days (logged before this fix) stay in the
  store and stay uncounted; this plan does not clean them and must not.
- Related, not in this plan (see the backlog in `plans/README.md`): editing a
  habit whose first date is still in the future moves its start to today.
