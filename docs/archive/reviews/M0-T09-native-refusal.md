# M0-T09 — native nonmatch, cancellation and explicit retry

**Verdict: approve — bounded source and native default-L/light regression only. No findings.**

12 October 2026 — independent review of `b7cd5d1..fa54e5d102f58637fa55a8c4793ddc0edab0e307` on `codex/m0-t09-native-refusal`. Authority: `14-shared.md` §8.10, the presentation-privacy design and current T09 acceptance claim. Reviewed only the new UI regression and biometric driver; no production/authentication/default change or repeated review of accepted source. The reviewer started no build or simulator run.

## Source judgment

The driver generates a dedicated UUID fixture, propagates it to the UI test and limits filesystem metadata reads to that fixture's real, non-symlink `Backups` directory. The test waits for native failed-match/retry UI before tapping the OS Cancel control and retains the full OS screenshot/hierarchy before its assertion. Recovery must leave no share/file/Files option for five seconds; a new explicit export tap must await fresh authentication. The driver requires recorded `--failure`, empty initial/post-cancellation Backups before injecting retry success, and exactly one nonempty plain export file after success. No app authentication bypass is introduced. The committed tree matches the reviewed diff; `git diff --check b7cd5d1..fa54e5d` passed.

## Native evidence

Retained raw command/log, enrollment/nonmatch/retry JSON, fixture and three backup snapshots, xcresult and seven attachments are under `Madar/Artifacts/t09-native-retirement-2026-10-12/run-fa54e5d-biometric-refusal/` (ignored). Independently inspected their outputs, attachment manifest, both native authentication hierarchies and all five original PNGs. The selected test ran on iPhone 17 Pro simulator `412F4437-7BD7-44D1-AA3D-2B7158090E14`, iOS 26.5 (`23F77`), at L/light.

- `nonmatch.json` records `--failure`, successful command execution and `simulateFailedMatch`. PNG `D8C7B3D8-A73D-4CCA-8573-0F2947F67FD5.png` and its hierarchy show the real Arabic failed-match alert, **لم يتم التعرف على الوجه**, with Try Again and Cancel. The log identifies the tapped control as `com.apple.localauthentication.ax.authentication.button.cancel`. The following app alert says authentication was cancelled. This is a failed match followed by user cancellation; one failed match did not terminally deny authentication.
- Exact fixture `F99A88C0-645E-4407-B4EE-300FA36F33B5` has `files: []` before nonmatch and after cancellation. Recovered PNG `E7354B15-980D-4100-A8A0-FC0D59A0C2E7.png` shows the ordinary notesOnly backup shell with its export button and no share sheet/readiness. The native trace confirms the five-second absence check before the next explicit tap.
- After that explicit tap, `retry-match.json` records a fresh `--success`/`simulateSuccessfulMatch`. Only then does the fixture contain one 14,091-byte `PlainExports/.../Madar-2026-10-12-plain.zip`. PNG `9B7E8B99-B821-4667-9088-C2E174537E0B.png` shows its native share sheet and Save to Files option. The test then dismisses sharing and recovers the foreground shell.

Saved selected-test output:

```text
Executed 1 test, with 0 failures (0 unexpected) in 42.658 (42.658) seconds
** TEST SUCCEEDED **
```

## Boundary

Accepted: native failed Face ID match plus user cancellation prevents plain export publication/sharing at the measured checkpoints, and explicit authenticated retry succeeds at default L/light. This does not establish biometric lockout/terminal device denial, encrypted export/key absence, archive-content validity, Files destination writes, AX3/dark refusal variants, true two-scene behavior, physical iPhone acceptance or full T09/integration/M0 approval. Existing accepted privacy evidence keeps its separate limits.
