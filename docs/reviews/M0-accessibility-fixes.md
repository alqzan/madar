# M0-T12 accessibility repairs — independent source review

Verdict: **approve** for the narrow source fix `b7e5f7c..d3fc0cc`. No source findings. Runtime/audit acceptance remains open.

Reviewer: Codex Sol, Standard high, 2026-10-11. Read the exact six-file diff and author report, §5's 44×44 layout/focus and AX5 passages, §13 minimum-text/accessibility rules, and adjacent unchanged typography/theme definitions needed to verify the selected roles. This is a narrow review of demonstrated repairs, not the failed predecessor, whole UI or M0 gate.

Fajr's semantic row reserves minimum height 44 in layout plus a rectangular focus shape; its combined Arabic label, unique identifier, natural leading alignment, accessibility-size stacking and read-only behavior remain. Reset moves both 44-point dimensions and its content shape inside the actual button label, preserving its existing action. The two preview/search symbols are decorative and explicitly hidden; the search field retains its query binding, native single-line behavior and full Arabic accessible name with a short visible prompt. Caption/body use approved 13/14-point Dynamic Type roles; the caption title has a header trait. `theme.accent` resolves to `accentText`, and the prompt uses the existing `ink2` role. No data, settings/defaults or font/token values change.

The two scroll edge effects are hidden as an explicitly recorded legibility improvement; the native tabs and minimization behavior are untouched. The decision and report correctly leave unresolved contrast/edge/nil-element audit observations open.

The new bound checks measure actual semantic Fajr and native reset nodes in L/AX3/AX5/dark variants, retain screenshots, check the search name/prompt and test continued title-height growth. Audit setup exposes content within a measured viewport above native bars. Its issue handler logs detail, frame, viewport membership and nil elements and **always returns false**; it contains no allowlist, expected-failure masking or audit suppression. System-size audit variants omit the explicit size override. This checks settled states and does not establish every scroll position or spoken VoiceOver journey.

Evidence:

```text
Author /tmp/madar-t12-top-build.log:
** TEST BUILD SUCCEEDED **
Reviewer: python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
Reviewer: python3 Madar/scripts/check-number-separators.py
PASS: RU1 app numeric separator source check
Reviewer: git diff --check b7e5f7c..d3fc0cc
(exit 0, no output)
```

Not performed by this reviewer: build, host/UI test execution, image comparison, runtime contrast or focus/heading-growth measurement, spoken VoiceOver, Reduce Motion, physical iPhone or M0 acceptance. Root owns both UI targets and actual screenshots. The prior `.all` run failed; a new `.all` failure must remain a recorded defect/runtime blocker rather than a green result. Source approval alone does not justify closing T12 or the M0 gate.
