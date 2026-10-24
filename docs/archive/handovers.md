
## Handover — diary denial, paper guidance and money clarity — 2026-10-21 — Codex
Works now: microphone refusal survives editor recreation and typing; paper indexing makes no edition-match promise; trip funding explains source/eligibility and units; accounts/home/analysis use Thmanyah figures; money journal columns show both calendars; obligation preview has a legend/unit and hides existing-money proportions when amounts are hidden.
Verified: `xcodebuild -project Madar/Madar.xcodeproj -scheme Madar -destination 'platform=iOS Simulator,id=412F4437-7BD7-44D1-AA3D-2B7158090E14' … test` — 18 distinct focused UI cases passed across recorded runs (3+1+3+2+1+4+2+2); native app/widget builds succeeded. Per-card commands/results and default L/light comparisons recorded above; `build-ui-gallery.py` 104 screens, 128/129 actual states; `git diff --check` clean.
Differences left: paper card long title plus saved position clips the details button at its 360-point detent; fitting attempts reverted after unstable return height. Existing fixture numbers/native floating navigation differ from prototypes; no new owner visual acceptance claimed.
Not verified: owner iPhone, hardware microphone/VoiceOver, real OS widgets/notifications, iOS 27 runtime, dark mode, device performance and distribution; no enlarged-text runs per owner. M7 remains open.
Next: continue the live queue and safe money/Mihbara improvements; retain the bounded long-title-card blocker. Paid-account/signing and real-device gates remain postponed by owner.
Model/effort: not exposed / not exposed.
Usage: 95% five-hour used / 37% weekly used at the final live check; stopped new work with 5% remaining, no reset or credits used.

## Handover — owner money import trial, VoiceOver dropped — 2026-10-23 (2) — Claude
- **Works now:** item 17 slice 1. The owner's old money backup imports into an isolated UI-test store: 25 own categories, 4 accounts, 9 cards, 187 rules, 533 movements (494 confirmed, 39 in review). A second run adds 0. The money first page leads to the salary once accounts exist. Owner: VoiceOver dropped forever; item 16 is test tooling only.
- **Verified:** `swift test --filter LegacyMoneyImport` 5/5; `MoneyOwnerTrialUITests` passed (`Claude-money-trial-20261023-r9.xcresult`, report `owner-data/money-import-*`); `MoneyFirstRunUITests` passed (r8). One money review pass (Sonnet): day check, cards keyed by bank and last four, debit card linked only to a bank's single account, no auto-confirm of a possible duplicate. All applied.
- **Differences left:** the empty envelopes block (dotted square, two diamonds) looks unfinished with no envelopes; «في حسابك» is negative until opening balances are set.
- **Not verified:** owner iPhone; any store other than the UI-test store (the hook is DEBUG plus env plus UI-test store only).
- **Next:** item 17 slice 2 (cycle settings: `dailyBudget`, `salaryDay`; there is no salary message in the old data, so the cycle starts with the owner's salary), then the owner's Quran, prayer and habit data. Owner decisions to add to the list: opening balances, which account the mada card draws on, the source of the rows before 21 Sep.
- **Model/effort:** claude-opus-5-5, effort not exposed. **Usage:** about 50% of the 5-hour window at the last reading.
