# M0-T11 dependency guard — independent fix-only review

Verdict: **changes requested**.

Reviewer: Codex Sol, Standard high, 2026-10-11. Scope: the M0L-01 finding from `946c87d`, fix `2e58db3..33e1221`, its ten Python fixtures and actual checker output. Branch `codex/m0-source-checks-fix-review` starts at `33e1221`; no production/build/simulator edits or ancestor re-review.

## Finding

1. **Medium — M0L-01 remains open**, `Madar/scripts/check-shipping-sources.py:54–58`: the guard matches only an initial literal array and never validates the expression after its closing bracket. A supported enumerated dependency followed by a computed concatenation (`dependencies: ["MadarCore"] + extraDependencies`, where `extraDependencies` contains the local `Helper` target) is accepted. An independent complete `build_files` fixture enumerates Main/Core but silently omits `Sources/Helper/File.swift`, whose handwritten red colour is independently detected by `scan_source`. Reject any computed suffix after the supported literal dependency array, validating the dependency argument boundary, and add a negative full-enumerator fixture for concatenation. This is the original missing-target coverage defect through a different supported-prefix expression; it does not change the present shipping baseline.

## Evidence and limits

The plain Main → Helper fixture now correctly fails closed. Independent probes also confirmed supported already-enumerated literal products remain accepted, while direct computed variables, conditional lists/products and unknown external products are rejected. The omitted computed suffix is the remaining case.

```text
python3 -m unittest discover -s Madar/scripts/tests -v
Ran 10 tests in 0.004s
OK

python3 Madar/scripts/check-shipping-sources.py --json-output /tmp/madar-m0-source-fix-review.json
FAIL: Madar/App/BackupSettingsView.swift:124: RU3 hand-built record count phrase requires catalog plurals
FAIL: Madar/App/BackupSettingsView.swift:251: RU3 hand-built record count phrase requires catalog plurals
STATIC FAIL: 60 shipping Swift files, 1 catalogs, 38 independently measured M0 token pairs
MANUAL TRACE REQUIRED: 418 source lines; no complete string/key/colour/action or M0 acceptance claim
(exit 1; expected retained T11 baseline failures, T13 not included)

Independent temporary computed-dependency fixture:
Computed Main -> Helper accepted without scope error: True
Enumerated relative sources: ['Packages/MadarCore/Sources/MadarCore/Core.swift', 'Packages/Main/Sources/Main/Main.swift']
Omitted Helper independently detected violations: ['Helper/File.swift:1: handwritten colour value']

git diff --check 2e58db3..33e1221
(exit 0, no output)
```

The full checker ran at the exact candidate in this managed checkout, where ignored font resources were available. It still reports static failures and 418 manual locations explicitly; neither this review nor those ten tests claims global string/key/colour/action coverage. No production review, complete manual trace, runtime UI/VoiceOver/motion, physical device or M0 acceptance is asserted. Re-review only the further dependency-boundary fix.
