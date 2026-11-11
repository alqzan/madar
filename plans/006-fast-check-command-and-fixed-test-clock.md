# Plan 006: One fast `make check`, a current process test in `make test`, and inbox tests on a fixed clock

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/Makefile Madar/README.md Madar/Packages/MadarCommands/Tests/MadarCommandsTests/InboxDrainTests.swift`
> If any of these changed, compare the "Current state" excerpts against the
> live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: dx / tests
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

There is no single quick command that tells an agent "the code is sane" without
a simulator, so every session assembles its own set of checks. `make test` ends
by running a script whose own header says it is historical and excluded from
acceptance, while the script that replaced it is not run by anything. Three
read-only source checks and two Python test files are run by no target. And one
test suite builds its fixture from the real clock and from the prayer engine,
so its result can change with the hour and weekday it runs — the same class of
failure the project already hit twice.

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell). The Makefile lives in `Madar/` and
its recipes run with `Madar/` as the working directory.

`Madar/Makefile:7` and `:18-29`:

```make
.PHONY: fonts generate build preview test test-ios test-links cloud-device
...
test:
	swift test --package-path Packages/MadarCore
	swift test --package-path Packages/MadarData
	swift test --package-path Packages/MadarSnapshots
	swift test --package-path Packages/MadarCommands
	swift test --package-path Packages/MadarMoney
	swift test --package-path Packages/MadarPrayer
	swift test --package-path Packages/MadarQuran
	swift test --package-path Packages/MadarInbox
	swift test --package-path Packages/MadarSync
	python3 scripts/cross-process-test.py
```

`Madar/scripts/cross-process-test.py:2-3`:

```python
# HISTORICAL SQLite-writer probe. Excluded from RA2/M0 acceptance.
# Use inbox-process-test.py for the current producer/app-consumer contract.
```

`Madar/scripts/inbox-process-test.py:2`: `"""RA2 proof: independent Foundation producers, then one synthetic app consumer."""`
It takes no arguments.

Read-only checks that no Makefile target runs (each resolves the repo from its
own location and needs no arguments): `Madar/scripts/check-number-separators.py`,
`check-review-contracts.py`, `check-shipping-sources.py`; and the unit tests
`Madar/scripts/tests/test_prepare_workspace.py`, `test_shipping_sources.py`.

`Madar/README.md:27` describes `make test` as checking «الكتابة من عمليتين مستقلتين على مخازن مؤقتة».

`Madar/Packages/MadarCommands/Tests/MadarCommandsTests/InboxDrainTests.swift:10-29`:

```swift
    private func fixture() throws -> (ModelContainer, DurableCommandAdapter, PendingInbox) {
        ...
        let now = Date(), context = ModelContext(container), settings = try SettingsStore(context: context)
        let day = prayerDay(now)
        ...
    private func prayer(id: UUID = UUID(), generation: UUID, now: Date = Date()) -> InboxRecord {
        .init(..., payload: .object(["dayKey": .string(prayerDay(now).description), ...]), source: .notification, issuedAt: now))
    }
    private func prayerDay(_ now: Date) -> GregorianDay {
        let place = try! ActivePlace(latitude: 24.7136, longitude: 46.6753, timeZoneID: "Asia/Riyadh")
        let civil = GregorianDay.containing(now, in: place.timeZone)
        guard let times = PrayerTimesEngine.calculate(day: civil, place: place) else { return civil }
        return now < times.fajr ? civil.adding(days: -1) : civil
    }
