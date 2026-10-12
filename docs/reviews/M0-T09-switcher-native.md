# M0-T09R — native switcher snapshot

**Verdict: approve — bounded native default-L/light switcher acceptance only.**

12 October 2026 — independent review of new native evidence for `b7cd5d1edac22dd588b08df1e2bcfc844a7acdaf`, `codex/m0-t09-switcher-sdk-repair`. The previously approved SDK-only fix was not reviewed again. No additional build or simulator run was started by this reviewer.

Authority: `docs/HANDOFF/sections/14-shared.md` §8.10; `docs/design/M0-presentation-privacy.md`; the current M0-T09R card. **No findings.**

## Verified evidence

Raw evidence remains at `Madar/Artifacts/t09-native-retirement-2026-10-12/run-b7cd5d1-switcher-snapshot/` (ignored): command, biometric enrollment/match output, app-process trace, Xcode log, xcresult, attachment manifest, two SpringBoard hierarchies and all three original PNGs. Reviewed those files independently. The manifest ties the images/hierarchies to `FoundationUITests/test_M0T09_DefaultNativeShareSwitcherCaptureIdentifiesMadarCard()` on iPhone 17 Pro simulator `412F4437-7BD7-44D1-AA3D-2B7158090E14`; the log identifies iOS 26.5 (`23F77`).

- `match.json` reports a successful native simulated Face ID match. `BB0A32A8-4ADB-48F1-876E-333C96A0F1A0.png` shows the authorized native share sheet, its plain archive filename and Save to Files option before the switcher gesture.
- The raw log and both hierarchies identify exactly one target card: `card:com.alqzan.madar2:sceneID:com.alqzan.madar2-D0D58FA5-1BB2-49A3-B7A3-78B83463F078`. The other installed app also named مدار has a different bundle identifier. The initial image `E5F4B1E1-6BD8-4FBE-97C0-A2BE6A0788C1.png` is cropped and supplies supplemental evidence only.
- After one target-directed horizontal pan, `E84C46F8-5358-4F16-82A6-BEDAC36B2A8F.png` shows the full centered target card. Hierarchy `4C36B2EC-6FAC-4AFB-AD67-5EB10FF19E80.txt` confirms its frame `(63.3125, 128.9828, 275.3751, 598.7010)` lies within the `402 × 874` screen. The complete card is covered by an opaque white lock presentation with generic Arabic text. No archive filename, native share controls, underlying Settings content or protected content is visible. The trace does not reopen the app between the switcher gesture and the capture.

Saved command output:

```text
Executed 1 test, with 0 failures (0 unexpected) in 31.396 (31.397) seconds
** TEST SUCCEEDED **
```

## Acceptance boundary

This closes the single actual identified/full-card OS snapshot result at default L/light, together with the existing SDK source approval. It does not approve full T09, its production integration, a section or M0. The images do not prove the precise synchronous inactive-cover boundary, AX3/dark switcher captures, genuine refusal, true two-scene behavior, spoken VoiceOver, Files destination writes or physical owner-iPhone acceptance. Existing separate accepted auth/retirement/lease evidence retains its original limits.
