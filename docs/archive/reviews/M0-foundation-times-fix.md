# M0-T10 clock accessibility identifier repair

Top repair/self-check: Codex Sol xhigh, 2026-10-11. This is the repair author's record, not an independent review or section approval.

After two Standard UI attempts, candidate `40f4216` was preserved as `m0-s2-foundation-times-candidate-40f4216`. Normal revert `1308a5b` restored the pre-clock product code on `m0-s2-foundation-times`; narrow branch `m0-s2-foundation-times-id-fix` starts from the preserved candidate.

The root's actual UI hierarchy showed each clock row inheriting the card identifier `foundation-prayer-times`. Remove that parent modifier at `Madar/App/FoundationHome.swift:63`; retain each row's unique `foundation-prayer-time-<prayer>` identifier and Arabic semantic label. No layout, engine, setting, data or notification behavior changes.

The existing `FoundationUITests.test_M0T10_TodayPrayerTimesAtDefaultAX3AX5AndDark` checks all five row identifiers and labels at default, AX3, AX5 and dark settings and remains the runtime regression. Source self-check covers only the one-line product diff and read-only contract/number lint.

```text
git diff --check
(exit 0, no output)
python3 Madar/scripts/check-review-contracts.py --require-ra4
PASS: 88 amended contract checks (read-only; device acceptance not tested)
python3 Madar/scripts/check-number-separators.py
PASS: RU1 app numeric separator source check
```

Not tested by this repair author: build, hosted tests, simulator accessibility hierarchy, screenshots or physical iPhone. Root owns those checks; a fresh Standard reviewer must inspect the fix diff before merge. M0 remains open.
