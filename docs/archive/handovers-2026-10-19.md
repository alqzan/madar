# Archived handover

## Handover — M3-V09 Day One tags — 2026-10-19 — Codex
Works now: Day One imports retain every tag, preserve the first-tag project link, and expose normalized `#وسم` search. Old unchanged exports restore tags alone while preserving whether the text was edited locally. Undo restores only tags and preserves later edits.
Verified: `swift test` Data schema 19/19, Core Day One 8/8 + tag search 5/5, Commands `DayOneImportPersistenceTests` 10/10; `xcodebuild test` iPhone 17 Pro import UI 1/1 (`M3-V09-tags-final-ui-20261019.xcresult`, no startup alert), prior import + search UI 2/2 and search integration 1/1; compare generated; `git diff --check` clean.
Differences left: M3-V08 uses the native safe area, live index counts and actual fixture names; V09 import description wraps one word earlier than the canonical.
Not verified: real Day One export, multi-GB import, owner iPhone; old imported tags require re-importing the source ZIP.
Next: M5-V15 Reconciliation cadence/BNPL; then continue the owner-approved ideas before the M7 gate.
Model/effort: not exposed / not exposed. Usage: 64% five-hour used / 58% weekly at last check.

## Handover — M6-V14 English word tools — 2026-10-19 — Codex
Works now: English word selection offers truthful dictionary availability, save-to-كلماتي with source/context/undo, and conditional on-device translation. The action card uses native interactive glass over the paper reader.
Verified: Data + Commands focused tests 1/1 each; iPhone 17 Pro / iOS 26.5 UI V14 + V08 2/2; `compare-screens.py R9-Reader-En-Word`; `git diff --check` clean.
Differences left: “original” has no simulator dictionary definition; English→Arabic translation is unsupported in this simulator; native selection handles remain visible while the card is open.
Not verified: translation output on a device with the language pair installed; owner iPhone.
Next: M6-V22 Auto-scroll (owner-approved v1).
Model/effort: not exposed / not exposed. Usage: 39% five-hour used / 54% weekly at last check.

## Handover — M6-V21 paragraph listening — 2026-10-19 — Codex
Works now: the reader speaks the current spine's paragraphs in sequence, highlights and scrolls to each one, and provides pause/resume/stop with native glass speed controls from ١× to ٢×. It stops under lock, backgrounding or covering sheets.
Verified: iPhone 17 Pro / iOS 26.5 listening UI 1/1; V21 + V14 + V08 regression 3/3; `compare-screens.py R10-Istima`; `git diff --check` clean.
Differences left: synthetic EPUB has 8 text blocks and repeated fixture text around a footnote versus the canonical's 5 paragraphs; app reader header remains visible.
Not verified: audible quality across device voices, interruption behavior, owner iPhone.
Next: M6-V22 Auto-scroll (owner-approved v1); then revisit M6-T01 to resolve the ALS app bridge.
Model/effort: not exposed / not exposed. Usage: 41% five-hour used / 54% weekly at last check.
