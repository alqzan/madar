# Madar (مدار) — instructions for coding agents (Codex and Claude Code)

Codex loads this file as `AGENTS.md` and Claude Code loads it as `CLAUDE.md`. The two files are identical. Change both or neither.

You are building **Madar**, a native iPhone app (SwiftUI, Arabic RTL). The approved spec is the handoff bundle in `docs/HANDOFF/`:
- `MADAR_HANDOFF.html`
- `screens/`
- `design-tokens.json`, `settings-schema.json`, `screens-index.json`, `data-dictionary.json`, `provenance.json`

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
| Screen work | The card's canonical files in `docs/HANDOFF/screens/`, the room's §7.x part for that screen, §5 for shared shapes, and the card's fix IDs |

## Availability

- Every action, option, import source and Intent parameter is classed as v1, v2 or deferred. The §12 table, as amended by the fixes file, decides which.
- **No v1 build shows an entry point to a feature that is not v1.** That means no disabled buttons and no "coming soon".
- A room that is not built yet has no entry point anywhere: not in widgets, controls or Capture.

## Rules (from the approved brief)

**Design**
- **Same as the design or better, never worse.** Match the screenshots in layout, spacing, type and tone. Improve only when the result is clearly better on iOS 27 (a native component, accessibility, performance), and log the change in `docs/DECISIONS.md`.
- **Go deeper and improve — owner, 15 October 2026.** The approved design is the floor, not the ceiling. In every card, and when revisiting screens already built, look for what would make Madar clearly better for the user: clearer copy, less repetition, better empty states, smoother flows, richer use of the data a room already owns, native iOS 27 polish. Small improvements that keep the rules, the data model and the v1 scope: build them, log one row in `docs/DECISIONS.md` (what, why, before/after screenshot names) and say so in the handover. Bigger ideas (a new feature, a rule or data-model change, anything outside v1): add a row to the board section «Ideas — for the owner» with the idea and why, and do not build it until the owner says yes. The owner wants Madar to feel very smart and "wow": crafted touches like the reflection under the prayer arches matter a lot to them (light, reflection, depth, gentle motion that respects Reduce Motion, each room's own ornament), and so does intelligence — the app anticipates the next useful thing from the data it already has (time of day, next prayer, what is due, what is near) instead of showing static numbers. **Creativity is the default (owner, 15 October 2026):** be bold and inventive in design and experience; build creative improvements without waiting for approval, as long as they keep the rules, the data model and the licences and can be reverted. The owner reviews afterwards and says what they do not like; that feedback is logged and followed. Only changes to rules, the data model, licences or v1 scope wait in «Ideas — for the owner». Show the real thing, never an abstract label: an amount the user can picture («نصف صفحة»، «٥ أسطر») instead of a multiplier («×١½»).
- **Deployment target is iOS 27.0.** Build and validate on iOS 27; use iOS 27 APIs directly without maintaining iOS 26 compatibility paths.
- **Arabic, right to left, everywhere.** Arabic-Indic digits by default.
- **Dates:** the primary date follows `core.firstCalendar` (Hijri first by default). The exception is the diary calendar, which is Gregorian first (`notes.calendarFirst`). **Both dates always (owner, 15 October 2026):** every date the user sees shows both calendars, the primary one as the main text and the other smaller beneath or beside it (for example the Quran plan's expected completion date). A Hijri-only or Gregorian-only date is a defect.

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
- Inside each room, work screen by screen in the board's order. A screen matches its canonical design before the next screen starts (visual acceptance, below).
- Each milestone ends with a build on the owner's iPhone that passes its acceptance checks.

---

## Working protocol — owner revision, 13 October 2026

This replaces the 12 October working protocol. Product rules above are unchanged. Reason: about 15 sessions produced about 190 commits, half of them records, claims and handovers, and prayer screens that work but do not look like the approved design. Older handovers, reports and automation memory are history, not instructions.

### 1. What a session delivers

- Something the owner can **see** on the phone: a screen that matches its canonical design, or the engine/flow a visible screen needs next. Several small cards per session are welcome.
- Take the first `ready` card in `docs/PROGRESS.md`. Do not reorder the queue or invent cards. If the card is blocked, write the blocker in its row and take the next `ready` card.
- Before coding, write one line in your reply: the screen, its canonical files, and what will look different afterwards.

### 2. Visual acceptance — the main gate for screens

- Each screen card names its canonical files (`screens/<room>/NN-<board>.jpg` and its `-s1` scrolled file). The screen is built to match them in layout, order of elements, spacing, type sizes and weights, shapes and ornament, and colour. Working code with a different look is not done.
- Take default-size screenshots (L, light unless the canonical is dark) of the same states as the canonical, then run `python3 Madar/scripts/compare-screens.py <board> <shot.png> [<scrolled.png>]` and open `Madar/Artifacts/compare/<board>.html`. Fix differences until none remain that you can name, and list any that remain in the handover.
- Each card has a **Do not copy** list: prototype-only elements, sample numbers, and anything a fix overrides (fixes and schema defaults win over screenshots, RL10). Respect it. Everything else on the screen is copied.
- An agent may set a screen to `matched — awaiting owner`. Only the owner sets `approved`. Self-graded "screenshots inspected" is not acceptance.
- Test and screenshot at the default text size only. Owner decision, 13 October 2026: no AX3/AX5 or other enlarged-text runs or screenshots. Keep the Dynamic Type code paths you touch working, but do not spend sessions testing them.
- Room flows use the room's own look (paper background, Madar cards, room typography). A stock grey grouped `Form`/`List` sheet is a mismatch unless the canonical shows a system sheet.
- Reuse existing code that is closer to the design before writing new drawing code.

### 3. Checks — the smallest that proves the change

- Engines: pure-Swift tests with expected values taken from the spec, never from the engine's output.
- Screens: the app builds, the changed flow's UI test passes (add or extend one when the flow is new), plus the screenshots above. Do not rerun unrelated suites.
- Before each commit: the changed code builds, the tests for the changed flow pass, and `git diff --check` is clean. The two script checks (`check-review-contracts.py`, `check-shipping-sources.py`) run only at a milestone gate, not on every commit. Before native builds in a fresh checkout: `python3 Madar/scripts/prepare-workspace.py`.
- Never claim a check you did not run. A simulator pass is not an owner-iPhone pass, and neither is distribution.

### 4. What not to do

- No new reports, plans, traces, source maps, inventories or review documents. The card row and one handover are the record. Exception: the owner asks for a document.
- **Frozen** until the owner unfreezes them: M0-T06, M0-T09 (privacy matrix only), M0-T12, app-switcher privacy, sync, and accessibility-inspector audits. The app-wide Face ID/iPhone-passcode gate is optional and off by default (`core.faceIDLock=none`); the owner enables it in Settings. When enabled, keep every room open after that single unlock, with no per-room or notebook-idle gate. The iPhone passcode is the fallback only when Face ID is unavailable (permission off, no enrolled face, lockout) (owner, 1–2 November 2026). The owner unfroze encrypted backup on 21 October 2026; build it. Keep all other frozen work unchanged. A confirmed privacy or data-loss defect in a route you are changing is still fixed before that route is accepted.
- No reviews. Owner decision, 13 October 2026: no reviewer agents, review passes, review documents or re-reviews for any change. Exceptions, each one review pass that fixes Critical/High findings and moves on:
  - A change that migrates or could delete the owner's stored records.
  - **Money cards (owner, 16 October 2026):** after each money engine or data card, and before money screens build on it, review the work, fix Critical/High findings with tests, and note the review in the card row. Max effort is not required; the review is what matters.
  - **UX review after each section (owner, 16 October 2026):** when a room or section is finished (for example each M5 block), one reviewer on the strongest model checks it against UX principles: smart, clear, useful, free of complexity, and "wow". Apply its high-value findings and log them in `docs/DECISIONS.md`.
- No branch or worktree per task. Commit a finished card on `main` once it builds and its checks pass. Use a single `codex/<section>` branch only for work that spans sessions, and merge it when the card is done. Never force-push, rewrite history, or delete another agent's branch or work.
- Don't delete unused code you didn't write (for example the old `PrayerRoom.swift`). Port what is useful; the owner decides what to remove.

### 5. Commits and handover

- One commit per finished card, with the board row update in the same commit: `[M1-V01] <visible result> (codex|claude, model: <actual or not exposed>, effort: <actual or not exposed>)`. No separate "Record/Claim/Preserve/handover" commits.
- One handover per session in `docs/PROGRESS.md`, at most 7 lines: **Works now**, **Verified** (command and result), **Differences left** (visual), **Not verified**, **Next**, **Model/effort**, **Usage**. Keep the last three handovers; move older ones to `docs/archive/`.

### 6. Model, usage and failure

- GPT-6 Luna max may write production code. Escalate a narrow problem to Sol only after two evidence-based repairs fail, or for an unresolved rule conflict.
- **Money (M5) gets our full strength — owner, 15 October 2026.** The owner sees money as the hardest room. Before its first card, read §7.5 (mal), §8 money definitions, the money data dictionary and every mal fix item end to end, and write the money engine with golden fixtures for every number before any screen. Use the strongest model and effort available for the money engine and its data model (Codex: Sol at its highest effort; Claude: the session's model at its highest effort). Every money number has one definition (§8), `Int` minor units, and a test from the spec.
- **Continuous improvement is the principle — owner, 15 October 2026.** Nothing built is final. Every session, after its cards, spends a share of its time going back to an earlier room and making it clearly better (the «Go deeper and improve» rule above), with a DECISIONS row and before/after screenshots.
- Usage: stop starting new work near 95% of the five-hour allowance, and keep a 3–5% reserve for the commit and handover. Never invent a usage number; say "not exposed". **Owner, 21 October 2026:** when about 5% of the allowance is left, stop, commit, and write the handover so the other agent (Codex or Claude) can take the rest: say exactly what remains and where.
- **Cheaper helper agents, always (owner, 21 October 2026).** While a long build, test or download runs, use cheaper subagents (Claude: Sonnet and Haiku; Codex: its smaller models) for parallel read-only work: searches, audits against these rules, finding unreachable states, reading logs, user-journey walks per room. Owner, 26 October 2026: there is no fixed cap on how many; launch as many as the work needs. They never touch the simulator, never edit, build or commit. The main agent checks each finding in the code, applies the ones that are right, and keeps writing production code itself. **Owner, 29 October 2026:** hunting for errors (bug hunts, dead ends, crashes, wrong conditions, copy and grammar audits) is always done by the cheapest helpers (Claude: Haiku, one per room in parallel; Codex: its smallest model), never by the main agent reading the code itself. The main agent only verifies and fixes what they report. **Owner, 29 October 2026 («خل هذا شي دايم»):** the main agent never sits waiting on a run. The moment a build, test or download starts, it launches helpers on areas not yet covered and keeps fixing files that run does not depend on.
- When something fails: diagnose once, try at most two evidence-based repairs, then record the blocker in the card and move on. Never mark a failed or unrun check as passed.

### 7. Map of the repository

- `AGENTS.md` = `CLAUDE.md` (root) is the protocol; `Madar/AGENTS.md` = `Madar/CLAUDE.md` points here. Keep each pair byte-identical.
- `docs/PROGRESS.md` is the board and the only status file. `docs/DECISIONS.md` holds owner decisions and conflicts. `docs/reports/M<n>.md` holds only the milestone gate table, filled at the milestone gate.
- `docs/HANDOFF/` is the approved spec (screens, JSON, `sections/` extracts, review fixes). `Madar/Specification/` is the working copy the generators and scripts read; keep them consistent.
- `docs/design/` holds architecture notes, `docs/journeys/` the journey register, and `docs/archive/` history only.
- `Madar/` holds the app: `App/` screens, `Packages/` engines and data, `Tests/`, `scripts/`. `Madar/Artifacts/` (screenshots, xcresults), `output/` and `tmp/` are local and not in Git.
