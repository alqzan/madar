# Plan 004: A cleared diary draft stays cleared, and a recording that ends on its own releases the audio session

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/App/DiaryTextEditor.swift Madar/App/DiaryVoiceController.swift Madar/Tests/Integration/DiaryEditorIntegrationTests.swift`
> If any of these files changed since this plan was written, compare the
> "Current state" excerpts against the live code before proceeding; on a
> mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none
- **Category**: bug
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

Two small defects in the diary writing page, both on paths the owner uses daily.

1. The editor saves its draft 500 ms after the last keystroke. When the page is
   closed, a pending save is flushed only if the text is not empty. So if the
   user deletes everything and leaves within half a second, the pending save of
   the empty text is cancelled and the stored draft keeps its old words; next
   time the page opens it shows them again as a restored draft.
2. Recording switches the system audio session to record mode and activates it.
   It is deactivated only in `stop()`. When a take ends by itself (the system
   ends it, or the encoder fails) or when starting fails after activation, the
   session stays active in record mode: other apps' audio is not told to resume.

## Current state

All paths are relative to the repository root. The repository root folder name
contains Arabic characters and a space: always quote it in shell commands.

- `Madar/App/DiaryTextEditor.swift` — the SwiftUI writing page.
- `Madar/App/DiaryVoiceController.swift` — recorder controller used by that page.
- `Madar/App/AppDiaryEditorService.swift` — read-only context: `draft(margin:)`
  (line 24) and `saveDraft(id:text:day:margin:writingDay:)` (line 32), which
  sends the `diary.saveDraft` command.
- `Madar/Tests/Integration/DiaryEditorIntegrationTests.swift` — XCTest class
  `DiaryEditorIntegrationTests`.

Draft flush on leaving, `DiaryTextEditor.swift:120-123`:

```swift
        .onDisappear {
            // B2-2: leaving never loses words; a pending 500 ms draft write is flushed unless the page was just saved.
            if loaded, !saving, !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { DiaryDraftFlush.run { try? await persistDraft() } }
            draftTask?.cancel(); savedDayTask?.cancel(); voice?.cancelConversion(); voice?.cancelDownload(); if let voice { Task { await voice.stop() } } }
```

The save it would call already handles an emptied draft, `DiaryTextEditor.swift:336-341`:

```swift
    private func persistDraft() async throws {
        guard let writingDay else { throw CocoaError(.coderInvalidValue) }
        guard hasDraftRecord || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return }
        try await AppDiaryService(app: app).saveDraft(id: draftID, text: text, day: day, margin: margin, writingDay: writingDay)
        hasDraftRecord = true
    }
```

`hasDraftRecord` is a `@State` Bool (line 24); it becomes true when a stored
draft is loaded (line 57) or after the first save (line 340).

Recording start, `DiaryVoiceController.swift:87-100`:

```swift
        do {
            try AppDiaryService(app: app).authorizeRead()
            app.diaryPlayback.stop()
            try AVAudioSession.sharedInstance().setCategory(.playAndRecord, mode: .default, options: [.defaultToSpeaker])
            try AVAudioSession.sharedInstance().setActive(true)
            ...
            try startChunk()
            recording = true
            startMetering()
            observeAudioSession()
        } catch { recording = false; message = madarUserMessage(error) }
    }
```

The only deactivation, in `stop()`, `DiaryVoiceController.swift:130-137`:

```swift
    func stop() async {
        guard let recorder else { return }; recording = false
        stopMetering(); stopObservingAudioSession(); elapsedSeconds = Int(recorder.currentTime.rounded(.down))
        let url = recorder.url; recorder.stop(); self.recorder = nil
        await storeChunk(url: url, successful: true)
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
        if let lastMedia { await transcribe(lastMedia) }
    }
