# M0 backup UI fix review

Verdict: **changes requested — scoped M0-T05 verification**.

Reviewer: Codex, GPT-6.1 Sol xhigh (Top), 2026-10-10; independent of the implementation. Reviewed the three-file diff in root commit `20eb1f104632a33df7117cddd51624f905d4f414` (implementer's original commit `2f6a8a8`), then read the root's current simulator test log and inspected `Madar/Artifacts/backup-current-AX3.png`. No simulator/test process or production edit was started by this reviewer.

| ID | Severity | Location | Finding and fix |
|---|---|---|---|
| M0U-01 | High | `Madar/Tests/UI/FoundationUITests.swift:32` | The required matching-password/export journey still fails: after native Next, mismatch rejection and replacing the confirmation, `backup-now` remains disabled. `Madar/Artifacts/backup-fixture-check.log:519` records this first failing assertion. The later missing-share and relaunch-key assertions follow from no export and are not separate proven causes. Diagnose the focus/input sequence on the actual field state without logging secrets, correct the UI or test dispatch according to that evidence, and rerun both L and AX3 through successful export and same-fixture relaunch. Do not weaken equality validation or approve based on attachment names. |

The inspected AX3 screenshot confirms a disabled export button and no visible error alert at capture time. It does not show the input fields or prove why the values differ; newline insertion, selection/replacement and focus behavior remain hypotheses. Screenshots named `native-export` after the first assertion failed are failure-state evidence, not evidence that a backup was produced.

No static finding in the DEBUG-only Keychain isolation change: it uses the same validated fixture ID as the isolated store directory, retains the production service outside DEBUG fixtures, and passes the selected service into the actual backup key store. The added setup identifier and fresh/same-fixture expectations are appropriate; they still require a green flow before this task can be accepted.

**Evidence boundary:** the inspected root test log already contains the decisive failure; the complete run had not ended when this review was written. No successful L/AX3 export, key persistence or second-fixture isolation is accepted from this run. No physical-device keyboard flow, canonical-screen comparison, broader privacy gate, or whole-M0 gate is claimed. Root owns follow-up debugging and the final command output. Re-review only the resulting fix diff and its new flow evidence.
