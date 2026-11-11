# Plan 005: The board (`docs/PROGRESS.md`) no longer contradicts the protocol or the owner's answers

> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- docs/PROGRESS.md`
> The board changes often. If it changed since this plan was written, do not
> rely on the line numbers below: locate each passage with the `grep` command
> given in its step. If a passage's text is no longer present, skip that step
> and say so in your report.

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: LOW (documentation only)
- **Depends on**: none
- **Category**: docs
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

Every agent session starts by reading the top of `docs/PROGRESS.md`. Today that
text disagrees with the protocol (`CLAUDE.md`, identical to `AGENTS.md`) in
several places, so a new session can pick up a wrong rule: an old stop
threshold, a build number six uploads behind, an app lock that no longer
exists, and a one-simulator rule that was later widened. Four rows of the ideas
table also still say «open» or «Awaiting owner» although the owner answered
them weeks ago, so answered questions look unanswered and one approved,
unbuilt item is invisible. The owner asked on 9 Nov for the rules and the board
to be consistent. This plan edits text only; no code and no product rule
changes.

## Current state

All paths are relative to the repository root. The repository root folder name
contains Arabic characters and a space: always quote it in shell commands.

Only one file is edited: `docs/PROGRESS.md` (232 lines at the planned commit).
The protocol it must agree with is `CLAUDE.md` (do not edit). The relevant
protocol lines, quoted:

- Stop thresholds: «Near 5% remaining in the five-hour window, or 2% in the
  weekly window, stop starting new work…»
- Simulators: «Use exactly two simulators, both on iOS 27.0: iPhone 15 Pro Max
  named `Madar 15 Pro Max` … and, for iPad work only, `Madar iPad Pro 13` …
  (owner 9 Nov 2026).»
- App lock: «There is no app lock (owner, 10 Nov 2026): the mechanism and the
  `core.faceIDLock` key are deleted…»
- Status words: «Only the owner marks a screen `approved`» — this plan never
  writes `approved`.

The stale passages (line numbers at the planned commit):

1. Line 1: `# Current work — 10 November 2026`
2. Line 3 ends with: `Current continuation (owner, 9 Nov): stop new work at 20% remaining in either exposed usage window; the earlier 5%/2% thresholds do not apply to this session.`
   (That sentence was for one session on 9 Nov; row 18 of the queue records it.)
3. Line 7 begins: `- M0–M6 software is on `main`; M7 owner-device/system acceptance remains open. Latest uploaded build: **0.1.0 (27)**, including Quran unreadable-draft recovery and the owner's exit-choice behavior.`
   Later handovers in the same file record newer uploads (build 33, then build
   34 at the planned commit); each upload leaves
   `Madar/Artifacts/OWNER-TestFlight-<N>/upload.log` containing «Upload succeeded».
   Step 2 finds the real newest number; do not assume one.
4. Line 54 contains the sentence: `الخمول المؤقت لا يغلق الغرفة عندما يكون قفل التطبيق معطلًا.`
5. The section `## Waiting on the owner` (line 79) contains dated owner
   statements of 2 Nov that were later superseded: «the only simulator is
   `Madar 15 Pro Max`», «Use only one simulator», and «the app-wide lock is
   optional and off by default».
