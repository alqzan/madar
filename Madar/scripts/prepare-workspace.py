#!/usr/bin/env python3
"""Validate private local font resources; --source copies only missing verified files."""
import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import shutil
import sys


class PreparationError(ValueError):
    pass


def expected_resources(root):
    app = root / 'Madar/App'
    metadata = json.loads((root / 'Madar/docs/font-provenance.json').read_text())
    with (app / 'Info.plist').open('rb') as handle:
        registered = plistlib.load(handle)['UIAppFonts']
    expected = {}
    fonts = set()
    for font in metadata['fonts']:
        fonts.add(font['file'])
        entries = [(font['file'], font['sha256'])]
        if 'licenseFile' in font:
            entries.append((font['licenseFile'], font['licenseSha256']))
        for name, digest in entries:
            if Path(name).name != name or name in ('.', '..') or '\\' in name:
                raise PreparationError(f'Unsafe resource name: {name!r}')
            if len(digest) != 64 or any(c not in '0123456789abcdef' for c in digest):
                raise PreparationError(f'Invalid SHA-256: {name}')
            if name in expected and expected[name] != digest:
                raise PreparationError(f'Conflicting provenance: {name}')
            expected[name] = digest
    if len(registered) != len(set(registered)) or set(registered) != fonts:
        raise PreparationError('UIAppFonts and font provenance disagree')
    return expected


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def prepare(root, source=None):
    root = root.resolve()
    expected = expected_resources(root)
    destination = root / 'Madar/App/Resources/Fonts'
    missing = []
    errors = []
    for name, sha in expected.items():
        target = destination / name
        if not target.exists():
            missing.append(name)
        elif not target.is_file() or target.is_symlink() or digest(target) != sha:
            errors.append(f'Conflicting local resource (preserved): {name}')
    # Check everything before writing anything, including source files.
    source_dir = source.resolve() / 'Madar/App/Resources/Fonts' if source else None
    if missing and source_dir is None:
        errors.extend(f'Missing resource: {name}' for name in missing)
    elif source_dir:
        for name in missing:
            origin = source_dir / name
            if not origin.is_file() or origin.is_symlink() or digest(origin) != expected[name]:
                errors.append(f'Missing or mismatched source resource: {name}')
    if errors:
        raise PreparationError('\n'.join(errors))
    if missing:
        destination.mkdir(parents=True, exist_ok=True)
    for name in missing:
        target = destination / name
        # Exclusive creation avoids overwriting a file created after validation.
        with (source_dir / name).open('rb') as origin, target.open('xb') as output:
            shutil.copyfileobj(origin, output)
        if digest(target) != expected[name]:
            raise PreparationError(f'Copy verification failed: {name}; do not build')
    return len(expected), len(missing)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--root', type=Path, default=Path(__file__).resolve().parents[2],
                        help='Repository to check/prepare (default: this script checkout)')
    parser.add_argument('--source', type=Path,
                        help='Explicit local repository supplying missing fonts; no downloads')
    args = parser.parse_args()
    try:
        count, copied = prepare(args.root, args.source)
    except (PreparationError, OSError, KeyError, TypeError, json.JSONDecodeError,
            plistlib.InvalidFileException) as error:
        print(f'FONT PREFLIGHT FAILED:\n{error}', file=sys.stderr)
        return 1
    print(f'FONT PREFLIGHT PASS: {count} font/license resources match provenance; {copied} copied')
    print('This checks fonts only; build, signing and runtime acceptance remain separate.')
    return 0


if __name__ == '__main__':
    sys.exit(main())
