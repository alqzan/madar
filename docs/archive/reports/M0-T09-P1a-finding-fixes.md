# M0-T09 P1a finding fixes — compiled, awaiting host execution/review

11 October 2026, codex, GPT-6.1 Sol Standard high. Isolated branch `m0-s2-privacy-compile-top`, base `274dfc4`. Main, PROGRESS, defaults/schema, and P1b were not changed.

- `3e00375` M0P1a-01: stale verifier completion performs no purge. Service binding/recovery shares the redaction queue; stale service data is purged under a synchronous cover before newer mutation/exposure. Two controlled regressions distinguish stale verifier from stale asynchronous binding.
- `c71384c` M0P1a-02: pre-await synchronous revocation reaches attached peer presenters independently of scope persistence; peers cannot recover while transition is pending. Separate success/failure notifications commit the persisted scope or keep revoked presentations covered. Regression delays persistence and fails it, checking peer cover and ticket before resolving the delay.
- `c3b5b8f` M0P1a-03: request-ID-guarded cancellation invalidates the authenticator, clears only that request, and wakes its keyed inactive continuation. Two regressions cover suspended verifier and inactive waiter without awaiting a late verifier before fresh authorization.
- `3235e09` M0P1a-04: exact owning-scene state maps background/foreground-inactive/active separately, with unattached/unknown fail closed. Controlled lifecycle seam tests late attach at 59/60 seconds, duplicate background not renewing the boundary, pending auth invalidation, and unattached lease removal.
- A second narrow M0P1a-03 commit covers cancellation immediately after service binding returns: defer enforces request cancellation before clearing ownership; cleanup is queued under cover before fresh binding. One additional controlled regression. This completes the same finding, not a new feature.

## Actual verification

Six generic simulator `xcodebuild ... CODE_SIGNING_ALLOWED=NO build-for-testing` invocations succeeded, zero failed Standard commands. Fix02 was rebuilt after replacing a notification-order-sensitive test observation with the controller's synchronous revocation seam. Logs:

```
/tmp/madar-privacy-fix01-build.log
/tmp/madar-privacy-fix02-build.log
/tmp/madar-privacy-fix03-build.log
/tmp/madar-privacy-fix04-build.log
/tmp/madar-privacy-fix03-completion-build.log
** TEST BUILD SUCCEEDED **
```

`git diff --check` passed. All 12 PresentationPrivacyTests sources compile: four baseline tests and eight finding regressions. No host tests or simulator were executed by this agent. Root reported baseline-only 24 host tests passed, 0 failures, 3.687 seconds; that predates these fixes and is not regression proof.

## Next

Root runs the 12 presentation host tests and existing host/inbox/export suite, then fresh Top fix-only review on `274dfc4..HEAD` before integration. Cross-scene notification regression uses two controllers/presenters attached to the same real host UIWindowScene; true two-scene isolation/runtime ownership still needs root evidence. Late-background attach uses a controlled activation-state observation of the exact host scene, not an OS-driven background transition.

Native switcher/presented-sheet frame, default/AX3/dark, accessibility, real protected-data and Face ID/passcode gates remain unverified. Root noted a baseline native cover detach appearance warning; no unrelated lifecycle refactor was made. P1b export/key/cached-share/private-note authorization is still unfinished; these fixes do not accept whole presentation privacy or M0. Next review: Top GPT-6.1 Sol xhigh; next P1b production task: Standard high after approval.
