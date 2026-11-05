#!/usr/bin/env python3
"""
xcstrings_tool.py — Programmatic operations on .xcstrings (String Catalog) files.

Use when .xcstrings files are too large for direct AI editing.

Commands:
    validate       Check for missing translations, stale entries, empty values
    add-key        Add a new localization key with comment and default value
    audit-plurals  Check plural category completeness for a specific language
    status         Export translation status report
    fix-plurals    Add missing plural categories with placeholder values

Usage:
    python3 xcstrings_tool.py validate path/to/Localizable.xcstrings
    python3 xcstrings_tool.py add-key path/to/file.xcstrings --key "greeting" --comment "..." --value "Hello!"
    python3 xcstrings_tool.py audit-plurals path/to/file.xcstrings --lang ru
    python3 xcstrings_tool.py status path/to/file.xcstrings
    python3 xcstrings_tool.py fix-plurals path/to/file.xcstrings --lang ru
"""

import json
import sys
import argparse
from pathlib import Path
from typing import Any

# CLDR plural categories required per language
CLDR_PLURAL_CATEGORIES = {
    # 2 categories
    "en": ["one", "other"],
    "es": ["one", "other"],
    "pt": ["one", "other"],
    "pt-BR": ["one", "other"],
    "it": ["one", "other"],
    "fr": ["one", "other"],
    "de": ["one", "other"],
    "nl": ["one", "other"],
    "hi": ["one", "other"],
    "bn": ["one", "other"],
    # 4 categories (Slavic)
    "ru": ["one", "few", "many", "other"],
    "uk": ["one", "few", "many", "other"],
    "pl": ["one", "few", "many", "other"],
    "cs": ["one", "few", "many", "other"],
    "sk": ["one", "few", "many", "other"],
    "hr": ["one", "few", "many", "other"],
    # 6 categories
    "ar": ["zero", "one", "two", "few", "many", "other"],
    # 1 category
    "ja": ["other"],
    "zh": ["other"],
    "zh-Hans": ["other"],
    "zh-Hant": ["other"],
    "ko": ["other"],
    "tr": ["other"],
    "th": ["other"],
    "vi": ["other"],
    "id": ["other"],
    "ms": ["other"],
}


def load_xcstrings(path: str) -> dict:
    """Load and parse an .xcstrings file."""
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def save_xcstrings(path: str, data: dict) -> None:
    """Save data back to .xcstrings file with consistent formatting."""
    with open(path, "w", encoding="utf-8") as f:
        json.dump(data, f, ensure_ascii=False, indent=2, sort_keys=False)
        f.write("\n")


def get_required_categories(lang: str) -> list[str]:
    """Get CLDR-required plural categories for a language."""
    # Try exact match, then base language
    if lang in CLDR_PLURAL_CATEGORIES:
        return CLDR_PLURAL_CATEGORIES[lang]
    base = lang.split("-")[0]
    if base in CLDR_PLURAL_CATEGORIES:
        return CLDR_PLURAL_CATEGORIES[base]
    return ["one", "other"]  # Default fallback


def cmd_validate(data: dict, source_lang: str) -> list[dict]:
    """Validate .xcstrings for common issues."""
    issues = []
    strings = data.get("strings", {})

    for key, entry in strings.items():
        state = entry.get("extractionState", "")
        localizations = entry.get("localizations", {})

        # Check for stale entries
        if state == "stale":
            issues.append({
                "severity": "warning",
                "key": key,
                "issue": "Stale entry — key no longer found in source code"
            })

        # Check for missing translations
        for lang, loc_data in localizations.items():
            if lang == source_lang:
                continue

            if "stringUnit" in loc_data:
                unit = loc_data["stringUnit"]
                if unit.get("state") == "new":
                    issues.append({
                        "severity": "error",
                        "key": key,
                        "lang": lang,
                        "issue": f"Missing translation (state=new)"
                    })
                elif not unit.get("value", "").strip():
                    issues.append({
                        "severity": "error",
                        "key": key,
                        "lang": lang,
                        "issue": "Empty translation value"
                    })

            # Check plural completeness
            if "variations" in loc_data and "plural" in loc_data["variations"]:
                plural = loc_data["variations"]["plural"]
                required = get_required_categories(lang)
                missing = [cat for cat in required if cat not in plural]
                if missing:
                    issues.append({
                        "severity": "critical",
                        "key": key,
                        "lang": lang,
                        "issue": f"Missing plural categories: {', '.join(missing)}"
                    })

        # Check for missing comment
        if not entry.get("comment", "").strip():
            issues.append({
                "severity": "info",
                "key": key,
                "issue": "Missing translator comment"
            })

    return issues


