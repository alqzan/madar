# Madar (مدار) — instructions for coding agents (Codex and Claude Code)

Codex loads this file as `AGENTS.md` and Claude Code loads it as `CLAUDE.md`. The two files are identical. Change both or neither.

You are building **Madar**, a native iPhone app (SwiftUI, Arabic RTL). The approved spec is the handoff bundle in `docs/HANDOFF/`:
- `MADAR_HANDOFF.html`
- `screens/`
- `design-tokens.json`, `settings-schema.json`, `screens-index.json`, `data-dictionary.json`, `provenance.json`

## Authority and current mandate — 9 November 2026

1. The owner's latest explicit instruction wins over older owner decisions, this protocol, the board and the handoff. Log a changed decision once in `docs/DECISIONS.md`; do not keep both versions as current instructions.
2. `AGENTS.md` and `CLAUDE.md` are one protocol. Keep them byte-identical. `docs/PROGRESS.md` is the current work and delivery status; `docs/DECISIONS.md` records why a rule changed. Archived boards, old handovers and memory are historical evidence, not competing queues or instructions.
3. For product questions not changed by the owner: review fixes (`docs/HANDOFF/Madar - Handoff Review Fixes - V1.md`) override the handoff. Behaviour and scope: text, then JSON, then screenshots. Exact keys/defaults/ranges/hex: JSON; resolve text/JSON conflicts using the text and record them. Canonical screenshots are the visual baseline; never copy sample data or prototype controls.
4. Current owner request (8–9 Nov): keep the instructions and board consistent, then go through the whole app for ease, flexibility, simplicity and responsiveness without making it heavier, and give iPad its own layout (sidebar, wide-screen pages) rather than a stretched iPhone. Revisit previously approved interfaces when there is a concrete improvement. This authorizes reversible UI/flow corrections and helper-assisted bug/UX inspection; older review bans, strict screenshot-copy requirements and pre-first-TestFlight freezes do not block this work.
5. Existing product/data/licensing safeguards still apply. Ask only for an unresolved product-rule/default/data-model/licence change, public publication, or access to/migration/deletion of real owner data. Do not ask again for work already authorized.

**Product safeguards:** RA1 local-only v1 (CloudKit remains deferred until explicit authorization); RA2 only the app opens the store, extensions use inbox/snapshots; RA3 lean M0; RP1 no automatic missed/qada record; RU1 no middle dot next to a digit. Later explicit owner decisions, including prayer records and calendar order, override original handoff wording.

## Delivery — standing owner authorization

- Complete, validate and commit directly requested changes on `main`, then archive/export/upload to internal TestFlight without another permission step. Public App Store release and App Review submission are separate.
- **One request, one build, at the end (owner, 12 Nov 2026).** Upload only after every part of the owner's request is finished and verified; never upload more than one build for the same request. Upload and stop: do not wait for Apple processing or TestFlight availability before reporting (check it on the next request if relevant).
- **Push to GitHub last (owner, 12 Nov 2026).** After the request's upload (or its final commit when there is no upload), push `main` to `origin` without asking. A cheap helper may run the push. Never force-push; if the push is rejected, fetch and rebase local commits onto `origin/main` only when there are no conflicts, otherwise record the blocker.
- Use an existing card when relevant. For a direct request without a matching card, use one descriptive `[OWNER]` commit and record the result in the current work section and handover; no invented card IDs.
- Keep `MARKETING_VERSION` unless requested; increment `CURRENT_PROJECT_VERSION` once per upload, and commit the bump with the request's handover.
- Treat signing, provisioning and Apple processing as technical requirements. Verify them live; do not carry an old blocker forward without checking. Record archive, upload, processing and owner-device acceptance separately; processing is not awaited (see above).
- iOS deployment target and the sole test runtime are 27.0. Use an installed Xcode that supports them; no exact Xcode patch version is pinned by this protocol. A newer installed Xcode alone is not a blocker.

## What to read: per task, never everything

