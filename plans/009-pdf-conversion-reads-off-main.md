# Plan 009: PDF conversion reads the book off the main thread

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/App/MihbaraConversions.swift Madar/App/AppMihbaraService.swift`
> If either changed, compare the "Current state" excerpts against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: perf
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

Turning a PDF book into a readable book («حوّله إلى نص») starts by reading the
whole PDF from the store and computing its SHA-256. That read runs on the main
thread, because the class is `@MainActor` and the call is synchronous. For a
large scanned book the screen freezes for the length of the read just after
the owner taps the button. The service already has an off-main version of the
same read, written for opening a book; conversion simply does not use it.

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell).

`Madar/App/MihbaraConversions.swift:44`: `@MainActor @Observable final class MihbaraConversions {`

`Madar/App/MihbaraConversions.swift:199-204`:

```swift
    /// Reads every page (embedded text first, on-device OCR otherwise) and writes the EPUB to a private folder.
    private func convert(_ book: MihbaraBook, app: AppSession) async throws -> (URL, PDFBookEPUB.Summary) {
        guard authorized(app) else { throw DataError.authenticationFailed }
        let bytes = try AppMihbaraService(app: app).pdfData(for: book)
        let reader = PDFBookTextReader(data: bytes, language: book.language)
        let total = try await reader.pageCount()
```

`Madar/App/AppMihbaraService.swift:297-303` (the exemplar to use):

```swift
    /// Opening a book: the checked read and the SHA-256 of a large file run off the main actor, so the tap never freezes the screen.
    func pdfDataOffMain(for book: MihbaraBook) async throws -> Data {
        let container = app.container
        return try await Task.detached(priority: .userInitiated) {
            try Self.verifiedBookData(container: container, for: book, allowedFormats: ["pdf", "pdfScanned"])
        }.value
    }
```

Both functions return the same verified bytes; only the thread differs.

## Commands you will need

Run from the repository root. Before any `xcodebuild`, run
`pgrep -fl xcodebuild`; if another build is running, wait for it (never kill it).

| Purpose | Command | Expected on success |
|---|---|---|
| App compiles | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |
| Find conversion tests | `grep -n "func test.*[Cc]onver" Madar/Tests/Integration/MihbaraHomeIntegrationTests.swift` | zero or more test names |
| Run one integration test | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=390840AD-4FF0-476F-8E1D-E0C521A58E45' -derivedDataPath DerivedData -resultBundlePath Artifacts/results/PLAN009-$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test -only-testing:MadarTests/MihbaraHomeIntegrationTests/<testName>` | `** TEST SUCCEEDED **` |
| Whitespace | `git diff --check` | no output |

## Scope

**In scope**: `Madar/App/MihbaraConversions.swift`, line 202 only.

**Out of scope**: `AppMihbaraService.swift` (read-only exemplar), the per-page
`savePage` and `loadCheckpoint` calls later in `convert` (an auditor reported
them as main-thread work too; they need their own measurement), every Turath
file (`MihbaraTurathView.swift`, `TurathBook.swift`), `PDFBookTextReader`.

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Use the off-main read

Replace line 202

```swift
        let bytes = try AppMihbaraService(app: app).pdfData(for: book)
```

with

```swift
        let bytes = try await AppMihbaraService(app: app).pdfDataOffMain(for: book)
```

**Verify**: the app build command → `** BUILD SUCCEEDED **`.

### Step 2: Run the conversion tests that exist

Run the "Find conversion tests" command. For each test name it prints, run the
integration test command with that name (one `xcodebuild` at a time).

**Verify**: each prints `** TEST SUCCEEDED **` with one executed test. If the
grep prints nothing, say so in your report: the build is then the only check.

## Test plan

No new test: the bytes returned are identical and behaviour is unchanged; only
the thread differs. Existing conversion tests, if any, are the regression check.

## Done criteria

- [ ] `grep -c "pdfData(for: book)" Madar/App/MihbaraConversions.swift` prints 0
- [ ] `grep -c "pdfDataOffMain(for: book)" Madar/App/MihbaraConversions.swift` prints 1
- [ ] The app build prints `** BUILD SUCCEEDED **`
- [ ] Every conversion test found in Step 2 passes (or none exists, and the report says so)
- [ ] `git diff --check` prints nothing; only `Madar/App/MihbaraConversions.swift` is modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- Line 202 does not match the excerpt.
- The compiler rejects the call (for example `MihbaraBook` is not `Sendable`
  in this context): do not add `@unchecked Sendable` or `nonisolated(unsafe)`;
  report the error text.

## Maintenance notes

- `pdfData(for:)` may now have no caller in the app. Leave it: the repository
  protocol says retained unused code need not be deleted in a cleanup pass.
- The rest of `convert` still touches the store on the main thread once per
  page; measure before changing it.
