#!/usr/bin/env python3
"""Extract artwork strips, without embedding the source page or its text.

Requires PyMuPDF. Input: the 624-page old Madinah scan, with the 1405 committee
seal on PDF page 620; source URL and source hash are in QuranResourceManifest.json.
"""
import base64
import sys
from pathlib import Path

import fitz

source = fitz.open(sys.argv[1])
if len(source) != 624:
    raise ValueError('Unexpected edition scan')
output = Path(sys.argv[2])
output.mkdir(parents=True, exist_ok=True)
page = source[606]  # printed page 604, PDF page 607
for name, outer, inner in [
    ('surah-opening', (150, 131, 691, 197), (303, 137, 550, 189)),
]:
    x0, y0, x1, y1 = outer
    a, b, c, d = inner
    images = []
    for box in [(x0, y0, x1, b), (x0, d, x1, y1), (x0, b, a, d), (c, b, x1, d)]:
        rect = fitz.Rect(box)
        pixmap = page.get_pixmap(matrix=fitz.Matrix(2, 2), clip=rect, alpha=False)
        data = base64.b64encode(pixmap.tobytes('png')).decode()
        images.append(f'<image x="{rect.x0-x0}" y="{rect.y0-y0}" width="{rect.width}" '
                      f'height="{rect.height}" href="data:image/png;base64,{data}"/>')
    svg = (f'<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 {x1-x0} {y1-y0}">'
           '<title>1405 ornamental asset; no Quran text</title>' + ''.join(images) + '</svg>\n')
    (output / f'{name}.svg').write_text(svg)
    print(f'Extracted {name}: four artwork strips, transparent text area')
