import XCTest
import SwiftUI
@testable import Madar

@MainActor final class LaunchAppearanceTests: XCTestCase {
    /// The loading state has no canonical; retain default-size visual evidence for both system appearances.
    func testLaunchPlaceholderRendersBothSystemAppearances() throws {
        for (name, scheme) in [("light", ColorScheme.light), ("dark", ColorScheme.dark)] {
            let renderer = ImageRenderer(content: MadarLaunchPlaceholder()
                .environment(\.colorScheme, scheme)
                .environment(\.layoutDirection, .rightToLeft)
                .environment(\.dynamicTypeSize, .large)
                .frame(width: 430, height: 932))
            renderer.scale = 2
            let rendered = try XCTUnwrap(renderer.uiImage)
            let attachment = XCTAttachment(image: rendered)
            attachment.name = "OWNER-launch-\(name)-L"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
    }
}
