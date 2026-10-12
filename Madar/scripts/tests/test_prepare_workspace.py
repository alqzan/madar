import hashlib
import importlib.util
import json
from pathlib import Path
import plistlib
import tempfile
import unittest

SCRIPT = Path(__file__).resolve().parents[1] / 'prepare-workspace.py'
SPEC = importlib.util.spec_from_file_location('workspace_preparation', SCRIPT)
checks = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(checks)


def fixture(root):
    app = root / 'Madar/App'
    (app / 'Resources/Fonts').mkdir(parents=True)
    (root / 'Madar/docs').mkdir(parents=True)
    with (app / 'Info.plist').open('wb') as handle:
        plistlib.dump({'UIAppFonts': ['Regular.ttf', 'Bold.ttf']}, handle)
    fonts = [{'file': name, 'sha256': hashlib.sha256(data).hexdigest()}
             for name, data in [('Regular.ttf', b'regular'), ('Bold.ttf', b'bold')]]
    (root / 'Madar/docs/font-provenance.json').write_text(json.dumps({'fonts': fonts}))
    return app / 'Resources/Fonts'


class WorkspacePreparationTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name) / 'target'
        self.target = fixture(self.root)
        self.source = Path(self.temp.name) / 'source'
        self.origin = fixture(self.source)
        (self.origin / 'Regular.ttf').write_bytes(b'regular')
        (self.origin / 'Bold.ttf').write_bytes(b'bold')

    def test_missing_bold_reported_before_build_and_no_check_mutation(self):
        (self.target / 'Regular.ttf').write_bytes(b'regular')
        with self.assertRaisesRegex(checks.PreparationError, 'Missing resource: Bold.ttf'):
            checks.prepare(self.root)
        self.assertFalse((self.target / 'Bold.ttf').exists())

    def test_all_missing_fonts_copied_and_second_run_is_read_only(self):
        self.assertEqual(checks.prepare(self.root, self.source), (2, 2))
        self.assertEqual((self.target / 'Bold.ttf').read_bytes(), b'bold')
        before = (self.target / 'Regular.ttf').stat().st_mtime_ns
        self.assertEqual(checks.prepare(self.root), (2, 0))
        self.assertEqual((self.target / 'Regular.ttf').stat().st_mtime_ns, before)

    def test_bad_source_prevents_partial_preparation(self):
        (self.origin / 'Bold.ttf').write_bytes(b'wrong')
        with self.assertRaisesRegex(checks.PreparationError, 'source resource: Bold.ttf'):
            checks.prepare(self.root, self.source)
        self.assertEqual(list(self.target.iterdir()), [])

    def test_conflicting_local_file_preserved_and_missing_file_not_copied(self):
        (self.target / 'Regular.ttf').write_bytes(b'user-file')
        with self.assertRaisesRegex(checks.PreparationError, 'preserved.*Regular.ttf'):
            checks.prepare(self.root, self.source)
        self.assertEqual((self.target / 'Regular.ttf').read_bytes(), b'user-file')
        self.assertFalse((self.target / 'Bold.ttf').exists())

    def test_registered_font_without_provenance_fails(self):
        with (self.root / 'Madar/App/Info.plist').open('wb') as handle:
            plistlib.dump({'UIAppFonts': ['Regular.ttf', 'Bold.ttf', 'New.ttf']}, handle)
        with self.assertRaisesRegex(checks.PreparationError, 'disagree'):
            checks.prepare(self.root, self.source)

    def test_license_resource_also_required_and_checked(self):
        path = self.root / 'Madar/docs/font-provenance.json'
        metadata = json.loads(path.read_text())
        metadata['fonts'][0].update(licenseFile='LICENSE.txt',
                                  licenseSha256=hashlib.sha256(b'license').hexdigest())
        path.write_text(json.dumps(metadata))
        with self.assertRaisesRegex(checks.PreparationError, 'source resource: LICENSE.txt'):
            checks.prepare(self.root, self.source)
        (self.origin / 'LICENSE.txt').write_bytes(b'license')
        self.assertEqual(checks.prepare(self.root, self.source), (3, 3))


if __name__ == '__main__':
    unittest.main()
