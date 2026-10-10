#!/usr/bin/env python3
"""Build an offline gallery from actual xcresult screenshot attachment metadata."""
import html
import json
import sys
from pathlib import Path

root = Path(__file__).resolve().parents[1]
folder = root / 'Artifacts' / (sys.argv[1] if len(sys.argv) > 1 else 'ui-final')
assert folder.parent == root / 'Artifacts'
manifest = json.loads((folder / 'manifest.json').read_text())
cards = []
for test in manifest:
    for attachment in test['attachments']:
        name = attachment['suggestedHumanReadableName'].split('_0_')[0]
        if not any(name.startswith('M0-' + prefix) for prefix in ('home-', 'settings-', 'components-')):
            continue
        size = name.rsplit('-', 1)[-1]
        mode = 'dark' if '-dark-' in name else 'light'
        kind = 'home' if name.startswith('M0-home-') else 'settings' if name.startswith('M0-settings-') else 'components'
        label = {'home': 'مدار', 'settings': 'خصّص مدار', 'components': 'المكونات المشتركة'}[kind]
        if '-lower-' in name: label += ' · بعد التمرير'
        filename = attachment['exportedFileName']
        assert (folder / filename).is_file(), filename
        card = f'<figure data-mode="{mode}" data-size="{size}" data-kind="{kind}"><a href="{folder.name}/{filename}" target="_blank"><img loading="lazy" src="{folder.name}/{filename}" alt="{html.escape(label)} · {mode} · {size}"></a><figcaption>{label} <span>{mode} · {size}</span></figcaption></figure>'
        cards.append((({'home': 0, 'settings': 1, 'components': 2}[kind], mode, ['L', 'AX3', 'AX5'].index(size), '-lower-' in name), card))
document = '''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8"><meta name="viewport" content="width=device-width,initial-scale=1"><title>مدار 2.0 · المعاينة المحلية</title>
<style>*{box-sizing:border-box}body{margin:0;background:#eee8dd;color:#1d1913;font:18px system-ui,sans-serif}main{max-width:1360px;margin:auto;padding:40px 24px}header{max-width:800px}small{color:#84632b}h1{font-size:clamp(34px,6vw,64px);margin:14px 0}p{line-height:1.8;color:#625d55}.controls{display:flex;flex-wrap:wrap;gap:18px;background:#fffdf8;border-radius:20px;padding:18px;margin:28px 0;position:sticky;top:12px;z-index:1;box-shadow:0 5px 22px #44371a14}label{display:flex;align-items:center;gap:8px}select{font:inherit;border:1px solid #ccc3b1;border-radius:12px;padding:8px;background:#fffdf8;color:inherit}section{display:grid;grid-template-columns:repeat(auto-fit,minmax(240px,1fr));gap:24px}figure{margin:0;max-width:370px;padding:12px;border-radius:30px;background:#fffdf8;box-shadow:0 8px 24px #44371a12}figure[hidden]{display:none}img{display:block;width:100%;border-radius:22px}figcaption{display:flex;justify-content:space-between;gap:8px;padding:16px 6px;font-size:15px}span{direction:ltr;color:#756d5f}a{color:inherit}footer{margin-top:35px;color:#756d5f;font-size:15px}</style>
<main><header><small>مدار 2.0 · أساس M0 · 10 أكتوبر 2026</small><h1>مدار، يبدأ من هنا.</h1><p>صور فعلية من التطبيق الأصلي على محاكي iPhone 17 Pro. اختر المظهر وحجم الخط لمراجعة مدار والتخصيص والمكونات المشتركة. اضغط الصورة لفتحها بالدقة الأصلية.</p><p>هذه معاينة محلية للأساس؛ المزامنة على جهازين والاستعادة إلى مخزن مأهول والتوزيع ما زالت ضمن بوابة M0.</p></header>
<div class="controls"><label>المظهر <select id="mode"><option value="light">فاتح</option><option value="dark">داكن</option><option value="all">كلاهما</option></select></label><label>الخط <select id="size"><option>L</option><option>AX3</option><option>AX5</option><option value="all">كل الأحجام</option></select></label><label>الشاشة <select id="kind"><option value="all">الكل</option><option value="home">مدار</option><option value="settings">التخصيص</option><option value="components">المكونات</option></select></label></div><section>''' + ''.join(card for _, card in sorted(cards)) + '''</section><footer>المرجع: نتيجة اختبارات Xcode وملف ui-final/manifest.json. أحجام الوصول تتبع Dynamic Type؛ اللقطات السفلية التُقطت بعد التمرير.</footer></main><script>const controls=['mode','size','kind'].map(id=>document.getElementById(id));function filter(){document.querySelectorAll('figure').forEach(card=>card.hidden=controls.some(control=>control.value!=='all'&&card.dataset[control.id]!==control.value));}controls.forEach(control=>control.addEventListener('change',filter));filter();</script></html>'''
document = document.replace('ui-final/manifest.json', f'{folder.name}/manifest.json')
output = root / 'Artifacts/preview.html'
output.write_text(document)
print(f'{len(cards)} verified attachments → {output}')
