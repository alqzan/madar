# M0-T10 foundation prayer clocks — independent review

Verdict: **approve** (source and task scope; runtime/visual acceptance remains a separate pre-merge requirement).

Reviewer: fresh Codex Sol, Standard high, 2026-10-11. Reviewed commit `3dc85ae` against `451289e`, commit by commit. This narrow UI presentation adds no engine, persistence, concurrency, notification, widget or intent implementation.

Authority read: root `AGENTS.md`, the M0-T10 card in `docs/PROGRESS.md`, RA3 in the review fixes, and the clock-reference passage in `docs/HANDOFF/sections/09-r-salah.md:177–190`. Review covers the changed FoundationHome presentation, host tests and UI test. Unchanged engine/session definitions were consulted only to confirm option types, observed setting values and active-place semantics.

No findings.

The implementation presents exactly Fajr, Dhuhr, Asr, Maghrib and Isha from the existing engine for the active place's current Gregorian civil day. It passes the stored method, Asr convention, high-latitude rule, offsets and Hijri calculation options. The minute timeline and observed session values refresh day/place/settings; calculation failure yields no fabricated rows. Selected numerals use the existing formatter, clock text has bidi isolation, accessibility sizes stack the name and clock, and each row exposes one Arabic semantic label. The diff adds no room route, logging or notification entry point and changes no stored day key.

The new hosted assertions use the approved Riyadh 2026-10-09 row, converted to unambiguous 24-hour clocks; UTC conversion and the five-minute offset have explicit arithmetic expectations. They also cover numeral style, a place-local day across UTC midnight, ordering and polar unavailability. The UI test exercises default, AX3, AX5 and dark configurations and retains first/last-row screenshots. Root executed the hosted tests; this reviewer read their raw output. The root UI run remains in progress.

Evidence checked:

```text
Candidate Madar/Artifacts/M0-T10-build-for-testing.log:
** TEST BUILD SUCCEEDED **
Root Madar/Artifacts/run3-today-times.log:
test_M0T10_FoundationPrayerClocksUseGoldenDayNumeralsAndZone passed (0.005 seconds).
test_M0T10_UnavailablePrayerClocksNeverFabricateRows passed (0.000 seconds).
Executed 20 tests, with 0 failures (0 unexpected) in 4.976 (4.982) seconds
Reviewer: python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
Reviewer: python3 Madar/scripts/check-number-separators.py
PASS: RU1 app numeric separator source check
Reviewer: git diff --check 451289e..3dc85ae
(exit 0, no output)
```

Not verified here: simulator flows, actual default/AX3/AX5/dark image comparison, VoiceOver interaction, location/settings runtime changes, or physical iPhone. The root agent owns the simulator and must record those results before merging. RA3 owner-iPhone acceptance and the M0 gate are still open; this approval does not close either.
