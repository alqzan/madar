# M0-T11 shipping-source tooling — independent review

Verdict: **changes requested**.

Reviewer: Codex Sol xhigh (Top, actual retained session configuration), 2026-10-11. Scope: commit `2e58db3` only, its three tooling/inventory files and task report. Read the main M0-T11 card, `M0-software-check-plan.md`, AGENTS design rules and the relevant token threshold metadata. No production edits, build, simulator or primary branch change.

## Finding

1. **Medium — M0L-01**, `Madar/scripts/check-shipping-sources.py:91–107`: package enumeration scans only the library product's first/root target directory and never traverses or rejects that target's local target dependencies. A normal manifest adding `.target(name: "Main", dependencies: ["Helper"])` plus `.target(name: "Helper")` silently omits `Sources/Helper/File.swift`; the probe's omitted file contains a colour violation that `scan_source` otherwise detects. No error or manual scope warning is emitted. This contradicts the promised fail-closed behavior when the shipping layout changes. Traverse reachable local target dependencies and their sources/resources, or explicitly refuse unsupported extra target dependencies; add an independent negative fixture for this case. The present seven-package baseline has no such additional target, so this is a checker coverage regression risk, not a newly found production defect.

## Evidence and limits

The eight Python tests passed. Contrast thresholds come from approved token metadata (small 4.5, large/nontext 3, minimum type 11); threshold acceptance uses unrounded calculated contrast rather than declared ratios. The report distinguishes these static checks from actual token use, computed settings/actions, copy grammar, opacity and runtime accessibility. Normal static success does not claim complete acceptance; the existing test proves strict mode returns 2 for remaining manual traces when static findings are absent.

```text
python3 -m unittest discover -s Madar/scripts/tests -v
Ran 8 tests in 0.004s
OK

python3 Madar/scripts/check-shipping-sources.py --json-output /tmp/madar-m0-source-review.json
FAIL: Madar/App/BackupSettingsView.swift:124: RU3 hand-built record count phrase requires catalog plurals
FAIL: Madar/App/BackupSettingsView.swift:251: RU3 hand-built record count phrase requires catalog plurals
STATIC FAIL: 60 shipping Swift files, 1 catalogs, 38 independently measured M0 token pairs
MANUAL TRACE REQUIRED: 418 source lines; no complete string/key/colour/action or M0 acceptance claim
(exit 1; --require-complete also exit 1 with these actual findings)

Independent temporary Main -> Helper package probe:
Shipping target dependency omitted without error: True
Enumerated source targets: ['Main']
Omitted file has known lint error: ['Helper/File.swift:1: handwritten colour value']

git diff --check 2e58db3^..2e58db3
(exit 0, no output)
```

The new managed review checkout lacks ignored bundled fonts, so its first full checker invocation correctly failed on missing `Amiri-Bold.ttf`. Full checker outputs above were reproduced read-only in the original clean `codex/m0-source-checks` worktree at the exact `2e58db3` commit, where those resources exist; Python tests and the dependency probe ran in the separate review worktree.

The retained backup RU3/numeral findings are already owned by M0-T13; this review changes none of that source. No full manual trace, runtime colour/font measurement, VoiceOver, Reduce Motion, physical iPhone or M0 gate is claimed. Fix-only re-review of M0L-01 is required; do not repeat the unchanged production review.
