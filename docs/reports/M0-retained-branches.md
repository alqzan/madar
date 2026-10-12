# M0 retained branches and worktrees

Snapshot: 2026-10-12 at main `fadbe69`, before the documentation-only license update. These refs and worktrees were left untouched by that update. “Do not merge” means preserve the evidence and require a current, scoped board decision; it is not permission to delete the branch or worktree.

## Non-merged branch tips

| Branch | Tip | Merge disposition / next step |
|---|---:|---|
| `codex/m0-accessibility-audit` | `97a1577` | Failed predecessor; preserve, do not merge. |
| `codex/m0-accessibility-fixes-review` | `851c6cd` | Review evidence only; preserve for T12, no production merge. |
| `codex/m0-accessibility-host` | `c273bc4` | Host/focus candidate; T12 contrast remains unresolved, no merge. |
| `codex/m0-accessibility-top` | `d3fc0cc` | Top review evidence; preserve, no production merge. |
| `codex/m0-export-privacy` | `2ea40ff` | P1b predecessor; continue only from repaired candidate after native acceptance. |
| `codex/m0-gate-readiness` | `7169fab` | Report candidate; reconcile against current M0 report before copying any docs. |
| `codex/m0-p1a-terminal-review` | `3a2bf6b` | Review evidence; preserve, no production merge. |
| `codex/m0-p1b-fixes` | `173fe0c` | Repaired T09 candidate with fix-only Top approval; finish native acceptance and section review before merge. |
| `codex/m0-p1b-rereview` | `8876626` | Fix-only Top review evidence for the candidate; no code merge. |
| `codex/m0-p1b-top-review` | `38d4fec` | Review evidence; preserve, no production merge. |
| `codex/m0-privacy-host` | `48a3fe4` | Old integration has three High findings; do not merge. |
| `codex/m0-source-checks-fix-review` | `ffc8e97` | Older source-check review evidence; current T11 is integrated, preserve only. |
| `codex/m0-t12-audit-triage` | `44d4799` | Diagnostic only; obtain an actionable Inspector trace and resolve T12 before merge. |
| `m0-fix-previous-plurals` | `cede9ee` | Older RU3 history; equivalent accepted fix is already on main, do not merge again. |
| `m0-fix-previous-prayer` | `9e4e6f9` | Historical fix branch; preserve, no merge without a new scoped defect. |
| `m0-inbox-lifecycle-tests` | `169d4e5` | Preserve; compare only if a specific T02 coverage gap is reopened. |
| `m0-s1-local-retention` | `4297c8a` | Historical candidate; accepted retention work is already integrated, no wholesale merge. |
| `m0-s1-money-models` | `dad332e` | Historical migration candidate; compare only for a specific remaining compatibility gap. |
| `m0-s2-backup-focus` | `9c0f47a` | Failed diagnostic predecessor; preserve, do not merge. |
| `m0-s2-backup-local-only-copy` | `d4a869d` | T14 equivalent is integrated as `d28c36a`; preserve branch history, do not merge again. |
| `m0-s2-foundation-times` | `1308a5b` | Older T10 candidate; accepted scope is integrated, no wholesale merge. |
| `m0-s2-presentation-privacy` | `8e643a1` | Older privacy candidate; preserve, continue from repaired T09 branch only. |
| `m0-s2-privacy-compile-top` | `5102620` | Compile/review evidence; preserve, no production merge. |
| `m0-s3-font-license-evidence` | `6227d1f` | T06 docs candidate predates T14; selected evidence is on main, do not merge product tree. |
| `m0-software-check-plan` | `ff09f96` | Plan evidence; current T11 scope is integrated, preserve unless a board item reopens it. |
| `m0-t11-source-checks-review` | `946c87d` | Older T11 review evidence; accepted implementation is on main, no code merge. |

## Worktrees

| Worktree | Branch @ HEAD | Disposition |
|---|---|---|
| `/private/tmp/madar-m0-p1b-top-review` | `codex/m0-p1b-top-review` @ `38d4fec` | Preserve review evidence. |
| `/Users/abdulrahman/.codex/worktrees/m0-arabic-plurals/بناء مدار 2.0` | `m0-s1-money-integration` @ `2fc39ab` | Accepted predecessor; preserve. |
| `/Users/abdulrahman/.codex/worktrees/m0-command-inbox/بناء مدار 2.0` | `m0-s1-command-inbox` @ `76bab3c` | Accepted predecessor; preserve. |
| `/Users/abdulrahman/.codex/worktrees/m0-foundation-times/بناء مدار 2.0` | `codex/m0-source-checks-terminal-review` @ `a399b1f` | Accepted T11 review evidence; preserve. |
| `/Users/abdulrahman/.codex/worktrees/m0-gate-report/بناء مدار 2.0` | `codex/m0-gate-readiness` @ `7169fab` | Reconcile report before copying. |
| `/Users/abdulrahman/.codex/worktrees/m0-local-data/بناء مدار 2.0` | `m0-s1-money-models` @ `dad332e` | Preserve candidate; no wholesale merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-p1b-fixes/بناء مدار 2.0` | `codex/m0-p1b-fixes` @ `173fe0c` | Finish native T09 acceptance/review before merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-p1b-rereview/بناء مدار 2.0` | `codex/m0-p1b-rereview` @ `8876626` | Preserve review evidence. |
| `/Users/abdulrahman/.codex/worktrees/m0-plain-export/بناء مدار 2.0` | `m0-s1-plain-export` @ `69b0698` | Accepted predecessor; preserve. |
| `/Users/abdulrahman/.codex/worktrees/m0-presentation-privacy/بناء مدار 2.0` | `codex/m0-export-privacy` @ `2ea40ff` | Preserve predecessor; use repaired T09 candidate. |
| `/Users/abdulrahman/.codex/worktrees/m0-source-boundary-top/بناء مدار 2.0` | `codex/m0-source-checks-top` @ `3ade5a5` | Accepted T11 review evidence; preserve. |
| `/Users/abdulrahman/.codex/worktrees/m0-source-checks-review/بناء مدار 2.0` | `codex/m0-accessibility-top` @ `d3fc0cc` | Preserve T12 review evidence. |
| `/Users/abdulrahman/.codex/worktrees/m0-t12-audit-triage/بناء مدار 2.0` | `codex/m0-t12-audit-triage` @ `44d4799` | Preserve diagnostic; T12 unresolved. |
| `/Users/abdulrahman/.codex/worktrees/m0-ui-debug/بناء مدار 2.0` | `codex/m0-accessibility-fixes-review` @ `851c6cd` | Preserve review evidence. |

The shared checkout remains `main`. Do not hand off by switching the shared checkout to any candidate branch.
