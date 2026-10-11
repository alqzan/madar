"""Negative fixtures for the bounded shipping checks; no app/simulator dependency."""
import importlib.util
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
            sources, _, _, _ = checks.build_files(project, root)
            self.assertEqual(sources, [root/'Included.swift'])
            project['objects']['included']['sourceTree'] = 'UNRESOLVED'
            with self.assertRaisesRegex(ValueError, 'unsupported sourceTree'): checks.build_files(project, root)


if __name__ == '__main__': unittest.main()
