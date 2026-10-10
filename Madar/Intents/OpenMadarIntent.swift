import AppIntents

/// Navigation only. No unbuilt room parameters or data writes exposed in M0.
struct OpenMadarIntent: AppIntent {
    static let title: LocalizedStringResource = "افتح مدار"
    static let openAppWhenRun = true
    func perform() async throws -> some IntentResult { .result() }
}
