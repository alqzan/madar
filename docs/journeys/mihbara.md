# Mihbara journeys — M6

References: 13-r-mih, 19-qa; RMI fixes, RD2/RD4. Apply [common states](README.md).

| ID / planned test | Steps and expected outcomes | State cases | Device requirement |
|---|---|---|---|
| J13 / test_J13_bookImportReaderRecovery | Import allowed local file/paper metadata; preview/cancel/save, reject unsupported/DRM before permanent copy. Read/search/bookmark; change font/theme/mode then return by stable locator. Background/idle doesn't invent reading time. Long OCR cancel/kill/resume preserves source and completed pages. Delete book retains title/sessions/highlights; file deletion separate; no dead origin arrow. | 300 books/long titles, 760-page PDF, missing/corrupt/duplicate file, ZIP traversal, unavailable OCR, lock. | Store/simulator; actual iPhone Arabic OCR proof or hide entry, PDF/EPUB samples. |
| J14 / test_J14_historyPrivateNotesGoodreads | Preview Goodreads quoted/multiline/Arabic/missing-date CSV; import twice, preserve reviews and read-count without invented dates. Make private note/highlight/word with locator and title; refuse/unlock auth, export/reimport supported records. System dictionary only, translation only available pairs; no hints/edition matching/side-by-side v2. | Empty/large history, missing date/book, malformed columns, locked private note and diary-linked note. | Store/simulator and actual iPhone system lookup/availability. |

J16/J17/J18 required. Book files omitted from bulk backup per RD4, with explicit import recovery. Reader engine proof and licensed quotes/fonts precede claims of readiness.
