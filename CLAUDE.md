# Madar (مدار) — instructions for coding agents (Codex and Claude Code)

Codex loads this file as `AGENTS.md` and Claude Code loads it as `CLAUDE.md`. The two files are identical. Change both or neither.

## If you received these files as attachments

The owner attaches three files to your first session: `AGENTS.md`, `CLAUDE.md`, and `Madar - Handoff Review Fixes - V1.md`. Before any other work:

1. Put `AGENTS.md` and `CLAUDE.md` at the repository root, replacing the copies that came with the handoff bundle. Keep the two identical.
2. Put `Madar - Handoff Review Fixes - V1.md` in `docs/HANDOFF/`, next to the bundle.
3. Commit: `[M0-T00] Add agent protocol and review fixes`.

If the repo doesn't contain the handoff bundle yet, the owner attaches it too (`madar-handoff` zip). Unzip it into `docs/HANDOFF/`.

From then on, every agent that works on this repo follows this file, whether it is Codex, Claude Code or any other. Each agent re-reads it at the start of every session.

You are building **Madar**, a native iPhone app (SwiftUI, Arabic RTL). The approved spec is the handoff bundle in `docs/HANDOFF/`:
- `MADAR_HANDOFF.html`
- `screens/`
- `design-tokens.json`, `settings-schema.json`, `screens-index.json`, `data-dictionary.json`, `provenance.json`

If the bundle is not in `docs/HANDOFF/` yet, move it there in your first task.

## Source of truth

1. **Review fixes:** `docs/HANDOFF/Madar - Handoff Review Fixes - V1.md` overrides the handoff where they conflict.
   - `[FIX]` items correct defects. Apply them.
   - `[DEFAULT]` items are recommended changes, applied by default. The owner may revert any of them, and the reversal is logged in `docs/DECISIONS.md`.
2. **Then the handoff's own precedence** (full table in §1):
   - Behaviour, rules, formulas, and what ships in v1: the **text** wins, then the JSON, then the screenshots.
   - Exact values (keys, defaults, ranges, hex): the JSON files. A mismatch between JSON and text is a bug: apply the text and log it.
   - Layout only: the `canonical` screenshot wins. `superseded` and `deferred` screens are not built.
   - Sample numbers in screenshots are never hard-coded.
3. **New conflict:** apply this precedence, add a row to `docs/DECISIONS.md`, and continue. Ask the owner only if the conflict changes one of these:
   - a rule
   - a data-model field
   - a licence
   - a `[DEFAULT]` item

**Overrides in force from the review** (details in the fixes file):
- **RA1:** the v1 store is local-only. No CloudKit.
- **RA2:** only the app process opens the store. Extensions write to an inbox.
- **RA3:** M0 is lean.
- **RP1:** an unlogged prayer never becomes "missed" or qada automatically.
- **RU1:** never put "·" next to a digit.

## What to read: per task, never everything

Do not load the whole handoff into context. Each task card in `docs/PROGRESS.md` lists the spec sections and fix IDs it needs. Read those and nothing else, and use `grep` to find a section instead of reading the spec end to end.

| When | Read |
|---|---|
| Once per milestone | §1 Agent Brief, and that milestone's fix items |
| Room work | The room's §7.x, the §8 shared systems it references, and its fix items |
| Data, persistence, commands, widget plumbing | §10 and §11 (plus §9 for widgets) |
| Gates | §12 (gate) and §13 (tests) for the current milestone |

## Availability

- Every action, option, import source and Intent parameter is classed as v1, v2 or deferred. The §12 table, as amended by the fixes file, decides which.
- **No v1 build shows an entry point to a feature that is not v1.** That means no disabled buttons and no "coming soon".
- A room that is not built yet has no entry point anywhere: not in widgets, controls or Capture.

## Rules (from the approved brief)

**Design**
- **Same as the design or better, never worse.** Match the screenshots in layout, spacing, type and tone. Improve only when the result is clearly better on iOS 27 (a native component, accessibility, performance), and log the change in `docs/DECISIONS.md`.
- **Deployment target is iOS 26.0.** Features that need iOS 27 go behind `#available` with an iOS 26 fallback.
- **Arabic, right to left, everywhere.** Arabic-Indic digits by default.
- **Dates:** the primary date follows `core.firstCalendar` (Hijri first by default). The exception is the diary calendar, which is Gregorian first (`notes.calendarFirst`).

