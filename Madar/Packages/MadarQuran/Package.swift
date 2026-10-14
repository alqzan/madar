// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "MadarQuran",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "MadarQuran", targets: ["MadarQuran"])],
    dependencies: [.package(path: "../MadarCore")],
    targets: [
        .target(name: "MadarQuran", dependencies: ["MadarCore"], resources: [
            .copy("Resources/UthmanicHafs_v2-0"),
            .copy("Resources/Quran1439"),
            .copy("Resources/Mushaf1405"),
            .copy("Resources/QuranResourceManifest.json"),
        ]),
        .testTarget(name: "MadarQuranTests", dependencies: ["MadarQuran", "MadarCore"]),
    ],
    swiftLanguageModes: [.v6]
)