```

The two endings that never deactivate, `DiaryVoiceController.swift:352-371`:

```swift
extension DiaryVoiceController: AVAudioRecorderDelegate {
    nonisolated func audioRecorderDidFinishRecording(_ recorder: AVAudioRecorder, successfully flag: Bool) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            if self.recorder === recorder { self.recorder = nil; self.recording = false; self.stopMetering(); self.stopObservingAudioSession() }
            if !flag { self.message = "توقف التسجيل؛ نحفظ المقطع الذي اكتمل" }
            await self.storeChunk(url: url, successful: flag)
            if !self.recording, let media = self.lastMedia { await self.transcribe(media) }
        }
    }
    nonisolated func audioRecorderEncodeErrorDidOccur(_ recorder: AVAudioRecorder, error: Error?) {
        let url = recorder.url
        Task { @MainActor [weak self] in
            guard let self else { return }
            self.recording = false; self.recorder = nil; self.stopMetering()
            self.message = "توقف التسجيل بسبب خطأ؛ نحفظ ما أمكن من الصوت"
            await self.storeChunk(url: url, successful: false)
        }
    }
}
```

Note: `audioRecorderDidFinishRecording` also fires after a normal `stop()`; in
that case `self.recorder` is already nil, so the `=== recorder` branch is
skipped. The fix below deactivates in the delegate only when that branch ran.

Integration test fixture to copy, `DiaryEditorIntegrationTests.swift:10-17`:

```swift
    func testDraftPhotoAndAudioPersistWithTheirEntryAndOriginalBytes() async throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "DiaryMedia-\(UUID())")
        defer { try? FileManager.default.removeItem(at: root) }
        let container = try MadarContainerFactory.makeLocal(at: root.appending(path: "Data")), app = try AppSession(container: container, groupDirectory: root)
        app.authorizeProtectedData(); let service = AppDiaryService(app: app), day = try service.currentDay(), id = UUID()
        try await service.saveDraft(id: id, text: "مسودة لا تضيع", day: "today", margin: nil, writingDay: day)
        XCTAssertEqual(try service.draft(margin: nil)?.text, "مسودة لا تضيع")
```

## Commands you will need

Run from the repository root unless a `cd` is shown.

| Purpose | Command | Expected on success |
|---|---|---|
| Is the simulator busy? | `pgrep -fl xcodebuild` | no output (if there is output, wait and retry; see STOP conditions) |
| Run the diary editor integration tests | `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=390840AD-4FF0-476F-8E1D-E0C521A58E45' -derivedDataPath DerivedData -resultBundlePath Artifacts/results/PLAN004-diary-$(date +%s).xcresult CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES test -only-testing:MadarTests/DiaryEditorIntegrationTests` | `** TEST SUCCEEDED **`, 0 failures |
| Whitespace | `git diff --check` | no output |

Use only the simulator id shown above. Never create, erase or reset a
simulator, and never run `xcodegen` or `make generate` for this plan (no file
is added).

## Scope

**In scope** (the only files you may modify):
- `Madar/App/DiaryTextEditor.swift` — the one condition on line 122
- `Madar/App/DiaryVoiceController.swift`
- `Madar/Tests/Integration/DiaryEditorIntegrationTests.swift`

**Out of scope** (do NOT touch):
- `DiaryInlineComposer.swift` (the inline field has its own draft path),
  `AppDiaryEditorService.swift`, `DiaryMediaCard.swift`, and every file in
  `Madar/Packages`.
- The user-visible Arabic strings: do not reword any message.
- Any file whose name contains `Money`, `Bank` or `Turath`; `docs/PROGRESS.md`,
  `docs/DECISIONS.md`, `CLAUDE.md`, `AGENTS.md`, `Madar/Madar.xcodeproj`.

## Git workflow

- Work on `main` (the repository protocol forbids a branch per task) unless your
  operator placed you in a worktree.
- One commit:
  `[OWNER] <what is now true, with test counts and the result bundle name> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`.
- Do NOT push, and do not archive or upload a build.

## Steps

### Step 1: Pin the service behaviour the fix relies on

In `DiaryEditorIntegrationTests.swift`, add a method
`testSavingAnEmptiedDraftLeavesNothingToRestore` using the fixture lines quoted
above (own temp-folder name): save a draft with the text `"سطر سيُمسح"`, assert
`draft(margin: nil)?.text` equals it, then save the same `id` with `text: ""`,
then assert `XCTAssertEqual(try service.draft(margin: nil)?.text ?? "", "")`.

This test does not exercise the view; it proves that the save the view will now
perform on leaving really clears the stored words.

**Verify**: run the diary editor integration tests command → `** TEST SUCCEEDED **`, with the new test passing. (If the new test fails or the empty save throws, that is a STOP condition: the view fix would not help.)

### Step 2: Flush an emptied draft on leaving

In `DiaryTextEditor.swift` line 122, change the condition so a draft that
already has a stored record is flushed even when the text is now empty:

```swift
            if loaded, !saving, hasDraftRecord || !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { DiaryDraftFlush.run { try? await persistDraft() } }
```