**Day boundary and data**
- `core.dayStart` governs every room. The one exception: prayer records are grouped by prayer day (Fajr to the next Fajr). A stored `dayKey` is never recomputed.
- One fact is recorded once: the owning room writes it, and other rooms read it. Each number has one definition (§8).
- Every setting ships with the agreed default from `settings-schema.json`, a reset, and undo. Appearance settings never change data.

**Prayer sanctity**
- From adhan until the sanctity window ends (adhan + 30 min; Maghrib + 20 min), nothing reaches the user: no notification, sound or Live Activity alert. This is not a setting.
- Every scheduled time goes through the single guard in fix RP3.

**Colour, text and accessibility**
- Base colours are for shapes and large text. Text under 24 pt uses the `*Text` variants in `design-tokens.json` (contrast ≥ 4.5:1).
- Use only the colour pairs listed in `contrast.pairs`. Minimum text size is 11 pt.
- Dynamic Type works up to AX5 everywhere. From AX1 up, each custom drawing switches to its list alternative. The one exception is the Mushaf page text, which offers zoom and a semantic ayah layer instead.

**Money and streaks**
- Money amounts are `Int` minor units.
- Streaks are derived, never stored.

**Prototype-only elements.** Don't build these as features: the day/night buttons, scene panels, and the sample numbers in screenshots.

**Engines and tests**
- The engines (prayer times, Quran scheduling, money, habits, streaks, day boundary, notifications) are pure Swift.
- Each engine has behavioural tests against golden fixtures, and the expected values come from the spec (§13). Never generate expected values from the code's own output.
- Never report something as tested without command output that shows the result.

**Notifications**
- The notification budget is per device.
- Never build logic on "delivered".

**Widgets**
- The OS chooses the widget family.
- Widgets read JSON snapshots only.

**Persistence**
- Optional or defaulted properties, no unique constraints, optional relationships.
- Deletes use tombstones. Uniqueness comes from natural keys, with a dedupe pass after every import.
- Use the single `MadarData` ModelContainer factory, local-only in v1 (RA1).

**Asking the owner.** Ask only about:
- items tagged *open* in §15
- licensing
- a rule here that must change
- a `[DEFAULT]` item you think is wrong

## Build machine

- The owner's Mac is Apple silicon. Building, the simulator and on-device runs all happen there.
- A session without macOS (Codex cloud, a Claude Code cloud session) writes code and pure-Swift tests only. It never claims a build or run it could not perform.

## Milestones

The order is M0 Foundation, M1 Prayer, M2 Quran, M3 Diary, M4 Lobby + Habits + Widgets, M5 Money, M6 Mihbara, M7 final integration.

- M0 is lean (fix RA3).
- Inside each room, build the minimal version first, then the rest of the room spec as follow-up tasks.
- Each milestone ends with a build on the owner's iPhone that passes its acceptance checks.

---

## Working protocol — owner revision, 12 October 2026

This revision replaces the previous working protocol, model-tier table, blanket Top reviews and M0 task order. It implements the owner's request for usable progress every development session and permission to use GPT-6 Luna max for production. Product rules above, data preservation, licences, RA1/RA2/RP1 and honest acceptance remain in force. Historical handovers, reports and automation memory are evidence, not instructions overriding this revision.

### 1. What a session delivers

- A development session must target at least one usable result: a working screen/flow, an integrated feature, a finished engine with independent golden cases, or a reproduced defect repaired and verified. State the before/after acceptance in one sentence before coding.
- Reports, source inventories, plans, test counts, screenshots of unchanged flows and branch claims are not product delivery. A documentation-only session is appropriate only when the owner explicitly requests documentation/process work, or no authorized implementation can proceed; record the exception honestly.
- Start with one coherent task. Finish and check it before starting another. Simple tasks may be grouped and completed sequentially; do not stop after one small task when more useful authorized work fits the remaining usage.
- Never promise success in every session or mark a failed/unavailable acceptance done. If blocked, diagnose once, allow at most two evidence-based repairs, then preserve the work and switch to an independent useful card. If every card is blocked, state the exact blocker and smallest next action instead of manufacturing delivery.
- The repo is the shared memory: root AGENTS/CLAUDE, docs/PROGRESS.md, docs/DECISIONS.md, existing reviews and Git. Do not ask the owner to reconstruct the previous session.

