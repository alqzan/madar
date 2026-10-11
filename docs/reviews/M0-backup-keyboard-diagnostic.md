# M0-T05 keyboard diagnostic — independent narrow review

Verdict: **approve** for `b986f7d..98216ab` source scope. Reviewer: Codex Sol, Standard high, 2026-10-11. No findings.

Read root `AGENTS.md`, the M0-T05 card, the two-file fix diff and its report. Consulted only the adjacent export predicate, unchanged secure-field traits, test journey and fixture routing needed to establish the fix's boundary. This does not review old branch ancestors or approve the whole backup, privacy or M0 gate.

The added keyboard diagnostic is compiled only under `DEBUG` and requires `UUID(uuidString:)` acceptance of `MADAR_UI_STORE_ID`. Release and non-fixture Debug views use the original Done/export buttons without an accessibility value. A normal UUID also satisfies the existing ASCII fixture routing in `Madar/App/MadarApp.swift:60–64`, which redirects both store and backup Keychain service to that fixture. The diagnostic exposes character counts and Boolean match/busy/export eligibility only; it never embeds passwords, keys, paths or stored user data.

The keyboard Done action remains `focusedPassword = nil`. The secure fields' AutoFill content types, native Next/Done handling and focus bindings are untouched. No model, validation, encryption, export, privacy, setting or persistence behavior is changed. `can-export` reads the actual `model.canExport` predicate at `BackupSettingsView.swift:81`, which directly drives the export button's `.disabled` state at line 226.

The test's mismatch assertion now observes that predicate on the visible accessory while the export row is virtualized. It still enters both native secure fields, uses native Next, checks mismatched counts/eligibility, deletes only the extra final character without re-tapping the populated field, then checks corrected counts/eligibility. After dismissing the keyboard it materializes and checks the actual enabled export button, performs export, waits for the actual encrypted-export result, and checks same-fixture relaunch key persistence plus fresh-fixture isolation in both L and AX3. The mirror is therefore diagnostic support for the full journey, not a substitute for completing it.

Evidence read/run:

```text
Author Madar/Artifacts/t05-keyboard-diagnostic-build-for-testing.log:
** TEST BUILD SUCCEEDED **
Reviewer: git diff --check b986f7d..98216ab
(exit 0, no output)
```

Not executed by this reviewer: builds, simulator or host tests, screenshot comparisons, physical device, VoiceOver, or privacy-sheet checks. Root owns the exact full L/AX3 rerun and must record its result before claiming runtime acceptance. Source inspection establishes Release exclusion; a Release runtime check was not performed.
