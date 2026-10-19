## Handover — M6-V22 adaptive auto-scroll — 2026-10-19 — Codex
Works now: the reader follows text at a paragraph-aware pace, highlights its current paragraph and offers pause/resume/stop in a glass player; preferences are independent for Arabic and English and default off.
Verified: `swift test --package-path Madar/Packages/MadarData` 72/72; iPhone 17 Pro / iOS 26.5 English-settings + auto-scroll UI 2/2; PDF import/read UI 3/3; collapsed navigation UI 1/1; `compare-screens.py R10-Tamrir`; `git diff --check` clean.
Differences left: synthetic text and the persistent reader header differ from `24-R10-Tamrir.jpg`.
Not verified: owner iPhone, large real EPUBs/PDFs, and OS-level placement.
Next: record the direct ALS app-bridge blocker (MCP has no app-facing API/export), then take the first owner-approved idea; start M7 after the approved ideas.
Model/effort: not exposed / not exposed. Usage: 52% five-hour used / 56% weekly at last check.
