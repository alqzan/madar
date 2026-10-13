#!/usr/bin/env python3
"""Side-by-side and overlay comparison of actual app screenshots with canonical handoff screens.

Usage (from the repository root):
  python3 Madar/scripts/compare-screens.py --list salah
  python3 Madar/scripts/compare-screens.py S1-Home actual-top.png [actual-scrolled.png ...]

The n-th actual screenshot is paired with the n-th canonical file of the board (unscrolled first).
Writes one self-contained page, Madar/Artifacts/compare/<board>.html (ignored by Git), with the images embedded.
Both images are drawn at the same width in points (393), so spacing and type size compare directly.
"""
import base64
import html
import json
import sys
from pathlib import Path

repo = Path(__file__).resolve().parents[2]
index = json.loads((repo / 'docs/HANDOFF/screens-index.json').read_text())['screens']

if len(sys.argv) >= 2 and sys.argv[1] == '--list':
    room = sys.argv[2] if len(sys.argv) > 2 else None
    for screen in index:
        if room is None or screen['room'] == room:
            print(f"{screen['room']:10} {screen['board']:14} {screen['kind']:9} {screen['status']:10} {screen['mode']:5} {screen['file']}")
    sys.exit(0)
if len(sys.argv) < 3:
    sys.exit(__doc__)

board, actuals = sys.argv[1], [Path(a).resolve() for a in sys.argv[2:]]
canonical = sorted((s for s in index if s['board'] == board), key=lambda s: s['scrolled'])
if not canonical:
    sys.exit(f'Unknown board {board!r}; run with --list <room>.')
if any(s['status'] != 'canonical' for s in canonical):
    print(f'warning: {board} is {canonical[0]["status"]}; superseded and deferred screens are not built.')
for actual in actuals:
    if not actual.is_file():
        sys.exit(f'Missing screenshot: {actual}')

out = repo / 'Madar/Artifacts/compare'
out.mkdir(parents=True, exist_ok=True)
def embed(path):
    kind = 'jpeg' if path.suffix.lower() in ('.jpg', '.jpeg') else 'png'
    return f'data:image/{kind};base64,' + base64.b64encode(path.read_bytes()).decode()


rows = []
for i in range(max(len(canonical), len(actuals))):
    ref = canonical[i] if i < len(canonical) else None
    ref_src = embed(repo / 'docs/HANDOFF' / ref['file']) if ref else None
    act_src = embed(actuals[i]) if i < len(actuals) else None
    label = html.escape(ref['title'] + (' · بعد التمرير' if ref and ref['scrolled'] else '')) if ref else 'لقطة إضافية'
    ref_img = f'<img src="{ref_src}" alt="المعتمد">' if ref else '<div class="none">لا توجد شاشة معتمدة</div>'
    act_img = f'<img src="{act_src}" alt="الفعلي">' if act_src else '<div class="none">لم تُلتقط</div>'
    overlay = f'<div class="stack">{ref_img}<img class="top" src="{act_src}" alt=""></div>' if ref and act_src else ''
    rows.append(f'<section><h2>{label}</h2><div class="pair"><figure>{ref_img}<figcaption>المعتمد</figcaption></figure>'
                f'<figure>{act_img}<figcaption>الفعلي</figcaption></figure>'
                + (f'<figure>{overlay}<figcaption>تراكب</figcaption></figure>' if overlay else '') + '</div></section>')

page = f'''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1">
<title>مقارنة {html.escape(board)}</title>
<style>body{{margin:0;padding:24px;background:#eee8dd;color:#1d1913;font:16px system-ui,sans-serif}}
.bar{{position:sticky;top:0;background:#fffdf8;padding:12px 16px;border-radius:14px;margin-bottom:20px;display:flex;gap:16px;align-items:center;z-index:2}}
.pair{{display:flex;gap:20px;flex-wrap:wrap}}figure{{margin:0;width:393px}}img{{display:block;width:393px;border-radius:18px;box-shadow:0 4px 18px #0002}}
figcaption{{text-align:center;padding:8px;color:#6b6356}}.stack{{position:relative;width:393px}}.stack img{{position:absolute;inset:0 auto auto 0}}
.stack img:first-child{{position:relative}}.top{{opacity:.5}}.none{{width:393px;height:200px;display:grid;place-items:center;background:#fff8;border-radius:18px}}</style>
<div class="bar"><b>{html.escape(board)}</b><label>شفافية الفعلي في التراكب <input id="o" type="range" min="0" max="100" value="50"></label>
<span>القرار للمالك: «مطابق — بانتظار المالك» ليس اعتمادًا.</span></div>
{''.join(rows)}
<script>document.getElementById('o').oninput=e=>document.querySelectorAll('.top').forEach(i=>i.style.opacity=e.target.value/100)</script></html>'''
target = out / f'{board}.html'
target.write_text(page)
print(f'{len(canonical)} canonical, {len(actuals)} actual → {target.relative_to(repo)}')
