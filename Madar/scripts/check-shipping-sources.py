#!/usr/bin/env python3
"""Bounded M0 shipping-source checks. Static success is not complete UI acceptance.

Uses PBX source/resource phases and local package product targets, never App/*.swift
as the shipping list. Unknown build layouts fail closed. Dynamic source constructs
are emitted for manual tracing; --require-complete returns 2 while any remain.
"""
import argparse
import hashlib
import json
import math
import re
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
DIGIT_DOT = re.compile(r"[0-9٠-٩۰-۹][\s\u2066-\u2069]*·|·[\s\u2066-\u2069]*[0-9٠-٩۰-۹]")
SWIFT_STRING = re.compile(r'"(?:\\.|[^"\\])*"')
PLURALS = {"zero", "one", "two", "few", "many", "other"}


def uncomment(text):
    """Preserve line numbers and quoted contents; erase Swift // and /* */ comments."""
    out, i, block = [], 0, 0
    while i < len(text):
        if block:
            if text[i:i+2] == '/*': block += 1; out.extend('  '); i += 2
            elif text[i:i+2] == '*/': block -= 1; out.extend('  '); i += 2
            else: out.append('\n' if text[i] == '\n' else ' '); i += 1
        elif text[i:i+2] == '//':
            end = text.find('\n', i)
            if end < 0: end = len(text)
            out.extend(' ' * (end-i)); i = end
        elif text[i:i+2] == '/*': block = 1; out.extend('  '); i += 2
        elif text[i] == '"':
            # Interpolated nested quotes are conservatively inventoried later.
            match = SWIFT_STRING.match(text, i)
            if not match: raise ValueError('unclosed Swift string')
            out.extend(match.group()); i = match.end()
        else: out.append(text[i]); i += 1
    if block: raise ValueError('unclosed Swift comment')
    return ''.join(out)


def check_target_dependencies(declaration, manifest, product, included_products):
    """Current literal dependency forms only; extra same-package targets fail closed.

    We do not implement a SwiftPM graph evaluator. Root product dependencies already
    enumerated by PBX are supported; the explicitly excluded pinned Adhan product
    is the only external dependency. Any new form needs deliberate scope support.
    """
    match = re.search(r'\bdependencies:\s*', declaration)
    if not match: return
    tail = declaration[match.end():]
    array = re.match(r'\[([^\]]*)\]', tail)
    if not array: raise ValueError(f'computed target dependencies require scope support: {product}')
    same_package_targets = set(re.findall(r'(?<!\w)\.(?:target|executableTarget)\(name:\s*"([^"]+)"', manifest))
    remaining = array[1].strip()
    while remaining:
        literal = re.match(r'"([^"\\]+)"', remaining)
        external = re.match(r'\.product\(name:\s*"([^"\\]+)",\s*package:\s*"([^"\\]+)"\)', remaining)
        if literal:
            name = literal[1]; consumed = literal.end()
            if name in same_package_targets:
                raise ValueError(f'additional local target dependency {product} -> {name} requires graph support')
            if name not in included_products:
                raise ValueError(f'unenumerated package dependency {product} -> {name}')
        elif external:
            name, package = external.groups(); consumed = external.end()
            if (name, package) != ('Adhan', 'adhan-swift') or not re.search(
                    r'\.package\(url:\s*"https://github\.com/batoulapps/adhan-swift\.git",\s*revision:\s*"[0-9a-f]{40}"\)', manifest):
                raise ValueError(f'unsupported external product dependency {product} -> {name}/{package}')
        else:
            raise ValueError(f'unsupported target dependency expression: {product}: {remaining}')
        remaining = remaining[consumed:].strip()
        if remaining:
            if not remaining.startswith(','): raise ValueError(f'unparsed target dependency tail: {product}')
            remaining = remaining[1:].strip()


