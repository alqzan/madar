#!/usr/bin/env python3
"""RA2 proof: independent Foundation producers, then one synthetic app consumer."""
import json
import subprocess
import tempfile
import uuid
from pathlib import Path

root = Path(__file__).resolve().parents[1]
producer_package = root / 'Packages/MadarInbox'
consumer_package = root / 'Packages/MadarCommands'
for package, product in [(producer_package, 'MadarInboxProducer'), (consumer_package, 'MadarInboxConsumer')]:
    subprocess.run(['swift', 'build', '--package-path', str(package), '--product', product], check=True)


def binary(package, product):
    folder = subprocess.check_output(['swift', 'build', '--package-path', str(package), '--show-bin-path'], text=True).strip()
    return str(Path(folder) / product)


producer = binary(producer_package, 'MadarInboxProducer')
consumer = binary(consumer_package, 'MadarInboxConsumer')
links = subprocess.check_output(['otool', '-L', producer], text=True)
assert 'SwiftData' not in links and 'CoreData' not in links, links
with tempfile.TemporaryDirectory(prefix='MadarInboxSynthetic-') as folder:
    directory = Path(folder)
    generation = str(uuid.uuid4())
    ids = [str(uuid.uuid4()), str(uuid.uuid4())]
    processes = [subprocess.Popen([producer, str(directory / 'PendingInbox'), identity, source, generation, str(uuid.uuid4())],
                                 stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
                 for identity, source in zip(ids, ['notification', 'widget'])]
    outputs = [process.communicate(timeout=20) for process in processes]
    assert all(process.returncode == 0 for process in processes), outputs
    assert not list(directory.rglob('*.store')), 'A producer opened a writable store'
    assert len(list((directory / 'PendingInbox/pending').glob('*.jsonl'))) == 2
    # Same stable command identity may arrive in another immutable delivery file.
    subprocess.run([producer, str(directory / 'PendingInbox'), ids[0], 'notification', generation, str(uuid.uuid4())], check=True, capture_output=True)
    counts = json.loads(subprocess.check_output([consumer, folder, generation], text=True))
    assert counts == {'rows': 1, 'receipts': 2, 'statuses': ['applied', 'duplicate'], 'refreshes': 3, 'unacknowledged': 0}, counts
    report = {'fixtureVersion': 1, 'platform': 'macOS independent producer processes / one app consumer',
              'producerStoreFiles': 0, 'producerLinksSwiftData': False, 'sources': ['notification', 'widget'],
              'deliveries': 3, 'commandIDs': 2, 'counts': counts, 'passed': True,
              'boundary': 'Synthetic durable inbox and production bus/drainer only; no physical notification, widget, protection or app lifecycle test.'}
    output = root / 'Artifacts/inbox-process.json'
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_text(json.dumps(report, ensure_ascii=False, indent=2) + '\n')
    print(json.dumps(report, ensure_ascii=False))
