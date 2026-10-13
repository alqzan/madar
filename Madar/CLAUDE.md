# Madar app workspace

Follow `../AGENTS.md` (identical to `../CLAUDE.md`): product rules, the working protocol and the repository map are there. The board is `../docs/PROGRESS.md`; owner decisions are in `../docs/DECISIONS.md`.

- Screens are accepted against their canonical files in `../docs/HANDOFF/screens/`: `python3 scripts/compare-screens.py <board> <shot.png>`.
- Build, test and preview commands are in `README.md` and the `Makefile`. Run `python3 scripts/prepare-workspace.py` before native builds in a fresh checkout.
- No public deployment, production CloudKit schema, or migration of the owner's real records without the owner's explicit go.