def build_files(project, root):
    """Resolve explicit PBX groups, application plus embedded extension phases."""
    objects = project['objects']; paths = {}
    def walk(identifier, base):
        obj = objects[identifier]
        tree = obj.get('sourceTree', '<group>')
        if tree in ('BUILT_PRODUCTS_DIR', 'SDKROOT'): return  # Not source/resource input.
        if tree not in ('<group>', 'SOURCE_ROOT'):
            raise ValueError(f'unsupported sourceTree {tree} for {identifier}')
        path = (root if tree == 'SOURCE_ROOT' else base) / obj.get('path', '')
        paths[identifier] = path
        for child in obj.get('children', []): walk(child, path)
    walk(objects[project['rootObject']]['mainGroup'], root)
    sources, resources, packages, target_names = set(), set(), set(), []
    targets = [o for o in objects.values() if o['isa'] == 'PBXNativeTarget'
               and o['productType'] in ('com.apple.product-type.application', 'com.apple.product-type.app-extension')]
    if {o['name'] for o in targets} != {'Madar', 'MadarWidgets'}:
        raise ValueError('shipping target set changed; inventory required')
    for target in targets:
        target_names.append(target['name'])
        if target.get('fileSystemSynchronizedGroups'):
            raise ValueError('synchronized group requires explicit inventory support')
        for phase_id in target['buildPhases']:
            phase = objects[phase_id]
            if phase['isa'] not in ('PBXSourcesBuildPhase', 'PBXResourcesBuildPhase'): continue
            selected = sources if phase['isa'] == 'PBXSourcesBuildPhase' else resources
            for item in phase['files']:
                reference = objects[item].get('fileRef')
                if reference not in paths: raise ValueError(f'unresolved build file {item}')
                if objects[reference]['isa'] != 'PBXFileReference':
                    raise ValueError('localized/group build resource requires explicit inventory support')
                path = paths[reference]
                if not path.exists(): raise ValueError(f'missing shipping file {path}')
                selected.add(path)
        for identifier in target.get('packageProductDependencies', []):
            dep = objects[identifier]
            if 'package' in dep:
                candidates = [objects[dep['package']]]
            else:
                candidates = [objects[x] for x in objects[project['rootObject']]['packageReferences']
                              if objects[x]['isa'] == 'XCLocalSwiftPackageReference'
                              and re.search(r'\.library\(name:\s*"' + re.escape(dep['productName']) + r'"',
                                            (root/objects[x]['relativePath']/'Package.swift').read_text())]
            if len(candidates) != 1 or candidates[0]['isa'] != 'XCLocalSwiftPackageReference':
                raise ValueError(f'unresolved/ambiguous local product {dep["productName"]}')
            packages.add((candidates[0]['relativePath'], dep['productName']))
    for relative, product in packages:
        package = root / relative
        manifest = uncomment((package / 'Package.swift').read_text())
        library = re.search(r'\.library\(name:\s*"' + re.escape(product) + r'",\s*targets:\s*\["([^"\]]+)"\]\)', manifest)
        if not library: raise ValueError(f'unknown product layout {product}')
        target = library.group(1)
        # Current manifests use default Sources/<target>. Do not silently ignore excludes.
        declaration = re.search(r'(?<!\w)\.target\(name:\s*"' + re.escape(target) + r'"', manifest)
        if not declaration: raise ValueError(f'missing library target {product}')
        start = manifest.index('(', declaration.start()); depth = 1; end = start+1
        while end < len(manifest) and depth:
            if manifest[end] == '(': depth += 1
            elif manifest[end] == ')': depth -= 1
            end += 1
        if depth or re.search(r'\b(?:path|exclude|sources)\s*:', manifest[start:end]):
            raise ValueError(f'custom package layout needs support: {product}')
        check_target_dependencies(manifest[start:end], manifest, product, {name for _, name in packages})
        directory = package / 'Sources' / target
        if not directory.is_dir(): raise ValueError(f'missing product source {directory}')
        sources.update(directory.rglob('*.swift'))
        declared_resources = re.findall(r'\.(?:process|copy)\("([^"]+)"\)', manifest[start:end])
        if re.search(r'\bresources:', manifest[start:end]) and (not declared_resources or
                len(declared_resources) != len(re.findall(r'\.(?:process|copy)\(', manifest[start:end]))):
            raise ValueError(f'computed package resources require explicit inventory: {product}')
        for resource in declared_resources:
            resource_path = directory / resource
            if not resource_path.exists(): raise ValueError(f'missing declared package resource {resource_path}')
            resources.update(resource_path.rglob('*.xcstrings') if resource_path.is_dir() else [resource_path])
    return sorted(sources), sorted(resources), sorted(packages), sorted(target_names)


def get_path(document, path):
    value = document
    for key in path.split('.'): value = value[key]
    return value


