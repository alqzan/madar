# M0-T05 keyboard dispatch diagnosis

Codex, GPT-6.1 Sol xhigh (Top), 2026-10-11. Scope: backup UI test input only.

The root's actual simulator run `Madar/Artifacts/run3-secure-native-ready.log` proved that the production secure field accepts Arabic input: tapping the observed native «ت» key produced passphrase count 1; `typeText("ت")` produced count 2. With that Arabic keyboard still active, `typeText("t")` left count 2. The selected probe failed at its Latin-count assertion, before any export. Earlier partial Latin passphrases therefore demonstrate a test keyboard-language dispatch defect; they do not establish broken password equality or a production field defect.

The previous capture also exposed an offscreen software-keyboard preview. After the root disabled simulated hardware-keyboard connection in Device Hub, the readiness-corrected test selected an actual hittable Arabic key. These are root-run observations, not a physical-device check.

The test-only repair waits for real hittable keyboard keys, then uses the observed native next-keyboard button only when its announced next layout is English. It makes one deliberate language switch and requires a hittable `t` key before Latin test input. The helper is used by the Arabic/Latin probe, Latin typing probe, and both password fields in the L/AX3 backup confirmation journey. Duplicate AX keys and keyboard presentation are handled by a bounded readiness expectation; no unknown layouts are cycled through.

Production SecureFields, AutoFill traits, minimum ten characters, exact confirmation equality, DEBUG UUID store/Keychain isolation and the lock gate are unchanged. Only synthetic fixture inputs are entered; diagnostics contain counts and match state, never actual passwords.

Verified in this subtask: source diff and `git diff --check`. Root evidence: native Arabic count 1 and Arabic typing count 2; the selected run ended `Executed 1 test, with 1 failure` / `** TEST FAILED **` at Latin transport. No build or simulator operation was started by this agent.

Pending: root rerun of the corrected Latin probe and the complete L/AX3 mismatch → correction → encrypted export → same-fixture relaunch → fresh-fixture isolation journey. No successful export, whole M0 acceptance, physical keyboard flow or privacy-sheet gate is claimed yet.

Integration: apply only the scoped new test commits/report to the current accepted baseline. Do not merge diagnostic branch ancestors or copy the whole older test file, which would replace unrelated current-baseline tests. The old mixed-character experiment in `e1ae006` is not part of this accepted-baseline repair.
