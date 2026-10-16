// swift-tools-version: 6.2
import PackageDescription

// M5 money engine: pure Swift value types, Int minor units, no SwiftData (CLAUDE.md engines rule).
let package = Package(
    name: "MadarMoney",
    platforms: [.iOS(.v26), .macOS(.v26)],
    products: [.library(name: "MadarMoney", targets: ["MadarMoney"])],
    targets: [
        .target(name: "MadarMoney"),
        .testTarget(name: "MadarMoneyTests", dependencies: ["MadarMoney"])
    ],
    swiftLanguageModes: [.v6]
)
