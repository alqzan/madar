"""Negative fixtures for the bounded shipping checks; no app/simulator dependency."""
import importlib.util
import json
import tempfile
import unittest
from unittest.mock import patch
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / 'check-shipping-sources.py'
SPEC = importlib.util.spec_from_file_location('shipping_checks', SCRIPT)
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


def tokens():
    return {'typeScale': {'minimumTextSize': 11, 'body': {'size': 14}},
            'rooms': {'bahw': {'light': {'ink': '#000000', 'bg': '#FFFFFF'}}},
            'contrast': {'pairs': [{'fg':'rooms.bahw.light.ink', 'bg':'rooms.bahw.light.bg',
                                   'use':'small', 'min':4.5, 'ratio':21.0}]}}


class ShippingCheckTests(unittest.TestCase):
    def test_complete_mode_rejects_manual_trace_even_with_no_static_findings(self):
        result = {'sources':[], 'catalogs':[], 'tokenPairsMeasured':[], 'findings':[], 'manualTrace':[{'status':'manual-trace-required'}]}
        with patch.object(checks, 'run', return_value=result), patch('sys.argv', ['checker','--require-complete']), patch('builtins.print'):
            self.assertEqual(checks.main(), 2)

    def test_black_white_ratio_and_alpha_threshold_ignore_declared_ratio(self):
        fixture = tokens()
        self.assertEqual(checks.contrast(fixture, 'rooms.bahw.light.ink', 'rooms.bahw.light.bg'), 21)
        fixture['rooms']['bahw']['light']['ink'] = 'rgba(0,0,0,.5)'
        # Half-alpha black over white is gray, independently below the required 4.5.
        issues, measured = checks.token_checks(fixture)
        self.assertTrue(any('below 4.5' in issue for issue in issues))
        self.assertLess(measured[0]['calculatedRatio'], 4.5)
        self.assertTrue(any('declared ratio drift' in issue for issue in issues))

    def test_token_types_minimum_and_unknown_pair_fail(self):
        fixture = tokens(); fixture['typeScale']['body']['size'] = 10.5
        fixture['contrast']['pairs'][0]['use'] = 'decorative-text'
        issues, _ = checks.token_checks(fixture)
        self.assertTrue(any('below 11' in issue for issue in issues))
        self.assertTrue(any('invalid pair use' in issue for issue in issues))
        fixture['contrast']['pairs'][0]['fg'] = False
        issues, _ = checks.token_checks(fixture)
        self.assertTrue(any('field types' in issue for issue in issues))

    def test_alpha_background_requires_underlying_colour(self):
        fixture = tokens(); fixture['rooms']['bahw']['light']['bg'] = 'rgba(255,255,255,.5)'
        with self.assertRaisesRegex(ValueError, 'underlying'):
            checks.contrast(fixture, 'rooms.bahw.light.ink', 'rooms.bahw.light.bg')

    def test_catalog_every_plural_leaf_and_missing_category(self):
        variations = {name: {'stringUnit': {'value': 'تعديلات'}} for name in checks.PLURALS}
        catalog = {'strings': {'count': {'localizations': {'ar': {'variations': {'plural': variations}}}}}}
        issues, values, groups = checks.catalog_checks(catalog)
        self.assertEqual(issues, []); self.assertEqual((len(values), groups), (6, 1))
        variations['many']['stringUnit']['value'] = '١١ · ١٢'
        del variations['two']
        issues, _, _ = checks.catalog_checks(catalog)
        self.assertTrue(any('numeric middle dot' in issue for issue in issues))
        self.assertTrue(any('categories incomplete' in issue for issue in issues))

    def test_literal_bad_colour_font_setting_and_dynamic_not_silently_green(self):
        definitions = {'core.faceIDLock': {'type':'choice', 'default':'notesOnly'}}
        source = '''// ١ · ٢ ignored comment
Text("١ · ٢").font(.system(size: 10))
Text("value").foregroundStyle(.red)
session.bool("core.faceIDLock")
session.string("core.missing")
session.set(.bool(true), key: "core.faceIDLock")
Text("\\(count) · pages")
session.string(definition.key)
Text("\\(digits(count)) سجلًّا")
'''
        issues, manual, _ = checks.scan_source(source, 'Madar/App/Test.swift', definitions)
        self.assertFalse(any(':1:' in issue for issue in issues))
        for phrase in ['numeric middle dot','below 11','colour value','bool read','unknown setting','bool write','catalog plurals']:
            self.assertTrue(any(phrase in issue for issue in issues), phrase)
        self.assertTrue(any('dynamic-middle-dot' in item['kinds'] for item in manual))
        self.assertTrue(any('computed-setting-or-key-access' in item['kinds'] for item in manual))

    def test_default_types_and_cut_supported_key_fail(self):
        schema = {'settings':[{'key':'core.lock','type':'choice','default':True,'options':[{'value':1}], 'availability':'v2'},
                              {'key':'core.offset','type':'int','default':9,'range':[-2,2]}]}
        issues, _ = checks.schema_checks(schema, ['core.lock','core.unknown'])
        for phrase in ['invalid default','cut key','unknown supported']:
            self.assertTrue(any(phrase in issue for issue in issues), phrase)

    def test_build_scope_uses_phases_not_unlisted_swift_and_unknown_fails(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); (root/'Included.swift').write_text(''); (root/'Excluded.swift').write_text('')
            project = {'rootObject':'project','objects': {
                'project':{'isa':'PBXProject','mainGroup':'group'},
                'group':{'isa':'PBXGroup','children':['included','excluded']},
                'included':{'isa':'PBXFileReference','path':'Included.swift'},
                'excluded':{'isa':'PBXFileReference','path':'Excluded.swift'},
                'build':{'isa':'PBXBuildFile','fileRef':'included'},
                'phase':{'isa':'PBXSourcesBuildPhase','files':['build']},
                'app':{'isa':'PBXNativeTarget','name':'Madar','productType':'com.apple.product-type.application','buildPhases':['phase']},
                'widget':{'isa':'PBXNativeTarget','name':'MadarWidgets','productType':'com.apple.product-type.app-extension','buildPhases':[]}}}
            sources, _, _, _, _ = checks.build_files(project, root)
            self.assertEqual(sources, [root/'Included.swift'])
            project['objects']['included']['sourceTree'] = 'UNRESOLVED'
            with self.assertRaisesRegex(ValueError, 'unsupported sourceTree'): checks.build_files(project, root)

    def test_remote_readium_product_requires_matching_exact_pin(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            url = 'https://github.com/readium/swift-toolkit.git'
            project = {'rootObject':'project','objects': {
                'project':{'isa':'PBXProject','mainGroup':'group','packageReferences':['package']},
                'group':{'isa':'PBXGroup','children':[]},
                'package':{'isa':'XCRemoteSwiftPackageReference','repositoryURL':url,
                           'requirement':{'kind':'exactVersion','version':'3.11.1'}},
                'product':{'isa':'XCSwiftPackageProductDependency','productName':'ReadiumNavigator','package':'package'},
                'app':{'isa':'PBXNativeTarget','name':'Madar','productType':'com.apple.product-type.application',
                       'buildPhases':[],'packageProductDependencies':['product']},
                'widget':{'isa':'PBXNativeTarget','name':'MadarWidgets','productType':'com.apple.product-type.app-extension',
                          'buildPhases':[]}}}
            with self.assertRaises(FileNotFoundError): checks.build_files(project, root)

            lock = root/'Madar.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved'
            lock.parent.mkdir(parents=True)
            lock.write_text(json.dumps({'version':3,'pins':[{
                'identity':'swift-toolkit','kind':'remoteSourceControl','location':url,
                'state':{'revision':'a'*40,'version':'3.11.1'}}]}))
            _, _, _, remote_products, targets = checks.build_files(project, root)
            self.assertEqual(remote_products, [(url,'ReadiumNavigator','3.11.1','a'*40)])
            self.assertEqual(set(targets), {'Madar','MadarWidgets'})

            project['objects']['package']['requirement']['version'] = '3.11.0'
            with self.assertRaisesRegex(ValueError, 'not pinned to its exact Xcode requirement'):
                checks.build_files(project, root)

    def test_M0L01_main_to_helper_is_rejected_not_silently_omitted(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory); package = root/'Packages/Main'
            for target in ['Main','Helper']: (package/'Sources'/target).mkdir(parents=True)
            (package/'Sources/Main/Main.swift').write_text('import Helper')
            helper = package/'Sources/Helper/File.swift'
            helper.write_text('Text("bad").foregroundStyle(.red)')
            (package/'Package.swift').write_text('''import PackageDescription
let package = Package(name: "Main", products: [.library(name: "Main", targets: ["Main"])],
targets: [.target(name: "Main", dependencies: ["Helper"]), .target(name: "Helper")])''')
            project = {'rootObject':'project','objects': {
                'project':{'isa':'PBXProject','mainGroup':'group','packageReferences':['package']},
                'group':{'isa':'PBXGroup','children':[]},
                'package':{'isa':'XCLocalSwiftPackageReference','relativePath':'Packages/Main'},
                'product':{'isa':'XCSwiftPackageProductDependency','productName':'Main'},
                'app':{'isa':'PBXNativeTarget','name':'Madar','productType':'com.apple.product-type.application','buildPhases':[], 'packageProductDependencies':['product']},
                'widget':{'isa':'PBXNativeTarget','name':'MadarWidgets','productType':'com.apple.product-type.app-extension','buildPhases':[]}}}
            # Independent known violation in Helper must never disappear behind a green scope.
            self.assertTrue(any('colour value' in x for x in checks.scan_source(helper.read_text(), 'Helper/File.swift', {})[0]))
            with self.assertRaisesRegex(ValueError, 'Main -> Helper'):
                checks.build_files(project, root)

    def test_M0L01_unsupported_dependency_forms_fail_closed(self):
        for declaration in ['(name: "Main", dependencies: dependencyList)',
                            '(name: "Main", dependencies : ["Main"] + extraDependencies)',
                            '(name: "Main", dependencies: [.target(name: "Helper")])',
                            '(name: "Main", dependencies: [.product(name: "Mystery", package: "unknown")])',
                            '(name: "Main", dependencies: ["NotEnumerated"])']:
            with self.subTest(declaration=declaration), self.assertRaises(ValueError):
                checks.check_target_dependencies(declaration, declaration, 'Main', {'Main'})

    def test_M0L01_computed_suffix_cannot_omit_violating_target(self):
        expressions = [
            '["MadarCore"] + extraDependencies',
            '["MadarCore"] + (includeHelper ? ["Helper"] : [])',
            '["MadarCore"].isEmpty ? extraDependencies : ["MadarCore"]',
            '["MadarCore"].map { $0 } + extraDependencies',
            '["MadarCore"] /* boundary */ + extraDependencies',
            '["MadarCore"]\n + extraDependencies',
        ]
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            for package, target in [('Main', 'Main'), ('Main', 'Helper'), ('MadarCore', 'MadarCore')]:
                source = root/'Packages'/package/'Sources'/target
                source.mkdir(parents=True)
                (source/'File.swift').write_text('Text("bad").foregroundStyle(.red)' if target == 'Helper' else '')
            helper = root/'Packages/Main/Sources/Helper/File.swift'
            # This independently detectable violation cannot be hidden by accepting
            # an enumerated literal prefix of a computed dependency expression.
            self.assertTrue(any('colour value' in x for x in checks.scan_source(helper.read_text(), 'Helper/File.swift', {})[0]))
            (root/'Packages/MadarCore/Package.swift').write_text('''import PackageDescription
let package = Package(name: "MadarCore", products: [.library(name: "MadarCore", targets: ["MadarCore"])],
targets: [.target(name: "MadarCore")])''')
            project = {'rootObject':'project','objects': {
                'project':{'isa':'PBXProject','mainGroup':'group','packageReferences':['main','core']},
                'group':{'isa':'PBXGroup','children':[]},
                'main':{'isa':'XCLocalSwiftPackageReference','relativePath':'Packages/Main'},
                'core':{'isa':'XCLocalSwiftPackageReference','relativePath':'Packages/MadarCore'},
                'mainProduct':{'isa':'XCSwiftPackageProductDependency','productName':'Main'},
                'coreProduct':{'isa':'XCSwiftPackageProductDependency','productName':'MadarCore'},
                'app':{'isa':'PBXNativeTarget','name':'Madar','productType':'com.apple.product-type.application','buildPhases':[], 'packageProductDependencies':['mainProduct','coreProduct']},
                'widget':{'isa':'PBXNativeTarget','name':'MadarWidgets','productType':'com.apple.product-type.app-extension','buildPhases':[]}}}
            for expression in expressions:
                with self.subTest(expression=expression):
                    (root/'Packages/Main/Package.swift').write_text('''import PackageDescription
let extraDependencies = ["Helper"]
let includeHelper = true
let package = Package(name: "Main", products: [.library(name: "Main", targets: ["Main"])],
targets: [.target(name: "Main", dependencies: ''' + expression + '''), .target(name: "Helper")])''')
                    with self.assertRaisesRegex(ValueError, 'computed target dependencies'):
                        checks.build_files(project, root)

    def test_M0L01_literal_dependency_argument_boundaries_remain_supported(self):
        for declaration in ['(name: "Main", dependencies: ["MadarCore"])',
                            '(name: "Main", dependencies: ["MadarCore"], resources: [.process("Resources")])',
                            '(name: "Main", dependencies: ["MadarCore"],)']:
            with self.subTest(declaration=declaration):
                checks.check_target_dependencies(declaration, declaration, 'Main', {'Main', 'MadarCore'})


if __name__ == '__main__': unittest.main()
