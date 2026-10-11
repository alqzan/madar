# M0-T09 P1a — unverified candidate preserved, production reverted

11 October 2026 — codex, GPT-6.1 Sol Standard high.

Candidate `e9bbfb71f927b961ca3be6a0f74addae18c550be` is intentionally unmerged and not accepted. Its normal revert restores all production/project/test source to baseline `0e3bb87`; no main or PROGRESS files were changed. Branch: `m0-s2-presentation-privacy`; worktree: `/Users/abdulrahman/.codex/worktrees/m0-presentation-privacy/بناء مدار 2.0`.

## Candidate scope

Scene-local session/controller ownership; exact hosting UIWindowScene bridge; synchronous non-key cover above app sheets on native inactivity/background, accessibility suppression, scoped disconnect/protected-data handling; injectable device authenticator and clock, stable first-background timestamp with 60-second expiry, request/scene authorization tickets, serial redaction and guarded rebinding. A native activity adapter is scaffolded but unused. Four host test sources cover private-note authentication and controller-owner isolation, 59/60-second repeated-background lease, late auth after background, and synchronous non-key cover above a presented controller.

P1b was not started: existing export, key setup/view and cached-share paths remain ungated; no private-note presence preflight or UI export fixture seam is integrated. Automatic encrypted backups were not changed. T09 cannot be accepted from this candidate.

## Actual self-check outputs

`xcodegen generate` succeeded. `git diff --check` succeeded before candidate commit. Generated project diff contains only the two new source registrations.

1. Generic simulator app build exited **65**, `/tmp/madar-privacy-build.log`: explicit-self errors inside the scope notification callback. First repair added `self`.
2. Generic simulator app build exited **65**, `/tmp/madar-privacy-build-green.log`: Observation macro rejected combined generation/epoch declaration (`_epoch` and `_generation` not covered). Second repair split declarations.
3. Generic simulator `build-for-testing` exited **65**, `/tmp/madar-privacy-build-final.log`:

```
ScenePrivacyPresenter.swift:37:39: error: sending 'note' risks causing data races [#RegionIsolation::SendingRisksDataRace]
** TEST BUILD FAILED **
(3 failures)
```

The third command was already running when root clarified that two failed build invocations, rather than two failed repairs, exhaust the stop rule. It should have stopped after invocation 2; this boundary error is recorded explicitly. No further repair was attempted. All source was preserved and normally reverted without rewriting history.

## First next task — Top (GPT-6.1 Sol xhigh)

Start from preserved candidate in a fresh isolated branch, split compiler and host test work, and resolve Notification region isolation without weakening actor safety. Then compile/run the four host tests and add missing real two-scene isolation, inactive-during-device-auth, cancellation/scope/disconnect and redaction/binding-failure probes before accepting P1a. Check bridge lifetime/disconnect and scene reattachment, and ensure failed redaction cannot expose content after asynchronous recovery. The controller-isolation source test is not actual two-UIWindowScene evidence. Native modal test is not runtime evidence until run by root.

Not verified: any tests executed, app runtime, native activity presentation, default/AX3 screenshots, real two-scene behavior, Face ID or physical-device gates. Root owns simulator/device execution and independent review. Do not merge this WIP or claim a green P1a.
