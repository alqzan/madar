---
name: verify
description: Madar's verification loop. Use before every commit that changes app code, tests or project files, and whenever you need to prove a change works — build, run the affected tests, launch the real app on the approved simulator with a synthetic store and drive the changed flow, then stamp the commit with how it was verified.
---

# Verify a Madar change

Owner, 17 Nov 2026: apply the Claude Code team's verification practice to Madar, automatically, in every session. The protocol in `AGENTS.md`/`CLAUDE.md` still wins where it is stricter (simulators, synthetic data, screenshots only for design changes, two repairs then record).

## 1. Pick the checks from the diff

1. `git diff --stat HEAD` (and staged). Read the triggers in `checklist.md` and keep only the items whose trigger matches the diff (usually 3–10). Run each one.
2. Find each changed area in `features.md`. It names the end-to-end UI test class, the integration/package tests and the smoke path for that area.

## 2. Cheap checks first, then heavier ones

1. `git diff --check`.
2. Package engines touched → `cd Madar/Packages/<Pkg> && swift test --filter <Suite>`.
3. App build: `cd Madar && xcodebuild -project Madar.xcodeproj -scheme Madar -destination 'generic/platform=iOS Simulator' -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build`. Run XcodeGen first if `project.yml` or file membership changed.
4. Integration slice: `build-for-testing` once, then `test-without-building -only-testing:MadarTests/<Class>` for every class `features.md` lists for the area.
5. End-to-end: `-only-testing:MadarUITests/<Class>` for the area's UI test class (the real user flow). Prefer it over unit tests whenever a flow changed.
6. Smoke the real app: `bash Madar/scripts/verify-smoke.sh [fixture]`. It builds Debug, installs on `Madar 15 Pro Max`, launches with an isolated `MADAR_UI_STORE_ID` store (never the owner's data), checks that the app is still running after a few seconds and that no new crash report appeared, and saves a screenshot under `Madar/Artifacts/verify/` (local evidence, not a design capture). Then drive the changed flow like a QA engineer with the iOS Simulator tool (`mcp__Claude_Code_iOS_Simulator__control`: screenshot, tap, swipe, text) and compare with the expected result in `features.md`. iPad layout changes: `SIMULATOR=85FA4D17-2DBF-46D6-837E-9221597B89DD`.

A successful build or zero executed tests is not a pass. Report executed counts and the result bundle path.

## 3. When a check fails

- Diagnose, fix, re-run. At most two evidence-based repairs for the same failure (protocol), then stop, record the blocker on the board and tell the owner in the handover.
- Flaky tests: never add sleeps, never retry until green, never `XCTSkip` to get past it. Find the cause; if the test checks a feature the owner removed or the cause cannot be found, delete the test and write why in the commit message and handover.
- A failure that keeps recurring across sessions becomes a new row in `checklist.md` (trigger, check, incident) in the same commit as its fix.

## 4. Stamp the commit

Every commit message ends with one `Verified:` line before the trailers, naming what actually ran, for example:

`Verified: build; swift test HabitJamaahConversionTests 2/2; MadarTests 41 (0 fail); MadarUITests/HabitsUITests 12/12; smoke habits fixture`

Documentation-only commits: `Verified: docs only — links and diff checked`. If nothing could run, say so and why: `Verified: none — <reason>`. The commit-gate hook (`.claude/hooks/commit-gate.py`) blocks a `git commit` without this line.

## 5. Keep the loop healthy

- Never weaken a check, the checklist, this skill or the hook inside the change it judges; change them in their own commit with the reason.
- Prune: when a room or feature is removed, delete its tests and its rows here in the same request.
