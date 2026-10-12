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

## Working protocol: Codex and Claude Code together

### 1. How the two agents work together

- **Codex and Claude Code both work on this repo, taking turns.** Either one can pick up where the other stopped. There are no fixed roles: every session does the same three things, in this order:
  1. a quick check of the previous session's work
  2. fixes for anything that check found
  3. new work from the board
- **The repo is the only shared memory:**
  - `docs/PROGRESS.md`
  - `docs/DECISIONS.md`
  - `docs/reviews/`
  - the git history

  Nothing from your chat carries over to the other agent.
- **Don't disturb working code.** Fix real defects only. Don't rewrite, rename, reformat or reorganise the other agent's code because you would have done it differently. If you disagree with a choice that works, note it under **Later** or in `DECISIONS.md`.
- **Never:**
  - force-push
  - rewrite shared history
  - reformat the whole repo
  - delete another agent's work without a note in the handover
- **One agent at a time is preferred.** If both must run at the same time, each takes a different section, claims it in `PROGRESS.md` on `main` before starting, and works on its own branch.

### 2. Start of every session: check, fix, then continue

**Trigger.** If the owner starts a session with only «اكمل» / "continue" (or any short go-ahead), that is the whole instruction: run this section from step 1, then do the next task on the board. Do not ask what to do. The owner should never have to explain where work stopped. `docs/PROGRESS.md` on `main` is that explanation.

1. Read this file, then `docs/PROGRESS.md`: the current milestone, the board, the **Last checked** commit, and the latest handover.
2. Run `git status` and `git log --oneline -20`.
3. **Quick check of the previous session.** Keep it short. It's a sanity check, not a full review.
   - Build and run the tests. Everything must be green.
   - Read the latest handover, including its **For the next agent** notes.
   - Look over what changed since **Last checked**: run `git diff --stat <last-checked>..HEAD`, then open only the files that look risky (engines, data model, notifications, anything the handover flags).
   - Compare the finished task cards with their acceptance checks.
4. **Fix what's broken before any new work.** One small commit per fix, tagged `[fix-previous]`, with a test where it makes sense.
5. **Update Last checked** in `PROGRESS.md` with one line: `Checked <from>..<to> — OK` or `Checked <from>..<to> — 2 issues, fixed in <commit>`.
6. **Continue** with the next task on the board.

### 3. Work size: big pieces, your call

- **Plan a milestone before coding it.**
  - In `PROGRESS.md`, split it into 2–4 **sections**. Each section is a visible piece of the room, for example M1-S1 "prayer home and logging" or M1-S2 "notifications and sanctity".
  - Split each section into **task cards** (`M1-T01`, `M1-T02`, …). Each card holds scope, spec references, fix IDs, acceptance checks, and what is out of scope.
- **A task is a coherent slice:** a screen with its logic, an engine with its tests, or a feature end to end. As a guide, keep a task under about 1,500 changed lines, not counting generated files, fixtures and assets.
- **Finish as much as you can in one session.** You may complete several task cards back to back. Commit each task separately, and run its self-check before starting the next.
- **Stop and hand over** when any of these happens:
  - a section is complete, so it now needs a section review
  - a self-check fails and two fix attempts didn't solve it
  - a spec conflict needs the owner
- **These sizes are guides, not hard caps.** You may go past them with a one-line reason in the handover.
- **Stay inside the plan:** no unrelated refactors and no features from later milestones. Ideas go under **Later**.
- **`main` must always build.** Work on one branch per section, named `m1-s2-short-name`. Merge it once the section review passes.

### 4. Models and effort: quality first, no waste

**Quality is the constraint, not time.** The owner accepts a longer project but not lower quality. The result must match the design and the spec, or be better.
- Never drop to a weaker tier or a lower effort to save tokens on work that affects quality.
- If a usage limit runs out, stop at a clean point and write the handover. The owner continues later or hands over to the other agent. Don't skip a step and don't downgrade.

