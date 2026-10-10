#!/usr/bin/env python3
"""Real OS URL delivery into a terminated simulator app; UI test confirms destination."""
import os
import subprocess
import time
from pathlib import Path

root = Path(__file__).resolve().parents[1]
device = os.environ.get('SIMULATOR', '412F4437-7BD7-44D1-AA3D-2B7158090E14')
result = root / f'Artifacts/M0-deep-link-{int(time.time())}.xcresult'
log = root / 'Artifacts/deep-link-test.log'
command = ['xcodebuild', '-project', 'Madar.xcodeproj', '-scheme', 'Madar', '-destination', f'platform=iOS Simulator,id={device}', '-derivedDataPath', 'DerivedData', '-resultBundlePath', str(result), '-only-testing:MadarUITests/FoundationUITests/testColdSettingsLinkOpenedByOS', 'CODE_SIGN_IDENTITY=-', 'CODE_SIGNING_ALLOWED=YES', 'test']
environment = dict(os.environ, TEST_RUNNER_MADAR_TEST_EXTERNAL_LINK='1')
with log.open('w') as output:
    process = subprocess.Popen(command, cwd=root, env=environment, stdout=output, stderr=subprocess.STDOUT)
    deadline = time.monotonic() + 180
    delivered = False
    while process.poll() is None:
        if not delivered and 'MADAR_DEEP_LINK_READY' in log.read_text():
            subprocess.run(['xcrun', 'simctl', 'openurl', device, 'madar://settings/core/core.theme'], check=True)
            delivered = True
        if time.monotonic() > deadline:
            process.terminate()
            raise TimeoutError(f'URL delivery test: {log}')
        time.sleep(0.1)
    assert delivered and process.returncode == 0, f'URL test failed or skipped; inspect {log}'
print(f'Cold URL delivery passed: {result}')
