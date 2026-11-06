import Foundation

/// §7.1 «الأيام القادمة» automatic source «تمام الجزء التالي»: the juz the user is working in and how many
/// Mushaf pages of it are not yet complete. The day itself comes from `QuranProgressEngine.forecast` with the
/// same 28-day pace the journey uses, so the lobby and the Quran room never disagree.
public struct QuranNextJuz: Equatable, Sendable {
    public let juz: Int
    public let remainingPages: Int
    public init(juz: Int, remainingPages: Int) { self.juz = juz; self.remainingPages = remainingPages }
}

extension QuranProgressEngine {
    /// The juz holding `frontierAyah` (the first ayah not yet memorised from the plan's start). Its remaining pages are
    /// the pages that carry any ayah of that juz and are not complete. A page shared with the neighbouring juz counts once.
    public static func nextJuz(frontierAyah: Int?, coverage: QuranCoverage, pages: [QuranCoveragePage],
                               juzSegments: [QuranCycleSegment]) -> QuranNextJuz? {
        guard let frontierAyah,
              let segment = juzSegments.first(where: { (($0.ayahs.first)...($0.ayahs.last)).contains(frontierAyah) }),
              !coverage.completedJuz.contains(segment.number) else { return nil }
        let span = segment.ayahs.first...segment.ayahs.last
        let remaining = pages.filter { page in
            !coverage.completedPages.contains(page.number) && page.ayahIDs.contains { span.contains($0) }
        }.count
        return remaining > 0 ? .init(juz: segment.number, remainingPages: remaining) : nil
    }
}
