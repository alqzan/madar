#!/usr/bin/env python3
"""Use Madar's shared pre-commit verification check in Codex."""

from pathlib import Path
from runpy import run_path

run_path(str(Path(__file__).resolve().parents[2] / '.claude/hooks/commit-gate.py'), run_name='__main__')