def rgba(value):
    if isinstance(value, str) and re.fullmatch(r'#[0-9A-Fa-f]{6}', value):
        return tuple(int(value[i:i+2], 16)/255 for i in (1, 3, 5)) + (1.0,)
    if isinstance(value, str):
        match = re.fullmatch(r'rgba\((\d+),(\d+),(\d+),([\d.]+)\)', value)
        if match:
            r, g, b = (int(match[i])/255 for i in (1, 2, 3)); a = float(match[4])
            if all(0 <= x <= 1 for x in (r, g, b, a)): return r, g, b, a
    raise ValueError(f'invalid colour token {value!r}')


def over(foreground, background):
    if background[3] != 1: raise ValueError('underlying background must be opaque')
    return tuple(foreground[i]*foreground[3] + background[i]*(1-foreground[3]) for i in range(3)) + (1.0,)


def opaque_colour(tokens, expression):
    parts = expression.split('@')
    if len(parts) > 2: raise ValueError('unsupported composite expression')
    colour = rgba(get_path(tokens, parts[0]))
    if len(parts) == 2: return over(colour, opaque_colour(tokens, parts[1]))
    if colour[3] != 1: raise ValueError(f'alpha background lacks explicit underlying token: {expression}')
    return colour


def contrast(tokens, foreground, background, rgb8=False):
    bg = opaque_colour(tokens, background)
    fg = over(rgba(get_path(tokens, foreground)), bg)
    if rgb8:
        fg = tuple(round(x*255)/255 for x in fg[:3]) + (1.0,)
        bg = tuple(round(x*255)/255 for x in bg[:3]) + (1.0,)
    def luminance(colour):
        values = [x/12.92 if x <= .04045 else ((x+.055)/1.055)**2.4 for x in colour[:3]]
        return sum(x*w for x, w in zip(values, (.2126, .7152, .0722)))
    light, dark = sorted((luminance(fg), luminance(bg)), reverse=True)
    return (light+.05)/(dark+.05)


def token_checks(tokens):
    failures, measured = [], []
    def sizes(value, path='typeScale'):
        if isinstance(value, dict):
            for key, child in value.items():
                if key in ('size', 'minimumTextSize') and (not isinstance(child, (float, int)) or isinstance(child, bool) or not math.isfinite(child) or child < 11):
                    failures.append(f'{path}.{key}: text size below 11 or not numeric')
                sizes(child, f'{path}.{key}')
        elif isinstance(value, list):
            for index, child in enumerate(value): sizes(child, f'{path}[{index}]')
    sizes(tokens['typeScale'])
    if tokens['typeScale']['minimumTextSize'] != 11: failures.append('minimumTextSize differs from approved 11')
    # M0 native foundation uses bahw (default RoomTheme); no future-room contrast audit.
    for pair in tokens['contrast']['pairs']:
        if not isinstance(pair, dict) or not all(isinstance(pair.get(key), str) for key in ('fg','bg','use')):
            failures.append('contrast pair has invalid field types'); continue
        if not isinstance(pair.get('ratio'), (float,int)) or isinstance(pair['ratio'], bool) or not math.isfinite(pair['ratio']):
            failures.append(f'{pair["fg"]}: invalid contrast ratio type'); continue
        if not (pair['fg'].startswith('rooms.bahw.') and pair['bg'].startswith('rooms.bahw.')): continue
        use = pair.get('use'); threshold = {'small': 4.5, 'large': 3.0, 'nontext': 3.0}.get(use)
        label = f"{pair['fg']} on {pair['bg']} ({use})"
        try:
            if threshold is None or pair['min'] != threshold: raise ValueError('invalid pair use/min type or threshold')
            ratio = contrast(tokens, pair['fg'], pair['bg'])
            # Declared rounded ratio is checked, never used to decide contrast.
            rgb8 = contrast(tokens, pair['fg'], pair['bg'], rgb8=True)
            if not isinstance(pair['ratio'], (float, int)) or min(abs(ratio-pair['ratio']), abs(rgb8-pair['ratio'])) > .011:
                failures.append(f'{label}: declared ratio drift; actual {ratio:.4f}')
            passes = ratio >= threshold
            if 'outline' in pair:
                outline = contrast(tokens, pair['outline'], pair['bg'])
                outline8 = contrast(tokens, pair['outline'], pair['bg'], rgb8=True)
                if use != 'nontext' or min(abs(outline-pair['outlineRatio']), abs(outline8-pair['outlineRatio'])) > .011:
                    failures.append(f'{label}: outline metadata drift')
                passes = passes or (use == 'nontext' and outline >= threshold)
            if not passes: failures.append(f'{label}: actual contrast {ratio:.4f} below {threshold}')
            measured.append(dict(pair=label, calculatedRatio=round(ratio, 6), rgb8Ratio=round(rgb8, 6), threshold=threshold))
        except (ValueError, KeyError, TypeError) as error: failures.append(f'{label}: {error}')
    if not measured: failures.append('no M0 contrast pairs measured')
    return failures, measured


