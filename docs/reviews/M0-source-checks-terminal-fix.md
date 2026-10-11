# M0-T11 dependency boundary — fix-only review

Verdict: **approve** — M0L-01 dependency-expression finding closed; no findings in this fix diff.

Fresh Codex Sol Standard high review, 2026-10-11. Scope only `33e1221..3ade5a5` (Top source/test fix `54579a3` and report), using `ffc8e97` as the finding input. Reviewer did not author the Top fix; unchanged earlier checker implementation and production were not re-reviewed. Own branch: `codex/m0-source-checks-terminal-review`.

`check-shipping-sources.py:52–62` now recognizes whitespace before the dependency colon and requires a literal array to end at the actual argument boundary: closing target parenthesis, next labelled argument or trailing comma before closure. It rejects supported-prefix concatenation/member/conditional/closure suffixes instead of accepting the first array. This remains a deliberately restricted manifest parser, not a SwiftPM graph evaluator.

Actual `python3 -m unittest discover -s Madar/scripts/tests -v` → **12 tests, OK**. The complete-enumerator fixture contains Main/Core and a Helper red-colour violation; all six suffix forms (plain/conditional concatenation, conditional/member suffix, closure/member suffix, comment and newline) are rejected. Positive literal end/resources/trailing-comma cases pass; the spaced-colon negative is covered. `git diff --check 33e1221..3ade5a5` → no output.

Actual full checker in this resource-complete historical checkout → exit **1**, exactly the two existing backup RU3 findings at `BackupSettingsView.swift:124,251`; scope remains **60 shipping files / one catalog / 38 M0 pairs / 418 manual locations**. Detailed output: `/tmp/madar-m0-source-terminal-review.json`. T13 is not included in this historical base, so these are neither new fix regressions nor claims about current integrated backup copy. Root must rerun the integrated checker after applying the accepted branches.

No production changes, app build, simulator or runtime/physical acceptance. This approval does not resolve manual tracing, VoiceOver, Reduce Motion or the M0 gate.
