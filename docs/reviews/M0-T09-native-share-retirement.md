# M0-T09 — Native share retirement regression review

12 October 2026 — independent Codex reviewer, GPT-6.1 Sol xhigh (Top).

**Verdict: approve — this regression slice only.** No findings. T09 section acceptance and M0 remain open; this is not integration approval.

Reviewed only `fb6b1bb..e53f882`: the new AX3/light native UI regression and its biometric/process-continuity driver. Earlier implementation/finding repairs were not re-reviewed. Authority: current T09 card/Recommendations, `docs/design/M0-presentation-privacy.md` native-share state and acceptance, and §8.10 (`14-shared.md`). No production behavior, defaults or schema changed.

The regression requires an authorized native archive item and Files action before pressing Home, a running-background to foreground transition, recovery before 60 seconds, and absence of the native item, destination and cached-share button. It materializes the adjacent password rows to avoid relying solely on an offscreen button's absence and observes five seconds without any new tap. The driver fails on an absent/ambiguous app service or changed PID/label; runner/widget bundle IDs do not match the exact app boundary.

Independent verifier ran the selected test on iPhone 17 Pro, iOS Simulator 26.5 (23F77), AX3/light. Reviewer inspected raw command, log, biometric result, both launchctl listings, process identity and both exported PNGs in:

`Madar/Artifacts/t09-native-retirement-2026-10-12/run-e53f882/`

- `match.json`: `outcome: success`, `operation: simulateSuccessfulMatch`; the app uses its real native authentication path.
- Both raw listings and `process-identity.json`: PID `18574`, label `UIKitApplication:com.alqzan.madar2[4cb6][rb-legacy]` before authentication match and after re-entry. The separate XCTest runner is excluded.
- Log: Home/background → recovered foreground shell in `4.516s`; native item/Files/cached-share remain absent through the five-second inverted expectation.
- `Executed 1 test, with 0 failures (0 unexpected) in 45.041 (45.043) seconds`; `** TEST SUCCEEDED **`. xcresult reports one pass, zero failures and zero skips.
- Before PNG `D54FEF68-2FCC-484D-9971-DCD30937B074.png` shows the native archive and “حفظ في الملفات”; after PNG `30C6FEB5-3B32-41CD-8E56-4FD1546B9906.png` shows the recovered backup/password form without the sheet or share row.

No failure occurred before XCTest, during authentication setup or in this product acceptance slice. xcresult retains an `Invalid frame dimension (negative or non-finite)` runtime warning; it did not fail this test and its cause was not investigated by this bounded review.

**Not verified by this slice:** synchronous inactive cover above the sheet, actual switcher capture, two scenes, exact 59/60-second expiry or later reauthentication, refusal, default/dark matrix, VoiceOver, destination-file write, retained-file deletion or physical iPhone behavior. Those require their own evidence; foreground retirement does not establish them. Reviewer ran no simulator/build and made no production edits.
