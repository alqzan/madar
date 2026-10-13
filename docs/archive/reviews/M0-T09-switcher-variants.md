# M0-T09 — remaining switcher variants

**Verdict: approve — bounded selection change and two new native privacy snapshots. No findings.**

12 October 2026 — independent review of `fa54e5d..07d2ada`, `codex/m0-t09-switcher-variants`. Authority: `14-shared.md` §8.10 and the presentation-privacy design. Reviewed only the new two-file variant-selection delta and the two new native evidence sets. The already accepted L/light switcher result was not repeated or reviewed again. This reviewer started no build or simulator run.

## Source

The driver passes the selected variant to the runner. The test maps the bounded values to AX3/light, L/light or L/dark, rejects an unknown value, logs the selected size/theme and labels its attachments accordingly. Existing real authentication, exact-card identification/full-frame assertions and one-pan centering behavior remain intact. Refusal/lease paths remain fixed to L/light. No production/authentication/default change. `git diff --check fa54e5d..07d2ada` passed.

## New native evidence

Both runs use iPhone 17 Pro simulator `412F4437-7BD7-44D1-AA3D-2B7158090E14`, iOS 26.5 (`23F77`). Independently inspected the raw command, successful Face ID match output, variant/capture/gesture logs, manifests, all six original PNGs, complete centered hierarchies and target identities in the immediate hierarchies. Retained evidence is under `Madar/Artifacts/t09-native-retirement-2026-10-12/` (ignored).

| Variant | Retained run | Complete centered PNG | Selected result |
|---|---|---|---|
| AX3 app SwiftUI environment/light | `run-07d2ada-switcher-ax3-light/` | `EDCB93A4-C2B6-453E-BE7A-421DDCB49A8F.png` | 1 test, 0 failures, 40.609s; `TEST SUCCEEDED` |
| L/dark | `run-07d2ada-switcher-default-dark/` | `EE54C7F8-7C73-40D2-A663-206D05E9AA22.png` | 1 test, 0 failures, 31.445s; `TEST SUCCEEDED` |

The authorized-share images show the real archive/native sharing before each switcher gesture. Both logs/hierarchies identify exactly one `card:com.alqzan.madar2:sceneID:com.alqzan.madar2-D0D58FA5-1BB2-49A3-B7A3-78B83463F078`, distinct from the other installed app also named مدار. After one target-directed pan, its full frame is inside the `402 × 874` screen: AX3/light `(63.3107, 128.9791, 275.3785, 598.7085)`; L/dark `(63.3125, 128.9828, 275.3751, 598.7010)`. Neither trace reopens the app before capture.

The full AX3/light card is opaque white; the full L/dark card is opaque black. Only the lock and generic Arabic protected-content/unlock text remain visible. No archive filename, native share controls, underlying app content or protected content is visible. The immediate cropped images are supplemental evidence; judgment uses the complete centered cards.

## Boundary

These results close the two missing switcher privacy configurations. AX3 here is the app's SwiftUI launch environment: the form visibly grows, while the UIKit cover/native-sheet text does not demonstrate AX3 scaling. System-wide content-size/AX3 UIKit behavior remains unverified. This is no full accessibility judgment and does not prove the precise synchronous inactive boundary, true two-scene operation, physical iPhone behavior, Files destination writes or full T09/integration/M0 approval. Separate accepted privacy results retain their original limits.
