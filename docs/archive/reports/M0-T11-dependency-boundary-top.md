# M0-T11 — Top dependency argument boundary repair

11 October 2026 — codex, Top Sol xhigh. Narrow repair after M0L-01 remained open through the Standard fix/re-review. Base `33e1221`; code/test commit `54579a3`, branch `codex/m0-source-checks-top`, managed worktree `/Users/abdulrahman/.codex/worktrees/m0-source-boundary-top/بناء مدار 2.0`. Existing privacy/review branches and all production files were preserved. No app build, simulator or primary-checkout mutation.

The checker now requires the complete literal dependency argument to end before the target closes or the next labelled argument begins. Concatenation, conditional/member/closure suffixes after a supported literal prefix fail closed. Whitespace before the dependency label's colon cannot bypass the guard. This adds four boundary-check lines and adjusts that field match; it does not evaluate SwiftPM graphs or add target traversal/features.

The full-enumerator fixture contains Main, an independently enumerated MadarCore product, and an omitted Helper source with a independently detected handwritten red colour. Six computed expressions cover direct concatenation, a conditional concatenation, a conditional member suffix, a closure/member suffix, comments and line breaks. Before repair the new fixture produced six failures (`ValueError not raised`); after repair all six are rejected. Separate positive cases retain literal dependencies as the final argument, before resources and before a trailing comma. The existing negative forms also include a spaced label followed by a computed expression.

## Actual verification

```text
python3 -m unittest discover -s Madar/scripts/tests -v
Ran 12 tests in 0.007s
OK
```

The new managed checkout lacks ignored font resources; its direct full-checker invocation correctly failed on missing `Amiri-Bold.ttf`. For a comparable full baseline, both the original checker at `33e1221` and the repaired checker were run read-only against the unchanged `m0-foundation-times` checkout at `33e1221`, whose resources exist. The repaired module's `ROOT` was set to that baseline for this invocation only; no source or resource was copied/changed there. Both exited **1** and reported exactly:

```text
FAIL: Madar/App/BackupSettingsView.swift:124: RU3 hand-built record count phrase requires catalog plurals
FAIL: Madar/App/BackupSettingsView.swift:251: RU3 hand-built record count phrase requires catalog plurals
STATIC FAIL: 60 shipping Swift files, 1 catalogs, 38 independently measured M0 token pairs
MANUAL TRACE REQUIRED: 418 source lines; no complete string/key/colour/action or M0 acceptance claim
Fixed/baseline full inventories identical: True
```

Full JSON inventories compared equal: `/tmp/madar-m0-source-top-baseline.json` and `/tmp/madar-m0-source-top-fixed-baseline.json`. Pre-fix negative output: `/tmp/madar-m0-source-top-before.log`. `git diff --check` passed. The retained backup findings are expected in this historic baseline and are not fixed or reclassified here.

Fresh Standard fix-only review of `33e1221..54579a3` is required before integration. Root then runs the current integrated checker. This repair does not accept the 418 manual locations, runtime accessibility or M0; actual scope changes beyond the supported dependency syntax still require deliberate support.
