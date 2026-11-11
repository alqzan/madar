# Plan 008: The bank-message screen ignores a second tap while a command is running

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/App/MoneyMessagesView.swift`
> If the file changed, compare the "Current state" excerpt against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

On «رسائل البنك», every button (confirm ✓, ignore, delete, apply statement,
link refund, «اعتمد الواضح», paste) starts its command in a new `Task` with
nothing that remembers a command is already running. The screen reloads on the
main thread after each command, so with many messages the row stays on screen
long enough to be tapped twice. The first command succeeds; the second one is
refused by the handler (`MoneyMutationHandler.swift:363` throws
`MoneyCommandError.alreadyConfirmed` when `reviewState == "ok"`), and the
screen then shows «لم يُحفظ: …» although the movement **was** saved. The owner
reads that as a failed save. After this plan a repeated tap on the same button
while its command is in flight does nothing.

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell).

`Madar/App/MoneyMessagesView.swift:16-29` holds the view state, among it:

```swift
    @State private var note: String?
    @State private var deleteFailureID: UUID?
    @State private var injectedDeleteFailure = false
```

`Madar/App/MoneyMessagesView.swift:363-394`:

```swift
    private func run(_ name: String, _ payload: [String: MadarCore.JSONValue], successNote: String? = nil) {
        Task {
            do {
                #if DEBUG
                ... (a DEBUG-only injected delete failure; leave it as is)
                #endif
                try await app.executeMoneyCommand(name, payload: payload)
                if name == "money.deleteTransaction" { deleteFailureID = nil }
                note = successNote
            } catch {
                if name == "money.deleteTransaction" {
                    if case .string(let rawID)? = payload["id"] { deleteFailureID = UUID(uuidString: rawID) }
                    note = nil
                }
                else if name == "money.applyStatement" { note = "المبلغ يختلف عن كشف قريب لهذه البطاقة؛ راجع البطاقة أو تجاهل الرسالة" }
                else { note = "لم يُحفظ: " + madarUserMessage(error) }
            }
            load()
        }
    }
```

Callers pass the row in `payload["id"]` for single-row commands
(`money.confirmTransaction`, `money.deleteTransaction`, `money.ignoreMessage`,
`money.applyStatement`, `money.linkRefund`); `money.confirmClear` passes
`"ids"`, `money.pasteBankMessages` passes `"messages"`, `money.attachTail`
passes its own payload.

## Commands you will need

Run from the repository root. Before any `xcodebuild`, run
`pgrep -fl xcodebuild`; if another build is running, wait for it (never kill it).

| Purpose | Command | Expected on success |
|---|---|---|
| App compiles | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build` | `** BUILD SUCCEEDED **` |
| Screen's UI tests | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=390840AD-4FF0-476F-8E1D-E0C521A58E45' -derivedDataPath DerivedData -resultBundlePath Artifacts/results/PLAN008-$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test -only-testing:MadarUITests/MoneyMessagesUITests` | `** TEST SUCCEEDED **`, 7 tests executed (the count at the planned commit) |
| Whitespace | `git diff --check` | no output |

Use only the simulator with that id. Never create, erase or boot another one.

## Scope

**In scope**: `Madar/App/MoneyMessagesView.swift` — one new `@State` line and
the function `run` only.

**Out of scope**: `load()` and `MoneyMessagesModels.swift` (moving the load off
the main thread is a separate, larger item in the backlog of
`plans/README.md`); `MoneyMutationHandler.swift` and every file under
`Madar/Packages/` (no money rule changes); the DEBUG block inside `run`.

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Remember which commands are running

Add next to the other state (after `injectedDeleteFailure`):

```swift
    /// Commands in flight, keyed by name and row, so a second tap on the same button is ignored instead of
    /// reaching the handler as a duplicate and showing a false «لم يُحفظ».
    @State private var inFlight: Set<String> = []
```

Change `run` so that it starts with:

```swift
        let key = name + "|" + (payload["id"].map { "\($0)" } ?? "")
        guard inFlight.insert(key).inserted else { return }
```

and, inside the `Task`, directly **before** the final `load()` line, add:

```swift
            inFlight.remove(key)
```

Do not change anything else in the function. Commands without an `"id"`
(`confirmClear`, `pasteBankMessages`, `attachTail`) get the key `name|`, so a
second identical press while the first is running is also ignored.

**Verify**: the app build command → `** BUILD SUCCEEDED **`.

### Step 2: Run the screen's UI tests

**Verify**: the UI test command → `** TEST SUCCEEDED **` with the same number
of executed tests as before your change (7 at the planned commit). Report the
executed count and the result bundle path.

## Test plan

No new automated test. A double tap needs the second tap to land while the
first command is still running; a UI test for that depends on timing and would
be flaky, and the view has no unit-testable seam. Say this in your report. The
existing seven `MoneyMessagesUITests` prove single taps still work.

## Done criteria

- [ ] `grep -c "inFlight" Madar/App/MoneyMessagesView.swift` prints 3
- [ ] The app build prints `** BUILD SUCCEEDED **`
- [ ] `MoneyMessagesUITests` pass with a non-zero executed count equal to the count before the change
- [ ] `git diff --check` prints nothing; only `Madar/App/MoneyMessagesView.swift` is modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- `run` no longer matches the excerpt (for example it already has a guard).
- The compiler reports that `inFlight` cannot be mutated inside the `Task`
  (actor isolation): do not add `nonisolated`, locks or a new class; report it.
- A `MoneyMessagesUITests` case fails after the change and passes without it.
- A UI test fails for an unrelated reason twice: record it and stop; do not
  erase the simulator or its stores.

## Maintenance notes

- This removes the false error; it does not make the screen faster. The real
  cause of the long window (the load and the dry-run confirm on the main
  thread) is the first row of "Needs measurement or a larger refactor" in
  `plans/README.md`.
- If a row-level "busy" look is wanted later, `inFlight` is the state to read.
