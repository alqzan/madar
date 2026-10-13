# M0-T06 — Root startup and lock surface trace

12 October 2026 — bounded source trace of 13 raw manual-inventory locations in `MadarApp.swift` and `MadarLock.swift`. The source hashes match the accepted T11 inventory: `MadarApp.swift` `9be3ed2689ccf06717cd9fd2bfe5b9f94c2ffe52c3e945be49cf013502b5f119`; `MadarLock.swift` `17862f1840f95da4fa26ba09d5fcbf685e8b9ca0fa1e05fc3dd691f114ce507f`.

## Route and state trace

The root loads or reopens the local managed store, constructs `AppSession`, builds the lock controller from `core.faceIDLock`, then gates the root shell. Startup errors expose an Arabic retry action and the underlying dynamic error string. The isolated `UITestStores/<UUID>` path and matching backup-key namespace are fixture-specific; they are not alternate production storage routes.

`MadarLockController` derives the protected feature from the selected scope, asks LocalAuthentication for `deviceOwnerAuthentication`, and calls `authorizeAccess` only after a successful result. `MadarLockGate` reveals protected children only when `canPresent` succeeds; an unprotected shell is retained but covered and hidden from hit testing/accessibility while covered. Scene inactivity redacts protected view models; backgrounding invalidates the current authentication context; returning after the existing 60-second lease locks again. Redaction failure stays fail-closed. The Arabic lock screen uses named typography and theme roles.

| Source | Locations | Disposition |
|---|---:|---|
| `MadarApp.swift` | 7 | Local-store startup/reopen, Arabic retry/error, lock-controller setup and root gate map to the M0 shell. Two fixture-path lines are DEBUG-only and do not prove owner-store isolation. |
| `MadarLock.swift` | 6 | Lock-screen theme/text/action map to the existing app-lock surface; authorization and protected-content ordering are summarized from source only. |

The separate P1b run and report remain the evidence for controlled export authorization. This trace does not prove native Face ID success/refusal, actual switcher capture, scene lifecycle timing, authentication prompt localization, spoken VoiceOver, physical protection or owner data. T09 and T12 remain open.

## Result

These 13 locations have a source disposition; two DEBUG fixture-path points are deferred from production acceptance. Across T06, 318 of 420 raw manual inventory locations are mapped, 136 are explicitly deferred and 102 remain undispositioned. The strict T11 checker still reports all 420 because it does not consume these reports. M0 remains NOT APPROVED.

Sources: `Madar/App/MadarApp.swift`; `Madar/App/MadarLock.swift`; `docs/reports/M0-T09-P1b-candidate.md`; `docs/reports/M0-T11-source-checks.md`; `docs/reports/M0.md` E11–E13/E18.