def default_valid(definition):
    value, kind = definition['default'], definition['type']
    if kind == 'choice': return any(type(option['value']) is type(value) and option['value'] == value for option in definition['options'])
    if kind == 'bool': return isinstance(value, bool)
    if kind in ('int', 'money'):
        return isinstance(value, int) and not isinstance(value, bool) and (not definition.get('range') or definition['range'][0] <= value <= definition['range'][-1])
    if kind in ('object', 'map', 'place', 'layout'): return isinstance(value, dict)
    if kind == 'list': return isinstance(value, list)
    if kind == 'string': return isinstance(value, str)
    if kind == 'time': return isinstance(value, str) and re.fullmatch(r'(?:[01]\d|2[0-3]):[0-5]\d', value) is not None
    return False


def schema_checks(schema, supported):
    failures = []; definitions = {}
    for row in schema['settings']:
        if row['key'] in definitions: failures.append(f"duplicate setting {row['key']}")
        definitions[row['key']] = row
        if not default_valid(row): failures.append(f"{row['key']}: invalid default for {row['type']}")
    for key in supported:
        if key not in definitions: failures.append(f'unknown supported key {key}')
        elif definitions[key].get('availability', 'v1') != 'v1': failures.append(f'cut key supported: {key}')
        elif definitions[key]['type'] not in {'choice', 'bool', 'int', 'place'}:
            failures.append(f'supported key has no shipped SettingControl branch: {key}')
    return failures, definitions


def catalog_checks(catalog):
    failures, values, plural_groups = [], [], 0
    def walk(value, path):
        nonlocal plural_groups
        if isinstance(value, dict):
            if 'stringUnit' in value:
                unit = value['stringUnit']
                if not isinstance(unit.get('value'), str): failures.append(f'{path}: missing string value')
                else:
                    values.append(dict(path=path, value=unit['value']))
                    if DIGIT_DOT.search(unit['value']): failures.append(f'{path}: numeric middle dot')
                    if '·' in unit['value'] and re.search(r'%(?:\d+\$)?[@dfiul]|%#@', unit['value']):
                        failures.append(f'{path}: format placeholder next to possible numeric middle dot; resolve explicitly')
            if 'plural' in value:
                plural_groups += 1
                if set(value['plural']) != PLURALS: failures.append(f'{path}: Arabic plural categories incomplete')
            for key, child in value.items(): walk(child, f'{path}/{key}')
        elif isinstance(value, list):
            for index, child in enumerate(value): walk(child, f'{path}/{index}')
    # Arabic source plus Arabic localizations; every localization value is also RU1 scanned.
    walk(catalog['strings'], 'strings')
    return failures, values, plural_groups


