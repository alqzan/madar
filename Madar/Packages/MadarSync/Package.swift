// swift-tools-version: 6.2
import PackageDescription
let package = Package(name: "MadarSync", platforms: [.iOS("27.0"), .macOS("27.0")], products: [.library(name: "MadarSync", targets: ["MadarSync"])], dependencies: [.package(path: "../MadarData")], targets: [.target(name: "MadarSync", dependencies: ["MadarData"]), .testTarget(name: "MadarSyncTests", dependencies: ["MadarSync", "MadarData"])], swiftLanguageModes: [.v6])
