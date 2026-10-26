#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""Build the local UI gallery from board-linked canonical screens and actual comparison pages.

Does not grade screens, run tests, publish anything, or include unrelated/private result bundles.
"""
import base64
import hashlib
import html
from html.parser import HTMLParser
import json
from pathlib import Path
import re
import subprocess

REPO = Path(__file__).resolve().parents[2]
OUT = REPO / "Madar/Artifacts/review"
ASSETS = OUT / "assets"
ROOMS = {"bahw": "البهو والعادات", "salah": "الصلاة", "quran": "القرآن", "notes-app": "المذكرات",
         "notes": "المذكرات المشتركة", "mal": "المال", "mihbara": "المحبرة", "flex": "التخصيص"}
DIGITS = str.maketrans("0123456789", "٠١٢٣٤٥٦٧٨٩")
# The linked card rows explicitly describe these references as a v2 style picker,
# an unbuilt home edit mode, and OS surfaces with separate device acceptance.
EXCLUDED = {"S11-Mizan", "Tahrir", "S10-Abwab"}


class Comparisons(HTMLParser):
    def __init__(self):
        super().__init__()
        self.sections = []
        self.current = None

    def handle_starttag(self, tag, attrs):
        attrs = dict(attrs)
        if tag == "section":
            self.current = []
            self.sections.append(self.current)
        if tag == "img" and self.current is not None and attrs.get("alt") == "الفعلي":
            self.current.append(attrs["src"])

    def handle_endtag(self, tag):
        if tag == "section":
            self.current = None


def write_asset(data, extension):
    name = hashlib.sha256(data).hexdigest()[:24] + extension
    path = ASSETS / name
    if not path.exists():
        path.write_bytes(data)
    return "assets/" + name


def actual_asset(source):
    match = re.fullmatch(r"data:image/(png|jpeg);base64,([A-Za-z0-9+/=\s]+)", source)
    if not match:
        raise ValueError("Comparison actual must be an embedded PNG or JPEG")
    return write_asset(base64.b64decode(match[2], validate=False), ".png" if match[1] == "png" else ".jpg")


def supplemental(folder, prefix, board, title, card):
    directory = REPO / "Madar/Artifacts" / folder
    manifest = directory / "manifest.json"
    if not manifest.is_file():
        return None
    for test in json.loads(manifest.read_text()):
        for attachment in test["attachments"]:
            if attachment["suggestedHumanReadableName"].startswith(prefix):
                image = (directory / attachment["exportedFileName"]).resolve()
                if not image.is_relative_to(directory.resolve()) or image.suffix != ".png":
                    raise ValueError("Supplemental screenshot escaped its export directory")
                return {"board": board, "room": "mihbara", "title": title, "card": card,
                        "status": "done — appearance awaits owner", "paired": 1,
                        "states": [{"reference": None, "actual": write_asset(image.read_bytes(), ".png"),
                                    "label": "الواجهة الفعلية", "mode": "فاتح"}]}
    return None


def main():
    ASSETS.mkdir(parents=True, exist_ok=True)
    screens = json.loads((REPO / "docs/HANDOFF/screens-index.json").read_text())["screens"]
    rows = []
    # Finished sections leave the board for docs/archive/ (27 Oct); their rows still count.
    board_files = [REPO / "docs/PROGRESS.md", *sorted((REPO / "docs/archive").glob("PROGRESS-*-finished-sections.md"))]
    for line in (line for path in board_files for line in path.read_text().splitlines()):
        if not re.match(r"\| M\d-", line):
            continue
        cells = [cell.strip() for cell in line.split("|") if cell.strip()]
        status = next((cell for cell in cells[2:6] if cell.startswith(("approved", "matched", "done"))), None)
        if status:
            rows.append((cells[0], status, line))
    boards = {}
    for screen in screens:
        # Owner 18 Oct explicitly enabled Turath search/download in v1; the frozen
        # index still carries its original deferred flag. Direct @als stays deferred.
        turath_override = screen["board"] == "R10-Turath-Bahth"
        if (screen["status"] != "canonical" and not turath_override) or screen["kind"] != "screen" or screen["board"] in EXCLUDED:
            continue
        if screen["room"] == "notes-app" and screen["board"] == "outside":
            continue  # RU2 explicitly invalidates this prototype.
        board = screen["board"]
        linked = next(((card, status) for card, status, line in rows if
                       Path(screen["file"]).name in line or f"/{board}.html" in line or f"`{board}`" in line), None)
        if turath_override:
            linked = ("M6-T01", "done — live simulator flow")
        if board == "R10-Milaf-PDF":
            # V18 records that this is an import-preview board, not the active PDF reader.
            linked = next(((card, status) for card, status, _ in rows if card == "M6-V17"), None)
        if linked:
            item = boards.setdefault(board, {"board": board, "room": screen["room"], "title": screen["title"],
                                            "card": linked[0], "status": linked[1], "states": []})
            item["states"].append(screen)

    prepared = []
    for item in boards.values():
        page = REPO / "Madar/Artifacts/compare" / (item["board"] + ".html")
        parser = Comparisons()
        if page.is_file():
            parser.feed(page.read_text())
        states = []
        for position, screen in enumerate(sorted(item["states"], key=lambda screen: screen["scrolled"])):
            path = (REPO / "docs/HANDOFF" / screen["file"]).resolve()
            if not path.is_relative_to(REPO / "docs/HANDOFF/screens"):
                raise ValueError("Canonical escaped the handoff screens directory")
            actuals = parser.sections[position] if position < len(parser.sections) else []
            states.append({"reference": write_asset(path.read_bytes(), path.suffix),
                           "actual": actual_asset(actuals[0]) if actuals else None,
                           "label": "البداية" if not screen["scrolled"] else "حالة إضافية " + str(screen["scrolled"]).translate(DIGITS),
                           "mode": "داكن" if screen["mode"] == "dark" else "فاتح"})
        item["states"] = states
        item["paired"] = sum(state["actual"] is not None for state in states)
        prepared.append(item)

    for arguments in [
        ("PDF-OCR-sources-r2-shots", "M6-PDF-OCR-search-L", "PDF-Reader", "قارئ PDF والبحث المحلي", "M6-V18"),
        ("M6-T01-live-persisted-shots", "M6-T01-live-quote-L", "Turath-Quote", "بطاقة الاقتباس من تراث", "M6-T01"),
    ]:
        item = supplemental(*arguments)
        if item:
            prepared.append(item)

    commit = subprocess.check_output(["git", "rev-parse", "--short", "HEAD"], cwd=REPO, text=True).strip()
    # Escape script-closing sequences even if a future source title contains HTML.
    payload = json.dumps(prepared, ensure_ascii=False).replace("<", "\\u003c")
    options = "".join(f'<option value="{html.escape(key)}">{value}</option>' for key, value in ROOMS.items())
    document = TEMPLATE.replace("__DATA__", payload).replace("__ROOMS__", options).replace("__COMMIT__", html.escape(commit))
    target = OUT / "madar-ui-review.html"
    target.write_text(document)
    states = sum(len(item["states"]) for item in prepared)
    paired = sum(item["paired"] for item in prepared)
    print(f"{len(prepared)} screens, {paired}/{states} actual states -> {target}")
    print("Unpaired:", ", ".join(item["board"] for item in prepared if item["paired"] < len(item["states"])))


TEMPLATE = '''<!doctype html><html lang="ar" dir="rtl"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1"><title>معاينة مدار الحالية</title>
<style>
:root{--paper:#f4eddd;--ink:#251f16;--quiet:#6b624f;--line:#d5c5a6;--card:#fffbef;--gold:#876625}
*{box-sizing:border-box}body{margin:0;background:var(--paper);color:var(--ink);font:16px/1.7 system-ui,sans-serif}
main{max-width:1440px;margin:auto;padding:38px 22px 70px}header{max-width:880px}.eyebrow{letter-spacing:.05em;color:var(--gold);font-weight:700}
h1{font-size:clamp(32px,5vw,58px);line-height:1.3;margin:14px 0}p{color:var(--quiet)}.notice{border-inline-start:3px solid var(--gold);padding:10px 18px;background:#fff7df}
.controls{position:sticky;top:0;z-index:2;padding:16px 0;background:var(--paper);display:flex;flex-wrap:wrap;gap:10px;align-items:center}
input,select,button{font:inherit;color:inherit}input,select{border:1px solid var(--line);background:var(--card);padding:10px 14px;border-radius:12px;min-height:44px}
input[type=search]{flex:1;min-width:180px}button{cursor:pointer}button:focus-visible,input:focus-visible,select:focus-visible{outline:3px solid var(--gold);outline-offset:3px}
#count{color:var(--quiet);font-size:14px}.grid{display:grid;grid-template-columns:repeat(auto-fill,minmax(245px,1fr));gap:22px}.card{border:1px solid var(--line);border-radius:22px;overflow:hidden;background:var(--card);text-align:right;padding:0;box-shadow:0 8px 22px #4d38160b}
.thumb{background:#e8ddc6;height:330px;overflow:hidden;position:relative}.thumb img{width:100%;display:block}.badge{position:absolute;inset:12px 12px auto auto;padding:3px 9px;border-radius:18px;background:#fffbefee;font-size:12px}
.card .body{padding:16px}.card h2{font-size:19px;margin:4px 0 8px}.meta{color:var(--quiet);font-size:13px}.room{color:var(--gold);font-size:13px;font-weight:700}.missing{border-style:dashed}
dialog{width:min(1450px,96vw);max-height:94vh;border:1px solid var(--line);border-radius:22px;background:var(--paper);color:var(--ink);padding:20px}
dialog::backdrop{background:#211c14b3}.dialogbar{position:sticky;top:-20px;background:var(--paper);z-index:1;padding:10px 0;display:flex;flex-wrap:wrap;align-items:center;gap:14px}.close{margin-inline-start:auto;border:1px solid var(--line);border-radius:30px;width:44px;height:44px;background:var(--card)}
.states{display:flex;gap:8px;flex-wrap:wrap}.states button{border:1px solid var(--line);padding:8px 14px;background:var(--card);border-radius:12px;min-height:44px}.states button[aria-pressed=true]{background:var(--ink);color:var(--card)}
.pair{display:grid;grid-template-columns:repeat(3,minmax(0,393px));gap:18px;align-items:start}.pair figure{margin:0}.pair img{width:100%;display:block;border-radius:15px}.pair figcaption{padding:10px 0;color:var(--quiet)}.stack{position:relative}.stack img+img{position:absolute;inset:0;opacity:.5}.empty{min-height:200px;display:grid;place-items:center;background:#fff7df;border-radius:15px;color:var(--quiet)}
.verdict{display:flex;gap:8px;flex-wrap:wrap;margin:6px 0 10px}.verdict button{border:1px solid var(--line);padding:8px 16px;background:var(--card);border-radius:12px;min-height:44px}.verdict button[aria-pressed=true][data-v=ok]{background:#2f5d3a;color:#fff}.verdict button[aria-pressed=true][data-v=fix]{background:#8a3b1f;color:#fff}
#note{width:100%;min-height:90px;border:1px solid var(--line);border-radius:12px;background:var(--card);padding:10px 14px;font:inherit;margin-bottom:14px}.judge{font-size:13px;font-weight:700;margin-inline-start:6px}.judge.ok{color:#2f5d3a}.judge.fix{color:#8a3b1f}
#export{border:1px solid var(--gold);background:var(--ink);color:var(--card);padding:10px 16px;border-radius:12px;min-height:44px}
@media(max-width:1050px){.pair{grid-template-columns:repeat(2,minmax(0,1fr))}.pair figure:last-child{max-width:393px;grid-column:1/-1}}@media(max-width:600px){main{padding:22px 12px}.grid{grid-template-columns:repeat(2,minmax(0,1fr));gap:12px}.thumb{height:230px}.card .body{padding:12px}.card h2{font-size:16px}.controls select{max-width:48%}.pair{gap:10px}dialog{padding:12px}.dialogbar{top:-12px}}
</style><main><header><div class="eyebrow">مدار · المعاينة المحلية</div><h1>كل غرفة، كما تظهر.</h1>
<p>لقطات التطبيق الفعلية بجانب الشاشات المعتمدة، بحجم الخط الافتراضي. افتح أي شاشة للمقارنة أو التراكب.</p>
<p class="notice">هذه اللقطات المتاحة من اختبارات المحاكي، وبعضها من اختبارات سابقة. ليست جولة آيفون أو اعتمادًا للإصدار. الصور الناقصة تظهر صراحة، وتبقى فروق الواجهة وقرارات المالك في لوحة التقدم.</p>
<p class="meta">مصدر حالة الشاشات: لوحة التقدم · نسخة المصدر <bdi>__COMMIT__</bdi> · لا تتضمن هذه الصفحة صور عينة رسائل البنك الخاصة.</p></header>
<div class="controls"><input id="search" type="search" aria-label="ابحث عن شاشة" placeholder="ابحث عن شاشة أو بطاقة…"><select id="room" aria-label="الغرفة"><option value="">كل الغرف</option>__ROOMS__</select><select id="coverage" aria-label="اكتمال اللقطات"><option value="">كل الحالات</option><option value="missing">تنقصها لقطة فعلية</option><option value="paired">لقطاتها مكتملة</option><option value="unjudged">لم أحكم عليها</option><option value="fix">تحتاج تعديلًا</option></select><button id="export" type="button">صدّر ملاحظاتي</button><span id="count" aria-live="polite"></span></div>
<section class="grid" id="grid" aria-label="شاشات مدار"></section><p id="noresults" hidden>لا توجد شاشة تطابق هذا البحث.</p></main>
<dialog id="viewer" aria-label="مقارنة الشاشة"><div class="dialogbar"><b id="title"></b><button class="close" id="close" aria-label="أغلق المقارنة">×</button></div><p id="status"></p><div class="verdict" id="verdict"><button type="button" data-v="ok">موافق</button><button type="button" data-v="fix">يحتاج تعديل</button></div><textarea id="note" aria-label="ملاحظتك" placeholder="ملاحظتك على هذه الشاشة: ما الذي يختلف أو لا يعجبك؟"></textarea><div class="states" id="states"></div><p><label>شفافية الفعلي في التراكب <input id="opacity" type="range" min="0" max="100" value="50"></label></p><div class="pair" id="pair"></div></dialog>
<script>
const data=__DATA__,rooms=Object.fromEntries([...document.getElementById('room').options].map(o=>[o.value,o.textContent]));
const $=id=>document.getElementById(id),digits=new Intl.NumberFormat('ar-SA'),grid=$('grid'),dialog=$('viewer');
function el(tag,text,cls){const e=document.createElement(tag);if(text!==undefined)e.textContent=text;if(cls)e.className=cls;return e}
function image(src,alt){const i=el('img');i.src=src;i.alt=alt;i.loading='lazy';return i}
let current=null,notes={};try{notes=JSON.parse(localStorage.getItem('madar-review-notes')||'{}')}catch(e){}
function persist(){try{localStorage.setItem('madar-review-notes',JSON.stringify(notes))}catch(e){}}
function loadNote(){const n=notes[current.board]||{};$('note').value=n.note||'';[...$('verdict').children].forEach(b=>b.setAttribute('aria-pressed',String(b.dataset.v===n.v)))}
function setNote(patch){const n=Object.assign(notes[current.board]||{},patch,{at:new Date().toISOString()});notes[current.board]=n;persist()}
function exportNotes(){const lines=['# ملاحظات المالك على شاشات مدار','','التاريخ: '+new Date().toISOString().slice(0,10),''];let ok=0,fix=0;for(const item of data){const n=notes[item.board];if(!n||(!n.v&&!n.note))continue;n.v==='ok'?ok++:n.v==='fix'?fix++:0;lines.push('## '+item.board+' — '+item.title,'- البطاقة: '+item.card+' · الحالة في اللوحة: '+item.status.split(' ')[0],'- الحكم: '+(n.v==='ok'?'موافق':n.v==='fix'?'يحتاج تعديل':'بلا حكم'),n.note?'- الملاحظة: '+n.note.replace(/\\n/g,' / '):'- الملاحظة: —','')}lines.splice(3,0,'موافق: '+ok+' · يحتاج تعديل: '+fix+' · من '+data.length+' شاشة','');const a=document.createElement('a');a.href=URL.createObjectURL(new Blob([lines.join('\\n')],{type:'text/markdown'}));a.download='madar-review-notes.md';a.click()}
function render(){grid.replaceChildren();let visible=data.filter(item=>(!$('room').value||item.room===$('room').value)&&(!$('search').value||[item.title,item.board,item.card,rooms[item.room]].join(' ').toLowerCase().includes($('search').value.toLowerCase()))&&(!$('coverage').value||($('coverage').value==='missing' ? item.paired<item.states.length : $('coverage').value==='unjudged' ? !notes[item.board]?.v : $('coverage').value==='fix' ? notes[item.board]?.v==='fix' : item.paired===item.states.length)));
for(const item of visible){const button=el('button',undefined,'card'+(item.paired<item.states.length?' missing':''));button.type='button';const thumb=el('div',undefined,'thumb');thumb.append(image(item.states[0].actual||item.states[0].reference,item.title));thumb.append(el('span',item.paired?digits.format(item.paired)+' / '+digits.format(item.states.length)+' لقطات':'المعتمد فقط','badge'));const body=el('div',undefined,'body');const j=notes[item.board]?.v;const room=el('div',rooms[item.room],'room');if(j)room.append(el('span',j==='ok'?'✓ موافق':'✎ يحتاج تعديل','judge '+j));body.append(room,el('h2',item.title),el('div',item.card+' · '+item.board,'meta'));button.append(thumb,body);button.onclick=()=>open(item);grid.append(button)}
let n=visible.length;$('count').textContent=n===1?'شاشة واحدة':n===2?'شاشتان':digits.format(n)+(n>=3&&n<=10?' شاشات':' شاشة');$('noresults').hidden=n>0;}
function open(item){current=item;loadNote();$('title').textContent=item.title;let status=item.status.startsWith('matched')?'مطابق — بانتظار المالك':item.status.startsWith('approved')?(item.status.includes('pending owner')?'بانتظار تجربة المالك':'معتمد في لوحة التقدم'):'منفّذ؛ تفاصيل القبول في لوحة التقدم';$('status').textContent=item.card+' — '+status;$('states').replaceChildren();item.states.forEach((s,i)=>{const b=el('button',s.label+'، '+s.mode);b.type='button';b.onclick=()=>show(item,i);$('states').append(b)});show(item,0);dialog.showModal()}
function show(item,n){[...$('states').children].forEach((b,i)=>b.setAttribute('aria-pressed',String(i===n)));const state=item.states[n],pair=$('pair');$('opacity').closest('p').hidden=!state.actual||!state.reference;pair.replaceChildren();for(const [label,src] of [['المعتمد',state.reference],['الفعلي',state.actual]]){const f=el('figure');f.append(el('figcaption',label),src?image(src,label):el('div',label==='المعتمد'?'لا يوجد مرجع تصميم مستقل لهذه الواجهة':'لم تُلتقط هذه الحالة','empty'));pair.append(f)}if(state.actual&&state.reference){const f=el('figure'),stack=el('div',undefined,'stack');stack.append(image(state.reference,'المعتمد'),image(state.actual,'الفعلي في التراكب'));f.append(el('figcaption','التراكب'),stack);pair.append(f);opacity()}}
function opacity(){document.querySelectorAll('.stack img+img').forEach(i=>i.style.opacity=$('opacity').value/100)}
$('close').onclick=()=>dialog.close();$('opacity').oninput=opacity;['search','room','coverage'].forEach(id=>$(id).addEventListener('input',render));$('search').value=new URL(location.href).searchParams.get('q')||'';render();
$('verdict').addEventListener('click',e=>{const v=e.target.dataset?.v;if(!v)return;const same=notes[current.board]?.v===v;setNote({v:same?'':v});loadNote();render()});
$('note').addEventListener('input',()=>setNote({note:$('note').value}));$('export').onclick=exportNotes;dialog.addEventListener('close',render);
</script></html>'''

if __name__ == "__main__":
    main()