def scan_source(text, path, definitions):
    failures, inventory, keys = [], [], set()
    clean = uncomment(text)
    for number, line in enumerate(clean.splitlines(), 1):
        if not line.strip(): continue
        spot = f'{path}:{number}'
        decoded = re.sub(r'\\u\{([0-9a-fA-F]+)\}', lambda m: chr(int(m[1], 16)), line)
        if DIGIT_DOT.search(decoded): failures.append(f'{spot}: numeric middle dot')
        if re.search(r'\\\((?:arabicNumber|digits|session\.digits)\([^\n]*?سجلًّا', line):
            failures.append(f'{spot}: RU3 hand-built record count phrase requires catalog plurals')
        if re.search(r'\b(?:Color|UIColor|CGColor)\s*\(\s*(?:red:|white:|displayP3Red:|#["\w])', line):
            failures.append(f'{spot}: handwritten colour constructor')
        if re.search(r'\bColor\(\.sRGB,\s*red:|\.(?:foregroundStyle|foregroundColor|background|tint)\(\.(?:red|green|blue|white|black|yellow|orange|pink|purple|gray)\b', line):
            failures.append(f'{spot}: handwritten colour value')
        for match in re.finditer(r'\b(?:Font\.)?(?:system|custom)\([^\n]*?size:\s*(\d+(?:\.\d+)?)', line):
            if float(match[1]) < 11: failures.append(f'{spot}: explicit font size below 11')
        for match in re.finditer(r'\b(?:session\.)?(string|bool|number)\("([\w.]+)"\)', line):
            kind, key = match.groups()
            # Only session or unqualified AppSession convenience functions are setting reads.
            if 'session.' not in match[0] and not path.endswith('/AppSession.swift'): continue
            keys.add(key)
            if key not in definitions: failures.append(f'{spot}: unknown setting {key}')
            elif definitions[key]['type'] not in {'string': {'choice', 'string', 'time'}, 'bool': {'bool'}, 'number': {'int', 'money'}}[kind]:
                failures.append(f'{spot}: {kind} read conflicts with {key} type {definitions[key]["type"]}')
        for key in re.findall(r'\b(?:key|for):\s*"([\w.]+)"|\bvalues\["([\w.]+)"\]', line):
            name = key[0] or key[1]
            if '.' not in name: continue
            if name in definitions: keys.add(name)
            elif name.split('.')[0] in {'core','salah','quran','notes','mal','mihbara','bahw','notif','tabbar'}:
                failures.append(f'{spot}: unknown literal setting key {name}')
        for write in re.finditer(r'\bsession\.set\(\.(bool|number|string|object|array)\([^\n]*?\),\s*key:\s*"([\w.]+)"', line):
            kind, key = write.groups()
            if key in definitions:
                expected = {'bool':'bool','int':'number','money':'number','string':'string','time':'string',
                            'place':'object','object':'object','map':'object','layout':'object','list':'array'}
                definition = definitions[key]
                expected_kind = expected.get(definition['type'])
                if definition['type'] == 'choice':
                    expected_kind = 'bool' if isinstance(definition['default'], bool) else 'string' if isinstance(definition['default'], str) else 'number'
                if kind != expected_kind: failures.append(f'{spot}: {kind} write conflicts with {key} type {definition["type"]}')
        kinds = []
        if '\\(' in line or re.search(r'String\(format:|\.formatted\(|Text\([^\n]*format:', line): kinds.append('dynamic-format')
        if '\\(' in line and re.search(r'(?:count|Count|digits\(|arabicNumber\()', line) and re.search(r'[\u0600-\u06ff]', line):
            kinds.append('count-phrase-candidate')
        dynamic_setting = re.search(r'\bsession\.(?:string|bool|number)\((?!")|\b(?:key):\s*(?!")\w|\b(?:session\.)?values\[(?!")', line)
        if dynamic_setting or (path.endswith('/SettingsStore.swift') and re.search(r'for:\s*\w', line)):
            kinds.append('computed-setting-or-key-access')
        if re.search(r'\b(?:Text|Label|Button|NavigationLink|Toggle|Stepper|ShareLink|TextField|SecureField)\s*\(|\.foregroundStyle\(|\.background\(|\.font\(', line): kinds.append('UI-colour-text-action')
        if '·' in decoded and ('\\(' in decoded or '%' in decoded): kinds.append('dynamic-middle-dot')
        if re.search(r'\b(?:Color|UIColor|CGColor)\s*\(', line): kinds.append('colour-construction')
        if '"""' in line or re.search(r'#+"', line): kinds.append('raw-or-multiline-string')
        if kinds: inventory.append(dict(location=spot, kinds=kinds, source=line.strip(), status='manual-trace-required'))
    return failures, inventory, sorted(keys)


