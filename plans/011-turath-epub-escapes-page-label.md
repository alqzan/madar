# Plan 011: Turath EPUB escapes the page label it writes into the book

> **Owner permission.** The owner's rule of 10 Nov 2026 said Turath code is
> never touched. On 11 Nov 2026 he allowed the Turath fixes found by this
> audit (decision D1 in `plans/README.md`). That permission covers exactly the
> two files in this plan's scope; touch no other Turath file.
>
> **Executor instructions**: Follow this plan step by step. Run every
> verification command and confirm the expected result before moving to the
> next step. If anything in the "STOP conditions" section occurs, stop and
> report — do not improvise. When done, update the status row for this plan
> in `plans/README.md` — unless a reviewer dispatched you and told you they
> maintain the index.
>
> **Drift check (run first)**: `git diff --stat 83c5e5b7..HEAD -- Madar/Packages/MadarCommands/Sources/MadarCommands/TurathBook.swift Madar/Packages/MadarCommands/Tests/MadarCommandsTests/TurathBookTests.swift`
> If either changed, compare the "Current state" excerpts against the live
> code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: none (owner permission given 11 Nov 2026, decision D1)
- **Category**: security / correctness
- **Planned at**: commit `83c5e5b7`, 2026-11-11

## Why this matters

A book downloaded from Turath is turned into an EPUB on the phone. Every piece
of server text is escaped before it is written into the book's XHTML, except
one: the volume name used in the printed-page label. It goes into an attribute
and into link text as it arrived. If a volume name ever contains `&`, `<` or
`"` (a data slip on the server is enough; no attacker is needed), the chapter
file becomes invalid XML and the book fails to open, or markup from the server
is rendered inside the reader. The escape function also lets through two code
points that XML 1.0 forbids (U+FFFE, U+FFFF).

## Current state

Paths are relative to the repository root (its folder name has Arabic
characters and a space: quote it in shell).

`Madar/Packages/MadarCommands/Sources/MadarCommands/TurathBook.swift:77` and `:92`:
the page's `volume` is a `String` read from the server field `vol` (string or
number) with no validation.

`TurathBook.swift:132-135`:

```swift
                let label = page.page.map { multiVolume ? "\(arabicDigits(page.volume))/\(arabicDigits(String($0)))" : arabicDigits(String($0)) }
                if let label {
                    body += "<span id=\"p-\(ordinal)\" epub:type=\"pagebreak\" role=\"doc-pagebreak\" title=\"\(label)\" aria-label=\"\(label)\"></span>"
                    pageList += "<li><a href=\"c\(n + 1).xhtml#p-\(ordinal)\">\(label)</a></li>"
```

`TurathBook.swift:211-226` (`static func escape(_ text: String) -> String`)
maps `&`, `<`, `>`, `"` to entities and has this default branch:

```swift
            default:
                // XML 1.0 forbids most control characters.
                if let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1, v < 0x20, v != 0x09 { continue }
                out.append(c)
```

`arabicDigits` (line 228) only swaps digits; other characters pass through.

The existing test to model on is
`Madar/Packages/MadarCommands/Tests/MadarCommandsTests/TurathBookTests.swift:38-60`
(`bookBecomesAValidDeterministicEPUBWithIndexPagesAndNotes`). It decodes the
fixture `book` (lines 18-24; three pages, `"vol":"1"` twice and `"vol":"2"`
once), builds the EPUB, writes it to a temp folder and checks
`EPUBBookFiles.printedShape(file:)` gives `pages == 3`, `volumes == 2`.

## Commands you will need

Run from the repository root.

| Purpose | Command | Expected on success |
|---|---|---|
| Turath tests | `swift test --package-path Madar/Packages/MadarCommands --filter TurathBookTests` | exit 0 |
| Whitespace | `git diff --check` | no output |

No simulator and no `xcodebuild` are needed.

## Scope

**In scope**: `TurathBook.swift` (line 132 and the default branch of `escape`),
`TurathBookTests.swift` (one new test).

**Out of scope**: every other Turath file (`MihbaraTurathView.swift`, the
catalogue, the download), `EPUBBookFiles.swift`, the EPUB layout, the fixture
constants already in the test file (build your variant from them, do not edit
them).

## Git workflow

Work on `main` unless your operator placed you in a worktree. One commit:
`[OWNER] <what is now true, with test counts> (claude, model: <your actual model id>, effort: <actual or "not exposed">)`. Do NOT push.

## Steps

### Step 1: Write the failing test first

Add to `TurathBookTests`:

```swift
    /// A volume name is server text like any other: markup characters in it must not break the book's XML.
    @Test func volumeNameWithMarkupCharactersStillGivesAReadableBook() throws {
        let text = try #require(String(data: book, encoding: .utf8)).replacingOccurrences(of: #""vol":"2""#, with: #""vol":"2 & \"<b>""#)
        let entry = try #require(try TurathCatalogue.decode(catalogue).first { $0.id == 12028 })
        let document = try TurathBookDocument.decode(Data(text.utf8), catalogue: entry)
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("TurathLabel-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let file = root.appendingPathComponent("book.epub"); try TurathEPUB.build(document).write(to: file)
        // Same shape as the plain fixture: three printed pages in two volumes.
        let shape = try #require(try EPUBBookFiles.printedShape(file: file))
        #expect(shape.pages == 3); #expect(shape.volumes == 2)
        #expect(TurathEPUB.escape("a\u{FFFE}b\u{FFFF}c") == "abc")
    }
```

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter TurathBookTests`
→ the new test **fails** (a thrown parse error, a wrong shape, or the last
expectation). If it passes before Step 2, that is a STOP condition.

### Step 2: Escape the label and drop the two forbidden code points

- Line 132: wrap both branches so the label is escaped once:

```swift
                let label = page.page.map { escape(multiVolume ? "\(arabicDigits(page.volume))/\(arabicDigits(String($0)))" : arabicDigits(String($0))) }
```

- In `escape`, add directly under the existing control-character line:

```swift
                if let v = c.unicodeScalars.first?.value, c.unicodeScalars.count == 1, v == 0xFFFE || v == 0xFFFF { continue }
```

**Verify**: `swift test --package-path Madar/Packages/MadarCommands --filter TurathBookTests`
→ exit 0, five tests (four existing plus the new one).

## Test plan

The new test's expected values come from the fixture's stated shape (three
printed pages, two volumes) and from XML 1.0, not from the code's output. The
existing `bookBecomesAValidDeterministicEPUB…` test must still pass: it proves
the bytes for a normal book are unchanged.

## Done criteria

- [ ] The new test failed before Step 2 and passes after it
- [ ] `swift test --package-path Madar/Packages/MadarCommands --filter TurathBookTests` exits 0 with 5 tests
- [ ] `git diff --check` prints nothing; only the two in-scope files are modified
- [ ] `plans/README.md` status row updated

## STOP conditions

- The change would need a Turath file outside this plan's scope.
- The new test passes before Step 2 (the EPUB reader is tolerant, so this test
  does not prove the defect): report it; do not weaken or delete the test.
- `"vol":"2"` is not found in the fixture text, or the replaced JSON does not
  decode.
- The existing deterministic-EPUB test fails after Step 2.

## Maintenance notes

- Other Turath findings (download memory, catalogue on the main thread,
  unswept download folder) are in the backlog of `plans/README.md`; they need
  the same owner gate.
- If a new place writes server text into XHTML, it must go through `escape`.
