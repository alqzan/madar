# M0 local store and retention fix review

Verdict: **approve — scoped M0-T03 changes only**.

Reviewer: Codex, GPT-6.1 Sol xhigh (Top), 2026-10-10; independent of the implementation. Reviewed commit `4297c8af7c6342d99e64254a3a43f048905aeb9f` on `m0-s1-local-retention` before root integration, using its complete fix diff and RA1/RD2 plus the current owner decisions. No production edits or simulator work performed by this reviewer.

**Findings: none in the reviewed fix diff.**

The factory now constructs every configuration with `.none`; the legacy CloudKit argument, stored preference and managed-pointer identifier cannot enable a cloud-backed binding. Initial reopen and generation refresh both preserve legacy pointer/account metadata without reopening CloudKit. RD2 removes only the Entry→MarginNote and Book→ReadingSession/Highlight cascades. It retains child identities/content/day keys, the Book tombstone title and file, shared media, existing HifzSession child ownership, alias remapping and historical child deletion barriers. All three dictionary copies change only the two matching deletion-policy strings.

Regression expectations come from RA1/RD2 and the owner contract, rather than captured implementation output. Exact records/fingerprints are used to establish preservation, with reconciliation idempotence and explicit restoration tested. The reading title is preserved on Book; this change does not add or assume a ReadingSession title field.

Command output read by the reviewer:

| Evidence | Final output |
|---|---|
| `/tmp/madar-data-rd2-red.log` | `Test run with 3 tests in 1 suite failed ... with 3 issues` — the new retention checks caught the original cascades before the fix. |
| `/tmp/madar-data-local-rd2-scoped.log` | `Test run with 6 tests in 2 suites passed after 0.516 seconds.` |
| `/tmp/madar-data-local-rd2-full.log` | `Test run with 38 tests in 3 suites passed after 6.886 seconds.` |

These are the implementing agent's actual macOS package-test logs, independently read, not a second test execution by this reviewer. `makeAppGroup`'s entitlement-dependent path is source-inspected; no physical-device CloudKit monitoring was performed. Diary/book screens do not yet ship, so deleted-origin arrow behavior is a future room UI acceptance check rather than an implementation accepted here. RA2, RA4, RA8, migration of owner data, full app/device gates and whole-M0 approval remain outside this verdict. This scoped change resolves M0R-01 and the data-layer portion of M0R-02; no previous review was broadly repeated.