| Tier | Codex | Claude Code | Use for |
|---|---|---|---|
| Standard | GPT-6.1 Sol, medium or high effort | Sonnet | Writes all production code: engines, data model, screens, features, tests |
| Top | GPT-6.1 Sol, xhigh effort | Opus (or the strongest Claude model you have) | The quality points below, and bugs the Standard tier couldn't fix |
| Light | Luna | Haiku | Mechanical work only: strings and localisation, renames, formatting, fixture data, splitting files, searches. Never production logic |

**Astra is not used in this project.** On coding, GPT-6.1 Sol matches it at about a fifth of the cost and runs faster. Always use GPT-6.1 Sol, not the older GPT-6 Sol.

**Use the Top tier at these points, and only these.** You don't need to ask whether to use it: plan it as described under "How a tier change actually happens", and record the reason in the handover.
- **Design notes before coding:**
  - M0's architecture
  - each engine: prayer times and day boundary, notification arbiter, Quran scheduler, money engine, bank-SMS parser

  A design note is short: types, rules, edge cases, test plan.
- **Section reviews** of any section that contains:
  - an engine
  - data-model or migration changes
  - notifications and sanctity
  - widget or intent plumbing
  - anything concurrent
- **Every milestone gate.**
- **A bug that survived two Standard-tier attempts,** after you reverted and split the task.

Reading and reviewing cost far fewer tokens than writing, so this spends the Top tier where it raises quality most.

**How a tier change actually happens.** The owner picks the model and effort when starting a session, and you can't change your own mid-session. So:
- Give each Top-tier point its own task card, marked `Top`.
- Stop before that card and say so in the handover: `Next session: Top (GPT-6.1 Sol xhigh, or Opus)`.
- If your tool can start a subagent with a chosen model or effort, you may run the Top-tier step as a subagent instead.
- Light-tier work can simply be done on the Standard tier when switching isn't worth it. The reverse is never allowed: production logic is never written on the Light tier.
- Never claim a tier you didn't run on.

**Effort.** The owner picks the effort level when starting a session. Recommended:
- **medium:** routine screens and features
- **high:** engines, data model, notifications, widget plumbing, and every review
- **xhigh:** the Top-tier points in Codex. In published coding-agent tests, GPT-6.1 Sol scored higher at xhigh than at max.
- **Opus in Claude Code:** high
- **max:** not needed

Write the recommended tier and effort for the next session in your handover.

**Tests come first for engines.** Write the golden-fixture tests from the spec's worked examples before writing the engine code.

**Subagents** are for independent, narrow jobs that can run in parallel, at the tier the job needs under the rules above. For example:
- write an engine's fixture tests while you implement the engine
- compare a built screen with its canonical screenshot
- review a section with a fresh context

Give each subagent a one-paragraph brief and ask for a short result. Never ask a subagent to read the whole spec.

**Commit messages record the tier you used.**

### 5. Reviews: four kinds, each with a purpose

1. **Self-check, after every task.**
   - Build: `xcodebuild` for the app, `swift test` for packages.
   - Run the task's tests and the lint tests: no colour literals, no "·" next to a digit, setting keys exist in the schema, availability flags respected.
   - For UI: run the screen in the simulator at default size and at AX3, take a screenshot, and compare it with the canonical screenshot.
   - Paste the last lines of each command's output into the handover.
2. **Quick check, at the start of every session** (section 2).
3. **Section review, after each big section.** It happens before the next section starts.
   - **Reviewer:** the agent that did not build most of the section. If that agent isn't available, a reviewer subagent with a fresh context does it.
   - **Tier:** Top for the kinds of section listed in section 4; Standard for sections that are only UI.
   - **Input:**
     - the section's diff, read commit by commit (`git log -p main..<section-branch>`)
     - the section's task cards
     - the spec sections and fix items those cards cite
   - **Run the section's flows** in the simulator. Use the iPhone when notifications, widgets or Live Activities are involved.
   - **Compare each screen with its canonical screenshot** at default size, at AX3, and in dark mode where a dark reference exists. A screen that is worse than the design is a High finding.
   - **Checklist:**
     - Does it do what the cards say, and only that?
     - Are the spec and the fix items respected? That means the rules, defaults, availability, privacy and sanctity.
     - Are the tests meaningful, with expected values taken from the spec?
     - Does new UI handle RTL, Arabic-Indic digits, Dynamic Type and VoiceOver labels?
     - Are there hard-coded sample data, colours or setting values?
   - **Output:** write `docs/reviews/<section-id>.md` containing:
     - a verdict: `approve` or `changes requested`
     - at most 15 findings, each with file:line, a severity (Critical/High/Medium/Low) and the fix

     "No findings" is a valid, short review.
   - **Critical and High findings** are fixed before the next section starts.
