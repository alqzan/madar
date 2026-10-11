# M0 current software checkpoint — 2026-10-11

This is command evidence on accepted main5832a8e, not a Top milestone gate or iPhone acceptance. No owner data was opened.

## Current accepted baseline

Root simulator iPhone17Pro / iOS26.5 / Xcode27: `run4-main-copy.log` ends `Executed22tests,0failures in3.639s` and ** TEST SUCCEEDED **. Backup count grammar/numerals accepted after independent Standard review1ee273e and the scoped UI evidence in M0-T13-backup-copy.md.

All seven package commands exited0; raw logs `Madar/Artifacts/run4-final-<package>.log`:

| Package | Final output |
|---|---|
| MadarCore | Test run with22tests in0suites passed after0.011seconds |
| MadarData | Test run with57tests in5suites passed after17.290seconds |
| MadarCommands | Test run with17tests in2suites passed after1.436seconds |
| MadarInbox | Test run with6tests in1suite passed after0.015seconds |
| MadarPrayer | Test run with12tests in1suite passed after0.609seconds |
| MadarSnapshots | Test run with3tests in1suite passed after0.038seconds |
| MadarSync | Test run with8tests in1suite passed after0.809seconds |

125 package tests total. Passing compiled future/scaffold packages does not make their rooms available or accepted. RA1/RA2/RA3 scope remains in force.

Contract88 (`--require-ra4`), RU1 source guard and diff check pass. Shipping lint T11 remains unmerged: initial local-target dependency omission946c87d and computed-concatenation follow-upffc8e97 require Top fix and independent review. There is no complete static-lint success claim; dynamic trace inventory remains explicit.

## Unmerged candidates and limits

- P1a reviewed3a2bf6b and candidate9d4b0ae: hosted39tests,0failures in3.949s / ** TEST SUCCEEDED **, including17privacy regressions and two copy tests. The native cover test uses one real hosting scene; two logical controllers/presenters are not two real UIKit scenes. P1b and native modal/switcher/auth flows remain pending.
- Backup numeral UI plus gallery on candidate9d4b0ae:2tests,0failures in83.693s / ** TEST SUCCEEDED **; all two backup and12gallery images inspected. Gallery is DEBUG-only, with no shipping entry. This is visual layout evidence, not spoken VoiceOver or full accessibility audit.
- Accessibility candidate97a1577 deliberately records failures; natural system-size `.all` audit failed with8issues in30.628s. Top split remains active. See M0-T12-accessibility-candidate.md for exact observations; do not import that candidate's failing test to main.
- Manual UI control returned `noWindowsAvailable` for Device Hub; owner was asked asynchronously to open its simulator window while automated checks continued. Actual OS Reduce Motion, Face ID refusal/success, switcher snapshot, Files destination write, physical iPhone/protected-data/owner-store migration and full M0 gate remain **not tested**.
