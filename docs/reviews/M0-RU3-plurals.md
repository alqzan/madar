# M0 inherited RU3 fix — scope review

Verdict: approve. Production: GPT-6.1 Sol high, cede9ee (integrated equivalent a4b3a4a). Root reviewed the narrow diff and actual simulator captures; no findings. This closes the specific inherited CustomizeMadar count defect recorded by the M0-T04 review, not general localization or the M0 gate.

The compiled Arabic String Catalog includes zero, one, two, few, many and other. The unchanged settings count selects grammar, while session.digits supplies the chosen numeral style. Native interpolation isolates numeric text for RTL. Explicit linguistic fixtures cover 0/1/2/3/11/100 in Hindi and western digits and load the shipped app resource.

Evidence: signed xcodebuild on iPhone 17 Pro simulator, iOS 26.5, selected CustomizationCopyTests and FoundationUITests/test_M0S2_RU3_CustomizationPluralsAtDefaultAndAX3: hosted test passed (12 expectations), UI test passed (114.612 s), ** TEST SUCCEEDED **. Actual settings edits and relaunch in fresh fixtures verify 0 → 1 → 2 → western 3 at L and AX3. Eight captures exported; root viewed western-three at L and AX3 and confirmed readable complete text with normal wrapping. Layout is otherwise unchanged from the accepted shell.

Root evidence copies: Madar/Artifacts/continue-plurals-runtime.log and continue-plurals-images/manifest.json. Candidate xcresult remains in the attached m0-arabic-plurals worktree. Not tested here: physical iPhone, VoiceOver, other application strings, AX5 or dark mode for this copy-only fix (unchanged shell coverage is in M0-lean-shell.md).
