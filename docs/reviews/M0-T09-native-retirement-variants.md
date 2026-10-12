# M0-T09 — Native retirement variants review

12 October 2026 — independent Codex reviewer, GPT-6.1 Sol xhigh (Top).

**Verdict: approve — default/light and default/dark regression slice only.** No findings. This closes the requested appearance/size matrix for the foreground-retirement flow when combined with retained AX3/light evidence. T09 section acceptance, integration approval and M0 remain open.

One source pass covered only `e53f882..daa9e99`: bounded variant selection in the UI test/driver. `default-light` maps to `L/light`, `default-dark` to `L/dark`, and the unchanged default `ax3-light` maps to `AX3/light`. Unknown test variants fail; nondefault driver variants require the retirement test. Variant markers and screenshot names identify the applied configuration. Native authentication, same-process, under-60-second recovery and five-second no-reopen assertions remain intact. No production code, defaults or schema changed; earlier implementation/reviews were not repeated.

Independent verifier ran each missing variant once on iPhone 17 Pro, iOS Simulator 26.5 (23F77). Reviewer inspected each raw command/log, genuine biometric match result, both launchctl listings, process JSON, xcresult summary and before/after PNGs.

| Variant confirmed in log and screenshots | XCTest result | Home to recovered shell | Same PID before/after |
|---|---|---|---|
| `default-light`, `size=L theme=light` | 1 pass, 0 failures/skips, 33.750s | 4.642s | 19608 |
| `default-dark`, `size=L theme=dark` | 1 pass, 0 failures/skips, 34.036s | 4.629s | 19787 |

Both logs end `** TEST SUCCEEDED **`; both biometric results record `outcome: success` / `simulateSuccessfulMatch`. Exact app launch labels also match across re-entry and remain distinct from the XCTest runner. Both xcresult summaries have no runtime warnings. The four PNGs show the intended theme/default text size, actual native archive and “حفظ في الملفات” before Home, then the recovered export/password form with no sheet or cached-share row. The tests retain the five-second no-reopen observation without another tap.

Raw evidence and named attachment manifests:

- `Madar/Artifacts/t09-native-retirement-2026-10-12/run-daa9e99-default-light/`
- `Madar/Artifacts/t09-native-retirement-2026-10-12/run-daa9e99-default-dark/`

AX3/light `e53f882` evidence is reused without a rerun; its earlier runtime warning remains recorded in its report. No failure occurred before XCTest, during native authentication setup or in either new acceptance flow. Reviewer performed no native run/build and made no production changes.

**Not verified:** synchronous inactive cover over the sheet, actual switcher capture, two scenes, exact 59/60-second expiry or later reauthentication, refusal, VoiceOver, destination write, retained-file deletion or physical iPhone. The completed matrix concerns this foreground-retirement flow only.
