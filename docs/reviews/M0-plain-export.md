# M0-T08 — Plain portable export section review

Verdict: **approve** for the scoped export implementation. **No findings.** Root app/host/UI validation remains required before integration; this is not the M0 gate.

Independent review of `b3a809d..2b8c326` (one commit, 416 changed lines), against the M0-T08 card, RA3 and the plain-export contract in `docs/design/M0-local-inbox.md`. RA4 ancestors were excluded from this review.

- Explicit versioned manifest includes every synced-model count, including zeros. Canonical per-model JSONL retains UUIDs, timestamps, tombstones, aliases and foreign keys; exact original media bytes are validated by both manifest and Media row hashes/sizes.
- The ZIP uses standard stored entries with UTF-8 paths, local/central agreement, CRC-32, strict end records and a 512 MiB input/output limit. Validation rejects duplicate/traversal paths, unsupported variants, truncation/trailing bytes and mismatched counts/hashes without filesystem extraction.
- The coordinator captures logical rows through the existing app writer barrier and store lease. Encoding runs off the main actor; the share URL is a separate private ZIP. No live SQLite, generation binding, device settings, installation setting, receipts or lock state is exported. Cancellation cleans only the current partial directory and resumes writers.
- Encrypted export/restore retains its authenticated header/schema check. The factored logical-file validation keeps original manifest/file/model/count/hash validation before forward mapping. Plain export does not configure encryption or change encrypted status/retention.
- Arabic UI explains that the file is unencrypted and exposes native ShareLink. Existing shared SwiftUI components are reused. Added host integration exercises the actual service/session path; root still needs to execute it and inspect default/AX3/dark UI and the share/save flow.

Independent command, exit 0:

```
swift test --package-path Madar/Packages/MadarData --filter PortableExportTests
✔ Suite PortableExportTests passed after 0.930 seconds.
✔ Test run with 8 tests in 1 suite passed after 0.930 seconds.
```

Raw independent output: `/tmp/madar-plain-independent-review-tests.log`. Also inspected implementing-agent full-run evidence `/tmp/madar-plain-data-tests.log`: `53 tests in 5 suites passed after 9.106 seconds`, including inherited encrypted backup and RA4 tests. That full run was not repeated by this reviewer. `git diff --check` passed.

Not tested here: app build, host integration execution, simulator screenshots, ShareLink save interaction, iPhone protection/signed run, owner data or physical M0 gate. No production source or shared-root branch was changed.
