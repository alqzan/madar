# Plan 002: The launch sweep removes plaintext backup folders left in the temporary directory

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/App/TemporaryFilesCleanup.swift Madar/Tests/Integration/AppInboxLifecycleTests.swift`
> If either file changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

Making or opening an encrypted backup writes the whole archive — diary text,
photos, voice, money rows — as one unencrypted file `archive.aar` inside a
folder `MadarBackup-<UUID>` in the app's temporary directory. The folder is
removed by a `defer` when the function returns. If the app is killed in the
middle (out of memory during a large backup, a force quit, a crash), the
unencrypted archive stays on disk. The app already has a launch sweep for its
own leftovers in the temporary directory, but the sweep's name list does not
include this folder or the legacy-import read copy, so they are never removed.
After this plan both are swept like the app's other leftovers.

## Current state

All paths are relative to the repository root. The repository root folder name
contains Arabic characters and a space: always quote it in shell commands.

- `Madar/App/TemporaryFilesCleanup.swift` — the launch sweep (called from
  `Madar/App/MadarApp.swift:138`). Whole file today:

```swift
/// B1-17: unpacked books, import caches and export folders were left in the temporary directory when a screen was closed
/// abnormally. At launch, items this app creates there (known names only) that are over an hour old are removed.
enum TemporaryFilesCleanup {
    static let knownPrefixes = ["MadarReader", "DayOneImport", "DiaryExport", "MadarImport-", "MadarSearch-", "DiaryPreview-", "Journal.zip"]
    static let knownSuffixes = [".epub", ".m4a"]

