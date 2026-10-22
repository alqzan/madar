import Testing
@testable import MadarCommands

/// Page labels shaped as Turath prints them in a three-volume set: «ج/ص», with an unlabelled introduction.
struct BookVolumesTests {
    let labels = ["مقدمة", "1/1", "1/2", "1/3", "2/1", "2/2", "فهرس", "3/1", "3/2"]

    @Test func volumesComeInReadingOrder() {
        #expect(BookVolumes.order(labels) == ["1", "2", "3"])
        #expect(BookVolumes.key("٢/١٥") == "٢")
        #expect(BookVolumes.key("15") == nil)
    }

    @Test func pagesWithoutALabelBelongToTheVolumeBefore() {
        #expect(BookVolumes.volume(ofPage: 0, labels: labels) == 0)
        #expect(BookVolumes.volume(ofPage: 5, labels: labels) == 1)
        #expect(BookVolumes.volume(ofPage: 6, labels: labels) == 1)
        #expect(BookVolumes.volume(ofPage: 8, labels: labels) == 2)
        #expect(BookVolumes.volume(ofPage: 2, labels: ["1", "2", "3"]) == nil)
    }

    @Test func tappingAVolumeOpensItsFirstPageUnlessTheSavedPlaceIsInside() {
        // Saved in volume 2 (page «2/2»): tapping volume 2 keeps the place, tapping volume 3 opens «3/1».
        #expect(BookVolumes.startPage(volume: 1, labels: labels, savedPage: 5) == nil)
        #expect(BookVolumes.startPage(volume: 2, labels: labels, savedPage: 5) == 7)
        #expect(BookVolumes.startPage(volume: 0, labels: labels, savedPage: nil) == 1)
        #expect(BookVolumes.startPage(volume: 3, labels: labels, savedPage: nil) == nil)
    }

    @Test func volumesAreNamedInWords() {
        #expect(BookVolumes.name(1) == "الجزء الثاني")
        #expect(BookVolumes.name(10) == "الجزء الحادي عشر")
        #expect(BookVolumes.name(20) == nil)
    }
}
