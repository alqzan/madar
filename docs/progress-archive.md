## Handover — review files received — 2026-10-10 — root

Done: read all attachments; copied protocol and handoff; extracted 25 sections; RD2 conflict resolved by owner. Earlier automatic prayer aging, multi-process SQLite proof and visible disabled cloud setting now conflict with V1.

Verified: file reads, exact AGENTS/CLAUDE match, current git status (no commits). Earlier logs: services integration v3 passed 10 tests; first services UI run failed 2 tests; fixes exist but rerun pending. These are not current milestone acceptance.

Not verified: full new contract compliance, physical iPhone run, notifications/widgets/Live Activities, actual cloud sync, Quran licenses, real user migration. Prior agents ended with tool-reported usage errors; no reset was consumed.

Current check: updated defaults passed 34 tests, then integrated RA1/RD2 passed 38 tests (Artifacts/review-local-retention-integrated.log). Unfinished M2 QuranRoom.swift is preserved and excluded from M0 target. Lock persistence passed in actual simulator checks. Backup UI still fails matching/export at the first assertion (backup-fixture-check.log); named native-export attachments from that failed flow are failure-state images. Top reviewer requested changes, not acceptance. Fresh diagnostic fix is being tested with failure collection disabled to avoid the previous 600-second diagnostic stall. Production password rules are not weakened.

Baseline snapshot: preserve the inherited app source as a separate local commit to permit isolated branch/worktree review. This is a record of existing implementation, not acceptance of old contracts. Build products, font binaries, output/ and tmp/ stay excluded. Earlier builders' actual model tiers are not inferred from inherited files.

Next: Top architecture note, current build/UI check, then scoped data/inbox fixes. Recommended tiers: Sol xhigh for architecture/reviews; Sol high for production paths. Human instructions remain above attached documents.

## Handover — M0-T04 lean shell — 2026-10-10 — claude (Sonnet, standard)

Done: quick check of Codex work (see Last checked). M0-T04 on branch `m0-s2-lean-shell` (not merged): glass-only native `TabView` (RL8); cut keys (`core.fontScale`, `core.motion`, `core.roomIdentity`, `tabbar.*`) removed from `AppSession.supportedKeys` and hard-coded to defaults in `TabShell.swift`; entry points to saved presets and sync settings removed from `CustomizeMadar.swift` (code kept for compatibility, `savePreset` unreachable). Stored values of cut keys are now ignored.
Verified: `xcodebuild ... generic/platform=iOS Simulator build` → `** BUILD SUCCEEDED **`. UI tests testFirstRunAndSettingsRenderWithoutUnbuiltRooms, testThemePersistenceResetAndUndoThroughUI, testLightDarkAndAccessibilityScreenshots → `Executed 3 tests, with 0 failures`, `** TEST SUCCEEDED **`.
Not verified: AX3 screenshot compared against canonical design by eye; physical iPhone; settings-schema `availability: v2` flags in the JSON were not changed here; `savePreset`/PresetsView files still exist.
For the next agent:
1. Section review of `m0-s2-lean-shell` (Standard), then merge. Possible merge conflict in `AppSession.swift` with the inbox branch.
2. Top-tier review of `m0-s1-command-inbox` (846e1bb) before merging: concurrency and data path. It reports its tests pass but no simulator run.
3. [fix-previous] `Packages/MadarPrayer/Tests/MadarPrayerTests/PrayerTests.swift` lines 22, 43, 84, 104: `#require(apply(...))` lacks `try`, so the package does not build its tests. Line ~58-66 asserts aging to missed, which RP1 forbids; remove `.agePending` (PrayerMutationHandler.swift) as part of M1 RP1 work. `PrayerRoom.swift:364` has "·" next to a digit (RU1).
4. Backup UI test: stop after two more attempts, test the model logic and verify by hand on the phone.
Next: Top (Sol xhigh or Opus, high) for item 2, then M0-T07 and M0-T06.