### 2. Start: bounded check, then implement

1. Read this file, the current board and only the latest handover in docs/PROGRESS.md. Run git status and git log --oneline -10. Read only the selected card's spec/fixes and risky changes relevant to it.
2. Reuse passing output for identical source/configuration. Do not rebuild the app, rerun all packages, audit old branches or re-review accepted work merely because a session started.
3. Select the first ready product card in the current queue and state its observable result. Treat historical Top labels and unresolved optional diagnostics according to the current board, not as an automatic stop.
4. Fix a reproduced defect that blocks the selected flow before extending it. Other unresolved checks remain attached to their affected feature; they do not block unrelated software work.
5. Update Last checked briefly with revisions inspected and evidence reused. Default to implementation after this bounded check; do not open a new planning/source-map report as the session's work.

### 3. Scope, milestones and branches

- Plan only the next section with 2–4 coherent cards: scope, exact spec/fix references, observable acceptance and exclusions. Reuse an existing architecture note; write a new one only for an unresolved design decision, at most 15 lines before implementation.
- Follow RA3 literally. M0 software acceptance covers tokens/fonts, MadarDay/Hijri/prayer times, one glass shell, M1-needed settings/models, app-only command/inbox writing and plain export. Preserve existing extra code/data without expanding the gate to encrypted-backup matrices, all future models, full notification/widget systems or repeated manual source maps.
- Repair a confirmed privacy/data-loss defect in an exposed route before accepting that route. Missing native/physical proof remains not tested. Never disable authentication, suppress an audit or delete previous work to force a pass.
- Separate **software readiness**, **owner-iPhone acceptance** and **distribution**. After the lean software dependencies are accepted, M1 software implementation may proceed while the owner-iPhone check is pending. Full M0/M1 acceptance and distribution still require their actual device evidence. This owner-authorized workflow change supersedes the old blanket 'no M1 until full M0 approval'; it is not a device-gate pass.
- main must build. Prefer one author, one branch per section with codex/ prefix. Reuse the current suitable worktree; do not create branches/worktrees for each diagnostic, report or review. Review and integrate a completed slice promptly rather than accumulating complete work offmain.
- Preserve unrelated edits, retained branches, ignored fonts/evidence and owner data. No force push, history rewrite, broad formatting or deletion of another agent's work.

### 4. Model choice — Luna max is allowed to build

- **Default for the owner's automated development: GPT-6 Luna, max effort.** Luna may write production Swift, screens, engines, persistence, commands and behavioural tests; it is no longer restricted to mechanical work. Quality is judged by the implementation and acceptance evidence, not a tier label.
- Keep tasks explicit and bounded: reuse working patterns, read only necessary files, test the actual changed behavior and finish the usable slice. max effort is a supported setting, not a guarantee of Sol-level results or a successful session.
- Sol is an escalation option, not a mandatory author/reviewer for every task. Escalate a narrow unresolved problem after two diagnosed repair attempts, an unresolved rule/design conflict, or a migration/security/concurrency change that the author cannot validate adequately. Do not rewrite a working feature merely to obtain a stronger-model label.
- Section review must be independent for new migration/data-loss, authentication/privacy, notification-sanctity and concurrent store/intent changes. A fresh Luna max reviewer may review a clearly specified slice; use GPT-6.1 Sol high/xhigh when the review has an unresolved risky decision or failed repair. Reuse existing independent approval for unchanged source.
- UI-only/routine changes need the author's focused self-check; there is no mandatory reviewer agent for each small change. Each milestone has one scoped gate against its integrated revision; there is no mandatory Top-tier stop solely because the card historically says Top.
- The owner/app selects the root model; an agent cannot claim to change itself. Record the actual model/effort when exposed, otherwise 'not exposed'. Never claim a tier that did not run.
- Subagents are optional for a real independent job, not a standing team of author/reviewer/build/usage agents. Avoid delegation for small cards; only one actor controls the same file or simulator. No polling agent for usage.

### 5. Verification and integration

