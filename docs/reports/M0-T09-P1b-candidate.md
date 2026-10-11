# M0-T09 P1b — candidate handover

11 October 2026 — codex, GPT-6.1 Sol Standard high. Worktree `m0-presentation-privacy`, branch `codex/m0-export-privacy`; primary checkout and PROGRESS remain root-owned. This is a compiled candidate, pending host execution, fresh Top review and native acceptance.

Explicit plain/encrypted export requests `.export` under the existing writer barrier and store lease before reading export rows, deriving/configuring the first export key, or creating the file. A metadata-only private NotebookNote count includes tombstones and adds `.privateNote`; the check and capture share the same writer barrier. Scene/generation/request validity is checked after authorization/key derivation/backend completion and before UI publication. Revocation cancels the owned export token and removes cached URL/passphrase UI state without deleting completed artifacts. Existing automatic-backup callers retain the default unattended coordinator path.

Cached sharing now uses an Arabic button, a fresh authorization request for the original payload requirements and the exact-scene native activity adapter. Existing accessibility IDs and UUID-only keyboard diagnostics remain. Existing host export fixtures explicitly inject a test authenticator; production has no authentication environment bypass. UI tests keep their actual OS authentication requirement.

## Self-check

`xcodebuild -project Madar/Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath /tmp/MadarPrivacyReviewDerivedData CODE_SIGNING_ALLOWED=NO build-for-testing`

- Production build: exit 0, `/tmp/madar-privacy-P1b-first-build.log`, `** TEST BUILD SUCCEEDED **`.
- First build with the new test source: exit 65, `/tmp/madar-privacy-P1b-tests-build.log`; a `@Sendable` hook captured the non-Sendable fixture. Fixed by capturing only its MainActor controller.
- Repaired test build: exit 0, `/tmp/madar-privacy-P1b-tests-green.log`, `** TEST BUILD SUCCEEDED **`. Both simulator architectures and host/UI test targets compiled. No tests executed by this agent; one failed compile total.
- `git diff --check`: exit 0, no output.
- Separate prior cover-symbol fix `94cb679`: generic test build succeeded in `/tmp/madar-privacy-cover-icon-build.log`; `PresentationPrivacyTests.test_M0P1a_sceneCoverLockSymbolExists` asserts the replacement `lock` symbol exists.

## Root execution targets

Run `MadarTests/ExportPrivacyTests` (nine methods):

- `test_M0P1b_refusalCreatesNoPlainEncryptedFileOrKey`
- `test_M0P1b_cancelledVerifierCannotCreateOutputOrReadKeys`
- `test_M0P1b_staleVerifierCannotExportOrConfigureKey`
- `test_M0P1b_scopesAndPrivatePayloadUseExplicitAuthorizationIncludingTombstones`
- `test_M0P1b_privatePayloadRefusesEvenWhenAppScopeIsNone`
- `test_M0P1b_staleKeyDerivationCannotSaveKeyOrCreateFile`
- `test_M0P1b_cachedShareReauthorizesOriginalPrivatePayloadAndRetainsFile`
- `test_M0P1b_backgroundDuringCachedShareCannotPresent`
- `test_M0P1b_modelRevokesCachedURLsAndPassphrasesWithoutDeletingCompletedExport`

These use real managed stores/coordinator/codecs with controlled device-verifier, key-store and presentation dependencies. Refused/cancelled/stale verification asserts no output, key load/save or presentation; a separate post-authorization key-derivation revocation permits the initial authorized configuration query but asserts no key save/file. Successful scope cases validate portable payloads. The presentation spy proves the service boundary only. It does not prove native activity-controller behavior. Run the existing full host suite and package tests after integration; host fixture changes are limited to authentication injection immediately before existing export operations.

## Not verified / review boundary

- No simulator or physical-device execution, native authentication success/refusal, Files destination write, switcher capture, VoiceOver, AX3/dark screenshots, or actual two-scene behavior. Root owns those checks and independent Top review.
- Adjacent existing restore-preview and restore first-safety-key routes remain unchanged under the plan's restore-redesign exclusion. `status()` still uses the existing `hasConfiguredKey()` configuration query. The new zero-key-read assertions cover explicit refused export requests, not opening Settings. Top must assess these adjacent routes against the approved key-setup wording before whole-privacy acceptance; this report does not claim those routes are gated.
- Existing UI export journeys require actual OS authentication under their default scope. They were not weakened or supplied with a production environment bypass.
- Retained SQLite fixtures are synthetic and left in temporary storage while SwiftData handles remain alive. No owner data, defaults, schema, backup format or retention policy changed.

Next: root host execution, fresh Top diff review, then native acceptance. Next session: Top GPT-6.1 Sol xhigh for review; Standard high for any scoped repair. Do not treat a successful compile as M0 or privacy approval.
