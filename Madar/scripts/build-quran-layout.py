#!/usr/bin/env python3
"""Bind the pinned page/word layout to the unchanged KFGQPC ayah text.

Usage: build-quran-layout.py <hafsData.json> <pinned-page-directory> <output.json>
The input page snapshot is mutqin-resources 0cd14756e44d52d012e00fb15b128979c5c0b213.
Quran.com word responses independently confirm the seven compound-word groupings.
Quran.com juz/hizb metadata is deliberately not used: its juz 4 starts at 3:93,
while the owner's KFGQPC data starts at 3:92.
"""
import json
import re
import sys
from collections import defaultdict
from pathlib import Path


def utf16(text, end):
    return len(text[:end].encode('utf-16-le')) // 2


def ranges(record):
    text = record['aya_text']
    end = len(text.rstrip())
    if 0xFC00 <= ord(text[end - 1]) <= 0xFD1D:
        end -= 1  # the font encodes ayah numbers 1...286 in this range
    parts = [(m.start(), m.end()) for m in re.finditer(r'\S+', text[:end])
             if m.group() != '۞']
    key = (record['sura_no'], record['aya_no'])
    # These ranges retain the source spelling; they change only visual grouping.
    joins = {(2, 181): (2, 'بَعۡدَ مَا'), (8, 6): (3, 'بَعۡدَ مَا'),
             (13, 37): (7, 'بَعۡدَ مَا'), (37, 130): (2, 'إِلۡ يَاسِينَ')}
    splits = {(15, 7): (0, 'لَّوۡمَا', 5), (27, 20): (3, 'مَالِيَ', 3),
              (36, 22): (0, 'وَمَالِيَ', 5)}
    if key in joins:
        i, spelling = joins[key]
        start, stop = parts[i][0], parts[i + 1][1]
        if text[start:stop] != spelling:
            raise ValueError(f'Changed compound spelling at {key}')
        parts[i:i + 2] = [(start, stop)]
    if key in splits:
        i, spelling, offset = splits[key]
        start, stop = parts[i]
        if text[start:stop] != spelling:
            raise ValueError(f'Changed split spelling at {key}')
        parts[i:i + 1] = [(start, start + offset), (start + offset, stop)]
    return [(utf16(text, a), utf16(text, b)) for a, b in parts]


def main():
    ayahs = json.loads(Path(sys.argv[1]).read_text())
    page_dir, output = Path(sys.argv[2]), Path(sys.argv[3])
    by_key = {(a['sura_no'], a['aya_no']): a for a in ayahs}
    groups = defaultdict(list)
    pages = []
    for page in range(1, 605):
        raw = json.loads((page_dir / f'{page}.json').read_text())
        if raw['p'] != page:
            raise ValueError(f'Wrong page identity {page}')
        # The first two source font grids bottom-align their opening text.
        # The official KFGQPC logical line numbers include title/basmala instead.
        shift = 7 if page <= 2 else 0
        lines = [{'number': n, 'kind': 'empty', 'words': [], 'ayahEnds': []}
                 for n in range(1, 9 if page <= 2 else 16)]
        pages.append({'page': page, 'lines': lines})
        for raw_line in raw['lines']:
            number = raw_line['l'] - shift
            if not 1 <= number <= len(lines):
                raise ValueError(f'Invalid line at page {page}')
            line = lines[number - 1]
            line['kind'] = 'ayah'
            for glyph, surah, ayah in raw_line['w']:
                if not glyph:
                    raise ValueError(f'Empty glyph at {surah}:{ayah}')
                groups[(surah, ayah)].append((page, number, line))

    words = 0
    for key, record in by_key.items():
        entries = groups[key]
        spans = ranges(record)
        if len(entries) != len(spans) + 1:
            raise ValueError(f'Word count mismatch {key}: {len(entries)-1}/{len(spans)}')
        if (entries[0][0], entries[0][1], entries[-1][1]) != (
                record['page'], record['line_start'], record['line_end']):
            raise ValueError(f'Official page/line boundary mismatch at {key}')
        if any(p != record['page'] for p, _, _ in entries):
            raise ValueError(f'Ayah spans pages at {key}')
        for index, ((lower, upper), (_, _, line)) in enumerate(zip(spans, entries)):
            line['words'].append({'ayahID': record['id'], 'wordIndex': index,
                                  'lowerUTF16': lower, 'upperUTF16': upper})
            words += 1
        entries[-1][2]['ayahEnds'].append(record['id'])
        if record['aya_no'] == 1:
            first = record['line_start']
            has_basmala = record['sura_no'] not in (1, 9)
            title = first - (2 if has_basmala else 1)
            lines = pages[record['page'] - 1]['lines']
            for number, kind in [(title, 'surah')] + ([(title + 1, 'basmala')] if has_basmala else []):
                line = lines[number - 1]
                if line['kind'] != 'empty':
                    raise ValueError(f'Header overlaps ayah at {key}')
                line.update(kind=kind, surahID=record['sura_no'])
    if len(groups) != 6236 or words != 77429:
        raise ValueError('Incomplete pinned word map')
    for page in pages:
        for line in page['lines']:
            if line['kind'] == 'empty':
                raise ValueError(f'Unclassified line on page {page["page"]}')
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps({'version': 1, 'edition': 1439, 'pages': pages},
                                 ensure_ascii=False, separators=(',', ':')) + '\n')
    print(f'PASS: 604 pages, 6236 official ayah boundaries, {words} placed words')


if __name__ == '__main__':
    main()