def cmd_add_key(data: dict, key: str, comment: str, value: str, source_lang: str) -> dict:
    """Add a new key to the String Catalog."""
    if "strings" not in data:
        data["strings"] = {}

    if key in data["strings"]:
        print(f"Warning: Key '{key}' already exists. Updating.")

    entry: dict[str, Any] = {
        "extractionState": "manual",
    }
    if comment:
        entry["comment"] = comment
    if value:
        entry["localizations"] = {
            source_lang: {
                "stringUnit": {
                    "state": "translated",
                    "value": value
                }
            }
        }

    data["strings"][key] = entry
    return data


def cmd_audit_plurals(data: dict, lang: str) -> list[dict]:
    """Audit plural category completeness for a specific language."""
    required = get_required_categories(lang)
    issues = []
    strings = data.get("strings", {})

    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        if lang not in localizations:
            continue

        loc = localizations[lang]
        if "variations" not in loc or "plural" not in loc.get("variations", {}):
            continue

        plural = loc["variations"]["plural"]
        present = list(plural.keys())
        missing = [cat for cat in required if cat not in present]
        extra = [cat for cat in present if cat not in required]

        if missing:
            issues.append({
                "key": key,
                "lang": lang,
                "required": required,
                "present": present,
                "missing": missing,
                "severity": "critical"
            })

        if extra:
            issues.append({
                "key": key,
                "lang": lang,
                "extra": extra,
                "severity": "info",
                "note": "Extra categories are harmless but unnecessary"
            })

    return issues


def cmd_status(data: dict) -> dict:
    """Generate translation status report."""
    strings = data.get("strings", {})
    source_lang = data.get("sourceLanguage", "en")

    # Collect all languages
    languages = set()
    for entry in strings.values():
        for lang in entry.get("localizations", {}):
            languages.add(lang)

    report = {
        "source_language": source_lang,
        "total_keys": len(strings),
        "languages": {},
        "stale_keys": [],
    }

    for lang in sorted(languages):
        if lang == source_lang:
            continue
        translated = 0
        needs_review = 0
        new = 0
        for key, entry in strings.items():
            loc = entry.get("localizations", {}).get(lang, {})
            if "stringUnit" in loc:
                state = loc["stringUnit"].get("state", "new")
                if state == "translated":
                    translated += 1
                elif state == "needs_review":
                    needs_review += 1
                else:
                    new += 1
            elif "variations" in loc:
                translated += 1  # Has variations = some work done
            else:
                new += 1

        total = translated + needs_review + new
        report["languages"][lang] = {
            "translated": translated,
            "needs_review": needs_review,
            "new": new,
            "total": total,
            "progress": f"{translated / total * 100:.1f}%" if total > 0 else "0%"
        }

    for key, entry in strings.items():
        if entry.get("extractionState") == "stale":
            report["stale_keys"].append(key)

    return report


def cmd_fix_plurals(data: dict, lang: str) -> tuple[dict, list[str]]:
    """Add missing plural categories with TODO placeholder values."""
    required = get_required_categories(lang)
    fixed = []
    strings = data.get("strings", {})

    for key, entry in strings.items():
        localizations = entry.get("localizations", {})
        if lang not in localizations:
            continue

        loc = localizations[lang]
        if "variations" not in loc or "plural" not in loc.get("variations", {}):
            continue

        plural = loc["variations"]["plural"]
        for cat in required:
            if cat not in plural:
                # Use the 'other' form as a placeholder if available
                placeholder = "TODO: translate"
                if "other" in plural and "stringUnit" in plural["other"]:
                    placeholder = f"TODO: {plural['other']['stringUnit'].get('value', 'translate')}"

                plural[cat] = {
                    "stringUnit": {
                        "state": "needs_review",
                        "value": placeholder
                    }
                }
                fixed.append(f"{key} [{lang}]: added '{cat}' category")

    return data, fixed