def run(root):
    app = root / 'Madar'
    project = json.loads(subprocess.check_output(['plutil', '-convert', 'json', '-o', '-', str(app/'Madar.xcodeproj/project.pbxproj')]))
    sources, resources, packages, targets = build_files(project, app)
    schema = json.loads((app/'Specification/settings-schema.json').read_text())
    tokens = json.loads((app/'Packages/MadarDesign/Sources/MadarDesign/Resources/design-tokens.json').read_text())
    failures, manual, source_keys, catalogs = [], [], set(), []
    session = uncomment((app/'App/AppSession.swift').read_text())
    supported_match = re.search(r'static let supportedKeys\s*=\s*\[([^\]]+)\]', session)
    if not supported_match: raise ValueError('supportedKeys no longer a literal list')
    supported = re.findall(r'"([\w.]+)"', supported_match[1])
    issues, definitions = schema_checks(schema, supported); failures.extend(issues)
    issues, measured = token_checks(tokens); failures.extend(issues)
    for copy in [root/'docs/HANDOFF/design-tokens.json', app/'Specification/design-tokens.json']:
        if json.loads(copy.read_text()) != tokens: failures.append(f'token resource differs from canonical {copy}')
    source_inventory = []
    for path in sources:
        relative = str(path.relative_to(root)); text = path.read_text()
        source_inventory.append(dict(path=relative, sha256=hashlib.sha256(path.read_bytes()).hexdigest()))
        if path.name in {'GeneratedTokens.swift', 'GeneratedMetrics.swift'}:
            if path.parent != app/'Packages/MadarDesign/Sources/MadarDesign': raise ValueError('unexpected generated exemption')
            continue  # Only declarations exempt; actual JSON above is independently checked.
        issues, entries, keys = scan_source(text, relative, definitions)
        failures.extend(issues); manual.extend(entries); source_keys.update(keys)
    for path in resources:
        if path.suffix != '.xcstrings': continue
        issues, values, groups = catalog_checks(json.loads(path.read_text()))
        failures.extend(f'{path.relative_to(root)}: {x}' for x in issues)
        catalogs.append(dict(path=str(path.relative_to(root)), values=values, pluralGroups=groups))
    reachability = json.loads((app/'scripts/m0-shipping-inventory.json').read_text())
    for entry in reachability['entrypoints']:
        path = root/entry['path']
        if path not in sources: failures.append(f'inventory source not shipping: {entry["path"]}')
        elif entry['anchor'] not in path.read_text(): failures.append(f'inventory anchor changed: {entry["path"]} {entry["anchor"]}')
    # The filtered settings/control proof is explicit, not inferred from JSON flags alone.
    customization = (app/'App/CustomizeMadar.swift').read_text()
    if 'guard AppSession.supportedKeys.contains(definition.key)' not in customization:
        failures.append('reachable settings no longer guarded by supportedKeys')
    if 'settingsKeys: Set(Self.supportedKeys), availability: .m0' not in session:
        failures.append('settings/room deep-link availability proof changed')
    return dict(scope='M0 static shipping checks; NOT complete acceptance', targets=targets,
                packages=[dict(path=p, product=n) for p,n in packages], sources=source_inventory,
                supportedKeys=supported, literalSettingKeys=sorted(source_keys),
                tokenPairsMeasured=measured, catalogs=catalogs, findings=failures,
                manualTrace=manual, reachability=reachability,
                exclusions=['test/probe executable targets', 'excluded QuranRoom.swift', 'external Adhan dependency source'],
                limits=['regex does not prove all rendered strings, computed settings or control reachability',
                        'UI inventory requires manual colour/background/font/action and count-phrase tracing',
                        'generated declarations exempt; canonical JSON parity and M0 pair math checked',
                        'no simulator, VoiceOver, Reduce Motion or physical-device proof'])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--json-output', type=Path, help='write reproducible inventory JSON')
    parser.add_argument('--require-complete', action='store_true', help='exit 2 if manual tracing remains')
    args = parser.parse_args()
    try: result = run(ROOT)
    except (ValueError, KeyError, TypeError, OSError, subprocess.CalledProcessError) as error:
        print(f'FAIL: shipping scope/check input unresolved: {error}'); return 1
    if args.json_output:
        args.json_output.parent.mkdir(parents=True, exist_ok=True)
        args.json_output.write_text(json.dumps(result, ensure_ascii=False, indent=2)+'\n')
    for finding in result['findings']: print(f'FAIL: {finding}')
    print(f"STATIC {'FAIL' if result['findings'] else 'PASS'}: {len(result['sources'])} shipping Swift files, {len(result['catalogs'])} catalogs, {len(result['tokenPairsMeasured'])} independently measured M0 token pairs")
    print(f"MANUAL TRACE REQUIRED: {len(result['manualTrace'])} source lines; no complete string/key/colour/action or M0 acceptance claim")
    return 1 if result['findings'] else 2 if args.require_complete and result['manualTrace'] else 0


if __name__ == '__main__': raise SystemExit(main())
