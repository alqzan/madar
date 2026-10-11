# M0-T09 P1b — independent review finding fixes

12 October 2026 — codex, Standard. Candidate branch `codex/m0-p1b-fixes` starts at integrated `48a3fe4`; managed worktree `/Users/abdulrahman/.codex/worktrees/m0-p1b-fixes/بناء مدار 2.0`. Root owns PROGRESS, main handover, host/native acceptance and fresh Top review. The independent review is copied byte-for-byte into `docs/reviews/M0-presentation-privacy.md`; its changes-requested verdict has not been rewritten.

## Changes

- **M0P1b-01:** app restoration requests owning-scene `.export` plus `.privateNote` when current stored private rows (including tombstones) enter its safety payload. Presence check, authorization and first-key setup execute inside the existing restore writer barrier/store lease before local-row/key access. A restore request identity and ticket survive derivation; controller revocation cancels its token and clears them. The derived key is saved only after validation. Restore revalidates after asynchronous file/safety/staging work and before generation promotion. Default unattended coordinator/automatic-backup behavior is preserved. Import preview behavior remains the existing flow; this repair targets explicit restore/first-key safety capture, not a restore redesign.
- **M0P1b-02:** `BackupKeyStore.exists()` checks presence without loading a credential. The Keychain implementation requests attributes with `kSecReturnData = false`; `hasConfiguredKey()` uses that query. Actual automatic backup still loads/reserves/saves the configured credential. A controlled derivation dependency defaults to the same real detached derivation, enabling deterministic revocation tests without an authentication bypass.
- **M0P1b-03:** the scene presenter retains each activity ticket and observes owning-controller revocation, including local scope changes. It covers and retires the activity/request/ticket synchronously. The cover stays visible until the native dismissal completion fires; state synchronization also rejects stale activity tickets before uncovering. Generic app reauthorization cannot reopen sharing. Completed files are retained. Narrow controlled presentation/dismissal adapters default to real UIKit presentation/dismissal.

No defaults, schema, backup format/retention, scheduled-backup rules or authentication bypass changed.

## Verification

`swift test --filter ManagedBackupTests` from `Madar/Packages/MadarData` passed on the first invocation:

```text
✔ Test test_M0P1b_02_configuredPresenceNeverLoadsSecretAndAutomaticBackupStillDoes() passed after 0.215 seconds.
✔ Test test_M0P1b_01_restoreAuthorizationRefusesBeforeKeyReadSafetyAndPromotion() passed after 0.318 seconds.
✔ Suite ManagedBackupTests passed after 9.695 seconds.
✔ Test run with 13 tests in 1 suite passed after 9.695 seconds.
```

This runs the affected existing restore/retention/cancellation/recovery suite as well as the two new package regressions. Log: `Madar/Artifacts/madar-p1b-fixes-package.log` (also `/tmp/madar-p1b-fixes-package.log`).

```text
python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
git diff --check
exit 0, no output
```

Root-hosted focused acceptance (`ExportPrivacyTests` plus the two new native-adapter retirement regressions) ran on iPhone 17 Pro / iOS 26.5:

```text
Executed 15 tests, with 0 failures (0 unexpected) in 5.242 seconds.
** TEST EXECUTE SUCCEEDED **
```

Raw output: `Madar/Artifacts/madar-p1b-root-host.log`.

The existing visible native-share UI journey was also attempted at L/light, AX3/light and L/dark. First run reused the author's unsigned generic build-for-testing, so the app-group entitlement was absent and startup showed `DataError` / retry. After diagnosing this environment mismatch, the targeted test was rebuilt with simulator signing (`CODE_SIGN_IDENTITY=- CODE_SIGNING_ALLOWED=YES`). It opened settings and completed export, but the default `notesOnly` scope required OS authentication; the UI test did not establish successful authentication and remained under `scene-privacy-cover` before it could inspect the native share item. The run failed at `FoundationUITests.swift:75` waiting for the share item. This does not establish an application defect or a successful authorized share; that flow remains **not verified**. Raw output: `Madar/Artifacts/madar-p1b-root-signed-ui.log`, result bundle `/tmp/madar-p1b-root-signed-ui.xcresult`. No repeated UI run was made.

Generic simulator compilation:

```sh
xcodebuild -project Madar.xcodeproj -scheme Madar   -destination 'generic/platform=iOS Simulator'   -derivedDataPath /tmp/madar-p1b-fixes-build   CODE_SIGNING_ALLOWED=NO build-for-testing
```

First build failed solely on the new test `ActivityProbe.finishRetirement()` invoking its MainActor callback from a nonisolated helper. First repair explicitly isolates the activity/derivation test helpers to MainActor. Retry then failed because ignored `Amiri-Regular.ttf` was absent in this isolated checkout; concurrent preview-link commands also stopped without a linker diagnostic. Second/final repair provisions the two existing ignored Amiri TTF files from the primary checkout, alongside its existing Thmanyah OTF files, without editing or staging binaries/project configuration. Final invocation compiled app and test bundles for both simulator architectures:

```text
** TEST BUILD SUCCEEDED **
```

Logs: `Madar/Artifacts/madar-p1b-fixes-build.log`, `madar-p1b-fixes-build-retry.log`, `madar-p1b-fixes-build-final.log` (also the corresponding `/tmp/` paths). One source repair and one isolated dependency provisioning repair; no further retry.

## For root / next reviewer

App-host regression run completed by root using the existing build-for-testing output. It ran the complete `ExportPrivacyTests` class plus the two new `PresentationPrivacyTests` listed below:

- `test_M0P1b_01_restoreFirstKeyRefusalCreatesNoSafetyOrPromotion`
- `test_M0P1b_01_authorizedFirstKeyRestoreCreatesSafetyAndPromotes`
- `test_M0P1b_01_restoreDelayedKeyDerivationRevocationCannotSaveSafetyOrPromote` (controlled suspension covers background, active lock, local scope and disconnect)
- `test_M0P1b_02_settingsConfiguredStatusDoesNotLoadOrSaveCredential` (configured/unconfigured Boolean plus unattended automatic credential access)
- `test_M0P1b_03_activeLockRetiresPrivateShareIncludingScopeNone`
- `test_M0P1b_03_localScopeChangeRetiresPrivateShareBeforeGenericAuthorization`

The last two tests use a real app-host UIWindowScene and native controller objects with a controlled adapter. They prove retirement order and cover lifetime while adapter completion is delayed; they do not prove UIKit/OS dismissal, system authentication, true two-scene operation, switcher frames or Files destination writes. A fresh Top fix-only review approved `33ab2ec` in commit `8876626`; original findings remain preserved above in `docs/reviews/M0-presentation-privacy.md`. Native authenticated share, inactive/switcher, true two-scene operation, default/AX3/dark privacy matrix, spoken VoiceOver, physical protected-data behavior and Files destination writes remain root/owner acceptance. M0 remains unapproved.
