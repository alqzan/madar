# M0-S2 backup copy — T14 scoped section review

Verdict: **approve** (scope only).

Reviewer: independent Codex reviewer, GPT-6.1 Sol, Standard high; 2026-10-12.
Reviewed candidate: `m0-s2-backup-local-only-copy`, commit `d4a869d`.

No findings.

- `BackupSettingsView.swift:227,279` now describes replacement on this device in both confirmation and preview. RA1 local-only v1 overrides the all-devices wording in handoff §17 (`17-data.md:406`); the precedence is recorded in `docs/DECISIONS.md`.
- `CustomizationCopy.swift:13–23` preserves the safety backup, tombstone and explicit restoration warning, the merge wording, and the password notice. Passing `status?.keyConfigured != false` preserves the previous notice condition, including nil status.
- `CustomizationCopyTests.swift:6–18` uses literal expected replacement and unchanged merge copy, rejects the old all-devices claim, and checks the password notice for an unconfigured key. The reviewed existing `/tmp/madar-ra1-restore-copy.log` shows `Executed 1 test, with 0 failures` and `** TEST SUCCEEDED **`; this reviewer did not rerun it.

Boundary: source and focused host copy test only. Native preview/confirmation UI, layout and spoken accessibility were not rerun. No restore, store or synchronization behavior changed; this approval does not accept T09 privacy or the M0 gate.
