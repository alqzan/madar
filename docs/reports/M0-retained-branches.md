# M0 retained branches and worktrees

Snapshot: 12 October 2026, after reviewed M0-T15 integration. Current git refs, not old handover tips. No pre-existing branch/worktree was deleted. See PROGRESS for the next acceptance; historical branches are not a queue of new reviews.

## Active candidates

- T09: `codex/m0-p1b-fixes` — repaired source; actual AX3 success/cancellation are partial evidence. Preserve T14 copy during eventual integration.
- T12: `codex/m0-t12-audit-triage` — prepared resources, executed diagnostic, contrast remains unresolved.
- All other non-merged refs below retain historical/source/review evidence; do not merge them wholesale.

## Every non-merged branch

| Branch | Current tip | Disposition |
|---|---|---|
| `codex/m0-accessibility-audit` | `97a1577` | Failed predecessor; preserve, do not merge. |
| `codex/m0-accessibility-fixes-review` | `851c6cd` | Review evidence only; preserve for T12, no production merge. |
| `codex/m0-accessibility-host` | `c273bc4` | Host/focus candidate; T12 contrast remains unresolved, no merge. |
| `codex/m0-accessibility-top` | `d3fc0cc` | Top review evidence; preserve, no production merge. |
| `codex/m0-export-privacy` | `2ea40ff` | P1b predecessor; continue only from repaired candidate after native acceptance. |
| `codex/m0-gate-readiness` | `7169fab` | Report candidate; reconcile against current M0 report before copying any docs. |
| `codex/m0-p1a-terminal-review` | `3a2bf6b` | Review evidence; preserve, no production merge. |
| `codex/m0-p1b-fixes` | `daa9e99` | Active T09 at native auth/cancellation and retirement matrix partial acceptance; finish remaining privacy flows and section review before merge. |
| `codex/m0-p1b-rereview` | `8876626` | Fix-only Top review evidence for the candidate; no code merge. |
| `codex/m0-p1b-top-review` | `38d4fec` | Review evidence; preserve, no production merge. |
| `codex/m0-privacy-host` | `48a3fe4` | Old integration has three High findings; do not merge. |
| `codex/m0-source-checks-fix-review` | `ffc8e97` | Older source-check review evidence; current T11 is integrated, preserve only. |
| `codex/m0-t12-audit-triage` | `bfa878b` | Active diagnostic; fonts validated/build passes, .all contrast still fails; do not merge as a repair. |
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

## Every non-main worktree

| Worktree | Current branch / HEAD | Disposition |
|---|---|---|
| `/private/tmp/madar-m0-p1b-top-review` | `codex/m0-p1b-top-review` @ `38d4fec` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-arabic-plurals/بناء مدار 2.0` | `m0-s1-money-integration` @ `2fc39ab` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-command-inbox/بناء مدار 2.0` | `m0-s1-command-inbox` @ `76bab3c` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-foundation-times/بناء مدار 2.0` | `codex/m0-source-checks-terminal-review` @ `a399b1f` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-gate-report/بناء مدار 2.0` | `codex/m0-gate-readiness` @ `7169fab` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-local-data/بناء مدار 2.0` | `m0-s1-money-models` @ `dad332e` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-p1b-fixes/بناء مدار 2.0` | `codex/m0-p1b-fixes` @ `daa9e99` | Active T09 candidate; repaired guards and native AX3 partial acceptance, complete remaining section acceptance before curated merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-p1b-rereview/بناء مدار 2.0` | `codex/m0-p1b-rereview` @ `8876626` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-plain-export/بناء مدار 2.0` | `m0-s1-plain-export` @ `69b0698` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-presentation-privacy/بناء مدار 2.0` | `codex/m0-export-privacy` @ `2ea40ff` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-source-boundary-top/بناء مدار 2.0` | `codex/m0-source-checks-top` @ `3ade5a5` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-source-checks-review/بناء مدار 2.0` | `codex/m0-accessibility-top` @ `d3fc0cc` | Preserve evidence; use current PROGRESS card before any merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-t12-audit-triage/بناء مدار 2.0` | `codex/m0-t12-audit-triage` @ `bfa878b` | Active T12 diagnostic; fonts ready/build passed, unsuppressed contrast audit still fails; no wholesale merge. |
| `/Users/abdulrahman/.codex/worktrees/m0-ui-debug/بناء مدار 2.0` | `codex/m0-accessibility-fixes-review` @ `851c6cd` | Preserve evidence; use current PROGRESS card before any merge. |

Main remains the shared clean handover checkout. M0-T15 tooling was merged; its temporary managed worktree was recoverably archived after integration. All prior worktrees are preserved.
