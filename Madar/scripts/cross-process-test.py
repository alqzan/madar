#!/usr/bin/env python3
import json
import subprocess
import tempfile
import time
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
package = root/'Packages/MadarCommands'
subprocess.run(['swift', 'build', '--package-path', str(package), '--product', 'MadarCommandProbe'], check=True)
binary_dir = subprocess.check_output(['swift', 'build', '--package-path', str(package), '--show-bin-path'], text=True).strip()
probe = str(Path(binary_dir)/'MadarCommandProbe')
with tempfile.TemporaryDirectory(prefix='Madar2SyntheticConcurrency-') as folder:
    store = str(Path(folder)/'Store')
    gate = Path(folder)/'go'
    subprocess.run([probe, 'prepare', store], check=True, capture_output=True)
    ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    processes = [subprocess.Popen([probe, 'write', store, identity, source, str(gate)], stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                 for identity, source in zip(ids, ['notification', 'widget'])]
    deadline = time.monotonic()+20
    while not all(gate.with_suffix('.'+identity).exists() for identity in ids):
        if any(process.poll() is not None for process in processes):
            raise RuntimeError([process.communicate() for process in processes])
        if time.monotonic() > deadline: raise TimeoutError('probe preparation')
        time.sleep(0.01)
    gate.touch()
    outputs = [process.communicate(timeout=20) for process in processes]
    assert all(process.returncode == 0 for process in processes), outputs
    statuses = sorted(stdout.strip() for stdout, _ in outputs)
    counts = json.loads(subprocess.check_output([probe, 'inspect', store], text=True))
    assert statuses == ['applied', 'duplicate'], (statuses, outputs)
    assert counts == {'rows': 1, 'receipts': 1}, counts
    report = {'fixtureVersion': 1, 'platform': 'macOS native processes', 'sources': ['notification', 'widget'],
              'statuses': statuses, 'counts': counts, 'passed': True,
              'boundary': 'Real independent processes share temporary stores and the app command adapter. This is not physical-device Intent or notification delivery.'}
    out = root/'Artifacts/cross-process.json'; out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(report, ensure_ascii=False, indent=2)+'\n')
    print(json.dumps(report, ensure_ascii=False))
