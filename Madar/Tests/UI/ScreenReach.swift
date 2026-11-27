import XCTest

/// iOS 27 lists a full-screen «شريط الأدوات» in the accessibility tree, so XCUITest reports visible rows as not
/// hittable although a finger reaches them (checklist row 26). Tests check the frame is on screen and tap its centre,
/// then still assert what the tap did.
extension XCUIElement {
    func isOnScreen(in app: XCUIApplication) -> Bool {
        exists && !frame.isEmpty && frame.minY > 50 && frame.maxY < app.frame.maxY - 34
    }
    func tapCentre() { coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap() }
    func pressCentre(forDuration duration: TimeInterval) { coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).press(forDuration: duration) }
}