4. **Milestone gate, at the end of each milestone, on the Top tier.** Run the milestone's acceptance checks from §12 and §13. Record the results in `docs/reports/M<n>.md`, and mark anything not tested as "not tested".

**Don't waste tokens:**
- Never re-read the whole handoff.
- Never review generated code, assets or unchanged files.
- No style nitpicks that break no rule.
- Never review a review.
- One review pass per change. A re-review covers only the fix diff.
- If the same mistake appears twice, add a test or a lint check instead of reviewing for it again.

### 5a. Session progress and usage — owner instruction, 11 October 2026

- Workspace preparation: before a native build/test in any new or reused worktree, run `python3 Madar/scripts/prepare-workspace.py` from the repository root. Missing private font resources are prepared only from an explicit verified local source using `--source <repo>`; never download, publish, overwrite a mismatched resource or spend build attempts discovering missing fonts. This font check does not prove build/signing/runtime readiness. `make generate/build/preview/test-ios/test-links` enforce it.

- Continuation discipline (owner request, 12 October 2026): follow the current Recommendations in `docs/PROGRESS.md`. Prefer finishing a missing acceptance result over restarting planning or writing another source-map report. Historical handovers/branches are evidence, not current instructions to reopen closed work; verify their blocker still exists. Review only the selected current candidate/change, not superseded candidates or reviews.
- A failed runtime check is not always a build defect. Record whether failure occurred before XCTest, in test setup/authentication, or in product acceptance; rerun only after a diagnosed change or to obtain genuinely new evidence. An unchanged nil-element accessibility failure needs an actionable trace, not another identical audit or a speculative color/suppression change.
- Acceptance/integration discipline: source review, mocked/hosted tests, native simulator flows and owner-iPhone gates are separate. Integrate accepted scope after its required review without reverting previously accepted work; do not inflate lean M0 with deferred features or reopen owner-confirmed licensing decisions without new relevant evidence.

- At the start, select one coherent task from the board and state its concrete acceptance result: a working screen/flow, a finished engine, a proven defect repair, or the decision required by a review card. Finish it before opening another independent task. Aim for at least one completed, verifiable task per session; this is a target, never permission to skip acceptance or fabricate completion.
- The initial sanity check stays bounded to the latest handover and risky changes. Do not turn it into another full review. If a required check has current passing evidence for the same code/configuration, reuse that evidence and cite its commit/output. Re-run only when a relevant change, failed result or explicit acceptance requirement justifies it; record the reason before an expensive repeat.
- Diagnose the first failed output before retrying. Respect the existing two-repair-attempt limit; do not cycle through equivalent simulator setup, broad audits or reviews. After the limit, preserve the evidence, split/escalate the problem and continue another independent authorized task if available. An unavailable manual UI does not block work that can proceed independently.
- Report progress as what now works and what remains, not counts of searches, builds or reviews. If the session produces no completed task, record the concrete blocker, what was tried, and the smallest next step in the handover. Test counts alone do not count as delivered functionality.
- Owner clarification (11 October 2026): use the smallest sufficient checks for the changed behavior. Do not run full app/package suites, broad audits or the full UI matrix after every task, and do not run product builds/tests for documentation-only changes. Existing current green evidence satisfies unchanged checks. This overrides blanket repeated-run wording in the start-of-session/self-check steps; necessary regression checks and milestone acceptance still apply.
- The session delivery target is **3–5% of the five-hour usage remaining** (95–97% used), not merely “stop near 90%.” Check usage at session start, task boundaries and before expensive work; keep the handover current while working and start finalizing around95%. Do not end a work session with more than5% remaining just because one task or section finished: complete the required review or select the next authorized useful task small enough to finish within the remaining budget. Section/review boundaries govern integration, not automatic early session termination. Verify usage after preparing the handover and before the final delivery. Never spend the margin on duplicate checks or artificial work; spend it on actual board progress and a clean main handover. Do not deliberately consume the last3% and risk interrupting delivery. If the usage reading is unavailable, explicitly report that the percentage target could not be verified.
- Keep quality, mandatory reviews and milestone gates intact. Use the required model tier; avoid unnecessary delegation and duplicate review. A completion/session estimate is provisional and must be revised using actually completed tasks, not presented as a deadline or quota.

