# M0-T09 P1a terminal findings — compiled, awaiting root tests

11 October 2026 — codex, GPT-6.1 Sol Standard high. Base `e3870d6`; branch `m0-s2-privacy-compile-top`. Only M0P1a-05/-06 were repaired. Main/PROGRESS, prior closed findings, defaults/schema and P1b were not changed.

M0P1a-05 (`fec37c5`): scope persistence has its own UUID ownership, independent of authentication generations. Concurrent scope writers are rejected until terminal reconciliation, including when the initiating scene disconnects. Success and failure both resolve matching peer pending requests using the actually stored setting. A failure after save reconciles the saved scope; unreadable settings stay closed until an explicit authorization can read them. Scope revocation remains covered until explicit authorization. Old terminal request IDs cannot clear newer pending state. AppPrivacyService's reconciliation query reloads settings only.

Four new host regression functions cover background/disconnect with successful save, failure before save and failure after save, cancellation ignored by a suspended persistence adapter that subsequently saves, and stale terminal IDs. Peer tests use two controllers and one presenter on a single host UIWindowScene; they are not actual two-scene evidence.

M0P1a-06: authorization checks active phase and captured lifecycle epoch after the child binding task returns and before committing leases/exposure. An invalid commit queues binding cleanup under the cover. One deterministic host regression interrupts exactly at that completion boundary using an internal default-noop lifecycle seam; it asserts no committed authorization, successful purge and a valid fresh request. No production authentication bypass was added.

Verification: four generic simulator build-for-testing invocations succeeded, zero failed Standard commands. Fix05 was rebuilt after adding cancellation coverage and holding revoked presentations until explicit authorization. Final outputs:

```
/tmp/madar-privacy-fix05-build.log
** TEST BUILD SUCCEEDED **
/tmp/madar-privacy-fix06-build.log
** TEST BUILD SUCCEEDED **
```

`git diff --check` passed. All 17 PresentationPrivacyTests sources compile (12 previous, 5 new). None were executed by this agent. Root owns host/runtime execution and fresh Top fix-only review of `e3870d6..HEAD` before integration. Physical authentication, actual two-scene ownership, switcher/native modal frames, AX3/dark/accessibility and P1b remain unverified. Full presentation privacy/M0 is not accepted by this compile result.
