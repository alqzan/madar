# Codex brief — M2 Quran (القرآن), one session

Owner request, 13 October 2026: Codex builds the next section (M2 Quran) in a single session. This file is a hint sheet, not a spec. The protocol is root `AGENTS.md` (working protocol, 13 October 2026). The owner lifted the M2 pause with this request; no iPhone test until the whole app is finished.

## Start here
1. Read `AGENTS.md`, then `docs/PROGRESS.md` (board, last three handovers). Add the M2 cards to the board before coding (they do not exist yet; the preflight card M2-RQ2 is done).
2. Spec for this room only: `docs/HANDOFF/sections/11-r-quran.md` (§7.4), the §8 shared systems it references, §5 shapes in `05-ds.md`, and fixes **RQ1–RQ7, RQ9** in `docs/HANDOFF/Madar - Handoff Review Fixes - V1.md`. Use `grep`; do not load the whole handoff.
3. Decisions already made (do not reopen): `docs/DECISIONS.md` — RQ1 computed-need formula and the 100/300/604-page simulation targets; RQ2 `PageSchedule.stage` removed. The Mushaf licence is obtained. Tafsir stays off (RQ8).
4. Engine audit and test disposition (KEEP / REWRITE / DROP for the 12 old tests) are in the M2-RQ2 card and the Quran extract. Port from the pinned source (My-dream `aba0c1b18a3bf3fc070395a40595e939c3b73aa3`) only what the audit says to keep.

## Order of work
1. **Engine first**, pure Swift in a new `Packages/MadarQuran` (or the existing package layout): interval/ease, due-risk, adaptive cap, computed need (RQ1), partial pages and khatm (RQ5), one definition of "far" (RQ4), learning peeks as hints (RQ3). Tests with expected values taken from the spec (§13), never from the engine's output.
2. **Data**: optional or defaulted properties, no unique constraints, tombstones, natural keys, the single `MadarData` container (local only). One Mushaf edition for all data (RQ7).
3. **Screens in board order** (`docs/HANDOFF/screens/quran/`): 01 Sharh, 02 Map, 03 Home, 04 Hifz, 05 Rev, 06 Drill, 07 Khitam, 08 Mushaf, 09 Widgets (v1 widgets only), 10–13 Sijil, 14 Khitta, 15 Setup, 16 Hurra, 17 Fihris, 18 Mansub, 19 Qiyam. Check each against §12: anything not v1 has **no entry point** (no disabled buttons, no "coming soon").
4. Each screen: canonical files → default-size screenshots (L, light unless canonical is dark) → `python3 Madar/scripts/compare-screens.py <board> <shot.png> [<scrolled.png>]` → fix → `matched — awaiting owner`. Only the owner sets `approved`.

## Rules that bite in this room
- Day boundary: `core.dayStart` (not the prayer day). A stored `dayKey` is never recomputed.
- One fact, one owner: the Quran room writes recitation/hifz; other rooms read. Prayer's «ورد القيام من محفوظك» row (V07) becomes possible only after this room exists — wire it last, and only if §12 says v1.
- Sanctity: no Quran notification, sound or Live Activity from adhan to the end of the sanctity window; every scheduled time goes through the single guard (RP3).
- Streaks derived, never stored. No money here. Arabic RTL, Arabic-Indic digits, never "·" next to a digit (RU1).
- Mushaf page text: zoom and a semantic ayah layer instead of the AX list alternative.
- Test at default text size only. Build in a worktree-free flow: commit finished cards on `main`.

## Visual notes learned in M1 (save the owner's time)
- The owner rejects generic cards and stock grey `Form`/`List`; use the room's paper background and arch language (see `PrayerTodayView.swift`, `PrayerStreakArches`).
- Lattice, ring and arch drawings must stay inside their shape; clipped or spilled ornament was the owner's most repeated complaint. Check the dark capture too (`MADAR_UI_THEME=dark`).
- Labels must wrap, never truncate with "…".
- Arabic plural forms («يوم واحد»، «يومان»، «٣ أيام») everywhere a count is shown.
- Sheets use content-height detents (`.height(contentHeight)`), not full-screen, when the canonical shows a short sheet.

## Done means
Engine tests green with command output shown; every v1 screen built and compared; board rows updated; one handover (≤ 7 lines); one commit per card. Do not claim an iPhone pass.
