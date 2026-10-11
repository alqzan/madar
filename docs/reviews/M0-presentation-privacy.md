# M0-T09 P1b — presentation privacy review

12 October 2026, 01:05 Arabia Standard Time. Independent Codex reviewer: GPT-6.1 Sol, xhigh (Top); did not implement the candidate. Source review only; the root agent owns simulator/native acceptance.

**Verdict: changes requested.** Repair the two High findings before merging or starting the next section. Resolve the Medium key-read finding within the existing boundary; no setting, schema, retention or unattended-backup change is required.

## Scope

Reviewed `94cb679` and `2ea40ff` commit by commit, the scoped plan `92d82d5`, and integration merge `48a3fe4` relative to approved P1a `3a2bf6b`. The integration's export/controller/presenter/coordinator/test files match `2ea40ff`; no extra integration repair was introduced. Accepted unrelated copy/clock changes were excluded. Authority: `docs/design/M0-presentation-privacy.md:18–26,34–37`, `docs/reports/M0-T09-P1b-plan.md:5–9`, handoff `14-shared.md:153–189`, and unchanged `core.faceIDLock` schema.

## Findings

1. **M0P1b-01 — High — First safety-key setup bypasses scene authorization.** `Madar/App/AppBackupService.swift:160–168`. With default `notesOnly`, Settings/restoration is reachable without opening the notes lock. A valid imported preview and its supplied password enter `hasConfiguredKey()` and `configurePassphrase(password)` without `.export`/private-payload authorization or a post-derivation ticket check. The default validation closure in `BackupCoordinator.swift:16–19` permits saving the derived key after background/scope/disconnect revocation. Restoration then captures the current store in its safety backup. This unchanged route does not meet the approved first-key setup boundary; the restore-redesign exclusion does not authorize bypassing it. **Fix:** guard this existing app route before protected local-row/key access and first-key setup, retain the ticket/request identity through derivation and the safety capture, and cancel on revocation. Keep scheduled backups unattended. Add refusal and delayed-derivation revocation regressions asserting no key save, safety file or generation promotion.

2. **M0P1b-02 — Medium — Status reads secret key material before the lock.** `Madar/App/AppBackupService.swift:54`, `Madar/Packages/MadarData/Sources/MadarData/BackupCoordinator.swift:15`. `BackupSettingsModel.refresh()` calls status on screen entry. `hasConfiguredKey()` uses `keyStore.load()`; `KeychainBackupKeyStore.load()` requests `kSecReturnData` and decodes the full credential (`BackupKeyStore.swift:32–37`). Only a Boolean reaches the UI, but secret key bytes are read while the default Settings shell is unprotected. The zero-key-read export tests omit this real entry path. **Fix:** add a metadata-only existence query to the key-store abstraction and use it for status/configuration checks. Keep actual key loading in authorized export or the existing unattended backup path. Add a status/Settings regression with a configured key proving no credential load/save and correct Boolean status.

3. **M0P1b-03 — High — Native share survives authorization revocation.** `Madar/App/ScenePrivacyPresenter.swift:93–115`. `present` validates the ticket once and discards it; `synchronize` later removes the cover based only on `.app`. Controller `lock()` or a local scope change covers the existing activity without dismissing it; the scope observers skip the originating controller. A private-file activity under scope `none` therefore remains attached when `lock()` clears private authorization, and `recoverActive()` can uncover the unprotected app shell with that stale activity still present. Generic `.app` authorization after a local scope change can likewise reveal the previous share without another explicit tap. This is a source-confirmed state path, not a demonstrated OS switcher capture. **Fix:** retain the activity authorization and observe owning-controller revocation; synchronously retire/dismiss the activity and its request/ticket before any uncover. Add a controlled native-adapter regression for active lock and local scope change, including a private file under `none`; generic reauthorization must not reopen the activity. Preserve the completed file.

## Evidence and limits