```

Further real-clock uses in the same file are near lines 63, 335 and 376.

## Commands you will need

Run from the repository root.

| Purpose | Command | Expected on success |
|---|---|---|
| The new target | `make -C Madar check` | exit 0 |
| Inbox tests | `swift test --package-path Madar/Packages/MadarCommands --filter InboxDrainTests` | exit 0, same number of tests as before your change |
| Process test | `python3 Madar/scripts/inbox-process-test.py` | exit 0 |
| Whitespace | `git diff --check` | no output |

Do not run `make test` in full, `make build`, `xcodebuild` or anything on a
simulator for this plan.

## Scope

**In scope**: `Madar/Makefile`, `Madar/README.md` (line 27 only),
`Madar/Packages/MadarCommands/Tests/MadarCommandsTests/InboxDrainTests.swift`.

**Out of scope**: the scripts themselves (do not edit or delete
`cross-process-test.py`; it stays as a historical probe), every source file
under `Sources/`, `CLAUDE.md`, `AGENTS.md`, `docs/`.

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Baseline

Run each of these once and record exit code and, for the Swift command, the
test count: `python3 Madar/scripts/check-number-separators.py`,
`python3 Madar/scripts/check-review-contracts.py`,
`python3 Madar/scripts/check-shipping-sources.py`,
`python3 -m unittest discover -s Madar/scripts/tests`,
`python3 Madar/scripts/inbox-process-test.py`,
`swift test --package-path Madar/Packages/MadarCommands --filter InboxDrainTests`.

**Verify**: all six exit 0. If one fails before you changed anything, that is a STOP condition for that item only: leave it out of `make check`, say so in your report, and continue.

### Step 2: Add `make check` and swap the process test

In `Madar/Makefile`: add `check` to the `.PHONY` line; add this target directly
above `test:` (recipe lines start with a TAB):

```make
# Fast, simulator-free sanity check.
check:
	python3 scripts/check-number-separators.py
	python3 scripts/check-review-contracts.py
	python3 scripts/check-shipping-sources.py
	python3 -m unittest discover -s scripts/tests
	swift test --package-path Packages/MadarCore
	swift test --package-path Packages/MadarPrayer
	swift test --package-path Packages/MadarQuran
```

In the `test:` recipe replace the last line with
`python3 scripts/inbox-process-test.py`.

In `Madar/README.md` line 27, replace only the phrase
«ومن الكتابة من عمليتين مستقلتين على مخازن مؤقتة» with
«ومن عقد الصندوق بين منتجين مستقلين والتطبيق»، and add one sentence after that
line's first sentence: «`make check` فحص سريع بلا محاكٍ: فحوص المصادر الثلاثة واختبارات السكربتات وحزم المحركات.»

**Verify**: `make -C Madar check` → exit 0; `grep -c "cross-process-test" Madar/Makefile` → 0.

### Step 3: Pin the inbox test clock

In `InboxDrainTests.swift`, add inside the suite:

```swift
    /// Thursday 15 Oct 2026, 14:00 Riyadh: after Fajr, so the prayer day is the civil day. Fixed so the fixture never
    /// depends on the hour or weekday the suite runs.
    private static let fixedNow = ISO8601DateFormatter().date(from: "2026-10-15T14:00:00+03:00")!
    private static let fixedDay = try! GregorianDay("2026-10-15")
```

Then: in `fixture()` use `let now = Self.fixedNow` and `let day = Self.fixedDay`;
change the default in `prayer(id:generation:now:)` to `now: Date = Self.fixedNow`
and build its `dayKey` from `Self.fixedDay.description` when `now == Self.fixedNow`,
otherwise keep `prayerDay(now)`; replace the other bare `Date()` calls in the
file (near lines 63, 335, 376) with `Self.fixedNow` **only where the value is
passed into the fixture, a command or the drain as its "now"**. Leave a
`Date()` that is used to build a unique temp path or to measure elapsed time.
Delete `prayerDay` if nothing uses it afterwards.

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter InboxDrainTests` → exit 0 with the same test count as Step 1.

## Test plan

No new tests. The existing `InboxDrainTests` must pass with the same count; the
fixed instant and day are stated in the comment and do not come from the code
under test.

## Done criteria

- [ ] `make -C Madar check` exits 0
- [ ] `grep -c "inbox-process-test.py" Madar/Makefile` prints 1 and `grep -c "cross-process-test" Madar/Makefile` prints 0
- [ ] `swift test --package-path Madar/Packages/MadarCommands --filter InboxDrainTests` exits 0, same test count as the baseline
- [ ] `grep -c "let now = Date()" Madar/Packages/MadarCommands/Tests/MadarCommandsTests/InboxDrainTests.swift` prints 0
- [ ] `git diff --check` prints nothing; only the three in-scope files are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- An `InboxDrainTests` case fails after Step 3 and passes when you revert only
  that case's clock change: the drain or the adapter reads the real clock
  internally (for example an expiry compared with `Date()`). Revert that one
  case, name it in your report, and continue with the rest.
- A recipe in `make check` needs network access or writes outside ignored
  build folders.
- The excerpts in "Current state" do not match the live files.

## Maintenance notes

- `make check` deliberately leaves out `MadarData`, `MadarCommands` and
  `MadarMoney` (slower); `make test` still runs every package.
- The repository protocol asks for `check-review-contracts.py` and
  `check-shipping-sources.py` only at milestone gates; `make check` makes them
  cheap to run more often but does not change that rule.
- Other suites that read the real clock were not surveyed here; see the
  test-quality rows in `plans/README.md`.
