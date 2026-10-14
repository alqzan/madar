#!/usr/bin/env python3
"""Bind the pinned original 1439 page fonts to Madar word IDs; run from the repository root.
Requires fontTools with WOFF2 support. Cache contains the pinned source tree, page JSON and font binaries.
"""
import json,hashlib,shutil
from pathlib import Path
from collections import defaultdict
from fontTools.ttLib import TTFont
root=Path('Madar/Packages/MadarQuran/Sources/MadarQuran/Resources');cache=Path('tmp/m2-r01')
layout=json.loads((root/'Quran1439/layout.json').read_text());data=json.loads((root/'UthmanicHafs_v2-0/hafsData_v2-0.json').read_text());ids={(x['sura_no'],x['aya_no']):x['id'] for x in data}
tree={x['path']:x for x in json.loads((cache/'mutqin-tree.json').read_text())['tree']}
out=[]; files=[];dest=root/'Quran1439/Fonts';dest.mkdir(exist_ok=True)
for p in range(1,605):
 rawBytes=(cache/f'qcf2-pages/{p}.json').read_bytes();assert hashlib.sha1(b'blob '+str(len(rawBytes)).encode()+b'\0'+rawBytes).hexdigest()==tree[f'mushaf/pages/{p}.json']['sha']
 raw=json.loads(rawBytes); flat=[(row['l']-(7 if p<=2 else 0),item) for row in raw['lines'] for item in row['w']]
 last={(s,a):i for i,(_,(_,s,a)) in enumerate(flat)};indices=defaultdict(int);entries=[]
 for i,(line,(glyph,s,a)) in enumerate(flat):
  aid=ids[s,a];isMark=last[s,a]==i
  entry={'ayahID':aid,'glyphs':glyph,'line':line}
  if not isMark:entry['wordIndex']=indices[aid];indices[aid]+=1
  entries.append(entry)
 existing=layout['pages'][p-1]
 for line in existing['lines']:
  row=[v for v in entries if v['line']==line['number']]
  assert [(v['ayahID'],v['wordIndex']) for v in row if 'wordIndex' in v]==[(v['ayahID'],v['wordIndex']) for v in line['words']],(p,line['number'])
  assert [v['ayahID'] for v in row if 'wordIndex' not in v]==line['ayahEnds'],(p,line['number'],'marks')
 source=cache/f'qcf2-fonts/{p}.woff2';b=source.read_bytes();assert hashlib.sha1(b'blob '+str(len(b)).encode()+b'\0'+b).hexdigest()==tree[f'mushaf/fonts/{p}.woff2']['sha']
 f=TTFont(source);cm=f.getBestCmap();missing={ord(c) for e in entries for c in e['glyphs'] if c!=' '}-set(cm);assert not missing,(p,missing)
 fontName=next(n.toUnicode() for n in f['name'].names if n.nameID==6)
 shutil.copy2(source,dest/f'{p}.woff2');files.append({'path':f'Quran1439/Fonts/{p}.woff2','sha256':hashlib.sha256(b).hexdigest(),'edition':1439,'role':'quranData'})
 out.append({'page':p,'fontName':fontName,'entries':entries})
result=root/'Quran1439/printed-glyphs.json';result.write_text(json.dumps({'version':1,'edition':1439,'pages':out},ensure_ascii=False,separators=(',',':'))+'\n')
manifestPath=root/'QuranResourceManifest.json';manifest=json.loads(manifestPath.read_text());manifest['files']=[v for v in manifest['files'] if '/Fonts/' not in v['path'] and not v['path'].endswith('printed-glyphs.json')]+files+[{'path':'Quran1439/printed-glyphs.json','sha256':hashlib.sha256(result.read_bytes()).hexdigest(),'edition':1439,'role':'quranData'}]
manifest['printedFontSource']={'repository':'https://github.com/abdoadel123/mutqin-resources','commit':'0cd14756e44d52d012e00fb15b128979c5c0b213','paths':'mushaf/fonts/1.woff2 ... 604.woff2 and mushaf/pages/1.json ... 604.json','verification':'All 604 font binaries match the pinned Git blob IDs; every private glyph exists in its own page font. All 77429 word groups and 6236 end markers bind to the existing verified 1439 map. Only ASCII spaces use the unchanged official Unicode font.'}
manifest['rendering']='QCF V2 printed word glyphs in the corresponding original 1439 page font; unchanged Hafs Unicode text remains the semantic layer. No private glyph fallback.'
manifestPath.write_text(json.dumps(manifest,ensure_ascii=False,indent=2)+'\n')
print('Verified and bundled 604 original fonts, 77429 word groups and 6236 ayah marks.',flush=True)
