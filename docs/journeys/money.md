# Money journeys — M5

References: 12-r-mal, 19-qa; RM fixes. Apply [common states](README.md); synthetic/anonymized corpus, no OTP retained.

| ID / planned test | Steps and expected outcomes | State cases | Device requirement |
|---|---|---|---|
| J11 / test_J11_messageReviewLedger | Ingest every supported SMS class with printed timestamp/card kind; preview parsed transaction/unknown manual review, edit/cancel/save. Exact replay once, near duplicate asks. Reconcile owned transfers, refund/obligation/card settlement and funded envelopes; verify conservation/net allowances and salary-cycle timestamp. Edit/delete/undo/explicit restore; no silent account/card assumption. Manual nisab method/price. | Long 40-char merchants, 7-digit/negative values, 30 envelopes, 200 cycle rows, mixed currencies; parser/corpus errors, lock, near duplicates, OTP message. | Engine/store/simulator L/AX5; actual iPhone Shortcut F09 plus privacy. |

J12 covers travel/manual FX; J16/J17/J18 required. MoneyTransaction compatibility must preserve prior IDs/links without treating schema rename as deletion.
