## Handover — M2-R01 Mushaf source decision and provenance — 2026-10-13 — Codex

Works now: owner decision recorded: all Quran text/maps/boundaries use 1439H; 1405H is limited to page frame and surah-opening ornament. M2-E03 and M2-V15 now point to 1439 data.
Verified: inspected the official KFGQPC v2.0/update 13.0 archive (SHA-256 `a7b0e5591945712ec5e4d6142938ae4d1e9b49bdc89dff06222789bfebdfd72c`); its readme documents ayah text, page, line_start/end and juz fields. The official guide and KFGQPC description identify the digitally processed 604-page Mushaf with the 1439H edition and per-word layers. `git diff --check` passed.
Differences left: the archive does not carry word coordinates or explicitly identify its edition in its readme; 1405 ornament files are not integrated.
Not verified: source-to-edition linkage, human review, resource integration, app build or owner iPhone.
Next: complete M2-R01 by pinning the 1439 map and separately documenting 1405 ornament provenance, terms and hashes; then continue M2-E03.
Model/effort: GPT-6; effort not exposed. Usage: not exposed.
