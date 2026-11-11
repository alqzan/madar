# Plan 010: The seven tap-crawl tests report a skip instead of a pass

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/Tests/UI/TapCrawlUITests.swift`
> If the file changed, compare the "Current state" excerpts against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW (test code only)
- **Depends on**: none
- **Category**: tests
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

Seven UI tests crawl every room and tap every control. They take about forty
minutes, so they run only when an environment variable is set. Without it each
test returns at once and is counted as **passed**. A full UI run therefore
reports seven green tests that asserted nothing, and the repository rule
«a successful test build or zero executed tests is not a passing suite» is
quietly broken in the totals. After this plan those tests are reported as
skipped, with the reason.

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell).

`Madar/Tests/UI/TapCrawlUITests.swift:10-16`:

```swift
    func testCrawlPrayer() { crawl("prayer", ["MADAR_UI_PRAYER_FIXTURE": "homeShowcase", "MADAR_UI_NOW": "2026-10-07T16:20:00+03:00", "MADAR_UI_TRACKING_START": "2026-10-01"]) }
    func testCrawlQuran() { crawl("quran", ["MADAR_UI_QURAN_FIXTURE": "home"]) }
    func testCrawlMoney() { crawl("money", ["MADAR_UI_MONEY_FIXTURE": "showcase", "MADAR_UI_NOW": "2026-10-16T15:00:00+03:00"]) }
    func testCrawlDiary() { crawl("notes", ["MADAR_UI_DIARY_FIXTURE": "home"]) }
    func testCrawlMihbara() { crawl("mihbara", ["MADAR_UI_MIHBARA_FIXTURE": "home"]) }
    func testCrawlLobby() { crawl("foundation", ["MADAR_UI_HABIT_FIXTURE": "showcase"]) }
    func testCrawlCustomize() { crawl("customize", [:]) }
```

`Madar/Tests/UI/TapCrawlUITests.swift:41-44`:

```swift
    private func crawl(_ tab: String, _ extra: [String: String]) {
        // About forty minutes for all rooms: run on purpose with TEST_RUNNER_MADAR_UI_CRAWL=1, never in a full suite.
        guard ProcessInfo.processInfo.environment["MADAR_UI_CRAWL"] == "1" else { return }
        continueAfterFailure = true
```

`testEdgeTapPressesWideButtons` (line 19) in the same file does not use
`crawl` and is not gated; leave it alone.

## Commands you will need

Run from the repository root. Before any `xcodebuild`, run
`pgrep -fl xcodebuild`; if another build is running, wait for it (never kill it).

| Purpose | Command | Expected on success |
|---|---|---|
| One crawl test, ungated | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=390840AD-4FF0-476F-8E1D-E0C521A58E45' -derivedDataPath DerivedData -resultBundlePath Artifacts/results/PLAN010-$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test -only-testing:MadarUITests/TapCrawlUITests/testCrawlCustomize` | `** TEST SUCCEEDED **` and a line containing `testCrawlCustomize` and `skipped` |
| Whitespace | `git diff --check` | no output |

Use only the simulator with that id. Do NOT set `TEST_RUNNER_MADAR_UI_CRAWL=1`
and do not run the whole class: the real crawl takes about forty minutes.

## Scope

**In scope**: `Madar/Tests/UI/TapCrawlUITests.swift` — the seven `testCrawl…`
functions and the first lines of `crawl`.

**Out of scope**: `testEdgeTapPressesWideButtons`, the body of `crawl` after
the guard, every other test file, all app source.

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Skip instead of returning

- Change the signature to `private func crawl(_ tab: String, _ extra: [String: String]) throws {`.
- Replace the `guard … else { return }` line with:

```swift
        try XCTSkipUnless(ProcessInfo.processInfo.environment["MADAR_UI_CRAWL"] == "1", "The tap crawl takes about forty minutes; run it on purpose with TEST_RUNNER_MADAR_UI_CRAWL=1")
```

- Change each of the seven tests from `func testCrawlX() { crawl(...) }` to
  `func testCrawlX() throws { try crawl(...) }`, keeping the arguments exactly.

Keep the existing comment line above the skip.

**Verify**: the "One crawl test" command → `** TEST SUCCEEDED **`, and its
output reports `testCrawlCustomize` as skipped (not passed). Quote that output
line in your report.

## Test plan

This plan changes test reporting only; the verification in Step 1 is the test.

## Done criteria

- [ ] `grep -c "XCTSkipUnless" Madar/Tests/UI/TapCrawlUITests.swift` prints 1
- [ ] `grep -c "try crawl(" Madar/Tests/UI/TapCrawlUITests.swift` prints 7
- [ ] `grep -c 'MADAR_UI_CRAWL"\] == "1" else { return }' Madar/Tests/UI/TapCrawlUITests.swift` prints 0
- [ ] The single crawl test is reported as skipped
- [ ] `git diff --check` prints nothing; only this one file is modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The file does not match the excerpts.
- The single test starts crawling (the app launches and taps begin): the
  variable is set in your environment or scheme; stop the run and report.
- The test target fails to build for a reason outside this file.

## Maintenance notes

- Reports that add up "tests passed" will now show seven fewer passes and
  seven skips for a full UI run. That is the intended, honest number.
- Other tests gated by `guard … else { return }` on an environment variable
  (owner-trial and iPad-capture files) were not surveyed here; the same change
  applies if they are found.
