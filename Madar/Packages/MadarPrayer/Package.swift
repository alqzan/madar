// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MadarPrayer", platforms: [.iOS(.v26), .macOS(.v26)], products: [.library(name: "MadarPrayer", targets: ["MadarPrayer"])], dependencies: [.package(path: "../MadarCore"), .package(path: "../MadarData")], targets: [.target(name: "MadarPrayer", dependencies: ["MadarCore", "MadarData"]), .testTarget(name: "MadarPrayerTests", dependencies: ["MadarPrayer"])], swiftLanguageModes: [.v6])