Change nothing else on that line or the next one.

**Verify**: `grep -c "if loaded, !saving, hasDraftRecord || " Madar/App/DiaryTextEditor.swift` → 1.

### Step 3: Release the audio session on every ending

In `DiaryVoiceController.swift`:

1. Add a private helper in the class body near `stop()`:
   ```swift
   /// Every way a take ends hands the audio session back, so other apps' audio can resume.
   private func endAudioSession() { try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation) }
   ```
2. In `stop()`, replace the `try? AVAudioSession.sharedInstance().setActive(false, ...)`
   line with `endAudioSession()`.
3. In the start function (the `do { ... } catch` quoted above): declare
   `var sessionActive = false` immediately before the `do`, set
   `sessionActive = true` on the line after `setActive(true)`, and change the
   catch to
   `catch { recording = false; if sessionActive { endAudioSession() }; message = madarUserMessage(error) }`.
   (Deactivating when the session was never activated could stop diary
   playback that is still running, hence the flag.)
4. In `audioRecorderDidFinishRecording`: record whether this callback ended the
   take, and deactivate only then, after the chunk is stored:
   ```swift
            let endedHere = self.recorder === recorder
            if endedHere { self.recorder = nil; self.recording = false; self.stopMetering(); self.stopObservingAudioSession() }
            if !flag { self.message = "توقف التسجيل؛ نحفظ المقطع الذي اكتمل" }
            await self.storeChunk(url: url, successful: flag)
            if endedHere, !self.recording { self.endAudioSession() }
            if !self.recording, let media = self.lastMedia { await self.transcribe(media) }
   ```
5. In `audioRecorderEncodeErrorDidOccur`: add
   `if !self.recording { self.endAudioSession() }` as the last statement of the
   task, after `storeChunk`.

**Verify**: `grep -c "endAudioSession()" Madar/App/DiaryVoiceController.swift` → 5 (one definition, four calls), and `grep -c "setActive(false" Madar/App/DiaryVoiceController.swift` → 1.

### Step 4: Build and run the tests

**Verify**: run the diary editor integration tests command (it compiles the app) → `** TEST SUCCEEDED **`, 0 failures.

## Test plan

- New integration test `testSavingAnEmptiedDraftLeavesNothingToRestore`
  (Step 1). Expected value comes from the product behaviour: an emptied page
  has nothing to restore.
- Not covered by an automated test: the view's `onDisappear` branch and the
  audio-session endings (the simulator cannot end a take from the system side).
  State this plainly in your report as "not verified by a test".
- Pattern: the first test in `DiaryEditorIntegrationTests.swift`.

## Done criteria

- [ ] The diary editor integration tests command prints `** TEST SUCCEEDED **` with 0 failures; report the executed test count and the result bundle path
- [ ] `grep -c "if loaded, !saving, hasDraftRecord || " Madar/App/DiaryTextEditor.swift` prints 1
- [ ] `grep -c "endAudioSession()" Madar/App/DiaryVoiceController.swift` prints 5
- [ ] `git diff --check` prints nothing
- [ ] `git status --short` shows no modified file outside the three in-scope files (files already modified before you started do not count; list them in your report)
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The excerpts in "Current state" do not match the live code.
- `pgrep -fl xcodebuild` still shows another build or test after you waited 15
  minutes (another session shares this simulator; do not run alongside it and
  do not kill its process).
- The Step 1 test fails: saving an empty text for an existing draft throws, or
  the old text is still returned. The fix then belongs in the command handler,
  which is out of scope.
- After a successful page save, `saving` is reset to `false` before the page
  disappears (read the function that commits the page in `DiaryTextEditor.swift`;
  the comment on line 121 says the flush is skipped when "the page was just
  saved"). If `saving` can be false at that point, the new condition would
  re-save a committed draft: stop.
- The build fails for a reason unrelated to your files (another session may
  have uncommitted work in the tree); report the first error, do not fix it.

## Maintenance notes

- A reviewer should try by hand, on a build: type a line, wait a second, delete
  it, leave immediately, reopen — no «مسودة مستعادة». And: start a recording,
  receive a call or trigger Siri, return — other audio resumes.
- Observed while reading, not changed here: after a normal `stop()`, the
  delegate callback calls `storeChunk` a second time for the same file. It is
  presumably a no-op once the file has moved; worth one look in review.
- The flush still swallows a failed save (`try?`). Surfacing it needs a place
  to show a message after the page has closed; left for a later change.
