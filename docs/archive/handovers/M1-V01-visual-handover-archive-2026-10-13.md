# أرشيف تسليمات M1-V01 — 13 أكتوبر 2026

## Handover — M1-V01/V05 arches and day sheet — 2026-10-13 — Claude

Works now: home prayer arches keep their lattice inside the dome with a clean rim (no clipped or spilled lattice); the past-day sheet opens at content height over «حالي» like the canonical; V05 test now also captures `-s1`.
Verified: UI tests V01 home, V05, T05, StreakArchMonth passed on iPhone 17 Pro simulator; compare page `Madar/Artifacts/compare/S4-Day.html`.
Differences left: state icons on day-sheet pills (earlier owner colour decision); next-prayer arch shows a thick outline with the lattice mostly under it.
Dark mode checked in the simulator (home arches and «سلاسلك»): fine; the truncated streak labels («الخمس في…», «إتمام الخم…») now wrap. Owner decision 13 Oct: no iPhone test until the whole app is finished, so M1-G waits.
Not verified: owner look; owner iPhone (M1-G).
Next: owner approves V01/V05, then the M1-G iPhone gate.
Model/effort: Claude Sonnet 5.5; effort not exposed. Usage: not exposed.

## Handover — M1-V01 «سلاسلك» stone arch — 2026-10-13 — Claude

Works now: home «سلاسلك» is three nested horseshoe arches in the home-arch shape (congregation inside, on time, completion outside), each one continuous line filling right to left and complete at a month; tap opens the details sheet (meaning, last seven days, break reason) and from it «حالي». Codex's pending F04/F05/S4 work committed earlier (`7182082`).
Verified: MadarPrayer `swift test` 25 passed; UI tests V01 home, streak sheet, streak month (9/16/24), V04 passed; V05, T05, T06 passed after the route change.
Differences left: no bead arc or month % on the home card (owner decision); S1 scrolled alignment and V05 `-s1` capture open.
Not verified: owner look; owner iPhone; dark-mode capture of the arch.
Next: owner reviews the arch; then V05 `-s1` and the S1 compare page.
Model/effort: Claude Opus 5.5; effort not exposed. Usage: not exposed.
