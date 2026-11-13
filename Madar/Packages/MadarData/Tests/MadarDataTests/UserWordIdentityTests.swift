import Testing
@testable import MadarData

/// T07 / quick win 33: «على» and «علي» are different words; the expected values are plain Arabic spelling.
struct UserWordIdentityTests {
    @Test func alefMaqsuraAndYaAreDifferentWords() {
        #expect(UserWordIdentity.normalizedWord("على") != UserWordIdentity.normalizedWord("علي"))
    }
    @Test func taMarbutaAndHaAreDifferentWords() {
        #expect(UserWordIdentity.normalizedWord("مدرسة") != UserWordIdentity.normalizedWord("مدرسه"))
    }
    @Test func hamzaFormsOfAlefStillMatch() {
        #expect(UserWordIdentity.normalizedWord("أحمد") == UserWordIdentity.normalizedWord("احمد"))
    }
}