def main():
    parser = argparse.ArgumentParser(description="xcstrings manipulation tool")
    subparsers = parser.add_subparsers(dest="command", help="Command to run")

    # validate
    p_validate = subparsers.add_parser("validate", help="Validate .xcstrings file")
    p_validate.add_argument("file", help="Path to .xcstrings file")

    # add-key
    p_add = subparsers.add_parser("add-key", help="Add a new key")
    p_add.add_argument("file", help="Path to .xcstrings file")
    p_add.add_argument("--key", required=True, help="Localization key")
    p_add.add_argument("--comment", default="", help="Translator comment")
    p_add.add_argument("--value", default="", help="Default value in source language")

    # audit-plurals
    p_audit = subparsers.add_parser("audit-plurals", help="Audit plural completeness")
    p_audit.add_argument("file", help="Path to .xcstrings file")
    p_audit.add_argument("--lang", required=True, help="Language code (e.g., ru, pl, ar)")

    # status
    p_status = subparsers.add_parser("status", help="Translation status report")
    p_status.add_argument("file", help="Path to .xcstrings file")

    # fix-plurals
    p_fix = subparsers.add_parser("fix-plurals", help="Add missing plural categories")
    p_fix.add_argument("file", help="Path to .xcstrings file")
    p_fix.add_argument("--lang", required=True, help="Language code (e.g., ru, pl, ar)")

    args = parser.parse_args()

    if not args.command:
        parser.print_help()
        sys.exit(1)

    # Load file
    file_path = args.file
    if not Path(file_path).exists():
        print(f"Error: File not found: {file_path}")
        sys.exit(1)

    data = load_xcstrings(file_path)
    source_lang = data.get("sourceLanguage", "en")

    if args.command == "validate":
        issues = cmd_validate(data, source_lang)
        if not issues:
            print("✅ No issues found.")
        else:
            for issue in sorted(issues, key=lambda x: {"critical": 0, "error": 1, "warning": 2, "info": 3}[x["severity"]]):
                severity = issue["severity"].upper()
                key = issue["key"]
                lang = issue.get("lang", "")
                msg = issue["issue"]
                lang_str = f" [{lang}]" if lang else ""
                print(f"[{severity}] {key}{lang_str}: {msg}")
            print(f"\nTotal: {len(issues)} issues")

    elif args.command == "add-key":
        data = cmd_add_key(data, args.key, args.comment, args.value, source_lang)
        save_xcstrings(file_path, data)
        print(f"✅ Added key '{args.key}' to {file_path}")

    elif args.command == "audit-plurals":
        issues = cmd_audit_plurals(data, args.lang)
        required = get_required_categories(args.lang)
        print(f"Language: {args.lang}")
        print(f"Required categories: {', '.join(required)}")
        print()
        if not issues:
            print("✅ All plural categories complete.")
        else:
            for issue in issues:
                key = issue["key"]
                if "missing" in issue:
                    print(f"❌ {key}: missing {', '.join(issue['missing'])}")
                if "extra" in issue:
                    print(f"ℹ️  {key}: extra {', '.join(issue['extra'])} (harmless)")
            critical = [i for i in issues if i["severity"] == "critical"]
            print(f"\n{len(critical)} keys with missing categories")

    elif args.command == "status":
        report = cmd_status(data)
        print(f"Source: {report['source_language']}")
        print(f"Total keys: {report['total_keys']}")
        print(f"Stale keys: {len(report['stale_keys'])}")
        print()
        for lang, stats in report["languages"].items():
            print(f"  {lang}: {stats['progress']} ({stats['translated']}/{stats['total']} translated, "
                  f"{stats['needs_review']} needs review, {stats['new']} new)")

    elif args.command == "fix-plurals":
        data, fixed = cmd_fix_plurals(data, args.lang)
        if fixed:
            save_xcstrings(file_path, data)
            print(f"✅ Fixed {len(fixed)} missing plural categories:")
            for f in fixed:
                print(f"  + {f}")
        else:
            print("✅ No missing plural categories found.")


if __name__ == "__main__":
    main()
