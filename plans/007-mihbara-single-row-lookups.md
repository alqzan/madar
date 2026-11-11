# Plan 007: Mihbara looks up one saved word and one reading session without loading the whole table

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/App/MihbaraReaderView.swift Madar/Packages/MadarCommands/Sources/MadarCommands/BookMutationHandler.swift`
> If either changed, compare the "Current state" excerpts against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW for Step 1, MED for Step 2 (a write path)
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

In the reader, every tap on a word asks "is this word already saved?" by
fetching every saved word from the store on the main thread, just before the
word card animates in. Saving a reading session does the same with every
reading session ever recorded, to find one by id. Both tables only grow, so the
reader gets slower the more the owner reads. After this plan each lookup asks
the store for the rows it needs.

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell).

`Madar/App/MihbaraReaderView.swift:1333-1339` (called at line 1326 from the
selection handler):

```swift
    @MainActor private func savedWordExists(_ word: String, language: String) -> Bool {
        let key = UserWordIdentity.key(language: language, word: word)
        let context = ModelContext(app.container)
        return (try? context.fetch(FetchDescriptor<UserWord>()))?.contains {
            $0.deletedAt == nil && $0.mergedInto == nil && UserWordIdentity.key(language: $0.language, word: $0.word) == key
        } ?? false
    }
```

`UserWord` (in `Madar/Packages/MadarData/Sources/MadarData/GeneratedModels.swift`,
read-only) has `word: String`, `language: String = "ar"`, `deletedAt: Date?`,
`mergedInto: UUID?`. `UserWordIdentity.key` normalises the word, so the stored
`word` cannot be compared with `==` in a predicate; only `language` and the two
optionals can be pushed into the store.

`Madar/Packages/MadarCommands/Sources/MadarCommands/BookMutationHandler.swift:338-345`:

```swift
        case .readingSession(let id, let bookID, let start, let end, ...):
            _ = try fileBook(bookID)
            guard end >= start, activeSeconds >= 60, ... else { throw DataError.invalidValue("بيانات جلسة القراءة غير صالحة") }
            let sessions = try context.fetch(FetchDescriptor<ReadingSession>())
            let row: ReadingSession
            let isNew: Bool
            if let existing = sessions.first(where: { $0.id == id }) {
```

A predicate of this shape already exists in the app, for example
`Madar/App/AppBahwService.swift:205`:
`FetchDescriptor<UpcomingDay>(predicate: #Predicate { $0.deletedAt == nil && $0.mergedInto == nil })`.

## Commands you will need

Run from the repository root.

| Purpose | Command | Expected on success |
|---|---|---|
| Book command tests | `swift test --package-path Madar/Packages/MadarCommands --filter Book` | exit 0 |
| App compiles | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |
| Whitespace | `git diff --check` | no output |

Before `xcodebuild`, run `pgrep -fl xcodebuild`; if another build is running,
wait for it (do not kill it).

## Scope

**In scope**: `Madar/App/MihbaraReaderView.swift` (the function
`savedWordExists` only), `Madar/Packages/MadarCommands/Sources/MadarCommands/BookMutationHandler.swift`
(the `.readingSession` case only).

**Out of scope**: the `let books = try context.fetch(FetchDescriptor<Book>())`
at the top of `BookMutationHandler.stage` (line 29; `books` is used throughout
the function), the `Media` and `UserWord` fetches elsewhere in that file, any
Turath file, any schema file.

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Narrow the saved-word lookup

Replace the fetch in `savedWordExists` with a predicate on the stored fields
and keep the normalised comparison in memory over that smaller set:

```swift
        let descriptor = FetchDescriptor<UserWord>(predicate: #Predicate { $0.language == language && $0.deletedAt == nil && $0.mergedInto == nil })
        return (try? context.fetch(descriptor))?.contains { UserWordIdentity.key(language: $0.language, word: $0.word) == key } ?? false
```

**Verify**: the app build command → `** BUILD SUCCEEDED **`.

### Step 2: Fetch the reading session by id

First run `grep -n "sessions" Madar/Packages/MadarCommands/Sources/MadarCommands/BookMutationHandler.swift`
and read every use of the local `sessions` inside the `.readingSession` case.
If its only use is `sessions.first(where: { $0.id == id })`, replace the fetch
and that lookup with:

```swift
            var sessionByID = FetchDescriptor<ReadingSession>(predicate: #Predicate { $0.id == id }); sessionByID.fetchLimit = 1
            ...
            if let existing = try context.fetch(sessionByID).first {
```

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter Book` → exit 0, then the app build command → `** BUILD SUCCEEDED **`.

## Test plan

No new tests: behaviour is unchanged and the existing book command tests cover
the reading-session path. Report the number of tests the filter ran; if it ran
zero, run `swift test --package-path Madar/Packages/MadarCommands` in full
instead and report that count.

## Done criteria

- [ ] `grep -c "FetchDescriptor<UserWord>()" Madar/App/MihbaraReaderView.swift` prints 0
- [ ] `grep -c "FetchDescriptor<ReadingSession>())" Madar/Packages/MadarCommands/Sources/MadarCommands/BookMutationHandler.swift` prints 0 (or Step 2 was skipped under a STOP condition and reported)
- [ ] The MadarCommands test command exits 0 with a non-zero test count
- [ ] The app build prints `** BUILD SUCCEEDED **`
- [ ] `git diff --check` prints nothing; only the two in-scope files are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- `sessions` in the `.readingSession` case is used for anything besides the
  by-id lookup (for example a duplicate check by time range): skip Step 2 and
  report the other use.
- The `#Predicate` does not compile because `id` or `language` is not captured
  as written; do not rewrite the model or add an index.
- The build fails for a reason unrelated to your two files.

## Maintenance notes

- Remaining whole-table fetches in `BookMutationHandler.swift` (all `Book`
  rows per command at line 29; `Media` and `UserWord` lookups reported near
  lines 66, 265 and 451 by an auditor and not re-read) are left on purpose:
  they sit on write paths with more semantics and deserve their own tests.
- If saved words grow large within one language, an in-memory key set refreshed
  on save would remove the fetch entirely.