The new explicit export path correctly places the metadata-only private-note check and authorization inside the writer barrier/store lease, before export row/key/file access. It revalidates before publishing URLs; cached sharing reauthorizes the original payload requirements and uses the owning scene. Private tombstones are included. No production authentication bypass was found.

Reused the root's raw `Madar/Artifacts/run4-export-privacy-host.log`: 49 tests, 0 failures, 6.084 seconds, `** TEST SUCCEEDED **`; includes nine controlled export tests and eighteen presentation tests. `run4-export-privacy-MadarData.log`: 57 tests in five suites passed after 14.520 seconds. These outputs do not exercise the three findings above. No green suite was rerun; no production file was edited.

No actual OS authentication refusal/success, cached native-share flow, immediate inactive frame, app-switcher capture, true two-scene runtime, default/AX3/dark privacy matrix, spoken VoiceOver, physical protected-data behavior or Files destination write was performed by this reviewer. Existing two-controller coverage shares one real UIWindowScene; the export presentation probe replaces the native adapter. Those checks remain separate acceptance requirements after the fixes. This verdict does not approve whole T09 or M0.

## Fix-only re-review — `33ab2ec`

12 October 2026, 01:16 Arabia Standard Time. Fresh independent reviewer: GPT-6.1 Sol, xhigh (Top). Reviewed only `48a3fe4..33ab2ec`, the three findings above, their scoped authority and `docs/reports/M0-T09-P1b-finding-fixes.md`. The original review and findings are preserved.

**Verdict: approve the fix diff. No residual Critical or High findings.** All three source findings are closed:

- **M0P1b-01:** `AppBackupService.swift:168–193` authorizes the owning scene for `.export` and current private-row safety payloads inside the restore writer barrier/store lease. Request identity, ticket and cancellation survive first-key derivation; the post-derivation check precedes key saving. `BackupCoordinator.swift:105–127` validates after file/safety/staging suspension and immediately before generation promotion. Revocation cancels the operation and invalidates its request/ticket. The refusal and suspended-derivation regressions prove no key save, safety catalog entry or promotion; authorized restoration still succeeds. Existing unattended backup behavior remains covered separately.
- **M0P1b-02:** `BackupCoordinator.swift:19` uses `BackupKeyStore.exists()`. The Keychain implementation (`BackupKeyStore.swift:34–44`) explicitly sets `kSecReturnData = false` and requests only presence attributes. The Settings refresh and package tests assert configured/unconfigured status with zero credential loads/saves, followed by successful unattended credential access.
- **M0P1b-03:** `ScenePrivacyPresenter.swift:38–43,107–145` observes its owning controller before state synchronization, covers and clears the activity/request/ticket synchronously, and holds the cover until the retirement adapter completion. The delayed-completion tests cover active lock and local scope change under all three scopes, including private exports under `none`; generic `.app` authorization neither uncovers the retiring activity nor reopens sharing. A later explicit authorized tap works, and the completed file is retained.

Reused current raw evidence; no build or suite was rerun for this documentation-only review:

```text
/tmp/madar-p1b-root-host.log — ExportPrivacyTests (13) + affected PresentationPrivacyTests (2)
Executed 15 tests, with 0 failures (0 unexpected) in 5.242 (5.246) seconds
** TEST EXECUTE SUCCEEDED **
/tmp/madar-p1b-fixes-package.log — swift test --filter ManagedBackupTests
Test run with 13 tests in 1 suite passed after 9.695 seconds.
```

The host activity tests use real scene/controller objects with a controlled presentation/retirement adapter. They prove the source state ordering and delayed-cover lifetime, not actual UIKit dismissal or an OS snapshot. Native OS authentication refusal/success, cached native-share interaction, immediate inactive/switcher captures, true two-scene runtime, default/AX3/dark matrix, spoken VoiceOver, physical protected-data behavior and Files destination writes remain separate acceptance checks. This approval covers the three finding repairs only; whole T09 and the M0 gate remain unapproved. Root owns integration and the handover on `main`.
