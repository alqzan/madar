#!/usr/bin/env python3
"""Madar commit gate (owner, 17 Nov 2026): a `git commit` must say how the change was verified.

PreToolUse hook for Bash. Blocks a `git commit` whose message has no `Verified:` line
(e.g. `Verified: build; HabitsUITests 12/12; smoke` or `Verified: none — <reason>`).
Escape hatch: after two blocks in one session the next commit passes, so the agent never gets stuck.
Mode: MADAR_COMMIT_GATE=off|observe|enforce (default enforce). Observe only logs.
"""
import json, os, re, sys, pathlib

def main():
    try:
        data = json.load(sys.stdin)
    except Exception:
        return 0
    if data.get("tool_name") != "Bash":
        return 0
    command = (data.get("tool_input") or {}).get("command", "")
    if not re.search(r"(^|[;&|\s])git\s+(-C\s+\S+\s+)?commit\b", command):
        return 0
    if re.search(r"--amend\b.*--no-edit|--dry-run", command):
        return 0
    mode = os.environ.get("MADAR_COMMIT_GATE", "enforce")
    if mode == "off":
        return 0
    if re.search(r"(?m)^\s*Verified:\s*\S", command) or "Verified:" in command:
        return 0
    # A message from a file (-F) is read if it exists.
    m = re.search(r"(?:-F|--file)[ =](\S+)", command)
    if m:
        try:
            if "Verified:" in pathlib.Path(m.group(1).strip("'\"")).read_text():
                return 0
        except Exception:
            pass
    state = pathlib.Path(os.environ.get("TMPDIR", "/tmp")) / f"madar-commit-gate-{data.get('session_id', 'none')}"
    blocks = int(state.read_text()) if state.exists() else 0
    log = pathlib.Path(__file__).with_name("commit-gate.log")
    if mode == "observe" or blocks >= 2:
        with log.open("a") as f:
            f.write(f"{'observe' if mode == 'observe' else 'passed-after-2-blocks'}\t{data.get('session_id','')}\t{command[:200]!r}\n")
        if blocks >= 2:
            state.write_text("0")
        return 0
    state.write_text(str(blocks + 1))
    print("Madar commit gate: add a `Verified:` line to the commit message saying what actually ran "
          "(build, test classes with executed counts, smoke run), or `Verified: docs only — …` / "
          "`Verified: none — <reason>`. Run the `verify` skill first (.claude/skills/verify/SKILL.md).", file=sys.stderr)
    return 2

if __name__ == "__main__":
    sys.exit(main())
