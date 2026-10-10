import json, re
from pathlib import Path
root = Path(__file__).resolve().parents[1]
s = root / 'Sources/MadarDesign/Resources/design-tokens.json'
data = json.loads(s.read_text())
out=['// Generated from design-tokens.json v3. Do not hand-edit color values.','import SwiftUI','public enum MadarToken {','    public static let colors: [String: Color] = [']
def walk(v,parts):
 if isinstance(v,dict):
  for k,a in v.items(): walk(a,parts+[k])
 elif isinstance(v,list):
  for i,a in enumerate(v): walk(a,parts+[str(i)])
 elif isinstance(v,str) and (re.fullmatch(r'#[0-9A-Fa-f]{6}',v) or re.fullmatch(r'rgba\([\d.,]+\)',v)):
  if v.startswith('#'): r,g,b=[int(v[i:i+2],16)/255 for i in (1,3,5)]; a=1
  else:r,g,b,a=map(float,v[5:-1].split(','));r/=255;g/=255;b/=255
  out.append(f'        "{".".join(parts)}": Color(.sRGB, red: {r:.12g}, green: {g:.12g}, blue: {b:.12g}, opacity: {a:.12g}),')
for key in ['rooms','widgetIdentity']:walk(data[key],[key])
out+=['    ]','}'];(root / 'Sources/MadarDesign/GeneratedTokens.swift').write_text('\n'.join(out)+'\n')
metrics = ['// Generated from design-tokens.json v3. Do not hand-edit metrics.', 'import Foundation', 'public enum MadarMetric {', '    public static let values: [String: Double] = [']
def metric_walk(value, parts):
    if isinstance(value, dict):
        for key, child in value.items(): metric_walk(child, parts + [key])
    elif isinstance(value, list):
        for index, child in enumerate(value): metric_walk(child, parts + [str(index)])
    elif isinstance(value, (int, float)) and not isinstance(value, bool):
        metrics.append(f'        "{".".join(parts)}": {value},')
for key in ['typeScale', 'spacing', 'radius', 'touch', 'lobbyGrid', 'motion']:
    metric_walk(data[key], [key])
metrics += ['    ]', '    public static let screenMargin: CGFloat = CGFloat(values["spacing.screenMargin"]!)', '    public static let cardPadding: CGFloat = CGFloat(values["spacing.cardPadding.1"]!)', '    public static let cardRadius: CGFloat = CGFloat(values["radius.card"]!)', '    public static let minTarget: CGFloat = CGFloat(values["touch.minTarget"]!)', '}']
(root / 'Sources/MadarDesign/GeneratedMetrics.swift').write_text('\n'.join(metrics) + '\n')
