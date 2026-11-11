# Plan 001: The merge pass keeps the media of a diary entry that can still be undeleted

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/Packages/MadarData/Sources/MadarData/RowMerger.swift Madar/Packages/MadarData/Tests/MadarDataTests/DataTests.swift`
> If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW (narrows an existing delete; never deletes more than today)
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

Deleting a diary entry is undoable for 10 minutes. The delete command keeps the
entry's photo and voice bytes alive for that window on purpose, and a separate
sweep clears them only after the window ends. The store's dedupe pass
(`RowMerger`) does not know about the window: whenever it runs, it tombstones
the media of every deleted entry and sets the bytes to nil. The pass runs after
every Day One import and inside backup restore. So: delete a photo entry, run an
import or a restore within 10 minutes, press undo — the text comes back and the
photo or recording is gone for good. The trigger is rare, the loss is
irreversible. After this plan the merge pass leaves that media alone until the
undo window has passed.

## Current state

All paths are relative to the repository root. The repository root folder name
contains Arabic characters and a space: always quote it in shell commands.

- `Madar/Packages/MadarData/Sources/MadarData/RowMerger.swift` — the dedupe
  pass. `run()` reads all rows as `DataRecord`, calls the pure static
  `reconciled(_:)`, and applies the differences. `cascade(_:)` is one step
  inside `reconciled`.
- `Madar/Packages/MadarData/Tests/MadarDataTests/DataTests.swift` — Swift
  Testing (`@Test`) tests for this pass.
- `Madar/Packages/MadarCommands/Sources/MadarCommands/DiaryMutationHandler.swift`
  and `DurableCommandAdapter.swift` — the delete command and the after-window
  sweep. Read-only context; do NOT modify them.

`RowMerger.swift:12-22` (today):

```swift
    @discardableResult public func run() throws -> Int {
        do {
            let instances = try RecordBridge.instances(context)
            let original = try instances.map { try $0.record() }
            let result = try Self.reconciled(original)
```

`RowMerger.swift:76`:

```swift
    public static func reconciled(_ input: [DataRecord]) throws -> [DataRecord] {
```

`RowMerger.swift:217-231` — the defect is line 229, which runs for every
tombstoned `Entry` regardless of how recently it was deleted:

```swift
    private static func cascade(_ rows: inout [DataRecord]) throws {
        for parent in rows where parent.deletedAt != nil && parent.fields["mergedInto"] == .null {
            ...
            if parent.model == "Entry" {
                let mediaIDs = Set(([parent.fields["mediaID"] ?? .null] + (parent.fields["attachmentMediaIDs"]?.array ?? [])).compactMap(\.string))
                for i in rows.indices where rows[i].model == "Media" && mediaIDs.contains(rows[i].id.uuidString) {
                    ...
                    if !shared { rows[i].fields["deletedAt"] = parent.fields["deletedAt"]; rows[i].fields["deletionBarrierAt"] = parent.fields["deletedAt"]; rows[i].fields["data"] = .null }
                }
            }
```

The promise it breaks, `DiaryMutationHandler.swift:179-180`:

```swift
        // Media rows and external bytes stay live through the undo window. Receipt records contain Entry
        // references only; the expiry sweep clears unreferenced bytes after undo is no longer possible.
```

The undo window length, `DurableCommandAdapter.swift:451`:

```swift
        receipt.undoExpiresAt = appliedAt.addingTimeInterval(request.semantics == .preset ? 60 : 600)
```

So a diary delete is undoable for 600 seconds. After that,
`DurableCommandAdapter.purgeExpiredDiaryEntryMedia` (lines 495-521) tombstones
the media and clears its bytes; that path is correct and stays as it is.

Other callers of `RowMerger.reconciled(...)` (they must keep compiling
unchanged): `Madar/Packages/MadarData/Sources/MadarData/BackupCoordinator.swift:351`
and `:367`, `Madar/Packages/MadarData/Sources/MadarData/Backup.swift:197`.

Existing test to model the new tests on, `DataTests.swift:120-128`:

```swift
    @Test func test_M0S1_RD2_entryDeletionRetainsMarginsAndSharedMedia() throws {
        let c = try MadarContainerFactory.makeInMemory(); let context = c.mainContext
        let media = Media(); let entry = Entry(); let other = Entry(); entry.mediaID = media.id; other.mediaID = media.id
        ...
        for row in [media as any PersistentModel,entry,other,note] { context.insert(row) }; try context.save(); try RowMerger(context:context).run()
        #expect(try note.record() == before); #expect(media.deletedAt == nil)
        #expect(try RowMerger(context:context).run() == 0)
    }
```

Project rules that apply (from the repository's `CLAUDE.md`): deletes use
tombstones; expected test values come from the product rule (here: the
10-minute undo), never from the code's own output; a change that could delete
stored records needs one focused review before it ships.

## Commands you will need

Run from the repository root.

| Purpose | Command | Expected on success |
|---|---|---|
| MadarData tests | `swift test --package-path Madar/Packages/MadarData` | exit 0, all tests pass |
| Day One import tests (call the merge pass) | `swift test --package-path Madar/Packages/MadarCommands --filter DayOneImportPersistenceTests` | exit 0 |
| Whitespace | `git diff --check` | no output |

Do not run `xcodebuild`, `make`, or anything on a simulator for this plan.

## Scope

**In scope** (the only files you may modify):
- `Madar/Packages/MadarData/Sources/MadarData/RowMerger.swift`
- `Madar/Packages/MadarData/Tests/MadarDataTests/DataTests.swift`

**Out of scope** (do NOT touch):
- `DiaryMutationHandler.swift`, `DurableCommandAdapter.swift`,
  `DayOneImportHandler.swift` — the delete, sweep and import behave correctly.
- `BackupCoordinator.swift`, `Backup.swift` — they call `reconciled` with the
  default argument and need no edit.
- Any file whose name contains `Money`, `Bank` or `Turath`; `GeneratedModels.swift`,
  `LegacyV1Models.swift`, any `SchemaV*.swift`.
- `docs/PROGRESS.md`, `docs/DECISIONS.md`, `CLAUDE.md`, `AGENTS.md`.

## Git workflow

- Work on `main` (the repository protocol forbids a branch per task) unless your
  operator placed you in a worktree.
- One commit. Message style, from `git log`:
  `[OWNER] Diary hub reads the archive and the memories shelf off the main actor (...) (claude, model: claude-sonnet-5-5, effort: medium)`.
  Use `[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`.
- Do NOT push, and do not archive or upload a build.

## Steps

### Step 1: Write the two tests first (one must fail)

In `DataTests.swift`, directly after
`test_M0S1_RD2_entryDeletionRetainsMarginsAndSharedMedia`, add two tests inside
the same suite:

1. `entryDeletedInsideUndoWindowKeepsItsMediaBytes`: in-memory container; one
   `Media` with `data = Data([1,2,3])`; one `Entry` with `mediaID = media.id`
   and `deletedAt = now.addingTimeInterval(-60)` where
   `let now = Date(timeIntervalSince1970: 1_800_000_000)`; insert, save, then
   `try RowMerger(context: context).run(now: now)`. Expect
   `media.deletedAt == nil` and `media.data == Data([1,2,3])`.
2. `entryDeletedAfterUndoWindowReleasesItsMedia`: same fixture with
   `deletedAt = now.addingTimeInterval(-601)`. Expect `media.deletedAt != nil`
   and `media.data == nil`.

`run(now:)` does not exist yet, so the package will not compile. That is the
expected state for this step.

**Verify**: `swift test --package-path Madar/Packages/MadarData 2>&1 | tail -5` → a compile error naming `run(now:)` (or an extra-argument error at the new call sites).

### Step 2: Thread a clock through the pass and add the grace check

In `RowMerger.swift`:

1. Add next to the other static members of `RowMerger`:
   ```swift
   /// A deleted diary entry can be undone for this long (`DurableCommandAdapter` sets the same 600 s on the
   /// receipt); its media stays untouched until then, and the receipt sweep clears it afterwards.
   public static let entryMediaUndoGrace: TimeInterval = 600
   ```
2. Change `run()` to `run(now: Date = Date())` and pass it on:
   `try Self.reconciled(original, now: now)`.
3. Change `reconciled(_ input: [DataRecord])` to
   `reconciled(_ input: [DataRecord], now: Date = Date())`.
4. Inside `reconciled`, find the call to `cascade` (run
   `grep -n "cascade(&" Madar/Packages/MadarData/Sources/MadarData/RowMerger.swift`;
   there must be exactly one call) and pass `now: now`.
5. Change `cascade(_ rows: inout [DataRecord])` to take `now: Date`, and wrap
   only the `if parent.model == "Entry" { ... }` block so it is skipped while
   the entry is still undoable:
   ```swift
   if parent.model == "Entry", parent.deletedAt! <= now.addingTimeInterval(-Self.entryMediaUndoGrace) {
   ```
   Leave the `children` loop below it (HifzSession → PageGrade/MistakeEvent)
   exactly as it is.

**Verify**: `swift test --package-path Madar/Packages/MadarData` → exit 0; both new tests pass; the existing `test_M0S1_RD2_*` tests still pass.

### Step 3: Confirm the import path still passes

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter DayOneImportPersistenceTests` → exit 0.

## Test plan

- The two tests in Step 1 (inside-window keeps bytes; after-window releases
  them). The 60 s and 601 s values come from the 600 s undo rule, not from the
  implementation.
- Pattern: `test_M0S1_RD2_entryDeletionRetainsMarginsAndSharedMedia` in the
  same file.
- Verification: the two commands in Steps 2 and 3.

## Done criteria

- [ ] `swift test --package-path Madar/Packages/MadarData` exits 0 and reports the two new tests as passed
- [ ] `swift test --package-path Madar/Packages/MadarCommands --filter DayOneImportPersistenceTests` exits 0
- [ ] `grep -c "entryMediaUndoGrace" Madar/Packages/MadarData/Sources/MadarData/RowMerger.swift` prints 2 or more
- [ ] `git diff --check` prints nothing
- [ ] `git status --short` shows no modified file outside the two in-scope files (files that were already modified before you started do not count; list them in your report)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" do not match the live code.
- `grep -n "cascade(&"` finds zero or more than one call site.
- An existing MadarData or Day One import test fails after Step 2 and the
  failure is not one of your two new tests.
- Making the tests pass appears to need a change in `DiaryMutationHandler.swift`,
  `DurableCommandAdapter.swift`, or any schema file.
- `parent.deletedAt` is not a `Date?` on `DataRecord` (the excerpt at line 233
  uses `parent.deletedAt!`; if that is no longer true, stop).

## Maintenance notes

- The 600 s value now lives in two places: `RowMerger.entryMediaUndoGrace` and
  `DurableCommandAdapter.swift:451`. If the undo window ever changes, change
  both; a follow-up could make the adapter read the constant.
- This change touches a path that deletes stored bytes. The repository protocol
  requires one focused review of such changes: the reviewer should confirm that
  the after-window sweep (`purgeExpiredDiaryEntryMedia`) still clears the media
  and that nothing else relied on the merge pass clearing it immediately.
- Not covered here: `DayOneImportHandler.undo` tombstones the rows an import
  created, including their media, through its own summary; that path is
  unchanged.
- `Madar/Packages/MadarSync` also calls `RowMerger(context:).run()`; sync is
  inactive in v1 and gets the default `now`.
