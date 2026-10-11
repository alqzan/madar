#!/usr/bin/env python3
"""RU1 source check for literal digits and known numeric interpolation."""
import re
from pathlib import Path

root = Path(__file__).resolve().parents[1]
literal = re.compile(r"[0-9٠-٩۰-۹][\s\u2066-\u2069]*·|·[\s\u2066-\u2069]*[0-9٠-٩۰-۹]")
numeric = re.compile(r"\\\((?:arabicNumber|digits)\(")
failures = []
for path in sorted((root / "App").rglob("*.swift")):
    for number, line in enumerate(path.read_text().splitlines(), 1):
        if literal.search(line) or ("·" in line and numeric.search(line)):
            failures.append(f"{path.relative_to(root)}:{number}: numeric middle dot")
if failures:
    raise SystemExit("\n".join(failures))
print("PASS: RU1 app numeric separator source check")