6. Line 196 ends with: `App lock remains optional and off by default; use the current root protocol.`
7. In the table under `## Ideas — for the owner`, four rows whose last cell is
   stale. Each row starts with the title shown here:
   - `| Grade-less mistakes in a free Quran session |` … last cell `| Awaiting owner |`.
     Answer already in the file (line 125): «save the session with its mistakes
     even without a page grade (already built by Codex in 1c371b6d, AU-96; keep it)».
   - `| Honorifics in scanned books |` … last cell `| open |`.
     Answer in the file (line 130): «Owner 27 Oct: replace with the correct
     honorific text — ready.» What the code does today:
     `Madar/Packages/MadarCommands/Sources/MadarCommands/PDFBookTextReader.swift:159-164`
     expands only the two Unicode ligatures ﷺ and ﷻ; replacing OCR noise words
     after a name is not built.
   - `| End a trip-linked habit pause when a trip is dismissed |` … last cell `| open |`.
     Answer in the file (line 132): «Owner 27 Oct: the habit resumes on the
     dismissal day — ready.» What the code does today:
     `Madar/Packages/MadarCommands/Sources/MadarCommands/HabitRepository.swift:112-116`
     ends a trip-linked pause only from `Trip.end`; a dismissed trip is not handled.
   - `| Money amounts in diary export |` … last cell `| open |`.
     Answer in the file (line 133): «Owner 27 Oct: keep the amounts (the export
     is the owner's own file) — no change needed.»

## Commands you will need

Run from the repository root.

| Purpose | Command | Expected on success |
|---|---|---|
| Newest uploaded build | `for d in $(ls -d Madar/Artifacts/OWNER-TestFlight-* \| sort -V); do grep -l "Upload succeeded" "$d/upload.log" 2>/dev/null; done \| tail -1` | a path such as `Madar/Artifacts/OWNER-TestFlight-33/upload.log`; the number in it is N |
| Protocol copies identical | `cmp CLAUDE.md AGENTS.md` | no output, exit 0 |
| Whitespace | `git diff --check` | no output |

No build, test or simulator is needed for this plan.

## Scope

**In scope** (the only file you may modify):
- `docs/PROGRESS.md`

**Out of scope** (do NOT touch):
- `CLAUDE.md`, `AGENTS.md`, `Madar/CLAUDE.md`, `Madar/AGENTS.md`,
  `docs/DECISIONS.md`, everything under `docs/archive/` and `docs/HANDOFF/`.
- The three handovers under `# Handovers`, the queue rows (the numbered table
  under `## Active queue — this request`), and any dated history sentence other
  than the ones named in the steps. History stays as written; this plan only
  fixes statements that read as current rules.
- Never write the status word `approved`, and never mark anything `done` that
  the steps below do not name.
- All source code.

## Git workflow

- Work on `main` (the repository protocol forbids a branch per task) unless your
  operator placed you in a worktree.
- One commit; documentation is the deliverable here, so a documentation-only
  commit is allowed:
  `[OWNER] Board agrees with the protocol: latest build, stop thresholds, no app lock, two simulators, four answered idea rows (claude, model: <your actual model id>, effort: <actual or "not exposed">)`.
- Do NOT push.

## Steps

### Step 1: Header date and the stale stop threshold

- Line 1: change the date to the date of the newest handover in the file (at the
  planned commit: `11 November 2026`).
- Line 3: delete exactly the sentence
  `Current continuation (owner, 9 Nov): stop new work at 20% remaining in either exposed usage window; the earlier 5%/2% thresholds do not apply to this session.`
  including the single space before it. Keep the rest of the line.

**Verify**: `grep -c "stop new work at 20% remaining" docs/PROGRESS.md` → 0.

### Step 2: Latest uploaded build

Find N with the "Newest uploaded build" command. In line 7, replace

`Latest uploaded build: **0.1.0 (27)**, including Quran unreadable-draft recovery`

with

`Latest uploaded build: **0.1.0 (N)** (evidence: `Madar/Artifacts/OWNER-TestFlight-N/upload.log` and the newest handover). Build 27 (10 Nov) included Quran unreadable-draft recovery`

using the real number for N. Leave the rest of the line unchanged.

**Verify**: `grep -c "Latest uploaded build: \*\*0.1.0 (27)\*\*" docs/PROGRESS.md` → 0, and `grep -c "Latest uploaded build: \*\*0.1.0 (" docs/PROGRESS.md` → 1.

### Step 3: App lock statements

- Line 54: replace the sentence
  `الخمول المؤقت لا يغلق الغرفة عندما يكون قفل التطبيق معطلًا.`
  with
  `الخمول المؤقت لا يغلق الغرفة (لا قفل للتطبيق منذ ١٠ نوفمبر).`
- Line 196: replace
  `App lock remains optional and off by default; use the current root protocol.`
  with
  `There is no app lock (owner, 10 Nov 2026); see the root protocol.`

**Verify**: `grep -c "قفل التطبيق معطلًا" docs/PROGRESS.md` → 0, and `grep -c "App lock remains optional" docs/PROGRESS.md` → 0.

### Step 4: One superseding note in «Waiting on the owner»

Do not rewrite the dated owner statements. Insert one new paragraph directly
after the heading line `## Waiting on the owner` (with a blank line before and
after it):

`**Superseded since these notes were written:** the 2 Nov single-simulator statements below are widened by the owner's 9 Nov addition of `Madar iPad Pro 13` (iPad work only), and the 2 Nov «app-wide lock is optional» statement is replaced by the owner's 10 Nov deletion of the app lock. The root protocol (`CLAUDE.md` = `AGENTS.md`) is current; the notes below are kept as dated history.`

**Verify**: `grep -c "Superseded since these notes were written" docs/PROGRESS.md` → 1.

### Step 5: Four idea rows

In the table under `## Ideas — for the owner`, replace only the **last cell** of
each of these four rows (find the row by its title cell; each title occurs once
as a row start):

| Row title | New last cell |
|---|---|
| Grade-less mistakes in a free Quran session | `Answered 2 Nov: save the session with its mistakes; built in 1c371b6d (AU-96).` |
| Honorifics in scanned books | `Answered 27 Oct: replace with the correct honorific text. Ready, not built: today only the ligatures ﷺ and ﷻ are expanded (`PDFBookTextReader.withoutStraySymbols`).` |
| End a trip-linked habit pause when a trip is dismissed | `Answered 27 Oct: the habit resumes on the dismissal day. Ready, not built: `HabitRepository` still derives the pause end from `Trip.end` only.` |
| Money amounts in diary export | `Answered 27 Oct: keep the amounts; no change needed (closed).` |

**Verify**: `grep -cE "^\| (Honorifics in scanned books|End a trip-linked habit pause when a trip is dismissed|Money amounts in diary export) .*\| open \|$" docs/PROGRESS.md` → 0, and `grep -cE "^\| Grade-less mistakes in a free Quran session .*\| Awaiting owner \|$" docs/PROGRESS.md` → 0.

### Step 6: Final checks

**Verify**: `cmp CLAUDE.md AGENTS.md` → no output; `git diff --check` → no output; `git diff --stat -- docs/PROGRESS.md` shows one file changed with roughly 10 insertions and 9 deletions.

## Test plan

Documentation only: the `grep` checks in each step are the tests. No app build
is required by the repository protocol for a documentation-only commit.

## Done criteria

- [ ] All six step verifications hold
- [ ] `git status --short` shows `docs/PROGRESS.md` as the only file you modified (files already modified before you started do not count; list them in your report)
- [ ] The word `approved` does not appear in `git diff -- docs/PROGRESS.md` on any added line: `git diff -- docs/PROGRESS.md | grep -c "^+.*approved"` prints 0
- [ ] `plans/README.md` status row updated

## STOP conditions

Stop and report back (do not improvise) if:

- The "Newest uploaded build" command prints nothing (no upload log on this
  machine): leave line 7 untouched, finish the other steps, and report it.
- A passage named in a step is not found by its `grep` and you cannot tell
  whether someone already fixed it.
- Another session has uncommitted changes in `docs/PROGRESS.md`
  (`git status --short docs/PROGRESS.md` shows it modified before you start):
  do not edit the file under them.
- You find further contradictions between the board and `CLAUDE.md`: list them
  in your report; do not fix them under this plan.

## Maintenance notes

- Two of the rewritten idea rows now say «Ready, not built». They are small
  approved items (dismissed-trip pause end; honorific noise words) that can be
  planned separately; see the backlog in `plans/README.md`.
- The top of the board goes stale after every delivery. A reviewer may prefer
  that line 7 stop naming a build number at all and point to the newest
  handover instead; that is the owner's or the main agent's call.
