import Foundation
import Testing
@testable import MadarCore

/// Rules from the owner (4 Nov 2026): varied wording, never the same sentence two days running, never blame.
@Suite struct NudgeWordingTests {
    private func days(_ count: Int) -> [GregorianDay] {
        let first = try! GregorianDay("2026-11-04")
        return (0..<count).map { first.adding(days: $0) }
    }

    @Test func theSameDayAlwaysReadsTheSame() {
        for moment in NudgeWording.Moment.allCases {
            for day in days(10) {
                #expect(NudgeWording.body(moment, dayKey: day.description) == NudgeWording.body(moment, dayKey: day.description))
            }
        }
    }

    @Test func noSentenceRepeatsOnConsecutiveDays() {
        for moment in NudgeWording.Moment.allCases {
            let list = days(200)
            for (yesterday, today) in zip(list, list.dropFirst()) {
                #expect(NudgeWording.body(moment, dayKey: yesterday.description) != NudgeWording.body(moment, dayKey: today.description),
                        "\(moment) repeated on \(today)")
            }
        }
    }

    @Test func everyVariantAppearsAcrossAMonthOrTwo() {
        for moment in NudgeWording.Moment.allCases {
            let shown = Set(days(120).map { NudgeWording.body(moment, dayKey: $0.description) })
            #expect(shown == Set(NudgeWording.variants(moment)), "\(moment) leaves a variant unused")
        }
    }

    @Test func wordingNeverBlamesAndKeepsTheDigitRule() {
        let blame = ["قصّرت", "قصرت", "فاتك", "فاتتك", "نسيت", "أهملت", "تأخرت", "لماذا لم", "يجب أن", "لازم"]
        for moment in NudgeWording.Moment.allCases {
            let variants = NudgeWording.variants(moment)
            #expect(Set(variants).count == variants.count)
            #expect(variants.count >= 4)
            for text in variants {
                for word in blame { #expect(!text.contains(word), "«\(text)» blames with \(word)") }
                #expect(!text.contains("·"))
            }
        }
    }

    @Test func aMalformedDayKeyStillGivesAVariant() {
        #expect(NudgeWording.variants(.diaryLine).contains(NudgeWording.body(.diaryLine, dayKey: "not-a-day")))
    }
}
