# M0-T09 — Native lease expiry regression review

12 October 2026 — independent Codex reviewer, GPT-6.1 Sol xhigh (Top).

**Verdict: approve — the actual 61-second background/fresh-authentication slice only.** No findings. Exact 59/60-second boundary, T09 section/integration approval and M0 remain open.

One source pass covered only `daa9e99..bbc1492`: the new fixed L/light UI regression and its two-match native driver. No production code, clock override, authentication bypass, default or schema change. Prior implementation and matrix evidence were reused without another review/run.

The interval begins only after XCTest confirms the app is running in the background; real monotonic time must reach 61 seconds and the app must still be backgrounded. Same-process return leaves native item, Files action and cached-share readiness absent for five seconds before another explicit export tap. That tap must show the cover and remain unready for two seconds before the distinct reauthentication checkpoint. The driver requires first-match success and verified same-process return before issuing the second native match; it preserves both results and fails if either checkpoint/match is missing.

Independent verifier ran the selected test once on iPhone 17 Pro, iOS Simulator 26.5 (23F77), L/light. Reviewer inspected raw command/log, both biometric results, both launchctl listings, process JSON, xcresult summary and all four PNGs under:

`Madar/Artifacts/t09-native-retirement-2026-10-12/run-bbc1492-lease-expiry/`

- Actual confirmed-background interval: `61.009s`, measured before activation. PID `20735` and exact label `UIKitApplication:com.alqzan.madar2[a9eb][rb-legacy]` match before the first authentication and after re-entry; the XCTest runner remains separate.
- `match-1.json` and `match-2.json` are distinct native commands, each recording `outcome: success` and `simulateSuccessfulMatch`.
- Before PNG `1CFB18F2-E879-4D41-AF0B-26EFA9F1CE7E.png` shows the native archive and Files action. Retired PNG `EAC84EB9-80FB-4436-91AC-B51E94B1AB07.png` shows the recovered export section without the cached-share row.
- Full-screen PNG `965A21F8-54FE-4988-AB9D-A8A2062589CF.png`, captured before the second checkpoint/match, visibly shows the native “بصمة الوجه” request over the covered scene. PNG `E52FB147-B419-4AB9-BA98-3F95D605D0D2.png` shows share readiness after the second match. This establishes a fresh native request rather than accepting a cached-ready result.
- `Executed 1 test, with 0 failures (0 unexpected) in 101.135 (101.136) seconds`; `** TEST SUCCEEDED **`. xcresult reports one pass, zero failures/skips and no runtime warnings; raw tooling diagnostics remain preserved.

No failure occurred before XCTest, in native authentication setup or in this acceptance flow. Reviewer performed no native run/build or production edits.

**Not verified:** exact 60.000-second transition, synchronous inactive cover over the sheet, actual switcher capture, two scenes, refusal, VoiceOver, destination-file write, retained-file deletion or physical iPhone behavior. This single L/light run proves beyond-lease recovery and explicit fresh-export authentication; it does not extend the earlier size/theme matrix to the lease-expiry flow.
