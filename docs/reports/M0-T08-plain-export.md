# M0-T08 — Plain portable export

Implemented by Codex Sol, Standard high, 2026-10-11, on `m0-s1-plain-export`, based on RA4 candidate `b3a809d`. Root integration and independent Top section review remain required.

Authority: RA3, `17-data.md` backup logical rows/media validation, and `docs/design/M0-local-inbox.md` plain-export passage. This adds the lean M0 plain export while retaining the existing encrypted backup/restore.

The Settings backup screen has «تصدير بياناتك», «جهّز ملف التصدير» and a native ShareLink «احفظ التصدير أو شاركه». The explanation states that the ZIP is unencrypted, includes JSONL records and media, and omits device settings and the app lock. No password or backup-key setup is needed. There is no plain-import UI in this task.

Portable format v1:

- A standard ZIP (method 0, stored; UTF-8 paths), readable by ordinary ZIP tools.
- `manifest.json`: `magic: MADAR-PLAIN`, `formatVersion: 1`, current `storeSchemaVersion`, ISO8601 `createdAt`, an explicit count for each synced model including zero counts, and `files` entries with `path`, `bytes`, and SHA-256.
- `data/<Model>.jsonl`: one canonical UTF-8 JSON object per line, sorted by UUID. `MoneyTransaction` is the corrected current model name.
- `media/<UUID>`: exact original photo/audio/file bytes. The JSONL Media row has `data: null`; manifest and Media row hashes/sizes must both match.
- Device models, command receipts, lock settings and the installation identity `DeviceSetting(sys.writerID)` are absent. The common record `writerID` remains fact provenance; no generation ID, live-store path, lock file, or device binding is serialized.

The coordinator quiesces app writers and holds the existing maintenance lease while capturing logical rows. Encoding runs off the main actor. A completed share URL points to a dedicated `Backups/PlainExports/<UUID>/Madar-<date>-plain.zip`, never live SQLite. Outputs use private file/directory permissions and complete file protection on iOS. Cancellation deletes only the current partial export directory and resumes the app writers; previous completed share files remain. Plain export does not configure encryption, update the encrypted backup status, or enter its retention catalog.

The validation API reads without filesystem extraction, rejects unsupported ZIP variants, path traversal, duplicate ZIP entries, truncation, trailing bytes, CRC mismatch, wrong/newer versions, missing files, extra files, wrong model counts, media hash mismatch, and invalid rows. It validates decoded rows in an isolated in-memory container. It does not treat unencrypted hashes as authentication.

Verified command:

```text
swift test --package-path Madar/Packages/MadarData
✔ Suite PortableExportTests passed after 4.235 seconds.
✔ Suite DataTests passed after 6.359 seconds.
✔ Suite ManagedBackupTests passed after 9.106 seconds.
✔ Test run with 53 tests in 5 suites passed after 9.106 seconds.
```

Raw output: `/tmp/madar-plain-data-tests.log` (local untracked evidence; copy to root Artifacts if needed).

The 8 new tests cover empty exports with all 55 counts, every synced model plus tombstones/aliases/photo/audio, complete row fingerprints after merge into an empty store and idempotent second merge, an independently known photo SHA-256, malformed versions/counts/missing files/typed rows, ZIP corruption/traversal/trailing bytes, media tampering with an updated ZIP CRC, device exclusions and writer lifecycle, cancellation cleanup, and system `/usr/bin/unzip -t` compatibility. All inherited encrypted backup and RA4 tests passed in the same run.

Also verified: `git diff --check` produced no findings.

Not tested by this implementing agent: app xcodebuild and host integration execution, simulator default/AX3/dark screenshots, share-sheet/file save interaction, iPhone file protection, physical M0 gate, or independent Top review. Root owns those checks. Host test `testPlainExportUIAdapterNeedsNoPasswordAndResumesSession` was added for the actual service/session path. UI identifiers: `plain-export-now`, `plain-export-share`.