- Choose the smallest sufficient check for the change. Production Swift/configuration changes need relevant compilation and affected behavioural tests; engine expected values come from the spec, never from the engine's output.
- UI changes need a real changed-flow smoke test and actual screenshot at default size plus AX3 when layout changed. Reuse unchanged dark/AX5/other-flow evidence; perform broader device/OS checks only when that feature's acceptance needs them.
- Distinguish a build failure, test-setup failure and product failure before retrying. Passing mocked/hosted tests, native simulator flows, physical-device checks and distribution are separate claims.
- Independent review, where section 4 requires it, covers only the selected production diff and its dependencies. Fix Critical/High findings before merging the affected change. A re-review covers only the repair. No reviews of reviews, generated assets or unrelated historical candidates.
- A completed card must reference the integrated commit or exact preserved branch tip, command result and usable screen/flow. An unmerged candidate is not delivered on main; say what remains before integration.
- Documentation-only changes need consistency and git diff --check, not app/package builds. Use one short handover and update the existing acceptance row; do not create a new report for every small check.

### 5a. Usage and workspace preparation

- Before a native build/test in a new or reused worktree, run python3 Madar/scripts/prepare-workspace.py from the repository root. Use --source <verified-local-repo> only for missing pinned resources. Never download, publish or overwrite conflicting private fonts. Preparation alone proves no build/signing/runtime acceptance.
- Preserve the owner's usage target: **deliver with approximately 5% of the five-hour allowance remaining; 3–5% is the final reserve, never deliberately consume the last 3%.** Check at start, task boundaries, before expensive work and before delivery; do not poll continuously or use reset credits automatically.
- When a simple card is complete and more than 5% remains, pick another ready useful card that can be completed, verified and handed over within the remaining budget. Several small completed features/fixes in one session are encouraged. Section completion is not automatic session termination; review/integrate or continue independent authorized work.
- Begin finalizing near 95% used. Do not start a large uncertain task near the reserve. Spend allowance on product progress, not duplicate green tests, inventories, reports or artificial work to reach a percentage.
- Weekly/account/tool limits and real blockers may end work earlier; record the actual limit/blocker. If telemetry is unavailable, report that the reserve could not be verified. Never invent a percentage or claim a guaranteed session outcome.
- A specific owner-requested documentation/process task does not authorize unrelated product changes merely to spend usage. The multi-card delivery target governs development/continuation sessions within their authorized scope.

### 6. Failure handling

- Diagnose the first failure before retrying. After two evidence-based repairs fail, preserve the current branch, raw output and last green revision; split/escalate the precise problem and continue another independent ready card. Do not revert shared or accepted work, or discard the failed diff.
- Do not repeat an unchanged nil-element accessibility audit or guess a color fix. Keep the issue open and pursue an actionable target only when it is the selected task; otherwise build independent functionality.
- Escalate to the owner only for a new product-rule/default/licence decision or when no authorized path exists. Routine implementation decisions and previously authorized changes need no repeated permission.
- Previous-session defects get a separate [fix-previous] commit when practical, with a regression that demonstrates the failure; do not hide them inside unrelated work.

### 7. Handover on clean main

- Commit each completed coherent slice separately after its focused check. Integrate accepted production through the section branch; never copy production files onto main as a docs handover shortcut.
- Put the short handover/board update on main even when production remains unmerged. Leave the shared checkout on main and clean without disturbing owner changes.
- Handover fields: **Works now**, **Verified** (exact command/output or unchanged evidence revision), **Not verified**, **Next concrete result**, **Active branch/worktree/tip**, **Model/effort**, **Usage**. A blocker comes first when no product task completed.
- Link docs/reports/M0-retained-branches.md for unchanged historical inventory; name only branches/worktrees changed or relevant this session. Do not repeat 30 historical refs in each handover.
- Keep the current queue and at most five handovers in PROGRESS.md; archive older notes. Historical recommendations are superseded by the current queue.
- Commit format: [M1-T03] <result> (codex|claude, model: <actual or not exposed>, effort: <actual or not exposed>).

### 8. Historical first-run tasks

M0-T00 file placement, handoff extraction, Before-M0 corrections, owner runbook and architecture are complete. Reuse them; do not restart foundation planning. New room packages get short identical AGENTS.md/CLAUDE.md files referencing the root protocol and the room's product rules/fix IDs.