### 6. When something goes wrong

- **Critical and High findings block the merge.** Fix them on the same branch and add a regression test named after the finding (`test_M1S2_<finding>`).
- **If the build or the tests still fail after two attempts:**
  1. Stop.
  2. Revert to the last green commit.
  3. Split the task smaller.
  4. Solve that problem on the Top tier (section 4).
  5. If it still fails, write it up in the handover and ask the owner.
- **A fix that would change a spec rule or a `[DEFAULT]` item:** log it in `DECISIONS.md` and ask the owner. Meanwhile, continue with other tasks.
- **Damage you find from an earlier session** (one the quick check missed): fix it in a `[fix-previous]` commit with a test, and mention it in the handover. Never patch it silently inside an unrelated task.

### 7. End of every session: handover

**The handover must reach `main`.** The next agent starts from `main`, so a handover that exists only on a work branch is invisible to it. Before you stop, whatever branch you worked on:
1. Commit your `docs/PROGRESS.md` update (board, Last checked, handover) to `main` as a docs-only commit: `git checkout main`, `git checkout <branch> -- docs/PROGRESS.md`, commit. Never put code on `main` this way.
2. Name every unmerged branch and worktree in the handover, with its latest commit and what is needed to merge it.
3. Leave the shared checkout on `main`, clean (`git status`), so it builds.
4. Anything you could not finish goes in the handover as the first line of **For the next agent**, not only in chat.

**Commit message format:** `[M1-T03] <what> (codex|claude, tier: standard)`

**Update `PROGRESS.md`:**
- Task status: `todo`, `in-progress`, `done` or `needs-fix`.
- Section status: `building`, `in-review`, `changes-requested` or `approved`.
- A handover note at the top of **Handovers**:

```
### Handover — M1-S2 (M1-T03 to M1-T05) — 12/10/2026 — codex (Sol)
Done: …
Verified: <commands and the last lines of their output>
Not verified: … (why)
For the next agent: what to check first, risks, shortcuts, open questions
Next: …
Next session: recommended tier and effort
```

Keep `PROGRESS.md` short: the board, **Last checked**, and the last 5 handovers. Move older handovers to `docs/progress-archive.md`.

### 8. First run (M0-T00)

1. Place the attached files (see the top of this file), and move the handoff bundle into `docs/HANDOFF/`.
2. Create `docs/PROGRESS.md` with these headings:
   - `Current milestone`
   - `Last checked`
   - `Board`: sections and tasks, with status and which agent built each
   - `Later`
   - `Handovers` (latest first)
3. Create `docs/DECISIONS.md` if it is missing.
4. Split `MADAR_HANDOFF.html` into plain-text section files under `docs/HANDOFF/sections/`, one file per §, with no content changes. Task cards then cite single files.
5. Apply the fixes tagged **Before M0**. These are spec and JSON corrections.
6. Write `docs/OWNER-RUNBOOK.md` (fix RA6).
7. Add a task card for M0's design note, marked `Top`, and hand over (section 4). Once the design note exists, plan M0 (fix RA3) as sections and task cards. The next agent checks that plan in its quick check before building starts.

When a room package is created (for example `Packages/RoomSalah/`), add short `AGENTS.md` and `CLAUDE.md` files there: at most one page each, with that room's rules and fix IDs.
