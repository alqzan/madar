import Foundation
import Testing
@testable import MadarData

/// Alerts show `localizedDescription`; the user must never read "MadarData.DataError error N".
struct DataErrorMessageTests {
    @Test func everyCaseReadsInArabic() {
        let cases: [DataError] = [.unknownModel("X"), .invalidValue("bad key"), .newerStore, .legacyStoreRequiresAdoption, .missingAppGroup, .undoExpired, .invalidBackup, .authenticationFailed, .unsupportedBackup]
        for error in cases {
            let text = error.localizedDescription
            #expect(!text.contains("DataError"), "\(error)")
            #expect(text.unicodeScalars.contains { (0x0600...0x06FF).contains($0.value) }, "\(error)")
        }
    }
    @Test func arabicInvalidValueKeepsItsOwnMessage() {
        #expect(DataError.invalidValue("المذكرات مقفلة").localizedDescription == "المذكرات مقفلة")
        #expect(DataError.invalidValue("bad key").localizedDescription != "bad key")
    }
}
