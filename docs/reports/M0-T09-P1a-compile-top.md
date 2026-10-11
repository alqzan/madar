# M0-T09 P1a — bounded compiler repair

11 October 2026 — codex, Top compiler repair. This is a self-check, not an independent section review or P1a acceptance.

Branch `m0-s2-privacy-compile-top` starts from preserved candidate `e9bbfb7` in `/Users/abdulrahman/.codex/worktrees/m0-presentation-privacy/بناء مدار 2.0`. Primary checkout, `main`, simulator devices and P1b were not modified.

## Diagnostic and isolation boundary

Previous actual diagnostic (`/tmp/madar-privacy-build-final.log`):

```text
ScenePrivacyPresenter.swift:37:39: error: sending 'note' risks causing data races [#RegionIsolation::SendingRisksDataRace]
note: 'note' is captured by a main actor-isolated closure. main actor-isolated uses in closure may race against code in the current isolation context
```

`project.yml` and generated project set `SWIFT_VERSION = 6.2`. Resolved build settings report `EFFECTIVE_SWIFT_VERSION = 6`; the actual compiler uses `-swift-version 6`. No explicit strict-concurrency, default-actor-isolation, approachable-concurrency or upcoming-feature settings/flags are present. Strict Swift 6 checking was preserved.

The scope observer already requests `queue: .main`, and presenter/window operations are `@MainActor`. The repair snapshots the sender's `ObjectIdentifier?` and the existing `Sendable` `MadarLockScope` before `MainActor.assumeIsolated`. The closure no longer captures `Notification`, its `Any` object or its user-info dictionary. Sender exclusion and invalid-scope refusal retain their prior behavior. The callback remains synchronous; native scene inactivity/background coverage still calls `coverNow()` before controller work. No Task, unsafe Sendable conformance or isolation relaxation was added.

Source change: six inserted and two removed lines in `Madar/App/ScenePrivacyPresenter.swift`. No native cover/window/lifecycle logic or tests changed.

## Actual checks

Both commands ran from this worktree's nested `Madar/`, with separate derived data, and exited **0**:

```sh
xcodebuild -project Madar.xcodeproj -scheme Madar \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/MadarPrivacyCompileTopDerivedData \
  CODE_SIGNING_ALLOWED=NO build
```

Raw log: `/tmp/madar-privacy-compile-top-build.log`. Last non-empty line:

```text
** BUILD SUCCEEDED **
```

```sh
xcodebuild -project Madar.xcodeproj -scheme Madar \
  -destination 'generic/platform=iOS Simulator' \
  -derivedDataPath /tmp/MadarPrivacyCompileTopDerivedData \
  CODE_SIGNING_ALLOWED=NO build-for-testing
```

Raw log: `/tmp/madar-privacy-compile-top-test-build.log`. Last non-empty line:

```text
** TEST BUILD SUCCEEDED **
```

The app build has no warning/error diagnostics. Test compilation has one App Intents metadata warning on the UI test runner: `Metadata extraction skipped, no AppIntents.framework dependency found`. The host and UI test bundles compiled, including the **4** methods in `PresentationPrivacyTests`. No tests were executed. Its two-controller authorization probe does not prove two actual `UIWindowScene` instances. `git diff --check` exited **0** with no output.

One repair attempt, no failed build invocations. Runtime scene coverage, app-switcher capture, accessibility, two-scene behavior, authentication races and device gates remain unverified here. Root owns those checks and independent review, plus the handover on `main`. The broader preserved candidate remains unaccepted until that work passes.
