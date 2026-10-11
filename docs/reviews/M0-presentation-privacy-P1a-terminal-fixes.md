# M0-T09 P1a — terminal fix-only review

Verdict: **approve** — bounded source approval for M0P1a-05/-06 only.

Independent codex Top review of `e3870d6..5102620`, read commit by commit (`fec37c5`, `fc7b645`; documentation `5102620`). Review branch: `codex/m0-p1a-terminal-review`. No production edits, generic build, simulator, host test or primary-checkout mutation performed by this reviewer. Root owns the 17 privacy host tests and current-baseline integration. Compilation reported by the author is not execution proof.

## Findings

No findings in this bounded fix diff.

## Closure

- **M0P1a-05 closed:** `Madar/App/MadarLock.swift:204–250` gives scope persistence separate UUID ownership, serializes overlapping writers, and resolves matching origin/peer pending states after background or disconnect. Both success and failure read the actual stored setting, including failures after save. Unreadable settings require reconciliation before authorization. Revoked presentations remain covered until an explicit authorized action; obsolete terminal IDs cannot finish a newer request. `AppPrivacyService.swift:34–41` reads settings and rejects unavailable/invalid state. `ScenePrivacyPresenter.swift:39–61` carries request IDs and only sends matching terminal outcomes to controllers, retaining synchronous pre-await coverage.
- **M0P1a-06 closed:** `Madar/App/MadarLock.swift:175–186` rechecks request ownership/cancellation, active phase and the captured lifecycle epoch after the child binding task returns. A lifecycle-invalid commit covers and queues cleanup before rejecting. The internal completion-boundary seam defaults to no action and never skips authentication or validation.
- The five added test methods use controlled delayed persistence and a deterministic commit interruption. They cover background/disconnect with save success, failure before save and failure after save; cancellation followed by a committed save; obsolete terminal IDs; and inactive commit rejection, cleanup and subsequent fresh authorization. Expected scopes, ticket rejection, cover state and binding state are asserted independently of controller output. The full privacy class now has 17 methods. Root must report their actual execution before treating them as passed.

## Acceptance boundary

This accepts the two source repairs, not full P1a runtime behavior, P1b or M0. Peer regressions use two controllers and one presenter in a single actual host scene, not two actual scenes. Real two-scene ownership/disconnect isolation, native presented-sheet/inactive/app-switcher frames, default/AX3/dark/accessibility, protected-data transitions and physical Face ID/passcode remain unverified until root runs and records them. P1b export/key/cached-share/private-note authorization remains separate and unfinished.
