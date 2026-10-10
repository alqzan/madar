# Handoff working copy

Copied from `output/madar-recheck-2026-10-10/source/` on 2026-10-10. The original stays untouched there. Root AGENTS.md / CLAUDE.md are the current protocol; the newly supplied review fixes override this bundle. Human decisions in `../DECISIONS.md` override both.

`sections/` contains 25 text-only extracts, one per original HTML section, including the introduction and gallery. Inline markup is removed and whitespace normalized; no behavior is rewritten. `sections/index.json` maps original IDs and SHA-256 values. Corrections are tracked separately rather than silently rewriting these extracts.

Executable JSON contracts currently live under `Madar/Specification/` and package resources. Before-M0 corrections must update all working copies together and validate consistency; copying the new review document alone is not implementation.