Do not load the whole handoff into context. Each task card in `docs/PROGRESS.md` lists the spec sections and fix IDs it needs. Read those and nothing else, and use `rg` to find a section instead of reading the spec end to end.

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
- **Same as the design or better, never worse.** Use the screenshots as the baseline for room identity, spacing, type and tone. The current owner mandate permits clearer, simpler flows beyond old approvals; record intentional changes in `docs/DECISIONS.md`.
- **Go deeper and improve — owner, 15 October 2026.** The approved design is the floor, not the ceiling. In every card, and when revisiting screens already built, look for what would make Madar clearly better for the user: clearer copy, less repetition, better empty states, smoother flows, richer use of the data a room already owns, native iOS 27 polish. Small improvements that keep the rules, the data model and the v1 scope: build them, log one row in `docs/DECISIONS.md` (what, why, before/after screenshot names) and say so in the handover. Bigger ideas (a new feature, a rule or data-model change, anything outside v1): add a row to the board section «Ideas — for the owner» with the idea and why, and do not build it until the owner says yes. The owner wants Madar to feel very smart and "wow": crafted touches like the reflection under the prayer arches matter a lot to them (light, reflection, depth, gentle motion that respects Reduce Motion, each room's own ornament), and so does intelligence — the app anticipates the next useful thing from the data it already has (time of day, next prayer, what is due, what is near) instead of showing static numbers. **Creativity is the default (owner, 15 October 2026):** be bold and inventive in design and experience; build creative improvements without waiting for approval, as long as they keep the rules, the data model and the licences and can be reverted. The owner reviews afterwards and says what they do not like; that feedback is logged and followed. Only changes to rules, the data model, licences or v1 scope wait in «Ideas — for the owner». Show the real thing, never an abstract label: an amount the user can picture («نصف صفحة»، «٥ أسطر») instead of a multiplier («×١½»).
- **Deployment target is iOS 27.0.** Build and validate on iOS 27; use iOS 27 APIs directly without maintaining iOS 26 compatibility paths.
- **Arabic, right to left, everywhere.** Arabic-Indic digits by default.
- **Dates:** the primary date follows `core.firstCalendar` (Gregorian first by default, owner 22 Oct; Quran follows it too, owner 8 Nov). The exception is the diary calendar, which is Gregorian first (`notes.calendarFirst`). **Both dates always (owner, 15 October 2026):** every date the user sees shows both calendars, the primary one as the main text and the other smaller beneath or beside it (for example the Quran plan's expected completion date). A Hijri-only or Gregorian-only date is a defect.

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
- Use exactly two simulators, both on iOS 27.0: iPhone 15 Pro Max named `Madar 15 Pro Max` (UDID `390840AD-4FF0-476F-8E1D-E0C521A58E45`) and, for iPad work only, `Madar iPad Pro 13` (UDID `85FA4D17-2DBF-46D6-837E-9221597B89DD`, owner 9 Nov 2026). Never create or use another simulator device or iOS simulator runtime.
- A session without macOS (Codex cloud, a Claude Code cloud session) writes code and pure-Swift tests only. It never claims a build or run it could not perform.

## Work selection and session protocol

- Read the current work section and newest handover in `docs/PROGRESS.md`, relevant decisions, Git state, running jobs and live usage before starting. Preserve other work. Read only the spec sections relevant to the change.
- Direct owner requests take priority. Otherwise take the first actionable `ready` card in the active queue. Historical tables do not create a second queue. If blocked, record the precise blocker and continue independent useful work.
- Before editing a screen, state the screen, its canonical reference (or that the state has none), and the intended visible improvement. Prefer existing components and the room's own paper, typography and ornament; avoid unexplained controls and repetitive copy.
- The approved design is a baseline. Improve a confusing flow even if previously approved, retaining product rules and room identity. Log the reason and before/after evidence. Do not claim a redesign is pixel-matched to an older canonical.
- Screenshots (owner 9 Nov): capture only when a change alters the design (layout, a drawing, a new screen state), at default text size; copy, logic and tap-area changes are verified by tests without captures. Use `python3 Madar/scripts/compare-screens.py <board> <shot.png> [<scrolled.png>]` when a canonical applies; document intentional differences. Only the owner marks a screen `approved`; agents use `matched — awaiting owner` or `built — awaiting owner` for intentional redesigns.
- Keep Dynamic Type paths working, but do not run enlarged-text or accessibility-inspector audits unless newly requested.

## Helpers and review

- Use cheaper read-only helpers for bug hunts, copy/UX inspection, searches and log reading. The main agent verifies findings and owns all source edits, builds, tests, simulator operations and commits. Give helpers bounded areas and avoid duplicate coverage.
- Use available helper slots for independent useful work during long runs; do not launch work merely to fill time, and do not change files an active build/test depends on. The actual runtime concurrency limit applies; there is no requirement to create unlimited agents.
- The current whole-app inspection is authorized. Avoid repeated general reviews and separate review reports. Record actionable findings in the current board section and apply the high-value ones.
- One focused review is required for changes that migrate/could delete stored records and for money engine/data changes. Fix Critical/High findings with tests before building screens on them. Room completion gets one focused UX pass, with useful findings applied.
- Use the strongest available reasoning for money engine/data rules; use inexpensive helpers for read-only discovery. Record actual model/effort when exposed; never invent a model name or usage number.

## Verification and failure handling

- Run `python3 Madar/scripts/prepare-workspace.py` before native builds in a fresh checkout. Regenerate with XcodeGen when project inputs or test/source file membership change.
- Engines: pure-Swift behavioural tests with expected values from the spec, not the implementation. Screens/flows: build and run the smallest meaningful affected UI/integration slice; add coverage for new behaviour. Do not rerun unrelated suites.
- Before committing changed code: build, affected checks and `git diff --check`. Documentation-only commits require link/path/consistency checks and diff checking, not an unrelated app build. Run `check-review-contracts.py` and `check-shipping-sources.py` at milestone gates, not every commit.
- Report actual executed test counts and result bundles. A successful test build or zero executed tests is not a passing suite. Simulator evidence is separate from owner-iPhone acceptance, visual approval, performance measurement and distribution.
- Diagnose a failure once; try at most two evidence-based repairs for the same blocker, then record it and move to independent work. Do not silently skip or label failed/unrun checks passed.
- Use synthetic isolated stores. Do not open/migrate/delete real owner/family records or run on their device without explicit authorization. Do not erase the shared simulator or its stores to make a test pass.

## Usage, commits and handover

- Check live five-hour and weekly usage at the start, after substantial work and before a new large batch/archive. Remaining = 100 minus used percent. Helpers share the allowance. If unavailable, say `not exposed`; do not estimate.
- Near 5% remaining in the five-hour window, or 2% in the weekly window, stop starting new work and reserve capacity for focused verification, commit, handover and the authorized TestFlight upload. Start archiving early enough to preserve that reserve. Never redeem reset credits without explicit confirmation.
- Commit one coherent finished change with its board update: `[<existing-card>] <result> (codex|claude, model: <actual or not exposed>, effort: <actual or not exposed>)`; use `[OWNER]` for this request where no card applies. No record-only/handover-only commits unless documentation itself is the requested deliverable.
- Work on `main`; no branch/worktree per task. A single `codex/<section>` branch is allowed for multi-session work. Never force-push, rewrite history or delete another agent's work. Retained unused code need not be deleted as part of UX cleanup.
- Keep one concise handover per session in `docs/PROGRESS.md` (no fixed length cap, owner 22 Oct): **Works now**, **Verified**, **Differences left**, **Not verified**, **Next**, **Model/effort**, **Usage**. Keep the newest three; archive older handovers. The newest current-work section wins over stale next steps in old handovers.

## Deferred work and repository map

- CloudKit/sync, M0-T06 paperwork, M0-T09 privacy matrix, M0-T12 contrast inspector and app-switcher privacy remain deferred unless explicitly reopened. Encrypted backup is already unfrozen. Fix a confirmed privacy/data-loss defect in any touched route.
- There is no app lock (owner, 10 Nov 2026): the mechanism and the `core.faceIDLock` key are deleted; rooms open directly, protected reads go through `AppSession.protectedDataAuthorized`, and OS file protection still applies. Do not rebuild a lock without an explicit owner request.
- `Madar/AGENTS.md` and `Madar/CLAUDE.md` point to this protocol and stay byte-identical.
- `docs/HANDOFF/` holds the approved original spec. Keep changed spec contracts consistent with `Madar/Specification/` when relevant. `docs/reports/M<n>.md` is milestone-gate evidence only; `docs/archive/` is history.
- `Madar/App/`, `Packages/`, `Tests/`, `scripts/` hold implementation and verification. `Madar/Artifacts/`, `output/`, `tmp/` are ignored local evidence. Do not add new status/report documents when the current board and handover suffice.
