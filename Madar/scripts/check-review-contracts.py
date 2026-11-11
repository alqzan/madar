#!/usr/bin/env python3
"""Read-only checks for the amended M0 contracts; not a product/device gate."""
import argparse
import hashlib
import json
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
parser = argparse.ArgumentParser()
parser.add_argument('--require-ra4', action='store_true')
args = parser.parse_args()
checks = 0


def require(condition, message):
    global checks
    if not condition:
        raise SystemExit(f'FAIL: {message}')
    checks += 1


require((ROOT / 'AGENTS.md').read_bytes() == (ROOT / 'CLAUDE.md').read_bytes(), 'root protocols differ')
require((ROOT / 'Madar/AGENTS.md').read_bytes() == (ROOT / 'Madar/CLAUDE.md').read_bytes(), 'app protocols differ')
handoff = ROOT / 'docs/HANDOFF'
index = json.loads((handoff / 'sections/index.json').read_text())
require(len(index) == 25, 'RA9 needs 25 extracts')
for entry in index:
    require(hashlib.sha256((handoff / entry['path']).read_bytes()).hexdigest() == entry['sha256'],
            f"frozen extract changed: {entry['path']}")

copies = [handoff, ROOT / 'Madar/Specification', ROOT / 'Madar/Packages/MadarData/Sources/MadarData/Resources']
require(len({(base / 'settings-schema.json').read_bytes() for base in copies}) == 1, 'settings copies drifted')
require((copies[1] / 'data-dictionary.json').read_bytes() == (copies[2] / 'data-dictionary.json').read_bytes(),
        'runtime dictionary copies drifted')
settings = {row['key']: row for row in json.loads((handoff / 'settings-schema.json').read_text())['settings']}
for key in ['notes.dictationFirst', 'salah.liveActivity', 'quran.tapForTafsir']:
    require(settings[key]['default'] is False, f'{key} agreed default must be false')
# Owner, 4 Nov 2026: the heart question starts off again (docs/DECISIONS.md); 26 Oct had set it on.
require(settings['salah.askHeart']['default'] is False, 'salah.askHeart owner default must be false (owner, 4 Nov 2026)')
require(settings['quran.tapForTafsir']['availabilityGate'] == 'M2 licence check', 'RQ8 licence gate missing')
# Owner, 6 Nov (FB-39b): smart presence starts at medium.
require(settings['bahw.smartPresence']['availability'] == 'v1' and settings['bahw.smartPresence']['default'] == 'medium', 'owner smart-presence contract changed')
require(settings['bahw.widgetScope']['availability'] == 'v1' and settings['bahw.widgetScope']['default'] == 'todayAndAfter', 'owner habit widget scope contract changed')
reader = settings['mihbara.readerEn']
require(reader['default']['arabicHints'] == 'none', 'RMI1 hints must default off')
require(reader['contract']['fieldAvailability']['arabicHints'] == 'v2', 'RMI1 hints must stay v2')
cut_keys = ['tabbar.style', 'tabbar.labels', 'tabbar.openOn', 'tabbar.minimizeOnScroll',
            'bahw.habitsView', 'bahw.yearView', 'bahw.upcomingView',
            'bahw.iphoneWidgetFamily', 'bahw.widgetIdentity',
            'core.fontScale', 'core.motion', 'core.roomIdentity', 'salah.balanceView',
            'quran.toolsOrder', 'notif.roomPriority', 'notes.echoDistances', 'mihbara.shape',
            'mihbara.sunnahPlace', 'mihbara.pageStyle', 'mihbara.motivateStyle', 'mihbara.notebookStyle']
for key in cut_keys:
    require(settings[key]['availability'] == 'v2', f'RA8 cut key visible: {key}')
require('مجدولًا' not in settings['salah.liveActivity']['note'], 'RL5 scheduled silent start remains promised')
html = (handoff / 'MADAR_HANDOFF.html').read_text()
require('اختبارات §١١ الثمانية' in html and 'اختبارات §١١ السبعة' not in html, 'RA5 count not amended')

journeys = ROOT / 'docs/journeys'
all_steps = '\n'.join(p.read_text() for p in journeys.glob('*.md') if p.name != 'README.md')
for number in range(1, 19):
    require(re.search(rf'\| J{number:02d} / test_\w+', all_steps), f'J{number:02d} lacks a procedure')
for required in ['Current work', 'Board', 'Later', 'Handovers']:
    require(f'# {required}' in (ROOT / 'docs/PROGRESS.md').read_text(), f'progress heading missing: {required}')
require((ROOT / 'docs/OWNER-RUNBOOK.md').exists(), 'RA6 runbook missing')
if args.require_ra4:
    dictionary = json.loads((ROOT / 'Madar/Specification/data-dictionary.json').read_text())
    names = {row['name'] for row in dictionary['models']}
    require('MoneyTransaction' in names and 'Transaction' not in names, 'RA4 model rename missing')
    require('@Model Transaction ' not in html and '@Model MoneyTransaction ' in html, 'RA4 working HTML model not amended')
print(f'PASS: {checks} amended contract checks (read-only; device acceptance not tested)')
