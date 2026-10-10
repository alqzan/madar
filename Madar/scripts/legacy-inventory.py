#!/usr/bin/env python3
"""Inventory pinned source fields; no reads or writes of the owner's records."""
import hashlib
import json
import re
import subprocess
from pathlib import Path

root = Path(__file__).resolve().parents[1]
reference = root.parent / 'output/madar-audit-2026-10-09/reference/My-dream'
pin = 'aba0c1b18a3bf3fc070395a40595e939c3b73aa3'
sha = subprocess.check_output(['git', '-C', str(reference), 'rev-parse', 'HEAD'], text=True).strip()
if sha != pin:
    raise SystemExit('Legacy reference pin mismatch')
source = reference / 'src/lib/types.ts'
text = source.read_text()
# Strip comments before scanning braces (inline object types remain fields).
clean = re.sub(r'/\*.*?\*/|//[^\n]*', '', text, flags=re.S)
interfaces = []
for match in re.finditer(r'export interface (\w+)(?:[^\{]*)\{', clean):
    depth = 1
    end = match.end()
    while depth and end < len(clean):
        depth += (clean[end] == '{') - (clean[end] == '}')
        end += 1
    body = clean[match.end():end-1]
    fields = []
    depth = 0
    start = 0
    for i, char in enumerate(body):
        depth += (char in '{[(') - (char in '}])')
        if char == ';' and depth == 0:
            part = body[start:i].strip()
            start = i+1
            field = re.match(r'(\w+)(\?)?\s*:\s*(.*)', part, flags=re.S)
            if not field:
                continue
            name, optional, typ = field.groups()
            fields.append({'field': name, 'optional': bool(optional), 'type': ' '.join(typ.split()),
                           'disposition': 'preserveRawUntilRoomMigration',
                           'target': 'Media(kind=doc): original export archive',
                           'validation': 'Before room import: explicit mapping, preview and counts; never silently discard unknown data.'})
    interfaces.append({'interface': match.group(1), 'fields': fields})
rules = {
    'JournalEntry': {'id': ('ImportLink.sourceID', 'deterministic UUIDv5; keep original ID'),
                     'date': ('Entry.dayKey', 'copy verbatim; dayPolicy legacy@0'),
                     'content': ('Entry.text', 'preserve text exactly; textFormat from source'),
                     'updatedAt': ('Entry.updatedAt', 'milliseconds to absolute Date; preserve missing'),
                     'photo': ('Media', 'decode legacy bytes once; SHA256; dedupe with photos'),
                     'photos': ('Media', 'decode originals; SHA256; never replace with preview'),
                     'audio': ('Media', 'decode bytes once; retain MIME'),
                     'audios': ('Media', 'preserve every file; dedupe legacy first audio'),
                     'photoRefs': ('Media', 'content hash reference; missing remains explicit'),
                     'audioRefs': ('Media', 'content hash reference; missing remains explicit'),
                     'videoRefs': ('Media', 'metadata-only when source has no file; never fabricate video'),
                     'attachments': ('Media', 'preserve filename/contentType/sourceMediaID; validate bytes separately')},
    'PrayerLog': {'date': ('PrayerLog.dayKey', 'preserve prayer civil date; prayerDay@1'),
                  'prayer': ('PrayerLog.prayer', 'explicit Arabic to fajr/dhuhr/asr/maghrib/isha'),
                  'status': ('PrayerLog.status', 'map documented statuses; unknown quarantined')},
    'Transaction': {'amount': ('Transaction.amountMinor', 'Decimal conversion using currency exponent; no binary floating rounding'),
                    'date': ('Transaction.dayKey', 'copy civil key legacy@0; preserve timestamp separately')},
    'AppData': {'deleted': ('deletionBarrierAt', 'preserve every source tombstone keyed via ImportLink'),
                'deletedMedia': ('Media.deletionBarrierAt', 'retain removal barriers by content hash'),
                'fieldUpdatedAt': ('Setting.updatedAt', 'preserve explicit clears; default is not a stored edit')}
}
for model in interfaces:
    for field in model['fields']:
        mapped = rules.get(model['interface'], {}).get(field['field'])
        if mapped:
            field.update(disposition='mappedAndRawPreserved', target=mapped[0], validation=mapped[1])
report = {'version': 1, 'legacyCommit': pin, 'source': 'src/lib/types.ts',
          'sourceSHA256': hashlib.sha256(source.read_bytes()).hexdigest(),
          'boundary': 'Static source inventory only. Not a completed importer or an assertion that user data has migrated.',
          'gate': 'Every raw archive entry retained; each room replaces pending maps with verified conversions before its import.',
          'checksRequired': ['source and target row counts by model', 'money sums per currency minor unit',
                             'exact original dates and zones', 'media bytes count and hashes',
                             'repeat batch no row growth', 'unknown field raw archive retained'],
          'interfaces': interfaces}
output = root / 'Specification/legacy-mapping.json'
output.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
print(f'{len(interfaces)} interfaces, {sum(len(m["fields"]) for m in interfaces)} fields inventoried; no user data accessed.')