    @discardableResult
    static func run(in directory: URL = FileManager.default.temporaryDirectory, now: Date = Date(), olderThan age: TimeInterval = 3600) -> Int {
        ...
            let ours = knownPrefixes.contains { name.hasPrefix($0) }
                || (knownSuffixes.contains { name.hasSuffix($0) } && UUID(uuidString: item.deletingPathExtension().lastPathComponent) != nil)
            guard ours, let modified = (try? item.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate,
                  now.timeIntervalSince(modified) > age else { continue }
            if (try? fileManager.removeItem(at: item)) != nil { removed += 1 }
```

- The two folders the list misses (read-only context, do NOT modify these files):
  - `Madar/Packages/MadarData/Sources/MadarData/Backup.swift:162` creates
    `temporaryDirectory/MadarBackup-<UUID>`; `encodeArchive` (line 164) and
    `decodeArchive` (line 175) write the unencrypted `archive.aar` into it and
    remove the folder only with `defer { try? FileManager.default.removeItem(at:directory) }`.
  - `Madar/Packages/MadarData/Sources/MadarData/LegacyV1Reader.swift:14` creates
    `temporaryDirectory/MadarLegacyRead-<UUID>`, a read copy of the old app's store.

- `Madar/Tests/Integration/AppInboxLifecycleTests.swift:298-316` — the existing
  XCTest for the sweep, in the class `TemporaryFilesCleanupTests`:

```swift
/// B1-17
final class TemporaryFilesCleanupTests: XCTestCase {
    func testOnlyOldItemsWithKnownNamesAreRemoved() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("CleanupFixture-\(UUID())", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        func make(_ name: String, age: TimeInterval) throws -> URL {
            let url = root.appendingPathComponent(name)
            try Data("x".utf8).write(to: url)
            try FileManager.default.setAttributes([.modificationDate: Date().addingTimeInterval(-age)], ofItemAtPath: url.path)
            return url
        }
        ...
        XCTAssertEqual(TemporaryFilesCleanup.run(in: root), 2)
```

Design decision already made for you: do NOT add a stricter file-protection
class to the backup folder. The app has no data-protection entitlement, so
these files already get the system default class, and backups may run from a
background task while the phone is locked; a stricter class would make those
backups fail. The fix is the sweep only.

## Commands you will need

Run from the repository root unless a `cd` is shown.

| Purpose | Command | Expected on success |
|---|---|---|
| Is the simulator busy? | `pgrep -fl xcodebuild` | no output (if there is output, wait and retry; see STOP conditions) |
| Run the sweep tests | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=390840AD-4FF0-476F-8E1D-E0C521A58E45' -derivedDataPath DerivedData -resultBundlePath Artifacts/results/PLAN002-cleanup-$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test -only-testing:MadarTests/TemporaryFilesCleanupTests` | `** TEST SUCCEEDED **`, 2 tests executed, 0 failures |
| Whitespace | `git diff --check` | no output |

Use only the simulator id shown above. Never create, erase or reset a
simulator, and never run `xcodegen` or `make generate` for this plan (no file
is added, so the project file does not change).

## Scope

**In scope** (the only files you may modify):
- `Madar/App/TemporaryFilesCleanup.swift`
- `Madar/Tests/Integration/AppInboxLifecycleTests.swift`

**Out of scope** (do NOT touch):
- `Backup.swift`, `LegacyV1Reader.swift`, `MadarApp.swift` — behaviour there is
  correct; only the sweep's list is incomplete.
- Any file whose name contains `Money`, `Bank` or `Turath`.
- `Madar/Madar.xcodeproj`, `Madar/project.yml`, `docs/PROGRESS.md`,
  `docs/DECISIONS.md`, `CLAUDE.md`, `AGENTS.md`.

## Git workflow

- Work on `main` (the repository protocol forbids a branch per task) unless your
  operator placed you in a worktree.
- One commit:
  `[OWNER] <what is now true, with test counts and the result bundle name> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`.
- Do NOT push, and do not archive or upload a build.

## Steps

### Step 1: Add the failing test

In `AppInboxLifecycleTests.swift`, inside `TemporaryFilesCleanupTests`, add a
second method `testInterruptedBackupAndLegacyReadFoldersAreRemoved`:

- Create a fixture root exactly as the existing test does.
- Create four **directories** under it, each containing one file
  `archive.aar` with a few bytes:
  `MadarBackup-<UUID>` aged 7200 s, `MadarBackup-<UUID>` aged 60 s,
  `MadarLegacyRead-<UUID>` aged 7200 s, and `SomeoneElse-<UUID>` aged 7200 s.
  Set the age with `FileManager.default.setAttributes([.modificationDate: ...], ofItemAtPath:)`
  on the **directory** after writing the file inside it (writing a file updates
  the directory's date).
- Assert `TemporaryFilesCleanup.run(in: root) == 2`, that the two old
  `MadarBackup-` / `MadarLegacyRead-` directories no longer exist, and that the
  fresh `MadarBackup-` directory and the `SomeoneElse-` directory still exist.

**Verify**: run the sweep tests command → `** TEST FAILED **` with the new test failing on the count (0 instead of 2) and the existing test passing.

### Step 2: Extend the name list

In `TemporaryFilesCleanup.swift`, add `"MadarBackup-"` and `"MadarLegacyRead-"`
to `knownPrefixes`, and extend the doc comment with one sentence: interrupted
backup and legacy-read folders (which hold unencrypted data) are included.
Change nothing else in the file.

**Verify**: run the sweep tests command again (it needs a new result bundle name; the `$(date +%s)` in the command provides one) → `** TEST SUCCEEDED **`, 2 tests, 0 failures.

## Test plan

- New: `testInterruptedBackupAndLegacyReadFoldersAreRemoved` (old folders
  removed, fresh folder kept, unknown name untouched).
- Pattern: `testOnlyOldItemsWithKnownNamesAreRemoved` in the same class.
- The one-hour age threshold is the sweep's documented rule; the 7200 s / 60 s
  fixtures sit clearly on either side of it.

## Done criteria

- [ ] The sweep tests command prints `** TEST SUCCEEDED **` with 2 tests executed and 0 failures; report the result bundle path
- [ ] `grep -c '"MadarBackup-"' Madar/App/TemporaryFilesCleanup.swift` prints 1
- [ ] `grep -c '"MadarLegacyRead-"' Madar/App/TemporaryFilesCleanup.swift` prints 1
- [ ] `git diff --check` prints nothing
- [ ] `git status --short` shows no modified file outside the two in-scope files (files already modified before you started do not count; list them in your report)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" do not match the live code.
- `pgrep -fl xcodebuild` still shows another build or test after you waited 15
  minutes (another session shares this simulator; do not run alongside it and
  do not kill its process).
- The build fails for a reason unrelated to your two files (another session may
  have uncommitted work in the tree); report the first error, do not fix it.
- The test only passes if you change the one-hour threshold or the matching
  logic in `run`.

## Maintenance notes

- Any new temporary folder name the app introduces must be added to
  `knownPrefixes`; the reviewer should check that the two new prefixes cannot
  match a file the app still needs (both folders are created and removed inside
  one function call).
- The sweep runs only at launch and only removes items older than an hour, so a
  leftover can stay on disk until the next launch. Shortening that would need
  the backup code to own its cleanup differently; it is deliberately not part of
  this plan.
- Deferred on purpose: a stricter file-protection class for the backup folder
  (it would break background backups while the phone is locked).
